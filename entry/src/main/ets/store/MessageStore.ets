import { TdClient } from '../tdkit/TdClient';
import { TdObject, TdRequest, TdError } from '../tdkit/TdTypes';
import { UserStore } from './UserStore';
import { MessageEntry, cloneMessage, buildMessageEntry, commentInfoFromInteraction, CommentInfo, reactionsFromInteraction, ReactionInfo, parseInlineKeyboard } from './MessageEntry';
import { formatUserStatus } from '../util/formatUserStatus';
import { formatPreview } from '../util/formatPreview';
import { formatMemberCount } from '../util/formatMemberCount';

const PAGE: number = 30;
const PHOTO_PRIORITY: number = 1;
// Re-request a still-missing thumbnail at most this often (stalled downloads
// whose bounded retries were exhausted by a transient network failure).
const THUMB_REKICK_MS: number = 8000;

type MsgListener = (msgs: MessageEntry[]) => void;
type SubtitleListener = (s: string) => void;

export class MessageStore {
  private client: TdClient;
  private users: UserStore;
  private chatId: number;
  private messages: MessageEntry[] = [];
  private oldestId: number = 0;
  private subtitle: string = '';
  private pinnedPreview: string = '';
  private pinnedIds: number[] = [];
  private pinnedPreviews: string[] = [];
  private msgSubs: MsgListener[] = [];
  private subSubs: SubtitleListener[] = [];
  private pinnedSubs: SubtitleListener[] = [];
  private unsubs: Array<() => void> = [];
  private fileToMsg: Map<number, number> = new Map();
  private linkFileToMsg: Map<number, number> = new Map();
  private fullPhotoFileToMsg: Map<number, number> = new Map();
  private videoFileToMsg: Map<number, number> = new Map();
  private stickerFileToMsg: Map<number, number> = new Map();
  private thumbLastKick: Map<number, number> = new Map();
  private peerUserId: number = 0;
  private groupId: number = 0;
  private lastReadInboxId: number = 0;
  private lastReadOutboxId: number = 0;
  private unreadCount: number = 0;
  private viewedUpTo: number = 0;
  private chatResolved: boolean = false;
  private historyPending: boolean = false;
  private isGroupFlag: boolean = false;
  private isChannel: boolean = false;
  private chatPhotoFileId: number = 0;
  private chatPhotoPath: string = '';
  private headerAvatarSubs: SubtitleListener[] = [];
  private chatTitle: string = '';
  private headerTitleSubs: SubtitleListener[] = [];
  private senderAvatarPaths: Map<string, string> = new Map();
  private senderRequested: Set<string> = new Set();
  private avatarFileToSender: Map<number, string> = new Map();
  private forwardTitleCache: Map<number, string> = new Map();
  private forwardTitleRequested: Set<number> = new Set();
  private thumbAttempts: Map<number, number> = new Map();
  private replierAvatarPaths: Map<number, string> = new Map();
  private replierAvatarRequested: Set<number> = new Set();
  private avatarFileToReplier: Map<number, number> = new Map();
  private requestedAroundMessageId: number = 0;
  private initialLoadStarted: boolean = false;
  private olderPending: boolean = false;
  private newerPending: boolean = false;
  private hasMoreNewer: boolean = false;
  private memberCount: number = 0;
  private onlineCount: number = 0;

  constructor(client: TdClient, users: UserStore, chatId: number) {
    this.client = client;
    this.users = users;
    this.chatId = chatId;
  }

  open(aroundMessageId?: number): void {
    this.sendSimple('openChat');
    this.unsubs.push(this.client.onUpdate('updateNewMessage', (u: TdObject) => this.onNewMessage(u)));
    this.unsubs.push(this.client.onUpdate('updateMessageSendSucceeded', (u: TdObject) => this.onSendSucceeded(u)));
    this.unsubs.push(this.client.onUpdate('updateMessageSendFailed', (u: TdObject) => this.onSendFailed(u)));
    this.unsubs.push(this.client.onUpdate('updateMessageContent', (u: TdObject) => this.onContent(u)));
    this.unsubs.push(this.client.onUpdate('updateDeleteMessages', (u: TdObject) => this.onDelete(u)));
    this.unsubs.push(this.client.onUpdate('updateChatReadOutbox', (u: TdObject) => this.onReadOutbox(u)));
    this.unsubs.push(this.client.onUpdate('updateFile', (u: TdObject) => this.onFile(u)));
    this.unsubs.push(this.client.onUpdate('updateUserStatus', (u: TdObject) => this.onUserStatus(u)));
    this.unsubs.push(this.client.onUpdate('updateBasicGroup', (u: TdObject) => this.onGroup(u)));
    this.unsubs.push(this.client.onUpdate('updateSupergroup', (u: TdObject) => this.onGroup(u)));
    this.unsubs.push(this.client.onUpdate('updateUser', () => { this.resolveSenderAvatars(); this.resolveCommentAvatars(); }));
    this.unsubs.push(this.client.onUpdate('updateMessageInteractionInfo', (u: TdObject) => this.onInteractionInfo(u)));
    this.unsubs.push(this.client.onUpdate('updateChatOnlineMemberCount', (u: TdObject) => this.onOnlineCount(u)));
    // A message got (un)pinned while the chat is open — re-resolve the pinned
    // list so the banner reflects the new pin without re-entering the chat.
    this.unsubs.push(this.client.onUpdate('updateMessageIsPinned', (u: TdObject) => {
      if ((u['chat_id'] as number | undefined) === this.chatId) {
        this.resolvePinned();
      }
    }));
    this.unsubs.push(this.client.onUpdate('updateMessageEdited', (u: TdObject) => this.onEdited(u)));
    this.requestedAroundMessageId = aroundMessageId !== undefined ? aroundMessageId : 0;
    this.resolveChat();
    this.resolvePinned();
  }

  close(): void {
    this.sendSimple('closeChat');
    for (const un of this.unsubs) {
      un();
    }
    this.unsubs = [];
  }

  getMessages(): MessageEntry[] {
    return this.messages;
  }

  getSubtitle(): string {
    return this.subtitle;
  }

  // Chat unread count snapshot captured at open time (for the scroll-to-bottom badge).
  getUnreadCount(): number {
    return this.unreadCount;
  }

  // True for basic groups / supergroups / channels — drives per-message avatars + sender names.
  getIsGroup(): boolean {
    return this.isGroupFlag;
  }

