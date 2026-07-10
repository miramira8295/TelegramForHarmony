import { describe, it, expect } from '@ohos/hypium';
import { TdClient } from '../main/ets/tdkit/TdClient';
import { TdObject, TdBridge } from '../main/ets/tdkit/TdTypes';
import { UserStore } from '../main/ets/store/UserStore';
import { ChatStore } from '../main/ets/store/ChatStore';
import { ChatEntry } from '../main/ets/store/ChatEntry';
import { FileService } from '../main/ets/services/FileService';

class FakeBridge implements TdBridge {
  onReceive: (json: string) => void = (): void => {};
  sent: string[] = [];
  init(cb: (json: string) => void): void { this.onReceive = cb; }
  send(json: string): void { this.sent.push(json); }
}

function pushCompletedFile(bridge: FakeBridge, fileId: number, path: string): void {
  const local: TdObject = { '@type': 'localFile' };
  local['path'] = path; local['is_downloading_completed'] = true;
  const file: TdObject = { '@type': 'file' };
  file['id'] = fileId; file['local'] = local;
  const u: TdObject = { '@type': 'updateFile' };
  u['file'] = file;
  bridge.onReceive(JSON.stringify(u));
}

function seedChat(bridge: FakeBridge, id: number): void {
  const list: TdObject = { '@type': 'chatListMain' };
  const pos: TdObject = { '@type': 'chatPosition' };
  pos['list'] = list; pos['order'] = '100'; pos['is_pinned'] = false;
  const chat: TdObject = { '@type': 'chat' };
  chat['id'] = id; chat['title'] = 'X'; chat['positions'] = [pos]; chat['unread_count'] = 0;
  const u: TdObject = { '@type': 'updateNewChat' }; u['chat'] = chat;
  bridge.onReceive(JSON.stringify(u));
}

export default function fileServiceTest() {
  describe('FileService', () => {
    it('completed_file_sets_avatar_path', 0, () => {
      const bridge = new FakeBridge();
      const client = new TdClient(bridge);
      const users = new UserStore(client);
      const store = new ChatStore(client, users);
      const files = new FileService(client, store);
      client.start();
      seedChat(bridge, 1);
      files.requestAvatar(1, 55);
      pushCompletedFile(bridge, 55, '/data/avatar_55.jpg');
      expect(store.getChats()[0].avatarPath).assertEqual('/data/avatar_55.jpg');
    });
    it('dedups_download', 0, () => {
      const bridge = new FakeBridge();
      const client = new TdClient(bridge);
      const users = new UserStore(client);
      const store = new ChatStore(client, users);
      const files = new FileService(client, store);
      client.start();
      seedChat(bridge, 1);
      files.requestAvatar(1, 55);
      const after1 = bridge.sent.length;
      files.requestAvatar(1, 55);
      expect(bridge.sent.length).assertEqual(after1);
    });
  });
}
