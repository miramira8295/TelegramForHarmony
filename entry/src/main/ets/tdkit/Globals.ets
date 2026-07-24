import testNapi from 'libentry.so';
import { TdClient } from './TdClient';
import { AuthService, AuthStage } from './AuthService';
import { UserStore } from '../store/UserStore';
import { ChatStore } from '../store/ChatStore';
import { ChatEntry } from '../store/ChatEntry';
import { FileService } from '../services/FileService';
import { FolderStore } from '../store/FolderStore';
import { UnreadCountStore } from '../store/UnreadCountStore';
import { common } from '@kit.AbilityKit';
import { TdObject, TdRequest } from './TdTypes';
import {
  accountRegistry, TD_ACCOUNT_SWITCHING, TD_SESSION_EPOCH,
  TdAccountDirectories, TdAccountSummary
} from './AccountRegistry';

let client: TdClient | undefined = undefined;
let auth: AuthService | undefined = undefined;
let users: UserStore | undefined = undefined;
let chats: ChatStore | undefined = undefined;
let files: FileService | undefined = undefined;
let folders: FolderStore | undefined = undefined;
let unread: UnreadCountStore | undefined = undefined;
let baseFilesDir: string = '';
let activeTdFilesDirectory: string = '';
let switchInFlight: Promise<void> | null = null;

export function initTdKit(context: common.Context): void {
  if (client !== undefined) {
    return;
  }
  baseFilesDir = context.filesDir;
  accountRegistry.init(context);
  createRuntime(accountRegistry.activeSlotId());
}

function createRuntime(slotId: string): void {
  const directories: TdAccountDirectories = accountRegistry.directories(baseFilesDir, slotId);
  activeTdFilesDirectory = directories.filesDirectory;
  client = new TdClient({ init: testNapi.tdInit, send: testNapi.tdSend });
  auth = new AuthService(client, directories.databaseDirectory, directories.filesDirectory);
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
  const runtimeClient = client;
  const runtimeAuth = auth;
  runtimeAuth.onStageChange((stage: AuthStage): void => {
    if (stage === AuthStage.Ready && client === runtimeClient && auth === runtimeAuth) {
      refreshActiveAccountSummary(runtimeClient);
    }
  });
  client.start();
}

async function stopRuntime(): Promise<void> {
  const currentAuth = auth;
  const currentClient = client;
  if (currentAuth !== undefined) {
    await currentAuth.closeDatabase();
    currentAuth.dispose();
  }
  currentClient?.dispose();
  try {
    testNapi.tdDestroy();
  } catch (caught) {
    console.error(`Globals.stopRuntime tdDestroy failed: ${caught}`);
  }
  client = undefined;
  auth = undefined;
  users = undefined;
  chats = undefined;
  files = undefined;
  folders = undefined;
  unread = undefined;
}

function bumpSessionEpoch(): void {
  const previous = AppStorage.get<number>(TD_SESSION_EPOCH) ?? 0;
  AppStorage.setOrCreate(TD_SESSION_EPOCH, previous + 1);
}

async function restartOnSlot(slotId: string, previousSlotId: string): Promise<void> {
  AppStorage.setOrCreate(TD_ACCOUNT_SWITCHING, true);
  try {
    await stopRuntime();
    createRuntime(slotId);
    bumpSessionEpoch();
  } catch (caught) {
    const error = caught as Error;
    console.error(`Globals.restartOnSlot(${slotId}) failed: ${error.message}`);
    if (previousSlotId !== '' && accountRegistry.hasSlot(previousSlotId)) {
      accountRegistry.setActive(previousSlotId);
      if (client === undefined) {
        createRuntime(previousSlotId);
        bumpSessionEpoch();
      }
    }
    throw error;
  } finally {
    AppStorage.setOrCreate(TD_ACCOUNT_SWITCHING, false);
  }
}

export function switchTdAccount(slotId: string): Promise<void> {
  if (!accountRegistry.hasSlot(slotId) || slotId === accountRegistry.activeSlotId()) {
    return Promise.resolve();
  }
  if (switchInFlight !== null) { return switchInFlight; }
  const previousSlotId = accountRegistry.activeSlotId();
  accountRegistry.setActive(slotId);
  switchInFlight = restartOnSlot(slotId, previousSlotId).finally((): void => {
    switchInFlight = null;
  });
  return switchInFlight;
}

export function addTdAccount(): Promise<void> {
  if (switchInFlight !== null) { return switchInFlight; }
  const previousSlotId = accountRegistry.activeSlotId();
  const account = accountRegistry.addPendingAccount();
  switchInFlight = restartOnSlot(account.slotId, previousSlotId).finally((): void => {
    switchInFlight = null;
  });
  return switchInFlight;
}

export function returnToPreviousTdAccount(): Promise<void> {
  if (switchInFlight !== null) {
    const pendingSwitch = switchInFlight;
    return pendingSwitch.then((): Promise<void> => returnToPreviousTdAccount());
  }
  const pendingSlotId = accountRegistry.activeSlotId();
  const previousSlotId = accountRegistry.previousSlotForActivePending();
  if (previousSlotId === '') { return Promise.resolve(); }
  return switchTdAccount(previousSlotId).then((): void => {
    accountRegistry.discardPending(pendingSlotId);
  });
}

export function canReturnToPreviousTdAccount(): boolean {
  return accountRegistry.previousSlotForActivePending() !== '';
}

