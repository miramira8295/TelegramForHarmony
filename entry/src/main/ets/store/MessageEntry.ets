import { TdObject } from '../tdkit/TdTypes';
import { UserStore } from './UserStore';
import { buttonStyleOf } from './ReplyKeyboard';
import { formatMsgContent, MsgContent } from '../util/formatMsgContent';
import { SERVICE_LABELS } from '../util/formatPreview';

export interface MessageEntry {
  id: number;
  isOutgoing: boolean;
  senderName: string;
  senderId: number;
  senderIsUser: boolean;
  senderInitials: string;
  senderAvatarPath: string;
  date: number;
  contentType: string;
  text: string;
  photoFileId: number;
  photoPath: string;
  photoProgress: number; // 0-100 download progress of the inline thumbnail
  photoWidth: number;
  photoHeight: number;
  placeholderLabel: string;
  replyToMessageId: number;
  replySenderName: string;
  replyText: string;
  sendState: string;
  albumId: string;
  textEntities: TdObject[];
  forwardFrom: string;   // display name of the forward origin ('' = not forwarded)
  forwardChatId: number; // origin channel/chat id to resolve a title for (0 = none/resolved)
  // Tappable origin of a forward: the original post (channel/chat) or its
  // author (user). All 0 for a hidden-origin forward, which can't be opened.
  forwardOriginChatId: number;
  forwardOriginMsgId: number;
  forwardOriginUserId: number;
  commentCount: number;         // channel post comment count (0 = no comments row)
  commentReplierIds: number[];  // up to 3 recent commenter user ids (for avatar stack)
  commentReplierAvatarPaths: string[]; // parallel to commentReplierIds, filled in as avatars download
  linkSiteName: string;         // link preview card ('' = no preview)
  linkTitle: string;
  linkDescription: string;
  linkDescriptionEntities: TdObject[];
  linkPhotoFileId: number;
  linkPhotoPath: string;
  linkUrl: string;              // tap target to open the preview's link/message
  reactions: ReactionInfo[];    // emoji reaction pills (empty = none)
  inlineButtons: InlineBtn[][]; // bot inline keyboard rows (empty = none)
  photoFullFileId: number;      // full-resolution photo file id (0 = no upgrade available)
  photoFullPath: string;        // local path once the full-resolution photo is downloaded (on tap)
  photoFullProgress: number;    // 0-100 download progress of the full-resolution photo
  videoFileId: number;          // full-resolution video file id (0 = not a video)
  videoFileSize: number;        // bytes (0 = unknown)
  videoMimeType: string;        // source mime type from TDLib, e.g. video/mp4
  videoFileName: string;        // original file name ('' = unknown)
  videoDuration: number;        // seconds
  videoPath: string;            // local path once the full video is downloaded
  videoProgress: number;        // 0-100 download progress of the full video file
  stickerFileId: number;        // animated (TGS) sticker source file id, 0 otherwise
  customEmojiId: string;        // single custom-emoji message, pending sticker resolution
  stickerFormat: string;        // 'webp' | 'tgs' | 'webm', '' for non-stickers
  stickerPath: string;          // local path of the downloaded TGS file
}

export interface ReactionInfo {
  emoji: string;
  count: number;
  isChosen: boolean;
}

// One bot inline-keyboard button. Exactly one of url/callbackData is set for
// the types we support; unsupported types render but do nothing on tap.
export interface InlineBtn {
  text: string;
  url: string;
  callbackData: string; // base64 payload for inlineKeyboardButtonTypeCallback
  style: string;        // 'primary' | 'success' | 'danger' | '' (default look)
}

