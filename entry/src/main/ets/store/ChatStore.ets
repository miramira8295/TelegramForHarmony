import { TdClient } from '../tdkit/TdClient';
import { TdObject, TdRequest, TdError } from '../tdkit/TdTypes';
import { UserStore } from './UserStore';
import { ChatEntry, PositionInfo, cloneEntry, computeInitials, compareOrderDesc, isMutedFrom, chatKindOf } from './ChatEntry';
import { listKeyOf, chatListOf } from './ListKey';
import { formatPreview } from '../util/formatPreview';

const PAGE_LIMIT: number = 30;
const MAIN: string = 'main';

interface Sub {
  listKey: string;
  listener: (chats: ChatEntry[]) => void;
}

export class ChatStore {
  private client: TdClient;
  private users: UserStore;
  private chats: Map<number, ChatEntry> = new Map();
  private positions: Map<string, Map<number, PositionInfo>> = new Map();
  private subs: Sub[] = [];
  private groupCallChats: Map<number, number> = new Map();
  private groupCallLoading: Set<number> = new Set();

  constructor(client: TdClient, users: UserStore) {
    this.client = client;
    this.users = users;
    client.onUpdate('updateNewChat', (u: TdObject) => this.onNewChat(u));
    client.onUpdate('updateChatPosition', (u: TdObject) => this.onPosition(u));
    client.onUpdate('updateChatLastMessage', (u: TdObject) => this.onLastMessage(u));
    client.onUpdate('updateChatReadInbox', (u: TdObject) => this.onReadInbox(u));
    client.onUpdate('updateChatTitle', (u: TdObject) => this.onTitle(u));
    client.onUpdate('updateChatPhoto', (u: TdObject) => this.onPhoto(u));
    client.onUpdate('updateChatNotificationSettings', (u: TdObject) => this.onNotify(u));
    client.onUpdate('updateChatMessageAutoDeleteTime', (u: TdObject) => this.onAutoDelete(u));
    client.onUpdate('updateChatIsMarkedAsUnread', (u: TdObject) => this.onMarkedUnread(u));
    client.onUpdate('updateChatVideoChat', (u: TdObject) => this.onVideoChat(u));
    client.onUpdate('updateGroupCall', (u: TdObject) => this.onGroupCall(u));
  }

  subscribe(listener: (chats: ChatEntry[]) => void, listKey: string = MAIN): () => void {
    const sub: Sub = { listKey, listener };
    this.subs = [...this.subs, sub];
    listener(this.getChats(listKey));
    return (): void => {
      this.subs = this.subs.filter((s: Sub) => s !== sub);
    };
  }

  // Every cached chat across all lists (main/archive/folders). Used to request
  // avatars regardless of which list a chat was surfaced through.
  allEntries(): ChatEntry[] {
    return Array.from(this.chats.values());
  }

  getChats(listKey: string = MAIN): ChatEntry[] {
    const bucket = this.positions.get(listKey);
    if (bucket === undefined) {
      return [];
    }
    const list: ChatEntry[] = [];
    bucket.forEach((_pos: PositionInfo, id: number) => {
      const e = this.chats.get(id);
      if (e !== undefined) {
        list.push(e);
      }
    });
    list.sort((a: ChatEntry, b: ChatEntry) => {
      const pa = bucket.get(a.id)!;
      const pb = bucket.get(b.id)!;
      if (pa.isPinned !== pb.isPinned) {
        return pa.isPinned ? -1 : 1;
      }
      return compareOrderDesc(pa.order, pb.order);
    });
    return list;
  }

  // Pinning is per chat list: a chat can be pinned in a folder but not in main.
  isPinned(listKey: string, chatId: number): boolean {
    const pos = this.positions.get(listKey)?.get(chatId);
    return pos !== undefined && pos.isPinned;
  }

  isArchived(chatId: number): boolean {
    return this.positions.get('archive')?.has(chatId) === true;
  }

  isInFolder(folderId: number, chatId: number): boolean {
    return this.positions.get(`folder:${folderId}`)?.has(chatId) === true;
  }

