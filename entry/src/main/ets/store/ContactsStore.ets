import { TdClient } from '../tdkit/TdClient';
import { TdObject, TdRequest, TdError } from '../tdkit/TdTypes';
import { formatLastSeen } from '../util/formatLastSeen';

const DL_PRIORITY: number = 1;

export interface ContactItem {
  id: number;
  name: string;
  initials: string;
  avatarPath: string;
  statusText: string;
  online: boolean;
  sortKey: number; // was_online ts for offline; huge for online; small negatives for coarse buckets
}

type Listener = () => void;

// Backing store for the contacts tab: getContacts → per-user name/status/avatar,
// sorted by last-seen (online first), kept live via updateUserStatus.
export class ContactsStore {
  private client: TdClient;
  private listeners: Listener[] = [];
  private unsubs: Array<() => void> = [];
  private fileApply: Map<number, (path: string) => void> = new Map();
  private byId: Map<number, ContactItem> = new Map();

  contacts: ContactItem[] = [];
  loading: boolean = true;

  constructor(client: TdClient) {
    this.client = client;
  }

  subscribe(l: Listener): () => void {
    this.listeners = [...this.listeners, l];
    l();
    return (): void => { this.listeners = this.listeners.filter((x: Listener) => x !== l); };
  }

  private notify(): void {
    for (const l of this.listeners) {
      l();
    }
  }

  open(): void {
    this.unsubs.push(this.client.onUpdate('updateFile', (u: TdObject) => {
      const f = u['file'] as TdObject | undefined;
      if (f !== undefined) {
        this.applyFile(f);
      }
    }));
    this.unsubs.push(this.client.onUpdate('updateUserStatus', (u: TdObject) => {
      const uid = u['user_id'] as number | undefined;
      if (uid !== undefined && this.byId.has(uid)) {
        this.updateStatus(uid, u['status'] as TdObject | undefined);
      }
    }));
    this.loadContacts();
  }

  close(): void {
    for (const un of this.unsubs) {
      un();
    }
    this.unsubs = [];
    this.listeners = [];
  }

  private loadContacts(): void {
    const req: TdRequest = { '@type': 'getContacts' };
    this.client.send(req).then((res: TdObject) => {
      const ids = (res['user_ids'] as number[] | undefined) ?? [];
      this.loading = false;
      for (const id of ids) {
        this.loadUser(id);
      }
      this.rebuild();
      this.notify();
    }).catch((e: TdError) => {
      console.error(`ContactsStore.getContacts failed: ${e.message}`);
      this.loading = false;
      this.notify();
    });
  }

  private loadUser(id: number): void {
    const req: TdRequest = { '@type': 'getUser' };
    req['user_id'] = id;
    this.client.send(req).then((user: TdObject) => {
      const first = (user['first_name'] as string | undefined) ?? '';
      const last = (user['last_name'] as string | undefined) ?? '';
      const name = `${first}${last !== '' ? ' ' + last : ''}`.trim();
      const status = user['status'] as TdObject | undefined;
      const nowSec = Math.floor(Date.now() / 1000);
      const item: ContactItem = {
        id,
        name: name !== '' ? name : '未命名',
        initials: name.length > 0 ? name.substring(0, 1).toUpperCase() : '?',
        avatarPath: '',
        statusText: formatLastSeen(status, nowSec),
        online: (status !== undefined) && (status['@type'] === 'userStatusOnline'),
        sortKey: this.sortKey(status)
      };
      this.byId.set(id, item);
      const photo = user['profile_photo'] as TdObject | undefined;
      const small = photo !== undefined ? (photo['small'] as TdObject | undefined) : undefined;
      const fileId = small !== undefined ? ((small['id'] as number | undefined) ?? 0) : 0;
      this.download(fileId, (p: string) => {
        const it = this.byId.get(id);
        if (it !== undefined) {
          it.avatarPath = p;
          this.rebuild();
          this.notify();
        }
      });
      this.rebuild();
      this.notify();
    }).catch((e: TdError) => {
      console.error(`ContactsStore.getUser failed: ${e.message}`);
    });
  }

  private updateStatus(id: number, status: TdObject | undefined): void {
    const it = this.byId.get(id);
    if (it === undefined) {
      return;
    }
    it.statusText = formatLastSeen(status, Math.floor(Date.now() / 1000));
    it.online = (status !== undefined) && (status['@type'] === 'userStatusOnline');
    it.sortKey = this.sortKey(status);
    this.rebuild();
    this.notify();
  }

  private sortKey(status: TdObject | undefined): number {
    if (status === undefined) {
      return -4;
    }
    const type = status['@type'] as string | undefined;
    if (type === 'userStatusOnline') {
      return Number.MAX_SAFE_INTEGER;
    }
    if (type === 'userStatusOffline') {
      return (status['was_online'] as number | undefined) ?? 0;
    }
    if (type === 'userStatusRecently') {
      return -1;
    }
    if (type === 'userStatusLastWeek') {
      return -2;
    }
    if (type === 'userStatusLastMonth') {
      return -3;
    }
    return -4;
  }

  // Rebuild the sorted array with a fresh identity so ArkUI re-renders the list.
  private rebuild(): void {
    const arr: ContactItem[] = [];
    this.byId.forEach((v: ContactItem) => { arr.push(v); });
    arr.sort((a: ContactItem, b: ContactItem) => b.sortKey - a.sortKey);
    this.contacts = arr;
  }

  private download(fileId: number, apply: (path: string) => void): void {
    if (fileId <= 0) {
      return;
    }
    this.fileApply.set(fileId, apply);
    const req: TdRequest = { '@type': 'downloadFile' };
    req['file_id'] = fileId;
    req['priority'] = DL_PRIORITY;
    this.client.send(req).then((f: TdObject) => this.applyFile(f)).catch((e: TdError) => {
      console.error(`ContactsStore.downloadFile failed: ${e.message}`);
    });
  }

  private applyFile(file: TdObject): void {
    const id = file['id'] as number | undefined;
    if (id === undefined) {
      return;
    }
    const apply = this.fileApply.get(id);
    if (apply === undefined) {
      return;
    }
    const local = file['local'] as TdObject | undefined;
    const done = local !== undefined ? ((local['is_downloading_completed'] as boolean | undefined) ?? false) : false;
    const path = local !== undefined ? ((local['path'] as string | undefined) ?? '') : '';
    if (done && path !== '') {
      apply(path);
    }
  }
}