// Parse message.reply_markup (replyMarkupInlineKeyboard) into button rows.
export function parseInlineKeyboard(replyMarkup: TdObject | undefined): InlineBtn[][] {
  if (replyMarkup === undefined || replyMarkup['@type'] !== 'replyMarkupInlineKeyboard') {
    return [];
  }
  const rows = (replyMarkup['rows'] as TdObject[][] | undefined) ?? [];
  const out: InlineBtn[][] = [];
  for (const row of rows) {
    const btns: InlineBtn[] = [];
    for (const b of row) {
      const t = b['type'] as TdObject | undefined;
      const tt = t !== undefined ? ((t['@type'] as string | undefined) ?? '') : '';
      btns.push({
        text: (b['text'] as string | undefined) ?? '',
        url: tt === 'inlineKeyboardButtonTypeUrl' ? ((t!['url'] as string | undefined) ?? '') : '',
        callbackData: tt === 'inlineKeyboardButtonTypeCallback' ? ((t!['data'] as string | undefined) ?? '') : '',
        style: buttonStyleOf(b)
      });
    }
    if (btns.length > 0) {
      out.push(btns);
    }
  }
  return out;
}

export function cloneMessage(m: MessageEntry): MessageEntry {
  return {
    id: m.id, isOutgoing: m.isOutgoing, senderName: m.senderName,
    senderId: m.senderId, senderIsUser: m.senderIsUser,
    senderInitials: m.senderInitials, senderAvatarPath: m.senderAvatarPath, date: m.date,
    contentType: m.contentType, text: m.text, photoFileId: m.photoFileId, photoPath: m.photoPath,
    photoProgress: m.photoProgress,
    photoWidth: m.photoWidth, photoHeight: m.photoHeight,
    placeholderLabel: m.placeholderLabel, replyToMessageId: m.replyToMessageId,
    replySenderName: m.replySenderName, replyText: m.replyText, sendState: m.sendState,
    albumId: m.albumId, textEntities: m.textEntities,
    forwardFrom: m.forwardFrom, forwardChatId: m.forwardChatId,
    forwardOriginChatId: m.forwardOriginChatId, forwardOriginMsgId: m.forwardOriginMsgId,
    forwardOriginUserId: m.forwardOriginUserId,
    commentCount: m.commentCount, commentReplierIds: m.commentReplierIds,
    commentReplierAvatarPaths: m.commentReplierAvatarPaths,
    linkSiteName: m.linkSiteName, linkTitle: m.linkTitle, linkDescription: m.linkDescription,
    linkDescriptionEntities: m.linkDescriptionEntities, linkPhotoFileId: m.linkPhotoFileId,
    linkPhotoPath: m.linkPhotoPath, linkUrl: m.linkUrl,
    reactions: m.reactions,
    inlineButtons: m.inlineButtons,
    photoFullFileId: m.photoFullFileId, photoFullPath: m.photoFullPath, photoFullProgress: m.photoFullProgress,
    videoFileId: m.videoFileId, videoFileSize: m.videoFileSize, videoMimeType: m.videoMimeType,
    videoFileName: m.videoFileName, videoDuration: m.videoDuration,
    videoPath: m.videoPath, videoProgress: m.videoProgress,
    stickerFileId: m.stickerFileId, stickerFormat: m.stickerFormat, stickerPath: m.stickerPath,
    customEmojiId: m.customEmojiId
  };
}

interface FwdOrigin {
  name: string;
  chatId: number;
  // Where the forward came from, kept for the tappable "转发自" header. chatId
  // above doubles as a "title still to resolve" marker and gets cleared once
  // resolved, so the origin is recorded separately here.
  originChatId: number;
  originMsgId: number;
  originUserId: number;
}

// Parse a message's forward_info into a display name (user/hidden origin) or a
// chat id to resolve a title for (channel/chat origin).
function forwardOrigin(message: TdObject, users: UserStore): FwdOrigin {
  const fi = message['forward_info'] as TdObject | undefined;
  const origin = fi !== undefined ? (fi['origin'] as TdObject | undefined) : undefined;
  if (origin === undefined) {
    return { name: '', chatId: 0, originChatId: 0, originMsgId: 0, originUserId: 0 };
  }
  const ot = origin['@type'] as string | undefined;
  if (ot === 'messageOriginUser') {
    const uid = (origin['sender_user_id'] as number | undefined) ?? 0;
    return {
      name: users.displayName(uid), chatId: 0,
      originChatId: 0, originMsgId: 0, originUserId: uid
    };
  }
  if (ot === 'messageOriginHiddenUser') {
    // Origin deliberately hidden — nothing to open.
    return {
      name: (origin['sender_name'] as string | undefined) ?? '', chatId: 0,
      originChatId: 0, originMsgId: 0, originUserId: 0
    };
  }
  if (ot === 'messageOriginChannel') {
    const cid = (origin['chat_id'] as number | undefined) ?? 0;
    return {
      name: '', chatId: cid,
      originChatId: cid, originMsgId: (origin['message_id'] as number | undefined) ?? 0,
      originUserId: 0
    };
  }
  if (ot === 'messageOriginChat') {
    const cid = (origin['sender_chat_id'] as number | undefined) ?? 0;
    return {
      name: '', chatId: cid,
      originChatId: cid, originMsgId: 0, originUserId: 0
    };
  }
  return { name: '', chatId: 0, originChatId: 0, originMsgId: 0, originUserId: 0 };
}

