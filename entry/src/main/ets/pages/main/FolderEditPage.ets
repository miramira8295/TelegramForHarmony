import { router, promptAction } from '@kit.ArkUI';
import { TdError } from '../../tdkit/TdTypes';
import { getChatStore } from '../../tdkit/Globals';
import { ChatEntry } from '../../store/ChatEntry';
import { FolderData, emptyFolder, getFolder, saveFolder } from '../../store/FolderApi';
import { AvatarView } from '../chatlist/AvatarView';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';

const CARD_RADIUS: number = 14;

export interface FolderEditParams {
  folderId: number; // 0 = create a new folder
}

// Which list the chat picker is currently filling.
const PICK_INCLUDE: string = 'include';
const PICK_EXCLUDE: string = 'exclude';

// 编辑文件夹: name, the chat-type filters TDLib applies, and the explicit
// include/exclude chat lists. Everything here maps straight onto the chatFolder
// object; icon, colour and pinned chats are carried through untouched.
@Entry
@Component
struct FolderEditPage {
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @State folderId: number = 0;
  @State name: string = '';
  @State included: number[] = [];
  @State excluded: number[] = [];
  @State includeContacts: boolean = false;
  @State includeNonContacts: boolean = false;
  @State includeBots: boolean = false;
  @State includeGroups: boolean = false;
  @State includeChannels: boolean = false;
  @State excludeMuted: boolean = false;
  @State excludeRead: boolean = false;
  @State excludeArchived: boolean = false;
  @State loading: boolean = true;
  @State saving: boolean = false;
  // Chat picker sheet.
  @State pickerOpen: boolean = false;
  @State pickerMode: string = PICK_INCLUDE;
  @State pickerQuery: string = '';
  private base: FolderData = emptyFolder();

  aboutToAppear(): void {
    const p = router.getParams() as FolderEditParams | undefined;
    this.folderId = p !== undefined ? (p.folderId ?? 0) : 0;
    if (this.folderId === 0) {
      this.loading = false;
      return;
    }
    getFolder(this.folderId).then((f: FolderData) => {
      this.base = f;
      this.name = f.name;
      this.included = f.includedChatIds;
      this.excluded = f.excludedChatIds;
      this.includeContacts = f.includeContacts;
      this.includeNonContacts = f.includeNonContacts;
      this.includeBots = f.includeBots;
      this.includeGroups = f.includeGroups;
      this.includeChannels = f.includeChannels;
      this.excludeMuted = f.excludeMuted;
      this.excludeRead = f.excludeRead;
      this.excludeArchived = f.excludeArchived;
      this.loading = false;
    }).catch((e: TdError) => {
      console.error(`FolderEditPage.getFolder failed: ${e.message}`);
      this.loading = false;
      promptAction.showToast({ message: '读取文件夹失败', duration: 1500 });
    });
  }

  private chatTitle(id: number): string {
    const e = getChatStore().allEntries().find((c: ChatEntry) => c.id === id);
    return e !== undefined ? e.title : `${id}`;
  }

  private chatEntry(id: number): ChatEntry | undefined {
    return getChatStore().allEntries().find((c: ChatEntry) => c.id === id);
  }

  // Chats offered in the picker: everything we know about, minus the ones
  // already in the list being edited, filtered by the search box.
  private pickerChats(): ChatEntry[] {
    const chosen: number[] = this.pickerMode === PICK_INCLUDE ? this.included : this.excluded;
    const q = this.pickerQuery.trim().toLowerCase();
    return getChatStore().allEntries().filter((c: ChatEntry) =>
      chosen.indexOf(c.id) < 0 && (q === '' || c.title.toLowerCase().includes(q)));
  }

  private addChat(id: number): void {
    if (this.pickerMode === PICK_INCLUDE) {
      this.included = [...this.included, id];
      this.excluded = this.excluded.filter((x: number) => x !== id); // a chat can't be both
    } else {
      this.excluded = [...this.excluded, id];
      this.included = this.included.filter((x: number) => x !== id);
    }
  }

  private removeChat(id: number, fromIncluded: boolean): void {
    if (fromIncluded) {
      this.included = this.included.filter((x: number) => x !== id);
    } else {
      this.excluded = this.excluded.filter((x: number) => x !== id);
    }
  }

  private hasAnyFilter(): boolean {
    return this.included.length > 0 || this.includeContacts || this.includeNonContacts
      || this.includeBots || this.includeGroups || this.includeChannels;
  }

