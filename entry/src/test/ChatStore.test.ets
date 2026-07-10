import { describe, it, expect } from '@ohos/hypium';
import { TdClient } from '../main/ets/tdkit/TdClient';
import { TdObject, TdBridge } from '../main/ets/tdkit/TdTypes';
import { UserStore } from '../main/ets/store/UserStore';
import { ChatStore } from '../main/ets/store/ChatStore';
import { ChatEntry } from '../main/ets/store/ChatEntry';

class FakeBridge implements TdBridge {
  onReceive: (json: string) => void = (): void => {};
  sent: string[] = [];
  init(cb: (json: string) => void): void { this.onReceive = cb; }
  send(json: string): void { this.sent.push(json); }
}

function mainPos(order: string, pinned: boolean): TdObject {
  const list: TdObject = { '@type': 'chatListMain' };
  const p: TdObject = { '@type': 'chatPosition' };
  p['list'] = list; p['order'] = order; p['is_pinned'] = pinned;
  return p;
}

function textMessage(text: string, date: number): TdObject {
  const ft: TdObject = { '@type': 'formattedText' }; ft['text'] = text;
  const content: TdObject = { '@type': 'messageText' }; content['text'] = ft;
  const m: TdObject = { '@type': 'message' };
  m['content'] = content; m['date'] = date;
  return m;
}

function pushNewChat(bridge: FakeBridge, id: number, title: string,
    positions: TdObject[], lastMsg: TdObject | null, unread: number): void {
  const chat: TdObject = { '@type': 'chat' };
  chat['id'] = id; chat['title'] = title; chat['positions'] = positions;
  chat['unread_count'] = unread;
  if (lastMsg !== null) { chat['last_message'] = lastMsg; }
  const u: TdObject = { '@type': 'updateNewChat' }; u['chat'] = chat;
  bridge.onReceive(JSON.stringify(u));
}

function pushPosition(bridge: FakeBridge, id: number, pos: TdObject): void {
  const u: TdObject = { '@type': 'updateChatPosition' };
  u['chat_id'] = id; u['position'] = pos;
  bridge.onReceive(JSON.stringify(u));
}

function folderPos(fid: number, order: string, pinned: boolean): TdObject {
  const list: TdObject = { '@type': 'chatListFolder' }; list['chat_folder_id'] = fid;
  const p: TdObject = { '@type': 'chatPosition' };
  p['list'] = list; p['order'] = order; p['is_pinned'] = pinned;
  return p;
}
function archivePos(order: string, pinned: boolean): TdObject {
  const list: TdObject = { '@type': 'chatListArchive' };
  const p: TdObject = { '@type': 'chatPosition' };
  p['list'] = list; p['order'] = order; p['is_pinned'] = pinned;
  return p;
}

function ids(chats: ChatEntry[]): number[] {
  return chats.map((c: ChatEntry) => c.id);
}

function make(): ChatStore {
  const bridge = new FakeBridge();
  const client = new TdClient(bridge);
  const users = new UserStore(client);
  const store = new ChatStore(client, users);
  client.start();
  // stash bridge on store for test access
  (store as object)['__bridge'] = bridge;
  return store;
}

function bridgeOf(store: ChatStore): FakeBridge {
  return (store as object)['__bridge'] as FakeBridge;
}

