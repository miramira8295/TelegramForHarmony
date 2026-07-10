import {
  IjkMediaPlayer,
  OnBufferingUpdateListener,
  OnCompletionListener,
  OnErrorListener,
  OnInfoListener,
  OnPreparedListener,
  OnVideoSizeChangedListener
} from '@ohos/ijkplayer';
import { audio } from '@kit.AudioKit';
import { getTdClient } from '../../tdkit/Globals';
import { VideoRangeServer } from '../../services/VideoRangeServer';
import { VideoStreamSession } from '../../services/VideoStreamSession';

const CONTROL_BAR_BG: string = '#6e3e3e40';
const CONTROL_ACCENT: string = '#FFFFFF';
const CONTROL_TEXT_SOFT: string = '#F3F4F6';
const CONTROL_TRACK: string = '#1F2329';
const CONTROL_TRACK_SOFT: string = '#2C3138';

// Output device types that count as "headphones": unplugging/disconnecting one
// of these pauses playback instead of blasting the speaker.
const HEADSET_DEVICE_TYPES: audio.DeviceType[] = [
  audio.DeviceType.WIRED_HEADSET,
  audio.DeviceType.WIRED_HEADPHONES,
  audio.DeviceType.BLUETOOTH_SCO,
  audio.DeviceType.BLUETOOTH_A2DP
];

const SPEEDS: string[] = ['0.5', '1.0', '1.5', '2.0'];
const SPEED_LABELS: string[] = ['0.5x', '1.0x', '1.5x', '2.0x'];
const DEFAULT_SPEED_IDX: number = 1;
let nextPlayerInstanceId: number = 1;

// mm:ss (or h:mm:ss for videos over an hour) for the time labels.
function formatMs(ms: number): string {
  const totalSeconds = Math.max(0, Math.floor(ms / 1000));
  const h = Math.floor(totalSeconds / 3600);
  const m = Math.floor((totalSeconds % 3600) / 60);
  const s = totalSeconds % 60;
  const mm = h > 0 ? `${m}`.padStart(2, '0') : `${m}`;
  const ss = `${s}`.padStart(2, '0');
  return h > 0 ? `${h}:${mm}:${ss}` : `${mm}:${ss}`;
}

@Component
export struct StreamingVideoPlayer {
  @Prop fileId: number;
  @Prop fileSize: number;
  @Prop mimeType: string = '';
  @Prop videoWidth: number = 0;
  @Prop videoHeight: number = 0;
  @Prop showControls: boolean = true;
  @StorageProp('topSafeHeight') topSafe: number = 0;
  onBackgroundTap: () => void = (): void => {};
  onSwipeNext: () => void = (): void => {};
  onSwipePrev: () => void = (): void => {};
  private player: IjkMediaPlayer | null = null;
  private session: VideoStreamSession | null = null;
  private rangeServer: VideoRangeServer | null = null;
  private progressUnsub: (() => void) | null = null;
  private routingManager: audio.AudioRoutingManager | null = null;
  private deviceChangeCb: ((change: audio.DeviceChangeAction) => void) | null = null;
  private progressTimer: number = -1;
  private readonly playerInstanceId: number = nextPlayerInstanceId++;
  @State status: string = '正在缓冲...';
  @State bufferedPercent: number = 0;
  @State isPlaying: boolean = false;
  @State currentTimeMs: number = 0;
  @State durationMs: number = 0;
  @State dragging: boolean = false;
  @State dragValueMs: number = 0;
  @State speedIdx: number = DEFAULT_SPEED_IDX;
  @State isCompleted: boolean = false;
  @State decodedAspectRatio: number = 0;
  @State viewportWidth: number = 1;
  @State viewportHeight: number = 1;

  aboutToDisappear(): void {
    this.release();
  }

