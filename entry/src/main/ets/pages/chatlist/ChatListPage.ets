import { getFolderStore, getUnreadCountStore, getChatStore, getTdClient } from '../../tdkit/Globals';
import { TdObject } from '../../tdkit/TdTypes';
import { FolderInfo } from '../../store/FolderStore';
import { ChatListView } from './ChatListView';
import { MainTabBody } from './MainTabBody';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY, COLOR_TAB_SELECTED, COLOR_TAB_UNSELECTED, COLOR_BADGE_BG, COLOR_TAB_PILL_BG } from '../../util/theme';
import { router } from '@kit.ArkUI';

interface TabSpec {
  key: string;
  title: string;
}

@Preview
@Component
export struct ChatListPage {
  @State folders: FolderInfo[] = [];
  @State unreadMap: Map<string, number> = new Map();
  @State selectedIndex: number = 0;
  @State searchMode: boolean = false;
  @State searchQuery: string = '';
  // TDLib connection state as a small status hint beside the title
  // ('' when connectionStateReady — nothing shown).
  @State syncLabel: string = '';
  @StorageProp('topSafeHeight') topSafe: number = 0;
  // Sliding selection pill: position/size interpolated between tab frames so it
  // follows the finger during content swipes (Telegram-style).
  @State indicatorX: number = 8;
  @State indicatorW: number = 0;
  @State indicatorH: number = 26;
  private tabXs: number[] = [];
  private tabWs: number[] = [];
  private tabsWidth: number = 0; // Tabs (content) width, for swipe-progress ratio
  private tabViewW: number = 0;  // tab strip viewport width, for keep-visible scrolling
  private tabScroller: Scroller = new Scroller();
  private controller: TabsController = new TabsController();
  private unsubFolders: (() => void) | null = null;
  private unsubUnread: (() => void) | null = null;
  private unsubChats: (() => void) | null = null;
  private unsubConn: (() => void) | null = null;
  private loadedFolders: Set<string> = new Set();

  // Place the pill at a (possibly fractional) tab position: 1.4 = 40% of the
  // way between tab 1 and tab 2, interpolating both position and width.
  private moveIndicatorTo(pos: number): void {
    const n = this.tabs().length;
    if (n === 0 || this.tabWs.length === 0) {
      return;
    }
    const p = Math.max(0, Math.min(n - 1, pos));
    const i0 = Math.floor(p);
    const i1 = Math.min(n - 1, i0 + 1);
    const f = p - i0;
    const x0 = this.tabXs[i0] ?? 8;
    const x1 = this.tabXs[i1] ?? x0;
    const w0 = this.tabWs[i0] ?? 0;
    const w1 = this.tabWs[i1] ?? w0;
    this.indicatorX = x0 + (x1 - x0) * f;
    this.indicatorW = w0 + (w1 - w0) * f;
  }

  // Scroll the tab strip so the selected tab is fully visible.
  private ensureTabVisible(index: number): void {
    const x = this.tabXs[index] ?? 0;
    const w = this.tabWs[index] ?? 0;
    if (w === 0 || this.tabViewW === 0) {
      return;
    }
    const off = this.tabScroller.currentOffset().xOffset;
    let target = -1;
    if (x < off + 8) {
      target = Math.max(0, x - 8);
    } else if (x + w > off + this.tabViewW - 8) {
      target = x + w - this.tabViewW + 8;
    }
    if (target >= 0) {
      this.tabScroller.scrollTo({ xOffset: target, yOffset: 0, animation: { duration: 200, curve: Curve.EaseOut } });
    }
  }

  aboutToAppear(): void {
    this.folders = getFolderStore().getFolders();
    this.ensureFolderLoads(this.folders);
    this.refreshUnread();
    this.unsubFolders = getFolderStore().subscribe((f: FolderInfo[]) => {
      this.folders = f;
      this.ensureFolderLoads(f);
      this.refreshUnread();
    });
    this.unsubUnread = getUnreadCountStore().subscribe(() => { this.refreshUnread(); });
    // any chat change recomputes folder badges (folder unread is derived from loaded chats)
    this.unsubChats = getChatStore().subscribe(() => { this.refreshUnread(); }, 'main');
    this.unsubConn = getTdClient().onUpdate('updateConnectionState', (u: TdObject) => {
      const st = u['state'] as TdObject | undefined;
      const t = st !== undefined ? ((st['@type'] as string | undefined) ?? '') : '';
      this.syncLabel = t === 'connectionStateUpdating' ? '刷新中...'
        : (t === 'connectionStateConnecting' || t === 'connectionStateConnectingToProxy' ? '连接中...'
          : (t === 'connectionStateWaitingForNetwork' ? '等待网络...' : ''));
    });
  }