  // True only for broadcast channels — reply_info.reply_count is a generic
  // Peer user id for private chats (0 for groups/channels) — used to open the
  // user profile page from the chat header.
  getPeerUserId(): number {
    return this.peerUserId;
  }

  // "times replied" counter shared with ordinary in-chat reply threads, so the
  // "N Comments" chip must only render for real channel posts.
  getIsChannel(): boolean {
    return this.isChannel;
  }

  // Id of the first unread message captured at open time (0 = none / all read).
  // Used by the page to position the initial scroll at the unread boundary.
  getFirstUnreadId(): number {
    if (this.unreadCount <= 0 || this.lastReadInboxId <= 0) {
      return 0;
    }
    for (const m of this.messages) {
      if (m.id > this.lastReadInboxId) {
        return m.id;
      }
    }
    return 0;
  }

  subscribe(l: MsgListener): () => void {
    this.msgSubs = [...this.msgSubs, l];
    l(this.messages);
    return (): void => { this.msgSubs = this.msgSubs.filter((x: MsgListener) => x !== l); };
  }

  subscribeSubtitle(l: SubtitleListener): () => void {
    this.subSubs = [...this.subSubs, l];
    l(this.subtitle);
    return (): void => { this.subSubs = this.subSubs.filter((x: SubtitleListener) => x !== l); };
  }

  subscribePinned(l: SubtitleListener): () => void {
    this.pinnedSubs = [...this.pinnedSubs, l];
    l(this.pinnedPreview);
    return (): void => { this.pinnedSubs = this.pinnedSubs.filter((x: SubtitleListener) => x !== l); };
  }

  // Header avatar path, resolved from the chat photo. Authoritative for the chat
  // page header (works even for channels/chats not present in the loaded lists).
  subscribeHeaderAvatar(l: SubtitleListener): () => void {
    this.headerAvatarSubs = [...this.headerAvatarSubs, l];
    l(this.chatPhotoPath);
    return (): void => { this.headerAvatarSubs = this.headerAvatarSubs.filter((x: SubtitleListener) => x !== l); };
  }

  // Chat title resolved from getChat — a fallback header title/initials for chats
  // opened by t.me link that aren't in ChatStore's cache yet.
  subscribeHeaderTitle(l: SubtitleListener): () => void {
    this.headerTitleSubs = [...this.headerTitleSubs, l];
    l(this.chatTitle);
    return (): void => { this.headerTitleSubs = this.headerTitleSubs.filter((x: SubtitleListener) => x !== l); };
  }

  private notifyHeaderTitle(): void {
    for (const l of this.headerTitleSubs) {
      l(this.chatTitle);
    }
  }

  private notifyHeaderAvatar(): void {
    for (const l of this.headerAvatarSubs) {
      l(this.chatPhotoPath);
    }
  }

  // Load the previous (older) page. Guarded so scroll-driven prefetch can call
  // this repeatedly without stacking duplicate in-flight requests.
  loadOlder(): void {
    if (this.olderPending || this.oldestId === 0) {
      return;
    }
    this.olderPending = true;
    const req: TdRequest = { '@type': 'getChatHistory' };
    req['chat_id'] = this.chatId;
    req['from_message_id'] = this.oldestId;
    req['offset'] = 0;
    req['limit'] = PAGE;
    req['only_local'] = false;
    this.client.send(req).then((res: TdObject) => {
      this.olderPending = false;
      this.onHistory(res);
    }).catch((e: TdError) => {
      this.olderPending = false;
      if ((e as TdError).code !== 404) {
        console.error(`MessageStore.loadOlder failed: ${e.message}`);
      }
    });
  }

  // True while unloaded newer pages exist below the loaded window (i.e. we
  // jumped into the middle of history and haven't reached the live tail).
  getHasMoreNewer(): boolean {
    return this.hasMoreNewer;
  }

  // Jump straight to the newest messages: drop the loaded window and reload
  // the latest page. Used by the scroll-to-bottom button when thousands of
  // unloaded messages separate the user from the tail — scrolling (and
  // page-by-page prefetching) through them would crawl.
  jumpToLatest(): void {
    this.hasMoreNewer = false;
    this.newerPending = false;
    this.olderPending = false;
    this.messages = [];
    this.oldestId = 0;
    this.loadHistory(0);
  }

  // Load the next (newer) page — only meaningful after a loadAround jump into
  // the middle of history left unloaded messages below the window.
  loadNewer(): void {
    if (this.newerPending || !this.hasMoreNewer || this.messages.length === 0) {
      return;
    }
    const newestId = this.messages[this.messages.length - 1].id;
    this.newerPending = true;
    const req: TdRequest = { '@type': 'getChatHistory' };
    req['chat_id'] = this.chatId;
    req['from_message_id'] = newestId;
    req['offset'] = -(PAGE - 1);
    req['limit'] = PAGE;
    req['only_local'] = false;
    this.client.send(req).then((res: TdObject) => {
      this.newerPending = false;
      const arr = (res['messages'] as TdObject[] | undefined) ?? [];
      let maxId = 0;
      for (const m of arr) {
        const id = (m['id'] as number | undefined) ?? 0;
        if (id > maxId) {
          maxId = id;
        }
      }
      if (maxId <= newestId) {
        this.hasMoreNewer = false; // nothing newer came back — we've reached the live tail
      }
      this.onHistory(res);
    }).catch((e: TdError) => {
      this.newerPending = false;
      if ((e as TdError).code !== 404) {
        console.error(`MessageStore.loadNewer failed: ${e.message}`);
      }
    });
  }

  send(text: string, replyToId: number = 0): void {
    const ft: TdObject = { '@type': 'formattedText' };
    ft['text'] = text;
    const content: TdObject = { '@type': 'inputMessageText' };
    content['text'] = ft;
    const req: TdRequest = { '@type': 'sendMessage' };
    req['chat_id'] = this.chatId;
    if (replyToId !== 0) {
      const rt: TdObject = { '@type': 'inputMessageReplyToMessage' };
      rt['message_id'] = replyToId;
      req['reply_to'] = rt;
    }
    req['input_message_content'] = content;
    this.client.send(req).then((m: TdObject) => {
      this.upsert(buildMessageEntry(m, this.users));
      this.resolveReplies();
      this.notify();
    }).catch((e: TdError) => {
      console.error(`MessageStore.send failed: ${e.message}`);
    });
  }

