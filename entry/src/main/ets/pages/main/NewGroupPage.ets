import { router, promptAction } from '@kit.ArkUI';
import { ContactsStore, ContactItem } from '../../store/ContactsStore';
import { getTdClient } from '../../tdkit/Globals';
import { TdError, TdObject, TdRequest } from '../../tdkit/TdTypes';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { AvatarView } from '../chatlist/AvatarView';
import { searchPublicUsers } from '../../store/PublicUserSearch';

const PAGE_BG: ResourceColor = $r('app.color.page_bg');
const CARD_BG: ResourceColor = $r('app.color.surface');

@Entry
@Component
struct NewGroupPage {
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @State contacts: ContactItem[] = [];
  @State loading: boolean = true;
  @State query: string = '';
  @State remoteUsers: ContactItem[] = [];
  @State knownRemoteUsers: ContactItem[] = [];
  @State remoteLoading: boolean = false;
  @State selectedIds: number[] = [];
  @State naming: boolean = false;
  @State title: string = '';
  @State creating: boolean = false;
  private store: ContactsStore | null = null;
  private unsubscribe: (() => void) | null = null;
  private searchTimer: number = -1;
  private searchSequence: number = 0;

  aboutToAppear(): void {
    const store = new ContactsStore(getTdClient());
    this.store = store;
    this.unsubscribe = store.subscribe((): void => {
      this.contacts = store.contacts;
      this.loading = store.loading;
    });
    store.open();
  }

  aboutToDisappear(): void {
    this.searchSequence++;
    if (this.searchTimer !== -1) {
      clearTimeout(this.searchTimer);
      this.searchTimer = -1;
    }
    if (this.unsubscribe !== null) {
      this.unsubscribe();
      this.unsubscribe = null;
    }
    if (this.store !== null) {
      this.store.close();
      this.store = null;
    }
  }

  private onQueryChanged(value: string): void {
    this.query = value;
    const sequence = ++this.searchSequence;
    if (this.searchTimer !== -1) {
      clearTimeout(this.searchTimer);
      this.searchTimer = -1;
    }
    const normalized = value.trim().replace(/^@/, '');
    if (normalized.length < 2) {
      this.remoteUsers = [];
      this.remoteLoading = false;
      return;
    }
    this.remoteLoading = true;
    this.searchTimer = setTimeout((): void => {
      this.searchTimer = -1;
      searchPublicUsers(getTdClient(), value).then((users: ContactItem[]): void => {
        if (sequence !== this.searchSequence) {
          return;
        }
        this.remoteUsers = users;
        const known = [...this.knownRemoteUsers];
        for (const user of users) {
          if (!known.some((item: ContactItem): boolean => item.id === user.id)) {
            known.push(user);
          }
        }
        this.knownRemoteUsers = known;
        this.remoteLoading = false;
      }).catch((error: TdError): void => {
        if (sequence !== this.searchSequence) {
          return;
        }
        console.warn(`NewGroupPage.searchPublicUsers failed: ${error.message}`);
        this.remoteUsers = [];
        this.remoteLoading = false;
      });
    }, 350);
  }

  private filteredContacts(): ContactItem[] {
    const value = this.query.trim().toLowerCase();
    if (value === '') {
      return this.contacts;
    }
    const localQuery = value.replace(/^@/, '');
    const result = this.contacts.filter((contact: ContactItem): boolean =>
      contact.name.toLowerCase().includes(localQuery) ||
        contact.statusText.toLowerCase().includes(value)
    );
    for (const user of this.remoteUsers) {
      if (!result.some((item: ContactItem): boolean => item.id === user.id)) {
        result.push(user);
      }
    }
    return result;
  }

  private selected(userId: number): boolean {
    return this.selectedIds.indexOf(userId) >= 0;
  }

  private toggle(userId: number): void {
    if (this.selected(userId)) {
      this.selectedIds = this.selectedIds.filter((id: number): boolean => id !== userId);
    } else {
      this.selectedIds = [...this.selectedIds, userId];
    }
  }

  private contactFor(userId: number): ContactItem {
    const contact = [...this.contacts, ...this.knownRemoteUsers]
      .find((item: ContactItem): boolean => item.id === userId);
    if (contact !== undefined) {
      return contact;
    }
    return {
      id: userId,
      name: '联系人',
      initials: '?',
      avatarPath: '',
      statusText: '',
      online: false,
      sortKey: 0
    };
  }

  private goNext(): void {
    if (this.selectedIds.length === 0) {
      promptAction.showToast({ message: '请至少选择一位联系人', duration: 1600 });
      return;
    }
    this.naming = true;
  }