  // TDLib does not emit updateUnreadChatCount for chat folders, so load each
  // folder once to populate its chats; the badge is then derived from them.
  private ensureFolderLoads(fs: FolderInfo[]): void {
    for (const f of fs) {
      const key = `folder:${f.id}`;
      if (!this.loadedFolders.has(key)) {
        this.loadedFolders.add(key);
        getChatStore().load(key);
      }
    }
  }

  // Main uses TDLib's authoritative unread count; folders derive it from loaded chats.
  private computeUnread(key: string): number {
    if (key === 'main') {
      return getUnreadCountStore().getUnread('main');
    }
    return getChatStore().unreadChatCount(key);
  }

  // Rebuild the whole badge map (new Map identity) so the tab bar re-renders.
  private refreshUnread(): void {
    const next: Map<string, number> = new Map();
    for (const spec of this.tabs()) {
      next.set(spec.key, this.computeUnread(spec.key));
    }
    this.unreadMap = next;
  }

  aboutToDisappear(): void {
    if (this.unsubFolders !== null) { this.unsubFolders(); this.unsubFolders = null; }
    if (this.unsubUnread !== null) { this.unsubUnread(); this.unsubUnread = null; }
    if (this.unsubChats !== null) { this.unsubChats(); this.unsubChats = null; }
    if (this.unsubConn !== null) { this.unsubConn(); this.unsubConn = null; }
  }

  private tabs(): TabSpec[] {
    const specs: TabSpec[] = [{ key: 'main', title: '所有' }];
    for (const f of this.folders) {
      specs.push({ key: `folder:${f.id}`, title: f.title });
    }
    return specs;
  }

  @Builder
  topBar() {
    if (this.searchMode) {
      // Expanded global search bar (same pattern as the in-chat search header).
      Row({ space: 8 }) {
        Row() {
          SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(22).fontColor([COLOR_TEXT_PRIMARY]);
        }
        .width(40).height(40).borderRadius(20).backgroundColor($r('app.color.surface'))
        .justifyContent(FlexAlign.Center)
        .shadow({ radius: 4, color: '#12000000', offsetX: 0, offsetY: 1 })
        .onClick(() => {
          this.searchMode = false;
          this.searchQuery = '';
        });
        TextInput({ text: this.searchQuery, placeholder: '全局搜索' })
          .layoutWeight(1).height(40)
          .backgroundColor($r('app.color.surface')).borderRadius(20)
          .defaultFocus(true)
          .onChange((v: string) => { this.searchQuery = v; })
          .onSubmit(() => {
            const q = this.searchQuery.trim();
            if (q !== '') {
              const params: Record<string, Object> = { 'query': q };
              router.pushUrl({ url: 'pages/search/GlobalSearchPage', params: params });
            }
          });
      }.width('100%').padding({ left: 12, right: 12, top: 6, bottom: 8 })
      .alignItems(VerticalAlign.Center);
    } else {
      Row() {
        Row({ space: 5 }) {
          Text('Telegram').fontSize(24).fontWeight(FontWeight.Bold).fontColor(COLOR_PRIMARY);
          if (this.syncLabel !== '') {
            Text(this.syncLabel).fontSize(11).fontColor(COLOR_TEXT_SECONDARY).margin({ bottom: 4 });
          }
        }.alignItems(VerticalAlign.Bottom).layoutWeight(1);
        SymbolGlyph($r('sys.symbol.magnifyingglass')).fontSize(24).fontColor([COLOR_TEXT_SECONDARY]).margin({ right: 16 })
          .onClick(() => { router.pushUrl({ url: 'pages/search/GlobalSearchPage' }); });
        SymbolGlyph($r('sys.symbol.more')).fontSize(24).fontColor([COLOR_TEXT_SECONDARY]);
      }.width('100%').padding({ left: 16, right: 16, top: 12, bottom: 8 });
    }
  }

