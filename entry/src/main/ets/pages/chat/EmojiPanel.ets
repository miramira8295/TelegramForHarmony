import { COLOR_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { StickerPicker, StickerItem, ClassicPack } from './StickerPicker';
import { GifPicker, GifItem } from './GifPicker';

interface EmojiSection {
  title: string;
  emoji: string[];
}

const SECTIONS: EmojiSection[] = [
  {
    title: '表情与人物',
    emoji: [
      '😀', '😃', '😄', '😁', '😆', '😅', '🤣', '😂', '🙂', '🙃', '😉', '😊',
      '😇', '🥰', '😍', '🤩', '😘', '😗', '☺️', '😚', '😙', '🥲', '😋', '😛',
      '😜', '🤪', '😝', '🤑', '🤗', '🤭', '🤫', '🤔', '🤐', '🤨', '😐', '😑',
      '😶', '😏', '😒', '🙄', '😬', '🤥', '😌', '😔', '😪', '🤤', '😴', '😷',
      '🤒', '🤕', '🤢', '🤮', '🤧', '🥵', '🥶', '🥴', '😵', '🤯', '🤠', '🥳',
      '🥸', '😎', '🤓', '🧐', '😕', '😟', '🙁', '☹️', '😮', '😯', '😲', '😳',
      '🥺', '😦', '😧', '😨', '😰', '😥', '😢', '😭', '😱', '😖', '😣', '😞',
      '😓', '😩', '😫', '🥱', '😤', '😡', '😠', '🤬', '😈', '👿', '💀', '☠️',
      '💩', '🤡', '👹', '👺', '👻', '👽', '👾', '🤖'
    ]
  },
  {
    title: '手势与身体',
    emoji: [
      '👋', '🤚', '🖐️', '✋', '🖖', '👌', '🤌', '🤏', '✌️', '🤞', '🤟', '🤘',
      '🤙', '👈', '👉', '👆', '🖕', '👇', '☝️', '👍', '👎', '✊', '👊', '🤛',
      '🤜', '👏', '🙌', '👐', '🤲', '🤝', '🙏', '✍️', '💅', '🤳', '💪', '🫶',
      '👀', '👁️', '👄', '🧠', '🦾', '🦵'
    ]
  },
  {
    title: '心与符号',
    emoji: [
      '❤️', '🧡', '💛', '💚', '💙', '💜', '🖤', '🤍', '🤎', '💔', '❣️', '💕',
      '💞', '💓', '💗', '💖', '💘', '💝', '💟', '💯', '💢', '💥', '💫', '💦',
      '💨', '🕳️', '💣', '💬', '💤', '🔥', '✨', '⭐', '🌟', '⚡', '☄️', '💎'
    ]
  },
  {
    title: '动物与自然',
    emoji: [
      '🐶', '🐱', '🐭', '🐹', '🐰', '🦊', '🐻', '🐼', '🐨', '🐯', '🦁', '🐮',
      '🐷', '🐸', '🐵', '🙈', '🙉', '🙊', '🐔', '🐧', '🐦', '🐤', '🦆', '🦅',
      '🦉', '🦇', '🐺', '🐗', '🐴', '🦄', '🐝', '🪲', '🦋', '🐢', '🐍', '🐙',
      '🦀', '🐬', '🐳', '🦈', '🌸', '🌹', '🌻', '🌈', '🌙', '☀️'
    ]
  },
  {
    title: '食物与活动',
    emoji: [
      '🍎', '🍊', '🍋', '🍉', '🍇', '🍓', '🍑', '🍍', '🥭', '🥑', '🍅', '🌽',
      '🍔', '🍟', '🍕', '🌭', '🥪', '🌮', '🍜', '🍣', '🍦', '🍰', '🎂', '🍫',
      '☕', '🍺', '🍷', '🥂', '⚽', '🏀', '🏈', '🎾', '🎮', '🎲', '🎯', '🎁',
      '🎉', '🎊', '🎈', '🏆', '🥇', '🚀'
    ]
  }
];

// Classic unicode sections repackaged as built-in packs for the picker.
const CLASSIC_PACKS: ClassicPack[] = SECTIONS.map((s: EmojiSection): ClassicPack => ({
  title: s.title,
  icon: s.emoji[0],
  emoji: s.emoji
}));

// Emoji picker panel styled after the official client: the emoji tab is the
// full picker (classic unicode packs + custom-emoji packs + trending + search);
// picking a custom emoji inserts its fallback unicode character.
@Component
export struct EmojiPanel {
  onPick: (emoji: string) => void = (): void => {};
  // Premium custom emoji — sent as its own animated-emoji message.
  onPickCustomEmoji: (emoji: string, customEmojiId: string) => void = (): void => {};
  onPickSticker: (s: StickerItem) => void = (): void => {};
  onPickGif: (g: GifItem) => void = (): void => {};
  @State tab: number = 0; // 0 Emoji / 1 Stickers / 2 GIFs

  @Builder
  bottomTab(label: string, idx: number) {
    Text(label)
      .fontSize(14)
      .fontWeight(this.tab === idx ? FontWeight.Bold : FontWeight.Normal)
      .fontColor(this.tab === idx ? COLOR_PRIMARY : COLOR_TEXT_SECONDARY)
      .padding({ left: 14, right: 14, top: 6, bottom: 6 })
      .backgroundColor(this.tab === idx ? $r('app.color.selected_pill') : Color.Transparent)
      .borderRadius(14)
      .onClick(() => { this.tab = idx; });
  }

  build() {
    Column() {
      if (this.tab === 0) {
        Column() {
          StickerPicker({
            stickerType: 'custom_emoji',
            includeTrending: true,
            classicPacks: CLASSIC_PACKS,
            onPick: (s: StickerItem): void => {
              if (s.customEmojiId !== '') {
                this.onPickCustomEmoji(s.emoji, s.customEmojiId);
              } else if (s.emoji !== '') {
                this.onPick(s.emoji);
              }
            }
          });
        }.layoutWeight(1).width('100%');
      } else if (this.tab === 1) {
        Column() {
          StickerPicker({ onPick: (s: StickerItem): void => { this.onPickSticker(s); } });
        }.layoutWeight(1).width('100%');
      } else {
        Column() {
          GifPicker({ onPick: (g: GifItem): void => { this.onPickGif(g); } });
        }.layoutWeight(1).width('100%');
      }
      Row({ space: 6 }) {
        this.bottomTab('Emoji', 0);
        this.bottomTab('Stickers', 1);
        this.bottomTab('GIFs', 2);
      }
      .width('100%').justifyContent(FlexAlign.Center)
      .padding({ top: 4, bottom: 6 })
      .border({ width: { top: 0.7 }, color: $r('app.color.divider') });
    }
    .width('100%').height(300)
    .backgroundColor($r('app.color.surface'));
  }
}
