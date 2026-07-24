import { router } from '@kit.ArkUI';
import {
  KEY_BATTERY_PERCENT,
  KEY_POWER_ACTIVE,
  KEY_POWER_AUTOPLAY_GIF,
  KEY_POWER_AUTOPLAY_VIDEO,
  KEY_POWER_CALL_ANIMATIONS,
  KEY_POWER_CHAT_EFFECTS,
  KEY_POWER_EMOJI,
  KEY_POWER_EMOJI_CHAT,
  KEY_POWER_EMOJI_REACTIONS,
  KEY_POWER_EMOJI_STATUS,
  KEY_POWER_EFFECT_BACKGROUND,
  KEY_POWER_EFFECT_BLUR,
  KEY_POWER_EFFECT_MENU,
  KEY_POWER_EFFECT_MESSAGE,
  KEY_POWER_EFFECT_REACTION,
  KEY_POWER_EFFECT_REPLY,
  KEY_POWER_PARTICLES,
  KEY_POWER_SMOOTH_TRANSITIONS,
  KEY_POWER_STICKERS,
  KEY_POWER_STICKER_AUTOPLAY,
  KEY_POWER_STICKER_LOOP,
  KEY_POWER_THRESHOLD,
  POWER_THRESHOLD_DEFAULT,
  refreshPowerSavingState,
  setBoolean,
  setNumber
} from '../../store/AppSettings';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';

const CARD_BG: ResourceColor = $r('app.color.surface');
const CARD_RADIUS: number = 14;
const THRESHOLDS: number[] = [0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100, 101];
const STICKER_KEYS: string[] = [KEY_POWER_STICKER_AUTOPLAY, KEY_POWER_STICKER_LOOP];
const EMOJI_KEYS: string[] = [KEY_POWER_EMOJI_CHAT, KEY_POWER_EMOJI_REACTIONS, KEY_POWER_EMOJI_STATUS];
const EFFECT_KEYS: string[] = [
  KEY_POWER_EFFECT_MESSAGE,
  KEY_POWER_EFFECT_REACTION,
  KEY_POWER_EFFECT_REPLY,
  KEY_POWER_EFFECT_MENU,
  KEY_POWER_EFFECT_BLUR,
  KEY_POWER_EFFECT_BACKGROUND
];

@Entry
@Component
struct PowerUsagePage {
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @StorageLink(KEY_POWER_THRESHOLD) threshold: number = POWER_THRESHOLD_DEFAULT;
  @StorageProp(KEY_POWER_ACTIVE) active: boolean = false;
  @StorageProp(KEY_BATTERY_PERCENT) batteryPercent: number = 100;
  @StorageLink(KEY_POWER_STICKERS) animatedStickers: boolean = true;
  @StorageLink(KEY_POWER_EMOJI) animatedEmoji: boolean = true;
  @StorageLink(KEY_POWER_CHAT_EFFECTS) chatEffects: boolean = true;
  @StorageLink(KEY_POWER_CALL_ANIMATIONS) callAnimations: boolean = true;
  @StorageLink(KEY_POWER_AUTOPLAY_VIDEO) autoplayVideo: boolean = true;
  @StorageLink(KEY_POWER_AUTOPLAY_GIF) autoplayGif: boolean = true;
  @StorageLink(KEY_POWER_PARTICLES) particles: boolean = true;
  @StorageLink(KEY_POWER_SMOOTH_TRANSITIONS) smoothTransitions: boolean = true;
  @StorageLink(KEY_POWER_STICKER_AUTOPLAY) stickerAutoplay: boolean = true;
  @StorageLink(KEY_POWER_STICKER_LOOP) stickerLoop: boolean = true;
  @StorageLink(KEY_POWER_EMOJI_CHAT) emojiChat: boolean = true;
  @StorageLink(KEY_POWER_EMOJI_REACTIONS) emojiReactions: boolean = true;
  @StorageLink(KEY_POWER_EMOJI_STATUS) emojiStatus: boolean = true;
  @StorageLink(KEY_POWER_EFFECT_MESSAGE) effectMessage: boolean = true;
  @StorageLink(KEY_POWER_EFFECT_REACTION) effectReaction: boolean = false;
  @StorageLink(KEY_POWER_EFFECT_REPLY) effectReply: boolean = false;
  @StorageLink(KEY_POWER_EFFECT_MENU) effectMenu: boolean = true;
  @StorageLink(KEY_POWER_EFFECT_BLUR) effectBlur: boolean = false;
  @StorageLink(KEY_POWER_EFFECT_BACKGROUND) effectBackground: boolean = false;
  @State expandedKey: string = '';

  aboutToAppear(): void {
    refreshPowerSavingState();
  }

