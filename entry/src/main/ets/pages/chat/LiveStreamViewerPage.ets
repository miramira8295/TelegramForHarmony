import { display, router } from '@kit.ArkUI';
import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { LiveStreamStore } from '../../store/LiveStreamStore';
import { GroupCallParticipantsStore } from '../../store/GroupCallParticipantsStore';
import {
  GroupCallParticipantInfo, GroupCallStreamInfo, GroupCallVideoSource, LiveStreamState, emptyLiveStreamState
} from '../../tdkit/GroupCallTypes';
import { getTdClient } from '../../tdkit/Globals';
import {
  endGroupCall, getGroupCall, leaveGroupCall, setGroupCallParticipantIsSpeaking,
  toggleGroupCallParticipantIsMuted
} from '../../tdkit/GroupCallApi';
import { TgcallsGroupSession, TgcallsJoinResult } from '../../services/TgcallsGroupSession';
import { liveStreamBackgroundTask } from '../../services/LiveStreamBackgroundTask';
import { TdObject } from '../../tdkit/TdTypes';
import { TdClient } from '../../tdkit/TdClient';
import {
  confirmAdminLeaveLiveStream, confirmLeaveLiveStream, setLiveStreamFullscreen
} from './LiveViewerUi';
import {
  FloatingLiveDescriptor, floatingLiveWindow
} from './LiveFloatingWindow';
import {
  KEY_POWER_CALL_ANIMATIONS, powerAnimationDuration, powerFeatureEnabled
} from '../../store/AppSettings';

const CALL_BACKGROUND: string = '#0D141B';
const CALL_PANEL: string = '#141E27';
const CALL_PANEL_ALT: string = '#101820';
const CALL_GREEN: string = '#39D98A';
const CALL_RED: string = '#D94B55';
const CALL_TEXT: string = '#F4F7F9';
const CALL_SUBTEXT: string = '#8B9BA8';
const AVATAR_COLORS: string[] = ['#4C9AFF', '#9C6ADE', '#E06C75', '#2CB67D', '#E39B3A', '#4CB8C4'];
const MICROPHONE_PERMISSION: Permissions = 'ohos.permission.MICROPHONE';
const CAMERA_PERMISSION: Permissions = 'ohos.permission.CAMERA';
const MEDIA_RECONNECT_GRACE_MS: number = 8000;
const MEDIA_HEALTH_INTERVAL_MS: number = 5000;
const LOCAL_VIDEO_START_TIMEOUT_MS: number = 20000;

interface LiveVideoSurfaceBinding {
  surfaceId: string;
  width: number;
  height: number;
}

@Component
struct LiveVideoTile {
  @Prop source: GroupCallVideoSource;
  @Prop tileHeight: number = 180;
  @Prop fillParent: boolean = false;
  @Prop showFullscreenButton: boolean = false;
  @Prop fullscreen: boolean = false;
  @Prop pulseExpanded: boolean = false;
  onSurfaceReady: (
    endpointId: string, surfaceId: string, surfaceWidth: number, surfaceHeight: number
  ) => void = (): void => {};
  onSurfaceGone: (endpointId: string, surfaceId: string) => void = (): void => {};
  onFullscreenToggle: () => void = (): void => {};
  private controller: XComponentController = new XComponentController();
  private boundSurfaceId: string = '0';
  private boundSurfaceWidth: number = 0;
  private boundSurfaceHeight: number = 0;

  aboutToDisappear(): void {
    if (this.boundSurfaceId !== '0') {
      this.onSurfaceGone(this.source.endpointId, this.boundSurfaceId);
    }
    this.boundSurfaceId = '0';
    this.boundSurfaceWidth = 0;
    this.boundSurfaceHeight = 0;
  }

  private refreshSurfaceSize(): void {
    if (this.boundSurfaceId === '0') { return; }
    const rect: SurfaceRect = this.controller.getXComponentSurfaceRect();
    const width = Math.max(1, Math.round(rect.surfaceWidth));
    const height = Math.max(1, Math.round(rect.surfaceHeight));
    if (width === this.boundSurfaceWidth && height === this.boundSurfaceHeight) { return; }
    this.boundSurfaceWidth = width;
    this.boundSurfaceHeight = height;
    this.onSurfaceReady(this.source.endpointId, this.boundSurfaceId, width, height);
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      XComponent({
        id: `group_call_video_${this.source.endpointId}`,
        // TEXTURE participates in ArkUI composition, so speaking borders,
        // labels and rounded clipping can safely sit above the video. A
        // SURFACE XComponent owns a separate surface layer and can remain
        // black when it is combined with these Stack overlays.
        type: XComponentType.TEXTURE,
        controller: this.controller
      })
        .onLoad((): void => {
          const rect: SurfaceRect = this.controller.getXComponentSurfaceRect();
          this.boundSurfaceId = this.controller.getXComponentSurfaceId();
          this.boundSurfaceWidth = Math.max(1, Math.round(rect.surfaceWidth));
          this.boundSurfaceHeight = Math.max(1, Math.round(rect.surfaceHeight));
          this.onSurfaceReady(
            this.source.endpointId, this.boundSurfaceId,
            this.boundSurfaceWidth, this.boundSurfaceHeight
          );
        })
        .onDestroy((): void => {
          if (this.boundSurfaceId !== '0') {
            this.onSurfaceGone(this.source.endpointId, this.boundSurfaceId);
          }
          this.boundSurfaceId = '0';
          this.boundSurfaceWidth = 0;
          this.boundSurfaceHeight = 0;
        })
        .width('100%').height('100%');

      if (this.source.isSpeaking) {
        Row()
          .width('100%').height('100%')
          .border({ width: this.pulseExpanded ? 3 : 2, color: CALL_GREEN })
          .borderRadius(8)
          .opacity(this.pulseExpanded ? 0.62 : 1);
      }

      if (this.source.isPaused) {
        Column() {
          SymbolGlyph($r('sys.symbol.camera')).fontSize(28).fontColor([CALL_SUBTEXT]);
          Text('视频已暂停').fontSize(12).fontColor(CALL_SUBTEXT).margin({ top: 6 });
        }
      }

      Column() {
        Blank();
        Row({ space: 5 }) {
          Stack({ alignContent: Alignment.Center }) {
            if (this.source.isSpeaking) {
              Circle({ width: 20, height: 20 }).fill('#5539D98A')
                .scale({ x: this.pulseExpanded ? 1.12 : 0.82, y: this.pulseExpanded ? 1.12 : 0.82 })
                .opacity(this.pulseExpanded ? 0.32 : 0.75);
            }
            SymbolGlyph($r('sys.symbol.mic'))
              .fontSize(this.source.isSpeaking && this.pulseExpanded ? 14 : 13)
              .fontColor([this.source.isMuted ? '#A9B4BC' : Color.White]);
          }
          .width(20).height(20);
          Text(this.source.name)
            .fontSize(12).fontColor(Color.White).fontWeight(FontWeight.Medium)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
        }
        .padding({ left: 8, right: 9, top: 4, bottom: 5 })
        .backgroundColor('#66000000').borderRadius(10)
        .margin({ left: 7, bottom: 7 }).alignSelf(ItemAlign.Start);
      }
      .width('100%').height('100%');

      if (this.showFullscreenButton) {
        Column() {
          Blank();
          Row() {
            Blank();
            Button({ type: ButtonType.Circle }) {
              if (this.fullscreen) {
                SymbolGlyph($r('sys.symbol.arrow_down_right_and_arrow_up_left'))
                  .fontSize(20).fontColor([Color.White]);
              } else {
                SymbolGlyph($r('sys.symbol.arrow_up_left_and_arrow_down_right'))
                  .fontSize(20).fontColor([Color.White]);
              }
            }
            .width(40).height(40).padding(0).backgroundColor('#A617222B')
            .border({ width: 1, color: '#42FFFFFF' })
            .onClick((): void => this.onFullscreenToggle());
          }.width('100%');
        }
        .width('100%').height('100%').padding({ right: 9, bottom: 9 });
      }
    }
    .width('100%').height(this.fillParent ? '100%' : `${this.tileHeight}vp`)
    .backgroundColor(Color.Black)
    .borderRadius(8).clip(true)
    .onAreaChange((_old: Area, _area: Area): void => {
      // Rotation resizes a TEXTURE XComponent after onLoad. Rebind the same
      // Surface with its new dimensions so the old canvas is not stretched.
      setTimeout((): void => this.refreshSurfaceSize(), 30);
    })
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.scale({ x: 0.96, y: 0.96 }))
      .animation({
        duration: powerAnimationDuration(KEY_POWER_CALL_ANIMATIONS, 220), curve: Curve.EaseOut
      }));
  }
}

@Component
struct LocalVideoPreviewTile {
  @Prop mode: number = 1;
  @Prop tileWidth: string = '100%';
  @Prop tileHeight: string = '190vp';
  @Prop compact: boolean = false;
  @Prop showFullscreenButton: boolean = false;
  @Prop fullscreen: boolean = false;
  onSurfaceReady: (
    surfaceId: string, surfaceWidth: number, surfaceHeight: number
  ) => void = (): void => {};
  onSurfaceGone: (surfaceId: string) => void = (): void => {};
  onFullscreenToggle: () => void = (): void => {};
  private controller: XComponentController = new XComponentController();
  private boundSurfaceId: string = '0';
  private boundSurfaceWidth: number = 0;
  private boundSurfaceHeight: number = 0;

  aboutToDisappear(): void {
    if (this.boundSurfaceId !== '0') {
      this.onSurfaceGone(this.boundSurfaceId);
      this.boundSurfaceId = '0';
    }
    this.boundSurfaceWidth = 0;
    this.boundSurfaceHeight = 0;
  }

