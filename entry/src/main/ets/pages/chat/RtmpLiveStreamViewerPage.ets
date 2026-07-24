import { router, promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { LiveStreamStore } from '../../store/LiveStreamStore';
import {
  GroupCallMessageEntry, GroupCallMessageStore
} from '../../store/GroupCallMessageStore';
import { MessageEntry } from '../../store/MessageEntry';
import { MessageStore } from '../../store/MessageStore';
import {
  GroupCallStreamInfo, LiveStreamState, emptyLiveStreamState
} from '../../tdkit/GroupCallTypes';
import { getTdClient, getUserStore } from '../../tdkit/Globals';
import { endGroupCall, getGroupCall, leaveGroupCall } from '../../tdkit/GroupCallApi';
import { TgcallsGroupSession, TgcallsJoinResult } from '../../services/TgcallsGroupSession';
import { liveStreamBackgroundTask } from '../../services/LiveStreamBackgroundTask';
import {
  confirmAdminLeaveLiveStream, confirmLeaveLiveStream, setLiveStreamFullscreen
} from './LiveViewerUi';
import {
  FloatingLiveDescriptor, floatingLiveWindow
} from './LiveFloatingWindow';
import {
  KEY_POWER_CALL_ANIMATIONS, powerAnimationDuration, powerFeatureEnabled
} from '../../store/AppSettings';

const LIVE_BACKGROUND: string = '#0A1117';
const LIVE_PANEL: string = '#101A23';
const LIVE_PANEL_ALT: string = '#16232D';
const LIVE_TEXT: string = '#F3F7F9';
const LIVE_SUBTEXT: string = '#8FA0AD';
const LIVE_RED: string = '#FF405C';
const LIVE_GREEN: string = '#39D98A';
const LIVE_ACCENT: string = '#4C9AFF';
const STREAM_RECONNECT_GRACE_MS: number = 8000;
const STREAM_STALL_MS: number = 15000;
const HEALTH_INTERVAL_MS: number = 4000;
const MAX_INTERACTIONS: number = 100;
const QUICK_REACTIONS: string[] = ['❤️', '🔥', '👏', '👍'];
const AVATAR_COLORS: string[] = ['#4C9AFF', '#9C6ADE', '#E06C75', '#2CB67D', '#E39B3A', '#4CB8C4'];

interface RtmpSurfaceBinding {
  surfaceId: string;
  width: number;
  height: number;
}

interface LiveInteractionEntry {
  key: string;
  id: number;
  senderName: string;
  senderInitials: string;
  senderAvatarPath: string;
  colorSeed: number;
  date: number;
  text: string;
  photoPath: string;
  emojiOnly: boolean;
  isFromOwner: boolean;
}

function isQuickReaction(text: string): boolean {
  return QUICK_REACTIONS.indexOf(text.trim()) >= 0;
}

// TDLib upgrades single Unicode emoji messages to messageAnimatedEmoji. The
// animated sticker is perfect for ChatPage, while the live overlay needs a
// cheap, reliable text fallback so it doesn't create dozens of media players.
function looksLikeEmojiOnly(raw: string): boolean {
  const value = raw.trim();
  if (value === '') { return false; }
  let hasEmoji = false;
  for (let i = 0; i < value.length;) {
    const first = value.charCodeAt(i);
    let codePoint = first;
    let width = 1;
    if (first >= 0xD800 && first <= 0xDBFF && i + 1 < value.length) {
      const second = value.charCodeAt(i + 1);
      if (second >= 0xDC00 && second <= 0xDFFF) {
        codePoint = 0x10000 + ((first - 0xD800) << 10) + (second - 0xDC00);
        width = 2;
      }
    }
    i += width;
    if (codePoint === 0x200D || codePoint === 0xFE0E || codePoint === 0xFE0F ||
      codePoint === 0x20E3 || codePoint === 0x0020) {
      continue;
    }
    const emoji = (codePoint >= 0x1F000 && codePoint <= 0x1FAFF) ||
      (codePoint >= 0x2600 && codePoint <= 0x27BF) ||
      (codePoint >= 0x2300 && codePoint <= 0x23FF) ||
      (codePoint >= 0x2B00 && codePoint <= 0x2BFF) ||
      codePoint === 0x00A9 || codePoint === 0x00AE || codePoint === 0x2122 ||
      codePoint === 0x3030 || codePoint === 0x303D || codePoint === 0x3297 || codePoint === 0x3299;
    if (!emoji) { return false; }
    hasEmoji = true;
  }
  return hasEmoji;
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

function liveMessageTime(timestamp: number): string {
  const value = new Date(timestamp * 1000);
  const hour = value.getHours().toString().padStart(2, '0');
  const minute = value.getMinutes().toString().padStart(2, '0');
  return `${hour}:${minute}`;
}

function groupCallInteraction(message: GroupCallMessageEntry): LiveInteractionEntry {
  return {
    key: `call:${message.id}:${message.revision}`,
    id: message.id,
    senderName: message.senderName,
    senderInitials: message.senderInitials,
    senderAvatarPath: message.senderAvatarPath,
    colorSeed: message.colorSeed,
    date: message.date,
    text: message.text,
    photoPath: '',
    emojiOnly: isQuickReaction(message.text) || looksLikeEmojiOnly(message.text),
    isFromOwner: message.isFromOwner
  };
}

function chatInteraction(message: MessageEntry): LiveInteractionEntry {
  const name = message.senderName !== '' ? message.senderName : (message.isOutgoing ? '我' : '频道');
  const text = message.text.trim() !== '' ? message.text : message.placeholderLabel;
  const emojiOnly = isQuickReaction(text) || looksLikeEmojiOnly(text);
  return {
    key: `chat:${message.id}:${message.sendState}:${name}:${message.senderAvatarPath}:${message.photoPath}:${text}`,
    id: message.id,
    senderName: name,
    senderInitials: name !== '' ? name.substring(0, 1).toUpperCase() : '?',
    senderAvatarPath: message.senderAvatarPath,
    colorSeed: message.senderId !== 0 ? message.senderId : message.id,
    date: message.date,
    text: text !== '' ? text : '新消息',
    photoPath: emojiOnly ? '' : message.photoPath,
    emojiOnly,
    isFromOwner: !message.senderIsUser
  };
}

@Component
struct RtmpVideoStage {
  @Prop status: string;
  @Prop hasVideo: boolean;
  @Prop recovering: boolean;
  @Prop fullscreen: boolean = false;
  @Prop pulseExpanded: boolean;
  onSurfaceReady: (surfaceId: string, width: number, height: number) => void = (): void => {};
  onSurfaceGone: () => void = (): void => {};
  onFullscreenToggle: () => void = (): void => {};
  private controller: XComponentController = new XComponentController();

  aboutToDisappear(): void {
    this.onSurfaceGone();
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      XComponent({
        id: 'rtmp_live_unified_video',
        type: XComponentType.TEXTURE,
        controller: this.controller
      })
        .onLoad((): void => {
          const rect: SurfaceRect = this.controller.getXComponentSurfaceRect();
          this.onSurfaceReady(
            this.controller.getXComponentSurfaceId(),
            Math.max(1, Math.round(rect.surfaceWidth)),
            Math.max(1, Math.round(rect.surfaceHeight))
          );
        })
        .onDestroy((): void => this.onSurfaceGone())
        .width('100%').height('100%');

      if (!this.hasVideo || this.recovering) {
        Column({ space: 10 }) {
          Stack({ alignContent: Alignment.Center }) {
            Circle({ width: 42, height: 42 }).fill('#283B49')
              .opacity(this.pulseExpanded ? 0.42 : 0.9)
              .scale({ x: this.pulseExpanded ? 1.14 : 0.9, y: this.pulseExpanded ? 1.14 : 0.9 });
            SymbolGlyph($r('sys.symbol.play_fill')).fontSize(20).fontColor([Color.White]);
          }.width(48).height(48);
          Text(this.status).fontSize(13).fontColor(LIVE_SUBTEXT).textAlign(TextAlign.Center);
        }
      }

      Column() {
        Row({ space: 6 }) {
          Circle({ width: 7, height: 7 }).fill(LIVE_RED)
            .opacity(this.pulseExpanded ? 1 : 0.55)
            .scale({ x: this.pulseExpanded ? 1.18 : 0.88, y: this.pulseExpanded ? 1.18 : 0.88 });
          Text('LIVE').fontSize(11).fontWeight(FontWeight.Bold).fontColor(Color.White);
        }
        .padding({ left: 9, right: 10, top: 5, bottom: 5 })
        .backgroundColor('#D9FF405C').borderRadius(12)
        .alignSelf(ItemAlign.Start).margin({ left: 12, top: 12 });
        Blank();
        if (this.recovering) {
          Text('连接中断，正在续播…')
            .fontSize(12).fontColor(Color.White)
            .padding({ left: 10, right: 10, top: 5, bottom: 5 })
            .backgroundColor('#A61C2730').borderRadius(12)
            .alignSelf(ItemAlign.Center).margin({ bottom: 12 });
        }
      }
      .width('100%').height('100%');

      Column() {
        Blank();
        Row() {
          Blank();
          Button({ type: ButtonType.Circle }) {
            Text(this.fullscreen ? '⤡' : '⤢')
              .fontSize(this.fullscreen ? 20 : 22).fontWeight(FontWeight.Bold).fontColor(Color.White);
          }
          .width(40).height(40).backgroundColor('#A617222B')
          .border({ width: 1, color: '#42FFFFFF' })
          .onClick((): void => this.onFullscreenToggle());
        }.width('100%');
      }
      .width('100%').height('100%').padding({ right: 10, bottom: 10 });
    }
    .width('100%').height(this.fullscreen ? '100%' : '220vp')
    .backgroundColor(Color.Black)
    .clip(true);
  }
}

@Component
struct LiveCommentBubble {
  @Prop message: LiveInteractionEntry;

  @Builder
  avatar() {
    if (this.message.senderAvatarPath !== '') {
      Image(this.message.senderAvatarPath.startsWith('/')
        ? `file://${this.message.senderAvatarPath}` : this.message.senderAvatarPath)
        .width(34).height(34).borderRadius(17).objectFit(ImageFit.Cover);
    } else {
      Stack() {
        Circle({ width: 34, height: 34 })
          .fill(AVATAR_COLORS[Math.abs(this.message.colorSeed) % AVATAR_COLORS.length]);
        Text(this.message.senderInitials).fontSize(13).fontWeight(FontWeight.Medium).fontColor(Color.White);
      }.width(34).height(34);
    }
  }

  build() {
    Row({ space: 9 }) {
      this.avatar();
      if (this.message.emojiOnly) {
        Row({ space: 7 }) {
          Text(this.message.senderName).fontSize(12).fontWeight(FontWeight.Medium)
            .fontColor(this.message.isFromOwner ? LIVE_GREEN : LIVE_ACCENT)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
          Text(this.message.text).fontSize(30);
        }
        .padding({ left: 11, right: 13, top: 5, bottom: 5 })
        .backgroundColor('#D91A2731').borderRadius(19);
      } else {
        Column({ space: 3 }) {
          Row({ space: 6 }) {
            Text(this.message.senderName)
              .fontSize(12).fontWeight(FontWeight.Medium)
              .fontColor(this.message.isFromOwner ? LIVE_GREEN : LIVE_ACCENT)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
            if (this.message.isFromOwner) {
              Text('主播').fontSize(9).fontWeight(FontWeight.Bold).fontColor('#082018')
                .padding({ left: 5, right: 5, top: 2, bottom: 2 })
                .backgroundColor(LIVE_GREEN).borderRadius(6);
            }
            Text(liveMessageTime(this.message.date)).fontSize(10).fontColor('#738491');
          }
          if (this.message.photoPath !== '') {
            Image(this.message.photoPath.startsWith('/')
              ? `file://${this.message.photoPath}` : this.message.photoPath)
              .width(170).height(104).borderRadius(10)
              .objectFit(ImageFit.Cover).margin({ top: 3 });
          }
          if (this.message.text !== '') {
            Text(this.message.text).fontSize(15).fontColor(LIVE_TEXT)
              .lineHeight(20).wordBreak(WordBreak.BREAK_WORD)
              .constraintSize({ maxWidth: 280 });
          }
        }
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 11, right: 13, top: 8, bottom: 9 })
        .backgroundColor(this.message.isFromOwner ? '#DD19392F' : '#DF17242E')
        .borderRadius({ topLeft: 5, topRight: 17, bottomLeft: 17, bottomRight: 17 });
      }
    }
    .width('100%').alignItems(VerticalAlign.Top)
    .transition(TransitionEffect.OPACITY.animation({
      duration: powerAnimationDuration(KEY_POWER_CALL_ANIMATIONS, 180), curve: Curve.EaseOut
    }));
  }
}

