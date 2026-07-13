import { AVATAR_PALETTE, AVATAR_SIZE, COLOR_PRIMARY } from '../../util/theme';
import { formatTTL } from '../../util/formatTTL';
import { AvLoopVideo } from '../common/AvLoopVideo';

@Component
export struct AvatarView {
  @Prop avatarPath: string;
  @Prop initials: string;
  @Prop colorSeed: number;
  @Prop autoDeleteTime: number = 0;
  // Animated profile photo (MPEG4 loop). Only profile pages pass this —
  // list rows stay static (one looping player per row would be too heavy).
  @Prop animPath: string = '';
  avatarSize: number = AVATAR_SIZE;

  @Builder
  base() {
    if (this.animPath !== '') {
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
      if (this.autoDeleteTime > 0) {
        Text(formatTTL(this.autoDeleteTime))
          .fontSize(9).fontColor(Color.White).fontWeight(FontWeight.Medium)
          .textAlign(TextAlign.Center)
          .backgroundColor(COLOR_PRIMARY)
          .borderRadius(8)
          .border({ width: 1.5, color: Color.White })
          .constraintSize({ minWidth: 16 })
          .padding({ left: 3, right: 3, top: 1, bottom: 1 });
      }
    }
    .width(this.avatarSize).height(this.avatarSize);
  }
}