  private refreshSurfaceSize(): void {
    if (this.boundSurfaceId === '0') { return; }
    const rect: SurfaceRect = this.controller.getXComponentSurfaceRect();
    const width = Math.max(1, Math.round(rect.surfaceWidth));
    const height = Math.max(1, Math.round(rect.surfaceHeight));
    if (width === this.boundSurfaceWidth && height === this.boundSurfaceHeight) { return; }
    this.boundSurfaceWidth = width;
    this.boundSurfaceHeight = height;
    this.onSurfaceReady(this.boundSurfaceId, width, height);
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      XComponent({
        id: `group_call_local_video_${this.mode}`,
        type: XComponentType.TEXTURE,
        controller: this.controller
      })
        .onLoad((): void => {
          const rect: SurfaceRect = this.controller.getXComponentSurfaceRect();
          this.boundSurfaceId = this.controller.getXComponentSurfaceId();
          this.boundSurfaceWidth = Math.max(1, Math.round(rect.surfaceWidth));
          this.boundSurfaceHeight = Math.max(1, Math.round(rect.surfaceHeight));
          this.onSurfaceReady(
            this.boundSurfaceId,
            this.boundSurfaceWidth,
            this.boundSurfaceHeight
          );
        })
        .onDestroy((): void => {
          if (this.boundSurfaceId !== '0') {
            this.onSurfaceGone(this.boundSurfaceId);
            this.boundSurfaceId = '0';
          }
          this.boundSurfaceWidth = 0;
          this.boundSurfaceHeight = 0;
        })
        .width('100%').height('100%');

      Column() {
        Blank();
        Row({ space: 5 }) {
          Circle({ width: 7, height: 7 }).fill(CALL_GREEN);
          Text(this.mode === 1 ? '你 · 前置' : '你 · 后置')
            .fontSize(this.compact ? 10 : 12)
            .fontColor(Color.White).fontWeight(FontWeight.Medium);
        }
        .padding({
          left: this.compact ? 7 : 9, right: this.compact ? 7 : 9,
          top: 4, bottom: 4
        })
        .backgroundColor('#8A000000').borderRadius(10)
        .margin({ left: 7, bottom: 7 }).alignSelf(ItemAlign.Start);
      }
      .width('100%').height('100%');

      if (this.showFullscreenButton) {
        Column() {
          Blank();
          Row() {
            Blank();
            Button({ type: ButtonType.Circle }) {
              if (this.fullscreen) {
                SymbolGlyph($r('sys.symbol.arrow_down_right_and_arrow_up_left'))
                  .fontSize(20).fontColor([Color.White]);
              } else {
                SymbolGlyph($r('sys.symbol.arrow_up_left_and_arrow_down_right'))
                  .fontSize(20).fontColor([Color.White]);
              }
            }
            .width(40).height(40).padding(0).backgroundColor('#A617222B')
            .border({ width: 1, color: '#42FFFFFF' })
            .onClick((): void => this.onFullscreenToggle());
          }.width('100%');
        }
        .width('100%').height('100%').padding({ right: 9, bottom: 9 });
      }
    }
    .width(this.tileWidth).height(this.tileHeight)
    .backgroundColor(Color.Black)
    .border({ width: this.compact ? 1.5 : 0, color: '#A6FFFFFF' })
    .borderRadius(this.compact ? 12 : 8).clip(true)
    .onAreaChange((_old: Area, _area: Area): void => {
      setTimeout((): void => this.refreshSurfaceSize(), 30);
    })
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.scale({ x: 0.96, y: 0.96 }))
      .animation({
        duration: powerAnimationDuration(KEY_POWER_CALL_ANIMATIONS, 200), curve: Curve.EaseOut
      }));
  }
}

@Entry
@Component
struct LiveStreamViewerPage {
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @StorageProp('appForegroundEpoch') @Watch('onAppForegroundEpoch') appForegroundEpoch: number = 0;
  @State state: LiveStreamState = emptyLiveStreamState();
  @State mediaStatus: string = '正在加入直播…';
  @State participants: GroupCallParticipantInfo[] = [];
  @State videoSources: GroupCallVideoSource[] = [];
  @State isMuted: boolean = true;
  @State pulseExpanded: boolean = false;
  @State microphoneScale: number = 1;
  @State videoAreaOpacity: number = 1;
  @State videoAreaScale: number = 1;
  @State isFullscreen: boolean = false;
  @State fullscreenPanelOpen: boolean = false;
  @State minimizeInProgress: boolean = false;
  @State localVideoMode: number = 0;
  @State localVideoActive: boolean = false;
  @State localVideoBusy: boolean = false;
  @State screenShareActive: boolean = false;
  @State screenShareBusy: boolean = false;
  @State desiredLocalVideoMode: number = 0;
  @State screenShareDesired: boolean = false;
  @State primaryVideoAspectRatio: number = 0;
  @State canManageLive: boolean = false;
  @State endingLive: boolean = false;
  private groupCallId: number = 0;
  private chatId: number = 0;
  private store: LiveStreamStore | null = null;
  private participantStore: GroupCallParticipantsStore | null = null;
  private off: (() => void) | null = null;
  private offParticipants: (() => void) | null = null;
  private tgcallsSession: TgcallsGroupSession | null = null;
  private requestedEndpoints: Set<string> = new Set();
  private unifiedSource: GroupCallVideoSource | null = null;
  private selfParticipantId: TdObject | null = null;
  private pulseTimer: number = -1;
  private videoSwitchSequence: number = 0;
  private pageActive: boolean = false;
  private mediaConnected: boolean = false;
  private hasJoinedOnce: boolean = false;
  private recoveryInFlight: boolean = false;
  private sessionSequence: number = 0;
  private reconnectAttempt: number = 0;
  private reconnectTimer: number = -1;
  private reconnectDueAt: number = 0;
  private healthTimer: number = -1;
  private groupCallRefreshInFlight: boolean = false;
  private surfaceBindings: Map<string, LiveVideoSurfaceBinding> = new Map();
  private leavingForFloating: boolean = false;
  private localVideoOperationSequence: number = 0;
  private screenShareOperationSequence: number = 0;
  private localPreviewSurfaceId: string = '0';
  private videoAspectRatios: Map<string, number> = new Map();

  aboutToAppear(): void {
    this.pageActive = true;
    const params = router.getParams() as Record<string, Object> | undefined;
    this.groupCallId = params !== undefined ? ((params['groupCallId'] as number | undefined) ?? 0) : 0;
    this.chatId = params !== undefined ? ((params['chatId'] as number | undefined) ?? 0) : 0;
    if (this.groupCallId <= 0) {
      this.mediaStatus = '无效的直播间';
      return;
    }
    this.startPulseAnimation();
    const client = getTdClient();
    this.store = new LiveStreamStore(client, this.groupCallId);
    this.off = this.store.subscribe((value: LiveStreamState): void => this.onLiveState(value));
    this.state = this.store.getState();
    this.participantStore = new GroupCallParticipantsStore(client, this.groupCallId);
    this.offParticipants = this.participantStore.subscribe(
      (value: GroupCallParticipantInfo[]): void => this.onParticipants(value)
    );

    const context = getContext(this) as common.UIAbilityContext;
    liveStreamBackgroundTask.start(context, !this.isMuted);
    this.startHealthMonitor();
    this.replaceSession('首次加入');
    this.refreshGroupCall('首次查询');
  }

  onPageShow(): void {
    if (this.pageActive && this.groupCallId > 0) { this.resumeAfterForeground(); }
  }

  private onAppForegroundEpoch(): void {
    if (this.pageActive && this.groupCallId > 0) { this.resumeAfterForeground(); }
  }

  private onLiveState(value: LiveStreamState): void {
    this.state = value;
    if (value.needRejoin) {
      this.scheduleRecovery(0, 'TDLib 要求重新加入');
    } else if (this.hasJoinedOnce && value.isActive && !value.isJoined) {
      this.scheduleRecovery(500, '直播成员状态已断开');
    }
  }

  private replaceSession(reason: string): void {
    if (!this.pageActive || this.groupCallId <= 0) { return; }
    if (this.recoveryInFlight) {
      this.scheduleRecovery(750, reason);
      return;
    }
    this.recoveryInFlight = true;
    this.clearRecoveryTimer();
    this.mediaConnected = false;
    const sequence = ++this.sessionSequence;
    const previous = this.tgcallsSession;
    // Ignore synchronous capturer-stop callbacks from the session being
    // replaced, while keeping the desired camera/screen mode for recovery.
    this.tgcallsSession = null;
    if (previous !== null) {
      previous.clearVideo();
      previous.stop();
    }
    this.requestedEndpoints.clear();
    this.unifiedSource = null;
    this.videoAspectRatios.clear();
    this.primaryVideoAspectRatio = 0;
    this.onParticipants(this.participants);
    this.mediaStatus = this.hasJoinedOnce ? '正在恢复直播连接…' : '正在加入直播…';

    const client = getTdClient();
    const session = new TgcallsGroupSession(
      (connected: boolean): void => this.onMediaNetworkState(session, connected),
      (audioSourceId: number, speaking: boolean): void => {
        this.onRemoteAudioActivity(session, client, audioSourceId, speaking);
      },
      (): void => {},
      (): void => {},
      (mode: number, active: boolean, error: number): void => {
        this.onLocalVideoState(session, mode, active, error);
      },
      (endpointId: string, width: number, height: number): void => {
        this.onVideoGeometry(session, endpointId, width, height);
      }
    );
    this.tgcallsSession = session;
    console.info(`[LiveStreamViewer] session ${sequence} start reason=${reason}`);
    session.join(client, this.groupCallId, this.isMuted).then((result: TgcallsJoinResult): void => {
      if (!this.pageActive || this.tgcallsSession !== session || sequence !== this.sessionSequence) { return; }
      this.hasJoinedOnce = true;
      this.reconnectAttempt = 0;
      this.clearRecoveryTimer();
      this.store?.setStreams(result.streams);
      this.state = {
        title: this.state.title,
        isActive: this.state.isActive,
        isRtmpStream: this.state.isRtmpStream,
        isJoined: true,
        needRejoin: false,
        canSendMessages: this.state.canSendMessages,
        areMessagesAllowed: this.state.areMessagesAllowed,
        participantCount: this.state.participantCount,
        streams: result.streams,
        error: ''
      };
      this.mediaStatus = result.isBroadcast
        ? (result.isUnifiedBroadcast ? 'RTMP 直播已连接' : '直播音视频已连接')
        : '正在建立媒体连接…';
      const unifiedVideoIds: number[] = [];
      const seenUnifiedVideoIds: Set<number> = new Set();
      for (const stream of result.streams) {
        if (stream.channelId !== 0 && !seenUnifiedVideoIds.has(stream.channelId)) {
          seenUnifiedVideoIds.add(stream.channelId);
          unifiedVideoIds.push(stream.channelId);
        }
      }
      if (result.isUnifiedBroadcast && unifiedVideoIds.length > 0) {
        this.unifiedSource = {
          endpointId: 'unified',
          participantKey: 'unified',
          name: this.state.title !== '' ? this.state.title : '直播主画面',
          audioSourceId: 0,
          sourceGroups: `SIM=${unifiedVideoIds.join(',')}`,
          isPaused: false,
          isScreenSharing: false,
          isSpeaking: true,
          isMuted: false
        };
      }
      this.onParticipants(this.participants);
      this.participantStore?.load(100).catch((error: Error): void => {
        console.error(`loadGroupCallParticipants: ${error.message}`);
      });
      this.applyVideoSources(this.videoSources);
      this.restoreSurfaceBindings();
      session.resumeMedia();
      this.restoreLocalVideo(session, result);
      if (!this.mediaConnected && !result.isBroadcast) {
        this.scheduleRecovery(MEDIA_RECONNECT_GRACE_MS, '加入后媒体连接超时');
      }
      this.refreshGroupCall('加入完成');
    }).catch((error: Error): void => {
      if (!this.pageActive || this.tgcallsSession !== session || sequence !== this.sessionSequence) { return; }
      session.stop();
      this.tgcallsSession = null;
      this.mediaStatus = '直播连接中断，正在重试…';
      this.state = {
        title: this.state.title,
        isActive: this.state.isActive,
        isRtmpStream: this.state.isRtmpStream,
        isJoined: false,
        needRejoin: this.state.needRejoin,
        canSendMessages: this.state.canSendMessages,
        areMessagesAllowed: this.state.areMessagesAllowed,
        participantCount: this.state.participantCount,
        streams: [],
        error: error.message
      };
      this.reconnectAttempt += 1;
      const delay = Math.min(30000, 1000 * Math.pow(2, Math.min(this.reconnectAttempt - 1, 5)));
      this.scheduleRecovery(delay, `加入失败：${error.message}`);
    }).finally((): void => {
      if (sequence === this.sessionSequence) { this.recoveryInFlight = false; }
    });
  }

