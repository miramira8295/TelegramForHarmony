import { getTdClient } from '../tdkit/Globals';
import { TdObject, TdRequest } from '../tdkit/TdTypes';

// Folder CRUD. editChatFolder replaces the whole folder object, so every field
// we don't edit — icon, colour, shareable flag, pinned chats — has to be read
// first and written back, or saving a rename would quietly reset them.

export interface FolderData {
  id: number;              // 0 = not created yet
  name: string;
  iconName: string;
  colorId: number;
  isShareable: boolean;
  pinnedChatIds: number[];
  includedChatIds: number[];
  excludedChatIds: number[];
  excludeMuted: boolean;
  excludeRead: boolean;
  excludeArchived: boolean;
  includeContacts: boolean;
  includeNonContacts: boolean;
  includeBots: boolean;
  includeGroups: boolean;
  includeChannels: boolean;
}

export function emptyFolder(): FolderData {
  return {
    id: 0, name: '', iconName: '', colorId: -1, isShareable: false,
    pinnedChatIds: [], includedChatIds: [], excludedChatIds: [],
    excludeMuted: false, excludeRead: false, excludeArchived: false,
    includeContacts: false, includeNonContacts: false, includeBots: false,
    includeGroups: false, includeChannels: false
  };
}

function nameOf(folder: TdObject): string {
  const name = folder['name'] as TdObject | undefined;
  if (name === undefined) {
    return '';
  }
  const text = name['text'] as TdObject | undefined;
  return text !== undefined ? ((text['text'] as string | undefined) ?? '') : '';
}

function toTdFolder(f: FolderData): TdObject {
  const text: TdObject = { '@type': 'formattedText' };
  text['text'] = f.name;
  text['entities'] = [];
  const name: TdObject = { '@type': 'chatFolderName' };
  name['text'] = text;
  name['animate_custom_emoji'] = false;
  const icon: TdObject = { '@type': 'chatFolderIcon' };
  icon['name'] = f.iconName;

  const out: TdObject = { '@type': 'chatFolder' };
  out['name'] = name;
  if (f.iconName !== '') {
    out['icon'] = icon;
  }
  out['color_id'] = f.colorId;
  out['is_shareable'] = f.isShareable;
  out['pinned_chat_ids'] = f.pinnedChatIds;
  out['included_chat_ids'] = f.includedChatIds;
  out['excluded_chat_ids'] = f.excludedChatIds;
  out['exclude_muted'] = f.excludeMuted;
  out['exclude_read'] = f.excludeRead;
  out['exclude_archived'] = f.excludeArchived;
  out['include_contacts'] = f.includeContacts;
  out['include_non_contacts'] = f.includeNonContacts;
  out['include_bots'] = f.includeBots;
  out['include_groups'] = f.includeGroups;
  out['include_channels'] = f.includeChannels;
  return out;
}

export async function getFolder(id: number): Promise<FolderData> {
  const req: TdRequest = { '@type': 'getChatFolder' };
  req['chat_folder_id'] = id;
  const f = await getTdClient().send(req);
  const icon = f['icon'] as TdObject | undefined;
  return {
    id,
    name: nameOf(f),
    iconName: icon !== undefined ? ((icon['name'] as string | undefined) ?? '') : '',
    colorId: (f['color_id'] as number | undefined) ?? -1,
    isShareable: (f['is_shareable'] as boolean | undefined) ?? false,
    pinnedChatIds: (f['pinned_chat_ids'] as number[] | undefined) ?? [],
    includedChatIds: (f['included_chat_ids'] as number[] | undefined) ?? [],
    excludedChatIds: (f['excluded_chat_ids'] as number[] | undefined) ?? [],
    excludeMuted: (f['exclude_muted'] as boolean | undefined) ?? false,
    excludeRead: (f['exclude_read'] as boolean | undefined) ?? false,
    excludeArchived: (f['exclude_archived'] as boolean | undefined) ?? false,
    includeContacts: (f['include_contacts'] as boolean | undefined) ?? false,
    includeNonContacts: (f['include_non_contacts'] as boolean | undefined) ?? false,
    includeBots: (f['include_bots'] as boolean | undefined) ?? false,
    includeGroups: (f['include_groups'] as boolean | undefined) ?? false,
    includeChannels: (f['include_channels'] as boolean | undefined) ?? false
  };
}

// id === 0 creates, anything else edits in place.
export async function saveFolder(f: FolderData): Promise<number> {
  if (f.id === 0) {
    const req: TdRequest = { '@type': 'createChatFolder' };
    req['folder'] = toTdFolder(f);
    const info = await getTdClient().send(req);
    return (info['id'] as number | undefined) ?? 0;
  }
  const req: TdRequest = { '@type': 'editChatFolder' };
  req['chat_folder_id'] = f.id;
  req['folder'] = toTdFolder(f);
  await getTdClient().send(req);
  return f.id;
}

// The folder is removed; the chats in it stay (leave_chat_ids empty).
export async function deleteFolder(id: number): Promise<void> {
  const req: TdRequest = { '@type': 'deleteChatFolder' };
  req['chat_folder_id'] = id;
  req['leave_chat_ids'] = [];
  await getTdClient().send(req);
}

// main_chat_list_position 0 keeps 全部聊天 first, like the official clients.
export async function reorderFolders(ids: number[]): Promise<void> {
  const req: TdRequest = { '@type': 'reorderChatFolders' };
  req['chat_folder_ids'] = ids;
  req['main_chat_list_position'] = 0;
  await getTdClient().send(req);
}

// How many chats the folder actually shows — the type filters make this more
// than just includedChatIds.length.
export async function folderChatCount(f: FolderData): Promise<number> {
  const req: TdRequest = { '@type': 'getChatFolderChatCount' };
  req['folder'] = toTdFolder(f);
  const res = await getTdClient().send(req);
  return (res['count'] as number | undefined) ?? 0;
}
