import lottie, { AnimationItem } from '@ohos/lottie';
import { gunzipTgs } from '../../util/gunzipTgs';

// Cap on simultaneously running Lottie animations: a screenful of TGS emoji
// cells (40+) redrawing canvases every frame stutters badly. Cells over the
// cap render their static thumbnail; scrolling releases slots so fresh cells
// animate again.
const MAX_LIVE_TGS: number = 14;
let liveTgs: number = 0;

// Plays a Telegram TGS sticker (gzipped Lottie JSON) on a Canvas via
// @ohos/lottie. On any decode failure it renders the raster thumbnail instead.
// @Reusable: grid scrolling recycles cells instead of tearing down and
// re-creating the Canvas + animation pipeline each time.
@Reusable
@Component
export struct TgsStickerView {
  @Prop tgsPath: string;
  @Prop thumbPath: string = '';
  @Prop boxWidth: number = 160;
  @Prop boxHeight: number = 160;
  @State failed: boolean = false;
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private anim: AnimationItem | null = null;
  private disposed: boolean = false;
  private holdsSlot: boolean = false;
  private canvasReady: boolean = false;

  aboutToReuse(params: Record<string, Object>): void {
    const np = params['tgsPath'] as string | undefined;
    if (np !== undefined) {
      this.tgsPath = np;
    }
    const nt = params['thumbPath'] as string | undefined;
    if (nt !== undefined) {
      this.thumbPath = nt;
    }
    this.disposed = false;
    this.failed = false;
    if (this.canvasReady) {
      this.startAnimation();
    }
  }

  aboutToRecycle(): void {
    this.stopAnim();
  }

  private stopAnim(): void {
    if (this.holdsSlot) {
      liveTgs--;
      this.holdsSlot = false;
    }
    if (this.anim !== null) {
      this.anim.destroy();
      this.anim = null;
    }
  }

  aboutToDisappear(): void {
    this.disposed = true;
    this.stopAnim();
  }

  private async startAnimation(): Promise<void> {
    this.stopAnim(); // reuse path: drop the previous sticker's animation first
    if (liveTgs >= MAX_LIVE_TGS) {
      this.failed = true; // over budget — static thumbnail instead
      return;
    }
    this.holdsSlot = true;
    liveTgs++;
    const json = await gunzipTgs(this.tgsPath);
    if (this.disposed) {
      return;
    }
    if (json === '') {
      this.failed = true;
      return;
    }
    try {
      this.ctx.imageSmoothingEnabled = true;
      this.anim = lottie.loadAnimation({
        container: this.ctx,
        renderer: 'canvas', // the only supported renderer
        loop: true,
        autoplay: true,
        animationData: JSON.parse(json),
        contentMode: 'Contain'
      });
    } catch (e) {
      console.error(`TgsStickerView lottie load failed: ${e}`);
      this.failed = true;
    }
  }

  build() {
    if (this.failed && this.thumbPath !== '') {
      Image(this.thumbPath.startsWith('/') ? `file://${this.thumbPath}` : this.thumbPath)
        .width(this.boxWidth).height(this.boxHeight).objectFit(ImageFit.Contain);
    } else {
      Canvas(this.ctx)
        .width(this.boxWidth).height(this.boxHeight)
        .onReady(() => {
          this.canvasReady = true;
          this.startAnimation();
        });
    }
  }
}
