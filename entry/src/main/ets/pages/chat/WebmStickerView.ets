import { IjkMediaPlayer, OnPreparedListener, OnErrorListener, OnCompletionListener } from '@ohos/ijkplayer';

let nextWebmStickerId: number = 1;
// Pre-EOF rewind: poll the position and seek to 0 this far before the end.
const LOOP_POLL_MS: number = 50;
// Keep this small: every loop cycle drops this much tail, so a large value
// visibly "speeds up" short stickers. 100ms is enough to dodge the EOF hitch
// (packet-buffering=0 does the heavy lifting).
const LOOP_REWIND_AHEAD_MS: number = 100;

// Native player setup/teardown scheduler. A sticker-grid tab switch destroys
// and creates ~15 ijkplayer instances at once; each native_setup/release is
// main-thread heavy, so running them inline freezes the UI for seconds.
// Two queues: releases run FIRST (a few per tick, so rapid tab switching
// can't pile up zombie players), inits run one per tick only once every
// pending release has been processed.
type PlayerJob = () => void;
const releaseJobs: PlayerJob[] = [];
const initJobs: PlayerJob[] = [];
let playerJobTimer: number = -1;
const PLAYER_JOB_INTERVAL_MS: number = 30;
const RELEASES_PER_TICK: number = 3;
let livePlayers: number = 0;

function runJob(job: PlayerJob): void {
  try {
    job();
  } catch (e) {
    console.error(`WebmStickerView player job failed: ${e}`);
  }
}

function pumpPlayerJobs(): void {
  if (playerJobTimer !== -1) {
    return;
  }
  playerJobTimer = setInterval(() => {
    if (releaseJobs.length > 0) {
      // Drain teardowns first — they free native resources.
      for (let i = 0; i < RELEASES_PER_TICK; i++) {
        const r = releaseJobs.shift();
        if (r === undefined) {
          break;
        }
        runJob(r);
      }
    } else {
      const init = initJobs.shift();
      if (init !== undefined) {
        runJob(init);
      }
    }
    if (releaseJobs.length === 0 && initJobs.length === 0) {
      clearInterval(playerJobTimer);
      playerJobTimer = -1;
    }
  }, PLAYER_JOB_INTERVAL_MS);
}

function enqueueRelease(job: PlayerJob): void {
  releaseJobs.push(job);
  pumpPlayerJobs();
}

function enqueueInit(job: PlayerJob): void {
  initJobs.push(job);
  pumpPlayerJobs();
}

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

  private destroyed: boolean = false;

  private release(): void {
    this.destroyed = true;
    this.stopLoopWatch();
    if (this.player !== null) {
      const p = this.player;
      this.player = null;
      // Deferred: releasing inline (e.g. a whole grid page unmounting on a
      // tab switch) serializes many native teardowns into one frame.
      enqueueRelease(() => {
        p.release();
        livePlayers--;
      });
    }
  }

  private initPlayer(context: object): void {
    if (this.destroyed || this.player !== null || this.webmPath === '') {
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
      // EOF safety net: if the pre-EOF rewind misses (longer MP4 avatar
      // loops report duration less precisely than webm stickers), restart
      // playback instead of stopping after one pass.
      const completionListener: OnCompletionListener = {
        onCompletion: (): void => {
          if (this.player !== player || this.destroyed) {
            return;
          }
          try {
            player.seekTo('0');
            player.start();
          } catch (e) {
            console.error(`WebmStickerView loop restart failed: ${e}`);
          }
        }
      };
      player.setOnCompletionListener(completionListener);
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
          // Deferred: a screenful of cells mounting together would otherwise
          // run all their native setups in the same frame.
          enqueueInit(() => {
            if (this.destroyed) {
              return; // cell died while queued (rapid tab switching)
            }
            this.initPlayer(context);
            livePlayers++;
            if (livePlayers > 24) {
              console.warn(`WebmStickerView: ${livePlayers} live players`);
            }
          });
        })
        .onDestroy(() => {
          this.release();
        });
    }
  }
}
