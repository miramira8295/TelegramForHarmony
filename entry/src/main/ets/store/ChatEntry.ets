import { TdObject } from '../tdkit/TdTypes';

export interface ChatEntry {
  id: number;
  title: string;
  isMuted: boolean;
  unreadCount: number;
  lastMessageText: string;
  lastMessageDate: number;
  lastSenderName: string;
  photoFileId: number;
  avatarPath: string;
  initials: string;
  autoDeleteTime: number;
}

export function cloneEntry(e: ChatEntry): ChatEntry {
  return {
    id: e.id, title: e.title, isMuted: e.isMuted, unreadCount: e.unreadCount,
    lastMessageText: e.lastMessageText, lastMessageDate: e.lastMessageDate,
    lastSenderName: e.lastSenderName, photoFileId: e.photoFileId,
    avatarPath: e.avatarPath, initials: e.initials, autoDeleteTime: e.autoDeleteTime
  };
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
