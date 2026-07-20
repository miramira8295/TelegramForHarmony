import { router } from '@kit.ArkUI';
import { LiveStreamStore } from '../../store/LiveStreamStore';
import { LiveStreamState, emptyLiveStreamState } from '../../tdkit/GroupCallTypes';
import { getTdClient } from '../../tdkit/Globals';
import { getGroupCall, leaveGroupCall } from '../../tdkit/GroupCallApi';
import { COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';

// 直播观看页(观众端)骨架 —— 计划 #1 只负责状态展示与生命周期管理;
// 画面/声音渲染由计划 #2 接入(StreamingVideoPlayer 等价物)。
@Entry
@Component
struct LiveStreamViewerPage {
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @State state: LiveStreamState = emptyLiveStreamState();
  private groupCallId: number = 0;
  private store: LiveStreamStore | null = null;
  private off: (() => void) | null = null;

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, Object> | undefined;
    this.groupCallId = params !== undefined ? ((params['groupCallId'] as number | undefined) ?? 0) : 0;
    const client = getTdClient();
    this.store = new LiveStreamStore(client, this.groupCallId);
    this.off = this.store.subscribe((s: LiveStreamState) => { this.state = s; });
    this.state = this.store.getState();
    getGroupCall(client, this.groupCallId).catch((e: Error) => {
      console.error(`LiveStreamViewerPage.getGroupCall failed: ${e.message}`);
    });
  }

  aboutToDisappear(): void {
    if (this.off !== null) { this.off(); this.off = null; }
    if (this.store !== null) { this.store.dispose(); this.store = null; }
    leaveGroupCall(getTdClient(), this.groupCallId).catch((e: Error) => {
      console.error(`LiveStreamViewerPage.leaveGroupCall failed: ${e.message}`);
    });
  }

  @Builder
  header() {
    Row({ space: 16 }) {
      SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(26).fontColor([COLOR_TEXT_PRIMARY])
        .onClick(() => { router.back(); });
      Text('直播').fontSize(18).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY)
        .layoutWeight(1);
    }
    .width('100%').height(48).padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center);
  }

  build() {
    Column() {
      this.header();
      Column() {
        Text(this.state.isActive ? '正在直播' : '直播未开始')
          .fontSize(18).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY)
          .margin({ top: 16 });
        Text(`观看人数：${this.state.participantCount}`)
          .fontSize(14).fontColor(COLOR_TEXT_SECONDARY).margin({ top: 8 });
        // 媒体区域占位 —— 音视频渲染将在计划 #2 接入
        Column() {
          Text('媒体播放将在计划 #2 接入').fontSize(13).fontColor('#888888');
        }
        .width('100%').height(220).backgroundColor(Color.Black)
        .justifyContent(FlexAlign.Center).borderRadius(8)
        .margin({ top: 16 });
        if (this.state.error !== '') {
          Text(this.state.error).fontSize(13).fontColor(Color.Red).margin({ top: 12 });
        }
      }
      .width('100%').layoutWeight(1).padding(16).alignItems(HorizontalAlign.Start);
    }
    .width('100%').height('100%')
    .backgroundColor($r('app.color.page_bg'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .padding({ top: this.topSafe, bottom: this.bottomSafe });
  }
}
