import { common } from '@kit.AbilityKit';
import {
  ComponentContent, OverlayManager, router, UIContext
} from '@kit.ArkUI';
import { GroupCallParticipantsStore } from '../../store/GroupCallParticipantsStore';
import { LiveStreamStore } from '../../store/LiveStreamStore';
import { liveStreamBackgroundTask } from '../../services/LiveStreamBackgroundTask';
import { TgcallsGroupSession, TgcallsJoinResult } from '../../services/TgcallsGroupSession';
import {
  GroupCallParticipantInfo, GroupCallStreamInfo, GroupCallVideoSource, LiveStreamState
} from '../../tdkit/GroupCallTypes';
import { getGroupCall, leaveGroupCall } from '../../tdkit/GroupCallApi';
import { getTdClient } from '../../tdkit/Globals';
import { confirmLeaveLiveStream } from './LiveViewerUi';
import {
  KEY_POWER_CALL_ANIMATIONS, powerAnimationDuration
} from '../../store/AppSettings';

const FLOAT_BACKGROUND: string = '#101820';
const FLOAT_PANEL: string = '#E9142029';
const FLOAT_TEXT: string = '#F4F7F9';
const FLOAT_SUBTEXT: string = '#A7B4BE';
const FLOAT_GREEN: string = '#39D98A';
const FLOAT_RED: string = '#FF405C';
const HEALTH_INTERVAL_MS: number = 5000;
const RECONNECT_GRACE_MS: number = 5000;

export interface FloatingLiveDescriptor {
  groupCallId: number;
  chatId: number;
  isRtmp: boolean;
  title: string;
  participantCount: number;
  primarySource: GroupCallVideoSource | null;
}

export interface FloatingLiveState {
  visible: boolean;
  large: boolean;
  title: string;
  participantCount: number;
  status: string;
  hasVideo: boolean;
  recovering: boolean;
  isRtmp: boolean;
  sourceName: string;
}

type FloatingLiveListener = (state: FloatingLiveState) => void;

interface FloatingSurfaceBinding {
  surfaceId: string;
  width: number;
  height: number;
}

class FloatingOverlayArgs {
  controller: LiveFloatingWindowController;

  constructor(controller: LiveFloatingWindowController) {
    this.controller = controller;
  }
}

function cloneSource(source: GroupCallVideoSource | null): GroupCallVideoSource | null {
  if (source === null) { return null; }
  return {
    endpointId: source.endpointId,
    participantKey: source.participantKey,
    name: source.name,
    audioSourceId: source.audioSourceId,
    sourceGroups: source.sourceGroups,
    isPaused: source.isPaused,
    isScreenSharing: source.isScreenSharing,
    isSpeaking: source.isSpeaking,
    isMuted: source.isMuted
  };
}

function copyState(state: FloatingLiveState): FloatingLiveState {
  return {
    visible: state.visible,
    large: state.large,
    title: state.title,
    participantCount: state.participantCount,
    status: state.status,
    hasVideo: state.hasVideo,
    recovering: state.recovering,
    isRtmp: state.isRtmp,
    sourceName: state.sourceName
  };
}

function uniqueVideoChannelIds(streams: GroupCallStreamInfo[]): number[] {
  const seen: Set<number> = new Set();
  const result: number[] = [];
  for (const stream of streams) {
    if (stream.channelId !== 0 && !seen.has(stream.channelId)) {
      seen.add(stream.channelId);
      result.push(stream.channelId);
    }
  }
  return result;
}

