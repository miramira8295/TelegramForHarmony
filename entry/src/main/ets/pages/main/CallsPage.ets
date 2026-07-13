import { router, promptAction } from '@kit.ArkUI';
import { getTdClient } from '../../tdkit/Globals';
import { CallsStore, CallItem } from '../../store/CallsStore';
import { AvatarView } from '../chatlist/AvatarView';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';

const CARD_BG: ResourceColor = $r('app.color.surface');
const CARD_RADIUS: number = 14;
const PAGE_BG: ResourceColor = $r('app.color.page_bg');
const COLOR_MISSED: string = '#E53935';
const COLOR_ANSWERED: string = '#34C759';

// Recent calls: an action card (new call / calls tab) above the call history
// from searchCallMessages. Rows open the chat; actual calling isn't supported.
@Entry
@Component
struct CallsPage {
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @State calls: CallItem[] = [];
  @State loading: boolean = true;
  @State hasMore: boolean = false;
  private store: CallsStore | null = null;
  private unsub: (() => void) | null = null;

  aboutToAppear(): void {
    const store = new CallsStore(getTdClient());
    this.store = store;
    this.unsub = store.subscribe(() => {
      this.calls = store.calls;
      this.loading = store.loading;
      this.hasMore = store.hasMore;
    });
    store.open();
  }

  aboutToDisappear(): void {
    if (this.unsub !== null) { this.unsub(); this.unsub = null; }
    if (this.store !== null) { this.store.close(); this.store = null; }
  }

  private openChat(chatId: number): void {
    const params: Record<string, Object> = { 'chatId': chatId };
    router.pushUrl({ url: 'pages/chat/ChatPage', params: params });
  }

  private notSupported(): void {
    promptAction.showToast({ message: '暂未支持通话功能' });
  }

  @Builder
  topBar() {
    Row({ space: 16 }) {
      SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(26).fontColor([COLOR_TEXT_PRIMARY])
        .onClick(() => { router.back(); });
      Text('通话').fontSize(22).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY)
        .layoutWeight(1);
      SymbolGlyph($r('sys.symbol.more')).fontSize(24).fontColor([COLOR_TEXT_PRIMARY]);
    }
    .width('100%').height(48).padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center);
  }

  @Builder
  actionRow(icon: string, label: string, onTap: () => void) {
    Row({ space: 14 }) {
      SymbolGlyph($r(icon)).fontSize(22).fontColor([COLOR_PRIMARY]).width(40)
        .margin({ left: 4 });
      Text(label).fontSize(16).fontColor(COLOR_PRIMARY).layoutWeight(1);
    }
    .width('100%').padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => { onTap(); });
  }

  @Builder
  actionCard() {
    Column() {
      Column() {
        this.actionRow('sys.symbol.phone_fill', '创建新通话', () => { this.notSupported(); });
        Divider().color($r('app.color.divider')).strokeWidth(0.7).margin({ left: 68 });
        this.actionRow('sys.symbol.arrow_down_circle', '显示通话标签页', () => { this.notSupported(); });
      }
      .width('100%').backgroundColor(CARD_BG).borderRadius(CARD_RADIUS)
      .padding({ top: 2, bottom: 2 });
    }
    .margin({ left: 12, right: 12, top: 8 });
  }

  @Builder
  callRow(c: CallItem) {
    Row({ space: 12 }) {
      AvatarView({ avatarPath: c.avatarPath, initials: c.initials, colorSeed: c.colorSeed, avatarSize: 46 });
      Column({ space: 3 }) {
        Text(c.name !== '' ? c.name : '…')
          .fontSize(16).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
        Row({ space: 5 }) {
          Text(c.outgoing ? '↗' : '↙')
            .fontSize(14).fontWeight(FontWeight.Bold)
            .fontColor(c.missed ? COLOR_MISSED : COLOR_ANSWERED);
          Text(c.timeLabel).fontSize(13).fontColor(COLOR_TEXT_SECONDARY)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
        }.alignItems(VerticalAlign.Center);
      }.alignItems(HorizontalAlign.Start).layoutWeight(1);
      SymbolGlyph($r('sys.symbol.phone')).fontSize(22).fontColor([COLOR_PRIMARY])
        .onClick(() => { this.notSupported(); });
    }
    .width('100%').padding({ left: 14, right: 14, top: 9, bottom: 9 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => { this.openChat(c.chatId); });
  }

  @Builder
  listCard() {
    Column() {
      Column() {
        ForEach(this.calls, (c: CallItem, index: number) => {
          if (index > 0) {
            Divider().color($r('app.color.divider')).strokeWidth(0.7).margin({ left: 72 });
          }
          this.callRow(c);
        }, (c: CallItem) => `${c.msgId}_${c.name}_${c.avatarPath}`);
        if (this.hasMore) {
          // Auto-paged by the outer Scroll's onReachEnd — just show activity.
          Row() {
            LoadingProgress().width(22).height(22).color(COLOR_TEXT_SECONDARY);
          }.width('100%').justifyContent(FlexAlign.Center).padding({ top: 8, bottom: 8 });
        }
      }
      .width('100%').backgroundColor(CARD_BG).borderRadius(CARD_RADIUS)
      .padding({ top: 4, bottom: 4 });
    }
    .margin({ left: 12, right: 12, top: 12 });
  }

  build() {
    Column() {
      this.topBar();
      Scroll() {
        Column() {
          this.actionCard();
          if (this.loading) {
            LoadingProgress().width(32).height(32).color(COLOR_TEXT_SECONDARY)
              .margin({ top: 48 });
          } else if (this.calls.length === 0) {
            Text('暂无通话记录').fontSize(14).fontColor(COLOR_TEXT_SECONDARY)
              .margin({ top: 48 });
          } else {
            this.listCard();
          }
        }
        .width('100%')
        .padding({ bottom: this.bottomSafe + 16 });
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.Top)
      .edgeEffect(EdgeEffect.Spring)
      .scrollBar(BarState.Off)
      .onReachEnd(() => { if (this.hasMore && this.store !== null) { this.store.loadMore(); } });
    }
    .width('100%').height('100%')
    .backgroundColor(PAGE_BG)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .padding({ top: this.topSafe });
  }
}
