import { router, promptAction } from '@kit.ArkUI';
import { TdError } from '../../tdkit/TdTypes';
import { getFolderStore } from '../../tdkit/Globals';
import { FolderInfo } from '../../store/FolderStore';
import { FolderData, getFolder, deleteFolder, reorderFolders, folderChatCount } from '../../store/FolderApi';
import { FolderEditParams } from './FolderEditPage';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';

const CARD_RADIUS: number = 14;
const DANGER: string = '#E53935';

// 聊天文件夹: the folder list behind the chat-list tabs. Reordering is done with
// 上移/下移 rather than drag handles — the same reorderChatFolders call, without
// a drag gesture fighting the list's scroll.
@Entry
@Component
struct ChatFoldersPage {
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @State folders: FolderInfo[] = [];
  @State counts: Map<number, number> = new Map();
  private unsub: (() => void) | null = null;

  aboutToAppear(): void {
    this.unsub = getFolderStore().subscribe((list: FolderInfo[]) => {
      this.folders = list;
      for (const f of list) {
        this.loadCount(f.id);
      }
    });
  }

  aboutToDisappear(): void {
    if (this.unsub !== null) {
      this.unsub();
      this.unsub = null;
    }
  }

  private loadCount(id: number): void {
    getFolder(id).then((f: FolderData) => folderChatCount(f)).then((n: number) => {
      const next: Map<number, number> = new Map(this.counts);
      next.set(id, n);
      this.counts = next; // new map — @State only re-renders on assignment
    }).catch((e: TdError) => {
      console.error(`ChatFoldersPage.count(${id}) failed: ${e.message}`);
    });
  }

  private countLabel(id: number): string {
    const n = this.counts.get(id);
    return n === undefined ? '' : `${n} 个聊天`;
  }

  private edit(id: number): void {
    const params: FolderEditParams = { folderId: id };
    router.pushUrl({ url: 'pages/main/FolderEditPage', params });
  }

  private move(index: number, delta: number): void {
    const target = index + delta;
    if (target < 0 || target >= this.folders.length) {
      return;
    }
    const next: FolderInfo[] = [...this.folders];
    const moved = next[index];
    next[index] = next[target];
    next[target] = moved;
    this.folders = next; // optimistic; updateChatFolders will confirm
    reorderFolders(next.map((f: FolderInfo) => f.id)).catch((e: TdError) => {
      console.error(`ChatFoldersPage.reorder failed: ${e.message}`);
      promptAction.showToast({ message: '排序失败，请重试', duration: 1500 });
    });
  }

  private confirmDelete(f: FolderInfo): void {
    promptAction.showDialog({
      title: '删除文件夹',
      message: `确定要删除「${f.title}」吗？文件夹里的聊天不会被删除。`,
      buttons: [
        { text: '取消', color: COLOR_TEXT_SECONDARY as string },
        { text: '删除', color: DANGER }
      ]
    }).then((res: promptAction.ShowDialogSuccessResponse) => {
      if (res.index !== 1) {
        return;
      }
      deleteFolder(f.id).then(() => {
        promptAction.showToast({ message: '文件夹已删除', duration: 1500 });
      }).catch((e: TdError) => {
        console.error(`ChatFoldersPage.deleteFolder failed: ${e.message}`);
        promptAction.showToast({ message: '删除失败，请重试', duration: 1500 });
      });
    }).catch((e: Object) => {
      console.error(`ChatFoldersPage.showDialog failed: ${JSON.stringify(e)}`);
    });
  }

  @Builder
  header() {
    Row({ space: 16 }) {
      SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(26).fontColor([COLOR_TEXT_PRIMARY])
        .onClick(() => { router.back(); });
      Text('聊天文件夹').fontSize(22).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY)
        .layoutWeight(1);
    }
    .width('100%').height(48).padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center);
  }

  @Builder
  rowMenu(f: FolderInfo, index: number) {
    Menu() {
      MenuItem({ content: '编辑文件夹' }).onClick(() => { this.edit(f.id); });
      MenuItem({ content: '上移' })
        .enabled(index > 0)
        .onClick(() => { this.move(index, -1); });
      MenuItem({ content: '下移' })
        .enabled(index < this.folders.length - 1)
        .onClick(() => { this.move(index, 1); });
      MenuItem({ content: '删除文件夹' }).onClick(() => { this.confirmDelete(f); });
    }
  }

  build() {
    Column() {
      this.header();
      Scroll() {
        Column({ space: 14 }) {
          Text('把聊天分到不同的文件夹里，在聊天列表顶部快速切换。')
            .fontSize(13).fontColor(COLOR_TEXT_SECONDARY)
            .width('100%').textAlign(TextAlign.Center)
            .padding({ left: 24, right: 24, top: 6, bottom: 2 });

          Column() {
            Row() {
              Text('全部聊天').fontSize(16).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1);
              Text('默认').fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
            }
            .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 });

            ForEach(this.folders, (f: FolderInfo, idx: number) => {
              Divider().color($r('app.color.divider')).strokeWidth(0.7).margin({ left: 16 });
              Row({ space: 10 }) {
                Column({ space: 2 }) {
                  Text(f.title).fontSize(16).fontColor(COLOR_TEXT_PRIMARY)
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
                  if (this.countLabel(f.id) !== '') {
                    Text(this.countLabel(f.id)).fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
                  }
                }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                .onClick(() => { this.edit(f.id); });
                SymbolGlyph($r('sys.symbol.dot_grid_1x2')).fontSize(20).fontColor([COLOR_TEXT_SECONDARY])
                  .bindMenu(this.rowMenu(f, idx));
              }
              .width('100%').padding({ left: 16, right: 16, top: 10, bottom: 10 })
              .alignItems(VerticalAlign.Center);
            }, (f: FolderInfo) => `f_${f.id}_${f.title}_${this.counts.get(f.id) ?? -1}`);

            Divider().color($r('app.color.divider')).strokeWidth(0.7).margin({ left: 16 });
            Row({ space: 10 }) {
              SymbolGlyph($r('sys.symbol.plus_circle')).fontSize(20).fontColor([COLOR_PRIMARY]);
              Text('创建新文件夹').fontSize(16).fontColor(COLOR_PRIMARY).layoutWeight(1);
            }
            .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 })
            .alignItems(VerticalAlign.Center)
            .onClick(() => { this.edit(0); });
          }
          .width('100%').backgroundColor($r('app.color.surface')).borderRadius(CARD_RADIUS);

          Text('点击文件夹可编辑名称与包含的聊天；右侧菜单可以调整顺序或删除。')
            .fontSize(12).fontColor(COLOR_TEXT_SECONDARY)
            .width('100%').padding({ left: 16, right: 16, top: 4 });
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 8, bottom: this.bottomSafe + 24 });
      }
      .layoutWeight(1).width('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Off);
    }
    .width('100%').height('100%')
    .backgroundColor($r('app.color.page_bg'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .padding({ top: this.topSafe });
  }
}
