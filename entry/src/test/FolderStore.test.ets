import { describe, it, expect } from '@ohos/hypium';
import { TdClient } from '../main/ets/tdkit/TdClient';
import { TdObject, TdBridge } from '../main/ets/tdkit/TdTypes';
import { FolderStore, FolderInfo } from '../main/ets/store/FolderStore';

class FakeBridge implements TdBridge {
  onReceive: (json: string) => void = (): void => {};
  sent: string[] = [];
  init(cb: (json: string) => void): void { this.onReceive = cb; }
  send(json: string): void { this.sent.push(json); }
}

function pushFolders(bridge: FakeBridge, folders: TdObject[]): void {
  const u: TdObject = { '@type': 'updateChatFolders' }; u['chat_folders'] = folders;
  bridge.onReceive(JSON.stringify(u));
}

export default function folderStoreTest() {
  describe('FolderStore', () => {
    it('parses_title_field', 0, () => {
      const bridge = new FakeBridge();
      const client = new TdClient(bridge);
      const store = new FolderStore(client);
      client.start();
      const f: TdObject = { '@type': 'chatFolderInfo' }; f['id'] = 5; f['title'] = 'Work';
      pushFolders(bridge, [f]);
      const got: FolderInfo[] = store.getFolders();
      expect(got.length).assertEqual(1);
      expect(got[0].id).assertEqual(5);
      expect(got[0].title).assertEqual('Work');
    });
    it('parses_name_text_fallback', 0, () => {
      const bridge = new FakeBridge();
      const client = new TdClient(bridge);
      const store = new FolderStore(client);
      client.start();
      const text: TdObject = { '@type': 'formattedText' }; text['text'] = 'Fun';
      const name: TdObject = { '@type': 'chatFolderName' }; name['text'] = text;
      const f: TdObject = { '@type': 'chatFolderInfo' }; f['id'] = 8; f['name'] = name;
      pushFolders(bridge, [f]);
      expect(store.getFolders()[0].title).assertEqual('Fun');
    });
    it('subscribe_replays_and_updates', 0, () => {
      const bridge = new FakeBridge();
      const client = new TdClient(bridge);
      const store = new FolderStore(client);
      client.start();
      let count = -1;
      store.subscribe((f: FolderInfo[]) => { count = f.length; });
      expect(count).assertEqual(0);
      const f: TdObject = { '@type': 'chatFolderInfo' }; f['id'] = 1; f['title'] = 'A';
      pushFolders(bridge, [f]);
      expect(count).assertEqual(1);
    });
  });
}
