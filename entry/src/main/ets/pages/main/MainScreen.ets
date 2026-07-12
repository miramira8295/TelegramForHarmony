import { getTdClient, getUnreadCountStore } from '../../tdkit/Globals';
import { ProfileStore } from '../../store/ProfileStore';
import { AvatarView } from '../chatlist/AvatarView';
import { ChatListPage } from '../chatlist/ChatListPage';
import { ContactsPage } from './ContactsPage';
import { SettingsPage } from './SettingsPage';
import { MyProfilePage } from './MyProfilePage';
import { TdObject, TdRequest, TdError } from '../../tdkit/TdTypes';
import { COLOR_PRIMARY, COLOR_TAB_UNSELECTED } from '../../util/theme';

const DOCK_BG: ResourceColor = Color.White;
const BADGE_BG: string = '#4CD964';
const DOCK_H: number = 62;      // capsule height
const DOCK_GAP: number = 12;    // gap below the capsule (above it: content padding)

// Root screen after login: a floating capsule dock (聊天/联系人/设置/个人资料)
// over four keep-alive tab bodies. The dock is a rounded pill that hovers above
// full-screen content; content reserves bottom space so nothing hides behind it.
// Tabs use scrollable(false) so swiping never fights ChatListPage's inner folder
// Tabs — only dock taps switch tabs.
@Component
export struct MainScreen {
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @State tab: number = 0;
  @State unread: number = 0;
  @State myId: number = 0;
  @State meAvatar: string = '';
  @State meInitials: string = '?';
  private controller: TabsController = new TabsController();
  private store: ProfileStore | null = null;
  private unsubStore: (() => void) | null = null;
  private unsubUnread: (() => void) | null = null;

  aboutToAppear(): void {
    this.unread = getUnreadCountStore().getUnread('main');
    this.unsubUnread = getUnreadCountStore().subscribe(() => {
      this.unread = getUnreadCountStore().getUnread('main');
    });
    const req: TdRequest = { '@type': 'getMe' };
    getTdClient().send(req).then((me: TdObject) => {
      this.myId = (me['id'] as number | undefined) ?? 0;
      if (this.myId === 0) {
        return;
      }
      const store = new ProfileStore(getTdClient(), this.myId);
      this.store = store;
      this.unsubStore = store.subscribe(() => {
        this.meAvatar = store.avatarPath;
        this.meInitials = store.initials;
      });
      store.open();
    }).catch((e: TdError) => {
      console.error(`MainScreen.getMe failed: ${e.message}`);
    });
  }

  aboutToDisappear(): void {
    if (this.unsubUnread !== null) { this.unsubUnread(); this.unsubUnread = null; }
    if (this.unsubStore !== null) { this.unsubStore(); this.unsubStore = null; }
    if (this.store !== null) { this.store.close(); this.store = null; }
  }

  private select(index: number): void {
    this.tab = index;
    this.controller.changeIndex(index);
  }

  @Builder
  dockItem(index: number, icon: string, label: string) {
    Column({ space: 2 }) {
      Stack({ alignContent: Alignment.TopEnd }) {
        SymbolGlyph($r(icon)).fontSize(24)
          .fontColor([this.tab === index ? COLOR_PRIMARY : COLOR_TAB_UNSELECTED]);
        if (index === 0 && this.unread > 0) {
          Text(this.unread > 99 ? '99+' : `${this.unread}`)
            .fontSize(10).fontColor(Color.White).fontWeight(FontWeight.Medium)
            .backgroundColor(BADGE_BG).borderRadius(9)
            .constraintSize({ minWidth: 18 }).height(18)
            .textAlign(TextAlign.Center).padding({ left: 5, right: 5 })
            .offset({ x: 12, y: -7 });
        }
      }
      Text(label).fontSize(10)
        .fontColor(this.tab === index ? COLOR_PRIMARY : COLOR_TAB_UNSELECTED);
    }
    .layoutWeight(1).height('100%')
    .justifyContent(FlexAlign.Center)
    .onClick(() => { this.select(index); });
  }

  @Builder
  profileDockItem() {
    Column({ space: 2 }) {
      Stack() {
        AvatarView({ avatarPath: this.meAvatar, initials: this.meInitials, colorSeed: this.myId, avatarSize: 24 });
      }
      .borderRadius(14).padding(2)
      .border({ width: this.tab === 3 ? 2 : 0, color: COLOR_PRIMARY });
      Text('个人资料').fontSize(10)
        .fontColor(this.tab === 3 ? COLOR_PRIMARY : COLOR_TAB_UNSELECTED);
    }
    .layoutWeight(1).height('100%')
    .justifyContent(FlexAlign.Center)
    .onClick(() => { this.select(3); });
  }

  // Floating capsule: outer Column carries the horizontal padding + bottom
  // margin (width('100%') + horizontal margin conflict on the same node in
  // ArkUI), inner Row is the pill itself.
  @Builder
  dock() {
    Column() {
      Row() {
        this.dockItem(0, 'sys.symbol.message', '聊天');
        this.dockItem(1, 'sys.symbol.person_2', '联系人');
        this.dockItem(2, 'sys.symbol.gearshape', '设置');
        this.profileDockItem();
      }
      .width('100%').height(DOCK_H)
      .backgroundColor(DOCK_BG)
      .borderRadius(DOCK_H / 2)
      .alignItems(VerticalAlign.Center)
      .shadow({ radius: 18, color: '#26000000', offsetX: 0, offsetY: 5 });
    }
    .width('100%')
    .padding({ left: 16, right: 16 })
    .margin({ bottom: this.bottomSafe + DOCK_GAP });
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Tabs({ controller: this.controller }) {
        TabContent() { ChatListPage(); }
        TabContent() { ContactsPage(); }
        TabContent() { SettingsPage(); }
        TabContent() { MyProfilePage(); }
      }
      .barHeight(0)
      .scrollable(false)
      .animationDuration(0)
      .onChange((index: number) => { this.tab = index; })
      .width('100%').height('100%');

      this.dock();
    }
    .width('100%').height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]);
  }
}