@Entry
@Component
struct RtmpLiveStreamViewerPage {
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @StorageProp('appForegroundEpoch') @Watch('onAppForegroundEpoch') appForegroundEpoch: number = 0;
  @State state: LiveStreamState = emptyLiveStreamState();
  @State mediaStatus: string = '正在加入直播…';
  @State recovering: boolean = false;
  @State hasVideo: boolean = false;
  @State messages: LiveInteractionEntry[] = [];
  @State draft: string = '';
  @State sending: boolean = false;
  @State pulseExpanded: boolean = false;
  @State isFullscreen: boolean = false;
  @State fullscreenPanelOpen: boolean = false;
  @State fullscreenMessagePreview: string = '';
  @State minimizeInProgress: boolean = false;
  @State canManageLive: boolean = false;
  @State endingLive: boolean = false;
  private groupCallId: number = 0;
  private chatId: number = 0;
  private pageActive: boolean = false;
  private hasJoinedOnce: boolean = false;
  private sessionSequence: number = 0;
  private recoveryInFlight: boolean = false;
  private reconnectAttempt: number = 0;
  private reconnectTimer: number = -1;
  private reconnectDueAt: number = 0;
  private healthTimer: number = -1;
  private pulseTimer: number = -1;
  private fullscreenPreviewTimer: number = -1;
  private groupCallRefreshInFlight: boolean = false;
  private joinedAt: number = 0;
  private lastPartAt: number = 0;
  private streamSignature: string = '';
  private surfaceBinding: RtmpSurfaceBinding | null = null;
  private liveStore: LiveStreamStore | null = null;
  private messageStore: GroupCallMessageStore | null = null;
  private channelMessageStore: MessageStore | null = null;
  private groupCallMessages: GroupCallMessageEntry[] = [];
  private channelMessages: MessageEntry[] = [];
  private session: TgcallsGroupSession | null = null;
  private offLive: (() => void) | null = null;
  private offMessages: (() => void) | null = null;
  private offMessageError: (() => void) | null = null;
  private offChannelMessages: (() => void) | null = null;
  private commentScroller: Scroller = new Scroller();
  private leavingForFloating: boolean = false;

