import { describe, it, expect } from '@ohos/hypium';
import { TdClient } from '../main/ets/tdkit/TdClient';
import { TdObject, TdBridge } from '../main/ets/tdkit/TdTypes';
import { UserStore } from '../main/ets/store/UserStore';

class FakeBridge implements TdBridge {
  onReceive: (json: string) => void = (): void => {};
  sent: string[] = [];
  init(cb: (json: string) => void): void { this.onReceive = cb; }
  send(json: string): void { this.sent.push(json); }
}

function pushUser(bridge: FakeBridge, id: number, first: string, last: string): void {
  const user: TdObject = { '@type': 'user' };
  user['id'] = id; user['first_name'] = first; user['last_name'] = last;
  const u: TdObject = { '@type': 'updateUser' };
  u['user'] = user;
  bridge.onReceive(JSON.stringify(u));
}

export default function userStoreTest() {
  describe('UserStore', () => {
    it('caches_and_resolves', 0, () => {
      const bridge = new FakeBridge();
      const client = new TdClient(bridge);
      const users = new UserStore(client);
      client.start();
      pushUser(bridge, 42, 'Ada', 'Lovelace');
      expect(users.displayName(42)).assertEqual('Ada Lovelace');
    });
    it('unknown_empty', 0, () => {
      const bridge = new FakeBridge();
      const client = new TdClient(bridge);
      const users = new UserStore(client);
      client.start();
      expect(users.displayName(999)).assertEqual('');
    });
    it('first_only', 0, () => {
      const bridge = new FakeBridge();
      const client = new TdClient(bridge);
      const users = new UserStore(client);
      client.start();
      pushUser(bridge, 7, 'Cher', '');
      expect(users.displayName(7)).assertEqual('Cher');
    });
  });
}