  private thresholdIndex(): number {
    const index = THRESHOLDS.indexOf(this.threshold);
    return index >= 0 ? index : 1;
  }

  private thresholdTitle(): string {
    if (this.threshold === 0) {
      return '关闭';
    }
    if (this.threshold === 101) {
      return '始终开启';
    }
    return `低于 ${this.threshold}%`;
  }

  private thresholdDescription(): string {
    if (this.threshold === 0) {
      return '自动省电已关闭。你仍可以在下方手动关闭高耗电效果。';
    }
    if (this.threshold === 101) {
      return '省电模式始终开启，高耗电动画与自动播放会保持暂停。';
    }
    return `电池电量达到 ${this.threshold}% 或更低时，自动暂停下方高耗电功能；电量恢复后自动还原。`;
  }

  private featureValue(key: string): boolean {
    if (key === KEY_POWER_STICKERS) { return this.animatedStickers; }
    if (key === KEY_POWER_EMOJI) { return this.animatedEmoji; }
    if (key === KEY_POWER_CHAT_EFFECTS) { return this.chatEffects; }
    if (key === KEY_POWER_CALL_ANIMATIONS) { return this.callAnimations; }
    if (key === KEY_POWER_AUTOPLAY_VIDEO) { return this.autoplayVideo; }
    if (key === KEY_POWER_AUTOPLAY_GIF) { return this.autoplayGif; }
    if (key === KEY_POWER_PARTICLES) { return this.particles; }
    return this.smoothTransitions;
  }

  private subFeatureValue(key: string): boolean {
    if (key === KEY_POWER_STICKER_AUTOPLAY) { return this.stickerAutoplay; }
    if (key === KEY_POWER_STICKER_LOOP) { return this.stickerLoop; }
    if (key === KEY_POWER_EMOJI_CHAT) { return this.emojiChat; }
    if (key === KEY_POWER_EMOJI_REACTIONS) { return this.emojiReactions; }
    if (key === KEY_POWER_EMOJI_STATUS) { return this.emojiStatus; }
    if (key === KEY_POWER_EFFECT_MESSAGE) { return this.effectMessage; }
    if (key === KEY_POWER_EFFECT_REACTION) { return this.effectReaction; }
    if (key === KEY_POWER_EFFECT_REPLY) { return this.effectReply; }
    if (key === KEY_POWER_EFFECT_MENU) { return this.effectMenu; }
    if (key === KEY_POWER_EFFECT_BLUR) { return this.effectBlur; }
    return this.effectBackground;
  }

  private groupKeys(key: string): string[] {
    if (key === KEY_POWER_STICKERS) { return STICKER_KEYS; }
    if (key === KEY_POWER_EMOJI) { return EMOJI_KEYS; }
    if (key === KEY_POWER_CHAT_EFFECTS) { return EFFECT_KEYS; }
    return [];
  }

  private groupCount(key: string): number {
    return this.groupKeys(key).filter(
      (subKey: string): boolean => this.subFeatureValue(subKey)
    ).length;
  }

  private setGroup(key: string, value: boolean): void {
    setBoolean(key, value);
    for (const subKey of this.groupKeys(key)) {
      setBoolean(subKey, value);
    }
  }

  private setSubFeature(groupKey: string, key: string, value: boolean): void {
    setBoolean(key, value);
    let anyEnabled = value;
    if (!anyEnabled) {
      anyEnabled = this.groupKeys(groupKey).some(
        (subKey: string): boolean => subKey !== key && this.subFeatureValue(subKey)
      );
    }
    setBoolean(groupKey, anyEnabled);
  }

  private setThresholdIndex(index: number): void {
    const safeIndex = Math.max(0, Math.min(THRESHOLDS.length - 1, Math.round(index)));
    setNumber(KEY_POWER_THRESHOLD, THRESHOLDS[safeIndex]);
  }