  aboutToAppear(): void {
    this.pageActive = true;
    const params = router.getParams() as Record<string, Object> | undefined;
    this.groupCallId = params !== undefined
      ? ((params['groupCallId'] as number | undefined) ?? 0) : 0;
    this.chatId = params !== undefined ? ((params['chatId'] as number | undefined) ?? 0) : 0;
    if (this.groupCallId <= 0) {
      this.mediaStatus = '无效的直播间';
      return;
    }
    const client = getTdClient();
    this.liveStore = new LiveStreamStore(client, this.groupCallId);
    this.offLive = this.liveStore.subscribe(
      (state: LiveStreamState): void => this.onLiveState(state)
    );
    this.messageStore = new GroupCallMessageStore(client, getUserStore(), this.groupCallId);
    this.offMessages = this.messageStore.subscribe(
      (messages: GroupCallMessageEntry[]): void => this.onMessages(messages)
    );
    this.offMessageError = this.messageStore.subscribeError((message: string): void => {
      promptAction.showToast({ message, duration: 1800 });
    });
    this.messageStore.open();
    if (this.chatId !== 0) {
      this.channelMessageStore = new MessageStore(
        client, getUserStore(), this.chatId, 0, MAX_INTERACTIONS
      );
      this.offChannelMessages = this.channelMessageStore.subscribe(
        (messages: MessageEntry[]): void => this.onChannelMessages(messages)
      );
      this.channelMessageStore.open(undefined, true);
    }
    this.startPulse();
    this.startHealthMonitor();
    liveStreamBackgroundTask.start(getContext(this) as common.UIAbilityContext, false);
    this.replaceSession('首次加入');
    this.refreshGroupCall('首次查询');
  }