  // Validate at the boundary: TDLib rejects a nameless or empty folder with an
  // opaque error, so say what's missing here.
  private save(): void {
    const name = this.name.trim();
    if (name === '') {
      promptAction.showToast({ message: '请填写文件夹名称', duration: 1500 });
      return;
    }
    if (!this.hasAnyFilter()) {
      promptAction.showToast({ message: '至少要包含一个聊天或一类聊天', duration: 2000 });
      return;
    }
    if (this.saving) {
      return;
    }
    this.saving = true;
    const next: FolderData = {
      id: this.folderId,
      name,
      iconName: this.base.iconName,
      colorId: this.base.colorId,
      isShareable: this.base.isShareable,
      pinnedChatIds: this.base.pinnedChatIds.filter((id: number) => this.included.indexOf(id) >= 0),
      includedChatIds: this.included,
      excludedChatIds: this.excluded,
      excludeMuted: this.excludeMuted,
      excludeRead: this.excludeRead,
      excludeArchived: this.excludeArchived,
      includeContacts: this.includeContacts,
      includeNonContacts: this.includeNonContacts,
      includeBots: this.includeBots,
      includeGroups: this.includeGroups,
      includeChannels: this.includeChannels
    };
    saveFolder(next).then(() => {
      this.saving = false;
      promptAction.showToast({ message: this.folderId === 0 ? '文件夹已创建' : '已保存', duration: 1500 });
      router.back();
    }).catch((e: TdError) => {
      this.saving = false;
      console.error(`FolderEditPage.saveFolder failed: ${e.message}`);
      promptAction.showToast({ message: `保存失败：${e.message}`, duration: 2000 });
    });
  }