  hasArchive(): boolean {
    const b = this.positions.get('archive');
    return b !== undefined && b.size > 0;
  }

  // Count of unmuted chats with unread messages in a list, computed from loaded
  // chats. Used for folder tab badges (TDLib's updateUnreadChatCount is emitted
  // only for the main and archive lists, not for chat folders).
  unreadChatCount(listKey: string): number {
    const bucket = this.positions.get(listKey);
    if (bucket === undefined) {
      return 0;
    }
    let count = 0;
    bucket.forEach((_pos: PositionInfo, id: number) => {
      const e = this.chats.get(id);
      if (e !== undefined && e.unreadCount > 0 && !e.isMuted) {
        count += 1;
      }
    });
    return count;
  }

  photoFileIdOf(chatId: number): number {
    const e = this.chats.get(chatId);
    return e !== undefined ? e.photoFileId : 0;
  }

  entryOf(chatId: number): ChatEntry | undefined {
    return this.chats.get(chatId);
  }

  async load(listKey: string = MAIN): Promise<void> {
    const req: TdRequest = { '@type': 'loadChats' };
    req['chat_list'] = chatListOf(listKey);
    req['limit'] = PAGE_LIMIT;
    try {
      await this.client.send(req);
    } catch (e) {
      const code = (e as TdError).code;
      if (code !== 404) {
        console.error(`ChatStore.load(${listKey}) failed: ${(e as TdError).message}`);
      }
    }
  }

  async loadMore(listKey: string = MAIN): Promise<void> {
    await this.load(listKey);
  }

  setAvatarPath(chatId: number, path: string): void {
    const e = this.chats.get(chatId);
    if (e === undefined || e.avatarPath === path) {
      return;
    }
    const c = cloneEntry(e);
    c.avatarPath = path;
    this.chats.set(chatId, c);
    this.notify();
  }

  private setPosition(listKey: string, id: number, order: string, isPinned: boolean): void {
    if (listKey === '') {
      return;
    }
    if (order === '0') {
      const b = this.positions.get(listKey);
      if (b !== undefined) {
        b.delete(id);
      }
      return;
    }
    let bucket = this.positions.get(listKey);
    if (bucket === undefined) {
      bucket = new Map();
      this.positions.set(listKey, bucket);
    }
    bucket.set(id, { order, isPinned });
  }

  private applyPositions(id: number, positions: TdObject[]): void {
    for (const p of positions) {
      const list = p['list'] as TdObject | undefined;
      if (list === undefined) {
        continue;
      }
      const key = listKeyOf(list);
      const order = (p['order'] as string | undefined) ?? '0';
      const isPinned = (p['is_pinned'] as boolean | undefined) ?? false;
      this.setPosition(key, id, order, isPinned);
    }
  }

  private senderName(message: TdObject | undefined): string {
    if (message === undefined) {
      return '';
    }
    const sender = message['sender_id'] as TdObject | undefined;
    if (sender === undefined) {
      return '';
    }
    if (sender['@type'] === 'messageSenderUser') {
      return this.users.displayName(sender['user_id'] as number);
    }
    if (sender['@type'] === 'messageSenderChat') {
      const c = this.chats.get(sender['chat_id'] as number);
      return c !== undefined ? c.title : '';
    }
    return '';
  }

  private smallPhotoId(photo: TdObject | undefined): number {
    if (photo === undefined) {
      return 0;
    }
    const small = photo['small'] as TdObject | undefined;
    if (small === undefined) {
      return 0;
    }
    return (small['id'] as number | undefined) ?? 0;
  }

  private videoChatId(videoChat: TdObject | undefined): number {
    return videoChat !== undefined
      ? ((videoChat['group_call_id'] as number | undefined) ?? 0) : 0;
  }

  private rememberGroupCall(chatId: number, previousId: number, groupCallId: number): void {
    if (previousId > 0 && this.groupCallChats.get(previousId) === chatId) {
      this.groupCallChats.delete(previousId);
    }
    if (groupCallId > 0) {
      this.groupCallChats.set(groupCallId, chatId);
      this.requestGroupCall(groupCallId);
    }
  }