  @Builder
  header() {
    Row({ space: 16 }) {
      SymbolGlyph($r('sys.symbol.chevron_left'))
        .fontSize(26).fontColor([COLOR_TEXT_PRIMARY])
        .onClick((): void => { router.back(); });
      Text('省电').fontSize(22).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY)
        .layoutWeight(1);
    }
    .width('100%').height(48).padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center);
  }

  @Builder
  modeCard() {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        Text('省电模式').fontSize(17).fontWeight(FontWeight.Bold).fontColor(COLOR_PRIMARY);
        Text(this.active ? 'ON' : 'OFF')
          .fontSize(13).fontWeight(FontWeight.Bold)
          .fontColor(this.active ? Color.White : COLOR_PRIMARY)
          .backgroundColor(this.active ? COLOR_PRIMARY : '#DCEEFF')
          .borderRadius(5).padding({ left: 7, right: 7, top: 3, bottom: 3 });
        Blank();
        Text(`当前 ${this.batteryPercent}%`)
          .fontSize(13).fontColor(this.active ? COLOR_PRIMARY : COLOR_TEXT_SECONDARY);
      }.width('100%');

      Row() {
        Text('关闭').fontSize(14)
          .fontColor(this.threshold === 0 ? COLOR_PRIMARY : COLOR_TEXT_SECONDARY);
        Blank();
        Row({ space: 5 }) {
          Text(this.thresholdTitle()).fontSize(15).fontColor(COLOR_PRIMARY);
          SymbolGlyph($r('sys.symbol.battery_100percent')).fontSize(17).fontColor([COLOR_PRIMARY]);
        }
        Blank();
        Text('开启').fontSize(14)
          .fontColor(this.threshold === 101 ? COLOR_PRIMARY : COLOR_TEXT_SECONDARY);
      }.width('100%');

      Slider({
        value: this.thresholdIndex(),
        min: 0,
        max: THRESHOLDS.length - 1,
        step: 1,
        style: SliderStyle.OutSet
      })
        .width('100%')
        .trackColor($r('app.color.divider'))
        .selectedColor(COLOR_PRIMARY)
        .blockColor(COLOR_PRIMARY)
        .onChange((value: number): void => { this.setThresholdIndex(value); });
    }
    .width('100%')
    .padding({ left: 18, right: 18, top: 15, bottom: 14 })
    .backgroundColor(CARD_BG).borderRadius(CARD_RADIUS);
  }

  @Builder
  featureRow(icon: string, title: string, key: string, total: number) {
    Row({ space: 13 }) {
      SymbolGlyph($r(icon)).fontSize(23).fontColor([COLOR_TEXT_PRIMARY]).width(30);
      Text(title).fontSize(16).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1);
      if (total > 0) {
        Row({ space: 7 }) {
          Text(`${this.groupCount(key)}/${total}`)
            .fontSize(14).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY);
          SymbolGlyph($r(this.expandedKey === key
            ? 'sys.symbol.chevron_up' : 'sys.symbol.chevron_down'))
            .fontSize(14).fontColor([COLOR_TEXT_PRIMARY]);
        }
        .height(42).padding({ left: 8, right: 8 })
        .onClick((): void => {
          this.expandedKey = this.expandedKey === key ? '' : key;
        });
        Divider().vertical(true).height(30).strokeWidth(0.7).color($r('app.color.divider'))
          .margin({ left: 2, right: 1 });
      }
      Toggle({ type: ToggleType.Switch, isOn: this.featureValue(key) })
        .selectedColor(COLOR_PRIMARY)
        .onChange((value: boolean): void => {
          if (total > 0) {
            this.setGroup(key, value);
          } else {
            setBoolean(key, value);
          }
        });
    }
    .width('100%').height(56).padding({ left: 16, right: 13 })
    .alignItems(VerticalAlign.Center);
  }

  @Builder
  subFeatureRow(groupKey: string, key: string, title: string) {
    Row({ space: 10 }) {
      Circle({ width: 5, height: 5 }).fill(COLOR_PRIMARY);
      Text(title).fontSize(14).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1);
      Toggle({ type: ToggleType.Switch, isOn: this.subFeatureValue(key) })
        .selectedColor(COLOR_PRIMARY)
        .onChange((value: boolean): void => {
          this.setSubFeature(groupKey, key, value);
        });
    }
    .width('100%').height(46)
    .padding({ left: 62, right: 13 })
    .backgroundColor($r('app.color.surface_alt'));
  }

  @Builder
  featuresCard() {
    Column() {
      Text('省电选项')
        .width('100%').fontSize(15).fontWeight(FontWeight.Medium).fontColor(COLOR_PRIMARY)
        .padding({ left: 16, right: 16, top: 13, bottom: 5 });
      this.featureRow('sys.symbol.face_smiling', '动态贴纸', KEY_POWER_STICKERS, 2);
      if (this.expandedKey === KEY_POWER_STICKERS) {
        this.subFeatureRow(KEY_POWER_STICKERS, KEY_POWER_STICKER_AUTOPLAY, '在聊天和贴纸面板中自动播放');
        Divider().strokeWidth(0.5).color($r('app.color.divider')).margin({ left: 62 });
        this.subFeatureRow(KEY_POWER_STICKERS, KEY_POWER_STICKER_LOOP, '循环播放动态贴纸');
      }
      Divider().strokeWidth(0.7).color($r('app.color.divider')).margin({ left: 58 });
      this.featureRow('sys.symbol.face_smiling_fill', '动态表情', KEY_POWER_EMOJI, 3);
      if (this.expandedKey === KEY_POWER_EMOJI) {
        this.subFeatureRow(KEY_POWER_EMOJI, KEY_POWER_EMOJI_CHAT, '聊天消息中的动态表情');
        Divider().strokeWidth(0.5).color($r('app.color.divider')).margin({ left: 62 });
        this.subFeatureRow(KEY_POWER_EMOJI, KEY_POWER_EMOJI_REACTIONS, '消息回应中的动态表情');
        Divider().strokeWidth(0.5).color($r('app.color.divider')).margin({ left: 62 });
        this.subFeatureRow(KEY_POWER_EMOJI, KEY_POWER_EMOJI_STATUS, '个人资料和标题栏状态表情');
      }
      Divider().strokeWidth(0.7).color($r('app.color.divider')).margin({ left: 58 });
      this.featureRow('sys.symbol.message', '聊天中的特效', KEY_POWER_CHAT_EFFECTS, 6);
      if (this.expandedKey === KEY_POWER_CHAT_EFFECTS) {
        this.subFeatureRow(KEY_POWER_CHAT_EFFECTS, KEY_POWER_EFFECT_MESSAGE, '新消息出现动画');
        Divider().strokeWidth(0.5).color($r('app.color.divider')).margin({ left: 62 });
        this.subFeatureRow(KEY_POWER_CHAT_EFFECTS, KEY_POWER_EFFECT_REACTION, '消息回应动画');
        Divider().strokeWidth(0.5).color($r('app.color.divider')).margin({ left: 62 });
        this.subFeatureRow(KEY_POWER_CHAT_EFFECTS, KEY_POWER_EFFECT_REPLY, '回复与转发动效');
        Divider().strokeWidth(0.5).color($r('app.color.divider')).margin({ left: 62 });
        this.subFeatureRow(KEY_POWER_CHAT_EFFECTS, KEY_POWER_EFFECT_MENU, '菜单和面板动效');
        Divider().strokeWidth(0.5).color($r('app.color.divider')).margin({ left: 62 });
        this.subFeatureRow(KEY_POWER_CHAT_EFFECTS, KEY_POWER_EFFECT_BLUR, '模糊与缩放效果');
        Divider().strokeWidth(0.5).color($r('app.color.divider')).margin({ left: 62 });
        this.subFeatureRow(KEY_POWER_CHAT_EFFECTS, KEY_POWER_EFFECT_BACKGROUND, '聊天背景动态效果');
      }
      Divider().strokeWidth(0.7).color($r('app.color.divider')).margin({ left: 58 });
      this.featureRow('sys.symbol.phone', '通话中的动画', KEY_POWER_CALL_ANIMATIONS, 0);
      Divider().strokeWidth(0.7).color($r('app.color.divider')).margin({ left: 58 });
      this.featureRow('sys.symbol.play_fill', '自动播放视频', KEY_POWER_AUTOPLAY_VIDEO, 0);
      Divider().strokeWidth(0.7).color($r('app.color.divider')).margin({ left: 58 });
      this.featureRow('sys.symbol.video', '自动播放 GIF', KEY_POWER_AUTOPLAY_GIF, 0);
      Divider().strokeWidth(0.7).color($r('app.color.divider')).margin({ left: 58 });
      this.featureRow('sys.symbol.gift', '粒子效果', KEY_POWER_PARTICLES, 0);
    }
    .width('100%').backgroundColor(CARD_BG).borderRadius(CARD_RADIUS)
    .padding({ bottom: 4 });
  }

  @Builder
  smoothCard() {
    Row({ space: 12 }) {
      Text('启用平滑过渡').fontSize(16).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1);
      Toggle({ type: ToggleType.Switch, isOn: this.smoothTransitions })
        .selectedColor(COLOR_PRIMARY)
        .onChange((value: boolean): void => {
          setBoolean(KEY_POWER_SMOOTH_TRANSITIONS, value);
        });
    }
    .width('100%').height(58).padding({ left: 18, right: 13 })
    .backgroundColor(CARD_BG).borderRadius(CARD_RADIUS);
  }

  build() {
    Column() {
      this.header();
      Scroll() {
        Column({ space: 12 }) {
          this.modeCard();
          Text(this.thresholdDescription())
            .fontSize(13).fontColor(COLOR_TEXT_SECONDARY).width('100%')
            .padding({ left: 15, right: 15 });
          this.featuresCard();
          this.smoothCard();
          Text('关闭后，应用不同页面和区域之间将不再使用平滑动画。')
            .fontSize(13).fontColor(COLOR_TEXT_SECONDARY).width('100%')
            .padding({ left: 15, right: 15 });
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 8, bottom: this.bottomSafe + 24 });
      }
      .layoutWeight(1).width('100%').scrollBar(BarState.Off);
    }
    .width('100%').height('100%')
    .backgroundColor($r('app.color.page_bg'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .padding({ top: this.topSafe });
  }
}