  private createGroup(): void {
    const groupTitle = this.title.trim();
    if (groupTitle === '') {
      promptAction.showToast({ message: '请输入群组名称', duration: 1600 });
      return;
    }
    if (this.creating) {
      return;
    }
    this.creating = true;
    const request: TdRequest = { '@type': 'createNewBasicGroupChat' };
    request['user_ids'] = this.selectedIds;
    request['title'] = groupTitle;
    request['message_auto_delete_time'] = 0;
    getTdClient().send(request).then((chat: TdObject): void => {
      this.creating = false;
      const chatId = (chat['id'] as number | undefined) ?? 0;
      if (chatId <= 0) {
        promptAction.showToast({ message: '群组创建失败，请重试', duration: 1800 });
        return;
      }
      const params: Record<string, Object> = { 'chatId': chatId };
      router.replaceUrl({ url: 'pages/chat/ChatPage', params: params });
    }).catch((error: TdError): void => {
      this.creating = false;
      console.error(`NewGroupPage.createNewBasicGroupChat failed: ${error.message}`);
      promptAction.showToast({ message: `群组创建失败：${error.message}`, duration: 2200 });
    });
  }

  private back(): void {
    if (this.naming) {
      this.naming = false;
      return;
    }
    router.back();
  }

  @Builder
  header() {
    Row({ space: 12 }) {
      Row() {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(24)
          .fontColor([COLOR_TEXT_PRIMARY]);
      }
      .width(40).height(40)
      .justifyContent(FlexAlign.Center)
      .onClick((): void => { this.back(); });

      Column({ space: 1 }) {
        Text(this.naming ? '新建群组' : '添加成员')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLOR_TEXT_PRIMARY);
        Text(this.naming ? `${this.selectedIds.length} 位成员` :
          (this.selectedIds.length > 0 ? `已选择 ${this.selectedIds.length} 人` : '选择群组成员'))
          .fontSize(12)
          .fontColor(COLOR_TEXT_SECONDARY);
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1);

      Text(this.naming ? (this.creating ? '创建中' : '创建') : '下一步')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.creating ? COLOR_TEXT_SECONDARY : COLOR_PRIMARY)
        .padding({ left: 10, right: 4, top: 10, bottom: 10 })
        .onClick((): void => {
          if (this.naming) {
            this.createGroup();
          } else {
            this.goNext();
          }
        });
    }
    .width('100%')
    .height(58)
    .padding({ left: 8, right: 14 })
    .alignItems(VerticalAlign.Center);
  }

  @Builder
  searchBox() {
    Row({ space: 8 }) {
      SymbolGlyph($r('sys.symbol.magnifyingglass'))
        .fontSize(17)
        .fontColor([COLOR_TEXT_SECONDARY]);
      TextInput({ text: this.query, placeholder: '搜索联系人或 @用户名' })
        .layoutWeight(1)
        .height(42)
        .fontSize(16)
        .backgroundColor(Color.Transparent)
        .padding(0)
        .onChange((value: string): void => { this.onQueryChanged(value); });
    }
    .height(46)
    .padding({ left: 13, right: 13 })
    .margin({ left: 14, right: 14, top: 4, bottom: 8 })
    .backgroundColor(CARD_BG)
    .borderRadius(14);
  }

  @Builder
  selectedChip(contact: ContactItem) {
    Column({ space: 3 }) {
      Stack({ alignContent: Alignment.TopEnd }) {
        AvatarView({
          avatarPath: contact.avatarPath,
          initials: contact.initials,
          colorSeed: contact.id,
          avatarSize: 46
        });
        Row() {
          SymbolGlyph($r('sys.symbol.xmark')).fontSize(10).fontColor([Color.White]);
        }
        .width(18).height(18).borderRadius(9)
        .backgroundColor('#8E8E93')
        .justifyContent(FlexAlign.Center)
        .offset({ x: 4, y: -4 });
      }
      Text(contact.name)
        .fontSize(11)
        .fontColor(COLOR_TEXT_PRIMARY)
        .maxLines(1)
        .width(62)
        .textAlign(TextAlign.Center)
        .textOverflow({ overflow: TextOverflow.Ellipsis });
    }
    .onClick((): void => { this.toggle(contact.id); });
  }

  @Builder
  selectedSummary() {
    if (this.selectedIds.length > 0) {
      Scroll() {
        Row({ space: 10 }) {
          ForEach(this.selectedIds, (userId: number) => {
            this.selectedChip(this.contactFor(userId));
          }, (userId: number): string => `${userId}`);
        }
        .padding({ left: 16, right: 16, top: 6, bottom: 8 });
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%');
    }
  }

  @Builder
  contactRow(contact: ContactItem) {
    Row({ space: 13 }) {
      AvatarView({
        avatarPath: contact.avatarPath,
        initials: contact.initials,
        colorSeed: contact.id,
        avatarSize: 48
      });
      Column({ space: 2 }) {
        Text(contact.name)
          .fontSize(16)
          .fontColor(COLOR_TEXT_PRIMARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
        Text(contact.statusText)
          .fontSize(13)
          .fontColor(contact.online ? COLOR_PRIMARY : COLOR_TEXT_SECONDARY);
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1);
      Row() {
        if (this.selected(contact.id)) {
          SymbolGlyph($r('sys.symbol.checkmark'))
            .fontSize(15)
            .fontColor([Color.White]);
        }
      }
      .width(24).height(24)
      .borderRadius(12)
      .border({ width: this.selected(contact.id) ? 0 : 1.5, color: '#C7C7CC' })
      .backgroundColor(this.selected(contact.id) ? COLOR_PRIMARY : Color.Transparent)
      .justifyContent(FlexAlign.Center);
    }
    .width('100%')
    .padding({ left: 16, right: 18, top: 8, bottom: 8 })
    .alignItems(VerticalAlign.Center)
    .onClick((): void => { this.toggle(contact.id); });
  }

  @Builder
  memberPicker() {
    Column() {
      this.searchBox();
      this.selectedSummary();
      if (this.loading) {
        Column({ space: 10 }) {
          LoadingProgress().width(30).height(30).color(COLOR_PRIMARY);
          Text('正在加载联系人…').fontSize(14).fontColor(COLOR_TEXT_SECONDARY);
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center);
      } else if (this.filteredContacts().length === 0 && !this.remoteLoading) {
        Column({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.person_2')).fontSize(42).fontColor([COLOR_TEXT_SECONDARY]);
          Text(this.query.trim() === '' ? '暂无联系人' : '没有找到用户')
            .fontSize(15).fontColor(COLOR_TEXT_SECONDARY);
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center);
      } else {
        List() {
          ForEach(this.filteredContacts(), (contact: ContactItem) => {
            ListItem() {
              Column() {
                this.contactRow(contact);
                Divider().strokeWidth(0.5).color($r('app.color.divider')).margin({ left: 77 });
              }
            }
          }, (contact: ContactItem): string =>
            `${contact.id}_${contact.avatarPath}_${this.selected(contact.id)}`
          );
          if (this.remoteLoading) {
            ListItem() {
              Row({ space: 8 }) {
                LoadingProgress().width(18).height(18).color(COLOR_PRIMARY);
                Text('正在搜索陌生用户…').fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
              }
              .width('100%')
              .height(54)
              .justifyContent(FlexAlign.Center);
            }
          }
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring);
      }
    }
    .layoutWeight(1);
  }

  @Builder
  namingMember(contact: ContactItem, index: number) {
    if (index > 0) {
      Divider().strokeWidth(0.5).color($r('app.color.divider')).margin({ left: 76 });
    }
    Row({ space: 12 }) {
      AvatarView({
        avatarPath: contact.avatarPath,
        initials: contact.initials,
        colorSeed: contact.id,
        avatarSize: 44
      });
      Text(contact.name).fontSize(16).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1);
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 8 });
  }

  @Builder
  namingPage() {
    Column({ space: 18 }) {
      Row({ space: 15 }) {
        Row() {
          SymbolGlyph($r('sys.symbol.person_3_fill')).fontSize(34).fontColor([Color.White]);
        }
        .width(72).height(72)
        .borderRadius(36)
        .backgroundColor(COLOR_PRIMARY)
        .justifyContent(FlexAlign.Center);
        TextInput({ text: this.title, placeholder: '群组名称' })
          .layoutWeight(1)
          .height(52)
          .fontSize(18)
          .backgroundColor(Color.Transparent)
          .border({ width: { bottom: 1 }, color: COLOR_PRIMARY })
          .onChange((value: string): void => { this.title = value; });
      }
      .padding({ left: 18, right: 18, top: 24 });

      Column() {
        Text(`${this.selectedIds.length} 位成员`)
          .width('100%')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(COLOR_PRIMARY)
          .padding({ left: 16, top: 12, bottom: 8 });
        ForEach(this.selectedIds, (userId: number, index: number) => {
          this.namingMember(this.contactFor(userId), index);
        }, (userId: number): string => `selected_${userId}`);
      }
      .margin({ left: 14, right: 14 })
      .backgroundColor(CARD_BG)
      .borderRadius(14);
    }
    .layoutWeight(1)
    .width('100%');
  }

  build() {
    Column() {
      this.header();
      if (this.naming) {
        this.namingPage();
      } else {
        this.memberPicker();
      }
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.topSafe, bottom: this.bottomSafe })
    .backgroundColor(PAGE_BG);
  }
}
