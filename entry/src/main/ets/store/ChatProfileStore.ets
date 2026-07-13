import { TdClient } from '../tdkit/TdClient';
import { TdObject, TdRequest, TdError } from '../tdkit/TdTypes';
import { formatUserStatus } from '../util/formatUserStatus';
import { formatMemberCount } from '../util/formatMemberCount';

type Listener = () => void;

const DL_PRIORITY: number = 1;
const MEMBER_PAGE: number = 30;

export interface MemberItem {
  userId: number;
  name: string;
  initials: string;
  avatarPath: string;
  status: string;
}

// Data assembly for the group/channel detail page (ChatProfilePage) — mirrors
// ProfileStore's subscribe/notify + download patterns.
export class ChatProfileStore {
  title: string = '';
  initials: string = '?';
  avatarPath: string = '';
  avatarAnimPath: string = ''; // animated chat photo (MPEG4), '' if none
  subtitle: string = '';      // "N 位成员" / "N 位订阅者"
  description: string = '';
  username: string = '';
  isChannel: boolean = false;
  isMuted: boolean = false;
  members: MemberItem[] = [];

  private client: TdClient;
  private chatId: number;
  private supergroupId: number = 0;
  private basicGroupId: number = 0;
  private listeners: Listener[] = [];
  private unsubs: Array<() => void> = [];
  private fileApply: Map<number, (path: string) => void> = new Map();

  constructor(client: TdClient, chatId: number) {
    this.client = client;
    this.chatId = chatId;
  }

  subscribe(l: Listener): () => void {
    this.listeners = [...this.listeners, l];
    l();
    return (): void => { this.listeners = this.listeners.filter((x: Listener) => x !== l); };
  }

  open(): void {
    this.unsubs.push(this.client.onUpdate('updateFile', (u: TdObject) => {
      const f = u['file'] as TdObject | undefined;
      if (f !== undefined) {
        this.applyFile(f);
      }
    }));
    this.unsubs.push(this.client.onUpdate('updateChatNotificationSettings', (u: TdObject) => {
      if ((u['chat_id'] as number | undefined) === this.chatId) {
        this.applyNotificationSettings(u['notification_settings'] as TdObject | undefined);
        this.notify();
      }
    }));
    this.loadChat();
  }

  close(): void {
    for (const un of this.unsubs) {
      un();
    }
    this.unsubs = [];
    this.listeners = [];
  }

  private notify(): void {
    for (const l of this.listeners) {
      l();
    }
  }

  private send(req: TdRequest, tag: string, onOk: (res: TdObject) => void): void {
    this.client.send(req).then(onOk).catch((e: TdError) => {
      console.error(`ChatProfileStore.${tag} failed: ${e.message}`);
    });
  }

  private download(fileId: number, apply: (path: string) => void): void {
    if (fileId <= 0) {
      return;
    }
    this.fileApply.set(fileId, apply);
    const req: TdRequest = { '@type': 'downloadFile' };
    req['file_id'] = fileId;
    req['priority'] = DL_PRIORITY;
    this.send(req, 'downloadFile', (f: TdObject) => this.applyFile(f));
  }

  private applyFile(file: TdObject): void {
    const id = file['id'] as number | undefined;
    if (id === undefined) {
      return;
    }
    const apply = this.fileApply.get(id);
    if (apply === undefined) {
      return;
    }
    const local = file['local'] as TdObject | undefined;
    const done = local !== undefined ? ((local['is_downloading_completed'] as boolean | undefined) ?? false) : false;
    const path = local !== undefined ? ((local['path'] as string | undefined) ?? '') : '';
    if (done && path !== '') {
      apply(path);
      this.notify();
    }
  }

  private loadChat(): void {
    const req: TdRequest = { '@type': 'getChat' };
    req['chat_id'] = this.chatId;
    this.send(req, 'getChat', (chat: TdObject) => {
      this.title = (chat['title'] as string | undefined) ?? '';
      this.initials = this.title.length > 0 ? this.title.substring(0, 1).toUpperCase() : '?';
      const photo = chat['photo'] as TdObject | undefined;
      const big = photo !== undefined ? (photo['big'] as TdObject | undefined) : undefined;
      this.download(big !== undefined ? ((big['id'] as number | undefined) ?? 0) : 0,
        (p: string) => { this.avatarPath = p; });
      this.applyNotificationSettings(chat['notification_settings'] as TdObject | undefined);
      const type = chat['type'] as TdObject | undefined;
      const typeName = type !== undefined ? ((type['@type'] as string | undefined) ?? '') : '';
      if (typeName === 'chatTypeSupergroup') {
        this.supergroupId = ((type as TdObject)['supergroup_id'] as number | undefined) ?? 0;
        this.loadSupergroup();
      } else if (typeName === 'chatTypeBasicGroup') {
        this.basicGroupId = ((type as TdObject)['basic_group_id'] as number | undefined) ?? 0;
        this.loadBasicGroup();
      }
      this.notify();
    });
  }

  // Muted = explicit non-default settings with a positive mute window.
  private applyNotificationSettings(ns: TdObject | undefined): void {
    if (ns === undefined) {
      return;
    }
    const useDefault = (ns['use_default_mute_for'] as boolean | undefined) ?? true;
    const muteFor = (ns['mute_for'] as number | undefined) ?? 0;
    this.isMuted = !useDefault && muteFor > 0;
  }