  // Toggle an emoji reaction on a message. TDLib pushes the updated counts back
  // via updateMessageInteractionInfo, which onInteraction() already applies.
  setReaction(messageId: number, emoji: string, isChosen: boolean): void {
    const rt: TdObject = { '@type': 'reactionTypeEmoji' };
    rt['emoji'] = emoji;
    if (isChosen) {
      const req: TdRequest = { '@type': 'removeMessageReaction' };
      req['chat_id'] = this.chatId;
      req['message_id'] = messageId;
      req['reaction_type'] = rt;
      this.client.send(req).catch((e: TdError) => {
        console.error(`MessageStore.removeMessageReaction failed: ${e.message}`);
      });
    } else {
      const req: TdRequest = { '@type': 'addMessageReaction' };
      req['chat_id'] = this.chatId;
      req['message_id'] = messageId;
      req['reaction_type'] = rt;
      req['is_big'] = false;
      req['update_recent_reactions'] = true;
      this.client.send(req).catch((e: TdError) => {
        console.error(`MessageStore.addMessageReaction failed: ${e.message}`);
      });
    }
  }

  // Resolve a public/private t.me link for a message (used by 拷贝消息链接).
  messageLink(messageId: number, cb: (url: string) => void): void {
    const req: TdRequest = { '@type': 'getMessageLink' };
    req['chat_id'] = this.chatId;
    req['message_id'] = messageId;
    this.client.send(req).then((res: TdObject) => {
      cb((res['link'] as string | undefined) ?? '');
    }).catch((e: TdError) => {
      console.error(`MessageStore.getMessageLink failed: ${e.message}`);
      cb('');
    });
  }

  // Send a document from a local (sandbox) path. TDLib uploads it and the
  // pending message arrives via the normal update flow.
  sendDocument(path: string, caption: string): void {
    const inputFile: TdObject = { '@type': 'inputFileLocal' };
    inputFile['path'] = path;
    const content: TdObject = { '@type': 'inputMessageDocument' };
    content['document'] = inputFile;
    if (caption !== '') {
      const ft: TdObject = { '@type': 'formattedText' };
      ft['text'] = caption;
      content['caption'] = ft;
    }
    const req: TdRequest = { '@type': 'sendMessage' };
    req['chat_id'] = this.chatId;
    req['input_message_content'] = content;
    this.client.send(req).then((m: TdObject) => {
      this.upsert(buildMessageEntry(m, this.users));
      this.notify();
    }).catch((e: TdError) => {
      console.error(`MessageStore.sendDocument failed: ${e.message}`);
    });
  }

  // Shared sendMessage plumbing for media content types.
  private sendContent(content: TdObject, tag: string): void {
    const req: TdRequest = { '@type': 'sendMessage' };
    req['chat_id'] = this.chatId;
    req['input_message_content'] = content;
    this.client.send(req).then((m: TdObject) => {
      this.upsert(buildMessageEntry(m, this.users));
      this.notify();
    }).catch((e: TdError) => {
      console.error(`MessageStore.${tag} failed: ${e.message}`);
    });
  }

  sendPhoto(path: string, caption: string): void {
    const inputFile: TdObject = { '@type': 'inputFileLocal' };
    inputFile['path'] = path;
    const content: TdObject = { '@type': 'inputMessagePhoto' };
    content['photo'] = inputFile;
    if (caption !== '') {
      const ft: TdObject = { '@type': 'formattedText' };
      ft['text'] = caption;
      content['caption'] = ft;
    }
    this.sendContent(content, 'sendPhoto');
  }

  sendVideo(path: string, caption: string): void {
    const inputFile: TdObject = { '@type': 'inputFileLocal' };
    inputFile['path'] = path;
    const content: TdObject = { '@type': 'inputMessageVideo' };
    content['video'] = inputFile;
    if (caption !== '') {
      const ft: TdObject = { '@type': 'formattedText' };
      ft['text'] = caption;
      content['caption'] = ft;
    }
    this.sendContent(content, 'sendVideo');
  }

  // Send a sticker the user picked from an installed set (already on Telegram
  // servers — reference it by TDLib file id).
  sendSticker(fileId: number, width: number, height: number): void {
    const inputFile: TdObject = { '@type': 'inputFileId' };
    inputFile['id'] = fileId;
    const content: TdObject = { '@type': 'inputMessageSticker' };
    content['sticker'] = inputFile;
    content['width'] = width;
    content['height'] = height;
    this.sendContent(content, 'sendSticker');
  }

  // Send a saved GIF (server-side file, referenced by id).
  sendAnimation(fileId: number, width: number, height: number, durationSec: number): void {
    const inputFile: TdObject = { '@type': 'inputFileId' };
    inputFile['id'] = fileId;
    const content: TdObject = { '@type': 'inputMessageAnimation' };
    content['animation'] = inputFile;
    content['width'] = width;
    content['height'] = height;
    content['duration'] = durationSec;
    this.sendContent(content, 'sendAnimation');
  }

  sendVoiceNote(path: string, durationSec: number): void {
    const inputFile: TdObject = { '@type': 'inputFileLocal' };
    inputFile['path'] = path;
    const content: TdObject = { '@type': 'inputMessageVoiceNote' };
    content['voice_note'] = inputFile;
    content['duration'] = durationSec;
    this.sendContent(content, 'sendVoiceNote');
  }

  private sendSimple(type: string): void {
    const req: TdRequest = { '@type': type };
    req['chat_id'] = this.chatId;
    this.client.send(req).catch((e: TdError) => {
      console.error(`MessageStore.${type} failed: ${e.message}`);
    });
  }

  private loadHistory(fromId: number): void {
    const req: TdRequest = { '@type': 'getChatHistory' };
    req['chat_id'] = this.chatId;
    req['from_message_id'] = fromId;
    req['offset'] = 0;
    req['limit'] = PAGE;
    req['only_local'] = false;
    this.client.send(req).then((res: TdObject) => this.onHistory(res)).catch((e: TdError) => {
      const code = (e as TdError).code;
      if (code !== 404) {
        console.error(`MessageStore.getChatHistory failed: ${e.message}`);
      }
    });
  }

  private onHistory(res: TdObject): void {
    const arr = (res['messages'] as TdObject[] | undefined) ?? [];
    for (const m of arr) {
      this.upsert(buildMessageEntry(m, this.users));
    }
    if (this.messages.length > 0) {
      this.oldestId = this.messages[0].id;
    }
    this.resolveReplies();
    this.resolveForwardTitles();
    this.requestPhotos();
    this.resolveSenderAvatars();
    this.resolveCommentAvatars();
    // NOTE: do NOT mark messages read here. Read state is a high-water mark in
    // TDLib, so viewing the newest loaded message would mark ALL older ones read.
    // Read-marking is driven by the actually-visible range (see markViewed).
    // Hold the very first render until getChat supplies the unread anchor, so the
    // page can position at the first unread message without a race. Later loads
    // (loadOlder) notify normally.
    if (this.chatResolved) {
      this.notify();
    } else {
      this.historyPending = true;
    }
  }