  private onMediaNetworkState(session: TgcallsGroupSession, connected: boolean): void {
    if (!this.pageActive || this.tgcallsSession !== session) { return; }
    this.mediaConnected = connected;
    if (connected) {
      this.reconnectAttempt = 0;
      this.clearRecoveryTimer();
      this.mediaStatus = '直播音视频已连接';
      session.resumeMedia();
      this.restoreSurfaceBindings();
      return;
    }
    this.mediaStatus = '网络波动，正在恢复媒体连接…';
    this.scheduleRecovery(MEDIA_RECONNECT_GRACE_MS, '媒体连接超时');
  }

  private onRemoteAudioActivity(
    session: TgcallsGroupSession, client: TdClient,
    audioSourceId: number, speaking: boolean
  ): void {
    if (!this.pageActive || this.tgcallsSession !== session) { return; }
    console.info(`[LiveStreamViewer] audio activity source=${audioSourceId} speaking=${speaking}`);
    this.participantStore?.applyAudioActivity(audioSourceId, speaking);
    setGroupCallParticipantIsSpeaking(
      client, this.groupCallId, audioSourceId, speaking
    ).then((sender: TdObject): void => {
      if (!this.pageActive || this.tgcallsSession !== session) { return; }
      this.participantStore?.applyAudioActivity(audioSourceId, speaking, sender);
    }).catch((error: Error): void => {
      console.error(
        `[LiveStreamViewer] set speaking source=${audioSourceId} failed: ${error.message}`
      );
    });
  }

  private onLocalVideoState(
    session: TgcallsGroupSession, mode: number, active: boolean, error: number
  ): void {
    if (!this.pageActive || this.tgcallsSession !== session) { return; }
    console.info(
      `[LiveStreamViewer] local video mode=${mode} active=${active} error=${error}`
    );
    if (mode === 3) {
      if (active) {
        this.screenShareDesired = true;
        this.screenShareActive = true;
        this.screenShareBusy = false;
        this.mediaStatus = this.localVideoActive
          ? '摄像头与屏幕共享同时直播中'
          : '正在共享本机屏幕';
        return;
      }
      if (!this.screenShareDesired) { return; }
      this.screenShareActive = false;
      this.screenShareBusy = false;
      this.screenShareDesired = false;
      this.screenShareOperationSequence += 1;
      session.stopScreenSharing().catch((caught: Error): void => {
        console.error(`[LiveStreamViewer] screen-share cleanup failed: ${caught.message}`);
      });
      this.mediaStatus = error !== 0
        ? '录屏未开始，请在系统弹窗中允许共享'
        : (this.localVideoActive ? '屏幕共享已关闭，摄像头仍在直播' : '屏幕共享已关闭');
      return;
    }
    if (active) {
      // A replaced camera can report its final state after the new camera has
      // already been requested. Never let that stale callback steal the UI
      // selection from the current mode.
      if (this.desiredLocalVideoMode !== 0 && mode !== this.desiredLocalVideoMode) {
        return;
      }
      this.desiredLocalVideoMode = mode;
      this.localVideoMode = mode;
      this.localVideoActive = true;
      this.localVideoBusy = false;
      this.refreshPrimaryVideoAspect();
      this.mediaStatus = this.screenShareActive
        ? '摄像头与屏幕共享同时直播中'
        : (mode === 1 ? '前置摄像头直播中' : '后置摄像头直播中');
      return;
    }
    // Switching front/back stops the old capturer after the new one has been
    // installed. Ignore that stale stop callback.
    if (mode !== this.desiredLocalVideoMode) { return; }
    this.localVideoMode = 0;
    this.localVideoActive = false;
    this.localVideoBusy = false;
    this.desiredLocalVideoMode = 0;
    this.refreshPrimaryVideoAspect();
    this.localVideoOperationSequence += 1;
    session.stopCamera().catch((caught: Error): void => {
      console.error(`[LiveStreamViewer] camera cleanup failed: ${caught.message}`);
    });
    if (error !== 0) {
      this.mediaStatus = '摄像头启动失败，请检查权限或是否被占用';
    } else {
      this.mediaStatus = this.screenShareActive
        ? '摄像头已关闭，屏幕仍在共享'
        : '摄像头已关闭';
    }
  }

  private onVideoGeometry(
    session: TgcallsGroupSession, endpointId: string, width: number, height: number
  ): void {
    if (!this.pageActive || this.tgcallsSession !== session ||
      endpointId === '' || width <= 0 || height <= 0) {
      return;
    }
    const aspectRatio = width / height;
    this.videoAspectRatios.set(endpointId, aspectRatio);
    const primaryEndpoint = this.videoSources.length > 0
      ? this.videoSources[0].endpointId
      : (this.isLocalCameraActive() ? '__local_camera__' : '');
    if (endpointId !== primaryEndpoint) { return; }
    if (Math.abs(this.primaryVideoAspectRatio - aspectRatio) < 0.01) { return; }
    this.primaryVideoAspectRatio = aspectRatio;
    console.info(
      `[LiveStreamViewer] primary video geometry endpoint=${endpointId} ` +
      `${width}x${height} aspect=${aspectRatio}`
    );
    if (this.isFullscreen) {
      setLiveStreamFullscreen(
        getContext(this) as common.UIAbilityContext, true, this.primaryVideoAspectRatio
      );
    }
  }

  private refreshPrimaryVideoAspect(): void {
    const primaryEndpoint = this.videoSources.length > 0
      ? this.videoSources[0].endpointId
      : (this.isLocalCameraActive() ? '__local_camera__' : '');
    const aspectRatio = primaryEndpoint === ''
      ? 0
      : (this.videoAspectRatios.get(primaryEndpoint) ?? 0);
    if (Math.abs(this.primaryVideoAspectRatio - aspectRatio) < 0.01) { return; }
    this.primaryVideoAspectRatio = aspectRatio;
    if (this.isFullscreen) {
      setLiveStreamFullscreen(
        getContext(this) as common.UIAbilityContext, true, this.primaryVideoAspectRatio
      );
    }
  }

  private restoreLocalVideo(
    session: TgcallsGroupSession, result: TgcallsJoinResult
  ): void {
    const cameraMode = this.desiredLocalVideoMode;
    const restoreScreenShare = this.screenShareDesired;
    if (cameraMode === 0 && !restoreScreenShare) { return; }
    if (result.isBroadcast) {
      this.localVideoMode = 0;
      this.localVideoActive = false;
      this.localVideoBusy = false;
      this.desiredLocalVideoMode = 0;
      this.screenShareActive = false;
      this.screenShareBusy = false;
      this.screenShareDesired = false;
      this.mediaStatus = '单向 RTMP 直播需使用主播推流入口';
      return;
    }
    if (cameraMode === 1 || cameraMode === 2) {
      this.localVideoBusy = true;
      this.startCameraVideo(cameraMode);
    }
    if (restoreScreenShare) {
      this.screenShareBusy = true;
      this.startScreenShareVideo();
    }
  }

  private scheduleRecovery(delayMs: number, reason: string): void {
    if (!this.pageActive) { return; }
    const dueAt = Date.now() + Math.max(0, delayMs);
    if (this.reconnectTimer !== -1 && this.reconnectDueAt <= dueAt) { return; }
    this.clearRecoveryTimer();
    this.reconnectDueAt = dueAt;
    this.reconnectTimer = setTimeout((): void => {
      this.reconnectTimer = -1;
      this.reconnectDueAt = 0;
      this.replaceSession(reason);
    }, Math.max(0, delayMs));
  }