  @Builder
  pill(spec: TabSpec, index: number) {
    Row({ space: 4 }) {
      Text(spec.title).fontSize(13)
        .fontWeight(this.selectedIndex === index ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.selectedIndex === index ? COLOR_TAB_SELECTED : COLOR_TAB_UNSELECTED);
      if ((this.unreadMap.get(spec.key) ?? 0) > 0) {
        Text(`${this.unreadMap.get(spec.key) ?? 0}`)
          .fontSize(10).fontColor(Color.White)
          .backgroundColor(this.selectedIndex === index ? COLOR_TAB_SELECTED : COLOR_BADGE_BG)
          .borderRadius(8).padding({ left: 5, right: 5, top: 1, bottom: 1 });
      }
    }
    .padding({ left: 11, right: 11, top: 4, bottom: 4 })
    .margin({ right: 3 })
    .borderRadius(14)
    .onAreaChange((_old: Area, area: Area) => {
      // Record each pill's frame for the sliding indicator + keep-visible math.
      this.tabXs[index] = area.position.x as number;
      this.tabWs[index] = area.width as number;
      this.indicatorH = area.height as number;
      if (index === this.selectedIndex) {
        this.moveIndicatorTo(index);
      }
    })
    .onClick(() => { this.controller.changeIndex(index); });
  }

  @Builder
  tabBar() {
    Column() {
      Scroll(this.tabScroller) {
        Stack({ alignContent: Alignment.TopStart }) {
          // Sliding selection pill behind the labels — driven by indicatorX/W,
          // which follow the finger during Tabs content swipes.
          Row()
            .width(this.indicatorW).height(this.indicatorH)
            .borderRadius(this.indicatorH / 2)
            .backgroundColor(COLOR_TAB_PILL_BG)
            .position({ x: this.indicatorX, y: (40 - this.indicatorH) / 2 });
          Row() {
            ForEach(this.tabs(), (spec: TabSpec, index: number) => {
              this.pill(spec, index);
            }, (spec: TabSpec) => `${spec.key}_${spec.title}`);
          }.padding({ left: 8, right: 8 }).height(40);
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .align(Alignment.Start)
      .width('100%')
      .onAreaChange((_old: Area, area: Area) => { this.tabViewW = area.width as number; });
    }
    .backgroundColor($r('app.color.surface'))
    .borderRadius(20)
    .clip(true)
    .margin({ left: 8, right: 8, top: 2, bottom: 8 })
    .shadow({ radius: 8, color: '#1F000000', offsetX: 0, offsetY: 0 });
  }

  build() {
    Column() {
      this.topBar();
      this.tabBar();
      Tabs({ controller: this.controller }) {
        ForEach(this.tabs(), (spec: TabSpec) => {
          TabContent() {
            // TabContent centers a content-sized child, so a short chat list
            // (few chats / a small folder) would float in the vertical middle.
            // A definite full-height Column pins the list to the top and lets
            // the body's layoutWeight(1) actually stretch.
            Column() {
              if (spec.key === 'main') {
                MainTabBody();
              } else {
                ChatListView({ listKey: spec.key });
              }
            }.width('100%').height('100%')
          }
        }, (spec: TabSpec) => `${spec.key}_${spec.title}`);
      }
      .barHeight(0)
      .onAreaChange((_old: Area, area: Area) => { this.tabsWidth = area.width as number; })
      // Content swipe in progress: convert the swipe offset into a fractional
      // tab position so the selection pill tracks the finger continuously.
      .onGestureSwipe((index: number, event: TabsAnimationEvent) => {
        if (this.tabsWidth > 0) {
          this.moveIndicatorTo(index - event.currentOffset / this.tabsWidth);
        }
      })
      // Finger released / tab tapped: settle the pill on the target tab and
      // scroll the strip if that tab sits outside the visible range.
      .onAnimationStart((_index: number, targetIndex: number) => {
        this.selectedIndex = targetIndex;
        animateTo({ duration: 250, curve: Curve.EaseOut }, () => { this.moveIndicatorTo(targetIndex); });
        this.ensureTabVisible(targetIndex);
      })
      .onChange((index: number) => {
        this.selectedIndex = index;
        animateTo({ duration: 200, curve: Curve.EaseOut }, () => { this.moveIndicatorTo(index); });
        this.ensureTabVisible(index);
      })
      .layoutWeight(1)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM]);
    }
    .width('100%').height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .padding({ top: this.topSafe });
  }
}
