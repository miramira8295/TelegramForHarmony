import { describe, it, expect } from '@ohos/hypium';
import { TdClient } from '../main/ets/tdkit/TdClient';
import { TdObject, TdBridge } from '../main/ets/tdkit/TdTypes';
import { UserStore } from '../main/ets/store/UserStore';
import { MessageStore } from '../main/ets/store/MessageStore';
import { MessageEntry } from '../main/ets/store/MessageEntry';

class FakeBridge implements TdBridge {
  onReceive: (json: string) => void = (): void => {};
  sent: string[] = [];
  init(cb: (json: string) => void): void { this.onReceive = cb; }
  send(json: string): void { this.sent.push(json); }
}
function setup(chatId: number): Array<Object> {
  const b = new FakeBridge(); const c = new TdClient(b); const u = new UserStore(c);
  const store = new MessageStore(c, u, chatId); c.start();
  return [b, store];
}
function textMessage(id: number, chatId: number, outgoing: boolean, text: string): TdObject {
  const ft: TdObject = { '@type': 'formattedText' }; ft['text'] = text;
  const content: TdObject = { '@type': 'messageText' }; content['text'] = ft;
  const m: TdObject = { '@type': 'message' };
  m['id'] = id; m['chat_id'] = chatId; m['is_outgoing'] = outgoing; m['date'] = 100; m['content'] = content;
  return m;
}
function pushNewMessage(b: FakeBridge, m: TdObject): void {
  const u: TdObject = { '@type': 'updateNewMessage' }; u['message'] = m;
  b.onReceive(JSON.stringify(u));
}
function extraOf(json: string): string {
  const o = JSON.parse(json) as TdObject; return (o['@extra'] as string | undefined) ?? '';
}
function feedChat(b: FakeBridge, chatId: number): void {
  // find the getChat request and answer it with a minimal chat (no unread
  // anchor), so startInitialLoad() takes the plain loadHistory(0) path.
  let extra = '';
  for (const s of b.sent) {
    const o = JSON.parse(s) as TdObject;
    if (o['@type'] === 'getChat') { extra = extraOf(s); }
  }
  const chat: TdObject = { '@type': 'chat' };
  chat['id'] = chatId;
  chat['@extra'] = extra;
  b.onReceive(JSON.stringify(chat));
}
function feedHistory(b: FakeBridge, msgs: TdObject[]): void {
  // find the getChatHistory request and answer it with a `messages` response
  let extra = '';
  for (const s of b.sent) {
    const o = JSON.parse(s) as TdObject;
    if (o['@type'] === 'getChatHistory') { extra = extraOf(s); }
  }
  const res: TdObject = { '@type': 'messages' }; res['total_count'] = msgs.length; res['messages'] = msgs; res['@extra'] = extra;
  b.onReceive(JSON.stringify(res));
}
function ids(list: MessageEntry[]): number[] { return list.map((m: MessageEntry) => m.id); }

export default function messageStoreTest() {
  describe('MessageStore', () => {
    it('open_sends_openchat_and_history', 0, async () => {
      const arr = setup(5); const b = arr[0] as FakeBridge; const store = arr[1] as MessageStore;
      store.open();
      feedChat(b, 5); // history is deferred until getChat resolves (unread anchor)
      // onChat() runs in a .then() microtask, not synchronously after feedChat.
      await new Promise<void>((r: (v: undefined) => void) => setTimeout(() => r(undefined), 0));
      const types = b.sent.map((s: string) => (JSON.parse(s) as TdObject)['@type']);
      expect(types.includes('openChat')).assertTrue();
      expect(types.includes('getChatHistory')).assertTrue();
    });
    it('history_loads_ascending', 0, async () => {
      const arr = setup(5); const b = arr[0] as FakeBridge; const store = arr[1] as MessageStore;
      store.open();
      feedChat(b, 5);
      await new Promise<void>((r: (v: undefined) => void) => setTimeout(() => r(undefined), 0));
      feedHistory(b, [textMessage(30, 5, false, 'c'), textMessage(20, 5, false, 'b'), textMessage(10, 5, false, 'a')]);
      await new Promise<void>((r: (v: undefined) => void) => setTimeout(() => r(undefined), 0));
      expect(ids(store.getMessages()).join(',')).assertEqual('10,20,30');
    });
    it('new_message_appends', 0, () => {
      const arr = setup(5); const b = arr[0] as FakeBridge; const store = arr[1] as MessageStore;
      store.open();
      pushNewMessage(b, textMessage(40, 5, false, 'new'));
      expect(ids(store.getMessages()).join(',')).assertEqual('40');
    });
    it('new_message_other_chat_ignored', 0, () => {
      const arr = setup(5); const b = arr[0] as FakeBridge; const store = arr[1] as MessageStore;
      store.open();
      pushNewMessage(b, textMessage(41, 99, false, 'other'));
      expect(store.getMessages().length).assertEqual(0);
    });
    it('send_succeeded_swaps_id', 0, () => {
      const arr = setup(5); const b = arr[0] as FakeBridge; const store = arr[1] as MessageStore;
      store.open();
      pushNewMessage(b, textMessage(1001, 5, true, 'hi')); // optimistic (temp id 1001, pending)
      const newMsg = textMessage(2002, 5, true, 'hi');
      const u: TdObject = { '@type': 'updateMessageSendSucceeded' }; u['message'] = newMsg; u['old_message_id'] = 1001;
      b.onReceive(JSON.stringify(u));
      expect(ids(store.getMessages()).join(',')).assertEqual('2002');
      expect(store.getMessages()[0].sendState).assertEqual('sent');
    });
    it('read_outbox_marks_read', 0, () => {
      const arr = setup(5); const b = arr[0] as FakeBridge; const store = arr[1] as MessageStore;
      store.open();
      pushNewMessage(b, textMessage(50, 5, true, 'x')); // outgoing, sent
      const u: TdObject = { '@type': 'updateChatReadOutbox' }; u['chat_id'] = 5; u['last_read_outbox_message_id'] = 50;
      b.onReceive(JSON.stringify(u));
      expect(store.getMessages()[0].sendState).assertEqual('read');
    });
    it('delete_removes', 0, () => {
      const arr = setup(5); const b = arr[0] as FakeBridge; const store = arr[1] as MessageStore;
      store.open();
      pushNewMessage(b, textMessage(60, 5, false, 'y'));
      const u: TdObject = { '@type': 'updateDeleteMessages' }; u['chat_id'] = 5; u['message_ids'] = [60]; u['is_permanent'] = true;
      b.onReceive(JSON.stringify(u));
      expect(store.getMessages().length).assertEqual(0);
    });
    it('send_optimistically_adds_and_requests', 0, async () => {
      const arr = setup(5); const b = arr[0] as FakeBridge; const store = arr[1] as MessageStore;
      store.open();
      const before = b.sent.length;
      store.send('hello');
      const sentTypes = b.sent.slice(before).map((s: string) => (JSON.parse(s) as TdObject)['@type']);
      expect(sentTypes.includes('sendMessage')).assertTrue();
    });
    it('close_unsubscribes', 0, () => {
      const arr = setup(5); const b = arr[0] as FakeBridge; const store = arr[1] as MessageStore;
      store.open();
      store.close();
      pushNewMessage(b, textMessage(70, 5, false, 'z'));
      expect(store.getMessages().length).assertEqual(0);
      const types = b.sent.map((s: string) => (JSON.parse(s) as TdObject)['@type']);
      expect(types.includes('closeChat')).assertTrue();
    });
  });
}