export class LiveFloatingWindowController {
  private descriptor: FloatingLiveDescriptor | null = null;
  private state: FloatingLiveState = {
    visible: false,
    large: false,
    title: '',
    participantCount: 0,
    status: '正在切换到悬浮窗…',
    hasVideo: false,
    recovering: false,
    isRtmp: false,
    sourceName: ''
  };
  private listeners: FloatingLiveListener[] = [];
  private overlayManager: OverlayManager | null = null;
  private overlayContent: ComponentContent<FloatingOverlayArgs> | null = null;
  private abilityContext: common.UIAbilityContext | null = null;
  private session: TgcallsGroupSession | null = null;
  private liveStore: LiveStreamStore | null = null;
  private participantStore: GroupCallParticipantsStore | null = null;
  private offLive: (() => void) | null = null;
  private offParticipants: (() => void) | null = null;
  private primarySource: GroupCallVideoSource | null = null;
  private requestedEndpoint: string = '';
  private surfaceBinding: FloatingSurfaceBinding | null = null;
  private generation: number = 0;
  private hasJoinedOnce: boolean = false;
  private reconnectAttempt: number = 0;
  private reconnectTimer: number = -1;
  private healthTimer: number = -1;
  private refreshInFlight: boolean = false;

  isVisible(): boolean {
    return this.descriptor !== null && this.state.visible;
  }

  subscribe(listener: FloatingLiveListener): () => void {
    this.listeners = [...this.listeners, listener];
    listener(copyState(this.state));
    return (): void => {
      this.listeners = this.listeners.filter(
        (current: FloatingLiveListener): boolean => current !== listener
      );
    };
  }

  show(
    uiContext: UIContext, abilityContext: common.UIAbilityContext, descriptor: FloatingLiveDescriptor
  ): void {
    this.removeOverlay();
    this.stopRuntime();
    this.abilityContext = abilityContext;
    this.descriptor = {
      groupCallId: descriptor.groupCallId,
      chatId: descriptor.chatId,
      isRtmp: descriptor.isRtmp,
      title: descriptor.title,
      participantCount: descriptor.participantCount,
      primarySource: cloneSource(descriptor.primarySource)
    };
    this.primarySource = cloneSource(descriptor.primarySource);
    this.state = {
      visible: true,
      large: false,
      title: descriptor.title !== '' ? descriptor.title : '正在直播',
      participantCount: descriptor.participantCount,
      status: '正在切换到悬浮窗…',
      hasVideo: descriptor.primarySource !== null,
      recovering: false,
      isRtmp: descriptor.isRtmp,
      sourceName: descriptor.primarySource?.name ?? ''
    };
    this.emit();
    this.overlayManager = uiContext.getOverlayManager();
    this.overlayContent = new ComponentContent<FloatingOverlayArgs>(
      uiContext, wrapBuilder(buildFloatingLiveOverlay), new FloatingOverlayArgs(this)
    );
    this.overlayManager.addComponentContent(this.overlayContent);
    liveStreamBackgroundTask.start(abilityContext, false);
    this.startRuntime();
  }

  expand(): void {
    if (!this.isVisible() || this.state.large) { return; }
    this.state.large = true;
    this.emit();
  }

  collapse(): void {
    if (!this.isVisible() || !this.state.large) { return; }
    this.state.large = false;
    this.emit();
  }

  attachSurface(surfaceId: string, width: number, height: number): void {
    if (surfaceId === '') { return; }
    this.surfaceBinding = {
      surfaceId,
      width: Math.max(1, width),
      height: Math.max(1, height)
    };
    this.bindCurrentSurface();
  }

  resizeSurface(width: number, height: number): void {
    const binding = this.surfaceBinding;
    if (binding === null || width <= 0 || height <= 0) { return; }
    binding.width = Math.round(width);
    binding.height = Math.round(height);
    this.bindCurrentSurface();
  }

  detachSurface(surfaceId: string): void {
    if (this.surfaceBinding?.surfaceId !== surfaceId) { return; }
    if (this.requestedEndpoint !== '') {
      this.session?.setVideoSurface(this.requestedEndpoint, '0');
    }
    this.surfaceBinding = null;
  }

  resumeMedia(): void {
    this.session?.resumeMedia();
    if (this.primarySource !== null && !this.descriptor?.isRtmp) {
      this.session?.setVideoChannel(
        this.primarySource.endpointId,
        this.primarySource.audioSourceId,
        this.primarySource.sourceGroups
      );
    }
    this.bindCurrentSurface();
    this.refreshGroupCall();
  }

