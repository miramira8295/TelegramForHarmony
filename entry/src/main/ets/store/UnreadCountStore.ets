import { TdClient } from '../tdkit/TdClient';
import { TdObject } from '../tdkit/TdTypes';
import { listKeyOf } from './ListKey';

export class UnreadCountStore {
  private counts: Map<string, number> = new Map();
  private listeners: Array<() => void> = [];

  constructor(client: TdClient) {
    client.onUpdate('updateUnreadChatCount', (u: TdObject) => this.onCount(u));
  }

  getUnread(listKey: string): number {
    return this.counts.get(listKey) ?? 0;
  }

  subscribe(listener: () => void): () => void {
    this.listeners = [...this.listeners, listener];
    listener();
    return (): void => {
      this.listeners = this.listeners.filter((l: () => void) => l !== listener);
    };
  }

  private onCount(update: TdObject): void {
    const chatList = update['chat_list'] as TdObject | undefined;
    if (chatList === undefined) {
      return;
    }
    const key = listKeyOf(chatList);
    if (key === '') {
      return;
    }
    this.counts.set(key, (update['unread_unmuted_count'] as number | undefined) ?? 0);
    for (const l of this.listeners) {
      l();
    }
  }
}
