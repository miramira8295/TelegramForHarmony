import lottie, { AnimationItem } from '@ohos/lottie';
import { gunzipTgs } from '../../util/gunzipTgs';
import {
  KEY_POWER_ACTIVE, KEY_POWER_EMOJI, KEY_POWER_EMOJI_CHAT, KEY_POWER_EMOJI_REACTIONS,
  KEY_POWER_EMOJI_STATUS, KEY_POWER_STICKERS, KEY_POWER_STICKER_AUTOPLAY, KEY_POWER_STICKER_LOOP
} from '../../store/AppSettings';

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
  @Prop powerCategory: string = 'sticker';
  @StorageProp(KEY_POWER_ACTIVE) @Watch('onPowerChanged') powerSaving: boolean = false;
  @StorageProp(KEY_POWER_STICKERS) @Watch('onPowerChanged') stickersEnabled: boolean = true;
  @StorageProp(KEY_POWER_EMOJI) @Watch('onPowerChanged') emojiEnabled: boolean = true;
  @StorageProp(KEY_POWER_STICKER_AUTOPLAY) @Watch('onPowerChanged') stickerAutoplay: boolean = true;
  @StorageProp(KEY_POWER_STICKER_LOOP) @Watch('onPowerChanged') stickerLoop: boolean = true;
  @StorageProp(KEY_POWER_EMOJI_CHAT) @Watch('onPowerChanged') emojiChat: boolean = true;
  @StorageProp(KEY_POWER_EMOJI_REACTIONS) @Watch('onPowerChanged') emojiReactions: boolean = true;
  @StorageProp(KEY_POWER_EMOJI_STATUS) @Watch('onPowerChanged') emojiStatus: boolean = true;
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

  private onPowerChanged(): void {
    if (this.powerSuspended()) {
      this.stopAnim();
    } else if (this.canvasReady) {
      this.startAnimation();
    }
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
    if (this.powerSuspended()) {
      return;
    }
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
        loop: this.powerCategory === 'sticker' ? this.stickerLoop : true,
        autoplay: true,
        animationData: JSON.parse(json),
        contentMode: 'Contain'
      });
    } catch (e) {
      console.error(`TgsStickerView lottie load failed: ${e}`);
      this.failed = true;
    }
  }

  private powerSuspended(): boolean {
    if (this.powerSaving) {
      return true;
    }
    if (this.powerCategory === 'emojiStatus' || this.powerCategory === 'emoji') {
      return !this.emojiEnabled || !this.emojiStatus;
    }
    if (this.powerCategory === 'emojiReaction') {
      return !this.emojiEnabled || !this.emojiReactions;
    }
    if (this.powerCategory === 'emojiChat') {
      return !this.emojiEnabled || !this.emojiChat;
    }
    return !this.stickersEnabled || !this.stickerAutoplay;
  }

  build() {
    if (this.powerSuspended()) {
      if (this.thumbPath !== '') {
        Image(this.thumbPath.startsWith('/') ? `file://${this.thumbPath}` : this.thumbPath)
          .width(this.boxWidth).height(this.boxHeight).objectFit(ImageFit.Contain);
      } else {
        Stack().width(this.boxWidth).height(this.boxHeight);
      }
    } else if (this.failed && this.thumbPath !== '') {
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