  requestClose(): void {
    confirmLeaveLiveStream((): void => {
      this.dismissAndLeave();
    });
  }

  async closeForAccountSwitch(): Promise<void> {
    const groupCallId = this.descriptor?.groupCallId ?? 0;
    this.removeOverlay();
    this.stopRuntime();
    this.descriptor = null;
    this.state.visible = false;
    this.emit();
    liveStreamBackgroundTask.stop();
    if (groupCallId <= 0) { return; }
    try {
      await leaveGroupCall(getTdClient(), groupCallId);
    } catch (caught) {
      const error = caught as Error;
      console.error(`LiveFloating.accountSwitch leave failed: ${error.message}`);
    }
  }

  async prepareForOpeningFullPage(): Promise<void> {
    if (this.descriptor === null) { return; }
    const groupCallId = this.descriptor.groupCallId;
    this.removeOverlay();
    this.stopRuntime();
    this.descriptor = null;
    this.state.visible = false;
    this.emit();
    liveStreamBackgroundTask.stop();
    try {
      await leaveGroupCall(getTdClient(), groupCallId);
    } catch (caught) {
      const error = caught as Error;
      console.error(`LiveFloating.prepareForOpening leave failed: ${error.message}`);
    }
  }

  async restoreFullPage(): Promise<void> {
    const descriptor = this.descriptor;
    if (descriptor === null) { return; }
    await this.prepareForOpeningFullPage();
    const params: Record<string, Object> = {
      'groupCallId': descriptor.groupCallId,
      'chatId': descriptor.chatId
    };
    router.pushUrl({
      url: descriptor.isRtmp
        ? 'pages/chat/RtmpLiveStreamViewerPage' : 'pages/chat/LiveStreamViewerPage',
      params
    });
  }

  private dismissAndLeave(): void {
    const groupCallId = this.descriptor?.groupCallId ?? 0;
    this.removeOverlay();
    this.stopRuntime();
    this.descriptor = null;
    this.state.visible = false;
    this.emit();
    liveStreamBackgroundTask.stop();
    if (groupCallId > 0) {
      leaveGroupCall(getTdClient(), groupCallId).catch((caught: Error): void => {
        console.error(`LiveFloating.dismiss leave failed: ${caught.message}`);
      });
    }
  }

  private startRuntime(): void {
    const descriptor = this.descriptor;
    if (descriptor === null || descriptor.groupCallId <= 0) { return; }
    const client = getTdClient();
    this.liveStore = new LiveStreamStore(client, descriptor.groupCallId);
    this.offLive = this.liveStore.subscribe(
      (state: LiveStreamState): void => this.onLiveState(state)
    );
    if (!descriptor.isRtmp) {
      this.participantStore = new GroupCallParticipantsStore(client, descriptor.groupCallId);
      this.offParticipants = this.participantStore.subscribe(
        (participants: GroupCallParticipantInfo[]): void => this.onParticipants(participants)
      );
    }
    this.healthTimer = setInterval((): void => {
      this.session?.resumeMedia();
      this.bindCurrentSurface();
      this.refreshGroupCall();
    }, HEALTH_INTERVAL_MS);
    this.replaceSession('进入悬浮窗');
    this.refreshGroupCall();
  }

  private stopRuntime(): void {
    this.generation += 1;
    this.clearReconnectTimer();
    if (this.healthTimer !== -1) {
      clearInterval(this.healthTimer);
      this.healthTimer = -1;
    }
    if (this.offParticipants !== null) {
      this.offParticipants();
      this.offParticipants = null;
    }
    this.participantStore?.dispose();
    this.participantStore = null;
    if (this.offLive !== null) {
      this.offLive();
      this.offLive = null;
    }
    this.liveStore?.dispose();
    this.liveStore = null;
    if (this.session !== null) {
      this.session.clearVideo();
      this.session.stop();
      this.session = null;
    }
    this.requestedEndpoint = '';
    this.surfaceBinding = null;
    this.hasJoinedOnce = false;
    this.reconnectAttempt = 0;
    this.refreshInFlight = false;
  }

