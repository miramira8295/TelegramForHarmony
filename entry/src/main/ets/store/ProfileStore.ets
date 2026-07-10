import { TdClient } from '../tdkit/TdClient';
import { TdObject, TdRequest, TdError } from '../tdkit/TdTypes';
import { formatUserStatus } from '../util/formatUserStatus';
import { formatMemberCount } from '../util/formatMemberCount';
import { formatPreview } from '../util/formatPreview';

const DL_PRIORITY: number = 1;
const WEEK_MINUTES: number = 7 * 24 * 60;

export interface CommonGroup {
  id: number;
  title: string;
  initials: string;
  avatarPath: string;
}

export interface StoryItem {
  id: number;
  thumbPath: string;
  duration: number; // seconds, 0 for photos
  isVideo: boolean;
}

export interface GiftItem {
  id: string;
  stickerPath: string;
}

// A gift from the catalog that can be sent (price in Telegram Stars).
export interface AvailGift {
  id: string; // int64 — kept as the raw JSON string to avoid precision loss
  stickerPath: string;
  stars: number;
}

type Listener = () => void;

// Backing store for the user profile page: user card, business info, personal
// channel, common groups, profile stories and received gifts.
export class ProfileStore {
  private client: TdClient;
  private userId: number;
  private listeners: Listener[] = [];
  private unsubs: Array<() => void> = [];
  // file id → apply(path) for every thumbnail/avatar this store downloads
  private fileApply: Map<number, (path: string) => void> = new Map();

  name: string = '';
  initials: string = '?';
  avatarPath: string = '';
  statusText: string = '';
  phone: string = '';
  usernames: string[] = [];
  isContact: boolean = false;
  bio: string = '';
  personalChatId: number = 0;
  bizOpen: boolean = false;
  bizHoursText: string = '';
  bizAddress: string = '';
  chTitle: string = '';
  chInitials: string = '?';
  chAvatarPath: string = '';
  chSubs: string = '';
  chPreview: string = '';
  groups: CommonGroup[] = [];
  stories: StoryItem[] = [];
  gifts: GiftItem[] = [];
  availableGifts: AvailGift[] = [];
  private availableLoaded: boolean = false;