  // chat.video_chat only carries the call id. Confirm is_active through
  // getGroupCall so scheduled/ended calls don't receive a LIVE badge.
  private requestGroupCall(groupCallId: number): void {
    if (groupCallId <= 0 || this.groupCallLoading.has(groupCallId)) { return; }
    this.groupCallLoading.add(groupCallId);
    const request: TdRequest = { '@type': 'getGroupCall' };
    request['group_call_id'] = groupCallId;
    this.client.send(request).then((groupCall: TdObject): void => {
      this.groupCallLoading.delete(groupCallId);
      this.applyGroupCall(groupCall);
    }).catch((error: TdError): void => {
      this.groupCallLoading.delete(groupCallId);
      if (error.code !== 404) {
        console.error(`ChatStore.getGroupCall(${groupCallId}) failed: ${error.message}`);
      }
    });
  }

  private applyGroupCall(groupCall: TdObject): void {
    const groupCallId = (groupCall['id'] as number | undefined) ?? 0;
    const chatId = this.groupCallChats.get(groupCallId);
    if (chatId === undefined) { return; }
    const entry = this.chats.get(chatId);
    if (entry === undefined || entry.liveGroupCallId !== groupCallId) { return; }
    const isLive = (groupCall['is_active'] as boolean | undefined) ?? false;
    const isRtmpLive = (groupCall['is_rtmp_stream'] as boolean | undefined) ?? false;
    if (entry.isLive === isLive && entry.isRtmpLive === isRtmpLive) { return; }
    const next = cloneEntry(entry);
    next.isLive = isLive;
    next.isRtmpLive = isRtmpLive;
    this.chats.set(chatId, next);
    this.notify();
  }

  private onNewChat(update: TdObject): void {
    const chat = update['chat'] as TdObject | undefined;
    if (chat === undefined) {
      return;
    }
    const id = chat['id'] as number;
    const previousGroupCallId = this.chats.get(id)?.liveGroupCallId ?? 0;
    const title = (chat['title'] as string | undefined) ?? '';
    const lastMsg = chat['last_message'] as TdObject | undefined;
    const groupCallId = this.videoChatId(chat['video_chat'] as TdObject | undefined);
    const entry: ChatEntry = {
      id,
      title,
      isMuted: isMutedFrom(chat['notification_settings'] as TdObject | undefined),
      unreadCount: (chat['unread_count'] as number | undefined) ?? 0,
      lastMessageText: formatPreview(lastMsg ?? null),
      lastMessageDate: lastMsg !== undefined ? ((lastMsg['date'] as number | undefined) ?? 0) : 0,
      lastMessageId: lastMsg !== undefined ? ((lastMsg['id'] as number | undefined) ?? 0) : 0,
      lastSenderName: this.senderName(lastMsg),
      photoFileId: this.smallPhotoId(chat['photo'] as TdObject | undefined),
      avatarPath: '',
      initials: computeInitials(title),
      autoDeleteTime: (chat['message_auto_delete_time'] as number | undefined) ?? 0,
      kind: chatKindOf(chat['type'] as TdObject | undefined),
      isMarkedUnread: (chat['is_marked_as_unread'] as boolean | undefined) ?? false,
      liveGroupCallId: groupCallId,
      isLive: false,
      isRtmpLive: false
    };
    this.chats.set(id, entry);
    this.rememberGroupCall(id, previousGroupCallId, groupCallId);
    const positions = (chat['positions'] as TdObject[] | undefined) ?? [];
    this.applyPositions(id, positions);
    this.notify();
  }

  private onPosition(update: TdObject): void {
    const id = update['chat_id'] as number;
    const pos = update['position'] as TdObject | undefined;
    if (pos === undefined) {
      return;
    }
    this.applyPositions(id, [pos]);
    this.notify();
  }