  private replaceSession(reason: string): void {
    const descriptor = this.descriptor;
    if (descriptor === null || descriptor.groupCallId <= 0) { return; }
    this.clearReconnectTimer();
    const sequence = ++this.generation;
    if (this.session !== null) {
      this.session.clearVideo();
      this.session.stop();
    }
    this.session = null;
    this.requestedEndpoint = '';
    this.setPlaybackState(
      this.hasJoinedOnce ? '正在恢复悬浮直播…' : '正在连接悬浮直播…',
      this.state.hasVideo,
      this.hasJoinedOnce
    );
    const client = getTdClient();
    const session = new TgcallsGroupSession(
      (connected: boolean): void => this.onNetworkState(session, sequence, connected),
      (): void => {},
      (streams: GroupCallStreamInfo[], unified: boolean): void => {
        if (this.isCurrent(session, sequence) && descriptor.isRtmp && unified) {
          this.configureRtmpStreams(streams);
        }
      },
      (received: boolean): void => {
        if (this.isCurrent(session, sequence) && descriptor.isRtmp) {
          this.setPlaybackState(
            received ? (this.state.hasVideo ? '直播播放中' : '直播音频播放中') : '直播缓冲中…',
            this.state.hasVideo,
            !received
          );
        }
      }
    );
    this.session = session;
    console.info(`[LiveFloating] session=${sequence} reason=${reason}`);
    session.join(client, descriptor.groupCallId, true).then((result: TgcallsJoinResult): void => {
      if (!this.isCurrent(session, sequence)) { return; }
      if (descriptor.isRtmp && (!result.isBroadcast || !result.isUnifiedBroadcast)) {
        this.setPlaybackState('直播模式已经变化', false, false);
        return;
      }
      this.hasJoinedOnce = true;
      this.reconnectAttempt = 0;
      this.liveStore?.setStreams(result.streams);
      if (descriptor.isRtmp) {
        this.configureRtmpStreams(result.streams);
      } else if (this.primarySource !== null) {
        this.configurePrimarySource(this.primarySource);
      }
      this.participantStore?.load(100).catch((caught: Error): void => {
        console.error(`LiveFloating.loadParticipants failed: ${caught.message}`);
      });
      session.resumeMedia();
      this.bindCurrentSurface();
      this.setPlaybackState(
        this.state.hasVideo ? '直播播放中' : '直播音频播放中',
        this.state.hasVideo,
        false
      );
      this.refreshGroupCall();
    }).catch((caught: Error): void => {
      if (!this.isCurrent(session, sequence)) { return; }
      session.stop();
      this.session = null;
      this.reconnectAttempt += 1;
      this.setPlaybackState('悬浮直播连接中断，正在重试…', this.state.hasVideo, true);
      const delay = Math.min(30000, 1000 * Math.pow(2, Math.min(this.reconnectAttempt - 1, 5)));
      this.scheduleReconnect(delay, `加入失败：${caught.message}`);
    });
  }

  private isCurrent(session: TgcallsGroupSession, sequence: number): boolean {
    return this.descriptor !== null && this.session === session && this.generation === sequence;
  }

  private onNetworkState(
    session: TgcallsGroupSession, sequence: number, connected: boolean
  ): void {
    if (!this.isCurrent(session, sequence)) { return; }
    if (connected) {
      this.reconnectAttempt = 0;
      this.clearReconnectTimer();
      session.resumeMedia();
      this.bindCurrentSurface();
      this.setPlaybackState(
        this.state.hasVideo ? '直播播放中' : '直播音频播放中',
        this.state.hasVideo,
        false
      );
      return;
    }
    if (this.hasJoinedOnce) {
      this.setPlaybackState('网络波动，正在恢复…', this.state.hasVideo, true);
      this.scheduleReconnect(RECONNECT_GRACE_MS, '媒体网络断开');
    }
  }