  // Pause when a headset (wired or Bluetooth) disconnects, per platform convention.
  private setupAudioDeviceListener(): void {
    try {
      const routingManager = audio.getAudioManager().getRoutingManager();
      this.routingManager = routingManager;
      this.deviceChangeCb = (change: audio.DeviceChangeAction): void => {
        if (change.type !== audio.DeviceChangeType.DISCONNECT) {
          return;
        }
        const unpluggedHeadset = change.deviceDescriptors.some(
          (d: audio.AudioDeviceDescriptor) => HEADSET_DEVICE_TYPES.includes(d.deviceType));
        if (unpluggedHeadset && this.isPlaying && this.player !== null) {
          this.player.pause();
          this.isPlaying = false;
        }
      };
      routingManager.on('deviceChange', audio.DeviceFlag.OUTPUT_DEVICES_FLAG, this.deviceChangeCb);
    } catch (e) {
      console.error(`StreamingVideoPlayer.setupAudioDeviceListener failed: ${e}`);
    }
  }

  private cleanupAudioDeviceListener(): void {
    if (this.routingManager !== null && this.deviceChangeCb !== null) {
      try {
        this.routingManager.off('deviceChange', this.deviceChangeCb);
      } catch (e) {
        console.error(`StreamingVideoPlayer.cleanupAudioDeviceListener failed: ${e}`);
      }
    }
    this.routingManager = null;
    this.deviceChangeCb = null;
  }

  private release(): void {
    this.cleanupAudioDeviceListener();
    this.stopProgressPolling();
    if (this.progressUnsub !== null) {
      this.progressUnsub();
      this.progressUnsub = null;
    }
    if (this.player !== null) {
      const p = this.player;
      this.player = null;
      try {
        // Native release must finish before its HTTP source is closed.
        p.release();
      } catch (e) {
        console.error(`StreamingVideoPlayer.release failed: ${e}`);
      }
    }
    if (this.rangeServer !== null) {
      this.rangeServer.close();
      this.rangeServer = null;
    }
    if (this.session !== null) {
      this.session.close();
      this.session = null;
    }
    this.isPlaying = false;
  }

  private async initPlayer(context: object): Promise<void> {
    if (this.fileId === 0 || this.player !== null || this.session !== null) {
      return;
    }
    if (this.fileSize <= 0) {
      this.status = '无法获取视频大小';
      return;
    }
    this.status = '正在缓冲...';
    this.setupAudioDeviceListener();
    const session = new VideoStreamSession(getTdClient(), this.fileId, this.fileSize);
    this.session = session;
    this.progressUnsub = session.subscribeProgress((buffered: number, total: number): void => {
      this.bufferedPercent = total > 0 ? Math.min(100, Math.floor((buffered / total) * 100)) : 0;
    });
    session.start();
    try {
      const rangeServer = new VideoRangeServer(session, this.fileId, this.fileSize, this.mimeType);
      this.rangeServer = rangeServer;
      const sourceUrl = await rangeServer.start();
      if (this.session !== session) {
        rangeServer.close();
        return;
      }
      const componentId = this.componentId();
      const player = new IjkMediaPlayer(componentId);
      this.player = player;
      player.setContext(context, componentId);
      player.native_setup();
      const preparedListener: OnPreparedListener = {
        onPrepared: (): void => {
          if (this.player !== player) {
            return;
          }
          this.status = '';
          this.durationMs = Math.max(0, player.getDuration());
          player.setSpeed(SPEEDS[this.speedIdx]);
          player.start();
          this.isPlaying = true;
          this.isCompleted = false;
          this.startProgressPolling();
        }
      };
      const completionListener: OnCompletionListener = {
        onCompletion: (): void => {
          this.isPlaying = false;
          this.isCompleted = true;
          this.currentTimeMs = this.durationMs;
        }
      };
      // The ring tracks the actual TDLib download (subscribeProgress above), not
      // ijk's playback buffer — ijk reports 100% long before the file is local,
      // which used to make the ring lie and disappear early.
      const bufferingListener: OnBufferingUpdateListener = {
        onBufferingUpdate: (): void => {}
      };
      const infoListener: OnInfoListener = {
        onInfo: (what: number, extra: number): void => {
          if (what === 701) {
            this.status = '正在缓冲...';
          } else if (what === 702 || what === 3) {
            this.status = '';
          }
        }
      };
      const errorListener: OnErrorListener = {
        onError: (what: number, extra: number): void => {
          this.status = '播放失败';
          this.isPlaying = false;
          console.error(`StreamingVideoPlayer error: what=${what}, extra=${extra}`);
        }
      };
      const sizeListener: OnVideoSizeChangedListener = {
        onVideoSizeChanged: (width: number, height: number, sarNum: number, sarDen: number): void => {
          this.updateVideoAspect(width, height, sarNum, sarDen);
        }
      };
      player.setOnPreparedListener(preparedListener);
      player.setOnCompletionListener(completionListener);
      player.setOnBufferingUpdateListener(bufferingListener);
      player.setOnInfoListener(infoListener);
      player.setOnErrorListener(errorListener);
      player.setOnVideoSizeChangedListener(sizeListener);
      player.setMessageListener();
      player.setOptionLong(IjkMediaPlayer.OPT_CATEGORY_PLAYER, 'start-on-prepared', '0');
      player.setOptionLong(IjkMediaPlayer.OPT_CATEGORY_PLAYER, 'enable-accurate-seek', '1');
      player.setOptionLong(IjkMediaPlayer.OPT_CATEGORY_PLAYER, 'soundtouch', '1');
      player.setOptionLong(IjkMediaPlayer.OPT_CATEGORY_PLAYER, 'mediacodec-all-videos', '1');
      player.setOptionLong(IjkMediaPlayer.OPT_CATEGORY_FORMAT, 'timeout', '60000000');
      player.setDataSource(sourceUrl);
      player.prepareAsync();
    } catch (e) {
      this.status = '播放失败';
      console.error(`StreamingVideoPlayer.init failed: ${e}`);
      this.release();
    }
  }