  private flushInitial(): void {
    this.chatResolved = true;
    if (this.historyPending) {
      this.historyPending = false;
      this.notify();
    }
  }

  private onNewMessage(u: TdObject): void {
    const m = u['message'] as TdObject | undefined;
    if (m === undefined || (m['chat_id'] as number | undefined) !== this.chatId) {
      return;
    }
    this.upsert(buildMessageEntry(m, this.users));
    this.resolveReplies();
    this.resolveForwardTitles();
    this.requestPhotos();
    this.resolveSenderAvatars();
    this.resolveCommentAvatars();
    // New incoming messages are marked read only when they become visible
    // (driven by markViewed from the page), not on arrival.
    this.notify();
  }

  private onSendSucceeded(u: TdObject): void {
    const oldId = u['old_message_id'] as number | undefined;
    const m = u['message'] as TdObject | undefined;
    if (oldId === undefined || m === undefined) {
      return;
    }
    this.messages = this.messages.filter((e: MessageEntry) => e.id !== oldId);
    this.upsert(buildMessageEntry(m, this.users));
    this.resolveReplies();
    this.notify();
  }

  private onSendFailed(u: TdObject): void {
    const m = u['message'] as TdObject | undefined;
    if (m === undefined) {
      return;
    }
    const id = m['id'] as number;
    this.patch(id, (c: MessageEntry) => { c.sendState = 'failed'; });
  }

  private onContent(u: TdObject): void {
    if ((u['chat_id'] as number | undefined) !== this.chatId) {
      return;
    }
    const id = u['message_id'] as number | undefined;
    if (id === undefined) {
      return;
    }
    const idx = this.indexOf(id);
    if (idx < 0) {
      return;
    }
    // rebuild content by wrapping the new content into a message-like object
    const fake: TdObject = { '@type': 'message' };
    fake['content'] = u['new_content'];
    const rebuilt = buildMessageEntry(fake, this.users);
    this.patch(id, (c: MessageEntry) => {
      c.contentType = rebuilt.contentType;
      c.text = rebuilt.text;
      c.photoFileId = rebuilt.photoFileId;
      c.photoWidth = rebuilt.photoWidth;
      c.photoHeight = rebuilt.photoHeight;
      c.placeholderLabel = rebuilt.placeholderLabel;
      c.photoPath = '';
      c.photoProgress = 0;
      c.linkSiteName = rebuilt.linkSiteName;
      c.linkTitle = rebuilt.linkTitle;
      c.linkDescription = rebuilt.linkDescription;
      c.linkDescriptionEntities = rebuilt.linkDescriptionEntities;
      c.linkPhotoFileId = rebuilt.linkPhotoFileId;
      c.linkPhotoPath = '';
      c.linkUrl = rebuilt.linkUrl;
      c.photoFullFileId = rebuilt.photoFullFileId;
      c.photoFullPath = '';
      c.photoFullProgress = 0;
      c.videoFileId = rebuilt.videoFileId;
      c.videoFileSize = rebuilt.videoFileSize;
      c.videoMimeType = rebuilt.videoMimeType;
      c.videoFileName = rebuilt.videoFileName;
      c.videoDuration = rebuilt.videoDuration;
      c.videoPath = '';
      c.videoProgress = 0;
    });
    this.requestPhotos();
  }

  private onDelete(u: TdObject): void {
    if ((u['chat_id'] as number | undefined) !== this.chatId) {
      return;
    }
    const removeIds = (u['message_ids'] as number[] | undefined) ?? [];
    const set = new Set<number>(removeIds);
    this.messages = this.messages.filter((e: MessageEntry) => !set.has(e.id));
    this.notify();
  }

  // Bots edit a message's inline keyboard in response to button presses —
  // updateMessageEdited carries the fresh reply_markup.
  private onEdited(u: TdObject): void {
    if ((u['chat_id'] as number | undefined) !== this.chatId) {
      return;
    }
    const id = u['message_id'] as number | undefined;
    if (id === undefined) {
      return;
    }
    const buttons = parseInlineKeyboard(u['reply_markup'] as TdObject | undefined);
    this.patch(id, (c: MessageEntry) => { c.inlineButtons = buttons; });
  }

  private onInteractionInfo(u: TdObject): void {
    if ((u['chat_id'] as number | undefined) !== this.chatId) {
      return;
    }
    const id = u['message_id'] as number | undefined;
    if (id === undefined) {
      return;
    }
    const ii = u['interaction_info'] as TdObject | undefined;
    const cmt: CommentInfo = commentInfoFromInteraction(ii);
    const rx: ReactionInfo[] = reactionsFromInteraction(ii);
    this.patch(id, (c: MessageEntry) => {
      c.commentCount = cmt.count;
      c.commentReplierIds = cmt.replierIds;
      c.commentReplierAvatarPaths = [];
      c.reactions = rx;
    });
    this.resolveCommentAvatars();
  }

  private onReadOutbox(u: TdObject): void {
    if ((u['chat_id'] as number | undefined) !== this.chatId) {
      return;
    }
    this.lastReadOutboxId = (u['last_read_outbox_message_id'] as number | undefined) ?? 0;
    this.notify(); // notify() applies the read marking centrally
  }

  // Outgoing messages at or below the outbox-read boundary become 'read'.
  // Applied on every notify so history pages (already read long ago) get
  // marked too, not only live updateChatReadOutbox events.
  private applyReadOutbox(): void {
    if (this.lastReadOutboxId <= 0) {
      return;
    }
    let changed = false;
    const mapped = this.messages.map((e: MessageEntry) => {
      if (e.isOutgoing && e.sendState === 'sent' && e.id <= this.lastReadOutboxId) {
        const c = cloneMessage(e);
        c.sendState = 'read';
        changed = true;
        return c;
      }
      return e;
    });
    if (changed) {
      this.messages = mapped;
    }
  }