  private onLiveState(state: LiveStreamState): void {
    if (this.descriptor === null) { return; }
    this.state.title = state.title !== '' ? state.title : this.state.title;
    this.state.participantCount = state.participantCount;
    if (!state.isActive && this.hasJoinedOnce) {
      this.clearReconnectTimer();
      this.setPlaybackState('直播已结束', this.state.hasVideo, false);
    } else if (state.needRejoin || (this.hasJoinedOnce && !state.isJoined)) {
      this.setPlaybackState('正在重新加入直播…', this.state.hasVideo, true);
      this.scheduleReconnect(500, 'TDLib 要求重新加入');
    } else {
      this.emit();
    }
  }

  private onParticipants(participants: GroupCallParticipantInfo[]): void {
    const sources: GroupCallVideoSource[] = [];
    for (const participant of participants) {
      for (const source of participant.videoSources) { sources.push(source); }
    }
    if (sources.length === 0) {
      if (this.primarySource === null) {
        this.setPlaybackState('直播音频播放中', false, this.state.recovering);
      }
      return;
    }
    sources.sort((left: GroupCallVideoSource, right: GroupCallVideoSource): number => {
      if (left.isScreenSharing !== right.isScreenSharing) {
        return left.isScreenSharing ? -1 : 1;
      }
      if (left.isSpeaking !== right.isSpeaking) { return left.isSpeaking ? -1 : 1; }
      return left.endpointId.localeCompare(right.endpointId);
    });
    const previousEndpoint = this.primarySource?.endpointId ?? '';
    const retained = sources.find(
      (source: GroupCallVideoSource): boolean => source.endpointId === previousEndpoint
    );
    this.configurePrimarySource(retained ?? sources[0]);
  }

  private configurePrimarySource(source: GroupCallVideoSource): void {
    const session = this.session;
    if (session === null) {
      this.primarySource = cloneSource(source);
      return;
    }
    if (this.requestedEndpoint !== '' && this.requestedEndpoint !== source.endpointId) {
      session.setVideoSurface(this.requestedEndpoint, '0');
      session.removeVideoChannel(this.requestedEndpoint);
    }
    this.primarySource = cloneSource(source);
    this.requestedEndpoint = source.endpointId;
    session.setVideoChannel(source.endpointId, source.audioSourceId, source.sourceGroups);
    this.state.hasVideo = true;
    this.state.sourceName = source.name;
    this.bindCurrentSurface();
    this.emit();
  }

  private configureRtmpStreams(streams: GroupCallStreamInfo[]): void {
    const ids = uniqueVideoChannelIds(streams);
    if (ids.length === 0) {
      this.requestedEndpoint = '';
      this.setPlaybackState('等待主播画面…', false, this.state.recovering);
      return;
    }
    this.requestedEndpoint = 'unified';
    this.session?.setVideoChannel('unified', 0, `SIM=${ids.join(',')}`);
    this.state.hasVideo = true;
    this.state.sourceName = this.state.title;
    this.bindCurrentSurface();
    this.emit();
  }

  private bindCurrentSurface(): void {
    const binding = this.surfaceBinding;
    if (binding === null || this.requestedEndpoint === '') { return; }
    this.session?.setVideoSurface(
      this.requestedEndpoint, binding.surfaceId, binding.width, binding.height
    );
  }

  private scheduleReconnect(delayMs: number, reason: string): void {
    if (this.descriptor === null || this.reconnectTimer !== -1) { return; }
    this.reconnectTimer = setTimeout((): void => {
      this.reconnectTimer = -1;
      this.replaceSession(reason);
    }, Math.max(0, delayMs));
  }