export interface CommentInfo {
  count: number;
  replierIds: number[];
}

// Channel posts carry their discussion-group comment count and recent
// commenters in interaction_info.reply_info (messageReplyInfo).
function commentInfo(message: TdObject): CommentInfo {
  return commentInfoFromInteraction(message['interaction_info'] as TdObject | undefined);
}

export function commentInfoFromInteraction(ii: TdObject | undefined): CommentInfo {
  const ri = ii !== undefined ? (ii['reply_info'] as TdObject | undefined) : undefined;
  if (ri === undefined) {
    return { count: 0, replierIds: [] };
  }
  const count = (ri['reply_count'] as number | undefined) ?? 0;
  const repliers = (ri['recent_replier_ids'] as TdObject[] | undefined) ?? [];
  const ids: number[] = [];
  for (const s of repliers) {
    if (s['@type'] === 'messageSenderUser') {
      const uid = s['user_id'] as number | undefined;
      if (uid !== undefined) {
        ids.push(uid);
      }
    }
    if (ids.length >= 3) {
      break;
    }
  }
  return { count, replierIds: ids };
}

// Service/system messages (chat title/photo changes, member joins, pinned
// notices, ...) rendered as a centered pill instead of a normal bubble.
// Returns '' when the content type isn't a recognized system message.
function systemMessageLabel(message: TdObject, users: UserStore): string {
  const content = message['content'] as TdObject | undefined;
  const type = content !== undefined ? (content['@type'] as string | undefined) : undefined;
  const actor = senderName(message, users);
  const who = actor !== '' ? actor : '有人';
  if (type === 'messageChatChangeTitle') {
    const title = (content!['title'] as string | undefined) ?? '';
    return `${who} 将群组改名为"${title}"`;
  }
  if (type === 'messageChatChangePhoto') {
    return `${who} 更新了群组头像`;
  }
  if (type === 'messageChatDeletePhoto') {
    return `${who} 删除了群组头像`;
  }
  if (type === 'messageChatAddMembers') {
    const ids = (content!['member_user_ids'] as number[] | undefined) ?? [];
    const names = ids.map((id: number) => users.displayName(id)).join('、');
    return names !== '' ? `${who} 邀请了 ${names}` : `${who} 邀请了新成员`;
  }
  if (type === 'messageChatDeleteMember') {
    const uid = content!['user_id'] as number | undefined;
    const name = uid !== undefined ? users.displayName(uid) : '';
    return name !== '' ? `${who} 移除了 ${name}` : `${who} 移除了一名成员`;
  }
  if (type === 'messageChatJoinByLink') {
    return `${who} 通过邀请链接加入群组`;
  }
  if (type === 'messageChatSetMessageAutoDeleteTime') {
    const secs = (content!['message_auto_delete_time'] as number | undefined) ?? 0;
    if (secs <= 0) {
      return `${who} 关闭了自动删除`;
    }
    const label = secs >= 86400 ? `${Math.round(secs / 86400)} 天`
      : (secs >= 3600 ? `${Math.round(secs / 3600)} 小时` : `${Math.round(secs / 60)} 分钟`);
    return `${who} 将消息自动删除时间设为 ${label}`;
  }
  if (type === 'messageChatJoinByRequest') {
    return `${who} 加入了群组`;
  }
  if (type === 'messageChatUpgradeTo' || type === 'messageChatUpgradeFrom') {
    return '群组已升级为超级群组';
  }
  if (type === 'messagePinMessage') {
    return `${who} 置顶了一条消息`;
  }
  if (type === 'messageBasicGroupChatCreate' || type === 'messageSupergroupChatCreate') {
    const title = (content!['title'] as string | undefined) ?? '';
    return `${who} 创建了群组"${title}"`;
  }
  // Channel direct-message (paid DM) settings — show the concrete star price /
  // enabled state, matching the official client's wording.
  if (type === 'messageDirectMessagePriceChanged') {
    const enabled = (content!['is_enabled'] as boolean | undefined) ?? false;
    const stars = (content!['paid_message_star_count'] as number | undefined) ?? 0;
    if (!enabled) {
      return '频道已关闭私信。';
    }
    return stars > 0 ? `此频道允许每条 ${stars} 颗星星的私信。` : '频道已启用私信。';
  }
  // Fallback for other service messages (video chats, gifts, giveaways, forum
  // topics, payments, …) → shown as a centered pill.
  const svc: string | undefined = type !== undefined ? SERVICE_LABELS[type] : undefined;
  if (svc !== undefined) {
    return svc;
  }
  return '';
}