  // --- photos ---
  // Download an inline thumbnail with up to 2 automatic retries (backoff),
  // so a transient failure doesn't leave the bubble stuck at 0% forever.
  private downloadThumb(fileId: number): void {
    const attempt = (this.thumbAttempts.get(fileId) ?? 0) + 1;
    this.thumbAttempts.set(fileId, attempt);
    const req: TdRequest = { '@type': 'downloadFile' };
    req['file_id'] = fileId;
    req['priority'] = PHOTO_PRIORITY;
    this.client.send(req).then((f: TdObject) => this.applyFile(f)).catch((err: TdError) => {
      console.error(`MessageStore photo ${fileId} (attempt ${attempt}): ${err.message}`);
      if (attempt <= 2) {
        setTimeout(() => this.downloadThumb(fileId), 1000 * attempt);
      }
    });
  }

  private requestPhotos(): void {
    for (const e of this.messages) {
      if ((e.contentType === 'photo' || e.contentType === 'video' || e.contentType === 'sticker')
        && e.photoFileId !== 0 && e.photoPath === '') {
        if (!this.fileToMsg.has(e.photoFileId)) {
          this.fileToMsg.set(e.photoFileId, e.id);
          this.downloadThumb(e.photoFileId);
        } else {
          // Already requested but still no local file: a download that burned
          // its retries (transient network failure at load time) would sit at
          // 0% forever — re-kick it, rate-limited. downloadFile is idempotent.
          const now = Date.now();
          const lastKick = this.thumbLastKick.get(e.photoFileId) ?? 0;
          if (now - lastKick > THUMB_REKICK_MS) {
            this.thumbLastKick.set(e.photoFileId, now);
            this.downloadThumb(e.photoFileId);
          }
        }
      }
      // Voice notes are small — download eagerly so tapping plays instantly.
      if (e.contentType === 'voice' && e.videoFileId !== 0 && e.videoPath === '') {
        this.requestVideoDownload(e.id); // deduped via videoFileToMsg
      }
      // Animated (TGS) sticker source file — small (<64KB), download eagerly so
      // the Lottie animation starts as soon as the message is visible.
      if (e.contentType === 'sticker' && e.stickerFileId !== 0 && e.stickerPath === '') {
        if (!this.stickerFileToMsg.has(e.stickerFileId)) {
          this.stickerFileToMsg.set(e.stickerFileId, e.id);
          const req: TdRequest = { '@type': 'downloadFile' };
          req['file_id'] = e.stickerFileId;
          req['priority'] = PHOTO_PRIORITY;
          this.client.send(req).then((f: TdObject) => this.applyFile(f)).catch((err: TdError) => {
            console.error(`MessageStore sticker ${e.stickerFileId}: ${err.message}`);
          });
        }
      }
      if (e.linkPhotoFileId !== 0 && e.linkPhotoPath === '') {
        if (!this.linkFileToMsg.has(e.linkPhotoFileId)) {
          this.linkFileToMsg.set(e.linkPhotoFileId, e.id);
          const req: TdRequest = { '@type': 'downloadFile' };
          req['file_id'] = e.linkPhotoFileId;
          req['priority'] = PHOTO_PRIORITY;
          this.client.send(req).then((f: TdObject) => this.applyFile(f)).catch((err: TdError) => {
            console.error(`MessageStore link photo ${e.linkPhotoFileId}: ${err.message}`);
          });
        }
      }
    }
  }

  // On-demand full-resolution photo download (triggered by opening the fullscreen
  // viewer). The inline bubble only ever downloads photoFileId (a small size).
  requestFullPhoto(messageId: number): void {
    const idx = this.indexOf(messageId);
    if (idx < 0) {
      return;
    }
    const e = this.messages[idx];
    if (e.photoFullFileId === 0 || e.photoFullPath !== '' || this.fullPhotoFileToMsg.has(e.photoFullFileId)) {
      return;
    }
    this.fullPhotoFileToMsg.set(e.photoFullFileId, messageId);
    const req: TdRequest = { '@type': 'downloadFile' };
    req['file_id'] = e.photoFullFileId;
    req['priority'] = PHOTO_PRIORITY;
    this.client.send(req).then((f: TdObject) => this.applyFile(f)).catch((err: TdError) => {
      console.error(`MessageStore full photo ${e.photoFullFileId}: ${err.message}`);
    });
  }

  // On-demand full video download (triggered by tapping to play). The inline
  // bubble only ever downloads the thumbnail (photoFileId).
  requestVideoDownload(messageId: number): void {
    const idx = this.indexOf(messageId);
    if (idx < 0) {
      return;
    }
    const e = this.messages[idx];
    if (e.videoFileId === 0 || e.videoPath !== '' || this.videoFileToMsg.has(e.videoFileId)) {
      return;
    }
    this.videoFileToMsg.set(e.videoFileId, messageId);
    const req: TdRequest = { '@type': 'downloadFile' };
    req['file_id'] = e.videoFileId;
    req['priority'] = PHOTO_PRIORITY;
    this.client.send(req).then((f: TdObject) => this.applyFile(f)).catch((err: TdError) => {
      console.error(`MessageStore video ${e.videoFileId}: ${err.message}`);
    });
  }

  private onFile(u: TdObject): void {
    const f = u['file'] as TdObject | undefined;
    if (f !== undefined) {
      this.applyFile(f);
    }
  }

  private downloadPercent(file: TdObject, local: TdObject): number {
    const size = ((file['size'] as number | undefined) ?? 0) || ((file['expected_size'] as number | undefined) ?? 0);
    const downloaded = (local['downloaded_size'] as number | undefined) ?? 0;
    return size > 0 ? Math.min(100, Math.floor((downloaded / size) * 100)) : 0;
  }

