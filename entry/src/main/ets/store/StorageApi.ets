import { getTdClient } from '../tdkit/Globals';
import { TdObject, TdRequest } from '../tdkit/TdTypes';

// Storage / network / draft calls behind 数据与存储. Media auto-download and
// "save to gallery" are deliberately absent: TDLib doesn't auto-download on the
// client's behalf and we have no gallery writer, so those switches would toggle
// nothing.

export interface StorageUsage {
  filesSize: number;   // downloaded media — the part worth clearing
  fileCount: number;
  databaseSize: number;
}

export interface NetworkUsage {
  sent: number;
  received: number;
  sinceDate: number;   // unix seconds
}

// Human-readable byte size, matching the official clients (1.28 GB).
export function formatBytes(bytes: number): string {
  if (bytes < 1024) {
    return `${bytes} B`;
  }
  const kb = bytes / 1024;
  if (kb < 1024) {
    return `${kb.toFixed(1)} KB`;
  }
  const mb = kb / 1024;
  if (mb < 1024) {
    return `${mb.toFixed(1)} MB`;
  }
  return `${(mb / 1024).toFixed(2)} GB`;
}

export async function getStorageUsage(): Promise<StorageUsage> {
  const res = await getTdClient().send({ '@type': 'getStorageStatisticsFast' } as TdRequest);
  return {
    filesSize: (res['files_size'] as number | undefined) ?? 0,
    fileCount: (res['file_count'] as number | undefined) ?? 0,
    databaseSize: (res['database_size'] as number | undefined) ?? 0
  };
}

// Drop every cached media file. The unlimited-everything form of optimizeStorage:
// -1 means "no limit" for size/ttl/count, so nothing is spared by age or volume.
export async function clearCache(): Promise<void> {
  const req: TdRequest = { '@type': 'optimizeStorage' };
  req['size'] = -1;
  req['ttl'] = -1;
  req['count'] = -1;
  req['immunity_delay'] = 0;
  req['file_types'] = [];
  req['chat_ids'] = [];
  req['exclude_chat_ids'] = [];
  req['return_deleted_file_statistics'] = false;
  req['chat_limit'] = 0;
  await getTdClient().send(req);
}

export async function getNetworkUsage(): Promise<NetworkUsage> {
  const req: TdRequest = { '@type': 'getNetworkStatistics' };
  req['only_current'] = false;
  const res = await getTdClient().send(req);
  const entries = (res['entries'] as TdObject[] | undefined) ?? [];
  let sent = 0;
  let received = 0;
  for (const e of entries) {
    sent += (e['sent_bytes'] as number | undefined) ?? 0;
    received += (e['received_bytes'] as number | undefined) ?? 0;
  }
  return { sent, received, sinceDate: (res['since_date'] as number | undefined) ?? 0 };
}

export async function resetNetworkUsage(): Promise<void> {
  await getTdClient().send({ '@type': 'resetNetworkStatistics' } as TdRequest);
}

export async function clearAllDrafts(): Promise<void> {
  const req: TdRequest = { '@type': 'clearAllDraftMessages' };
  req['exclude_secret_chats'] = true;
  await getTdClient().send(req);
}