  onPageShow(): void {
    if (this.pageActive && this.groupCallId > 0) { this.resumeAfterForeground(); }
  }

  private onAppForegroundEpoch(): void {
    if (this.pageActive && this.groupCallId > 0) { this.resumeAfterForeground(); }
  }

  private onLiveState(next: LiveStreamState): void {
    this.state = next;
    if (next.needRejoin) {
      this.recovering = true;
      this.scheduleRecovery(0, 'TDLib 要求重新加入');
    } else if (this.hasJoinedOnce && next.isActive && !next.isJoined) {
      this.recovering = true;
      this.scheduleRecovery(500, '直播成员状态已断开');
    }
    if (this.hasJoinedOnce && !next.isActive) {
      this.mediaStatus = '直播已结束';
      this.recovering = false;
      this.clearRecoveryTimer();
    }
  }

  private onMessages(next: GroupCallMessageEntry[]): void {
    this.groupCallMessages = next;
    this.rebuildInteractions();
  }

  private onChannelMessages(next: MessageEntry[]): void {
    this.channelMessages = next.filter(
      (message: MessageEntry): boolean => message.contentType !== 'hidden'
    ).slice(-MAX_INTERACTIONS);
    this.rebuildInteractions();
  }

  private rebuildInteractions(): void {
    const previousLast = this.messages.length > 0 ? this.messages[this.messages.length - 1].key : '';
    const combined: LiveInteractionEntry[] = [];
    for (const message of this.channelMessages) { combined.push(chatInteraction(message)); }
    for (const message of this.groupCallMessages) { combined.push(groupCallInteraction(message)); }
    combined.sort((left: LiveInteractionEntry, right: LiveInteractionEntry): number => {
      if (left.date !== right.date) { return left.date - right.date; }
      if (left.id !== right.id) { return left.id - right.id; }
      return left.key < right.key ? -1 : (left.key > right.key ? 1 : 0);
    });
    this.messages = combined.length > MAX_INTERACTIONS
      ? combined.slice(combined.length - MAX_INTERACTIONS) : combined;
    const nextLast = this.messages.length > 0 ? this.messages[this.messages.length - 1].key : '';
    if (nextLast !== '' && nextLast !== previousLast) {
      setTimeout((): void => this.commentScroller.scrollEdge(Edge.Bottom), 40);
      if (this.isFullscreen && !this.fullscreenPanelOpen) {
        const latest = this.messages[this.messages.length - 1];
        this.fullscreenMessagePreview = `${latest.senderName}：${latest.text}`;
        if (this.fullscreenPreviewTimer !== -1) { clearTimeout(this.fullscreenPreviewTimer); }
        this.fullscreenPreviewTimer = setTimeout((): void => {
          this.fullscreenPreviewTimer = -1;
          this.fullscreenMessagePreview = '';
        }, 3200);
      }
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
    this.recovering = this.hasJoinedOnce;
    this.mediaStatus = this.hasJoinedOnce ? '正在恢复直播…' : '正在加入直播…';
    const sequence = ++this.sessionSequence;
    if (this.session !== null) {
      this.session.clearVideo();
      this.session.stop();
    }
    this.session = null;
    this.streamSignature = '';
    this.hasVideo = false;
    this.lastPartAt = 0;

    const client = getTdClient();
    const session = new TgcallsGroupSession(
      (connected: boolean): void => this.onNetworkState(session, connected),
      (): void => {},
      (streams: GroupCallStreamInfo[], unified: boolean): void => {
        if (this.isCurrent(session, sequence) && unified) {
          this.onBroadcastStreams(session, streams);
        }
      },
      (received: boolean): void => {
        if (this.isCurrent(session, sequence)) { this.onBroadcastActivity(received); }
      }
    );
    this.session = session;
    console.info(`[RtmpLiveStream] session ${sequence} start reason=${reason}`);
    session.join(client, this.groupCallId, true).then((result: TgcallsJoinResult): void => {
      if (!this.isCurrent(session, sequence)) { return; }
      if (!result.isBroadcast || !result.isUnifiedBroadcast) {
        this.mediaStatus = '直播模式已经变化，请返回后重新进入';
        this.recovering = false;
        session.stop();
        this.session = null;
        return;
      }
      this.hasJoinedOnce = true;
      this.reconnectAttempt = 0;
      this.joinedAt = Date.now();
      this.lastPartAt = Date.now();
      const joinedState = this.state;
      this.liveStore?.setStreams(result.streams);
      this.state = {
        title: joinedState.title,
        isActive: joinedState.isActive,
        isRtmpStream: true,
        isJoined: true,
        needRejoin: false,
        canSendMessages: joinedState.canSendMessages,
        areMessagesAllowed: joinedState.areMessagesAllowed,
        participantCount: joinedState.participantCount,
        streams: result.streams,
        error: ''
      };
      this.onBroadcastStreams(session, result.streams);
      this.restoreSurface();
      session.resumeMedia();
      this.recovering = false;
      this.mediaStatus = result.streams.length > 0 ? '直播播放中' : '等待主播开始推流…';
      this.refreshGroupCall('加入完成');
    }).catch((caught: Error): void => {
      if (!this.isCurrent(session, sequence)) { return; }
      session.stop();
      this.session = null;
      this.recovering = true;
      this.mediaStatus = '直播连接中断，正在重试…';
      this.reconnectAttempt += 1;
      const delay = Math.min(30000, 1000 * Math.pow(2, Math.min(this.reconnectAttempt - 1, 5)));
      this.scheduleRecovery(delay, `加入失败：${caught.message}`);
    }).finally((): void => {
      if (sequence === this.sessionSequence) { this.recoveryInFlight = false; }
    });
  }

  private isCurrent(session: TgcallsGroupSession, sequence: number): boolean {
    return this.pageActive && this.session === session && this.sessionSequence === sequence;
  }

  private onBroadcastStreams(session: TgcallsGroupSession, streams: GroupCallStreamInfo[]): void {
    if (this.session !== session) { return; }
    const streamState = this.state;
    this.liveStore?.setStreams(streams);
    this.state = {
      title: streamState.title,
      isActive: streamState.isActive,
      isRtmpStream: true,
      isJoined: true,
      needRejoin: false,
      canSendMessages: streamState.canSendMessages,
      areMessagesAllowed: streamState.areMessagesAllowed,
      participantCount: streamState.participantCount,
      streams,
      error: streamState.error
    };
    const videoChannelIds = uniqueVideoChannelIds(streams);
    this.hasVideo = videoChannelIds.length > 0;
    if (!this.hasVideo) {
      this.streamSignature = '';
      this.mediaStatus = '等待主播开始推流…';
      return;
    }
    const signature = videoChannelIds.join(',');
    if (signature === this.streamSignature) { return; }
    this.streamSignature = signature;
    const groups = `SIM=${videoChannelIds.join(',')}`;
    session.setVideoChannel('unified', 0, groups);
    this.mediaStatus = this.recovering ? '正在恢复直播…' : '直播播放中';
  }

  private onBroadcastActivity(received: boolean): void {
    if (received) {
      this.lastPartAt = Date.now();
      if (this.recovering) {
        this.recovering = false;
        this.clearRecoveryTimer();
      }
      this.mediaStatus = this.hasVideo ? '直播播放中' : '直播音频播放中';
      return;
    }
    if (this.state.streams.length > 0 && Date.now() - this.lastPartAt >= STREAM_STALL_MS) {
      this.recovering = true;
      this.mediaStatus = '直播缓冲中，正在续播…';
    }
  }

  private onNetworkState(session: TgcallsGroupSession, connected: boolean): void {
    if (this.session !== session) { return; }
    if (connected) {
      session.resumeMedia();
      this.restoreSurface();
      this.applyCurrentVideoChannel(true);
      return;
    }
    if (this.hasJoinedOnce) {
      this.recovering = true;
      this.mediaStatus = '网络波动，正在尝试续播…';
      this.scheduleRecovery(STREAM_RECONNECT_GRACE_MS, '媒体网络断开');
    }
  }

  private applyCurrentVideoChannel(force: boolean): void {
    const session = this.session;
    if (session === null) { return; }
    const streams = this.state.streams;
    const previous = this.streamSignature;
    if (force) { this.streamSignature = ''; }
    this.onBroadcastStreams(session, streams);
    if (!force) { this.streamSignature = this.streamSignature !== '' ? this.streamSignature : previous; }
  }

  private setSurface(surfaceId: string, width: number, height: number): void {
    this.surfaceBinding = { surfaceId, width, height };
    this.session?.setVideoSurface('unified', surfaceId, width, height);
  }

  private clearSurface(): void {
    this.surfaceBinding = null;
    this.session?.setVideoSurface('unified', '0');
  }

  private restoreSurface(): void {
    const binding = this.surfaceBinding;
    if (binding !== null) {
      this.session?.setVideoSurface('unified', binding.surfaceId, binding.width, binding.height);
    }
  }

  private scheduleRecovery(delayMs: number, reason: string): void {
    if (!this.pageActive || this.groupCallId <= 0 || !this.state.isActive && this.hasJoinedOnce) { return; }
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
    this.healthTimer = setInterval((): void => {
      this.refreshGroupCall('定时健康检查');
      if (!this.hasJoinedOnce || this.state.streams.length === 0) { return; }
      const reference = this.lastPartAt > 0 ? this.lastPartAt : this.joinedAt;
      if (reference > 0 && Date.now() - reference >= STREAM_STALL_MS) {
        this.recovering = true;
        this.mediaStatus = '直播流中断，正在重新同步…';
        this.session?.resumeMedia();
        this.restoreSurface();
        this.applyCurrentVideoChannel(true);
        this.scheduleRecovery(3000, '直播分片长时间无数据');
      }
    }, HEALTH_INTERVAL_MS);
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
      const next: LiveStreamState = {
        title: (groupCall['title'] as string | undefined) ?? this.state.title,
        isActive: (groupCall['is_active'] as boolean | undefined) ?? this.state.isActive,
        isRtmpStream: (groupCall['is_rtmp_stream'] as boolean | undefined) ?? true,
        isJoined: (groupCall['is_joined'] as boolean | undefined) ?? this.state.isJoined,
        needRejoin: (groupCall['need_rejoin'] as boolean | undefined) ?? this.state.needRejoin,
        canSendMessages: (groupCall['can_send_messages'] as boolean | undefined) ?? false,
        areMessagesAllowed: (groupCall['are_messages_allowed'] as boolean | undefined) ?? false,
        participantCount: (groupCall['participant_count'] as number | undefined) ??
          this.state.participantCount,
        streams: this.state.streams,
        error: this.state.error
      };
      if (this.liveStore !== null) {
        this.liveStore.applyGroupCall(groupCall);
      } else {
        this.onLiveState(next);
      }
      console.info(
        `[RtmpLiveStream] health reason=${reason} active=${next.isActive} joined=${next.isJoined} ` +
        `needRejoin=${next.needRejoin} admin=${this.canManageLive} ` +
        `canBeManaged=${canBeManaged} isOwned=${isOwned} ` +
        `lastPartAgo=${this.lastPartAt > 0 ? Date.now() - this.lastPartAt : -1}`
      );
    } catch (caught) {
      const error = caught as Error;
      console.error(`[RtmpLiveStream] health check failed reason=${reason}: ${error.message}`);
    } finally {
      this.groupCallRefreshInFlight = false;
    }
  }