  private applyFile(file: TdObject): void {
    const id = file['id'] as number | undefined;
    if (id === undefined) {
      return;
    }
    const local = file['local'] as TdObject | undefined;
    if (local === undefined) {
      return;
    }
    const done = (local['is_downloading_completed'] as boolean | undefined) ?? false;
    const path = (local['path'] as string | undefined) ?? '';

    // Animated sticker source (TGS): path on completion (no progress UI needed).
    const stickerMsgId = this.stickerFileToMsg.get(id);
    if (stickerMsgId !== undefined && done && path !== '') {
      this.patch(stickerMsgId, (c: MessageEntry) => { c.stickerPath = path; });
      return;
    }

    // Full-resolution photo / full video: progress while downloading, path on completion.
    const fullMsgId = this.fullPhotoFileToMsg.get(id);
    if (fullMsgId !== undefined) {
      const percent = this.downloadPercent(file, local);
      this.patch(fullMsgId, (c: MessageEntry) => {
        if (done && path !== '') {
          c.photoFullPath = path;
          // Backfill: if the inline thumbnail download failed/stalled, the
          // full-resolution image serves as the bubble thumbnail too.
          if (c.photoPath === '') {
            c.photoPath = path;
          }
        }
        c.photoFullProgress = percent;
      });
      return;
    }
    const videoMsgId = this.videoFileToMsg.get(id);
    if (videoMsgId !== undefined) {
      const percent = this.downloadPercent(file, local);
      this.patch(videoMsgId, (c: MessageEntry) => {
        if (done && path !== '') {
          c.videoPath = path;
        }
        c.videoProgress = percent;
      });
      return;
    }
    // Inline thumbnail: progress while downloading, path on completion (drives
    // the in-bubble loading ring).
    const thumbMsgId = this.fileToMsg.get(id);
    if (thumbMsgId !== undefined) {
      const percent = this.downloadPercent(file, local);
      this.patch(thumbMsgId, (c: MessageEntry) => {
        if (done && path !== '') {
          c.photoPath = path;
        }
        c.photoProgress = percent;
      });
      return;
    }

    if (!done || path === '') {
      return;
    }
    // The chat photo drives the header avatar (may also be a message sender's avatar
    // when the channel posts as itself — fall through so both get updated).
    if (id === this.chatPhotoFileId && this.chatPhotoPath !== path) {
      this.chatPhotoPath = path;
      this.notifyHeaderAvatar();
    }
    const senderKey = this.avatarFileToSender.get(id);
    if (senderKey !== undefined) {
      this.senderAvatarPaths.set(senderKey, path);
      this.applySenderPath(senderKey, path);
      return;
    }
    const replierUid = this.avatarFileToReplier.get(id);
    if (replierUid !== undefined) {
      this.replierAvatarPaths.set(replierUid, path);
      this.applyReplierAvatar(replierUid, path);
      return;
    }
    const linkMsgId = this.linkFileToMsg.get(id);
    if (linkMsgId !== undefined) {
      this.patch(linkMsgId, (c: MessageEntry) => { c.linkPhotoPath = path; });
    }
  }

  // Download the chat photo for the header avatar (independent of the chat lists,
  // so channels opened from a folder still get their header avatar).
  private downloadChatPhoto(): void {
    if (this.chatPhotoFileId <= 0) {
      return;
    }
    const req: TdRequest = { '@type': 'downloadFile' };
    req['file_id'] = this.chatPhotoFileId;
    req['priority'] = PHOTO_PRIORITY;
    this.client.send(req).then((f: TdObject) => this.applyFile(f)).catch((err: TdError) => {
      console.error(`MessageStore chatPhoto ${this.chatPhotoFileId}: ${err.message}`);
    });
  }

  // --- sender avatars (group/channel per-message avatars) ---
  private senderKey(senderId: number, isUser: boolean): string {
    return `${isUser ? 'u' : 'c'}${senderId}`;
  }

  private resolveSenderAvatars(): void {
    const seen = new Set<string>();
    for (const e of this.messages) {
      if (e.isOutgoing || e.senderId === 0) {
        continue;
      }
      const key = this.senderKey(e.senderId, e.senderIsUser);
      if (seen.has(key)) {
        continue;
      }
      seen.add(key);
      const known = this.senderAvatarPaths.get(key);
      if (known !== undefined && known !== '') {
        this.applySenderPath(key, known);
        continue;
      }
      if (this.senderRequested.has(key)) {
        continue;
      }
      let fileId = 0;
      if (e.senderIsUser) {
        fileId = this.users.photoFileId(e.senderId);
      } else if (e.senderId === this.chatId) {
        fileId = this.chatPhotoFileId;
      }
      if (fileId <= 0) {
        continue; // not known yet — retried on updateUser / getChat
      }
      this.senderRequested.add(key);
      this.avatarFileToSender.set(fileId, key);
      const req: TdRequest = { '@type': 'downloadFile' };
      req['file_id'] = fileId;
      req['priority'] = PHOTO_PRIORITY;
      this.client.send(req).then((f: TdObject) => this.applyFile(f)).catch((err: TdError) => {
        console.error(`MessageStore avatar ${fileId}: ${err.message}`);
      });
    }
  }

  private applySenderPath(key: string, path: string): void {
    let changed = false;
    const next = this.messages.map((e: MessageEntry) => {
      if (!e.isOutgoing && this.senderKey(e.senderId, e.senderIsUser) === key && e.senderAvatarPath !== path) {
        changed = true;
        const c = cloneMessage(e);
        c.senderAvatarPath = path;
        return c;
      }
      return e;
    });
    if (changed) {
      this.messages = next;
      this.notify();
    }
  }

  // --- comment-row avatars (recent commenters shown on a channel post) ---
  private resolveCommentAvatars(): void {
    for (const e of this.messages) {
      for (const uid of e.commentReplierIds) {
        const known = this.replierAvatarPaths.get(uid);
        if (known !== undefined && known !== '') {
          this.applyReplierAvatar(uid, known);
          continue;
        }
        if (this.replierAvatarRequested.has(uid)) {
          continue;
        }
        const fileId = this.users.photoFileId(uid);
        if (fileId <= 0) {
          continue; // not known yet — retried on updateUser
        }
        this.replierAvatarRequested.add(uid);
        this.avatarFileToReplier.set(fileId, uid);
        const req: TdRequest = { '@type': 'downloadFile' };
        req['file_id'] = fileId;
        req['priority'] = PHOTO_PRIORITY;
        this.client.send(req).then((f: TdObject) => this.applyFile(f)).catch((err: TdError) => {
          console.error(`MessageStore replier avatar ${fileId}: ${err.message}`);
        });
      }
    }
  }

  private applyReplierAvatar(userId: number, path: string): void {
    let changed = false;
    const next = this.messages.map((e: MessageEntry) => {
      const idx = e.commentReplierIds.indexOf(userId);
      if (idx < 0 || e.commentReplierAvatarPaths[idx] === path) {
        return e;
      }
      changed = true;
      const c = cloneMessage(e);
      const arr = c.commentReplierAvatarPaths.slice();
      while (arr.length <= idx) {
        arr.push('');
      }
      arr[idx] = path;
      c.commentReplierAvatarPaths = arr;
      return c;
    });
    if (changed) {
      this.messages = next;
      this.notify();
    }
  }