  private clearReconnectTimer(): void {
    if (this.reconnectTimer !== -1) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = -1;
    }
  }

  private async refreshGroupCall(): Promise<void> {
    const descriptor = this.descriptor;
    if (descriptor === null || this.refreshInFlight) { return; }
    this.refreshInFlight = true;
    try {
      const groupCall = await getGroupCall(getTdClient(), descriptor.groupCallId);
      if (this.descriptor?.groupCallId === descriptor.groupCallId) {
        this.liveStore?.applyGroupCall(groupCall);
      }
    } catch (caught) {
      const error = caught as Error;
      console.error(`LiveFloating.refresh failed: ${error.message}`);
    } finally {
      this.refreshInFlight = false;
    }
  }

  private setPlaybackState(status: string, hasVideo: boolean, recovering: boolean): void {
    this.state.status = status;
    this.state.hasVideo = hasVideo;
    this.state.recovering = recovering;
    this.emit();
  }

  private emit(): void {
    const snapshot = copyState(this.state);
    for (const listener of this.listeners) { listener(snapshot); }
  }

  private removeOverlay(): void {
    const content = this.overlayContent;
    if (content !== null) {
      try {
        this.overlayManager?.removeComponentContent(content);
      } catch (caught) {
        console.error(`LiveFloating.removeOverlay failed: ${caught}`);
      }
      content.dispose();
    }
    this.overlayContent = null;
    this.overlayManager = null;
  }
}

export const floatingLiveWindow: LiveFloatingWindowController =
  new LiveFloatingWindowController();

@Component
struct FloatingLiveOverlay {
  controller: LiveFloatingWindowController = floatingLiveWindow;
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @StorageProp('appForegroundEpoch') @Watch('onForegroundEpoch') foregroundEpoch: number = 0;
  @State state: FloatingLiveState = {
    visible: false,
    large: false,
    title: '',
    participantCount: 0,
    status: '',
    hasVideo: false,
    recovering: false,
    isRtmp: false,
    sourceName: ''
  };
  private off: (() => void) | null = null;
  private surfaceController: XComponentController = new XComponentController();
  private surfaceId: string = '';
  @State controlsVisible: boolean = true;

  aboutToAppear(): void {
    this.off = this.controller.subscribe((state: FloatingLiveState): void => {
      this.state = state;
    });
  }

  aboutToDisappear(): void {
    if (this.surfaceId !== '') {
      this.controller.detachSurface(this.surfaceId);
      this.surfaceId = '';
    }
    if (this.off !== null) {
      this.off();
      this.off = null;
    }
  }

  private onForegroundEpoch(): void {
    this.controller.resumeMedia();
  }

  private refreshSurfaceSize(): void {
    if (this.surfaceId === '') { return; }
    const rect: SurfaceRect = this.surfaceController.getXComponentSurfaceRect();
    this.controller.resizeSurface(
      Math.max(1, Math.round(rect.surfaceWidth)),
      Math.max(1, Math.round(rect.surfaceHeight))
    );
  }

  private onPlayerTap(): void {
    if (!this.state.large) {
      this.controlsVisible = true;
      this.controller.expand();
      return;
    }
    this.controlsVisible = !this.controlsVisible;
  }

  private collapsePlayer(): void {
    this.controlsVisible = true;
    this.controller.collapse();
  }

