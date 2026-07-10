import { IjkMediaPlayer, OnPreparedListener, OnErrorListener } from '@ohos/ijkplayer';

let nextWebmStickerId: number = 1;
// Pre-EOF rewind: poll the position and seek to 0 this far before the end.
const LOOP_POLL_MS: number = 50;
const LOOP_REWIND_AHEAD_MS: number = 250;

// Loops a Telegram WEBM (VP9) video sticker inline, muted, via ijkplayer on a
// TEXTURE XComponent (composites within ArkUI, unlike SURFACE). Falls back to
// the raster thumbnail if playback fails.
@Component
export struct WebmStickerView {
  @Prop webmPath: string;
  @Prop thumbPath: string = '';
  @Prop boxWidth: number = 160;
  @Prop boxHeight: number = 160;
  @State failed: boolean = false;
  private player: IjkMediaPlayer | null = null;
  private readonly instanceId: number = nextWebmStickerId++;
  private loopTimer: number = -1;
  private durationMs: number = 0;

  private componentId(): string {
    return `webm_sticker_${this.instanceId}`;
  }

  aboutToDisappear(): void {
    this.release();
  }

  // Seamless loop: jump back to 0 shortly BEFORE the end, so playback never
  // hits EOF — ijk's own loop path (EOF → buffering state → seek) visibly
  // hitches even with packet-buffering disabled.
  private startLoopWatch(): void {
    this.stopLoopWatch();
    this.loopTimer = setInterval(() => {
      const p = this.player;
      if (p === null || this.durationMs <= 0) {
        return;
      }
      try {
        const pos = p.getCurrentPosition();
        if (pos >= this.durationMs - LOOP_REWIND_AHEAD_MS) {
          p.seekTo('0');
        }
      } catch (e) {
        console.error(`WebmStickerView loop watch failed: ${e}`);
      }
    }, LOOP_POLL_MS);
  }

  private stopLoopWatch(): void {
    if (this.loopTimer !== -1) {
      clearInterval(this.loopTimer);
      this.loopTimer = -1;
    }
  }

  private release(): void {
    this.stopLoopWatch();
    if (this.player !== null) {
      const p = this.player;
      this.player = null;
      try {
        p.release();
      } catch (e) {
        console.error(`WebmStickerView.release failed: ${e}`);
      }
    }
  }

  private initPlayer(context: object): void {
    if (this.player !== null || this.webmPath === '') {
      return;
    }
    try {
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
          player.setVolume('0', '0'); // stickers are always silent
          player.setLoopCount(true);  // safety net if the pre-EOF rewind misses
          player.start();
          this.durationMs = Math.max(0, player.getDuration());
          this.startLoopWatch();
        }
      };
      const errorListener: OnErrorListener = {
        onError: (what: number, extra: number): void => {
          console.error(`WebmStickerView error: what=${what}, extra=${extra}`);
          this.failed = true;
        }
      };
      player.setOnPreparedListener(preparedListener);
      player.setOnErrorListener(errorListener);
      player.setMessageListener();
      player.setOptionLong(IjkMediaPlayer.OPT_CATEGORY_PLAYER, 'start-on-prepared', '0');
      // Loop-seam smoothing: without these, every loop restart re-enters ijk's
      // packet-buffering state and the seek back to 0 visibly hitches.
      player.setOptionLong(IjkMediaPlayer.OPT_CATEGORY_PLAYER, 'packet-buffering', '0');
      player.setOptionLong(IjkMediaPlayer.OPT_CATEGORY_PLAYER, 'framedrop', '1');
      player.setOptionLong(IjkMediaPlayer.OPT_CATEGORY_PLAYER, 'enable-accurate-seek', '1');
      player.setOption(IjkMediaPlayer.OPT_CATEGORY_FORMAT, 'fflags', 'fastseek');
      player.setDataSource(this.webmPath);
      player.prepareAsync();
    } catch (e) {
      console.error(`WebmStickerView.init failed: ${e}`);
      this.failed = true;
      this.release();
    }
  }

  build() {
    if (this.failed && this.thumbPath !== '') {
      Image(this.thumbPath.startsWith('/') ? `file://${this.thumbPath}` : this.thumbPath)
        .width(this.boxWidth).height(this.boxHeight).objectFit(ImageFit.Contain);
    } else {
      XComponent({ id: this.componentId(), type: XComponentType.TEXTURE, libraryname: 'ijkplayer_napi' })
        .width(this.boxWidth).height(this.boxHeight)
        .onLoad((context: object) => {
          this.initPlayer(context);
        })
        .onDestroy(() => {
          this.release();
        });
    }
  }
}