  // --- subtitle ---
  // Newest pinned message → one-line preview shown in the banner under the header.
  private resolvePinned(): void {
    const filter: TdObject = { '@type': 'searchMessagesFilterPinned' };
    const req: TdRequest = { '@type': 'searchChatMessages' };
    req['chat_id'] = this.chatId;
    req['query'] = '';
    req['from_message_id'] = 0;
    req['offset'] = 0;
    req['limit'] = 20;
    req['filter'] = filter;
    this.client.send(req).then((res: TdObject) => {
      const arr = (res['messages'] as TdObject[] | undefined) ?? [];
      const ids: number[] = [];
      const previews: string[] = [];
      for (const m of arr) {
        const id = m['id'] as number | undefined;
        if (id !== undefined) {
          ids.push(id);
          previews.push(formatPreview(m));
        }
      }
      this.pinnedIds = ids; // newest → oldest, as returned
      this.pinnedPreviews = previews;
      if (previews.length > 0) {
        this.setPinned(previews[0]);
      }
    }).catch((e: TdError) => {
      // no pinned message / unsupported → no banner
    });
  }

  // Pinned message ids, newest → oldest (for the banner tap-cycle).
  getPinnedIds(): number[] {
    return this.pinnedIds;
  }

  // Pinned message previews, aligned with getPinnedIds().
  getPinnedPreviews(): string[] {
    return this.pinnedPreviews;
  }

  // Load a page centered on a message (for jumping to a pinned/quoted message
  // that isn't in the currently loaded window). Notifies when it arrives.
  loadAround(messageId: number): void {
    // Jumping into the middle of history: newer messages beyond this window
    // may exist — enable downward prefetch to discover/load them.
    this.hasMoreNewer = true;
    const req: TdRequest = { '@type': 'getChatHistory' };
    req['chat_id'] = this.chatId;
    req['from_message_id'] = messageId;
    req['offset'] = -15;
    req['limit'] = 30;
    req['only_local'] = false;
    this.client.send(req).then((res: TdObject) => this.onHistory(res)).catch((e: TdError) => {
      console.error(`MessageStore.loadAround failed: ${e.message}`);
    });
  }

  private setPinned(s: string): void {
    this.pinnedPreview = s;
    for (const l of this.pinnedSubs) {
      l(this.pinnedPreview);
    }
  }

  private resolveChat(): void {
    const req: TdRequest = { '@type': 'getChat' };
    req['chat_id'] = this.chatId;
    this.client.send(req).then((chat: TdObject) => this.onChat(chat)).catch((e: TdError) => {
      console.error(`MessageStore.getChat failed: ${e.message}`);
      this.startInitialLoad();
      this.flushInitial();
    });
  }

  private onChat(chat: TdObject): void {
    // Capture the unread boundary BEFORE loading history / marking read, so the
    // page can position at the first unread message even after we mark it read.
    this.lastReadInboxId = (chat['last_read_inbox_message_id'] as number | undefined) ?? 0;
    this.lastReadOutboxId = (chat['last_read_outbox_message_id'] as number | undefined) ?? 0;
    this.unreadCount = (chat['unread_count'] as number | undefined) ?? 0;
    const photo = chat['photo'] as TdObject | undefined;
    const small = photo !== undefined ? (photo['small'] as TdObject | undefined) : undefined;
    this.chatPhotoFileId = small !== undefined ? ((small['id'] as number | undefined) ?? 0) : 0;
    this.downloadChatPhoto();
    this.chatTitle = (chat['title'] as string | undefined) ?? '';
    this.notifyHeaderTitle();
    const type = chat['type'] as TdObject | undefined;
    if (type !== undefined) {
      const t = type['@type'] as string | undefined;
      if (t === 'chatTypePrivate') {
        this.peerUserId = (type['user_id'] as number | undefined) ?? 0;
        this.fetchUserStatus();
      } else if (t === 'chatTypeBasicGroup') {
        this.groupId = (type['basic_group_id'] as number | undefined) ?? 0;
        this.isGroupFlag = true;
        this.resolveBasicGroup(this.groupId);
      } else if (t === 'chatTypeSupergroup') {
        this.groupId = (type['supergroup_id'] as number | undefined) ?? 0;
        this.isGroupFlag = true;
        this.resolveSupergroup(this.groupId);
      }
    }
    this.resolveSenderAvatars();
    this.startInitialLoad();
    this.flushInitial();
  }

  private startInitialLoad(): void {
    if (this.initialLoadStarted) {
      return;
    }
    this.initialLoadStarted = true;
    if (this.requestedAroundMessageId > 0) {
      this.loadAround(this.requestedAroundMessageId);
      return;
    }
    // getFirstUnreadId() only scans the loaded window, so with a large unread
    // count the newest-30 page (loadHistory(0)) never actually contains the
    // true first-unread message — it silently returns the oldest of that page
    // instead, landing (and read-marking) far past the real boundary. Center
    // on lastReadInboxId to guarantee the boundary is in the loaded window —
    // but ONLY when there's actually something unread: last_read_inbox_message_id
    // only tracks incoming messages, so a fully-read chat whose newest messages
    // are outgoing (sent by us) can have it sitting well behind the true tail —
    // loadAround there would miss the real end of the chat. Fully-read chats
    // always just load the newest page instead.
    if (this.unreadCount > 0 && this.lastReadInboxId > 0) {
      this.loadAround(this.lastReadInboxId);
      return;
    }
    this.loadHistory(0);
  }

  private fetchUserStatus(): void {
    if (this.peerUserId === 0) {
      return;
    }
    const req: TdRequest = { '@type': 'getUser' };
    req['user_id'] = this.peerUserId;
    this.client.send(req).then((user: TdObject) => {
      this.setSubtitle(formatUserStatus(user['status'] as TdObject | undefined, Math.floor(Date.now() / 1000)));
    }).catch((e: TdError) => {
      console.error(`MessageStore.getUser failed: ${e.message}`);
    });
  }

  private onUserStatus(u: TdObject): void {
    if ((u['user_id'] as number | undefined) !== this.peerUserId || this.peerUserId === 0) {
      return;
    }
    this.setSubtitle(formatUserStatus(u['status'] as TdObject | undefined, Math.floor(Date.now() / 1000)));
  }

  private onGroup(u: TdObject): void {
    const g = (u['basic_group'] as TdObject | undefined) ?? (u['supergroup'] as TdObject | undefined);
    if (g === undefined) {
      return;
    }
    if ((g['id'] as number | undefined) !== this.groupId || this.groupId === 0) {
      return;
    }
    const isCh = (g['is_channel'] as boolean | undefined);
    if (isCh !== undefined) {
      this.isChannel = isCh;
    }
    const count = (g['member_count'] as number | undefined) ?? 0;
    if (count > 0) {
      this.setMemberSubtitle(count);
    }
  }