  private togglePlay(): void {
    if (this.player === null) {
      return;
    }
    if (this.isPlaying) {
      this.player.pause();
      this.isPlaying = false;
    } else {
      this.player.start();
      this.isPlaying = true;
    }
  }

  private replay(): void {
    if (this.player === null) {
      return;
    }
    this.isCompleted = false;
    this.currentTimeMs = 0;
    this.player.seekTo('0');
    this.player.start();
    this.isPlaying = true;
  }

  // Drag the seek bar: track the dragged position live (without fighting the
  // player's own timeUpdate events); commit the seek only once the user
  // releases (End) or taps a new spot (Click).
  private onSeekChange(value: number, mode: SliderChangeMode): void {
    if (mode === SliderChangeMode.Begin || mode === SliderChangeMode.Moving) {
      this.dragging = true;
      this.dragValueMs = value;
      return;
    }
    this.dragging = false;
    this.currentTimeMs = value;
    if (this.player !== null) {
      this.player.seekTo(`${Math.floor(value)}`);
    }
  }

  private cycleSpeed(): void {
    this.speedIdx = (this.speedIdx + 1) % SPEEDS.length;
    if (this.player !== null) {
      this.player.setSpeed(SPEEDS[this.speedIdx]);
    }
  }

  private onSwipeSwitch(offsetX: number): void {
    if (Math.abs(offsetX) < 50) {
      return;
    }
    if (offsetX < 0) {
      this.onSwipeNext();
    } else {
      this.onSwipePrev();
    }
  }

  private componentId(): string {
    return `stream_video_${this.fileId}_${this.playerInstanceId}`;
  }

  private startProgressPolling(): void {
    this.stopProgressPolling();
    this.progressTimer = setInterval((): void => {
      if (this.player === null) {
        return;
      }
      if (!this.dragging) {
        this.currentTimeMs = Math.max(0, this.player.getCurrentPosition());
      }
      const duration = this.player.getDuration();
      if (duration > 0) {
        this.durationMs = duration;
      }
      this.updateVideoAspect(this.player.getVideoWidth(), this.player.getVideoHeight(),
        this.player.getVideoSarNum(), this.player.getVideoSarDen());
      this.isPlaying = this.player.isPlaying();
    }, 350);
  }

