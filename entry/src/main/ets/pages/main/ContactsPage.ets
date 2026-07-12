import { getTdClient } from '../../tdkit/Globals';
import { ContactsStore, ContactItem } from '../../store/ContactsStore';
import { AvatarView } from '../chatlist/AvatarView';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';

const CARD_BG: ResourceColor = Color.White;
const CARD_RADIUS: number = 14;
const PAGE_BG: string = '#EFEFF4';

// The contacts tab: search box, invite/recent-calls shortcuts, and the contact
// list sorted by last-seen. Title shows 正在刷新... until getContacts resolves.
@Preview
@Component
export struct ContactsPage {
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @State contacts: ContactItem[] = [];
  @State loading: boolean = true;
  @State query: string = '';
  private store: ContactsStore | null = null;
  private unsub: (() => void) | null = null;

  aboutToAppear(): void {
    const store = new ContactsStore(getTdClient());
    this.store = store;
    this.unsub = store.subscribe(() => {
      this.contacts = store.contacts;
      this.loading = store.loading;
    });
    store.open();
  }

  aboutToDisappear(): void {
    if (this.unsub !== null) { this.unsub(); this.unsub = null; }
    if (this.store !== null) { this.store.close(); this.store = null; }
  }

  private filtered(): ContactItem[] {
    const q = this.query.trim().toLowerCase();
    if (q === '') {
      return this.contacts;
    }
    return this.contacts.filter((c: ContactItem) => c.name.toLowerCase().includes(q));
  }

  @Builder
  topBar() {
    Row() {
      Text(this.loading ? '正在刷新...' : '联系人')
        .fontSize(28).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY)
        .layoutWeight(1);
      SymbolGlyph($r('sys.symbol.line_3_horizontal'))
        .fontSize(22).fontColor([COLOR_TEXT_PRIMARY]);
    }
    .width('100%').height(48).padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center);
  }

  @Builder
  searchBox() {
    Row({ space: 8 }) {
      SymbolGlyph($r('sys.symbol.magnifyingglass')).fontSize(17).fontColor([COLOR_TEXT_SECONDARY]);
      TextInput({ text: this.query, placeholder: '搜索联系人' })
        .layoutWeight(1).height(36).fontSize(16)
        .backgroundColor(Color.Transparent).padding(0).borderRadius(0)
        .placeholderColor(COLOR_TEXT_SECONDARY)
        .onChange((v: string) => { this.query = v; });
    }
    .width('100%').padding({ left: 12, right: 12, top: 4, bottom: 4 })
    .height(44)
    .backgroundColor(CARD_BG).borderRadius(CARD_RADIUS)
    .alignItems(VerticalAlign.Center)
    .margin({ left: 12, right: 12, top: 4 });
  }

  @Builder
  actionRow(icon: string, bg: string, label: string) {
    Row({ space: 14 }) {
      Row() {
        SymbolGlyph($r(icon)).fontSize(20).fontColor([Color.White]);
      }
      .width(40).height(40).borderRadius(20).backgroundColor(bg)
      .justifyContent(FlexAlign.Center);
      Text(label).fontSize(16).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1);
    }
    .width('100%').padding({ left: 14, right: 14, top: 8, bottom: 8 })
    .alignItems(VerticalAlign.Center);
  }

  @Builder
  actionCard() {
    Column() {
      Column() {
        this.actionRow('sys.symbol.person_badge_plus', COLOR_PRIMARY, '邀请朋友');
        Divider().color('#EDEDED').strokeWidth(0.7).margin({ left: 68 });
        this.actionRow('sys.symbol.phone_fill', '#34C759', '最近通话');
      }
      .width('100%').backgroundColor(CARD_BG).borderRadius(CARD_RADIUS)
      .padding({ top: 4, bottom: 4 });
    }
    .margin({ left: 12, right: 12, top: 12 });
  }

  @Builder
  contactRow(c: ContactItem) {
    Row({ space: 12 }) {
      AvatarView({ avatarPath: c.avatarPath, initials: c.initials, colorSeed: c.id, avatarSize: 46 });
      Column({ space: 3 }) {
        Text(c.name).fontSize(16).fontColor(COLOR_TEXT_PRIMARY)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
        Text(c.statusText)
          .fontSize(13)
          .fontColor(c.online ? COLOR_PRIMARY : COLOR_TEXT_SECONDARY)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
      }.alignItems(HorizontalAlign.Start).layoutWeight(1);
    }
    .width('100%').padding({ left: 14, right: 14, top: 7, bottom: 7 })
    .alignItems(VerticalAlign.Center);
  }

  @Builder
  listCard() {
    Column() {
      Column() {
        Text('按最后上线时间排序')
          .fontSize(13).fontColor(COLOR_PRIMARY).fontWeight(FontWeight.Medium)
          .width('100%').padding({ left: 14, right: 14, top: 10, bottom: 6 });
        ForEach(this.filtered(), (c: ContactItem, index: number) => {
          if (index > 0) {
            Divider().color('#EDEDED').strokeWidth(0.7).margin({ left: 72 });
          }
          this.contactRow(c);
        }, (c: ContactItem) => `${c.id}_${c.avatarPath}`);
      }
      .width('100%').backgroundColor(CARD_BG).borderRadius(CARD_RADIUS)
      .padding({ bottom: 4 });
    }
    .margin({ left: 12, right: 12, top: 12 });
  }

  @Builder
  fab() {
    Row() {
      SymbolGlyph($r('sys.symbol.person_badge_plus')).fontSize(24).fontColor([Color.White]);
    }
    .width(56).height(56).borderRadius(28).backgroundColor(COLOR_PRIMARY)
    .justifyContent(FlexAlign.Center)
    .shadow({ radius: 10, color: '#33000000', offsetX: 0, offsetY: 3 })
    .margin({ right: 18, bottom: this.bottomSafe + 88 });
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column() {
        this.topBar();
        Scroll() {
          Column() {
            this.searchBox();
            this.actionCard();
            this.listCard();
          }
          .width('100%')
          .padding({ bottom: this.bottomSafe + 88 });
        }
        .layoutWeight(1)
        .width('100%')
        .align(Alignment.Top)
        .edgeEffect(EdgeEffect.Spring)
        .scrollBar(BarState.Off);
      }
      .width('100%').height('100%');

      this.fab();
    }
    .width('100%').height('100%')
    .backgroundColor(PAGE_BG)
    .padding({ top: this.topSafe });
  }
}
