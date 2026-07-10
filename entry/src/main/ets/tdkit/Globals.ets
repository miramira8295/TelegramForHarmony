import testNapi from 'libentry.so';
import { TdClient } from './TdClient';
import { AuthService } from './AuthService';
import { UserStore } from '../store/UserStore';
import { ChatStore } from '../store/ChatStore';
import { ChatEntry } from '../store/ChatEntry';
import { FileService } from '../services/FileService';
import { FolderStore } from '../store/FolderStore';
import { UnreadCountStore } from '../store/UnreadCountStore';

let client: TdClient | undefined = undefined;
let auth: AuthService | undefined = undefined;
let users: UserStore | undefined = undefined;
let chats: ChatStore | undefined = undefined;
let files: FileService | undefined = undefined;
let folders: FolderStore | undefined = undefined;
let unread: UnreadCountStore | undefined = undefined;

export function initTdKit(filesDir: string): void {
  if (client !== undefined) {
    return;
  }
  client = new TdClient({ init: testNapi.tdInit, send: testNapi.tdSend });
  auth = new AuthService(client, filesDir);
  users = new UserStore(client);
  chats = new ChatStore(client, users);
  files = new FileService(client, chats);
  folders = new FolderStore(client);
  unread = new UnreadCountStore(client);
  const fileService = files;
  const chatStore = chats;
  // Request avatars for EVERY cached chat, not just the main list — otherwise
  // chats surfaced only under a folder tab never get their photo downloaded.
  chatStore.subscribe(() => {
    for (const e of chatStore.allEntries()) {
      if (e.photoFileId !== 0 && e.avatarPath === '') {
        fileService.requestAvatar(e.id, e.photoFileId);
      }
    }
  });
  client.start();
}

export function isReady(): boolean {
  return client !== undefined;
}

export function getTdClient(): TdClient {
  return client!;
}

export function getAuthService(): AuthService {
  return auth!;
}

export function getChatStore(): ChatStore {
  return chats!;
}

export function getFileService(): FileService {
  return files!;
}

export function getFolderStore(): FolderStore {
  return folders!;
}

export function getUnreadCountStore(): UnreadCountStore {
  return unread!;
}

export function getUserStore(): UserStore {
  return users!;
}
