import { TdClient } from '../tdkit/TdClient';
import { TdError, TdObject, TdRequest } from '../tdkit/TdTypes';
import { formatLastSeen } from '../util/formatLastSeen';
import { ContactItem } from './ContactsStore';

function chatIds(result: TdObject): number[] {
  return (result['chat_ids'] as number[] | undefined) ?? [];
}

async function runChatSearch(client: TdClient, type: string, query: string): Promise<number[]> {
  const request: TdRequest = { '@type': type };
  request['query'] = query;
  if (type === 'searchChatsOnServer') {
    request['limit'] = 30;
  }
  try {
    return chatIds(await client.send(request));
  } catch (error) {
    const caught = error as TdError;
    console.warn(`PublicUserSearch.${type} failed: ${caught.message}`);
    return [];
  }
}

function activeUsername(user: TdObject): string {
  const usernames = user['usernames'] as TdObject | undefined;
  const active = usernames !== undefined
    ? ((usernames['active_usernames'] as string[] | undefined) ?? [])
    : [];
  if (active.length > 0) {
    return active[0];
  }
  return (user['username'] as string | undefined) ?? '';
}

function avatarPath(user: TdObject, chat: TdObject): string {
  const profilePhoto = user['profile_photo'] as TdObject | undefined;
  const userSmall = profilePhoto !== undefined ? profilePhoto['small'] as TdObject | undefined : undefined;
  const userLocal = userSmall !== undefined ? userSmall['local'] as TdObject | undefined : undefined;
  const userPath = userLocal !== undefined ? ((userLocal['path'] as string | undefined) ?? '') : '';
  if (userPath !== '') {
    return userPath;
  }
  const chatPhoto = chat['photo'] as TdObject | undefined;
  const chatSmall = chatPhoto !== undefined ? chatPhoto['small'] as TdObject | undefined : undefined;
  const chatLocal = chatSmall !== undefined ? chatSmall['local'] as TdObject | undefined : undefined;
  return chatLocal !== undefined ? ((chatLocal['path'] as string | undefined) ?? '') : '';
}

async function resolvePrivateUser(client: TdClient, chatId: number): Promise<ContactItem | null> {
  try {
    const chatRequest: TdRequest = { '@type': 'getChat' };
    chatRequest['chat_id'] = chatId;
    const chat = await client.send(chatRequest);
    const type = chat['type'] as TdObject | undefined;
    if (type === undefined || type['@type'] !== 'chatTypePrivate') {
      return null;
    }
    const userId = (type['user_id'] as number | undefined) ?? 0;
    if (userId <= 0) {
      return null;
    }
    const userRequest: TdRequest = { '@type': 'getUser' };
    userRequest['user_id'] = userId;
    const user = await client.send(userRequest);
    const first = (user['first_name'] as string | undefined) ?? '';
    const last = (user['last_name'] as string | undefined) ?? '';
    const name = `${first}${last !== '' ? ` ${last}` : ''}`.trim();
    const username = activeUsername(user);
    const status = user['status'] as TdObject | undefined;
    const online = status !== undefined && status['@type'] === 'userStatusOnline';
    const statusText = username !== ''
      ? `@${username}`
      : formatLastSeen(status, Math.floor(Date.now() / 1000));
    return {
      id: userId,
      name: name !== '' ? name : (username !== '' ? username : '未命名用户'),
      initials: name !== '' ? name.substring(0, 1).toUpperCase() : '?',
      avatarPath: avatarPath(user, chat),
      statusText: statusText,
      online: online,
      sortKey: online ? Number.MAX_SAFE_INTEGER : 0
    };
  } catch (error) {
    const caught = error as TdError;
    console.warn(`PublicUserSearch.resolvePrivateUser(${chatId}) failed: ${caught.message}`);
    return null;
  }
}

// Telegram can only discover strangers who have a public username/searchable
// chat. Combine public search with server-side chat search, then keep private
// user chats and expose them in the same shape as the local contact list.
export async function searchPublicUsers(client: TdClient, rawQuery: string): Promise<ContactItem[]> {
  const query = rawQuery.trim().replace(/^@/, '');
  if (query.length < 2) {
    return [];
  }
  const publicIds = await runChatSearch(client, 'searchPublicChats', query);
  const serverIds = await runChatSearch(client, 'searchChatsOnServer', query);
  const ids: number[] = [];
  for (const id of [...publicIds, ...serverIds]) {
    if (ids.indexOf(id) < 0) {
      ids.push(id);
    }
  }
  const users: ContactItem[] = [];
  for (const id of ids.slice(0, 30)) {
    const user = await resolvePrivateUser(client, id);
    if (user !== null && !users.some((item: ContactItem): boolean => item.id === user.id)) {
      users.push(user);
    }
  }
  return users;
}
