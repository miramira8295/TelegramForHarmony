import { media } from '@kit.MediaKit';
import { fileIo as fs } from '@kit.CoreFileKit';

let nextAvLoopId: number = 1;

// Muted, seamlessly looping video via the system AVPlayer (hardware decode,
// native loop — much lighter than ijkplayer). H.264/H.265 content only; VP9
// webm still needs WebmStickerView's software decoder.
@Component
export struct AvLoopVideo {
  @Prop videoPath: string;
  @Prop boxWidth: number = 100;
  @Prop boxHeight: number = 100;
  onFailed: () => void = (): void => {};   // codec/demux failure — caller may fall back
  onWorking: () => void = (): void => {};  // first successful playback
  private player: media.AVPlayer | null = null;
  private ctrl: XComponentController = new XComponentController();
  private fd: number = -1;
  private destroyed: boolean = false;
  private readonly instanceId: number = nextAvLoopId++;

  aboutToDisappear(): void {
    this.destroyed = true;
    this.release();
  }

  private release(): void {
    const p = this.player;
    this.player = null;
    if (p !== null) {
      p.release().catch((e: Object) => {
        console.error(`AvLoopVideo.release failed: ${JSON.stringify(e)}`);
      });
    }
    if (this.fd >= 0) {
      try {
        fs.closeSync(this.fd);
      } catch (e) {
        console.error(`AvLoopVideo fd close failed: ${e}`);
      }
      this.fd = -1;
    }
  }

  private initPlayer(surfaceId: string): void {
    if (this.videoPath === '' || this.destroyed) {
      return;
    }
    media.createAVPlayer().then((p: media.AVPlayer) => {
      if (this.destroyed) {
        p.release();
        return;
      }
      this.player = p;
      p.on('stateChange', (state: string) => {
        if (this.player !== p) {
          return;
        }
        if (state === 'initialized') {
          p.surfaceId = surfaceId;
          p.prepare().catch((e: Object) => {
            console.error(`AvLoopVideo.prepare failed: ${JSON.stringify(e)}`);
            this.onFailed();
          });
        } else if (state === 'prepared') {
          p.loop = true;
          p.setVolume(0);
          p.play().catch((e: Object) => {
            console.error(`AvLoopVideo.play failed: ${JSON.stringify(e)}`);
          });
        } else if (state === 'playing') {
          console.info(`AvLoopVideo playing: ${this.videoPath}`);
          this.onWorking();
        }
      });
      p.on('error', (err: Object) => {
        console.error(`AvLoopVideo player error: ${JSON.stringify(err)}`);
        this.onFailed();
      });
      try {
        const f = fs.openSync(this.videoPath, fs.OpenMode.READ_ONLY);
        this.fd = f.fd;
        p.url = `fd://${f.fd}`;
      } catch (e) {
        console.error(`AvLoopVideo open(${this.videoPath}) failed: ${e}`);
      }
    }).catch((e: Object) => {
      console.error(`AvLoopVideo.createAVPlayer failed: ${JSON.stringify(e)}`);
    });
  }

  build() {
    XComponent({ id: `avloop_${this.instanceId}`, type: XComponentType.TEXTURE, controller: this.ctrl })
      .width(this.boxWidth).height(this.boxHeight)
      .onLoad(() => {
        console.info(`AvLoopVideo surface ready for ${this.videoPath}`);
        this.initPlayer(this.ctrl.getXComponentSurfaceId());
      })
      .onDestroy(() => {
        this.release();
      });
  }
}