  private resumeAfterForeground(): void {
    liveStreamBackgroundTask.start(getContext(this) as common.UIAbilityContext, false);
    this.session?.resumeMedia();
    this.restoreSurface();
    this.applyCurrentVideoChannel(true);
    this.refreshGroupCall('回到前台');
    if (this.hasJoinedOnce && this.state.streams.length > 0 &&
      Date.now() - this.lastPartAt >= STREAM_STALL_MS) {
      this.recovering = true;
      this.scheduleRecovery(2500, '前台恢复后直播流未恢复');
    }
  }

  private startPulse(): void {
    this.pulseTimer = setInterval((): void => {
      if (!powerFeatureEnabled(KEY_POWER_CALL_ANIMATIONS)) {
        this.pulseExpanded = false;
        return;
      }
      this.pulseExpanded = !this.pulseExpanded;
    }, 780);
  }

  private sendMessage(text?: string): void {
    const channelStore = this.channelMessageStore;
    const canSendGroupCallMessage = this.state.canSendMessages && this.state.areMessagesAllowed;
    if (this.sending || (channelStore === null && !canSendGroupCallMessage)) { return; }
    const value = (text ?? this.draft).trim();
    if (value === '') { return; }
    this.sending = true;
    const sending = channelStore !== null
      ? channelStore.sendAsync(value)
      : (this.messageStore !== null
        ? this.messageStore.send(value)
        : Promise.reject(new Error('消息通道不可用')));
    sending.then((): void => {
      if (text === undefined) { this.draft = ''; }
    }).catch((caught: Error): void => {
      promptAction.showToast({ message: `发送失败：${caught.message}`, duration: 1800 });
    }).finally((): void => {
      this.sending = false;
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
      isRtmp: true,
      title: this.state.title,
      participantCount: this.state.participantCount,
      primarySource: null
    };
    const abilityContext = getContext(this) as common.UIAbilityContext;
    const uiContext = this.getUIContext();
    this.pageActive = false;
    this.sessionSequence += 1;
    this.clearRecoveryTimer();
    if (this.session !== null) {
      this.session.clearVideo();
      this.session.stop();
      this.session = null;
    }
    if (this.isFullscreen) {
      this.isFullscreen = false;
      this.fullscreenPanelOpen = false;
      setLiveStreamFullscreen(abilityContext, false);
    }
    leaveGroupCall(getTdClient(), this.groupCallId).catch((caught: Error): void => {
      console.error(`RtmpLiveStream.minimize leave failed: ${caught.message}`);
    }).finally((): void => {
      this.leavingForFloating = true;
      floatingLiveWindow.show(uiContext, abilityContext, descriptor);
      router.back();
    });
  }

  private toggleFullscreen(): void {
    const next = !this.isFullscreen;
    this.fullscreenPanelOpen = false;
    this.fullscreenMessagePreview = '';
    this.isFullscreen = next;
    setLiveStreamFullscreen(getContext(this) as common.UIAbilityContext, next);
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

  aboutToDisappear(): void {
    if (this.isFullscreen) {
      setLiveStreamFullscreen(getContext(this) as common.UIAbilityContext, false);
    }
    this.pageActive = false;
    this.sessionSequence += 1;
    this.clearRecoveryTimer();
    if (this.healthTimer !== -1) { clearInterval(this.healthTimer); this.healthTimer = -1; }
    if (this.pulseTimer !== -1) { clearInterval(this.pulseTimer); this.pulseTimer = -1; }
    if (this.fullscreenPreviewTimer !== -1) {
      clearTimeout(this.fullscreenPreviewTimer);
      this.fullscreenPreviewTimer = -1;
    }
    if (this.offLive !== null) { this.offLive(); this.offLive = null; }
    if (this.offMessages !== null) { this.offMessages(); this.offMessages = null; }
    if (this.offMessageError !== null) { this.offMessageError(); this.offMessageError = null; }
    if (this.offChannelMessages !== null) { this.offChannelMessages(); this.offChannelMessages = null; }
    this.liveStore?.dispose();
    this.liveStore = null;
    this.messageStore?.close();
    this.messageStore = null;
    this.channelMessageStore?.close();
    this.channelMessageStore = null;
    this.groupCallMessages = [];
    this.channelMessages = [];
    if (this.session !== null) {
      this.session.clearVideo();
      this.session.stop();
      this.session = null;
    }
    this.surfaceBinding = null;
    if (!this.leavingForFloating) { liveStreamBackgroundTask.stop(); }
    if (this.groupCallId > 0 && !this.leavingForFloating) {
      leaveGroupCall(getTdClient(), this.groupCallId).catch((error: Error): void => {
        console.error(`RtmpLiveStream.leaveGroupCall failed: ${error.message}`);
      });
    }
  }

  @Builder
  header() {
    Row({ space: 12 }) {
      SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(26).fontColor([LIVE_TEXT])
        .onClick((): void => this.leave());
      Column({ space: 2 }) {
        Text(this.state.title !== '' ? this.state.title : '频道直播')
          .fontSize(17).fontWeight(FontWeight.Bold).fontColor(LIVE_TEXT)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
        Row({ space: 6 }) {
          Circle({ width: 6, height: 6 }).fill(this.state.isActive ? LIVE_RED : LIVE_SUBTEXT)
            .opacity(this.pulseExpanded ? 1 : 0.55);
          Text(this.state.isActive
            ? (this.state.participantCount > 0 ? `${this.state.participantCount} 人正在观看` : '直播中')
            : '直播已结束')
            .fontSize(12).fontColor(LIVE_SUBTEXT);
          if (this.canManageLive) {
            Text('管理员')
              .fontSize(10).fontWeight(FontWeight.Medium).fontColor(LIVE_GREEN)
              .padding({ left: 7, right: 7, top: 2, bottom: 2 })
              .backgroundColor('#2639D98A').borderRadius(8);
          }
        }
      }.layoutWeight(1).alignItems(HorizontalAlign.Start);
      Row({ space: 5 }) {
        SymbolGlyph($r('sys.symbol.eye')).fontSize(17).fontColor([LIVE_SUBTEXT]);
        Text(`${this.state.participantCount}`).fontSize(13).fontColor(LIVE_TEXT);
      }
      .padding({ left: 9, right: 10, top: 6, bottom: 6 })
      .backgroundColor(LIVE_PANEL_ALT).borderRadius(15);
      Button({ type: ButtonType.Circle }) {
        SymbolGlyph($r('sys.symbol.plus_square_on_square')).fontSize(18).fontColor([LIVE_TEXT]);
      }
      .width(36).height(36).backgroundColor(LIVE_PANEL_ALT)
      .enabled(!this.minimizeInProgress)
      .onClick((): void => this.minimizeToFloating());
    }
    .width('100%').height(56).padding({ left: 16, right: 14 })
    .alignItems(VerticalAlign.Center).backgroundColor(LIVE_BACKGROUND);
  }

  @Builder
  interactionHeader() {
    Row() {
      Column({ space: 2 }) {
        Text('直播互动').fontSize(15).fontWeight(FontWeight.Bold).fontColor(LIVE_TEXT);
        Text('频道消息与直播互动会实时出现在这里').fontSize(11).fontColor(LIVE_SUBTEXT);
      }.alignItems(HorizontalAlign.Start).layoutWeight(1);
      Row({ space: 5 }) {
        Circle({ width: 6, height: 6 }).fill(LIVE_GREEN)
          .opacity(this.pulseExpanded ? 1 : 0.48);
        Text('实时').fontSize(11).fontColor(LIVE_GREEN);
      }
      .padding({ left: 8, right: 9, top: 5, bottom: 5 })
      .backgroundColor('#2539D98A').borderRadius(12);
    }
    .width('100%').height(50).padding({ left: 14, right: 14 })
    .backgroundColor(LIVE_PANEL);
  }

  @Builder
  comments() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.messages.length === 0) {
        Column({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.message')).fontSize(32).fontColor([LIVE_SUBTEXT]);
          Text(this.chatId !== 0 ? '等待频道消息与直播互动' :
            (this.state.areMessagesAllowed ? '等待第一条互动消息' : '主播暂未开启互动消息'))
            .fontSize(13).fontColor(LIVE_SUBTEXT);
        }
      }
      List({ scroller: this.commentScroller, space: 10 }) {
        ForEach(this.messages, (message: LiveInteractionEntry) => {
          ListItem() {
            LiveCommentBubble({ message });
          }
        }, (message: LiveInteractionEntry): string => message.key)
      }
      .width('100%').height('100%')
      .padding({ left: 12, right: 14, top: 10, bottom: 10 })
      .edgeEffect(EdgeEffect.Spring)
      .scrollBar(BarState.Off)
      .onReachEnd((): void => {});
    }
    .width('100%').layoutWeight(1).backgroundColor(LIVE_PANEL);
  }

