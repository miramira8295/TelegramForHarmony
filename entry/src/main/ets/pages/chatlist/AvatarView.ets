import { AVATAR_PALETTE, AVATAR_SIZE, COLOR_PRIMARY } from '../../util/theme';
import { formatTTL } from '../../util/formatTTL';
import { AvLoopVideo } from '../common/AvLoopVideo';
import { KEY_POWER_ACTIVE, KEY_POWER_AUTOPLAY_VIDEO } from '../../store/AppSettings';

@Component
export struct AvatarView {
  @Prop avatarPath: string;
  @Prop initials: string;
  @Prop colorSeed: number;
  @Prop autoDeleteTime: number = 0;
  @Prop isLive: boolean = false;
  @Prop livePulseExpanded: boolean = false;
  // Animated profile photo (MPEG4 loop). Only profile pages pass this —
  // list rows stay static (one looping player per row would be too heavy).
  @Prop animPath: string = '';
  @StorageProp(KEY_POWER_ACTIVE) powerSaving: boolean = false;
  @StorageProp(KEY_POWER_AUTOPLAY_VIDEO) autoplayVideo: boolean = true;
  avatarSize: number = AVATAR_SIZE;

  @Builder
  base() {
    if (this.animPath !== '' && this.autoplayVideo && !this.powerSaving) {
      // Animated avatars are H.264 MP4 — the system AVPlayer loops them with
      // hardware decode (far lighter than ijkplayer's software path).
      Column() {
        AvLoopVideo({
          videoPath: this.animPath,
          boxWidth: this.avatarSize,
          boxHeight: this.avatarSize
        });
      }
      .width(this.avatarSize).height(this.avatarSize)
      .borderRadius(this.avatarSize / 2)
      .clip(true);
    } else if (this.avatarPath !== '') {
      // ArkUI Image needs a file:// URI for absolute sandbox paths; TDLib
      // hands us bare filesystem paths like /data/.../photo.jpg.
      Image(this.avatarPath.startsWith('/') ? `file://${this.avatarPath}` : this.avatarPath)
        .width(this.avatarSize).height(this.avatarSize)
        .borderRadius(this.avatarSize / 2)
        .objectFit(ImageFit.Cover);
    } else {
      Stack() {
        Circle({ width: this.avatarSize, height: this.avatarSize })
          .fill(AVATAR_PALETTE[Math.abs(this.colorSeed) % AVATAR_PALETTE.length]);
        Text(this.initials)
          .fontColor(Color.White).fontSize(this.avatarSize * 0.4).fontWeight(FontWeight.Medium);
      }
      .width(this.avatarSize).height(this.avatarSize);
    }
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      this.base();
      if (this.autoDeleteTime > 0 && !this.isLive) {
        Text(formatTTL(this.autoDeleteTime))
          .fontSize(9).fontColor(Color.White).fontWeight(FontWeight.Medium)
          .textAlign(TextAlign.Center)
          .backgroundColor(COLOR_PRIMARY)
          .borderRadius(8)
          .border({ width: 1.5, color: Color.White })
          .constraintSize({ minWidth: 16 })
          .padding({ left: 3, right: 3, top: 1, bottom: 1 });
      }
      if (this.isLive) {
        Stack({ alignContent: Alignment.Center }) {
          Circle({ width: 22, height: 22 })
            .fill('#442AABEE')
            .opacity(this.livePulseExpanded ? 0.18 : 0.52)
            .scale({
              x: this.livePulseExpanded ? 1.12 : 0.92,
              y: this.livePulseExpanded ? 1.12 : 0.92
            });
          Circle({ width: 18, height: 18 })
            .fill('#F8FCFF')
            .shadow({ radius: 3, color: '#292A88C9', offsetX: 0, offsetY: 1 })
            .scale({
              x: this.livePulseExpanded ? 1.03 : 0.98,
              y: this.livePulseExpanded ? 1.03 : 0.98
            });
          Row({ space: 1.5 }) {
            Circle({ width: 2.5, height: 2.5 }).fill('#249FE8');
            Rect({ width: 2.5, height: 8, radius: 1.25 }).fill('#249FE8');
            Rect({ width: 2.5, height: 8, radius: 1.25 }).fill('#249FE8');
            Circle({ width: 2.5, height: 2.5 }).fill('#249FE8');
          }.alignItems(VerticalAlign.Center);
        }
        .width(22).height(22)
        .translate({ x: 1, y: 1 });
      }
    }
    .width(this.avatarSize).height(this.avatarSize);
  }
}
