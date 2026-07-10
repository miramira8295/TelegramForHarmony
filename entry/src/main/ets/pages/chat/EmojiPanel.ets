import { COLOR_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { StickerPicker, StickerItem } from './StickerPicker';
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

// Emoji picker panel styled after the official client: sectioned emoji grid +
// bottom Emoji / Stickers / GIFs tabs (stickers & GIFs are placeholders).
@Component
export struct EmojiPanel {
  onPick: (emoji: string) => void = (): void => {};
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
      .backgroundColor(this.tab === idx ? '#EDF3FA' : Color.Transparent)
      .borderRadius(14)
      .onClick(() => { this.tab = idx; });
  }

  build() {
    Column() {
      if (this.tab === 0) {
        Scroll() {
          Column() {
            ForEach(SECTIONS, (s: EmojiSection) => {
              Column() {
                Text(s.title)
                  .fontSize(12).fontColor(COLOR_TEXT_SECONDARY).fontWeight(FontWeight.Medium)
                  .width('100%')
                  .padding({ left: 12, top: 8, bottom: 2 });
                Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
                  ForEach(s.emoji, (e: string) => {
                    Text(e).fontSize(26).padding(5)
                      .onClick(() => { this.onPick(e); });
                  }, (e: string) => e);
                }.padding({ left: 6, right: 6 });
              }.width('100%').alignItems(HorizontalAlign.Start);
            }, (s: EmojiSection) => s.title);
          }.width('100%');
        }
        .layoutWeight(1).width('100%')
        .scrollBar(BarState.Off);
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
      .border({ width: { top: 0.7 }, color: '#EDEDED' });
    }
    .width('100%').height(300)
    .backgroundColor(Color.White);
  }
}
