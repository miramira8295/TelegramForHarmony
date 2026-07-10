import { getVoicePlayback, VoiceState } from '../../services/VoicePlayback';
import { COLOR_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';

const TRACK_W: number = 110;

// Voice-note row inside a message bubble: play/pause circle + progress track +
// elapsed/total time. Subscribes to the shared player, so progress ticks
// without the LazyForEach row itself re-rendering.
@Component
export struct VoiceBubble {
  @Prop msgId: number = 0;
  @Prop durationSec: number = 0;
  @Prop isOutgoing: boolean = false;
  @Prop voicePath: string = '';   // '' while the eager download is in flight
  onNeedDownload: () => void = (): void => {};
  @State playing: boolean = false;
  @State paused: boolean = false;
  @State finished: boolean = false; // playback ran to the end → replay icon
  @State progress: number = 0; // 0..1
  @State elapsedSec: number = 0;
  private unsub: (() => void) | null = null;

  aboutToAppear(): void {
    this.unsub = getVoicePlayback().subscribe((s: VoiceState) => {
      const mine = s.playingId === this.msgId;
      this.playing = mine && !s.paused;
      this.paused = mine && s.paused;
      if (s.completedId === this.msgId) {
        this.finished = true;
      } else if (mine) {
        this.finished = false;
      }
      this.progress = mine && s.durationMs > 0 ? Math.min(1, s.positionMs / s.durationMs)
        : (this.finished ? 1 : 0);
      this.elapsedSec = mine ? Math.floor(s.positionMs / 1000) : 0;
    });
  }

  aboutToDisappear(): void {
    if (this.unsub !== null) {
      this.unsub();
      this.unsub = null;
    }
  }

  private accent(): ResourceColor {
    return this.isOutgoing ? '#5CA853' : COLOR_PRIMARY;
  }

  private timeLabel(): string {
    const total = this.formatSec(this.durationSec);
    if (this.playing || this.paused) {
      return `${this.formatSec(this.elapsedSec)} / ${total}`;
    }
    if (this.finished) {
      return `${total} / ${total}`; // ran to the end — show the full elapsed time
    }
    return total;
  }

  private formatSec(totalSeconds: number): string {
    const m = Math.floor(totalSeconds / 60);
    const s = totalSeconds % 60;
    return `${m}:${`${s}`.padStart(2, '0')}`;
  }

  private onTap(): void {
    if (this.voicePath === '') {
      this.onNeedDownload();
      return;
    }
    getVoicePlayback().toggle(this.msgId, this.voicePath, this.durationSec);
  }

  build() {
    Row({ space: 10 }) {
      Stack() {
        Circle({ width: 40, height: 40 }).fill(this.accent());
        SymbolGlyph($r(this.playing ? 'sys.symbol.pause'
          : (this.finished ? 'sys.symbol.arrow_counterclockwise' : 'sys.symbol.play_fill')))
          .fontSize(18).fontColor([Color.White]);
      }.width(40).height(40);
      Column({ space: 6 }) {
        // Progress track: full-width base line + played overlay.
        Stack({ alignContent: Alignment.Start }) {
          Column().width(TRACK_W).height(2).borderRadius(1)
            .backgroundColor(this.isOutgoing ? '#B5D9AE' : '#C4D7EE');
          Column().width(Math.max(2, TRACK_W * this.progress)).height(3).borderRadius(1.5)
            .backgroundColor(this.accent());
        }.width(TRACK_W).height(4);
        Text(this.timeLabel())
          .fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
      }.alignItems(HorizontalAlign.Start);
    }
    .alignItems(VerticalAlign.Center)
    .padding({ top: 2, bottom: 10, right: 34 })
    .onClick(() => { this.onTap(); });
  }
}
