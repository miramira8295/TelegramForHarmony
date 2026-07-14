import { router, promptAction } from '@kit.ArkUI';
import { TdError } from '../../tdkit/TdTypes';
import {
  StorageUsage, NetworkUsage, formatBytes,
  getStorageUsage, clearCache, getNetworkUsage, resetNetworkUsage, clearAllDrafts
} from '../../store/StorageApi';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';

const CARD_RADIUS: number = 14;
const DANGER: string = '#E53935';

// 数据与存储. Only rows that map to a TDLib call live here: media auto-download
// and "save to gallery" are client-side behaviours we haven't built, and a
// switch that changes nothing is worse than no switch at all.
@Entry
@Component
struct DataStoragePage {
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @State cacheSize: number = 0;
  @State cacheCount: number = 0;
  @State dbSize: number = 0;
  @State sent: number = 0;
  @State received: number = 0;
  @State since: number = 0;
  @State busy: boolean = false;

  aboutToAppear(): void {
    this.load();
  }

  onPageShow(): void {
    this.load();
  }

  private load(): void {
    getStorageUsage().then((s: StorageUsage) => {
      this.cacheSize = s.filesSize;
      this.cacheCount = s.fileCount;
      this.dbSize = s.databaseSize;
    }).catch((e: TdError) => {
      console.error(`DataStoragePage.getStorageUsage failed: ${e.message}`);
    });
    getNetworkUsage().then((n: NetworkUsage) => {
      this.sent = n.sent;
      this.received = n.received;
      this.since = n.sinceDate;
    }).catch((e: TdError) => {
      console.error(`DataStoragePage.getNetworkUsage failed: ${e.message}`);
    });
  }

  private sinceLabel(): string {
    if (this.since === 0) {
      return '';
    }
    const d = new Date(this.since * 1000);
    return `自 ${d.getFullYear()}-${d.getMonth() + 1}-${d.getDate()} 起`;
  }

  private confirm(title: string, message: string, okText: string, okColor: string,
    run: () => Promise<void>, done: string): void {
    promptAction.showDialog({
      title, message,
      buttons: [
        { text: '取消', color: COLOR_TEXT_SECONDARY as string },
        { text: okText, color: okColor }
      ]
    }).then((res: promptAction.ShowDialogSuccessResponse) => {
      if (res.index !== 1 || this.busy) {
        return;
      }
      this.busy = true;
      run().then(() => {
        this.busy = false;
        promptAction.showToast({ message: done, duration: 1500 });
        this.load();
      }).catch((e: TdError) => {
        this.busy = false;
        console.error(`DataStoragePage action failed: ${e.message}`);
        promptAction.showToast({ message: '操作失败，请重试', duration: 1500 });
      });
    }).catch((e: Object) => {
      console.error(`DataStoragePage.showDialog failed: ${JSON.stringify(e)}`);
    });
  }

  @Builder
  header() {
    Row({ space: 16 }) {
      SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(26).fontColor([COLOR_TEXT_PRIMARY])
        .onClick(() => { router.back(); });
      Text('数据与存储').fontSize(22).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY)
        .layoutWeight(1);
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
  footnote(text: string) {
    Text(text).fontSize(12).fontColor(COLOR_TEXT_SECONDARY)
      .width('100%').padding({ left: 16, right: 16, top: 6 });
  }

  // No-parameter builders throughout: a @Builder's value parameters are captured
  // on first render, so a parameterised row would stay at its loading-time value.
  @Builder
  storageCard() {
    Column() {
      this.cardTitle('存储和流量使用情况');
      Row({ space: 10 }) {
        Column({ space: 2 }) {
          Text('存储使用情况').fontSize(16).fontColor(COLOR_TEXT_PRIMARY);
          Text(`${this.cacheCount} 个缓存文件 · 数据库 ${formatBytes(this.dbSize)}`)
            .fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
        }.alignItems(HorizontalAlign.Start).layoutWeight(1);
        Text(formatBytes(this.cacheSize)).fontSize(15).fontColor(COLOR_PRIMARY);
      }
      .width('100%').padding({ left: 16, right: 16, top: 10, bottom: 10 })
      .alignItems(VerticalAlign.Center);
      Divider().color($r('app.color.divider')).strokeWidth(0.7).margin({ left: 16 });
      Row({ space: 10 }) {
        Column({ space: 2 }) {
          Text('流量使用情况').fontSize(16).fontColor(COLOR_TEXT_PRIMARY);
          Text(`已发送 ${formatBytes(this.sent)} · 已接收 ${formatBytes(this.received)}`)
            .fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
        }.alignItems(HorizontalAlign.Start).layoutWeight(1);
        Text(formatBytes(this.sent + this.received)).fontSize(15).fontColor(COLOR_PRIMARY);
      }
      .width('100%').padding({ left: 16, right: 16, top: 10, bottom: 10 })
      .alignItems(VerticalAlign.Center);
    }
    .width('100%').backgroundColor($r('app.color.surface')).borderRadius(CARD_RADIUS)
    .padding({ bottom: 4 });
  }

  @Builder
  actionsCard() {
    Column() {
      Text('清理缓存').fontSize(16).fontColor(COLOR_TEXT_PRIMARY)
        .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 })
        .onClick(() => {
          this.confirm('清理缓存',
            `将删除全部 ${formatBytes(this.cacheSize)} 已下载的图片、视频和文件。它们仍在云端，需要时会重新下载。`,
            '清理', COLOR_PRIMARY as string,
            (): Promise<void> => clearCache(), '缓存已清理');
        });
      Divider().color($r('app.color.divider')).strokeWidth(0.7).margin({ left: 16 });
      Text('重置流量统计').fontSize(16).fontColor(COLOR_TEXT_PRIMARY)
        .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 })
        .onClick(() => {
          this.confirm('重置流量统计', '流量计数将从现在重新开始。',
            '重置', COLOR_PRIMARY as string,
            (): Promise<void> => resetNetworkUsage(), '流量统计已重置');
        });
      Divider().color($r('app.color.divider')).strokeWidth(0.7).margin({ left: 16 });
      Text('清空所有云端草稿').fontSize(16).fontColor(DANGER)
        .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 })
        .onClick(() => {
          this.confirm('清空所有云端草稿', '所有会话里未发送的草稿都会被删除，此操作无法撤销。',
            '清空', DANGER,
            (): Promise<void> => clearAllDrafts(), '草稿已清空');
        });
    }
    .width('100%').backgroundColor($r('app.color.surface')).borderRadius(CARD_RADIUS);
  }

  build() {
    Column() {
      this.header();
      Scroll() {
        Column({ space: 14 }) {
          this.storageCard();
          if (this.since !== 0) {
            this.footnote(`流量统计${this.sinceLabel()}。`);
          }
          this.actionsCard();
          this.footnote('自动下载与「保存到相册」尚未实现，等做好了会出现在这里。');

          Column() {
            this.cardTitle('代理');
            Row({ space: 10 }) {
              Text('代理设置').fontSize(16).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1);
              SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(16).fontColor([COLOR_TEXT_SECONDARY]);
            }
            .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 })
            .alignItems(VerticalAlign.Center)
            .onClick(() => { router.pushUrl({ url: 'pages/main/ProxyPage' }); });
          }
          .width('100%').backgroundColor($r('app.color.surface')).borderRadius(CARD_RADIUS)
          .padding({ bottom: 4 });
          this.footnote('支持 SOCKS5、MTProto 和 HTTP 代理。');
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