export default function chatStoreTest() {
  describe('ChatStore', () => {
    it('orders_by_desc_order_pinned_first', 0, () => {
      const store = make();
      const b = bridgeOf(store);
      pushNewChat(b, 1, 'A', [mainPos('100', false)], null, 0);
      pushNewChat(b, 2, 'B', [mainPos('300', false)], null, 0);
      pushNewChat(b, 3, 'C', [mainPos('50', true)], null, 0);
      // pinned (3) first, then 2 (300) > 1 (100)
      expect(ids(store.getChats()).join(',')).assertEqual('3,2,1');
    });
    it('excludes_order_zero', 0, () => {
      const store = make();
      const b = bridgeOf(store);
      pushNewChat(b, 1, 'A', [], null, 0); // no main position
      expect(store.getChats().length).assertEqual(0);
    });
    it('archive_removes_unarchive_restores', 0, () => {
      const store = make();
      const b = bridgeOf(store);
      pushNewChat(b, 1, 'A', [mainPos('100', false)], null, 0);
      expect(store.getChats().length).assertEqual(1);
      pushPosition(b, 1, mainPos('0', false)); // archived
      expect(store.getChats().length).assertEqual(0);
      pushPosition(b, 1, mainPos('100', false)); // unarchived
      expect(store.getChats().length).assertEqual(1);
    });
    it('last_message_updates_and_reorders', 0, () => {
      const store = make();
      const b = bridgeOf(store);
      pushNewChat(b, 1, 'A', [mainPos('100', false)], null, 0);
      pushNewChat(b, 2, 'B', [mainPos('200', false)], null, 0);
      // chat 1 gets a newer message that bumps its order above 2
      const u: TdObject = { '@type': 'updateChatLastMessage' };
      u['chat_id'] = 1; u['last_message'] = textMessage('hi', 1783512000);
      u['positions'] = [mainPos('300', false)];
      b.onReceive(JSON.stringify(u));
      expect(ids(store.getChats()).join(',')).assertEqual('1,2');
      expect(store.getChats()[0].lastMessageText).assertEqual('hi');
    });
    it('read_inbox_updates_unread', 0, () => {
      const store = make();
      const b = bridgeOf(store);
      pushNewChat(b, 1, 'A', [mainPos('100', false)], null, 5);
      const u: TdObject = { '@type': 'updateChatReadInbox' };
      u['chat_id'] = 1; u['unread_count'] = 0;
      b.onReceive(JSON.stringify(u));
      expect(store.getChats()[0].unreadCount).assertEqual(0);
    });
    it('notification_settings_mute', 0, () => {
      const store = make();
      const b = bridgeOf(store);
      pushNewChat(b, 1, 'A', [mainPos('100', false)], null, 0);
      const ns: TdObject = { '@type': 'chatNotificationSettings' }; ns['mute_for'] = 3600;
      const u: TdObject = { '@type': 'updateChatNotificationSettings' };
      u['chat_id'] = 1; u['notification_settings'] = ns;
      b.onReceive(JSON.stringify(u));
      expect(store.getChats()[0].isMuted).assertEqual(true);
    });
    it('subscribe_replays_and_notifies', 0, () => {
      const store = make();
      const b = bridgeOf(store);
      let calls = 0;
      const off = store.subscribe((_c: ChatEntry[]) => { calls += 1; });
      expect(calls).assertEqual(1); // replay
      pushNewChat(b, 1, 'A', [mainPos('100', false)], null, 0);
      expect(calls).assertEqual(2);
      off();
      pushNewChat(b, 2, 'B', [mainPos('200', false)], null, 0);
      expect(calls).assertEqual(2); // no more after unsubscribe
    });
    it('load_sends_loadChats', 0, () => {
      const store = make();
      const b = bridgeOf(store);
      store.load();
      const sent = JSON.parse(b.sent[b.sent.length - 1]) as TdObject;
      expect(sent['@type']).assertEqual('loadChats');
    });
    it('sender_name_from_user', 0, () => {
      const store = make();
      const b = bridgeOf(store);
      const user: TdObject = { '@type': 'user' };
      user['id'] = 7; user['first_name'] = 'Ada'; user['last_name'] = 'L';
      const uu: TdObject = { '@type': 'updateUser' }; uu['user'] = user;
      b.onReceive(JSON.stringify(uu));
      const sender: TdObject = { '@type': 'messageSenderUser' }; sender['user_id'] = 7;
      const m = textMessage('hey', 1783512000); m['sender_id'] = sender;
      pushNewChat(b, 1, 'Group', [mainPos('100', false)], m, 0);
      expect(store.getChats()[0].lastSenderName).assertEqual('Ada L');
    });
    it('sender_name_private_empty', 0, () => {
      const store = make();
      const b = bridgeOf(store);
      const m = textMessage('hi', 1783512000); // no sender_id
      pushNewChat(b, 1, 'A', [mainPos('100', false)], m, 0);
      expect(store.getChats()[0].lastSenderName).assertEqual('');
    });
    it('photo_file_id_and_set_avatar_path', 0, () => {
      const store = make();
      const b = bridgeOf(store);
      const small: TdObject = { '@type': 'file' }; small['id'] = 88;
      const photo: TdObject = { '@type': 'chatPhotoInfo' }; photo['small'] = small;
      const chat: TdObject = { '@type': 'chat' };
      chat['id'] = 1; chat['title'] = 'A'; chat['positions'] = [mainPos('100', false)];
      chat['unread_count'] = 0; chat['photo'] = photo;
      const u: TdObject = { '@type': 'updateNewChat' }; u['chat'] = chat;
      b.onReceive(JSON.stringify(u));
      expect(store.photoFileIdOf(1)).assertEqual(88);
      store.setAvatarPath(1, '/data/a.jpg');
      expect(store.getChats()[0].avatarPath).assertEqual('/data/a.jpg');
    });
    it('update_does_not_mutate_prior_snapshot', 0, () => {
      const store = make();
      const b = bridgeOf(store);
      pushNewChat(b, 1, 'A', [mainPos('100', false)], null, 5);
      const before = store.getChats()[0];
      const ur: TdObject = { '@type': 'updateChatReadInbox' };
      ur['chat_id'] = 1; ur['unread_count'] = 0;
      b.onReceive(JSON.stringify(ur));
      expect(before.unreadCount).assertEqual(5);            // 旧快照不被改写(不可变)
      expect(store.getChats()[0].unreadCount).assertEqual(0); // 新快照已更新
    });
    it('notification_settings_unmute', 0, () => {
      const store = make();
      const b = bridgeOf(store);
      pushNewChat(b, 1, 'A', [mainPos('100', false)], null, 0);
      const ns: TdObject = { '@type': 'chatNotificationSettings' }; ns['mute_for'] = 0;
      const u: TdObject = { '@type': 'updateChatNotificationSettings' };
      u['chat_id'] = 1; u['notification_settings'] = ns;
      b.onReceive(JSON.stringify(u));
      expect(store.getChats()[0].isMuted).assertEqual(false);
    });
    it('load_more_sends_loadChats', 0, () => {
      const store = make();
      const b = bridgeOf(store);
      store.loadMore();
      const sent = JSON.parse(b.sent[b.sent.length - 1]) as TdObject;
      expect(sent['@type']).assertEqual('loadChats');
    });
    it('chat_in_main_and_folder_independent_order', 0, () => {
      const store = make();
      const b = bridgeOf(store);
      pushNewChat(b, 1, 'A', [mainPos('100', false), folderPos(5, '900', false)], null, 0);
      pushNewChat(b, 2, 'B', [mainPos('200', false), folderPos(5, '800', false)], null, 0);
      expect(ids(store.getChats('main')).join(',')).assertEqual('2,1');       // 200>100
      expect(ids(store.getChats('folder:5')).join(',')).assertEqual('1,2');   // 900>800
    });
    it('folder_only_chat_not_in_main', 0, () => {
      const store = make();
      const b = bridgeOf(store);
      pushNewChat(b, 1, 'A', [folderPos(5, '100', false)], null, 0);
      expect(store.getChats('main').length).assertEqual(0);
      expect(store.getChats('folder:5').length).assertEqual(1);
    });
    it('archive_bucket_and_hasArchive', 0, () => {
      const store = make();
      const b = bridgeOf(store);
      expect(store.hasArchive()).assertEqual(false);
      pushNewChat(b, 1, 'A', [archivePos('100', false)], null, 0);
      expect(store.getChats('archive').length).assertEqual(1);
      expect(store.hasArchive()).assertEqual(true);
    });
    it('unread_chat_count_excludes_read_and_muted', 0, () => {
      const store = make();
      const b = bridgeOf(store);
      pushNewChat(b, 1, 'A', [folderPos(5, '300', false)], null, 3); // unread, unmuted -> counted
      pushNewChat(b, 2, 'B', [folderPos(5, '200', false)], null, 0); // read -> not counted
      pushNewChat(b, 3, 'C', [folderPos(5, '100', false)], null, 5); // unread but muted below -> not counted
      const ns: TdObject = { '@type': 'chatNotificationSettings' }; ns['mute_for'] = 3600;
      const u: TdObject = { '@type': 'updateChatNotificationSettings' }; u['chat_id'] = 3; u['notification_settings'] = ns;
      b.onReceive(JSON.stringify(u));
      expect(store.unreadChatCount('folder:5')).assertEqual(1);
      expect(store.unreadChatCount('main')).assertEqual(0);
    });
    it('position_update_adds_to_folder', 0, () => {
      const store = make();
      const b = bridgeOf(store);
      pushNewChat(b, 1, 'A', [mainPos('100', false)], null, 0);
      pushPosition(b, 1, folderPos(5, '300', false));
      expect(store.getChats('folder:5').length).assertEqual(1);
      expect(store.getChats('main').length).assertEqual(1); // still in main
    });
    it('display_update_reflects_across_lists', 0, () => {
      const store = make();
      const b = bridgeOf(store);
      pushNewChat(b, 1, 'A', [mainPos('100', false), folderPos(5, '100', false)], null, 5);
      const u: TdObject = { '@type': 'updateChatReadInbox' }; u['chat_id'] = 1; u['unread_count'] = 0;
      b.onReceive(JSON.stringify(u));
      expect(store.getChats('main')[0].unreadCount).assertEqual(0);
      expect(store.getChats('folder:5')[0].unreadCount).assertEqual(0);
    });
    it('subscribe_listkey_replays_only_that_list', 0, () => {
      const store = make();
      const b = bridgeOf(store);
      pushNewChat(b, 1, 'A', [folderPos(5, '100', false)], null, 0);
      let seen = -1;
      const off = store.subscribe((c: ChatEntry[]) => { seen = c.length; }, 'folder:5');
      expect(seen).assertEqual(1); // replay of folder:5
      off();
    });
    it('entry_of_returns_display_or_undefined', 0, () => {
      const store = make();
      const b = bridgeOf(store);
      expect(store.entryOf(1)).assertUndefined();
      pushNewChat(b, 1, 'Alice', [mainPos('100', false)], null, 0);
      const e = store.entryOf(1);
      expect(e !== undefined).assertTrue();
      expect(e!.title).assertEqual('Alice');
    });
  });
}