  @Builder
  composer() {
    if (this.channelMessageStore !== null ||
      (this.state.areMessagesAllowed && this.state.canSendMessages)) {
      Column({ space: 7 }) {
        Row({ space: 10 }) {
          ForEach(QUICK_REACTIONS, (emoji: string) => {
            Text(emoji).fontSize(21).textAlign(TextAlign.Center)
              .width(38).height(32).backgroundColor(LIVE_PANEL_ALT).borderRadius(16)
              .onClick((): void => this.sendMessage(emoji));
          }, (emoji: string): string => emoji)
        }
        .width('100%').padding({ left: 2 });
        Row({ space: 9 }) {
          TextInput({ text: this.draft, placeholder: '说点什么…' })
            .layoutWeight(1).height(42)
            .fontSize(15).fontColor(LIVE_TEXT).placeholderColor(LIVE_SUBTEXT)
            .backgroundColor(LIVE_PANEL_ALT).borderRadius(21)
            .padding({ left: 15, right: 15 })
            .enterKeyType(EnterKeyType.Send)
            .onChange((value: string): void => { this.draft = value; })
            .onSubmit((): void => this.sendMessage());
          Button() {
            SymbolGlyph($r('sys.symbol.paperplane')).fontSize(20).fontColor([Color.White]);
          }
          .width(42).height(42).borderRadius(21)
          .backgroundColor(this.draft.trim() === '' || this.sending ? '#40505C' : LIVE_RED)
          .enabled(this.draft.trim() !== '' && !this.sending)
          .onClick((): void => this.sendMessage());
        }.width('100%');
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 8, bottom: Math.max(9, this.bottomSafe) })
      .backgroundColor(LIVE_BACKGROUND);
    } else {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.lock_fill')).fontSize(16).fontColor([LIVE_SUBTEXT]);
        Text(this.state.areMessagesAllowed ? '当前账号暂时不能发送互动消息' : '当前没有可用的消息通道')
          .fontSize(12).fontColor(LIVE_SUBTEXT);
      }
      .width('100%').height(48 + Math.max(0, this.bottomSafe))
      .padding({ left: 16, right: 16, bottom: Math.max(0, this.bottomSafe) })
      .justifyContent(FlexAlign.Center).backgroundColor(LIVE_BACKGROUND);
    }
  }

  @Builder
  fullscreenInteractionDrawer() {
    Row() {
      Blank()
        .layoutWeight(1)
        .height('100%')
        .backgroundColor('#66000000')
        .onClick((): void => { this.fullscreenPanelOpen = false; });
      Column() {
        Row({ space: 10 }) {
          Column({ space: 2 }) {
            Text('直播互动').fontSize(17).fontWeight(FontWeight.Bold).fontColor(LIVE_TEXT);
            Text(`最近 ${this.messages.length} 条 · 消息实时更新`)
              .fontSize(11).fontColor(LIVE_SUBTEXT);
          }.alignItems(HorizontalAlign.Start).layoutWeight(1);
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.xmark')).fontSize(18).fontColor([LIVE_TEXT]);
          }
          .width(36).height(36).backgroundColor(LIVE_PANEL_ALT)
          .onClick((): void => { this.fullscreenPanelOpen = false; });
        }
        .width('100%').height(58).padding({ left: 14, right: 12 })
        .backgroundColor(LIVE_PANEL);
        this.comments();
        this.composer();
      }
      .width('84%').height('100%').constraintSize({ maxWidth: 460 })
      .backgroundColor(LIVE_PANEL)
      .shadow({ radius: 24, color: '#80000000', offsetX: -8, offsetY: 0 });
    }
    .width('100%').height('100%');
  }

  @Builder
  fullscreenVideo() {
    Stack({ alignContent: Alignment.Center }) {
      RtmpVideoStage({
        status: this.mediaStatus,
        hasVideo: this.hasVideo,
        recovering: this.recovering,
        fullscreen: true,
        pulseExpanded: this.pulseExpanded,
        onSurfaceReady: (surfaceId: string, width: number, height: number): void =>
          this.setSurface(surfaceId, width, height),
        onSurfaceGone: (): void => this.clearSurface(),
        onFullscreenToggle: (): void => this.toggleFullscreen()
      });

      Column() {
        Row({ space: 8 }) {
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(22).fontColor([Color.White]);
          }
          .width(42).height(42).backgroundColor('#A617222B')
          .onClick((): void => this.leave());
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.plus_square_on_square')).fontSize(18).fontColor([Color.White]);
          }
          .width(42).height(42).backgroundColor('#B63390EC')
          .enabled(!this.minimizeInProgress)
          .onClick((): void => this.minimizeToFloating());
          Row({ space: 6 }) {
            Circle({ width: 7, height: 7 }).fill(LIVE_RED)
              .opacity(this.pulseExpanded ? 1 : 0.55);
            Text('LIVE').fontSize(11).fontWeight(FontWeight.Bold).fontColor(Color.White);
          }
          .height(34).padding({ left: 10, right: 11 })
          .backgroundColor('#C9FF405C').borderRadius(17);
          Blank();
          Button() {
            Row({ space: 6 }) {
              SymbolGlyph($r('sys.symbol.message')).fontSize(17).fontColor([Color.White]);
              Text(`互动 ${this.messages.length}`).fontSize(13).fontColor(Color.White);
            }
          }
          .height(40).padding({ left: 12, right: 12 })
          .backgroundColor('#A617222B').borderRadius(20)
          .onClick((): void => {
            this.fullscreenMessagePreview = '';
            this.fullscreenPanelOpen = true;
            setTimeout((): void => this.commentScroller.scrollEdge(Edge.Bottom), 80);
          });
        }.width('100%');
        Blank();
        if (this.fullscreenMessagePreview !== '') {
          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.message')).fontSize(16).fontColor([LIVE_ACCENT]);
            Text(this.fullscreenMessagePreview)
              .fontSize(13).fontColor(Color.White).maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis });
          }
          .constraintSize({ maxWidth: 360 })
          .padding({ left: 12, right: 13, top: 8, bottom: 8 })
          .backgroundColor('#C914222B').borderRadius(18).alignSelf(ItemAlign.Start)
          .transition(TransitionEffect.OPACITY.animation({
            duration: powerAnimationDuration(KEY_POWER_CALL_ANIMATIONS, 180), curve: Curve.EaseOut
          }));
        }
      }
      .width('100%').height('100%')
      .padding({ left: 14, right: 14, top: this.topSafe + 10, bottom: this.bottomSafe + 14 });

      if (this.fullscreenPanelOpen) {
        this.fullscreenInteractionDrawer();
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
          RtmpVideoStage({
            status: this.mediaStatus,
            hasVideo: this.hasVideo,
            recovering: this.recovering,
            fullscreen: false,
            pulseExpanded: this.pulseExpanded,
            onSurfaceReady: (surfaceId: string, width: number, height: number): void =>
              this.setSurface(surfaceId, width, height),
            onSurfaceGone: (): void => this.clearSurface(),
            onFullscreenToggle: (): void => this.toggleFullscreen()
          });
          this.interactionHeader();
          this.comments();
          this.composer();
        }
        .width('100%').height('100%');
      }
    }
    .width('100%').height('100%').backgroundColor(LIVE_BACKGROUND)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .padding({ top: this.isFullscreen ? 0 : this.topSafe });
  }
}