export function logoutCurrentTdAccount(): Promise<void> {
  if (switchInFlight !== null) { return switchInFlight; }
  const currentSlotId = accountRegistry.activeSlotId();
  const fallback = accountRegistry.all().find(
    (account: TdAccountSummary): boolean =>
      account.slotId !== currentSlotId && !account.pendingLogin && account.userId !== 0
  );
  const currentAuth = auth;
  if (currentAuth === undefined) {
    return Promise.reject(new Error('账号服务尚未就绪'));
  }
  AppStorage.setOrCreate(TD_ACCOUNT_SWITCHING, true);
  switchInFlight = currentAuth.logOut().then(async (): Promise<void> => {
    // Hide the logged-out session immediately. If the app is killed while the
    // next runtime is starting, it won't reappear as a usable account.
    accountRegistry.markLoggedOut(currentSlotId);
    if (fallback !== undefined) {
      accountRegistry.setActive(fallback.slotId);
      await restartOnSlot(fallback.slotId, currentSlotId);
      accountRegistry.removeAccount(currentSlotId);
    } else {
      // Recreate TDLib on the same (now logged-out) database so it emits
      // authorizationStateWaitPhoneNumber and the UI returns to login.
      await restartOnSlot(currentSlotId, currentSlotId);
    }
  }).finally((): void => {
    switchInFlight = null;
    AppStorage.setOrCreate(TD_ACCOUNT_SWITCHING, false);
  });
  return switchInFlight;
}

export function getTdAccounts(): TdAccountSummary[] {
  return accountRegistry.all();
}

export function removeDuplicateTdAccountsForActive(): number {
  return accountRegistry.removeDuplicatesForActive();
}

export function getActiveTdAccountSlot(): string {
  return accountRegistry.activeSlotId();
}

export function getTdFilesDirectory(): string {
  return activeTdFilesDirectory;
}

export function updateActiveTdAccountProfile(
  userId: number, name: string, phone: string, username: string, avatarPath: string
): void {
  accountRegistry.updateActiveProfile(userId, name, phone, username, avatarPath);
}

function refreshActiveAccountSummary(runtimeClient: TdClient): void {
  const slotBeforeRequest = accountRegistry.active();
  const request: TdRequest = { '@type': 'getMe' };
  runtimeClient.send(request).then((me: TdObject): void => {
    if (client !== runtimeClient) { return; }
    const firstName = (me['first_name'] as string | undefined) ?? '';
    const lastName = (me['last_name'] as string | undefined) ?? '';
    const name = `${firstName} ${lastName}`.trim();
    const phone = (me['phone_number'] as string | undefined) ?? '';
    const usernames = me['usernames'] as TdObject | undefined;
    const activeUsernames =
      (usernames?.['active_usernames'] as string[] | undefined) ?? [];
    const profilePhoto = me['profile_photo'] as TdObject | undefined;
    const small = profilePhoto?.['small'] as TdObject | undefined;
    const local = small?.['local'] as TdObject | undefined;
    const avatarPath = (local?.['path'] as string | undefined) ?? '';
    const userId = (me['id'] as number | undefined) ?? 0;
    const duplicateSlotId = slotBeforeRequest.pendingLogin
      ? accountRegistry.findOtherLoggedInSlot(userId, slotBeforeRequest.slotId)
      : '';
    if (duplicateSlotId !== '' &&
      accountRegistry.activeSlotId() === slotBeforeRequest.slotId &&
      auth !== undefined) {
      resolveDuplicateAccountLogin(
        slotBeforeRequest.slotId,
        duplicateSlotId,
        runtimeClient,
        auth,
        userId,
        name,
        phone,
        activeUsernames.length > 0 ? activeUsernames[0] : '',
        avatarPath
      );
      return;
    }
    accountRegistry.updateActiveProfile(
      userId,
      name,
      phone,
      activeUsernames.length > 0 ? activeUsernames[0] : '',
      avatarPath
    );
  }).catch((caught: Error): void => {
    console.error(`Globals.refreshActiveAccountSummary failed: ${caught.message}`);
  });
}

function resolveDuplicateAccountLogin(
  duplicateSlotId: string,
  existingSlotId: string,
  runtimeClient: TdClient,
  runtimeAuth: AuthService,
  userId: number,
  name: string,
  phone: string,
  username: string,
  avatarPath: string
): void {
  if (switchInFlight !== null) {
    const pendingSwitch = switchInFlight;
    pendingSwitch.then((): void => {
      resolveDuplicateAccountLogin(
        duplicateSlotId, existingSlotId, runtimeClient, runtimeAuth,
        userId, name, phone, username, avatarPath
      );
    }).catch((caught: Error): void => {
      console.error(`Globals.resolveDuplicateAccountLogin wait failed: ${caught.message}`);
    });
    return;
  }
  if (client !== runtimeClient || auth !== runtimeAuth ||
    accountRegistry.activeSlotId() !== duplicateSlotId) {
    return;
  }
  let logoutCompleted: boolean = false;
  AppStorage.setOrCreate(TD_ACCOUNT_SWITCHING, true);
  switchInFlight = runtimeAuth.logOut().then(async (): Promise<void> => {
    logoutCompleted = true;
    accountRegistry.markLoggedOut(duplicateSlotId);
    accountRegistry.setActive(existingSlotId);
    await restartOnSlot(existingSlotId, duplicateSlotId);
    accountRegistry.removeAccount(duplicateSlotId);
  }).catch((caught: Error): void => {
    console.error(`Globals.resolveDuplicateAccountLogin failed: ${caught.message}`);
    if (!logoutCompleted && client === runtimeClient &&
      accountRegistry.activeSlotId() === duplicateSlotId) {
      // Keep the freshly authenticated runtime usable if Telegram rejected
      // the cleanup request; it can be resolved manually from Devices.
      accountRegistry.updateActiveProfile(userId, name, phone, username, avatarPath);
    }
  }).finally((): void => {
    switchInFlight = null;
    AppStorage.setOrCreate(TD_ACCOUNT_SWITCHING, false);
  });
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