  private loadSupergroup(): void {
    const req: TdRequest = { '@type': 'getSupergroup' };
    req['supergroup_id'] = this.supergroupId;
    this.send(req, 'getSupergroup', (sg: TdObject) => {
      this.isChannel = (sg['is_channel'] as boolean | undefined) ?? false;
      const usernames = sg['usernames'] as TdObject | undefined;
      const editable = usernames !== undefined ? ((usernames['editable_username'] as string | undefined) ?? '') : '';
      const active = usernames !== undefined ? (usernames['active_usernames'] as string[] | undefined) : undefined;
      this.username = editable !== '' ? editable : (active !== undefined && active.length > 0 ? active[0] : '');
      const count = (sg['member_count'] as number | undefined) ?? 0;
      if (count > 0) {
        this.subtitle = `${formatMemberCount(count)} 位${this.isChannel ? '订阅者' : '成员'}`;
      }
      this.notify();

      const full: TdRequest = { '@type': 'getSupergroupFullInfo' };
      full['supergroup_id'] = this.supergroupId;
      this.send(full, 'getSupergroupFullInfo', (fi: TdObject) => {
        this.description = (fi['description'] as string | undefined) ?? '';
        this.parsePhotoAnimation(fi['photo'] as TdObject | undefined);
        const memberCount = (fi['member_count'] as number | undefined) ?? 0;
        if (memberCount > 0) {
          this.subtitle = `${formatMemberCount(memberCount)} 位${this.isChannel ? '订阅者' : '成员'}`;
        }
        this.notify();
        // Member lists are only available for groups (channels expose admins only).
        const canGetMembers = (fi['can_get_members'] as boolean | undefined) ?? false;
        if (!this.isChannel && canGetMembers) {
          this.loadSupergroupMembers();
        }
      });
    });
  }

  // Full-info photo is a chatPhoto; its optional `animation` is a small MPEG4
  // loop (the chat's chatPhotoInfo only carries a has_animation flag).
  private parsePhotoAnimation(photo: TdObject | undefined): void {
    const anim = photo !== undefined ? (photo['animation'] as TdObject | undefined) : undefined;
    const file = anim !== undefined ? (anim['file'] as TdObject | undefined) : undefined;
    const fileId = file !== undefined ? ((file['id'] as number | undefined) ?? 0) : 0;
    this.download(fileId, (p: string) => { this.avatarAnimPath = p; });
  }

  private memberOffset: number = 0;
  private membersPending: boolean = false;
  hasMoreMembers: boolean = false;

  private loadSupergroupMembers(): void {
    this.memberOffset = 0;
    this.fetchMembersPage();
  }

  // Scroll-driven: the profile page calls this near the list's end.
  loadMoreMembers(): void {
    if (!this.hasMoreMembers || this.membersPending || this.supergroupId === 0) {
      return;
    }
    this.fetchMembersPage();
  }

  private fetchMembersPage(): void {
    this.membersPending = true;
    const req: TdRequest = { '@type': 'getSupergroupMembers' };
    req['supergroup_id'] = this.supergroupId;
    req['offset'] = this.memberOffset;
    req['limit'] = MEMBER_PAGE;
    this.send(req, 'getSupergroupMembers', (res: TdObject) => {
      const raw = (res['members'] as TdObject[] | undefined) ?? [];
      this.memberOffset += raw.length;
      this.hasMoreMembers = raw.length === MEMBER_PAGE;
      this.membersPending = false;
      this.resolveMembers(raw);
    });
  }

  private loadBasicGroup(): void {
    const req: TdRequest = { '@type': 'getBasicGroupFullInfo' };
    req['basic_group_id'] = this.basicGroupId;
    this.send(req, 'getBasicGroupFullInfo', (fi: TdObject) => {
      this.description = (fi['description'] as string | undefined) ?? '';
      this.parsePhotoAnimation(fi['photo'] as TdObject | undefined);
      const members = (fi['members'] as TdObject[] | undefined) ?? [];
      if (members.length > 0) {
        this.subtitle = `${formatMemberCount(members.length)} 位成员`;
      }
      this.notify();
      this.resolveMembers(members);
    });
  }

  // chatMember[] → MemberItem[] via getUser (name/status/avatar) per member.
  private resolveMembers(raw: TdObject[]): void {
    for (const m of raw) {
      const sender = m['member_id'] as TdObject | undefined;
      if (sender === undefined || (sender['@type'] as string | undefined) !== 'messageSenderUser') {
        continue;
      }
      const uid = (sender['user_id'] as number | undefined) ?? 0;
      if (uid <= 0) {
        continue;
      }
      const req: TdRequest = { '@type': 'getUser' };
      req['user_id'] = uid;
      this.send(req, 'getUser', (user: TdObject) => {
        const first = (user['first_name'] as string | undefined) ?? '';
        const last = (user['last_name'] as string | undefined) ?? '';
        const name = `${first} ${last}`.trim();
        if (name === '') {
          return;
        }
        const item: MemberItem = {
          userId: uid,
          name,
          initials: name.substring(0, 1).toUpperCase(),
          avatarPath: '',
          status: formatUserStatus(user['status'] as TdObject | undefined, Math.floor(Date.now() / 1000))
        };
        this.members = [...this.members, item];
        const photo = user['profile_photo'] as TdObject | undefined;
        const small = photo !== undefined ? (photo['small'] as TdObject | undefined) : undefined;
        this.download(small !== undefined ? ((small['id'] as number | undefined) ?? 0) : 0,
          (p: string) => {
            this.members = this.members.map((x: MemberItem): MemberItem =>
              x.userId === uid ? {
                userId: x.userId, name: x.name, initials: x.initials, avatarPath: p, status: x.status
              } : x);
          });
        this.notify();
      });
    }
  }
}
