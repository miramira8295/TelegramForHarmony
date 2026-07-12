import { getTdClient } from '../../tdkit/Globals';
import { ProfileStore } from '../../store/ProfileStore';
import { AvatarView } from '../chatlist/AvatarView';
import { TdObject, TdRequest, TdError } from '../../tdkit/TdTypes';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';

const CARD_BG: ResourceColor = Color.White;
const CARD_RADIUS: number = 14;
const PAGE_BG: string = '#EFEFF4';

// The current user's own profile tab (Telegram-style "my profile"): avatar
// header, 设置照片/编辑信息/设置 quick actions, an info card (phone/username/
// birthday) and the 动态 posts section. Mirrors ProfileStore snapshot into
// @State so every card re-renders on updates.
@Preview
@Component
export struct MyProfilePage {
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @State myId: number = 0;
  @State name: string = '';
  @State initials: string = '?';
  @State avatarPath: string = '';
  @State statusText: string = '';
  @State phone: string = '';
  @State usernames: string[] = [];
  @State birthday: string = '';
  @State postTab: number = 0; // 0 动态 / 1 已归档的动态
  private store: ProfileStore | null = null;
  private unsub: (() => void) | null = null;

  aboutToAppear(): void {
    const req: TdRequest = { '@type': 'getMe' };
    getTdClient().send(req).then((me: TdObject) => {
      this.myId = (me['id'] as number | undefined) ?? 0;
      if (this.myId === 0) {
        return;
      }
      const store = new ProfileStore(getTdClient(), this.myId);
      this.store = store;
      this.unsub = store.subscribe(() => { this.refresh(); });
      store.open();
    }).catch((e: TdError) => {
      console.error(`MyProfilePage.getMe failed: ${e.message}`);
    });
  }

  aboutToDisappear(): void {
    if (this.unsub !== null) { this.unsub(); this.unsub = null; }
    if (this.store !== null) { this.store.close(); this.store = null; }
  }

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
    this.birthday = s.birthday;
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
  sectionDivider() {
    Divider().color('#EDEDED').strokeWidth(0.7);
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
        this.circleButton('sys.symbol.qrcode', () => {});
        Blank().layoutWeight(1);
        this.circleButton('sys.symbol.more', () => {});
      }.width('100%').padding({ left: 12, right: 12 });
      AvatarView({
        avatarPath: this.avatarPath, initials: this.initials,
        colorSeed: this.myId, avatarSize: 100
      });
      Text(this.name)
        .fontSize(20).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: '86%' });
      Text(this.statusText !== '' ? this.statusText : '在线')
        .fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
    }
    .width('100%')
    .padding({ top: this.topSafe + 8 });
  }

  @Builder
  actionsRow() {
    Row({ space: 8 }) {
      this.actionButton('sys.symbol.camera', '设置照片', () => {});
      this.actionButton('sys.symbol.pencil', '编辑信息', () => {});
      this.actionButton('sys.symbol.gearshape', '设置', () => {});
    }
    .width('100%').padding({ left: 12, right: 12, top: 14 });
  }

  @Builder
  infoCard() {
    Column() {
      Column() {
        if (this.phone !== '') {
          this.infoRow(`+${this.phone}`, '手机', COLOR_TEXT_PRIMARY);
        }
        if (this.usernames.length > 0) {
          if (this.phone !== '') {
            this.sectionDivider();
          }
          this.infoRow(`@${this.usernames[0]}`, '用户名', COLOR_TEXT_PRIMARY);
        }
        if (this.birthday !== '') {
          if (this.phone !== '' || this.usernames.length > 0) {
            this.sectionDivider();
          }
          this.infoRow(this.birthday, '生日', COLOR_TEXT_PRIMARY);
        }
      }
      .width('100%').padding({ left: 12, right: 12, top: 4, bottom: 4 })
      .backgroundColor(CARD_BG).borderRadius(CARD_RADIUS)
      .alignItems(HorizontalAlign.Start);
    }
    .margin({ left: 12, right: 12, top: 12 });
  }

  @Builder
  postTabPill(label: string, index: number) {
    Text(label)
      .fontSize(14)
      .fontWeight(this.postTab === index ? FontWeight.Medium : FontWeight.Normal)
      .fontColor(this.postTab === index ? COLOR_PRIMARY : COLOR_TEXT_SECONDARY)
      .backgroundColor(this.postTab === index ? '#E3F0FB' : Color.Transparent)
      .borderRadius(14)
      .padding({ left: 16, right: 16, top: 6, bottom: 6 })
      .onClick(() => { this.postTab = index; });
  }

  @Builder
  postsTabs() {
    Row({ space: 4 }) {
      this.postTabPill('动态', 0);
      this.postTabPill('已归档的动态', 1);
    }
    .padding(3)
    .backgroundColor(CARD_BG).borderRadius(18)
    .margin({ top: 16, bottom: 8 });
  }

  @Builder
  emptyPosts() {
    Column({ space: 12 }) {
      Text('暂无贴文').fontSize(17).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY);
      Text('发布照片和视频并显示在您的个人资料页上')
        .fontSize(14).fontColor(COLOR_TEXT_SECONDARY)
        .textAlign(TextAlign.Center).constraintSize({ maxWidth: '80%' });
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.camera')).fontSize(20).fontColor([Color.White]);
        Text('添加贴文').fontSize(16).fontColor(Color.White).fontWeight(FontWeight.Medium);
      }
      .padding({ left: 24, right: 24, top: 12, bottom: 12 })
      .backgroundColor(COLOR_PRIMARY).borderRadius(24)
      .margin({ top: 6 });
    }
    .width('100%')
    .padding({ top: 36, bottom: 36 });
  }

  build() {
    Scroll() {
      Column() {
        this.header();
        this.actionsRow();
        this.infoCard();
        this.postsTabs();
        this.emptyPosts();
      }
      .width('100%')
      .padding({ bottom: this.bottomSafe + 88 });
    }
    .width('100%').height('100%')
    .backgroundColor(PAGE_BG)
    .align(Alignment.Top)
    .edgeEffect(EdgeEffect.Spring)
    .scrollBar(BarState.Off);
  }
}