  private stopProgressPolling(): void {
    if (this.progressTimer >= 0) {
      clearInterval(this.progressTimer);
      this.progressTimer = -1;
    }
  }

  private updateVideoAspect(width: number, height: number, sarNum: number, sarDen: number): void {
    if (width <= 0 || height <= 0) {
      return;
    }
    const pixelAspect = sarNum > 0 && sarDen > 0 ? sarNum / sarDen : 1;
    const aspect = (width * pixelAspect) / height;
    if (Number.isFinite(aspect) && aspect > 0 && Math.abs(aspect - this.decodedAspectRatio) > 0.001) {
      this.decodedAspectRatio = aspect;
    }
  }

  private displayAspectRatio(): number {
    if (this.decodedAspectRatio > 0) {
      return this.decodedAspectRatio;
    }
    if (this.videoWidth > 0 && this.videoHeight > 0) {
      return this.videoWidth / this.videoHeight;
    }
    return 16 / 9;
  }

  private surfaceWidth(): number {
    const aspect = this.displayAspectRatio();
    const viewportAspect = this.viewportWidth / this.viewportHeight;
    return viewportAspect > aspect ? this.viewportHeight * aspect : this.viewportWidth;
  }

  private surfaceHeight(): number {
    const aspect = this.displayAspectRatio();
    const viewportAspect = this.viewportWidth / this.viewportHeight;
    return viewportAspect > aspect ? this.viewportHeight : this.viewportWidth / aspect;
  }

  @Builder
  ghostButton(label: string, width: number, onTap?: () => void) {
    Row() {
      Text(label).fontSize(14).fontColor(CONTROL_ACCENT).fontWeight(FontWeight.Medium);
    }
    .width(width).height(30).justifyContent(FlexAlign.Center)
    .opacity(onTap !== undefined ? 1 : 0.72)
    .onClick(() => {
      if (onTap !== undefined) {
        onTap();
      }
    });
  }

