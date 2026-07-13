import { TdClient } from '../tdkit/TdClient';
import { TdObject, TdRequest, TdError } from '../tdkit/TdTypes';

const DL_PRIORITY: number = 1;
const PAGE_LIMIT: number = 50;

export interface CallItem {
  msgId: number;
  chatId: number;
  name: string;
  initials: string;
  avatarPath: string;
  colorSeed: number;
  timeLabel: string; // "2024年1月15日 06:58"
  outgoing: boolean;
  missed: boolean;   // incoming call that was missed/declined
}

type Listener = () => void;

// "2024年1月15日 06:58" from a unix timestamp (seconds).
export function formatCallTime(ts: number): string {
  const d = new Date(ts * 1000);
  const hh = `${d.getHours()}`.padStart(2, '0');
  const mm = `${d.getMinutes()}`.padStart(2, '0');
  return `${d.getFullYear()}年${d.getMonth() + 1}月${d.getDate()}日 ${hh}:${mm}`;
}

// Backing store for the recent-calls page: searchCallMessages pages through
// the call history; each row resolves its chat title/avatar via getChat.
export class CallsStore {
  private client: TdClient;
  private listeners: Listener[] = [];
  private unsubs: Array<() => void> = [];
  private fileApply: Map<number, (path: string) => void> = new Map();
  private nextOffset: string = '';
  private loadingPage: boolean = false;

  calls: CallItem[] = [];
  loading: boolean = true;   // first page still in flight
  hasMore: boolean = false;

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
    this.loadMore();
  }

  close(): void {
    for (const un of this.unsubs) {
      un();
    }
    this.unsubs = [];
    this.listeners = [];
  }

  loadMore(): void {
    if (this.loadingPage) {
      return;
    }
    this.loadingPage = true;
    const req: TdRequest = { '@type': 'searchCallMessages' };
    req['offset'] = this.nextOffset;
    req['limit'] = PAGE_LIMIT;
    req['only_missed'] = false;
    this.client.send(req).then((res: TdObject) => {
      const msgs = (res['messages'] as TdObject[] | undefined) ?? [];
      this.nextOffset = (res['next_offset'] as string | undefined) ?? '';
      this.hasMore = this.nextOffset !== '' && msgs.length > 0;
      for (const m of msgs) {
        this.appendCall(m);
      }
      this.loading = false;
      this.loadingPage = false;
      this.notify();
    }).catch((e: TdError) => {
      console.error(`CallsStore.searchCallMessages failed: ${e.message}`);
      this.loading = false;
      this.loadingPage = false;
      this.hasMore = false;
      this.notify();
    });
  }

  private appendCall(m: TdObject): void {
    const msgId = (m['id'] as number | undefined) ?? 0;
    const chatId = (m['chat_id'] as number | undefined) ?? 0;
    if (msgId === 0 || chatId === 0) {
      return;
    }
    const outgoing = (m['is_outgoing'] as boolean | undefined) ?? false;
    const content = m['content'] as TdObject | undefined;
    const reason = content !== undefined ? (content['discard_reason'] as TdObject | undefined) : undefined;
    const reasonName = reason !== undefined ? ((reason['@type'] as string | undefined) ?? '') : '';
    const missed = !outgoing
      && (reasonName === 'callDiscardReasonMissed' || reasonName === 'callDiscardReasonDeclined');
    const item: CallItem = {
      msgId,
      chatId,
      name: '',
      initials: '?',
      avatarPath: '',
      colorSeed: chatId,
      timeLabel: formatCallTime((m['date'] as number | undefined) ?? 0),
      outgoing,
      missed
    };
    this.calls = [...this.calls, item];
    this.resolveChat(chatId, msgId);
  }

  private resolveChat(chatId: number, msgId: number): void {
    const req: TdRequest = { '@type': 'getChat' };
    req['chat_id'] = chatId;
    this.client.send(req).then((chat: TdObject) => {
      // Deleted accounts come back with an empty title — label them the way
      // official clients do.
      const rawTitle = (chat['title'] as string | undefined) ?? '';
      const title = rawTitle !== '' ? rawTitle : '已删除账户';
      this.patch(msgId, (c: CallItem): CallItem => ({
        msgId: c.msgId, chatId: c.chatId,
        name: title, initials: rawTitle.length > 0 ? rawTitle.substring(0, 1).toUpperCase() : '?',
        avatarPath: c.avatarPath, colorSeed: c.colorSeed,
        timeLabel: c.timeLabel, outgoing: c.outgoing, missed: c.missed
      }));
      const photo = chat['photo'] as TdObject | undefined;
      const small = photo !== undefined ? (photo['small'] as TdObject | undefined) : undefined;
      const fileId = small !== undefined ? ((small['id'] as number | undefined) ?? 0) : 0;
      this.download(fileId, (p: string) => {
        this.patch(msgId, (c: CallItem): CallItem => ({
          msgId: c.msgId, chatId: c.chatId,
          name: c.name, initials: c.initials,
          avatarPath: p, colorSeed: c.colorSeed,
          timeLabel: c.timeLabel, outgoing: c.outgoing, missed: c.missed
        }));
      });
    }).catch((e: TdError) => {
      console.error(`CallsStore.getChat(${chatId}) failed: ${e.message}`);
    });
  }

  private patch(msgId: number, fn: (c: CallItem) => CallItem): void {
    this.calls = this.calls.map((c: CallItem): CallItem => c.msgId === msgId ? fn(c) : c);
    this.notify();
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
      console.error(`CallsStore.downloadFile failed: ${e.message}`);
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
