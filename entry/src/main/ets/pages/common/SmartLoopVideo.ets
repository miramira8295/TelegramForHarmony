import { AvLoopVideo } from './AvLoopVideo';
import { WebmStickerView } from '../chat/WebmStickerView';

// One-time probe verdict for VP9/WEBM on the system AVPlayer:
// 0 = unknown (try AVPlayer), 1 = works, -1 = unsupported (go straight to ijk).
let avWebmVerdict: number = 0;

// Looping muted video that prefers the system AVPlayer (hardware decode) and
// silently falls back to ijkplayer (ffmpeg software VP9) when the system
// codec can't handle the file. The verdict is remembered process-wide.
@Component
export struct SmartLoopVideo {
  @Prop videoPath: string;
  @Prop thumbPath: string = '';
  @Prop boxWidth: number = 160;
  @Prop boxHeight: number = 160;
  @State useIjk: boolean = avWebmVerdict === -1;

  build() {
    if (this.useIjk) {
      WebmStickerView({
        webmPath: this.videoPath, thumbPath: this.thumbPath,
        boxWidth: this.boxWidth, boxHeight: this.boxHeight
      });
    } else {
      AvLoopVideo({
        videoPath: this.videoPath,
        boxWidth: this.boxWidth, boxHeight: this.boxHeight,
        onFailed: (): void => {
          if (avWebmVerdict === 0) {
            console.warn('SmartLoopVideo: AVPlayer cannot play this webm — falling back to ijkplayer');
          }
          avWebmVerdict = -1;
          this.useIjk = true;
        },
        onWorking: (): void => {
          avWebmVerdict = 1;
        }
      });
    }
  }
}
