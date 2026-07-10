import { describe, it, expect } from '@ohos/hypium';
import { TdClient } from '../main/ets/tdkit/TdClient';
import { TdObject, TdBridge } from '../main/ets/tdkit/TdTypes';
import { UnreadCountStore } from '../main/ets/store/UnreadCountStore';

class FakeBridge implements TdBridge {
  onReceive: (json: string) => void = (): void => {};
  sent: string[] = [];
  init(cb: (json: string) => void): void { this.onReceive = cb; }
  send(json: string): void { this.sent.push(json); }
}

function pushUnread(bridge: FakeBridge, listType: string, unmuted: number): void {
  const cl: TdObject = { '@type': listType };
  const u: TdObject = { '@type': 'updateUnreadChatCount' };
  u['chat_list'] = cl; u['unread_unmuted_count'] = unmuted;
  bridge.onReceive(JSON.stringify(u));
}

export default function unreadCountStoreTest() {
  describe('UnreadCountStore', () => {
    it('stores_unmuted_by_list', 0, () => {
      const bridge = new FakeBridge();
      const client = new TdClient(bridge);
      const store = new UnreadCountStore(client);
      client.start();
      pushUnread(bridge, 'chatListMain', 3);
      pushUnread(bridge, 'chatListArchive', 7);
      expect(store.getUnread('main')).assertEqual(3);
      expect(store.getUnread('archive')).assertEqual(7);
    });
    it('unknown_list_zero', 0, () => {
      const bridge = new FakeBridge();
      const client = new TdClient(bridge);
      const store = new UnreadCountStore(client);
      client.start();
      expect(store.getUnread('folder:9')).assertEqual(0);
    });
    it('subscribe_fires', 0, () => {
      const bridge = new FakeBridge();
      const client = new TdClient(bridge);
      const store = new UnreadCountStore(client);
      client.start();
      let fires = 0;
      store.subscribe(() => { fires += 1; });
      expect(fires).assertEqual(1); // replay
      pushUnread(bridge, 'chatListMain', 2);
      expect(fires).assertEqual(2);
    });
  });
}
