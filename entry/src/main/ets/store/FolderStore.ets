import { TdClient } from '../tdkit/TdClient';
import { TdObject } from '../tdkit/TdTypes';

export interface FolderInfo {
  id: number;
  title: string;
}

function folderTitle(info: TdObject): string {
  const t = info['title'] as string | undefined;
  if (t !== undefined && t !== '') {
    return t;
  }
  const name = info['name'] as TdObject | undefined;
  if (name !== undefined) {
    const text = name['text'] as TdObject | undefined;
    if (text !== undefined) {
      return (text['text'] as string | undefined) ?? '';
    }
  }
  return '';
}

export class FolderStore {
  private folders: FolderInfo[] = [];
  private listeners: Array<(folders: FolderInfo[]) => void> = [];

  constructor(client: TdClient) {
    client.onUpdate('updateChatFolders', (u: TdObject) => this.onFolders(u));
  }

  getFolders(): FolderInfo[] {
    return this.folders;
  }

  subscribe(listener: (folders: FolderInfo[]) => void): () => void {
    this.listeners = [...this.listeners, listener];
    listener(this.folders);
    return (): void => {
      this.listeners = this.listeners.filter((l: (folders: FolderInfo[]) => void) => l !== listener);
    };
  }

  private onFolders(update: TdObject): void {
    const arr = update['chat_folders'] as TdObject[] | undefined;
    if (arr === undefined) {
      return;
    }
    const next: FolderInfo[] = [];
    for (const info of arr) {
      const id = info['id'] as number | undefined;
      if (id === undefined) {
        continue;
      }
      next.push({ id, title: folderTitle(info) });
    }
    this.folders = next;
    for (const l of this.listeners) {
      l(this.folders);
    }
  }
}
