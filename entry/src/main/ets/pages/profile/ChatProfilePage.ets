import { router, promptAction } from '@kit.ArkUI';
import { getTdClient } from '../../tdkit/Globals';
import { ChatProfileStore, MemberItem } from '../../store/ChatProfileStore';
import { AvatarView } from '../chatlist/AvatarView';
import { TdObject, TdRequest, TdError } from '../../tdkit/TdTypes';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { ExpandableText } from './ExpandableText';

const CARD_BG: ResourceColor = Color.White;
const CARD_RADIUS: number = 14;

// Group / channel detail page — visually mirrors ProfilePage (header, action
// row, info card) with a member list instead of the personal tabs.
@Entry
@Component
struct ChatProfilePage {
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @State title: string = '';
  @State initials: string = '?';
  @State avatarPath: string = '';
  @State subtitle: string = '';
  @State description: string = '';
  @State chatUsername: string = '';
  @State isChannel: boolean = false;
  @State isMuted: boolean = false;
  @State members: MemberItem[] = [];
  private chatId: number = 0;
  private store: ChatProfileStore | null = null;
  private unsub: (() => void) | null = null;

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, Object> | undefined;
    this.chatId = params !== undefined ? (params['chatId'] as number) : 0;
    const store = new ChatProfileStore(getTdClient(), this.chatId);
    this.store = store;
    this.unsub = store.subscribe(() => { this.refresh(); });
    store.open();
  }

  aboutToDisappear(): void {
    if (this.unsub !== null) { this.unsub(); this.unsub = null; }
    if (this.store !== null) { this.store.close(); this.store = null; }
  }

  // Mirror the store snapshot into @State (plain-field reads don't re-render).
  private refresh(): void {
    const s = this.store;
    if (s === null) {
      return;
    }
    this.title = s.title;
    this.initials = s.initials;
    this.avatarPath = s.avatarPath;
    this.subtitle = s.subtitle;
    this.description = s.description;
    this.chatUsername = s.username;
    this.isChannel = s.isChannel;
    this.isMuted = s.isMuted;
    this.members = s.members;
  }

  private openChat(): void {
    const params: Record<string, Object> = { 'chatId': this.chatId };
    router.pushUrl({ url: 'pages/chat/ChatPage', params: params });
  }

  private toggleMute(): void {
    const willMute = !this.isMuted;
    const settings: TdObject = { '@type': 'chatNotificationSettings' };
    settings['use_default_mute_for'] = false;
    settings['mute_for'] = willMute ? 2147483647 : 0; // forever / unmute
    const req: TdRequest = { '@type': 'setChatNotificationSettings' };
    req['chat_id'] = this.chatId;
    req['notification_settings'] = settings;
    getTdClient().send(req).then(() => {
      // The updateChatNotificationSettings event also confirms this, but flip
      // immediately so the button reacts without waiting for the round-trip.
      this.isMuted = willMute;
      promptAction.showToast({ message: willMute ? '已静音' : '已取消静音', duration: 1500 });
    }).catch((e: TdError) => {
      console.error(`ChatProfilePage.setChatNotificationSettings failed: ${e.message}`);
      promptAction.showToast({ message: '操作失败', duration: 1500 });
    });
  }

  private openMemberProfile(userId: number): void {
    const params: Record<string, Object> = { 'userId': userId };
    router.pushUrl({ url: 'pages/profile/ProfilePage', params: params });
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

  // Dedicated builder (not the param-based actionButton): @Builder value
  // params don't re-evaluate on @State change, so the icon/label would stick.
  @Builder
  muteButton() {
    Column({ space: 5 }) {
      Stack() {
        if (this.isMuted) {
          SymbolGlyph($r('sys.symbol.bell')).fontSize(22).fontColor([COLOR_PRIMARY])
            .transition(TransitionEffect.OPACITY
              .combine(TransitionEffect.scale({ x: 0.4, y: 0.4 }))
              .animation({ duration: 220, curve: Curve.EaseOut }));
        } else {
          SymbolGlyph($r('sys.symbol.bell_slash')).fontSize(22).fontColor([COLOR_PRIMARY])
            .transition(TransitionEffect.OPACITY
              .combine(TransitionEffect.scale({ x: 0.4, y: 0.4 }))
              .animation({ duration: 220, curve: Curve.EaseOut }));
        }
      }.height(24);
      Text(this.isMuted ? '取消静音' : '静音').fontSize(12).fontColor(COLOR_PRIMARY);
    }
    .layoutWeight(1).height(62)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(CARD_BG).borderRadius(CARD_RADIUS)
    .onClick(() => { this.toggleMute(); });
  }

  @Builder
  sectionDivider() {
    Divider().color('#EDEDED').strokeWidth(0.7);
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
        colorSeed: this.chatId, avatarSize: 100
      });
      Text(this.title)
        .fontSize(20).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: '86%' });
      if (this.subtitle !== '') {
        Text(this.subtitle).fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
      }
    }
    .width('100%')
    .padding({ top: this.topSafe + 8 });
  }

  @Builder
  actionsRow() {
    Row({ space: 8 }) {
      this.actionButton('sys.symbol.message', '消息', () => { this.openChat(); });
      this.muteButton();
      this.actionButton('sys.symbol.magnifyingglass', '搜索', () => {});
      this.actionButton('sys.symbol.more', '更多', () => {});
    }
    .width('100%').padding({ left: 12, right: 12, top: 14 });
  }

  @Builder
  infoCard() {
    Column() {
      Column() {
        if (this.description !== '') {
          Column({ space: 2 }) {
            ExpandableText({ content: this.description });
            Text('简介').fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%').padding({ top: 8, bottom: 8 });
        }
        if (this.chatUsername !== '') {
          if (this.description !== '') {
            this.sectionDivider();
          }
          Row() {
            Column({ space: 2 }) {
              Text(`@${this.chatUsername}`).fontSize(15).fontColor(COLOR_PRIMARY).copyOption(CopyOptions.LocalDevice);
              Text('链接').fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
            }.alignItems(HorizontalAlign.Start).layoutWeight(1);
            SymbolGlyph($r('sys.symbol.qrcode')).fontSize(22).fontColor([COLOR_TEXT_SECONDARY]);
          }
          .width('100%').padding({ top: 8, bottom: 8 })
          .alignItems(VerticalAlign.Center);
        }
        if (this.description === '' && this.chatUsername === '') {
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
  membersCard() {
    Column() {
      Column() {
        Text(`成员`).fontSize(14).fontColor(COLOR_PRIMARY).fontWeight(FontWeight.Bold)
          .padding({ top: 10, bottom: 4 });
        ForEach(this.members, (m: MemberItem, idx: number) => {
          Column() {
            Row({ space: 10 }) {
              AvatarView({ avatarPath: m.avatarPath, initials: m.initials,
                colorSeed: m.userId, avatarSize: 40 });
              Column({ space: 2 }) {
                Text(m.name).fontSize(15).fontColor(COLOR_TEXT_PRIMARY)
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
                Text(m.status).fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
              }.alignItems(HorizontalAlign.Start).layoutWeight(1);
            }
            .width('100%').padding({ top: 6, bottom: 6 })
            .alignItems(VerticalAlign.Center)
            .onClick(() => { this.openMemberProfile(m.userId); });
            if (idx < this.members.length - 1) {
              Divider().color('#EDEDED').strokeWidth(0.7).margin({ left: 50 });
            }
          }.width('100%');
        }, (m: MemberItem) => `${m.userId}_${m.avatarPath}`);
      }
      .width('100%').padding({ left: 12, right: 12, top: 4, bottom: 8 })
      .backgroundColor(CARD_BG).borderRadius(CARD_RADIUS)
      .alignItems(HorizontalAlign.Start);
    }
    .margin({ left: 12, right: 12, top: 12, bottom: 24 });
  }

  build() {
    Scroll() {
      Column() {
        this.header();
        this.actionsRow();
        this.infoCard();
        if (this.members.length > 0) {
          this.membersCard();
        }
      }
      .width('100%');
    }
    .width('100%').height('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
    .backgroundColor('#EFEFF4')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]);
  }
}
