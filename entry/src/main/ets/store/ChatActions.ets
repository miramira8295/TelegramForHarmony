import { promptAction } from '@kit.ArkUI';
import { getTdClient } from '../tdkit/Globals';
import { TdObject, TdRequest, TdError } from '../tdkit/TdTypes';
import { chatListOf } from './ListKey';
import { ChatKind } from './ChatEntry';

// Every chat-list context-menu action, as a plain TDLib call. The UI never
// mutates the store directly — TDLib echoes each change back as an update
// (updateChatPosition / updateChatNotificationSettings / ...) and ChatStore
// re-renders from that, so the list stays consistent with the server.

// TDLib treats "muted forever" as this sentinel, NOT 0xFFFFFFFF (which
// overflows int32 and is rejected).
export const MUTE_FOREVER: number = 2147483647;

export interface MuteOption {
  label: string;
  seconds: number;
}

export const MUTE_OPTIONS: MuteOption[] = [
  { label: '静音 1 小时', seconds: 3600 },
  { label: '静音 8 小时', seconds: 8 * 3600 },
  { label: '静音 2 天', seconds: 2 * 24 * 3600 },
  { label: '永久静音', seconds: MUTE_FOREVER }
];

function fail(what: string, e: TdError): void {
  console.error(`ChatActions.${what} failed: ${e.message}`);
  promptAction.showToast({ message: `操作失败：${e.message}`, duration: 2000 });
}

export function togglePin(listKey: string, chatId: number, pinned: boolean): void {
  const req: TdRequest = { '@type': 'toggleChatIsPinned' };
  req['chat_list'] = chatListOf(listKey);
  req['chat_id'] = chatId;
  req['is_pinned'] = pinned;
  getTdClient().send(req).catch((e: TdError) => { fail('togglePin', e); });
}

// seconds = 0 unmutes; MUTE_FOREVER mutes indefinitely.
export function setMute(chatId: number, seconds: number): void {
  const settings: TdObject = { '@type': 'chatNotificationSettings' };
  settings['use_default_mute_for'] = false;
  settings['mute_for'] = seconds;
  const req: TdRequest = { '@type': 'setChatNotificationSettings' };
  req['chat_id'] = chatId;
  req['notification_settings'] = settings;
  getTdClient().send(req).catch((e: TdError) => { fail('setMute', e); });
}

// Reads everything up to the newest message and clears a manual unread flag.
export function markAsRead(chatId: number, lastMessageId: number): void {
  const client = getTdClient();
  if (lastMessageId !== 0) {
    const view: TdRequest = { '@type': 'viewMessages' };
    view['chat_id'] = chatId;
    view['message_ids'] = [lastMessageId];
    view['force_read'] = true;
    client.send(view).catch((e: TdError) => { fail('markAsRead', e); });
  }
  markUnread(chatId, false);
}

export function markUnread(chatId: number, unread: boolean): void {
  const req: TdRequest = { '@type': 'toggleChatIsMarkedAsUnread' };
  req['chat_id'] = chatId;
  req['is_marked_as_unread'] = unread;
  getTdClient().send(req).catch((e: TdError) => { fail('markUnread', e); });
}

export function setArchived(chatId: number, archived: boolean): void {
  const req: TdRequest = { '@type': 'addChatToList' };
  req['chat_id'] = chatId;
  req['chat_list'] = chatListOf(archived ? 'archive' : 'main');
  getTdClient().send(req).catch((e: TdError) => { fail('setArchived', e); });
}

// TDLib has no "add chat to folder" call: the whole folder must be read,
// edited and written back.
export async function setInFolder(folderId: number, chatId: number, include: boolean): Promise<void> {
  const client = getTdClient();
  try {
    const get: TdRequest = { '@type': 'getChatFolder' };
    get['chat_folder_id'] = folderId;
    const folder = await client.send(get);
    const included = (folder['included_chat_ids'] as number[] | undefined) ?? [];
    const next = include
      ? (included.includes(chatId) ? included : [...included, chatId])
      : included.filter((id: number) => id !== chatId);
    // Removing a chat also has to drop it from the pinned list, or TDLib
    // rejects the edit (a pinned chat must be an included one).
    const pinned = (folder['pinned_chat_ids'] as number[] | undefined) ?? [];
    const nextFolder: TdObject = folder;
    nextFolder['included_chat_ids'] = next;
    if (!include) {
      nextFolder['pinned_chat_ids'] = pinned.filter((id: number) => id !== chatId);
    }
    const edit: TdRequest = { '@type': 'editChatFolder' };
    edit['chat_folder_id'] = folderId;
    edit['folder'] = nextFolder;
    await client.send(edit);
    promptAction.showToast({ message: include ? '已添加到文件夹' : '已移出文件夹', duration: 1500 });
  } catch (e) {
    fail('setInFolder', e as TdError);
  }
}

// revoke: also delete the history for the other side (private chats only).
export function clearHistory(chatId: number, revoke: boolean): void {
  const req: TdRequest = { '@type': 'deleteChatHistory' };
  req['chat_id'] = chatId;
  req['remove_from_chat_list'] = false;
  req['revoke'] = revoke;
  getTdClient().send(req).catch((e: TdError) => { fail('clearHistory', e); });
}

// Groups/channels are left; private and secret chats are deleted from the list.
export function leaveOrDeleteChat(chatId: number, kind: ChatKind): void {
  const client = getTdClient();
  if (kind === 'basicGroup' || kind === 'supergroup' || kind === 'channel') {
    const req: TdRequest = { '@type': 'leaveChat' };
    req['chat_id'] = chatId;
    client.send(req).catch((e: TdError) => { fail('leaveChat', e); });
    return;
  }
  const req: TdRequest = { '@type': 'deleteChatHistory' };
  req['chat_id'] = chatId;
  req['remove_from_chat_list'] = true;
  req['revoke'] = false;
  client.send(req).catch((e: TdError) => { fail('deleteChat', e); });
}

// Menu label for the destructive last item, by chat kind.
export function leaveLabel(kind: ChatKind): string {
  if (kind === 'channel') {
    return '退出频道';
  }
  if (kind === 'basicGroup' || kind === 'supergroup') {
    return '退出群组';
  }
  return '删除聊天';
}
