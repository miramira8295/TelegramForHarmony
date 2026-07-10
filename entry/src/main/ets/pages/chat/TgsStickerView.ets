import lottie, { AnimationItem } from '@ohos/lottie';
import { gunzipTgs } from '../../util/gunzipTgs';

// Plays a Telegram TGS sticker (gzipped Lottie JSON) on a Canvas via
// @ohos/lottie. On any decode failure it renders the raster thumbnail instead.
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

  aboutToDisappear(): void {
    this.disposed = true;
    if (this.anim !== null) {
      this.anim.destroy();
      this.anim = null;
    }
  }

  private async startAnimation(): Promise<void> {
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
          this.startAnimation();
        });
    }
  }
}