// Content types intentionally hidden from the timeline. Empty by default — all
// service messages are now surfaced as centered pills via systemMessageLabel /
// SERVICE_LABELS instead of being hidden.
const HIDDEN_CONTENT_TYPES: string[] = [];

function isHiddenContent(message: TdObject): boolean {
  const content = message['content'] as TdObject | undefined;
  const t = content !== undefined ? (content['@type'] as string | undefined) : undefined;
  return t !== undefined && HIDDEN_CONTENT_TYPES.indexOf(t) >= 0;
}

function reactions(message: TdObject): ReactionInfo[] {
  return reactionsFromInteraction(message['interaction_info'] as TdObject | undefined);
}

export function reactionsFromInteraction(ii: TdObject | undefined): ReactionInfo[] {
  const rx = ii !== undefined ? (ii['reactions'] as TdObject | undefined) : undefined;
  const list = rx !== undefined ? (rx['reactions'] as TdObject[] | undefined) : undefined;
  if (list === undefined) {
    return [];
  }
  const out: ReactionInfo[] = [];
  for (const r of list) {
    const t = r['type'] as TdObject | undefined;
    const tt = t !== undefined ? ((t['@type'] as string | undefined) ?? '') : '';
    let emoji = '';
    if (tt === 'reactionTypeEmoji') {
      emoji = (t!['emoji'] as string | undefined) ?? '';
    } else if (tt === 'reactionTypePaid') {
      emoji = '⭐';
    } else {
      continue; // custom-emoji reactions need a sticker download; skip for now
    }
    out.push({
      emoji,
      count: (r['total_count'] as number | undefined) ?? 0,
      isChosen: (r['is_chosen'] as boolean | undefined) ?? false
    });
  }
  return out;
}

function albumIdOf(message: TdObject): string {
  const v = message['media_album_id'];
  if (v === undefined) {
    return '';
  }
  const s = `${v}`;
  return s === '0' ? '' : s;
}

function senderName(message: TdObject, users: UserStore): string {
  const sender = message['sender_id'] as TdObject | undefined;
  if (sender === undefined) {
    return '';
  }
  if (sender['@type'] === 'messageSenderUser') {
    return users.displayName(sender['user_id'] as number);
  }
  return '';
}

function senderIdOf(message: TdObject): number {
  const sender = message['sender_id'] as TdObject | undefined;
  if (sender === undefined) {
    return 0;
  }
  const st = sender['@type'] as string | undefined;
  if (st === 'messageSenderUser') {
    return (sender['user_id'] as number | undefined) ?? 0;
  }
  if (st === 'messageSenderChat') {
    return (sender['chat_id'] as number | undefined) ?? 0;
  }
  return 0;
}

function senderIsUserOf(message: TdObject): boolean {
  const sender = message['sender_id'] as TdObject | undefined;
  return sender !== undefined && sender['@type'] === 'messageSenderUser';
}