  build() {
    Column() {
      Blank();
      Row() {
        Blank();
        Stack({ alignContent: Alignment.Center }) {
          XComponent({
            id: 'floating_live_primary_video',
            type: XComponentType.TEXTURE,
            controller: this.surfaceController
          })
            .onLoad((): void => {
              const rect: SurfaceRect = this.surfaceController.getXComponentSurfaceRect();
              this.surfaceId = this.surfaceController.getXComponentSurfaceId();
              this.controller.attachSurface(
                this.surfaceId,
                Math.max(1, Math.round(rect.surfaceWidth)),
                Math.max(1, Math.round(rect.surfaceHeight))
              );
            })
            .onDestroy((): void => {
              if (this.surfaceId !== '') {
                this.controller.detachSurface(this.surfaceId);
                this.surfaceId = '';
              }
            })
            .width('100%').height('100%')
            .onClick((): void => this.onPlayerTap());

          if ((!this.state.hasVideo || this.state.recovering) &&
            (!this.state.large || this.controlsVisible)) {
            Column({ space: 7 }) {
              Stack({ alignContent: Alignment.Center }) {
                Circle({ width: 34, height: 34 }).fill('#384B59');
                SymbolGlyph($r('sys.symbol.play_fill')).fontSize(16).fontColor([Color.White]);
              }.width(38).height(38);
              Text(this.state.status).fontSize(11).fontColor(FLOAT_SUBTEXT)
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
            }
            .onClick((): void => this.onPlayerTap());
          }

          if (!this.state.large || this.controlsVisible) {
            Column() {
              Row({ space: 6 }) {
                if (this.state.large) {
                  Button({ type: ButtonType.Circle }) {
                    SymbolGlyph($r('sys.symbol.arrow_down_right_and_arrow_up_left'))
                      .fontSize(14).fontColor([Color.White]);
                  }
                  .width(29).height(29)
                  .backgroundColor('#B02A3540')
                  .onClick((): void => this.collapsePlayer());
                }
                Circle({ width: 6, height: 6 }).fill(
                  this.state.recovering ? '#F5A623' : FLOAT_RED
                );
                Text('LIVE').fontSize(10).fontWeight(FontWeight.Bold).fontColor(Color.White);
                Text(this.state.title).fontSize(11).fontColor(FLOAT_TEXT)
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1);
                Button({ type: ButtonType.Circle }) {
                  SymbolGlyph($r('sys.symbol.xmark')).fontSize(13).fontColor([Color.White]);
                }
                .width(27).height(27).backgroundColor('#A62B3540')
                .onClick((): void => this.controller.requestClose());
              }
              .width('100%')
              .padding({ left: 8, right: 7, top: 6, bottom: 5 })
              .backgroundColor('#A6121B22');
              Blank()
                .onClick((): void => this.onPlayerTap());
              Row({ space: 7 }) {
                Text(this.state.large ? '点击画面隐藏控件' : '点击画面放大')
                  .fontSize(10).fontColor(FLOAT_SUBTEXT).layoutWeight(1);
                Button() {
                  Row({ space: 5 }) {
                    SymbolGlyph($r('sys.symbol.plus_square_on_square'))
                      .fontSize(14).fontColor([Color.White]);
                    Text('返回直播').fontSize(11).fontColor(Color.White);
                  }
                }
                .height(30).padding({ left: 9, right: 9 })
                .backgroundColor('#C93390EC').borderRadius(15)
                .onClick((): void => { this.controller.restoreFullPage(); });
              }
              .width('100%')
              .padding({ left: 9, right: 7, top: 5, bottom: 6 })
              .backgroundColor('#B6121B22');
            }
            .width('100%').height('100%')
            .transition(
              TransitionEffect.OPACITY.animation({
                duration: powerAnimationDuration(KEY_POWER_CALL_ANIMATIONS, 160),
                curve: Curve.EaseOut
              })
            );
          }
        }
        .width(this.state.large ? 320 : 196)
        .height(this.state.large ? 180 : 112)
        .backgroundColor(FLOAT_BACKGROUND)
        .borderRadius(13).clip(true)
        .border({ width: 1, color: '#3DFFFFFF' })
        .shadow({ radius: 22, color: '#78000000', offsetX: 0, offsetY: 8 })
        .animation({
          duration: powerAnimationDuration(KEY_POWER_CALL_ANIMATIONS, 240), curve: Curve.Friction
        })
        .onAreaChange((_old: Area, _area: Area): void => {
          setTimeout((): void => this.refreshSurfaceSize(), 30);
        })
        .transition(
          TransitionEffect.scale({ x: 0.9, y: 0.9 })
            .combine(TransitionEffect.OPACITY)
            .animation({
              duration: powerAnimationDuration(KEY_POWER_CALL_ANIMATIONS, 220), curve: Curve.Friction
            })
        );
      }
      .width('100%');
    }
    .width('100%').height('100%')
    .padding({ right: 12, bottom: this.bottomSafe + 82, top: this.topSafe + 8 })
    // Only the mini-player consumes touches. Everything outside it continues
    // to hit-test the currently visible app page beneath the global overlay.
    .hitTestBehavior(HitTestMode.Transparent);
  }
}

@Builder
function buildFloatingLiveOverlay(args: FloatingOverlayArgs) {
  FloatingLiveOverlay({ controller: args.controller });
}
