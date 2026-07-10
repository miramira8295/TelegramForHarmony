import { TdClient } from '../tdkit/TdClient';
import { TdObject, TdRequest, TdError } from '../tdkit/TdTypes';

// Data sources for the chat input's '@' mention and '/' command suggestion
// panels. Pure request helpers — no state; ChatPage owns filtering/UI.

export interface MentionItem {
  userId: number;
  name: string;     // display name (first + last)
  username: string; // '' when the member has no public username
}

export interface CommandItem {
  command: string;     // without the leading '/'
  description: string;
}

const MENTION_LIMIT: number = 12;
const BOT_LIMIT: number = 10;

function displayNameOf(user: TdObject): string {
  const first = (user['first_name'] as string | undefined) ?? '';
  const last = (user['last_name'] as string | undefined) ?? '';
  return `${first} ${last}`.trim();
}

function usernameOf(user: TdObject): string {
  const u = user['usernames'] as TdObject | undefined;
  if (u === undefined) {
    return '';
  }
  const editable = (u['editable_username'] as string | undefined) ?? '';
  if (editable !== '') {
    return editable;
  }
  const active = u['active_usernames'] as string[] | undefined;
  return active !== undefined && active.length > 0 ? active[0] : '';
}

function memberUserIds(res: TdObject): number[] {
  const members = res['members'] as TdObject[] | undefined;
  const ids: number[] = [];
  if (members === undefined) {
    return ids;
  }
  for (const m of members) {
    const sender = m['member_id'] as TdObject | undefined;
    if (sender === undefined || (sender['@type'] as string | undefined) !== 'messageSenderUser') {
      continue;
    }
    const uid = (sender['user_id'] as number | undefined) ?? 0;
    if (uid > 0) {
      ids.push(uid);
    }
  }
  return ids;
}

function getUser(client: TdClient, userId: number): Promise<TdObject> {
  const req: TdRequest = { '@type': 'getUser' };
  req['user_id'] = userId;
  return client.send(req);
}

// Group members matching `query` (server-side prefix search on name/username).
export function searchMentions(client: TdClient, chatId: number, query: string): Promise<MentionItem[]> {
  const req: TdRequest = { '@type': 'searchChatMembers' };
  req['chat_id'] = chatId;
  req['query'] = query;
  req['limit'] = MENTION_LIMIT;
  return client.send(req).then((res: TdObject) => {
    const ids = memberUserIds(res);
    const fetches: Array<Promise<TdObject>> = ids.map((uid: number) => getUser(client, uid));
    return Promise.all(fetches).then((users: TdObject[]) => {
      const items: MentionItem[] = [];
      for (let i = 0; i < users.length; i++) {
        const name = displayNameOf(users[i]);
        const t = users[i]['type'] as TdObject | undefined;
        const typeName = t !== undefined ? ((t['@type'] as string | undefined) ?? '') : '';
        if (name === '' || typeName === 'userTypeDeleted') {
          continue;
        }
        items.push({ userId: ids[i], name, username: usernameOf(users[i]) });
      }
      return items;
    });
  }).catch((e: TdError) => {
    console.error(`searchMentions failed: ${e.message}`);
    const empty: MentionItem[] = [];
    return empty;
  });
}

function commandsOfFullInfo(full: TdObject): CommandItem[] {
  const items: CommandItem[] = [];
  const botInfo = full['bot_info'] as TdObject | undefined;
  const cmds = botInfo !== undefined ? (botInfo['commands'] as TdObject[] | undefined) : undefined;
  if (cmds === undefined) {
    return items;
  }
  for (const c of cmds) {
    const command = (c['command'] as string | undefined) ?? '';
    if (command !== '') {
      items.push({ command, description: (c['description'] as string | undefined) ?? '' });
    }
  }
  return items;
}

function getFullInfoCommands(client: TdClient, userId: number): Promise<CommandItem[]> {
  const req: TdRequest = { '@type': 'getUserFullInfo' };
  req['user_id'] = userId;
  return client.send(req).then((full: TdObject) => commandsOfFullInfo(full))
    .catch((e: TdError) => {
      console.error(`getUserFullInfo(${userId}) for commands failed: ${e.message}`);
      const empty: CommandItem[] = [];
      return empty;
    });
}

// Bot commands available in this chat. Private bot chat: the peer's own
// commands. Groups: commands of every bot member, merged.
export function loadBotCommands(client: TdClient, chatId: number, peerUserId: number): Promise<CommandItem[]> {
  if (peerUserId > 0) {
    return getFullInfoCommands(client, peerUserId);
  }
  const req: TdRequest = { '@type': 'searchChatMembers' };
  req['chat_id'] = chatId;
  req['query'] = '';
  req['limit'] = BOT_LIMIT;
  req['filter'] = { '@type': 'chatMembersFilterBots' } as TdObject;
  return client.send(req).then((res: TdObject) => {
    const ids = memberUserIds(res);
    const fetches: Array<Promise<CommandItem[]>> = ids.map((uid: number) => getFullInfoCommands(client, uid));
    return Promise.all(fetches).then((lists: CommandItem[][]) => {
      const merged: CommandItem[] = [];
      for (const list of lists) {
        for (const item of list) {
          merged.push(item);
        }
      }
      return merged;
    });
  }).catch((e: TdError) => {
    console.error(`loadBotCommands failed: ${e.message}`);
    const empty: CommandItem[] = [];
    return empty;
  });
}
