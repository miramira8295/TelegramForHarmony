import { router, promptAction } from '@kit.ArkUI';
import { getTdClient } from '../../tdkit/Globals';
import { ProfileStore, CommonGroup, StoryItem, GiftItem, AvailGift } from '../../store/ProfileStore';
import { AvatarView } from '../chatlist/AvatarView';
import { TdObject, TdRequest, TdError } from '../../tdkit/TdTypes';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { ExpandableText } from './ExpandableText';
import { openUrl } from '../../util/openUrl';
import { common } from '@kit.AbilityKit';

const CARD_BG: ResourceColor = Color.White;
const CARD_RADIUS: number = 14;
const PAGE_BG: string = '#EFEFF4';

// User profile page (Telegram-style): avatar header, quick actions, personal
// channel card, info card (phone/bio/usernames/business), add-contact, and
// 动态/礼物/群组 tabs. Store data is MIRRORED into @State fields — ArkUI's
// minimal-update re-renders only nodes that read changed state, so reading
// plain store fields from build() would never refresh.
@Entry
@Preview
@Component
struct ProfilePage {
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('screenWidthVp') screenW: number = 360;
  @State profTab: number = 0; // 0 动态 / 1 礼物 / 2 群组
  @State name: string = '';
  @State initials: string = '?';
  @State avatarPath: string = '';
  @State statusText: string = '';
  @State phone: string = '';
  @State usernames: string[] = [];
  @State isContact: boolean = false;
  @State bio: string = '';
  @State bioEntities: TdObject[] = [];
  @State personalChatId: number = 0;
  @State bizOpen: boolean = false;
  @State bizHoursText: string = '';
  @State bizAddress: string = '';
  @State bizLat: number = 0;
  @State bizLng: number = 0;
  @State chTitle: string = '';
  @State chInitials: string = '?';
  @State chAvatarPath: string = '';
  @State chSubs: string = '';
  @State chPreview: string = '';
  @State groups: CommonGroup[] = [];
  @State stories: StoryItem[] = [];
  @State gifts: GiftItem[] = [];
  @State availGifts: AvailGift[] = [];
  @State showGiftPicker: boolean = false;
  private userId: number = 0;
  private store: ProfileStore | null = null;
  private unsub: (() => void) | null = null;

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, Object> | undefined;
    this.userId = params !== undefined ? (params['userId'] as number) : 0;
    const store = new ProfileStore(getTdClient(), this.userId);
    this.store = store;
    this.unsub = store.subscribe(() => { this.refresh(); });
    store.open();
  }

  aboutToDisappear(): void {
    if (this.unsub !== null) { this.unsub(); this.unsub = null; }
    if (this.store !== null) { this.store.close(); this.store = null; }
  }

  // Copy the store snapshot into @State so every card re-renders on updates.
  private refresh(): void {
    const s = this.store;
    if (s === null) {
      return;
    }
    this.name = s.name;
    this.initials = s.initials;
    this.avatarPath = s.avatarPath;
    this.statusText = s.statusText;
    this.phone = s.phone;
    this.usernames = s.usernames;
    this.isContact = s.isContact;
    this.bio = s.bio;
    this.bioEntities = s.bioEntities;
    this.personalChatId = s.personalChatId;
    this.bizOpen = s.bizOpen;
    this.bizHoursText = s.bizHoursText;
    this.bizAddress = s.bizAddress;
    this.bizLat = s.bizLat;
    this.bizLng = s.bizLng;
    this.chTitle = s.chTitle;
    this.chInitials = s.chInitials;
    this.chAvatarPath = s.chAvatarPath;
    this.chSubs = s.chSubs;
    this.chPreview = s.chPreview;
    this.groups = s.groups;
    this.stories = s.stories;
    this.gifts = s.gifts;
    this.availGifts = s.availableGifts;
  }

  private sendGift(g: AvailGift): void {
    if (this.store === null) {
      return;
    }
    this.store.sendGift(g.id, (error: string) => {
      if (error === '') {
        this.showGiftPicker = false;
        promptAction.showToast({ message: '礼物已发送 🎁' });
      } else if (error.indexOf('BALANCE') >= 0) {
        promptAction.showToast({ message: '星币余额不足' });
      } else {
        promptAction.showToast({ message: `发送失败: ${error}` });
      }
    });
  }

  private openChat(chatId: number): void {
    const params: Record<string, Object> = { 'chatId': chatId };
    router.pushUrl({ url: 'pages/chat/ChatPage', params: params });
  }

  private sendMessage(): void {
    // Ensure the private chat exists before navigating into it.
    const req: TdRequest = { '@type': 'createPrivateChat' };
    req['user_id'] = this.userId;
    req['force'] = false;
    getTdClient().send(req).then((chat: TdObject) => {
      const id = chat['id'] as number | undefined;
      if (id !== undefined) {
        this.openChat(id);
      }
    }).catch((e: TdError) => {
      console.error(`ProfilePage.createPrivateChat failed: ${e.message}`);
    });
  }

  private addContact(): void {
    const contact: TdObject = { '@type': 'contact' };
    contact['phone_number'] = this.phone;
    contact['first_name'] = this.name !== '' ? this.name : '联系人';
    contact['last_name'] = '';
    contact['user_id'] = this.userId;
    const req: TdRequest = { '@type': 'addContact' };
    req['contact'] = contact;
    req['share_phone_number'] = false;
    getTdClient().send(req).then(() => {
      this.isContact = true;
    }).catch((e: TdError) => {
      console.error(`ProfilePage.addContact failed: ${e.message}`);
    });
  }

  private toggleMute(): void {
    const settings: TdObject = { '@type': 'chatNotificationSettings' };
    settings['use_default_mute_for'] = false;
    settings['mute_for'] = 2147483647; // "forever"
    const req: TdRequest = { '@type': 'setChatNotificationSettings' };
    req['chat_id'] = this.userId;
    req['notification_settings'] = settings;
    getTdClient().send(req).catch((e: TdError) => {
      console.error(`ProfilePage.setChatNotificationSettings failed: ${e.message}`);
    });
  }

  // 位置 tap → system map app via geo: URI (coordinates when TDLib provides
  // them, otherwise an address query).
  private openMap(): void {
    const hasCoords = this.bizLat !== 0 || this.bizLng !== 0;
    const q = encodeURIComponent(this.bizAddress);
    const uri = hasCoords ? `geo:${this.bizLat},${this.bizLng}?q=${q}` : `geo:0,0?q=${q}`;
    openUrl(getContext(this) as common.UIAbilityContext, uri);
  }

  private storyCell(): number {
    return (this.screenW - 4) / 3;
  }

  private formatDuration(totalSeconds: number): string {
    const m = Math.floor(totalSeconds / 60);
    const s = totalSeconds % 60;
    return `${m}:${`${s}`.padStart(2, '0')}`;
  }

  @Builder
  circleButton(symbol: string, onTap: () => void) {
    Row() {
      SymbolGlyph($r(symbol)).fontSize(22).fontColor([COLOR_TEXT_PRIMARY]);
    }
    .width(40).height(40).borderRadius(20).backgroundColor(Color.White)
    .justifyContent(FlexAlign.Center)
    .shadow({ radius: 4, color: '#12000000', offsetX: 0, offsetY: 1 })
    .onClick(onTap);
  }

  @Builder
  actionButton(symbol: string, label: string, onTap: () => void) {
    Column({ space: 5 }) {
      SymbolGlyph($r(symbol)).fontSize(22).fontColor([COLOR_PRIMARY]);
      Text(label).fontSize(12).fontColor(COLOR_PRIMARY);
    }
    .layoutWeight(1).height(62)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(CARD_BG).borderRadius(CARD_RADIUS)
    .onClick(onTap);
  }

  @Builder
  infoRow(value: string, label: string, valueColor: ResourceColor) {
    Column({ space: 2 }) {
      Text(value).fontSize(15).fontColor(valueColor).copyOption(CopyOptions.LocalDevice);
      Text(label).fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({ top: 8, bottom: 8 });
  }

  @Builder
  header() {
    Column({ space: 8 }) {
      Row() {
        this.circleButton('sys.symbol.chevron_left', () => { router.back(); });
        Blank().layoutWeight(1);
        this.circleButton('sys.symbol.more', () => {});
      }.width('100%').padding({ left: 12, right: 12 });
      AvatarView({
        avatarPath: this.avatarPath, initials: this.initials,
        colorSeed: this.userId, avatarSize: 100
      });
      Text(this.name)
        .fontSize(20).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: '86%' });
      Text(this.statusText).fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
    }
    .width('100%')
    .padding({ top: this.topSafe + 8 });
  }

  @Builder
  actionsRow() {
    Row({ space: 8 }) {
      this.actionButton('sys.symbol.message', '消息', () => { this.sendMessage(); });
      this.actionButton('sys.symbol.bell', '静音', () => { this.toggleMute(); });
      this.actionButton('sys.symbol.phone', '通话', () => {});
      this.actionButton('sys.symbol.gift', '礼物', () => {
        if (this.store !== null) {
          this.store.loadAvailableGifts();
        }
        this.showGiftPicker = true;
      });
    }
    .width('100%').padding({ left: 12, right: 12, top: 14 });
  }

  @Builder
  channelCard() {
    // Outer wrapper carries the margins — width('100%') and horizontal margin
    // on the same node conflict in ArkUI (the margin is swallowed).
    Column() {
      Column({ space: 8 }) {
        Row({ space: 8 }) {
          Text('频道').fontSize(14).fontColor(COLOR_PRIMARY).fontWeight(FontWeight.Bold);
          Text(this.chSubs).fontSize(13).fontColor(COLOR_PRIMARY);
          Blank().layoutWeight(1);
        }.width('100%');
        Row({ space: 10 }) {
          AvatarView({
            avatarPath: this.chAvatarPath, initials: this.chInitials,
            colorSeed: this.personalChatId, avatarSize: 46
          });
          Column({ space: 2 }) {
            Text(this.chTitle).fontSize(15).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
            Text(this.chPreview).fontSize(13).fontColor(COLOR_TEXT_SECONDARY)
              .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis });
          }.alignItems(HorizontalAlign.Start).layoutWeight(1);
        }.width('100%');
      }
      .width('100%').padding(12)
      .backgroundColor(CARD_BG).borderRadius(CARD_RADIUS)
      .alignItems(HorizontalAlign.Start)
      .onClick(() => { this.openChat(this.personalChatId); });
    }
    .margin({ left: 12, right: 12, top: 12 });
  }

  @Builder
  sectionDivider() {
    Divider().color('#EDEDED').strokeWidth(0.7);
  }

  @Builder
  infoCard() {
    Column() {
      Column() {
        if (this.phone !== '') {
          this.infoRow(`+${this.phone}`, this.phone.startsWith('888') ? '匿名号码' : '手机号码', COLOR_TEXT_PRIMARY);
        }
        if (this.bio !== '') {
          if (this.phone !== '') {
            this.sectionDivider();
          }
          Column({ space: 2 }) {
            ExpandableText({ content: this.bio, entities: this.bioEntities });
            Text('个人简介').fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          .padding({ top: 8, bottom: 8 });
        }
        if (this.usernames.length > 0) {
          if (this.phone !== '' || this.bio !== '') {
            this.sectionDivider();
          }
          Row() {
            Column({ space: 2 }) {
              Text(`@${this.usernames[0]}`).fontSize(15).fontColor(COLOR_PRIMARY).copyOption(CopyOptions.LocalDevice);
              if (this.usernames.length > 1) {
                Text(`同时 ${this.usernames.slice(1).map((u: string) => `@${u}`).join(', ')}`)
                  .fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
              } else {
                Text('用户名').fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
              }
            }.alignItems(HorizontalAlign.Start).layoutWeight(1);
            SymbolGlyph($r('sys.symbol.qrcode')).fontSize(22).fontColor([COLOR_TEXT_SECONDARY]);
          }
          .width('100%').padding({ top: 8, bottom: 8 })
          .alignItems(VerticalAlign.Center);
        }
        if (this.bizHoursText !== '') {
          if (this.phone !== '' || this.bio !== '' || this.usernames.length > 0) {
            this.sectionDivider();
          }
          Row() {
            Column({ space: 2 }) {
              Text(this.bizOpen ? '营业中' : '休息中')
                .fontSize(15).fontColor(this.bizOpen ? '#34C759' : '#FF3B30');
              Text('营业时间').fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
            }.alignItems(HorizontalAlign.Start).layoutWeight(1);
            Text(this.bizHoursText).fontSize(14).fontColor(COLOR_TEXT_PRIMARY);
          }
          .width('100%').padding({ top: 8, bottom: 8 })
          .alignItems(VerticalAlign.Center);
        }
        if (this.bizAddress !== '') {
          if (this.phone !== '' || this.bio !== '' || this.usernames.length > 0 || this.bizHoursText !== '') {
            this.sectionDivider();
          }
          Column({ space: 2 }) {
            Text(this.bizAddress).fontSize(15).fontColor(COLOR_PRIMARY)
              .copyOption(CopyOptions.LocalDevice);
            Text('位置 · 点击打开地图').fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          .padding({ top: 8, bottom: 8 })
          .onClick(() => { this.openMap(); });
        }
        if (this.phone === '' && this.bio === '' && this.usernames.length === 0
          && this.bizHoursText === '' && this.bizAddress === '') {
          Text('暂无资料').fontSize(14).fontColor(COLOR_TEXT_SECONDARY)
            .padding({ top: 10, bottom: 10 });
        }
      }
      .width('100%').padding({ left: 12, right: 12, top: 4, bottom: 4 })
      .backgroundColor(CARD_BG).borderRadius(CARD_RADIUS)
      .alignItems(HorizontalAlign.Start);
    }
    .margin({ left: 12, right: 12, top: 12 });
  }

  @Builder
  addContactCard() {
    Column() {
      Row({ space: 12 }) {
        SymbolGlyph($r('sys.symbol.person_badge_plus'))
          .fontSize(22)
          .fontColor([COLOR_TEXT_PRIMARY]);
        Text('添加为联系人')
          .fontSize(15)
          .fontColor(COLOR_TEXT_PRIMARY);
      }
      .width('100%')
      .padding(14)
      .backgroundColor(CARD_BG)
      .borderRadius(CARD_RADIUS)
    }
    .margin({ left: 12, right: 12, top: 12 });
  }

  @Builder
  tabPill(label: string, index: number) {
    Text(label)
      .fontSize(14)
      .fontWeight(this.profTab === index ? FontWeight.Medium : FontWeight.Normal)
      .fontColor(this.profTab === index ? COLOR_PRIMARY : COLOR_TEXT_SECONDARY)
      .backgroundColor(this.profTab === index ? '#E3F0FB' : Color.Transparent)
      .borderRadius(14)
      .padding({ left: 14, right: 14, top: 5, bottom: 5 })
      .onClick(() => { this.profTab = index; });
  }

  @Builder
  tabsBar() {
    Row({ space: 4 }) {
      this.tabPill('动态', 0);
      this.tabPill('礼物', 1);
      this.tabPill('群组', 2);
    }
    .padding(3)
    .backgroundColor(CARD_BG).borderRadius(18)
    .margin({ top: 14, bottom: 8 });
  }

  @Builder
  emptyHint(text: string) {
    Text(text).fontSize(14).fontColor(COLOR_TEXT_SECONDARY)
      .width('100%').textAlign(TextAlign.Center)
      .padding({ top: 30, bottom: 30 });
  }

  @Builder
  storiesGrid() {
    if (this.stories.length === 0) {
      this.emptyHint('暂无动态');
    } else {
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.stories, (it: StoryItem) => {
          Stack({ alignContent: Alignment.BottomStart }) {
            if (it.thumbPath !== '') {
              Image(it.thumbPath.startsWith('/') ? `file://${it.thumbPath}` : it.thumbPath)
                .width(this.storyCell()).height(this.storyCell() * 1.33).objectFit(ImageFit.Cover);
            } else {
              Column().width(this.storyCell()).height(this.storyCell() * 1.33).backgroundColor('#D8D8D8');
            }
            if (it.isVideo) {
              Text(`▶ ${this.formatDuration(it.duration)}`)
                .fontSize(11).fontColor(Color.White)
                .backgroundColor('#00000066').borderRadius(4)
                .padding({ left: 4, right: 4, top: 1, bottom: 1 })
                .margin({ left: 6, bottom: 6 });
            }
          }
          .width(this.storyCell()).height(this.storyCell() * 1.33)
          .margin({ right: 1, bottom: 1 });
        }, (it: StoryItem) => `story_${it.id}_${it.thumbPath}`);
      }.width('100%');
    }
  }

  @Builder
  giftsGrid() {
    if (this.gifts.length === 0) {
      this.emptyHint('暂无礼物');
    } else {
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
        ForEach(this.gifts, (g: GiftItem) => {
          if (g.stickerPath !== '') {
            Image(g.stickerPath.startsWith('/') ? `file://${g.stickerPath}` : g.stickerPath)
              .width(this.storyCell()).height(this.storyCell()).objectFit(ImageFit.Contain)
              .padding(10);
          } else {
            // Animated (TGS/WEBM) stickers without a raster thumbnail can't be
            // rendered by Image — show a gift glyph instead of a blank cell.
            Text('🎁').fontSize(40)
              .width(this.storyCell()).height(this.storyCell())
              .textAlign(TextAlign.Center);
          }
        }, (g: GiftItem) => `gift_${g.id}_${g.stickerPath}`);
      }.width('100%');
    }
  }

  @Builder
  groupsList() {
    Column() {
      if (this.groups.length === 0) {
        this.emptyHint('暂无共同群组');
      } else {
        Column() {
          ForEach(this.groups, (g: CommonGroup, index: number) => {
            if (index > 0) {
              // Row separator, indented past the avatar (Telegram-style).
              Divider().color('#EDEDED').strokeWidth(0.7).margin({ left: 68 });
            }
            Row({ space: 12 }) {
              AvatarView({ avatarPath: g.avatarPath, initials: g.initials, colorSeed: g.id, avatarSize: 42 });
              Text(g.title).fontSize(15).fontColor(COLOR_TEXT_PRIMARY)
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1);
            }
            .width('100%').padding({ left: 14, right: 14, top: 8, bottom: 8 })
            .onClick(() => { this.openChat(g.id); });
          }, (g: CommonGroup) => `grp_${g.id}_${g.avatarPath}`);
        }
        .width('100%').backgroundColor(CARD_BG).borderRadius(CARD_RADIUS)
        .padding({ top: 4, bottom: 4 });
      }
    }
    .margin({ left: 12, right: 12 });
  }

  // Bottom sheet with the sendable gift catalog (paid with Telegram Stars).
  @Builder
  giftPicker() {
    Column() {
      // Dim area above the sheet — tap to dismiss.
      Column().width('100%').layoutWeight(1)
        .onClick(() => { this.showGiftPicker = false; });
      Column({ space: 10 }) {
        Text('发送礼物').fontSize(16).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY);
        Text('使用 Telegram 星币支付').fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
        Scroll() {
          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
            ForEach(this.availGifts, (g: AvailGift) => {
              Column({ space: 4 }) {
                if (g.stickerPath !== '') {
                  Image(g.stickerPath.startsWith('/') ? `file://${g.stickerPath}` : g.stickerPath)
                    .width(56).height(56).objectFit(ImageFit.Contain);
                } else {
                  Text('🎁').fontSize(40).width(56).height(56).textAlign(TextAlign.Center);
                }
                Text(`⭐ ${g.stars}`).fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
              }
              .width((this.screenW - 48) / 4)
              .padding({ top: 8, bottom: 8 })
              .onClick(() => { this.sendGift(g); });
            }, (g: AvailGift) => `avail_${g.id}_${g.stickerPath}`);
          }.width('100%');
        }.constraintSize({ maxHeight: 360 }).scrollBar(BarState.Off);
        if (this.availGifts.length === 0) {
          Text('加载礼物目录...').fontSize(13).fontColor(COLOR_TEXT_SECONDARY).padding(16);
        }
      }
      .width('100%').padding({ left: 12, right: 12, top: 14, bottom: 24 })
      .backgroundColor(Color.White)
      .borderRadius({ topLeft: 18, topRight: 18 });
    }
    .width('100%').height('100%')
    .backgroundColor('#00000066');
  }

  build() {
    Stack() {
      Scroll() {
        Column() {
          this.header();
          this.actionsRow();
          if (this.personalChatId !== 0 && this.chTitle !== '') {
            this.channelCard();
          }
          this.infoCard();
          if (!this.isContact) {
            this.addContactCard();
          }
          this.tabsBar();
          if (this.profTab === 0) {
            this.storiesGrid();
          } else if (this.profTab === 1) {
            this.giftsGrid();
          } else {
            this.groupsList();
          }
        }
        .width('100%')
        .padding({ bottom: 24 })
      }
      .width('100%').height('100%')
      .backgroundColor(PAGE_BG)
      .align(Alignment.Top)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]);

      if (this.showGiftPicker) {
        this.giftPicker();
      }
    }.width('100%').height('100%');
  }
}