  @Builder
  header() {
    Row({ space: 16 }) {
      SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(26).fontColor([COLOR_TEXT_PRIMARY])
        .onClick(() => { router.back(); });
      Text(this.folderId === 0 ? '新建文件夹' : '编辑文件夹')
        .fontSize(22).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY)
        .layoutWeight(1);
      Text(this.saving ? '保存中…' : '保存').fontSize(16).fontColor(COLOR_PRIMARY)
        .onClick(() => { this.save(); });
    }
    .width('100%').height(48).padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center);
  }

  @Builder
  cardTitle(text: string) {
    Text(text).fontSize(15).fontWeight(FontWeight.Medium).fontColor(COLOR_PRIMARY)
      .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 6 });
  }

  @Builder
  typeToggle(title: string, on: boolean, onSet: (v: boolean) => void) {
    Row({ space: 12 }) {
      Text(title).fontSize(16).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1);
      Toggle({ type: ToggleType.Switch, isOn: on })
        .selectedColor(COLOR_PRIMARY)
        .onChange((v: boolean) => { onSet(v); });
    }
    .width('100%').padding({ left: 16, right: 16, top: 4, bottom: 4 })
    .alignItems(VerticalAlign.Center);
  }

  // Chosen-chat row. Inline in the ForEach rather than a @Builder: its content
  // must track the @State arrays.
  @Builder
  chatList(ids: number[], fromIncluded: boolean) {
    ForEach(ids, (id: number) => {
      Divider().color($r('app.color.divider')).strokeWidth(0.7).margin({ left: 62 });
      Row({ space: 12 }) {
        AvatarView({
          avatarPath: this.chatEntry(id)?.avatarPath ?? '',
          initials: this.chatEntry(id)?.initials ?? '?',
          colorSeed: id, avatarSize: 34
        });
        Text(this.chatTitle(id)).fontSize(16).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
        SymbolGlyph($r('sys.symbol.xmark')).fontSize(16).fontColor([COLOR_TEXT_SECONDARY])
          .onClick(() => { this.removeChat(id, fromIncluded); });
      }
      .width('100%').padding({ left: 16, right: 16, top: 7, bottom: 7 })
      .alignItems(VerticalAlign.Center);
    }, (id: number) => `c_${fromIncluded}_${id}`);
  }

  @Builder
  pickerSheet() {
    Column() {
      Text(this.pickerMode === PICK_INCLUDE ? '添加要包含的聊天' : '添加要排除的聊天')
        .fontSize(18).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY)
        .padding({ top: 14, bottom: 8 });
      TextInput({ placeholder: '搜索聊天', text: this.pickerQuery })
        .fontSize(15)
        .backgroundColor($r('app.color.page_bg'))
        .borderRadius(10)
        .margin({ left: 16, right: 16, bottom: 6 })
        .onChange((v: string) => { this.pickerQuery = v; });
      List() {
        ForEach(this.pickerChats(), (c: ChatEntry) => {
          ListItem() {
            Row({ space: 12 }) {
              AvatarView({
                avatarPath: c.avatarPath, initials: c.initials,
                colorSeed: c.id, avatarSize: 38
              });
              Text(c.title).fontSize(16).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1)
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
              SymbolGlyph($r('sys.symbol.plus')).fontSize(18).fontColor([COLOR_PRIMARY]);
            }
            .width('100%').padding({ left: 16, right: 16, top: 7, bottom: 7 })
            .alignItems(VerticalAlign.Center)
            .onClick(() => { this.addChat(c.id); });
          }
        }, (c: ChatEntry) => `pk_${c.id}`);
      }
      .layoutWeight(1).width('100%')
      .scrollBar(BarState.Off);
      Text('完成').fontSize(16).fontColor(Color.White)
        .width('100%').textAlign(TextAlign.Center)
        .backgroundColor(COLOR_PRIMARY).borderRadius(10)
        .padding({ top: 12, bottom: 12 })
        .margin({ left: 16, right: 16, top: 8, bottom: this.bottomSafe + 8 })
        .onClick(() => { this.pickerOpen = false; this.pickerQuery = ''; });
    }
    .width('100%').height('100%');
  }

  @Builder
  addRow(label: string, mode: string) {
    Row({ space: 10 }) {
      SymbolGlyph($r('sys.symbol.plus_circle')).fontSize(19).fontColor([COLOR_PRIMARY]);
      Text(label).fontSize(16).fontColor(COLOR_PRIMARY).layoutWeight(1);
    }
    .width('100%').padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.pickerMode = mode;
      this.pickerQuery = '';
      this.pickerOpen = true;
    });
  }

  build() {
    Column() {
      this.header();
      if (this.loading) {
        Column() {
          LoadingProgress().width(36).height(36).color(COLOR_TEXT_SECONDARY);
        }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
      } else {
        Scroll() {
          Column({ space: 14 }) {
            Column() {
              this.cardTitle('文件夹名称');
              TextInput({ placeholder: '例如：工作', text: this.name })
                .fontSize(16)
                .backgroundColor($r('app.color.page_bg'))
                .borderRadius(10)
                .margin({ left: 16, right: 16, bottom: 12 })
                .onChange((v: string) => { this.name = v; });
            }
            .width('100%').backgroundColor($r('app.color.surface')).borderRadius(CARD_RADIUS);

            Column() {
              this.cardTitle('包含的聊天');
              this.typeToggle('联系人', this.includeContacts,
                (v: boolean): void => { this.includeContacts = v; });
              this.typeToggle('非联系人', this.includeNonContacts,
                (v: boolean): void => { this.includeNonContacts = v; });
              this.typeToggle('群组', this.includeGroups,
                (v: boolean): void => { this.includeGroups = v; });
              this.typeToggle('频道', this.includeChannels,
                (v: boolean): void => { this.includeChannels = v; });
              this.typeToggle('机器人', this.includeBots,
                (v: boolean): void => { this.includeBots = v; });
              this.chatList(this.included, true);
              Divider().color($r('app.color.divider')).strokeWidth(0.7).margin({ left: 16 });
              this.addRow('添加聊天', PICK_INCLUDE);
            }
            .width('100%').backgroundColor($r('app.color.surface')).borderRadius(CARD_RADIUS)
            .padding({ top: 2, bottom: 2 });

            Column() {
              this.cardTitle('排除的聊天');
              this.typeToggle('已静音', this.excludeMuted,
                (v: boolean): void => { this.excludeMuted = v; });
              this.typeToggle('已读', this.excludeRead,
                (v: boolean): void => { this.excludeRead = v; });
              this.typeToggle('已归档', this.excludeArchived,
                (v: boolean): void => { this.excludeArchived = v; });
              this.chatList(this.excluded, false);
              Divider().color($r('app.color.divider')).strokeWidth(0.7).margin({ left: 16 });
              this.addRow('添加聊天', PICK_EXCLUDE);
            }
            .width('100%').backgroundColor($r('app.color.surface')).borderRadius(CARD_RADIUS)
            .padding({ top: 2, bottom: 2 });

            Text('单独排除的聊天优先于上面的类型规则。')
              .fontSize(12).fontColor(COLOR_TEXT_SECONDARY)
              .width('100%').padding({ left: 16, right: 16 });
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 8, bottom: this.bottomSafe + 24 });
        }
        .layoutWeight(1).width('100%')
        .align(Alignment.Top)
        .scrollBar(BarState.Off);
      }
    }
    .width('100%').height('100%')
    .backgroundColor($r('app.color.page_bg'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .padding({ top: this.topSafe })
    .bindSheet($$this.pickerOpen, this.pickerSheet(), {
      height: '70%',
      backgroundColor: $r('app.color.surface'),
      dragBar: true
    });
  }
}