  private clearRecoveryTimer(): void {
    if (this.reconnectTimer !== -1) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = -1;
      this.reconnectDueAt = 0;
    }
  }

  private startHealthMonitor(): void {
    if (this.healthTimer !== -1) { return; }
    this.healthTimer = setInterval((): void => {
      this.refreshGroupCall('定时健康检查');
    }, MEDIA_HEALTH_INTERVAL_MS);
  }

  private async refreshGroupCall(reason: string): Promise<void> {
    if (!this.pageActive || this.groupCallId <= 0 || this.groupCallRefreshInFlight) { return; }
    this.groupCallRefreshInFlight = true;
    try {
      const groupCall = await getGroupCall(getTdClient(), this.groupCallId);
      if (!this.pageActive) { return; }
      const canBeManaged = (groupCall['can_be_managed'] as boolean | undefined) ?? false;
      const isOwned = (groupCall['is_owned'] as boolean | undefined) ?? false;
      this.canManageLive = canBeManaged || isOwned;
      this.selfParticipantId = (groupCall['message_sender_id'] as TdObject | undefined) ??
        this.selfParticipantId;
      const next: LiveStreamState = {
        title: (groupCall['title'] as string | undefined) ?? this.state.title,
        isActive: (groupCall['is_active'] as boolean | undefined) ?? this.state.isActive,
        isRtmpStream: (groupCall['is_rtmp_stream'] as boolean | undefined) ?? this.state.isRtmpStream,
        isJoined: (groupCall['is_joined'] as boolean | undefined) ?? this.state.isJoined,
        needRejoin: (groupCall['need_rejoin'] as boolean | undefined) ?? this.state.needRejoin,
        canSendMessages: (groupCall['can_send_messages'] as boolean | undefined) ??
          this.state.canSendMessages,
        areMessagesAllowed: (groupCall['are_messages_allowed'] as boolean | undefined) ??
          this.state.areMessagesAllowed,
        participantCount: (groupCall['participant_count'] as number | undefined) ??
          this.state.participantCount,
        streams: this.state.streams,
        error: this.state.error
      };
      if (this.store !== null) {
        this.store.applyGroupCall(groupCall);
      } else {
        this.onLiveState(next);
      }
      if (!next.isActive) { this.mediaStatus = '直播已结束'; }
      console.info(
        `[LiveStreamViewer] health reason=${reason} active=${next.isActive} ` +
        `joined=${next.isJoined} needRejoin=${next.needRejoin} media=${this.mediaConnected} ` +
        `admin=${this.canManageLive} canBeManaged=${canBeManaged} isOwned=${isOwned}`
      );
    } catch (caught) {
      const error = caught as Error;
      console.error(`[LiveStreamViewer] health check failed reason=${reason}: ${error.message}`);
    } finally {
      this.groupCallRefreshInFlight = false;
    }
  }

  private resumeAfterForeground(): void {
    liveStreamBackgroundTask.start(
      getContext(this) as common.UIAbilityContext, !this.isMuted
    );
    const session = this.tgcallsSession;
    if (session !== null) {
      session.resumeMedia();
      this.applyVideoSources(this.videoSources);
      this.restoreSurfaceBindings();
    }
    this.refreshGroupCall('回到前台');
    if (this.hasJoinedOnce && !this.mediaConnected) {
      this.scheduleRecovery(3000, '前台恢复后媒体未连接');
    }
  }

  private onParticipants(value: GroupCallParticipantInfo[]): void {
    this.participants = value;
    const current = value.find(
      (participant: GroupCallParticipantInfo): boolean => participant.isCurrentUser
    );
    if (current !== undefined) {
      this.selfParticipantId = this.participantSender(current);
    }
    if (current !== undefined && this.hasJoinedOnce && current.isMuted !== this.isMuted) {
      this.isMuted = current.isMuted;
      this.tgcallsSession?.setMuted(this.isMuted);
      liveStreamBackgroundTask.setRecording(!this.isMuted);
    }
    const sources: GroupCallVideoSource[] = [];
    if (this.unifiedSource !== null) { sources.push(this.unifiedSource); }
    for (const participant of value) {
      for (const source of participant.videoSources) {
        // Telegram advertises the current user's camera endpoint in the
        // participant list but does not loop that media back through the SFU.
        // Rendering it as an incoming channel therefore creates a black main
        // tile and pushes the real local preview into picture-in-picture.
        // Screen sharing is a separate presentation session and can still be
        // rendered through the normal incoming path.
        if (participant.isCurrentUser && !source.isScreenSharing) { continue; }
        sources.push(source);
      }
    }
    sources.sort((a: GroupCallVideoSource, b: GroupCallVideoSource): number => {
      if (a.isScreenSharing !== b.isScreenSharing) { return a.isScreenSharing ? -1 : 1; }
      if (a.isSpeaking !== b.isSpeaking) { return a.isSpeaking ? -1 : 1; }
      return a.endpointId.localeCompare(b.endpointId);
    });
    this.videoSources = sources;
    this.refreshPrimaryVideoAspect();
    this.applyVideoSources(sources);
  }

  private applyVideoSources(sources: GroupCallVideoSource[]): void {
    const next: Set<string> = new Set();
    for (const source of sources) {
      next.add(source.endpointId);
      this.tgcallsSession?.setVideoChannel(source.endpointId, source.audioSourceId, source.sourceGroups);
    }
    for (const old of this.requestedEndpoints) {
      if (!next.has(old)) { this.tgcallsSession?.removeVideoChannel(old); }
    }
    this.requestedEndpoints = next;
  }

  private setSurface(endpointId: string, surfaceId: string, surfaceWidth: number, surfaceHeight: number): void {
    this.surfaceBindings.set(endpointId, {
      surfaceId,
      width: surfaceWidth,
      height: surfaceHeight
    });
    this.tgcallsSession?.setVideoSurface(endpointId, surfaceId, surfaceWidth, surfaceHeight);
  }

  private clearSurface(endpointId: string, surfaceId: string): void {
    const current = this.surfaceBindings.get(endpointId);
    if (current !== undefined && current.surfaceId !== surfaceId) { return; }
    this.surfaceBindings.delete(endpointId);
    this.tgcallsSession?.setVideoSurface(endpointId, '0');
  }

  private isLocalCameraActive(): boolean {
    return this.localVideoActive;
  }

  private setLocalPreviewSurface(
    surfaceId: string, surfaceWidth: number, surfaceHeight: number
  ): void {
    this.localPreviewSurfaceId = surfaceId;
    this.tgcallsSession?.setLocalVideoSurface(surfaceId, surfaceWidth, surfaceHeight);
  }

  private clearLocalPreviewSurface(surfaceId: string): void {
    if (surfaceId !== this.localPreviewSurfaceId) { return; }
    this.localPreviewSurfaceId = '0';
    this.tgcallsSession?.setLocalVideoSurface('0');
  }

  private restoreSurfaceBindings(): void {
    const session = this.tgcallsSession;
    if (session === null) { return; }
    for (const entry of this.surfaceBindings.entries()) {
      const binding = entry[1];
      session.setVideoSurface(entry[0], binding.surfaceId, binding.width, binding.height);
    }
  }

  private async toggleMuted(): Promise<void> {
    this.animateMicrophoneTap();
    if (!this.isMuted) {
      if (this.tgcallsSession?.setMuted(true) ?? false) {
        this.isMuted = true;
        liveStreamBackgroundTask.setRecording(false);
        if (this.selfParticipantId !== null) {
          toggleGroupCallParticipantIsMuted(
            getTdClient(), this.groupCallId, this.selfParticipantId, true
          ).catch((error: Error): void => {
            console.error(`toggleGroupCallParticipantIsMuted(true): ${error.message}`);
          });
        }
      }
      return;
    }
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const manager = abilityAccessCtrl.createAtManager();
      const result = await manager.requestPermissionsFromUser(context, [MICROPHONE_PERMISSION]);
      const granted = result.authResults.length > 0 && result.authResults[0] === 0;
      if (!granted) {
        this.mediaStatus = '需要麦克风权限才能开麦';
        return;
      }
      if (this.selfParticipantId !== null) {
        await toggleGroupCallParticipantIsMuted(
          getTdClient(), this.groupCallId, this.selfParticipantId, false
        );
      }
      if (this.tgcallsSession?.setMuted(false) ?? false) {
        this.isMuted = false;
        liveStreamBackgroundTask.setRecording(true);
      } else {
        this.mediaStatus = '麦克风启动失败';
      }
    } catch (error) {
      this.mediaStatus = `麦克风不可用：${error}`;
    }
  }

  private captureSize(mode: number): number[] {
    if (mode !== 3) { return [1280, 720]; }
    try {
      const screen = display.getDefaultDisplaySync();
      const rawWidth = Math.max(2, screen.width);
      const rawHeight = Math.max(2, screen.height);
      const scale = Math.min(1, 1280 / Math.max(rawWidth, rawHeight));
      const width = Math.max(2, Math.round(rawWidth * scale / 2) * 2);
      const height = Math.max(2, Math.round(rawHeight * scale / 2) * 2);
      return [width, height];
    } catch (_) {
      return [720, 1280];
    }
  }

  private async stopCameraVideo(): Promise<void> {
    this.localVideoOperationSequence += 1;
    const session = this.tgcallsSession;
    this.desiredLocalVideoMode = 0;
    this.localVideoMode = 0;
    this.localVideoActive = false;
    this.localVideoBusy = session !== null;
    try {
      const stopped = session !== null && await session.stopCamera();
      if (!stopped) {
        this.mediaStatus = '摄像头关闭失败';
        return;
      }
      this.mediaStatus = this.screenShareActive
        ? '摄像头已关闭，屏幕仍在共享'
        : '摄像头已关闭';
    } catch (caught) {
      this.mediaStatus = `摄像头关闭失败：${caught}`;
    } finally {
      this.localVideoBusy = false;
    }
  }

  private async stopScreenShareVideo(): Promise<void> {
    this.screenShareOperationSequence += 1;
    const session = this.tgcallsSession;
    this.screenShareDesired = false;
    this.screenShareActive = false;
    this.screenShareBusy = session !== null;
    try {
      const stopped = session !== null && await session.stopScreenSharing();
      if (!stopped) {
        this.mediaStatus = '屏幕共享关闭失败';
        return;
      }
      this.mediaStatus = this.localVideoActive
        ? '屏幕共享已关闭，摄像头仍在直播'
        : '屏幕共享已关闭';
    } catch (caught) {
      this.mediaStatus = `屏幕共享关闭失败：${caught}`;
    } finally {
      this.screenShareBusy = false;
    }
  }

  private async toggleCamera(): Promise<void> {
    if (this.localVideoActive ||
      this.desiredLocalVideoMode === 1 || this.desiredLocalVideoMode === 2) {
      await this.stopCameraVideo();
      return;
    }
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const manager = abilityAccessCtrl.createAtManager();
      const result = await manager.requestPermissionsFromUser(
        context, [CAMERA_PERMISSION]
      );
      const granted = result.authResults.length > 0 && result.authResults[0] === 0;
      if (!granted) {
        this.mediaStatus = '需要摄像头权限才能开启视频';
        return;
      }
      await this.startCameraVideo(1);
    } catch (caught) {
      this.mediaStatus = `摄像头不可用：${caught}`;
    }
  }

  private async switchCamera(): Promise<void> {
    if (this.desiredLocalVideoMode !== 1 && this.desiredLocalVideoMode !== 2) {
      this.mediaStatus = '请先开启摄像头';
      return;
    }
    await this.startCameraVideo(this.desiredLocalVideoMode === 1 ? 2 : 1);
  }

  private async toggleScreenShare(): Promise<void> {
    if (this.screenShareActive || this.screenShareDesired) {
      await this.stopScreenShareVideo();
      return;
    }
    await this.startScreenShareVideo();
  }

  private async startCameraVideo(mode: number): Promise<void> {
    const session = this.tgcallsSession;
    if (session === null || !this.hasJoinedOnce || (mode !== 1 && mode !== 2)) {
      this.mediaStatus = '请等待直播连接完成';
      return;
    }
    const size = this.captureSize(mode);
    const operationSequence = ++this.localVideoOperationSequence;
    this.desiredLocalVideoMode = mode;
    this.localVideoMode = mode;
    this.localVideoActive = false;
    this.localVideoBusy = true;
    this.mediaStatus = '正在启动摄像头…';
    setTimeout((): void => {
      if (!this.pageActive || this.tgcallsSession !== session ||
        operationSequence !== this.localVideoOperationSequence ||
        !this.localVideoBusy || this.desiredLocalVideoMode !== mode) {
        return;
      }
      this.localVideoOperationSequence += 1;
      this.desiredLocalVideoMode = 0;
      this.localVideoMode = 0;
      this.localVideoActive = false;
      this.localVideoBusy = false;
      this.mediaStatus = '摄像头首帧等待超时，请重试';
      session.stopCamera().catch((caught: Error): void => {
        console.error(`[LiveStreamViewer] timed-out camera cleanup failed: ${caught.message}`);
      });
    }, LOCAL_VIDEO_START_TIMEOUT_MS);
    try {
      const started = await session.startCamera(mode, size[0], size[1]);
      if (operationSequence !== this.localVideoOperationSequence) { return; }
      if (started) { return; }
      this.desiredLocalVideoMode = 0;
      this.localVideoMode = 0;
      this.localVideoBusy = false;
      this.mediaStatus = '当前直播模式不支持本机推流';
    } catch (caught) {
      if (operationSequence !== this.localVideoOperationSequence) { return; }
      this.desiredLocalVideoMode = 0;
      this.localVideoMode = 0;
      this.localVideoActive = false;
      this.localVideoBusy = false;
      this.mediaStatus = `摄像头推流启动失败：${caught}`;
    }
  }

  private async startScreenShareVideo(): Promise<void> {
    const session = this.tgcallsSession;
    if (session === null || !this.hasJoinedOnce) {
      this.mediaStatus = '请等待直播连接完成';
      return;
    }
    const size = this.captureSize(3);
    const operationSequence = ++this.screenShareOperationSequence;
    this.screenShareDesired = true;
    this.screenShareActive = false;
    this.screenShareBusy = true;
    this.mediaStatus = '正在请求录屏授权…';
    setTimeout((): void => {
      if (!this.pageActive || this.tgcallsSession !== session ||
        operationSequence !== this.screenShareOperationSequence ||
        !this.screenShareBusy || !this.screenShareDesired) {
        return;
      }
      this.screenShareOperationSequence += 1;
      this.screenShareDesired = false;
      this.screenShareActive = false;
      this.screenShareBusy = false;
      this.mediaStatus = '录屏授权或首帧等待超时，请重试';
      session.stopScreenSharing().catch((caught: Error): void => {
        console.error(`[LiveStreamViewer] timed-out screen-share cleanup failed: ${caught.message}`);
      });
    }, LOCAL_VIDEO_START_TIMEOUT_MS);
    try {
      const started = await session.startScreenSharing(size[0], size[1]);
      if (operationSequence !== this.screenShareOperationSequence) { return; }
      if (started) { return; }
      this.screenShareDesired = false;
      this.screenShareActive = false;
      this.screenShareBusy = false;
      this.mediaStatus = '当前直播模式不支持屏幕共享';
    } catch (caught) {
      if (operationSequence !== this.screenShareOperationSequence) { return; }
      this.screenShareDesired = false;
      this.screenShareActive = false;
      this.screenShareBusy = false;
      this.mediaStatus = `录屏共享启动失败：${caught}`;
    }
  }

  private participantSender(participant: GroupCallParticipantInfo): TdObject | null {
    if (participant.senderId === 0) { return null; }
    if (participant.senderType === 'messageSenderUser') {
      const sender: TdObject = { '@type': 'messageSenderUser' };
      sender['user_id'] = participant.senderId;
      return sender;
    }
    if (participant.senderType === 'messageSenderChat') {
      const sender: TdObject = { '@type': 'messageSenderChat' };
      sender['chat_id'] = participant.senderId;
      return sender;
    }
    return null;
  }

  private toggleParticipantMuted(participant: GroupCallParticipantInfo): void {
    if (!this.canManageLive || participant.isCurrentUser) { return; }
    const sender = this.participantSender(participant);
    if (sender === null) { return; }
    const nextMuted = !participant.isMuted;
    toggleGroupCallParticipantIsMuted(
      getTdClient(), this.groupCallId, sender, nextMuted
    ).then((): void => {
      this.mediaStatus = nextMuted
        ? `已将 ${participant.name} 静音`
        : `已允许 ${participant.name} 发言`;
    }).catch((error: Error): void => {
      this.mediaStatus = `成员麦克风管理失败：${error.message}`;
    });
  }

  private leave(): void {
    if (this.canManageLive) {
      confirmAdminLeaveLiveStream(
        (): void => this.leaveNow(),
        (): void => this.endLiveForEveryone()
      );
      return;
    }
    confirmLeaveLiveStream((): void => this.leaveNow());
  }

  private endLiveForEveryone(): void {
    if (this.endingLive || this.groupCallId <= 0) { return; }
    this.endingLive = true;
    this.mediaStatus = '正在结束直播…';
    endGroupCall(getTdClient(), this.groupCallId).then((): void => {
      this.mediaStatus = '直播已结束';
      this.leaveNow();
    }).catch((error: Error): void => {
      this.endingLive = false;
      this.mediaStatus = `结束直播失败：${error.message}`;
    });
  }

  private leaveNow(): void {
    if (this.isFullscreen) {
      setLiveStreamFullscreen(getContext(this) as common.UIAbilityContext, false);
    }
    router.back();
  }

  private minimizeToFloating(): void {
    if (this.minimizeInProgress || this.groupCallId <= 0) { return; }
    this.minimizeInProgress = true;
    const descriptor: FloatingLiveDescriptor = {
      groupCallId: this.groupCallId,
      chatId: this.chatId,
      isRtmp: false,
      title: this.state.title,
      participantCount: this.state.participantCount,
      primarySource: this.videoSources.length > 0 ? this.videoSources[0] : null
    };
    const abilityContext = getContext(this) as common.UIAbilityContext;
    const uiContext = this.getUIContext();
    this.pageActive = false;
    this.sessionSequence += 1;
    this.clearRecoveryTimer();
    if (this.tgcallsSession !== null) {
      this.tgcallsSession.clearVideo();
      this.tgcallsSession.stop();
      this.tgcallsSession = null;
    }
    if (this.isFullscreen) {
      this.isFullscreen = false;
      this.fullscreenPanelOpen = false;
      setLiveStreamFullscreen(abilityContext, false);
    }
    leaveGroupCall(getTdClient(), this.groupCallId).catch((caught: Error): void => {
      console.error(`LiveStreamViewerPage.minimize leave failed: ${caught.message}`);
    }).finally((): void => {
      this.leavingForFloating = true;
      floatingLiveWindow.show(uiContext, abilityContext, descriptor);
      router.back();
    });
  }

  private toggleFullscreen(): void {
    const next = !this.isFullscreen;
    this.fullscreenPanelOpen = false;
    this.isFullscreen = next;
    setLiveStreamFullscreen(
      getContext(this) as common.UIAbilityContext, next,
      next ? this.primaryVideoAspectRatio : 0
    );
  }

  onBackPress(): boolean {
    if (this.fullscreenPanelOpen) {
      this.fullscreenPanelOpen = false;
      return true;
    }
    if (this.isFullscreen) {
      this.toggleFullscreen();
      return true;
    }
    this.leave();
    return true;
  }

  private cyclePrimaryVideo(): void {
    if (this.videoSources.length < 2) {
      this.mediaStatus = '当前只有一路画面';
      return;
    }
    const sequence = ++this.videoSwitchSequence;
    animateTo({
      duration: powerAnimationDuration(KEY_POWER_CALL_ANIMATIONS, 110), curve: Curve.EaseOut
    }, (): void => {
      this.videoAreaOpacity = 0.54;
      this.videoAreaScale = 0.985;
    });
    setTimeout((): void => {
      if (sequence !== this.videoSwitchSequence) { return; }
      this.videoSources = [...this.videoSources.slice(1), this.videoSources[0]];
      animateTo({
        duration: powerAnimationDuration(KEY_POWER_CALL_ANIMATIONS, 210), curve: Curve.FastOutSlowIn
      }, (): void => {
        this.videoAreaOpacity = 1;
        this.videoAreaScale = 1;
      });
    }, 115);
  }

  private startPulseAnimation(): void {
    if (this.pulseTimer !== -1) { return; }
    this.pulseTimer = setInterval((): void => {
      if (!powerFeatureEnabled(KEY_POWER_CALL_ANIMATIONS)) {
        this.pulseExpanded = false;
        this.microphoneScale = 1;
        return;
      }
      const hasSpeaker = this.participants.some(
        (participant: GroupCallParticipantInfo): boolean => participant.isSpeaking
      );
      if (this.isMuted && !hasSpeaker) {
        if (this.pulseExpanded) {
          animateTo({
            duration: powerAnimationDuration(KEY_POWER_CALL_ANIMATIONS, 260), curve: Curve.EaseOut
          }, (): void => {
            this.pulseExpanded = false;
          });
        }
        return;
      }
      animateTo({
        duration: powerAnimationDuration(KEY_POWER_CALL_ANIMATIONS, 680), curve: Curve.EaseInOut
      }, (): void => {
        this.pulseExpanded = !this.pulseExpanded;
      });
    }, 720);
  }

  private animateMicrophoneTap(): void {
    animateTo({
      duration: powerAnimationDuration(KEY_POWER_CALL_ANIMATIONS, 85), curve: Curve.EaseOut
    }, (): void => {
      this.microphoneScale = 0.91;
    });
    setTimeout((): void => {
      animateTo({
        duration: powerAnimationDuration(KEY_POWER_CALL_ANIMATIONS, 240), curve: Curve.Friction
      }, (): void => {
        this.microphoneScale = 1;
      });
    }, 90);
  }

  aboutToDisappear(): void {
    if (this.isFullscreen) {
      setLiveStreamFullscreen(getContext(this) as common.UIAbilityContext, false);
    }
    this.pageActive = false;
    this.sessionSequence += 1;
    this.recoveryInFlight = false;
    this.clearRecoveryTimer();
    if (this.healthTimer !== -1) { clearInterval(this.healthTimer); this.healthTimer = -1; }
    if (!this.leavingForFloating) { liveStreamBackgroundTask.stop(); }
    if (this.pulseTimer !== -1) { clearInterval(this.pulseTimer); this.pulseTimer = -1; }
    this.videoSwitchSequence += 1;
    if (this.offParticipants !== null) { this.offParticipants(); this.offParticipants = null; }
    if (this.participantStore !== null) { this.participantStore.dispose(); this.participantStore = null; }
    if (this.tgcallsSession !== null) {
      this.tgcallsSession.clearVideo();
      this.tgcallsSession.stop();
      this.tgcallsSession = null;
    }
    this.requestedEndpoints.clear();
    this.surfaceBindings.clear();
    this.localPreviewSurfaceId = '0';
    this.unifiedSource = null;
    this.selfParticipantId = null;
    if (this.off !== null) { this.off(); this.off = null; }
    if (this.store !== null) { this.store.dispose(); this.store = null; }
    if (this.groupCallId > 0 && !this.leavingForFloating) {
      leaveGroupCall(getTdClient(), this.groupCallId).catch((error: Error): void => {
        console.error(`LiveStreamViewerPage.leaveGroupCall failed: ${error.message}`);
      });
    }
  }

  @Builder
  header() {
    Row({ space: 14 }) {
      SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(26).fontColor([CALL_TEXT])
        .onClick((): void => this.leave());
      Column() {
        Text(this.state.title !== '' ? this.state.title : '直播')
          .fontSize(17).fontWeight(FontWeight.Bold).fontColor(CALL_TEXT)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
        Row({ space: 6 }) {
          Circle({ width: 6, height: 6 }).fill(CALL_GREEN)
            .opacity(this.pulseExpanded ? 1 : 0.48)
            .scale({ x: this.pulseExpanded ? 1.16 : 0.86, y: this.pulseExpanded ? 1.16 : 0.86 });
          Text(`${this.state.participantCount} 位参与者`)
            .fontSize(12).fontColor(CALL_SUBTEXT);
          if (this.canManageLive) {
            Text('管理员')
              .fontSize(10).fontWeight(FontWeight.Medium).fontColor(CALL_GREEN)
              .padding({ left: 7, right: 7, top: 2, bottom: 2 })
              .backgroundColor('#2639D98A').borderRadius(8);
          }
        }
        .margin({ top: 2 });
      }
      .layoutWeight(1).alignItems(HorizontalAlign.Start);
      Button({ type: ButtonType.Circle }) {
        SymbolGlyph($r('sys.symbol.plus_square_on_square')).fontSize(19).fontColor([CALL_TEXT]);
      }
      .width(38).height(38).backgroundColor('#26323C')
      .enabled(!this.minimizeInProgress)
      .onClick((): void => this.minimizeToFloating());
      SymbolGlyph($r('sys.symbol.more')).fontSize(23).fontColor([CALL_TEXT]);
    }
    .width('100%').height(56).padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center).backgroundColor(CALL_BACKGROUND);
  }

  @Builder
  videoArea() {
    if (this.videoSources.length === 0 && !this.isLocalCameraActive()) {
      Column() {
        SymbolGlyph($r('sys.symbol.camera')).fontSize(38).fontColor([CALL_SUBTEXT]);
        Text(this.mediaStatus).fontSize(13).fontColor(CALL_SUBTEXT).margin({ top: 10 });
      }
      .width('100%').height(210).justifyContent(FlexAlign.Center)
      .backgroundColor(Color.Black).borderRadius(8);
    } else if (this.videoSources.length === 0) {
      LocalVideoPreviewTile({
        mode: this.localVideoMode,
        tileWidth: '100%',
        tileHeight: '190vp',
        showFullscreenButton: true,
        fullscreen: false,
        onSurfaceReady: (
          surfaceId: string, surfaceWidth: number, surfaceHeight: number
        ): void => this.setLocalPreviewSurface(surfaceId, surfaceWidth, surfaceHeight),
        onSurfaceGone: (surfaceId: string): void =>
          this.clearLocalPreviewSurface(surfaceId),
        onFullscreenToggle: (): void => this.toggleFullscreen()
      });
    } else if (this.videoSources.length === 1 && this.isLocalCameraActive()) {
      // Camera + screen share are two independent Telegram video endpoints.
      // Present them like two speakers instead of hiding the camera in PiP.
      Row({ space: 3 }) {
        Column() {
          LiveVideoTile({
            source: this.videoSources[0],
            tileHeight: 190,
            showFullscreenButton: true,
            fullscreen: false,
            pulseExpanded: this.pulseExpanded,
            onSurfaceReady: (
              endpointId: string, surfaceId: string, surfaceWidth: number, surfaceHeight: number
            ): void => this.setSurface(endpointId, surfaceId, surfaceWidth, surfaceHeight),
            onSurfaceGone: (endpointId: string, surfaceId: string): void =>
              this.clearSurface(endpointId, surfaceId),
            onFullscreenToggle: (): void => this.toggleFullscreen()
          });
        }
        .layoutWeight(1).height(190);
        Column() {
          LocalVideoPreviewTile({
            mode: this.localVideoMode,
            tileWidth: '100%',
            tileHeight: '190vp',
            onSurfaceReady: (
              surfaceId: string, surfaceWidth: number, surfaceHeight: number
            ): void => this.setLocalPreviewSurface(surfaceId, surfaceWidth, surfaceHeight),
            onSurfaceGone: (surfaceId: string): void =>
              this.clearLocalPreviewSurface(surfaceId)
          });
        }
        .layoutWeight(1).height(190);
      }
      .width('100%').height(190);
    } else {
      LiveVideoTile({
        source: this.videoSources[0],
        tileHeight: 190,
        showFullscreenButton: true,
        fullscreen: false,
        pulseExpanded: this.pulseExpanded,
        onSurfaceReady: (
          endpointId: string, surfaceId: string, surfaceWidth: number, surfaceHeight: number
        ): void => this.setSurface(endpointId, surfaceId, surfaceWidth, surfaceHeight),
        onSurfaceGone: (endpointId: string, surfaceId: string): void =>
          this.clearSurface(endpointId, surfaceId),
        onFullscreenToggle: (): void => this.toggleFullscreen()
      });
      if (this.videoSources.length > 1 || this.isLocalCameraActive()) {
        Grid() {
          ForEach(
            this.videoSources.slice(1, this.isLocalCameraActive() ? 6 : 7),
            (source: GroupCallVideoSource) => {
              GridItem() {
                LiveVideoTile({
                  source,
                  tileHeight: 132,
                  pulseExpanded: this.pulseExpanded,
                  onSurfaceReady: (
                    endpointId: string, surfaceId: string,
                    surfaceWidth: number, surfaceHeight: number
                  ): void => this.setSurface(
                    endpointId, surfaceId, surfaceWidth, surfaceHeight
                  ),
                  onSurfaceGone: (endpointId: string, surfaceId: string): void =>
                    this.clearSurface(endpointId, surfaceId)
                });
              }
            },
            (source: GroupCallVideoSource): string => source.endpointId
          )
          if (this.isLocalCameraActive()) {
            GridItem() {
              LocalVideoPreviewTile({
                mode: this.localVideoMode,
                tileWidth: '100%',
                tileHeight: '132vp',
                onSurfaceReady: (
                  surfaceId: string, surfaceWidth: number, surfaceHeight: number
                ): void => this.setLocalPreviewSurface(
                  surfaceId, surfaceWidth, surfaceHeight
                ),
                onSurfaceGone: (surfaceId: string): void =>
                  this.clearLocalPreviewSurface(surfaceId)
              });
            }
          }
        }
        .columnsTemplate('1fr 1fr').columnsGap(3).rowsGap(3)
        .height(Math.ceil((
          Math.min(this.videoSources.length, this.isLocalCameraActive() ? 6 : 7) - 1 +
          (this.isLocalCameraActive() ? 1 : 0)
        ) / 2) * 135)
        .width('100%').margin({ top: 3 });
      }
    }
  }

  @Builder
  participantRow(participant: GroupCallParticipantInfo) {
    Row({ space: 12 }) {
      Stack() {
        if (participant.isSpeaking) {
          Circle({ width: 50, height: 50 }).fill('#4439D98A')
            .opacity(this.pulseExpanded ? 0.28 : 0.72)
            .scale({ x: this.pulseExpanded ? 1.08 : 0.92, y: this.pulseExpanded ? 1.08 : 0.92 });
        }
        Circle({ width: 42, height: 42 })
          .fill(AVATAR_COLORS[Math.abs(participant.colorSeed) % AVATAR_COLORS.length]);
        Text(participant.initials).fontSize(16).fontWeight(FontWeight.Medium).fontColor(Color.White);
      }
      .width(42).height(42);
      Column() {
        Text(participant.isCurrentUser ? `${participant.name}（你）` : participant.name)
          .fontSize(15).fontWeight(FontWeight.Medium).fontColor(CALL_TEXT)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
        Text(participant.isSpeaking ? '正在发言' :
          (participant.isMuted
            ? (this.canManageLive && !participant.isCurrentUser
              ? '麦克风已关闭 · 点击允许发言' : '麦克风已关闭')
            : (this.canManageLive && !participant.isCurrentUser
              ? '可以发言 · 点击可静音' : '正在收听')))
          .fontSize(12).fontColor(participant.isSpeaking ? CALL_GREEN : CALL_SUBTEXT).margin({ top: 3 });
      }
      .layoutWeight(1).alignItems(HorizontalAlign.Start);
      Stack({ alignContent: Alignment.Center }) {
        if (participant.isSpeaking) {
          Circle({ width: 34, height: 34 }).fill('#4939D98A')
            .opacity(this.pulseExpanded ? 0.35 : 0.78)
            .scale({ x: this.pulseExpanded ? 1.08 : 0.9, y: this.pulseExpanded ? 1.08 : 0.9 });
        }
        SymbolGlyph($r('sys.symbol.mic'))
          .fontSize(participant.isSpeaking && this.pulseExpanded ? 22 : 20)
          .fontColor([participant.isSpeaking ? CALL_GREEN :
            (participant.isMuted ? '#53616C' : CALL_SUBTEXT)]);
        if (participant.isMuted && !participant.isSpeaking) {
          Text('╱').fontSize(24).fontColor('#697782').fontWeight(FontWeight.Bold);
        }
      }
      .width(36).height(36)
      .backgroundColor(
        this.canManageLive && !participant.isCurrentUser ? '#26323C' : Color.Transparent
      )
      .borderRadius(18)
      .onClick((): void => this.toggleParticipantMuted(participant));
    }
    .width('100%').height(62).padding({ left: 12, right: 12 })
    .backgroundColor(participant.isSpeaking ? '#192A2B' : CALL_PANEL)
    .animation({
      duration: powerAnimationDuration(KEY_POWER_CALL_ANIMATIONS, 220), curve: Curve.EaseOut
    });
  }

  @Builder
  roundButton(symbol: Resource, color: string, onTap: () => void) {
    Button({ type: ButtonType.Circle }) {
      SymbolGlyph(symbol).fontSize(24).fontColor([Color.White]);
    }
    .width(52).height(52).backgroundColor(color).onClick(onTap);
  }

  @Builder
  localMediaButton(
    symbol: Resource, label: string, active: boolean,
    inactiveColor: string, onTap: () => void
  ) {
    Column({ space: 4 }) {
      Button({ type: ButtonType.Circle }) {
        SymbolGlyph(symbol).fontSize(21)
          .fontColor([active ? CALL_BACKGROUND : Color.White]);
      }
      .width(46).height(46)
      .backgroundColor(active ? CALL_GREEN : inactiveColor)
      .border({ width: active ? 2 : 0, color: '#BFFFFFFF' })
      .shadow({
        radius: active ? 12 : 0,
        color: active ? '#8039D98A' : Color.Transparent,
        offsetX: 0,
        offsetY: 0
      })
      .onClick(onTap);
      Text(label).fontSize(10).fontColor(active ? CALL_GREEN : CALL_SUBTEXT);
    }
    .width(52).alignItems(HorizontalAlign.Center);
  }

  @Builder
  cameraMediaButton() {
    Column({ space: 4 }) {
      Button({ type: ButtonType.Circle }) {
        SymbolGlyph($r('sys.symbol.camera')).fontSize(21)
          .fontColor([this.localVideoActive ? CALL_BACKGROUND : Color.White]);
      }
      .width(46).height(46)
      .backgroundColor(
        this.localVideoActive ? CALL_GREEN :
          (this.localVideoBusy ? '#3D6256' : '#34424D')
      )
      .border({ width: this.localVideoActive ? 2 : 0, color: '#BFFFFFFF' })
      .shadow({
        radius: this.localVideoActive ? 12 : 0,
        color: this.localVideoActive ? '#8039D98A' : Color.Transparent,
        offsetX: 0,
        offsetY: 0
      })
      .enabled(!this.localVideoBusy)
      .onClick((): void => { this.toggleCamera(); });
      Text(this.localVideoBusy ? '处理中' : '摄像头')
        .fontSize(10)
        .fontColor(this.localVideoActive ? CALL_GREEN :
          (this.localVideoBusy ? '#91B7AA' : CALL_SUBTEXT));
    }
    .width(52).alignItems(HorizontalAlign.Center)
    .animation({
      duration: powerAnimationDuration(KEY_POWER_CALL_ANIMATIONS, 180), curve: Curve.EaseOut
    });
  }

  @Builder
  screenShareMediaButton() {
    Column({ space: 4 }) {
      Button({ type: ButtonType.Circle }) {
        SymbolGlyph($r('sys.symbol.computer')).fontSize(21)
          .fontColor([this.screenShareActive ? CALL_BACKGROUND : Color.White]);
      }
      .width(46).height(46)
      .backgroundColor(
        this.screenShareActive ? CALL_GREEN :
          (this.screenShareBusy ? '#3D6256' : '#34424D')
      )
      .border({ width: this.screenShareActive ? 2 : 0, color: '#BFFFFFFF' })
      .shadow({
        radius: this.screenShareActive ? 12 : 0,
        color: this.screenShareActive ? '#8039D98A' : Color.Transparent,
        offsetX: 0,
        offsetY: 0
      })
      .enabled(!this.screenShareBusy)
      .onClick((): void => { this.toggleScreenShare(); });
      Text(this.screenShareBusy ? '处理中' : '共享屏幕')
        .fontSize(10)
        .fontColor(this.screenShareActive ? CALL_GREEN :
          (this.screenShareBusy ? '#91B7AA' : CALL_SUBTEXT));
    }
    .width(52).alignItems(HorizontalAlign.Center)
    .animation({
      duration: powerAnimationDuration(KEY_POWER_CALL_ANIMATIONS, 180), curve: Curve.EaseOut
    });
  }

  @Builder
  switchCameraButton() {
    Column({ space: 4 }) {
      Button({ type: ButtonType.Circle }) {
        Text('↻').fontSize(24).fontWeight(FontWeight.Bold).fontColor(Color.White);
      }
      .width(46).height(46)
      .backgroundColor(
        this.desiredLocalVideoMode === 1 || this.desiredLocalVideoMode === 2
          ? '#465661' : '#26323C'
      )
      .enabled(
        !this.localVideoBusy &&
        (this.desiredLocalVideoMode === 1 || this.desiredLocalVideoMode === 2)
      )
      .onClick((): void => { this.switchCamera(); });
      Text(this.desiredLocalVideoMode === 2 ? '切前置' : '切后置')
        .fontSize(10).fontColor(CALL_SUBTEXT);
    }
    .width(52).alignItems(HorizontalAlign.Center);
  }

  @Builder
  controls() {
    Column() {
      Row() {
        this.cameraMediaButton();
        this.screenShareMediaButton();
        Stack({ alignContent: Alignment.Center }) {
          if (!this.isMuted) {
            Circle({ width: 96, height: 96 }).fill('#2639D98A')
              .scale({ x: this.pulseExpanded ? 1.08 : 0.86, y: this.pulseExpanded ? 1.08 : 0.86 })
              .opacity(this.pulseExpanded ? 0.12 : 0.42);
            Circle({ width: 84, height: 84 }).fill('#3439D98A')
              .scale({ x: this.pulseExpanded ? 1.03 : 0.91, y: this.pulseExpanded ? 1.03 : 0.91 })
              .opacity(this.pulseExpanded ? 0.22 : 0.52);
          } else {
            Circle({ width: 82, height: 82 }).fill('#263E38');
          }
          Circle({ width: 68, height: 68 }).fill(this.isMuted ? '#2C6652' : CALL_GREEN);
          SymbolGlyph($r('sys.symbol.mic')).fontSize(this.pulseExpanded && !this.isMuted ? 34 : 31)
            .fontColor([Color.White]);
          if (this.isMuted) {
            Text('╱').fontSize(35).fontWeight(FontWeight.Bold).fontColor(Color.White);
          }
        }
        .width(98).height(104)
        .scale({ x: this.microphoneScale, y: this.microphoneScale })
        .onClick((): void => { this.toggleMuted(); });
        this.switchCameraButton();
        this.localMediaButton(
          $r('sys.symbol.phone_fill'), this.canManageLive ? '管理' : '退出', false, CALL_RED,
          (): void => this.leave()
        );
      }
      .width('100%').justifyContent(FlexAlign.SpaceAround).alignItems(VerticalAlign.Center);
      Text(this.localVideoBusy && this.screenShareBusy ? '正在启动摄像头和屏幕共享…' :
        (this.localVideoBusy ? '正在启动摄像头…' :
          (this.screenShareBusy ? '正在启动屏幕共享…' :
            (this.localVideoActive && this.screenShareActive
              ? '摄像头和屏幕共享同时直播中'
              : (this.screenShareActive ? '正在共享本机屏幕' :
                (this.localVideoActive ? '摄像头直播中，可随时切换前后镜头' :
                  (this.isMuted ? '点击麦克风开始说话' : '麦克风已开启，你正在发言')))))))
        .fontSize(13).fontWeight(FontWeight.Medium)
        .fontColor((!this.isMuted || this.localVideoActive || this.screenShareActive)
          ? CALL_GREEN : CALL_TEXT)
        .margin({ top: 1 }).maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis });
    }
    .width('100%').height(138).padding({ left: 6, right: 6, top: 1, bottom: 5 })
    .backgroundColor(CALL_BACKGROUND);
  }

  @Builder
  fullscreenParticipantDrawer() {
    Row() {
      Blank()
        .layoutWeight(1)
        .height('100%')
        .backgroundColor('#66000000')
        .onClick((): void => { this.fullscreenPanelOpen = false; });
      Column() {
        Row({ space: 10 }) {
          Column({ space: 2 }) {
            Text('语音成员').fontSize(17).fontWeight(FontWeight.Bold).fontColor(CALL_TEXT);
            Text(`${this.participants.length} 人 · 发言状态实时更新`)
              .fontSize(11).fontColor(CALL_SUBTEXT);
          }.alignItems(HorizontalAlign.Start).layoutWeight(1);
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.xmark')).fontSize(18).fontColor([CALL_TEXT]);
          }
          .width(36).height(36).backgroundColor('#263641')
          .onClick((): void => { this.fullscreenPanelOpen = false; });
        }
        .width('100%').height(58).padding({ left: 14, right: 12 });
        Scroll() {
          Column({ space: 1 }) {
            ForEach(this.participants, (participant: GroupCallParticipantInfo) => {
              this.participantRow(participant);
            }, (participant: GroupCallParticipantInfo): string =>
              `fullscreen:${participant.key}:${participant.revision}`)
          }.width('100%');
        }
        .width('100%').layoutWeight(1).scrollBar(BarState.Off);
      }
      .width('82%').height('100%').constraintSize({ maxWidth: 430 })
      .backgroundColor('#F2131D25')
      .shadow({ radius: 24, color: '#80000000', offsetX: -8, offsetY: 0 });
    }
    .width('100%').height('100%');
  }

  @Builder
  fullscreenVideo() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.videoSources.length > 0 && this.isLocalCameraActive()) {
        Flex({
          direction: this.primaryVideoAspectRatio > 1.08
            ? FlexDirection.Row : FlexDirection.Column
        }) {
          Column() {
            LiveVideoTile({
              source: this.videoSources[0],
              fillParent: true,
              pulseExpanded: this.pulseExpanded,
              onSurfaceReady: (
                endpointId: string, surfaceId: string,
                surfaceWidth: number, surfaceHeight: number
              ): void => this.setSurface(
                endpointId, surfaceId, surfaceWidth, surfaceHeight
              ),
              onSurfaceGone: (endpointId: string, surfaceId: string): void =>
                this.clearSurface(endpointId, surfaceId)
            });
          }
          .layoutWeight(1)
          .margin({
            right: this.primaryVideoAspectRatio > 1.08 ? 1.5 : 0,
            bottom: this.primaryVideoAspectRatio > 1.08 ? 0 : 1.5
          });
          Column() {
            LocalVideoPreviewTile({
              mode: this.localVideoMode,
              tileWidth: '100%',
              tileHeight: '100%',
              onSurfaceReady: (
                surfaceId: string, surfaceWidth: number, surfaceHeight: number
              ): void => this.setLocalPreviewSurface(
                surfaceId, surfaceWidth, surfaceHeight
              ),
              onSurfaceGone: (surfaceId: string): void =>
                this.clearLocalPreviewSurface(surfaceId)
            });
          }
          .layoutWeight(1)
          .margin({
            left: this.primaryVideoAspectRatio > 1.08 ? 1.5 : 0,
            top: this.primaryVideoAspectRatio > 1.08 ? 0 : 1.5
          });
        }
        .width('100%').height('100%');
      } else if (this.videoSources.length > 0) {
        LiveVideoTile({
          source: this.videoSources[0],
          fillParent: true,
          pulseExpanded: this.pulseExpanded,
          onSurfaceReady: (
            endpointId: string, surfaceId: string, surfaceWidth: number, surfaceHeight: number
          ): void => this.setSurface(endpointId, surfaceId, surfaceWidth, surfaceHeight),
          onSurfaceGone: (endpointId: string, surfaceId: string): void =>
            this.clearSurface(endpointId, surfaceId)
        });
      } else if (this.isLocalCameraActive()) {
        LocalVideoPreviewTile({
          mode: this.localVideoMode,
          tileWidth: '100%',
          tileHeight: '100%',
          onSurfaceReady: (
            surfaceId: string, surfaceWidth: number, surfaceHeight: number
          ): void => this.setLocalPreviewSurface(surfaceId, surfaceWidth, surfaceHeight),
          onSurfaceGone: (surfaceId: string): void =>
            this.clearLocalPreviewSurface(surfaceId)
        });
      } else {
        Column({ space: 10 }) {
          SymbolGlyph($r('sys.symbol.camera')).fontSize(38).fontColor([CALL_SUBTEXT]);
          Text(this.mediaStatus).fontSize(13).fontColor(CALL_SUBTEXT);
        }
      }

      Column() {
        Row({ space: 6 }) {
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.arrow_down_right_and_arrow_up_left'))
              .fontSize(20).fontColor([Color.White]);
          }
          .width(42).height(42).padding(0)
          .backgroundColor('#A617222B')
          .border({ width: 1, color: '#42FFFFFF' })
          .onClick((): void => this.toggleFullscreen());
          Button({ type: ButtonType.Circle }) {
            Stack({ alignContent: Alignment.Center }) {
              SymbolGlyph($r('sys.symbol.mic')).fontSize(21).fontColor([Color.White]);
              if (this.isMuted) {
                Text('╱').fontSize(24).fontWeight(FontWeight.Bold).fontColor(Color.White);
              }
            }
          }
          .width(42).height(42).backgroundColor(this.isMuted ? '#8A40505A' : '#C539D98A')
          .onClick((): void => { this.toggleMuted(); });
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.camera')).fontSize(20).fontColor([
              this.localVideoActive ? CALL_BACKGROUND : Color.White
            ]);
          }
          .width(42).height(42)
          .backgroundColor(
            this.localVideoActive ? CALL_GREEN :
              (this.localVideoBusy ? '#A63D6256' : '#A640505A')
          )
          .enabled(!this.localVideoBusy)
          .onClick((): void => { this.toggleCamera(); });
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.computer')).fontSize(20).fontColor([
              this.screenShareActive ? CALL_BACKGROUND : Color.White
            ]);
          }
          .width(42).height(42)
          .backgroundColor(
            this.screenShareActive ? CALL_GREEN :
              (this.screenShareBusy ? '#A63D6256' : '#A640505A')
          )
          .enabled(!this.screenShareBusy)
          .onClick((): void => { this.toggleScreenShare(); });
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.phone_fill')).fontSize(21).fontColor([Color.White]);
          }
          .width(42).height(42).backgroundColor('#D9D94B55')
          .onClick((): void => this.leave());
          Blank();
          Button() {
            Row({ space: 6 }) {
              SymbolGlyph($r('sys.symbol.person_2')).fontSize(17).fontColor([Color.White]);
              Text(`成员 ${this.participants.length}`).fontSize(13).fontColor(Color.White);
            }
          }
          .height(40).padding({ left: 12, right: 12 })
          .backgroundColor('#A617222B').borderRadius(20)
          .onClick((): void => { this.fullscreenPanelOpen = true; });
        }
        .width('100%');
        Blank();
        if (this.participants.some(
          (participant: GroupCallParticipantInfo): boolean => participant.isSpeaking
        )) {
          Row({ space: 7 }) {
            Circle({ width: 7, height: 7 }).fill(CALL_GREEN)
              .opacity(this.pulseExpanded ? 1 : 0.52);
            Text(`${this.participants.find(
              (participant: GroupCallParticipantInfo): boolean => participant.isSpeaking
            )?.name ?? '成员'} 正在发言`)
              .fontSize(12).fontColor(Color.White).maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis });
          }
          .padding({ left: 11, right: 12, top: 7, bottom: 7 })
          .backgroundColor('#B314222B').borderRadius(16).alignSelf(ItemAlign.Start);
        }
      }
      .width('100%').height('100%')
      .padding({ left: 14, right: 14, top: this.topSafe + 10, bottom: this.bottomSafe + 12 });

      if (this.fullscreenPanelOpen) {
        this.fullscreenParticipantDrawer();
      }
    }
    .width('100%').height('100%').backgroundColor(Color.Black);
  }

  build() {
    Stack() {
      if (this.isFullscreen) {
        this.fullscreenVideo();
      } else {
        Column() {
          this.header();
          Scroll() {
            Column() {
              if (this.videoSources.length > 0 || this.isLocalCameraActive()) {
                Column() {
                  this.videoArea();
                }
                .width('100%')
                .opacity(this.videoAreaOpacity)
                .scale({ x: this.videoAreaScale, y: this.videoAreaScale });
              }
              if (this.state.error !== '') {
                Text(this.state.error).fontSize(12).fontColor('#FF7B82')
                  .padding(10).width('100%').backgroundColor('#332027');
              }
              if (this.participants.length > 0) {
                Column({ space: 1 }) {
                  ForEach(this.participants, (participant: GroupCallParticipantInfo) => {
                    this.participantRow(participant);
                  }, (participant: GroupCallParticipantInfo): string =>
                    `${participant.key}:${participant.revision}`)
                }
                .width('100%').margin({ top: 4 });
              }
            }
            .width('100%').padding({ left: 8, right: 8, bottom: 8 });
          }
          .width('100%').layoutWeight(1).scrollBar(BarState.Off);
          this.controls();
        }
        .width('100%').height('100%');
      }
    }
    .width('100%').height('100%').backgroundColor(CALL_PANEL_ALT)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .padding({
      top: this.isFullscreen ? 0 : this.topSafe,
      bottom: this.isFullscreen ? 0 : this.bottomSafe
    });
  }
}