  // Subscriber/member count subtitle, K-abbreviated like Telegram
  // ("33.1K 位订阅者" / "128 位成员, 12 人在线").
  private setMemberSubtitle(count: number): void {
    this.memberCount = count;
    this.composeMemberSubtitle();
  }

  private composeMemberSubtitle(): void {
    if (this.memberCount <= 0) {
      return;
    }
    let s = `${formatMemberCount(this.memberCount)} 位${this.isChannel ? '订阅者' : '成员'}`;
    // Channels don't surface member presence — online counts are a group thing.
    if (!this.isChannel && this.onlineCount > 0) {
      s += `, ${this.onlineCount} 人在线`;
    }
    this.setSubtitle(s);
  }

  private onOnlineCount(u: TdObject): void {
    if ((u['chat_id'] as number | undefined) !== this.chatId) {
      return;
    }
    this.onlineCount = (u['online_member_count'] as number | undefined) ?? 0;
    this.composeMemberSubtitle();
  }

  // Supergroup/channel: the pushed supergroup object often carries member_count 0,
  // so fetch the authoritative count from getSupergroupFullInfo (and is_channel
  // from getSupergroup) rather than waiting for an updateSupergroup that may not come.
  private resolveSupergroup(id: number): void {
    if (id === 0) {
      return;
    }
    const sg: TdRequest = { '@type': 'getSupergroup' };
    sg['supergroup_id'] = id;
    this.client.send(sg).then((s: TdObject) => {
      this.isChannel = (s['is_channel'] as boolean | undefined) ?? this.isChannel;
      const c = (s['member_count'] as number | undefined) ?? 0;
      if (c > 0) {
        this.setMemberSubtitle(c);
      }
    }).catch((e: TdError) => {
      console.error(`MessageStore.getSupergroup failed: ${e.message}`);
    });
    const full: TdRequest = { '@type': 'getSupergroupFullInfo' };
    full['supergroup_id'] = id;
    this.client.send(full).then((f: TdObject) => {
      const c = (f['member_count'] as number | undefined) ?? 0;
      if (c > 0) {
        this.setMemberSubtitle(c);
      }
    }).catch((e: TdError) => {
      console.error(`MessageStore.getSupergroupFullInfo failed: ${e.message}`);
    });
  }

  private resolveBasicGroup(id: number): void {
    if (id === 0) {
      return;
    }
    this.isChannel = false;
    const req: TdRequest = { '@type': 'getBasicGroup' };
    req['basic_group_id'] = id;
    this.client.send(req).then((bg: TdObject) => {
      const c = (bg['member_count'] as number | undefined) ?? 0;
      if (c > 0) {
        this.setMemberSubtitle(c);
      }
    }).catch((e: TdError) => {
      console.error(`MessageStore.getBasicGroup failed: ${e.message}`);
    });
  }

  private setSubtitle(s: string): void {
    this.subtitle = s;
    for (const l of this.subSubs) {
      l(this.subtitle);
    }
  }

  // --- read marking (driven by the visible range) ---
  // Mark messages read up to maxVisibleId. Because TDLib read state is a
  // high-water mark, we only ever send the highest id the user has actually
  // seen — so entering a chat without scrolling leaves the rest unread.
  markViewed(maxVisibleId: number): void {
    if (maxVisibleId <= this.viewedUpTo) {
      return;
    }
    this.viewedUpTo = maxVisibleId;
    const req: TdRequest = { '@type': 'viewMessages' };
    req['chat_id'] = this.chatId;
    req['message_ids'] = [maxVisibleId];
    req['force_read'] = true;
    this.client.send(req).catch((e: TdError) => {
      console.error(`MessageStore.viewMessages failed: ${e.message}`);
    });
  }

  // Forwards from a channel/chat only carry the origin chat id (forwardChatId);
  // resolve it to a display title via getChat, then patch matching messages.
  private resolveForwardTitles(): void {
    for (const e of this.messages) {
      if (e.forwardChatId === 0 || e.forwardFrom !== '') {
        continue;
      }
      const cached = this.forwardTitleCache.get(e.forwardChatId);
      if (cached !== undefined) {
        this.patch(e.id, (c: MessageEntry) => { c.forwardFrom = cached; c.forwardChatId = 0; });
        continue;
      }
      if (this.forwardTitleRequested.has(e.forwardChatId)) {
        continue;
      }
      this.forwardTitleRequested.add(e.forwardChatId);
      const id = e.forwardChatId;
      const req: TdRequest = { '@type': 'getChat' };
      req['chat_id'] = id;
      this.client.send(req).then((chat: TdObject) => {
        const title = (chat['title'] as string | undefined) ?? '';
        this.forwardTitleCache.set(id, title);
        this.resolveForwardTitles();
      }).catch((err: TdError) => {
        console.error(`MessageStore forward title ${id}: ${err.message}`);
      });
    }
  }

  private resolveReplies(): void {
    this.messages = this.messages.map((e: MessageEntry) => {
      if (e.replyToMessageId === 0 || e.replyText !== '') {
        return e;
      }
      const target = this.messages.find((x: MessageEntry) => x.id === e.replyToMessageId);
      if (target === undefined) {
        return e;
      }
      const c = cloneMessage(e);
      c.replySenderName = target.senderName;
      c.replyText = target.contentType === 'text' ? target.text : (target.placeholderLabel !== '' ? target.placeholderLabel : '[图片]');
      return c;
    });
  }

  private indexOf(id: number): number {
    for (let i = 0; i < this.messages.length; i++) {
      if (this.messages[i].id === id) {
        return i;
      }
    }
    return -1;
  }

  private upsert(entry: MessageEntry): void {
    const idx = this.indexOf(entry.id);
    if (idx >= 0) {
      const next = this.messages.slice();
      next[idx] = entry;
      this.messages = next;
      return;
    }
    const next = this.messages.slice();
    next.push(entry);
    next.sort((a: MessageEntry, b: MessageEntry) => a.id - b.id);
    this.messages = next;
  }

  private patch(id: number, fn: (c: MessageEntry) => void): void {
    const idx = this.indexOf(id);
    if (idx < 0) {
      return;
    }
    const c = cloneMessage(this.messages[idx]);
    fn(c);
    const next = this.messages.slice();
    next[idx] = c;
    this.messages = next;
    this.notify();
  }

  private notify(): void {
    this.applyReadOutbox();
    for (const l of this.msgSubs) {
      l(this.messages);
    }
  }
}
