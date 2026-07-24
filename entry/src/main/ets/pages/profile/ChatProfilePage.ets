import { router, promptAction } from '@kit.ArkUI';
import { getTdClient } from '../../tdkit/Globals';
import { ChatProfileStore, MemberItem } from '../../store/ChatProfileStore';
import { AvatarView } from '../chatlist/AvatarView';
import { QrDialog } from '../common/QrDialog';
import { TdObject, TdRequest, TdError } from '../../tdkit/TdTypes';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { ExpandableText } from './ExpandableText';
import { publicLink } from '../../util/telegramLink';
import {
  createVideoChat, getGroupCall, startScheduledVideoChat
} from '../../tdkit/GroupCallApi';
import { KEY_POWER_SMOOTH_TRANSITIONS, powerAnimationDuration } from '../../store/AppSettings';

const CARD_BG: ResourceColor = $r('app.color.surface');
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
  @State avatarAnimPath: string = '';
  @State subtitle: string = '';
  @State description: string = '';
  @State chatUsername: string = '';
  @State isChannel: boolean = false;
  @State isMuted: boolean = false;
  @State canManageVideoChats: boolean = false;
  @State liveGroupCallId: number = 0;
  @State creatingLive: boolean = false;
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

  @State qrLink: string = '';
  private qrCtrl: CustomDialogController = new CustomDialogController({
    builder: QrDialog({ link: this.qrLink, title: this.title }),
    alignment: DialogAlignment.Center,
    autoCancel: true
  });

  private openQr(): void {
    if (this.chatUsername === '') {
      return;
    }
    this.qrLink = publicLink(this.chatUsername);
    this.qrCtrl.open();
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
    this.avatarAnimPath = s.avatarAnimPath;
    this.subtitle = s.subtitle;
    this.description = s.description;
    this.chatUsername = s.username;
    this.isChannel = s.isChannel;
    this.isMuted = s.isMuted;
    this.canManageVideoChats = s.canManageVideoChats;
    this.liveGroupCallId = s.liveGroupCallId;
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

  private openLiveViewer(groupCallId: number, isRtmpStream: boolean): void {
    const params: Record<string, Object> = {
      'groupCallId': groupCallId,
      'chatId': this.chatId
    };
    router.pushUrl({
      url: isRtmpStream
        ? 'pages/chat/RtmpLiveStreamViewerPage'
        : 'pages/chat/LiveStreamViewerPage',
      params: params
    });
  }

  private async openExistingLive(): Promise<void> {
    if (this.liveGroupCallId <= 0 || this.creatingLive) { return; }
    this.creatingLive = true;
    const groupCallId = this.liveGroupCallId;
    try {
      let groupCall = await getGroupCall(getTdClient(), groupCallId);
      let active = (groupCall['is_active'] as boolean | undefined) ?? false;
      const scheduledStartDate =
        (groupCall['scheduled_start_date'] as number | undefined) ?? 0;
      if (!active && scheduledStartDate > 0 && this.canManageVideoChats) {
        await startScheduledVideoChat(getTdClient(), groupCallId);
        groupCall = await getGroupCall(getTdClient(), groupCallId);
        active = (groupCall['is_active'] as boolean | undefined) ?? false;
      }
      if (!active) {
        promptAction.showToast({ message: '直播尚未开始或已经结束', duration: 1600 });
        return;
      }
      const isRtmp = (groupCall['is_rtmp_stream'] as boolean | undefined) ?? false;
      this.openLiveViewer(groupCallId, isRtmp);
    } catch (caught) {
      const error = caught as TdError;
      promptAction.showToast({ message: `进入直播失败：${error.message}`, duration: 1800 });
    } finally {
      this.creatingLive = false;
    }
  }

  private createLiveMenu(): void {
    if (!this.canManageVideoChats || this.creatingLive) { return; }
    if (this.liveGroupCallId > 0) {
      this.openExistingLive();
      return;
    }
    promptAction.showActionMenu({
      title: '发起直播',
      buttons: [
        { text: '多人语音/视频直播', color: '#3390EC' },
        { text: '单向频道直播（RTMP）', color: '#3390EC' }
      ]
    }).then((result): void => {
      if (result.index === 0) {
        this.createAndOpenLive(false);
      } else if (result.index === 1) {
        this.createAndOpenLive(true);
      }
    }).catch((): void => {});
  }

  private async createAndOpenLive(isRtmpStream: boolean): Promise<void> {
    if (this.creatingLive || !this.canManageVideoChats) { return; }
    this.creatingLive = true;
    try {
      const groupCallId = await createVideoChat(getTdClient(), this.chatId, isRtmpStream);
      if (groupCallId <= 0) {
        throw new Error('Telegram 未返回直播间标识');
      }
      this.liveGroupCallId = groupCallId;
      this.openLiveViewer(groupCallId, isRtmpStream);
    } catch (caught) {
      const error = caught as Error;
      promptAction.showToast({ message: `发起直播失败：${error.message}`, duration: 2000 });
    } finally {
      this.creatingLive = false;
    }
  }

  @Builder
  circleButton(symbol: string, onTap: () => void) {
    Row() {
      SymbolGlyph($r(symbol)).fontSize(22).fontColor([COLOR_TEXT_PRIMARY]);
    }
    .width(40).height(40).borderRadius(20).backgroundColor($r('app.color.surface'))
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
              .animation({
                duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 220), curve: Curve.EaseOut
              }));
        } else {
          SymbolGlyph($r('sys.symbol.bell_slash')).fontSize(22).fontColor([COLOR_PRIMARY])
            .transition(TransitionEffect.OPACITY
              .combine(TransitionEffect.scale({ x: 0.4, y: 0.4 }))
              .animation({
                duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 220), curve: Curve.EaseOut
              }));
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
  liveButton() {
    Column({ space: 5 }) {
      SymbolGlyph($r('sys.symbol.camera')).fontSize(22).fontColor([COLOR_PRIMARY]);
      Text(this.creatingLive
        ? '处理中'
        : (this.liveGroupCallId > 0 ? '进入直播' : '直播'))
        .fontSize(12).fontColor(COLOR_PRIMARY);
    }
    .layoutWeight(1).height(62)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(CARD_BG).borderRadius(CARD_RADIUS)
    .enabled(!this.creatingLive)
    .opacity(this.creatingLive ? 0.62 : 1)
    .onClick((): void => { this.createLiveMenu(); });
  }

  @Builder
  sectionDivider() {
    Divider().color($r('app.color.divider')).strokeWidth(0.7);
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
        colorSeed: this.chatId, avatarSize: 100,
        animPath: this.avatarAnimPath
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
      if (this.canManageVideoChats) {
        this.liveButton();
      } else {
        this.actionButton('sys.symbol.more', '更多', () => {});
      }
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
            SymbolGlyph($r('sys.symbol.qrcode')).fontSize(22).fontColor([COLOR_TEXT_SECONDARY])
              .onClick(() => { this.openQr(); });
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
              Divider().color($r('app.color.divider')).strokeWidth(0.7).margin({ left: 50 });
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
    .backgroundColor($r('app.color.page_bg'))
    // Member list pages in automatically as the page scrolls to the bottom.
    .onReachEnd(() => { if (this.store !== null) { this.store.loadMoreMembers(); } })
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]);
  }
}