  private onLastMessage(update: TdObject): void {
    const id = update['chat_id'] as number;
    const e = this.chats.get(id);
    if (e === undefined) {
      return;
    }
    const lastMsg = update['last_message'] as TdObject | undefined;
    const c = cloneEntry(e);
    c.lastMessageText = formatPreview(lastMsg ?? null);
    c.lastMessageDate = lastMsg !== undefined ? ((lastMsg['date'] as number | undefined) ?? 0) : 0;
    c.lastMessageId = lastMsg !== undefined ? ((lastMsg['id'] as number | undefined) ?? 0) : 0;
    c.lastSenderName = this.senderName(lastMsg);
    this.chats.set(id, c);
    const positions = update['positions'] as TdObject[] | undefined;
    if (positions !== undefined) {
      this.applyPositions(id, positions);
    }
    this.notify();
  }

  private onReadInbox(update: TdObject): void {
    const id = update['chat_id'] as number;
    const e = this.chats.get(id);
    if (e === undefined) {
      return;
    }
    const c = cloneEntry(e);
    c.unreadCount = (update['unread_count'] as number | undefined) ?? 0;
    this.chats.set(id, c);
    this.notify();
  }

  private onTitle(update: TdObject): void {
    const id = update['chat_id'] as number;
    const e = this.chats.get(id);
    if (e === undefined) {
      return;
    }
    const title = (update['title'] as string | undefined) ?? '';
    const c = cloneEntry(e);
    c.title = title;
    c.initials = computeInitials(title);
    this.chats.set(id, c);
    this.notify();
  }

  private onPhoto(update: TdObject): void {
    const id = update['chat_id'] as number;
    const e = this.chats.get(id);
    if (e === undefined) {
      return;
    }
    const c = cloneEntry(e);
    c.photoFileId = this.smallPhotoId(update['photo'] as TdObject | undefined);
    c.avatarPath = '';
    this.chats.set(id, c);
    this.notify();
  }

  private onNotify(update: TdObject): void {
    const id = update['chat_id'] as number;
    const e = this.chats.get(id);
    if (e === undefined) {
      return;
    }
    const c = cloneEntry(e);
    c.isMuted = isMutedFrom(update['notification_settings'] as TdObject | undefined);
    this.chats.set(id, c);
    this.notify();
  }

  private onMarkedUnread(update: TdObject): void {
    const id = update['chat_id'] as number;
    const e = this.chats.get(id);
    if (e === undefined) {
      return;
    }
    const c = cloneEntry(e);
    c.isMarkedUnread = (update['is_marked_as_unread'] as boolean | undefined) ?? false;
    this.chats.set(id, c);
    this.notify();
  }

  private onAutoDelete(update: TdObject): void {
    const id = update['chat_id'] as number;
    const e = this.chats.get(id);
    if (e === undefined) {
      return;
    }
    const c = cloneEntry(e);
    c.autoDeleteTime = (update['message_auto_delete_time'] as number | undefined) ?? 0;
    this.chats.set(id, c);
    this.notify();
  }

  private onVideoChat(update: TdObject): void {
    const chatId = (update['chat_id'] as number | undefined) ?? 0;
    const entry = this.chats.get(chatId);
    if (entry === undefined) { return; }
    const groupCallId = this.videoChatId(update['video_chat'] as TdObject | undefined);
    const previousId = entry.liveGroupCallId;
    const next = cloneEntry(entry);
    next.liveGroupCallId = groupCallId;
    // A newly announced id can still be scheduled. Keep the badge hidden
    // until getGroupCall/updateGroupCall confirms is_active.
    next.isLive = false;
    next.isRtmpLive = false;
    this.chats.set(chatId, next);
    this.rememberGroupCall(chatId, previousId, groupCallId);
    this.notify();
  }

  private onGroupCall(update: TdObject): void {
    const groupCall = update['group_call'] as TdObject | undefined;
    if (groupCall !== undefined) { this.applyGroupCall(groupCall); }
  }

  private notify(): void {
    for (const s of this.subs) {
      s.listener(this.getChats(s.listKey));
    }
  }
}