function outgoingState(message: TdObject): string {
  const st = message['sending_state'] as TdObject | undefined;
  if (st === undefined) {
    return 'sent';
  }
  if (st['@type'] === 'messageSendingStatePending') {
    return 'sending';
  }
  if (st['@type'] === 'messageSendingStateFailed') {
    return 'failed';
  }
  return 'sent';
}

function replyId(message: TdObject): number {
  const r = message['reply_to'] as TdObject | undefined;
  if (r === undefined || r['@type'] !== 'messageReplyToMessage') {
    return 0;
  }
  return (r['message_id'] as number | undefined) ?? 0;
}

export function buildMessageEntry(message: TdObject, users: UserStore): MessageEntry {
  const c: MsgContent = formatMsgContent(message);
  const isOutgoing = (message['is_outgoing'] as boolean | undefined) ?? false;
  const name = senderName(message, users);
  const fwd: FwdOrigin = forwardOrigin(message, users);
  const cmt: CommentInfo = commentInfo(message);
  const sysLabel = systemMessageLabel(message, users);
  const hidden = isHiddenContent(message);
  // Log genuinely unhandled content types — not hidden, not given a description
  // (still the bare 'Message' fallback) — so missing types surface in hilog.
  if (!hidden && c.contentType === 'other' && c.placeholderLabel === 'Message') {
    const rc = message['content'] as TdObject | undefined;
    const rt = rc !== undefined ? ((rc['@type'] as string | undefined) ?? 'unknown') : 'unknown';
    console.warn(`[UNHANDLED_MSG] type=${rt} id=${(message['id'] as number | undefined) ?? 0}`);
  }
  return {
    id: (message['id'] as number | undefined) ?? 0,
    isOutgoing,
    senderName: name,
    senderId: senderIdOf(message),
    senderIsUser: senderIsUserOf(message),
    senderInitials: name.length > 0 ? name.substring(0, 1).toUpperCase() : '?',
    senderAvatarPath: '',
    date: (message['date'] as number | undefined) ?? 0,
    contentType: hidden ? 'hidden' : (sysLabel !== '' ? 'system' : c.contentType),
    text: c.text,
    photoFileId: c.photoFileId,
    photoPath: '',
    photoProgress: 0,
    photoWidth: c.photoWidth,
    photoHeight: c.photoHeight,
    placeholderLabel: sysLabel !== '' ? sysLabel : c.placeholderLabel,
    replyToMessageId: replyId(message),
    replySenderName: '',
    replyText: '',
    sendState: isOutgoing ? outgoingState(message) : 'none',
    albumId: albumIdOf(message),
    textEntities: c.entities,
    forwardFrom: fwd.name,
    forwardChatId: fwd.chatId,
    forwardOriginChatId: fwd.originChatId,
    forwardOriginMsgId: fwd.originMsgId,
    forwardOriginUserId: fwd.originUserId,
    commentCount: cmt.count,
    commentReplierIds: cmt.replierIds,
    commentReplierAvatarPaths: [],
    linkSiteName: c.linkSiteName,
    linkTitle: c.linkTitle,
    linkDescription: c.linkDescription,
    linkDescriptionEntities: c.linkDescriptionEntities,
    linkPhotoFileId: c.linkPhotoFileId,
    linkPhotoPath: '',
    linkUrl: c.linkUrl,
    reactions: reactions(message),
    inlineButtons: parseInlineKeyboard(message['reply_markup'] as TdObject | undefined),
    photoFullFileId: c.photoFullFileId,
    photoFullPath: '',
    photoFullProgress: 0,
    videoFileId: c.videoFileId,
    videoFileSize: c.videoFileSize,
    videoMimeType: c.videoMimeType,
    videoFileName: c.videoFileName,
    videoDuration: c.videoDuration,
    videoPath: '',
    videoProgress: 0,
    stickerFileId: c.stickerFileId ?? 0,
    stickerFormat: c.stickerFormat ?? '',
    stickerPath: '',
    customEmojiId: c.customEmojiId ?? ''
  };
}