  @Builder
  playControl() {
    Stack() {
      Circle({ width: 42, height: 42 }).fill('#00000000');
      if (this.isPlaying) {
        Row({ space: 5 }) {
          Column().width(4).height(16).borderRadius(2).backgroundColor(CONTROL_ACCENT);
          Column().width(4).height(16).borderRadius(2).backgroundColor(CONTROL_ACCENT);
        }
        .width(18).height(18)
        .justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center);
      } else {
        SymbolGlyph($r('sys.symbol.play_fill')).fontSize(22).fontColor([CONTROL_ACCENT]).margin({ left: 2 });
      }
    }
    .width(56).height(42)
    .onClick(() => { this.togglePlay(); });
  }

  build() {
    Stack() {
      XComponent({ id: this.componentId(), type: XComponentType.SURFACE, libraryname: 'ijkplayer_napi' })
        .width(this.surfaceWidth()).height(this.surfaceHeight())
        .onLoad((context: object) => {
          this.initPlayer(context);
        })
        .onDestroy(() => {
          this.release();
        })
        .onClick(() => { this.onBackgroundTap(); });
      // Top-right download indicator: stays visible until the file is fully
      // downloaded, with the status label underneath only while buffering.
      if (this.status !== '' || this.bufferedPercent < 100) {
        Column({ space: 4 }) {
          Stack() {
            Progress({ value: this.bufferedPercent, total: 100, type: ProgressType.Ring })
              .width(44).height(44).color(Color.White);
            Text(`${this.bufferedPercent}%`).fontSize(10).fontColor(Color.White);
          }
          if (this.status !== '') {
            Text(this.status).fontSize(11).fontColor(Color.White);
          }
        }
        .alignItems(HorizontalAlign.Center)
        .padding(8).backgroundColor('#00000066').borderRadius(14)
        // Same vertical line as the viewer's top chrome bar.
        .position({ x: '100%', y: this.topSafe + 12 })
        .markAnchor({ x: '100%', y: 0 })
        .offset({ x: -16 });
      }
      if (this.isCompleted) {
        Stack() {
          Row({ space: 8 }) {
            Text('↻').fontSize(30).fontColor(Color.White).fontWeight(FontWeight.Medium);
            Text('重播').fontSize(18).fontColor(Color.White).fontWeight(FontWeight.Medium);
          }
          .padding({ left: 20, right: 20, top: 14, bottom: 14 })
          .backgroundColor(CONTROL_BAR_BG)
          .borderRadius(20);
        }
        .constraintSize({ minWidth: 140, minHeight: 64 })
        .onClick(() => { this.replay(); });
      }
      if (this.showControls) {
        Column() {
          // The blank area above the bar handles background taps itself (toggle
          // chrome) — no Transparent pass-through, so the bar's buttons keep
          // their events instead of leaking to the XComponent underneath.
          Blank().layoutWeight(1)
            .onClick(() => { this.onBackgroundTap(); });
          Column({ space: 10 }) {
            Row() {
              Blank().layoutWeight(1);
              this.playControl();
              Row({ space: 8 }) {
                this.ghostButton('↻', 30, () => { this.replay(); });
                this.ghostButton(SPEED_LABELS[this.speedIdx], 42, () => { this.cycleSpeed(); });
              }
              .layoutWeight(1)
              .justifyContent(FlexAlign.End)
              .alignItems(VerticalAlign.Center);
            }.width('100%').alignItems(VerticalAlign.Center);
            Row({ space: 8 }) {
              Text(formatMs(this.dragging ? this.dragValueMs : this.currentTimeMs))
                .fontSize(11).fontColor(CONTROL_TEXT_SOFT).fontWeight(FontWeight.Medium);
              Stack() {
                Row()
                  .width('100%').height(4).borderRadius(2).backgroundColor(CONTROL_TRACK_SOFT);
                Row()
                  .width(this.durationMs > 0
                    ? `${Math.max(0, Math.min(100, ((this.dragging ? this.dragValueMs : this.currentTimeMs) / this.durationMs) * 100))}%`
                    : '0%')
                  .height(4).borderRadius(2).backgroundColor(CONTROL_TRACK)
                  .align(Alignment.Start);
                Slider({
                  value: this.dragging ? this.dragValueMs : this.currentTimeMs,
                  min: 0, max: this.durationMs > 0 ? this.durationMs : 1, step: 1
                })
                  .width('100%')
                  .trackColor('#00000000').selectedColor('#00000000').blockColor(CONTROL_ACCENT)
                  .blockSize({ width: 16, height: 16 })
                  .onChange((value: number, mode: SliderChangeMode) => { this.onSeekChange(value, mode); });
              }
              .layoutWeight(1)
              .height(20)
              .align(Alignment.Center);
              Text(formatMs(this.durationMs)).fontSize(11).fontColor(CONTROL_TEXT_SOFT).fontWeight(FontWeight.Medium);
            }.width('100%').alignItems(VerticalAlign.Center);
          }
          .margin({ left: 12, right: 12, bottom: 18 })
          .padding({ left: 14, right: 14, top: 12, bottom: 12 })
          .backgroundColor(CONTROL_BAR_BG)
          .borderRadius(18);
          // NOTE: no hitTestBehavior on this wrapper or the bar. Block suppresses
          // hit-testing of CHILDREN (killed every button), and Transparent leaks
          // gesture events through to the XComponent (buttons lose to its onClick).
        }.width('100%').height('100%');
      }
    }
    .width('100%').height('100%').backgroundColor(Color.Black)
    .onAreaChange((_old: Area, area: Area): void => {
      const width = area.width as number;
      const height = area.height as number;
      if (width > 0 && height > 0) {
        this.viewportWidth = width;
        this.viewportHeight = height;
      }
    });
  }
}
