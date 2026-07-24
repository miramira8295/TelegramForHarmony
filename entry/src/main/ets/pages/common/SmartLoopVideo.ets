import { AvLoopVideo } from './AvLoopVideo';
import { WebmStickerView } from '../chat/WebmStickerView';
import {
  KEY_POWER_ACTIVE, KEY_POWER_AUTOPLAY_GIF, KEY_POWER_AUTOPLAY_VIDEO, KEY_POWER_EMOJI,
  KEY_POWER_EMOJI_CHAT, KEY_POWER_EMOJI_REACTIONS, KEY_POWER_EMOJI_STATUS,
  KEY_POWER_STICKERS, KEY_POWER_STICKER_AUTOPLAY, KEY_POWER_STICKER_LOOP
} from '../../store/AppSettings';

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
  @Prop powerCategory: string = 'sticker';
  @StorageProp(KEY_POWER_ACTIVE) powerSaving: boolean = false;
  @StorageProp(KEY_POWER_AUTOPLAY_GIF) autoplayGif: boolean = true;
  @StorageProp(KEY_POWER_AUTOPLAY_VIDEO) autoplayVideo: boolean = true;
  @StorageProp(KEY_POWER_STICKERS) stickersEnabled: boolean = true;
  @StorageProp(KEY_POWER_STICKER_AUTOPLAY) stickerAutoplay: boolean = true;
  @StorageProp(KEY_POWER_STICKER_LOOP) stickerLoop: boolean = true;
  @StorageProp(KEY_POWER_EMOJI) emojiEnabled: boolean = true;
  @StorageProp(KEY_POWER_EMOJI_CHAT) emojiChat: boolean = true;
  @StorageProp(KEY_POWER_EMOJI_REACTIONS) emojiReactions: boolean = true;
  @StorageProp(KEY_POWER_EMOJI_STATUS) emojiStatus: boolean = true;
  @State useIjk: boolean = avWebmVerdict === -1;

  private suspended(): boolean {
    if (this.powerSaving) {
      return true;
    }
    if (this.powerCategory === 'gif') {
      return !this.autoplayGif;
    }
    if (this.powerCategory === 'video') {
      return !this.autoplayVideo;
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

  private loopEnabled(): boolean {
    return this.powerCategory === 'sticker' ? this.stickerLoop : true;
  }

  build() {
    if (this.suspended()) {
      if (this.thumbPath !== '') {
        Image(this.thumbPath.startsWith('/') ? `file://${this.thumbPath}` : this.thumbPath)
          .width(this.boxWidth).height(this.boxHeight).objectFit(ImageFit.Cover);
      } else {
        Stack().width(this.boxWidth).height(this.boxHeight);
      }
    } else if (this.useIjk) {
      WebmStickerView({
        webmPath: this.videoPath, thumbPath: this.thumbPath,
        boxWidth: this.boxWidth, boxHeight: this.boxHeight,
        powerCategory: this.powerCategory
      });
    } else {
      AvLoopVideo({
        videoPath: this.videoPath,
        boxWidth: this.boxWidth, boxHeight: this.boxHeight,
        loop: this.loopEnabled(),
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
