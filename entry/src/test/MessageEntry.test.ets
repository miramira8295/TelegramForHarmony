import { describe, it, expect } from '@ohos/hypium';
import { TdClient } from '../main/ets/tdkit/TdClient';
import { TdObject, TdBridge } from '../main/ets/tdkit/TdTypes';
import { UserStore } from '../main/ets/store/UserStore';
import { buildMessageEntry, cloneMessage, MessageEntry } from '../main/ets/store/MessageEntry';

class FakeBridge implements TdBridge {
  onReceive: (json: string) => void = (): void => {};
  sent: string[] = [];
  init(cb: (json: string) => void): void { this.onReceive = cb; }
  send(json: string): void { this.sent.push(json); }
}
function usersOf(): UserStore {
  const b = new FakeBridge(); const c = new TdClient(b); const u = new UserStore(c); c.start();
  const user: TdObject = { '@type': 'user' }; user['id'] = 7; user['first_name'] = 'Ann'; user['last_name'] = '';
  const upd: TdObject = { '@type': 'updateUser' }; upd['user'] = user;
  b.onReceive(JSON.stringify(upd));
  return u;
}
function msg(id: number, outgoing: boolean, senderUserId: number, text: string): TdObject {
  const ft: TdObject = { '@type': 'formattedText' }; ft['text'] = text;
  const c: TdObject = { '@type': 'messageText' }; c['text'] = ft;
  const sender: TdObject = { '@type': 'messageSenderUser' }; sender['user_id'] = senderUserId;
  const m: TdObject = { '@type': 'message' };
  m['id'] = id; m['is_outgoing'] = outgoing; m['sender_id'] = sender; m['date'] = 100; m['content'] = c;
  return m;
}

export default function messageEntryTest() {
  describe('MessageEntry', () => {
    it('incoming_text', 0, () => {
      const e = buildMessageEntry(msg(10, false, 7, 'hi'), usersOf());
      expect(e.id).assertEqual(10);
      expect(e.isOutgoing).assertEqual(false);
      expect(e.senderName).assertEqual('Ann');
      expect(e.contentType).assertEqual('text');
      expect(e.text).assertEqual('hi');
      expect(e.sendState).assertEqual('none');
    });
    it('outgoing_sending_state', 0, () => {
      const m = msg(11, true, 7, 'yo');
      const st: TdObject = { '@type': 'messageSendingStatePending' }; m['sending_state'] = st;
      const e = buildMessageEntry(m, usersOf());
      expect(e.sendState).assertEqual('sending');
    });
    it('outgoing_sent_when_no_state', 0, () => {
      const e = buildMessageEntry(msg(12, true, 7, 'done'), usersOf());
      expect(e.sendState).assertEqual('sent');
    });
    it('clone_is_independent', 0, () => {
      const e = buildMessageEntry(msg(13, false, 7, 'x'), usersOf());
      const c = cloneMessage(e); c.text = 'changed';
      expect(e.text).assertEqual('x');
    });
  });
}