  constructor(client: TdClient, userId: number) {
    this.client = client;
    this.userId = userId;
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
    this.unsubs.push(this.client.onUpdate('updateUserStatus', (u: TdObject) => {
      if ((u['user_id'] as number | undefined) === this.userId) {
        this.statusText = formatUserStatus(u['status'] as TdObject | undefined, Math.floor(Date.now() / 1000));
        this.notify();
      }
    }));
    this.loadUser();
    this.loadFullInfo();
    this.loadStories();
    this.loadGifts();
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
      console.error(`ProfileStore.${tag} failed: ${e.message}`);
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

  private loadUser(): void {
    const req: TdRequest = { '@type': 'getUser' };
    req['user_id'] = this.userId;
    this.send(req, 'getUser', (user: TdObject) => {
      const first = (user['first_name'] as string | undefined) ?? '';
      const last = (user['last_name'] as string | undefined) ?? '';
      this.name = `${first}${last !== '' ? ' ' + last : ''}`;
      this.initials = this.name.length > 0 ? this.name.substring(0, 1).toUpperCase() : '?';
      this.phone = (user['phone_number'] as string | undefined) ?? '';
      this.isContact = (user['is_contact'] as boolean | undefined) ?? false;
      this.statusText = formatUserStatus(user['status'] as TdObject | undefined, Math.floor(Date.now() / 1000));
      const un = user['usernames'] as TdObject | undefined;
      this.usernames = un !== undefined ? ((un['active_usernames'] as string[] | undefined) ?? []) : [];
      const photo = user['profile_photo'] as TdObject | undefined;
      const big = photo !== undefined ? (photo['big'] as TdObject | undefined) : undefined;
      const fileId = big !== undefined ? ((big['id'] as number | undefined) ?? 0) : 0;
      this.download(fileId, (p: string) => { this.avatarPath = p; });
      this.notify();
    });
  }

  private loadFullInfo(): void {
    const req: TdRequest = { '@type': 'getUserFullInfo' };
    req['user_id'] = this.userId;
    this.send(req, 'getUserFullInfo', (full: TdObject) => {
      const bioFt = full['bio'] as TdObject | undefined;
      this.bio = bioFt !== undefined ? ((bioFt['text'] as string | undefined) ?? '') : '';
      // Bots have no bio; surface the bot description in its place.
      if (this.bio === '') {
        const botInfo = full['bot_info'] as TdObject | undefined;
        const botDesc = botInfo !== undefined ? ((botInfo['short_description'] as string | undefined) ?? '') : '';
        const botFull = botInfo !== undefined ? ((botInfo['description'] as string | undefined) ?? '') : '';
        this.bio = botDesc !== '' ? botDesc : botFull;
      }
      this.personalChatId = (full['personal_chat_id'] as number | undefined) ?? 0;
      this.parseBusiness(full['business_info'] as TdObject | undefined);
      if (this.personalChatId !== 0) {
        this.loadChannel(this.personalChatId);
      }
      const groupCount = (full['group_in_common_count'] as number | undefined) ?? 0;
      console.info(`ProfileStore: fullInfo groups=${groupCount} gifts=${(full['gift_count'] as number | undefined) ?? 0} personalChat=${this.personalChatId}`);
      if (groupCount > 0) {
        this.loadGroupsInCommon();
      }
      this.notify();
    });
  }

  // "营业中 / 7 × 24 小时营业" from Telegram Business opening hours.
  private parseBusiness(biz: TdObject | undefined): void {
    if (biz === undefined) {
      return;
    }
    this.bizOpen = ((biz['next_close_in'] as number | undefined) ?? 0) > 0;
    const hours = (biz['local_opening_hours'] as TdObject | undefined)
      ?? (biz['opening_hours'] as TdObject | undefined);
    if (hours !== undefined) {
      const intervals = (hours['opening_hours'] as TdObject[] | undefined) ?? [];
      let total = 0;
      for (const iv of intervals) {
        total += ((iv['end_minute'] as number | undefined) ?? 0) - ((iv['start_minute'] as number | undefined) ?? 0);
      }
      this.bizHoursText = total >= WEEK_MINUTES ? '7 × 24 小时营业' : '查看营业时间';
    }
    const loc = biz['location'] as TdObject | undefined;
    this.bizAddress = loc !== undefined ? ((loc['address'] as string | undefined) ?? '') : '';
  }

  private loadChannel(chatId: number): void {
    const req: TdRequest = { '@type': 'getChat' };
    req['chat_id'] = chatId;
    this.send(req, 'getChat(channel)', (chat: TdObject) => {
      this.chTitle = (chat['title'] as string | undefined) ?? '';
      this.chInitials = this.chTitle.length > 0 ? this.chTitle.substring(0, 1).toUpperCase() : '?';
      this.chPreview = formatPreview(chat['last_message'] as TdObject | undefined ?? null);
      const photo = chat['photo'] as TdObject | undefined;
      const small = photo !== undefined ? (photo['small'] as TdObject | undefined) : undefined;
      this.download(small !== undefined ? ((small['id'] as number | undefined) ?? 0) : 0,
        (p: string) => { this.chAvatarPath = p; });
      const type = chat['type'] as TdObject | undefined;
      const sgId = type !== undefined ? ((type['supergroup_id'] as number | undefined) ?? 0) : 0;
      if (sgId !== 0) {
        const sg: TdRequest = { '@type': 'getSupergroupFullInfo' };
        sg['supergroup_id'] = sgId;
        this.send(sg, 'getSupergroupFullInfo', (f: TdObject) => {
          const c = (f['member_count'] as number | undefined) ?? 0;
          if (c > 0) {
            this.chSubs = `${formatMemberCount(c)} 位订阅者`;
            this.notify();
          }
        });
      }
      this.notify();
    });
  }

  // Page through ALL groups in common (the API caps each page; keep requesting
  // from the last chat id until a page comes back empty).
  private loadGroupsInCommon(offsetChatId: number = 0): void {
    const req: TdRequest = { '@type': 'getGroupsInCommon' };
    req['user_id'] = this.userId;
    req['offset_chat_id'] = offsetChatId;
    req['limit'] = 100;
    this.send(req, 'getGroupsInCommon', (res: TdObject) => {
      const ids = (res['chat_ids'] as number[] | undefined) ?? [];
      console.info(`ProfileStore: groupsInCommon page=${ids.length} offset=${offsetChatId}`);
      if (ids.length > 0) {
        this.loadGroupsInCommon(ids[ids.length - 1]);
      }
      for (const id of ids) {
        const cr: TdRequest = { '@type': 'getChat' };
        cr['chat_id'] = id;
        this.send(cr, 'getChat(group)', (chat: TdObject) => {
          const title = (chat['title'] as string | undefined) ?? '';
          const g: CommonGroup = {
            id,
            title,
            initials: title.length > 0 ? title.substring(0, 1).toUpperCase() : '?',
            avatarPath: ''
          };
          this.groups = [...this.groups, g];
          const photo = chat['photo'] as TdObject | undefined;
          const small = photo !== undefined ? (photo['small'] as TdObject | undefined) : undefined;
          this.download(small !== undefined ? ((small['id'] as number | undefined) ?? 0) : 0,
            (p: string) => {
              this.groups = this.groups.map((x: CommonGroup): CommonGroup => x.id === id
                ? { id: x.id, title: x.title, initials: x.initials, avatarPath: p } : x);
            });
          this.notify();
        });
      }
    });
  }

  // Profile ("posted to chat page") stories — the 动态 grid.
  private loadStories(): void {
    // The private chat may not exist locally yet ("Chat not found") —
    // materialize it first, then query the profile stories.
    const create: TdRequest = { '@type': 'createPrivateChat' };
    create['user_id'] = this.userId;
    create['force'] = false;
    this.send(create, 'createPrivateChat', () => this.loadStoriesNow());
  }

  private loadStoriesNow(): void {
    const req: TdRequest = { '@type': 'getChatPostedToChatPageStories' };
    req['chat_id'] = this.userId; // a user's chat id equals the user id
    req['from_story_id'] = 0;
    req['limit'] = 30;
    this.send(req, 'getStories', (res: TdObject) => {
      const arr = (res['stories'] as TdObject[] | undefined) ?? [];
      for (const s of arr) {
        const id = (s['id'] as number | undefined) ?? 0;
        const content = s['content'] as TdObject | undefined;
        const ct = content !== undefined ? ((content['@type'] as string | undefined) ?? '') : '';
        let thumbFileId = 0;
        let duration = 0;
        let isVideo = false;
        if (ct === 'storyContentVideo') {
          isVideo = true;
          const video = content!['video'] as TdObject | undefined;
          duration = video !== undefined ? Math.round((video['duration'] as number | undefined) ?? 0) : 0;
          const thumb = video !== undefined ? (video['thumbnail'] as TdObject | undefined) : undefined;
          const file = thumb !== undefined ? (thumb['file'] as TdObject | undefined) : undefined;
          thumbFileId = file !== undefined ? ((file['id'] as number | undefined) ?? 0) : 0;
        } else if (ct === 'storyContentPhoto') {
          const photo = content!['photo'] as TdObject | undefined;
          const sizes = photo !== undefined ? ((photo['sizes'] as TdObject[] | undefined) ?? []) : [];
          if (sizes.length > 0) {
            const file = sizes[0]['photo'] as TdObject | undefined;
            thumbFileId = file !== undefined ? ((file['id'] as number | undefined) ?? 0) : 0;
          }
        } else {
          continue;
        }
        const item: StoryItem = { id, thumbPath: '', duration, isVideo };
        this.stories = [...this.stories, item];
        this.download(thumbFileId, (p: string) => {
          this.stories = this.stories.map((x: StoryItem): StoryItem => x.id === id
            ? { id: x.id, thumbPath: p, duration: x.duration, isVideo: x.isVideo } : x);
        });
      }
      this.notify();
    });
  }

  // Raster file id for a sticker: prefer the thumbnail (TGS/WEBM animated
  // stickers can't be rendered by Image); WEBP stickers may use the file itself.
  private stickerRasterFileId(sticker: TdObject | undefined): number {
    if (sticker === undefined) {
      return 0;
    }
    const thumb = sticker['thumbnail'] as TdObject | undefined;
    const thumbFile = thumb !== undefined ? (thumb['file'] as TdObject | undefined) : undefined;
    let fileId = thumbFile !== undefined ? ((thumbFile['id'] as number | undefined) ?? 0) : 0;
    if (fileId === 0) {
      const fmt = sticker['format'] as TdObject | undefined;
      if (fmt !== undefined && fmt['@type'] === 'stickerFormatWebp') {
        const file = sticker['sticker'] as TdObject | undefined;
        fileId = file !== undefined ? ((file['id'] as number | undefined) ?? 0) : 0;
      }
    }
    return fileId;
  }

  // Gift catalog for the send-gift picker (prices are in Telegram Stars).
  loadAvailableGifts(): void {
    if (this.availableLoaded) {
      return;
    }
    this.availableLoaded = true;
    const req: TdRequest = { '@type': 'getAvailableGifts' };
    this.send(req, 'getAvailableGifts', (res: TdObject) => {
      const arr = (res['gifts'] as TdObject[] | undefined) ?? [];
      console.info(`ProfileStore: availableGifts=${arr.length}`);
      for (const ag of arr) {
        const gift = ag['gift'] as TdObject | undefined;
        if (gift === undefined) {
          continue;
        }
        const id = `${gift['id']}`; // int64 arrives as a string in TDLib JSON
        const stars = (gift['star_count'] as number | undefined) ?? 0;
        const item: AvailGift = { id, stickerPath: '', stars };
        this.availableGifts = [...this.availableGifts, item];
        this.download(this.stickerRasterFileId(gift['sticker'] as TdObject | undefined), (p: string) => {
          this.availableGifts = this.availableGifts.map((x: AvailGift): AvailGift => x.id === id
            ? { id: x.id, stickerPath: p, stars: x.stars } : x);
        });
      }
      this.notify();
    });
  }

  // Send a catalog gift to this user, paying with the account's Star balance.
  sendGift(giftId: string, onResult: (error: string) => void): void {
    const owner: TdObject = { '@type': 'messageSenderUser' };
    owner['user_id'] = this.userId;
    const text: TdObject = { '@type': 'formattedText' };
    text['text'] = '';
    const req: TdRequest = { '@type': 'sendGift' };
    req['gift_id'] = giftId;
    req['owner_id'] = owner;
    req['text'] = text;
    req['is_private'] = false;
    req['pay_for_upgrade'] = false;
    this.client.send(req).then(() => {
      onResult('');
    }).catch((e: TdError) => {
      console.error(`ProfileStore.sendGift failed: ${e.message}`);
      onResult(e.message);
    });
  }

  private loadGifts(): void {
    const sender: TdObject = { '@type': 'messageSenderUser' };
    sender['user_id'] = this.userId;
    const req: TdRequest = { '@type': 'getReceivedGifts' };
    req['business_connection_id'] = '';
    req['owner_id'] = sender;
    req['collection_id'] = 0;
    req['exclude_unsaved'] = false;
    req['exclude_saved'] = false;
    req['exclude_unlimited'] = false;
    req['exclude_upgradable'] = false;
    req['exclude_non_upgradable'] = false;
    req['exclude_upgraded'] = false;
    req['sort_by_price'] = false;
    req['offset'] = '';
    req['limit'] = 30;
    this.send(req, 'getReceivedGifts', (res: TdObject) => {
      const arr = (res['gifts'] as TdObject[] | undefined) ?? [];
      console.info(`ProfileStore: gifts total=${(res['total_count'] as number | undefined) ?? 0} page=${arr.length}`);
      for (const rg of arr) {
        const rid = (rg['received_gift_id'] as string | undefined) ?? '';
        const sent = rg['gift'] as TdObject | undefined;
        const st = sent !== undefined ? ((sent['@type'] as string | undefined) ?? '') : '';
        if (st !== 'sentGiftRegular') {
          continue; // upgraded gifts carry a different model; keep it simple
        }
        const gift = sent!['gift'] as TdObject | undefined;
        const sticker = gift !== undefined ? (gift['sticker'] as TdObject | undefined) : undefined;
        // Gift stickers are usually TGS (Lottie) which Image can't render —
        // prefer the raster thumbnail; fall back to the sticker file only for WEBP.
        let fileId = 0;
        if (sticker !== undefined) {
          const thumb = sticker['thumbnail'] as TdObject | undefined;
          const thumbFile = thumb !== undefined ? (thumb['file'] as TdObject | undefined) : undefined;
          fileId = thumbFile !== undefined ? ((thumbFile['id'] as number | undefined) ?? 0) : 0;
          if (fileId === 0) {
            const fmt = sticker['format'] as TdObject | undefined;
            if (fmt !== undefined && fmt['@type'] === 'stickerFormatWebp') {
              const file = sticker['sticker'] as TdObject | undefined;
              fileId = file !== undefined ? ((file['id'] as number | undefined) ?? 0) : 0;
            }
          }
        }
        const item: GiftItem = { id: rid, stickerPath: '' };
        this.gifts = [...this.gifts, item];
        this.download(fileId, (p: string) => {
          this.gifts = this.gifts.map((x: GiftItem): GiftItem => x.id === rid
            ? { id: x.id, stickerPath: p } : x);
        });
      }
      this.notify();
    });
  }
}
