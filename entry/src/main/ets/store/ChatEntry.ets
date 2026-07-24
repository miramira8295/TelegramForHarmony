import { TdObject } from '../tdkit/TdTypes';

// Which TDLib chat kind this is — decides whether the context menu offers
// 退出群组 / 退出频道 / 删除聊天, and whether "清空聊天记录" is even possible.
export type ChatKind = 'private' | 'secret' | 'basicGroup' | 'supergroup' | 'channel';

export interface ChatEntry {
  id: number;
  title: string;
  isMuted: boolean;
  unreadCount: number;
  lastMessageText: string;
  lastMessageDate: number;
  lastMessageId: number;   // newest message — 标记为已读 reads up to it
  lastSenderName: string;
  photoFileId: number;
  avatarPath: string;
  initials: string;
  autoDeleteTime: number;
  kind: ChatKind;
  isMarkedUnread: boolean; // manually flagged unread (unread_count may be 0)
  liveGroupCallId: number; // current video chat/group call bound to this chat
  isLive: boolean;        // true only after groupCall.is_active is confirmed
  isRtmpLive: boolean;
}

export function cloneEntry(e: ChatEntry): ChatEntry {
  return {
    id: e.id, title: e.title, isMuted: e.isMuted, unreadCount: e.unreadCount,
    lastMessageText: e.lastMessageText, lastMessageDate: e.lastMessageDate,
    lastMessageId: e.lastMessageId,
    lastSenderName: e.lastSenderName, photoFileId: e.photoFileId,
    avatarPath: e.avatarPath, initials: e.initials, autoDeleteTime: e.autoDeleteTime,
    kind: e.kind, isMarkedUnread: e.isMarkedUnread,
    liveGroupCallId: e.liveGroupCallId, isLive: e.isLive, isRtmpLive: e.isRtmpLive
  };
}

// A supergroup with is_channel set is a broadcast channel; without it, a group.
export function chatKindOf(type: TdObject | undefined): ChatKind {
  if (type === undefined) {
    return 'private';
  }
  const t = (type['@type'] as string | undefined) ?? '';
  if (t === 'chatTypeSupergroup') {
    return ((type['is_channel'] as boolean | undefined) ?? false) ? 'channel' : 'supergroup';
  }
  if (t === 'chatTypeBasicGroup') {
    return 'basicGroup';
  }
  if (t === 'chatTypeSecret') {
    return 'secret';
  }
  return 'private';
}

export interface PositionInfo {
  order: string;
  isPinned: boolean;
}

export function computeInitials(title: string): string {
  const trimmed = title.trim();
  if (trimmed === '') {
    return '?';
  }
  const words = trimmed.split(/\s+/);
  if (words.length >= 2) {
    return (words[0].charAt(0) + words[1].charAt(0)).toUpperCase();
  }
  return words[0].charAt(0).toUpperCase();
}

// Descending order for non-negative int64 stored as string.
export function compareOrderDesc(a: string, b: string): number {
  if (a.length !== b.length) {
    return b.length - a.length;
  }
  if (a === b) {
    return 0;
  }
  return a < b ? 1 : -1;
}

export function isMutedFrom(notificationSettings: TdObject | undefined): boolean {
  if (notificationSettings === undefined) {
    return false;
  }
  const muteFor = (notificationSettings['mute_for'] as number | undefined) ?? 0;
  return muteFor > 0;
}
