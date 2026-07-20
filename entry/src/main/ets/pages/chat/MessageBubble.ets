import { MessageEntry, ReactionInfo, InlineBtn } from '../../store/MessageEntry';
import { TdObject } from '../../tdkit/TdTypes';
import { AvatarView } from '../chatlist/AvatarView';
import {
  KEY_TEXT_SIZE, KEY_BUBBLE_RADIUS, KEY_REDUCE_ANIM, TEXT_SIZE_DEFAULT, RADIUS_DEFAULT
} from '../../store/AppSettings';
import { TgsStickerView } from './TgsStickerView';
import { WebmStickerView } from './WebmStickerView';
import { SmartLoopVideo } from '../common/SmartLoopVideo';
import { VoiceBubble } from './VoiceBubble';
import { formatTime } from '../../util/formatTime';
import { formatFileSize } from '../../util/formatFileSize';
import { parseFormattedText, RichSegment, RichRun } from '../../util/richText';
import { packAlbumRows, AlbumCell } from '../../util/packAlbumRows';
import { COLOR_PRIMARY, COLOR_TEXT_SECONDARY, COLOR_BUBBLE_OUT, COLOR_BUBBLE_IN, COLOR_BUBBLE_TEXT, AVATAR_PALETTE, botButtonBg } from '../../util/theme';

const ALBUM_MAX_WIDTH: number = 280;
const STICKER_MAX: number = 160;
const MEDIA_MAX_WIDTH: number = 280;
const MEDIA_MAX_HEIGHT_RATIO: number = 1.2;
const LINK_PREVIEW_HEIGHT_RATIO: number = 0.62;
// Quick reactions shown in the long-press menu's top row (tap the chevron to
// open the full emoji picker).
const QUICK_REACTIONS: string[] = ['❤️', '👍', '👎', '🔥', '🥰', '👏'];

interface MediaBox {
  width: number;
  height: number;
}

@Component
export struct MessageBubble {
  @Prop msg: MessageEntry;
  @Prop nowSec: number;
  @Prop isGroup: boolean;
  @Prop isChannel: boolean;
  @Prop showUnreadDivider: boolean;
  @Prop dateLabel: string = ''; // date pill above this row when the day changes
  @Prop albumPaths: string[];
  @Prop albumRatios: number[];
  @Prop albumMemberIds: number[];
  @Prop albumIsVideo: boolean[];
  @Prop albumProgress: number[];
  @Prop albumCaption: string;
  albumCaptionEntities: TdObject[] = [];
  @StorageProp('screenWidthVp') screenW: number = 360;
  // Measured width of the bubble (it shrinks to fit content) — the inline
  // keyboard below matches it exactly instead of the theoretical max width.
  @State bubbleW: number = 0;
  // x/y are the tap's window coordinates (vp) — the fullscreen viewer uses them
  // as the anchor for its expand-from-tap / shrink-back-to-tap transition.
  onMediaTap: (messageId: number, x: number, y: number) => void = (): void => {};
  onLinkTap: (url: string) => void = (): void => {};
  onCommentTap: (messageId: number) => void = (): void => {};
  onBotCallback: (messageId: number, data: string) => void = (): void => {};
  onAvatarTap: (userId: number) => void = (): void => {};
  onReplyTap: (messageId: number) => void = (): void => {};
  onFileTap: (messageId: number) => void = (): void => {};
  onFileSave: (messageId: number) => void = (): void => {};
  onVoiceTap: (messageId: number) => void = (): void => {};
  // Long-press context menu actions.
  onSetReaction: (messageId: number, emoji: string, isChosen: boolean) => void = (): void => {};
  onReplyTo: (messageId: number) => void = (): void => {};
  onCopyText: (messageId: number) => void = (): void => {};
  onCopyLink: (messageId: number) => void = (): void => {};
  onForwardMsg: (messageId: number) => void = (): void => {};
  onReportMsg: (messageId: number) => void = (): void => {};
  onSelectMsg: (messageId: number) => void = (): void => {};
  // "转发自 X" tapped: (originChatId, originMsgId, originUserId) — chat ids for a
  // channel/chat origin, user id for a user origin.
  onForwardTap: (chatId: number, messageId: number, userId: number) => void = (): void => {};
  onOpenReactions: (messageId: number) => void = (): void => {};
  // Chat's currently active video chat, if any (0 = none live) — lets a
  // "started" system pill know whether it's still tappable, and supplies the
  // id to hand off on tap. Sourced from ChatPage's existing updateChatVideoChat
  // subscription (see liveGroupCallId there) rather than re-subscribing here.
  @Prop liveGroupCallId: number = 0;
  onLiveStreamTap: (groupCallId: number) => void = (): void => {};
  // Live arrival: slide the bubble in from below (never set for history rows).
  @Prop animateIn: boolean = false;
  // 聊天设置 → 消息字号 / 消息圆角, applied live.
  @StorageProp(KEY_TEXT_SIZE) msgTextSize: number = TEXT_SIZE_DEFAULT;
  @StorageProp(KEY_BUBBLE_RADIUS) bubbleRadius: number = RADIUS_DEFAULT;
  @StorageProp(KEY_REDUCE_ANIM) reduceAnim: boolean = false;
  @Prop showAvatar: boolean = true;     // last row of a same-sender run
  @Prop showSenderName: boolean = true; // first row of a same-sender run

  // mm:ss (or h:mm:ss for long videos) duration badge text.
  private formatDuration(totalSeconds: number): string {
    const h = Math.floor(totalSeconds / 3600);
    const m = Math.floor((totalSeconds % 3600) / 60);
    const s = totalSeconds % 60;
    const mm = h > 0 ? `${m}`.padStart(2, '0') : `${m}`;
    const ss = `${s}`.padStart(2, '0');
    return h > 0 ? `${h}:${mm}:${ss}` : `${mm}:${ss}`;
  }

  // Concrete pixel caps for text. Percentage widths ('100%') don't resolve inside
  // a shrink-to-fit bubble (maxWidth:'78%' with no definite width), so text falls
  // back to its intrinsic width and overflows. A concrete maxWidth forces wrapping.
  private inlineMaxW(): number {
    return this.screenW * 0.78 - 32;
  }

  // The link preview card adds its own 8+8 horizontal padding on top of the
  // bubble's, so content inside it needs a narrower cap than inlineMaxW().
  private cardMaxW(): number {
    return this.inlineMaxW() - 16;
  }

  private mediaThumbW(): number {
    return Math.min(MEDIA_MAX_WIDTH, this.inlineMaxW());
  }

  private mediaMaxH(): number {
    return this.mediaThumbW() * MEDIA_MAX_HEIGHT_RATIO;
  }

  private mediaRatio(): number {
    if (this.msg.photoWidth > 0 && this.msg.photoHeight > 0) {
      return this.msg.photoWidth / this.msg.photoHeight;
    }
    return 1;
  }

  private mediaBox(): MediaBox {
    const maxW = this.mediaThumbW();
    const maxH = this.mediaMaxH();
    const ratio = this.mediaRatio();
    let width = maxW;
    let height = width / ratio;
    if (height > maxH) {
      height = maxH;
      width = height * ratio;
    }
    return { width, height };
  }

  private linkPreviewH(): number {
    return this.cardMaxW() * LINK_PREVIEW_HEIGHT_RATIO;
  }

  private albumW(): number {
    return Math.min(ALBUM_MAX_WIDTH, this.inlineMaxW());
  }

  // Per-sender name color, matching the sender's avatar color (same hash/palette
  // as AvatarView) so a user's name and avatar are visually tied together.
  private senderColor(): ResourceColor {
    return AVATAR_PALETTE[Math.abs(this.msg.senderId) % AVATAR_PALETTE.length];
  }

  @Builder
  statusIcon() {
    if (this.msg.sendState === 'sending') {
      SymbolGlyph($r('sys.symbol.clock')).fontSize(12).fontColor([COLOR_TEXT_SECONDARY]);
    } else if (this.msg.sendState === 'sent') {
      SymbolGlyph($r('sys.symbol.checkmark')).fontSize(12).fontColor([COLOR_TEXT_SECONDARY]);
    } else if (this.msg.sendState === 'read') {
      // Double check: two overlapped checkmarks.
      Row() {
        SymbolGlyph($r('sys.symbol.checkmark')).fontSize(12).fontColor([COLOR_PRIMARY]);
        SymbolGlyph($r('sys.symbol.checkmark')).fontSize(12).fontColor([COLOR_PRIMARY])
          .margin({ left: -8 });
      }
    } else if (this.msg.sendState === 'failed') {
      SymbolGlyph($r('sys.symbol.exclamationmark_circle')).fontSize(12).fontColor([Color.Red]);
    }
  }

  // Invisible tail appended to the last text line: reserves exactly the space
  // the overlaid timestamp occupies, so it never covers real text (Telegram's
  // inline-time layout).
  private timeReserve(): string {
    return `  ${formatTime(this.msg.date, this.nowSec)}${this.msg.isOutgoing ? '   ' : ''}`;
  }

  @Builder
  richRuns(runs: RichRun[], maxWidth: number, reserveTail: boolean) {
    Text() {
      ForEach(runs, (r: RichRun) => {
        Span(r.text)
          .fontWeight(r.bold ? FontWeight.Bold : FontWeight.Normal)
          .fontStyle(r.italic ? FontStyle.Italic : FontStyle.Normal)
          .fontColor(r.link ? COLOR_PRIMARY : COLOR_BUBBLE_TEXT)
          .onClick(r.url !== '' ? (() => { this.onLinkTap(r.url); }) : undefined);
      }, (r: RichRun, i: number) => `run_${i}_${r.text}`);
      if (reserveTail) {
        // fontSize 14 (not 11): when this reserve wraps onto its own line, the
        // taller line leaves a visible gap between the text and the timestamp.
        Span(this.timeReserve()).fontSize(14).fontColor(Color.Transparent);
      }
    }.fontSize(16).constraintSize({ maxWidth });
  }

  // Render TDLib formatted text: inline bold/link runs, pre/code blocks and
  // blockquotes as gray boxes. maxWidth is the caller's available content
  // width (narrower inside nested cards like the link preview). reserveTail
  // pads the final text line for the inline timestamp overlay.
  @Builder
  richContent(text: string, entities: TdObject[], maxWidth: number, reserveTail: boolean) {
    Column() {
      ForEach(parseFormattedText(text, entities), (seg: RichSegment, segIdx: number) => {
        if (seg.kind === 'pre') {
          Column() {
            Text(seg.text).fontSize(14).fontColor(COLOR_BUBBLE_TEXT).fontFamily('monospace')
              .constraintSize({ maxWidth: maxWidth - 20 }).wordBreak(WordBreak.BREAK_ALL);
          }
          .backgroundColor($r('app.color.surface_alt')).borderRadius(6)
          .padding(8).margin({ top: 4, bottom: 2 });
        } else if (seg.kind === 'quote') {
          Column() {
            // Span-based rendering keeps links inside the quote tappable.
            Text() {
              ForEach(seg.runs, (r: RichRun) => {
                Span(r.text)
                  .fontWeight(r.bold ? FontWeight.Bold : FontWeight.Normal)
                  .fontStyle(r.italic ? FontStyle.Italic : FontStyle.Normal)
                  .fontColor(r.link ? COLOR_PRIMARY : COLOR_BUBBLE_TEXT)
                  .onClick(r.url !== '' ? (() => { this.onLinkTap(r.url); }) : undefined);
              }, (r: RichRun, i: number) => `qrun_${i}_${r.text}`);
            }
            .fontSize(this.msgTextSize)
            .constraintSize({ maxWidth: maxWidth - 20 }).wordBreak(WordBreak.BREAK_ALL);
          }
          .backgroundColor($r('app.color.surface_alt')).borderRadius(6)
          .border({ width: { left: 3 }, color: COLOR_PRIMARY })
          .padding({ left: 8, right: 8, top: 6, bottom: 6 }).margin({ top: 4, bottom: 2 });
        } else {
          this.richRuns(seg.runs, maxWidth,
            reserveTail && segIdx === parseFormattedText(text, entities).length - 1);
        }
      }, (seg: RichSegment, i: number) => `seg_${i}_${seg.kind}`);
    }.alignItems(HorizontalAlign.Start);
  }

  // Channel post footer: recent-commenter avatars + comment count + chevron,
  // tapping opens the linked discussion group's thread for this post.
  @Builder
  commentsRow() {
    Row({ space: 6 }) {
      if (this.msg.commentReplierIds.length > 0) {
        Row() {
          ForEach(this.msg.commentReplierIds, (uid: number, idx: number) => {
            AvatarView({
              avatarPath: idx < this.msg.commentReplierAvatarPaths.length ? this.msg.commentReplierAvatarPaths[idx] : '',
              initials: '?', colorSeed: uid, avatarSize: 22
            }).margin({ left: idx === 0 ? 0 : -8 }).border({ width: 1.5, color: Color.White });
          }, (uid: number, idx: number) => `replier_${idx}_${uid}`);
        }
      }
      Text(`${this.msg.commentCount} 条评论`).fontSize(13).fontColor(COLOR_PRIMARY).fontWeight(FontWeight.Medium);
      SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(13).fontColor([COLOR_PRIMARY]);
    }
    .constraintSize({ maxWidth: this.inlineMaxW() })
    .border({ width: { top: 1 }, color: '#00000014' })
    .padding({ top: 6 }).margin({ top: 6 })
    .onClick(() => { this.onCommentTap(this.msg.id); });
  }

  // Bot inline keyboard rendered below the bubble: translucent rounded buttons,
  // equal widths per row (Telegram style). URL buttons open links; callback
  // buttons send the payload back to the bot.
  @Builder
  inlineKeyboard() {
    Row() {
      Column({ space: 4 }) {
        ForEach(this.msg.inlineButtons, (row: InlineBtn[], rowIdx: number) => {
          Row({ space: 4 }) {
            ForEach(row, (btn: InlineBtn, btnIdx: number) => {
              Text(btn.text)
                .fontSize(14).fontColor(Color.White).fontWeight(FontWeight.Medium)
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                .textAlign(TextAlign.Center)
                .layoutWeight(1).height(36)
                .backgroundColor(botButtonBg(btn.style, '#4d000000'))
                .borderRadius(8)
                .onClick(() => {
                  if (btn.url !== '') {
                    this.onLinkTap(btn.url);
                  } else if (btn.callbackData !== '') {
                    this.onBotCallback(this.msg.id, btn.callbackData);
                  }
                });
            }, (btn: InlineBtn, btnIdx: number) => `ib_${rowIdx}_${btnIdx}_${btn.text}`);
          }.width('100%');
        }, (_row: InlineBtn[], rowIdx: number) => `ibrow_${rowIdx}`);
      }
      // Match the bubble's MEASURED width (it shrinks to fit its content), so
      // the keyboard is never wider than the bubble above it.
      .width(this.bubbleW > 0 ? this.bubbleW : this.inlineMaxW() + 16);
    }
    .width('100%')
    .padding({
      // Align with the bubble's edge, not the tail tip: the tail adds 7vp
      // before an incoming bubble / after an outgoing one.
      left: 10 + (this.msg.isOutgoing ? 0 : (this.isGroup ? 38 : 0) + 7),
      right: 10 + (this.msg.isOutgoing ? 7 : 0),
      top: 2, bottom: 2
    })
    .justifyContent(this.msg.isOutgoing ? FlexAlign.End : FlexAlign.Start);
  }

  // Loading ring shown centered on a media placeholder while its thumbnail
  // downloads — same style as the fullscreen viewer's (percent inside the ring).
  @Builder
  loadingRing(size: number, percent: number) {
    Stack() {
      Progress({ value: percent, total: 100, type: ProgressType.Ring })
        .width(size).height(size).color(Color.White);
      Text(`${percent}%`).fontSize(Math.max(9, size * 0.24)).fontColor(Color.White);
    }
    .padding(6)
    .backgroundColor('#00000066')
    .borderRadius(size);
  }

  // Centered play-triangle badge, overlaid on video thumbnails.
  @Builder
  playBadge(size: number) {
    Stack() {
      Circle({ width: size, height: size }).fill('#6B728099');
      SymbolGlyph($r('sys.symbol.play_fill')).fontSize(size * 0.42).fontColor([Color.White]).margin({ left: 2 });
    }.width(size).height(size);
  }

  // Masonry album grid: each row is scaled to fill the media width while preserving
  // every photo's own aspect ratio (rows vary in height), instead of a uniform
  // square grid that crops everything to 1:1. Video members get a play badge;
  // tapping any cell opens the fullscreen viewer for that specific message.
  @Builder
  albumGrid() {
    Column({ space: 2 }) {
      ForEach(packAlbumRows(this.albumRatios, this.albumW()), (row: AlbumCell[], rowIdx: number) => {
        Row({ space: 2 }) {
          ForEach(row, (cell: AlbumCell) => {
            Stack() {
              if (this.albumPaths[cell.idx] !== '') {
                Image(this.albumPaths[cell.idx].startsWith('/') ? `file://${this.albumPaths[cell.idx]}` : this.albumPaths[cell.idx])
                  .width(cell.width).height(cell.height).borderRadius(4).objectFit(ImageFit.Cover);
              } else {
                Column().width(cell.width).height(cell.height).borderRadius(4).backgroundColor('#E0E0E0');
                if (this.albumPaths[cell.idx] === '') {
                  this.loadingRing(Math.min(32, Math.min(cell.width, cell.height) * 0.4), this.albumProgress[cell.idx] ?? 0);
                }
              }
              if (this.albumIsVideo[cell.idx]) {
                this.playBadge(Math.min(40, Math.min(cell.width, cell.height) * 0.46));
              }
            }
            .width(cell.width).height(cell.height)
            .onClick((e: ClickEvent) => { this.onMediaTap(this.albumMemberIds[cell.idx], e.windowX, e.windowY); });
          }, (cell: AlbumCell) => `cell_${cell.idx}`);
        }
      }, (_row: AlbumCell[], rowIdx: number) => `row_${rowIdx}`);
    }.alignItems(HorizontalAlign.Start).width(this.albumW()).constraintSize({ maxWidth: this.albumW() });
  }

  // URL / message-link preview card (TDLib messageText.link_preview): accent
  // left border, site name, title, description, optional photo, tap to open.
  @Builder
  linkPreviewCard() {
    Column() {
      if (this.msg.linkSiteName !== '') {
        Text(this.msg.linkSiteName).fontSize(13).fontColor(COLOR_PRIMARY).fontWeight(FontWeight.Bold);
      }
      if (this.msg.linkTitle !== '') {
        Text(this.msg.linkTitle).fontSize(14).fontColor(COLOR_BUBBLE_TEXT).fontWeight(FontWeight.Bold)
          .margin({ top: 2 }).constraintSize({ maxWidth: this.cardMaxW() });
      }
      if (this.msg.linkDescription !== '') {
        // Plain text, not richContent: entities inside a preview description
        // (e.g. an @mention) must not be individually tappable — the whole
        // card is one tap target, so a stray link inside the text can't hijack it.
        Text(this.msg.linkDescription).fontSize(14).fontColor(COLOR_BUBBLE_TEXT)
          .margin({ top: 2 }).constraintSize({ maxWidth: this.cardMaxW() });
      }
      if (this.msg.linkPhotoFileId !== 0) {
        if (this.msg.linkPhotoPath !== '') {
          Image(this.msg.linkPhotoPath.startsWith('/') ? `file://${this.msg.linkPhotoPath}` : this.msg.linkPhotoPath)
            .width(this.cardMaxW()).height(this.linkPreviewH()).borderRadius(6).objectFit(ImageFit.Cover)
            .margin({ top: 4 });
        } else {
          Column().width(this.cardMaxW()).height(this.linkPreviewH()).borderRadius(6).backgroundColor('#E0E0E0').margin({ top: 4 });
        }
      }
      Text('查看消息').fontSize(13).fontColor(COLOR_PRIMARY).fontWeight(FontWeight.Medium).margin({ top: 6 });
    }
    .alignItems(HorizontalAlign.Start)
    .constraintSize({ maxWidth: this.inlineMaxW() })
    .backgroundColor('#F2EFE9').borderRadius(8)
    .border({ width: { left: 3 }, color: COLOR_PRIMARY })
    .padding({ left: 8, right: 8, top: 6, bottom: 6 }).margin({ top: 4 })
    .onClick(() => { this.onLinkTap(this.msg.linkUrl); });
  }

  // Emoji reaction pills (👍 3, ❤️ 2, ...), highlighted when the current user
  // has picked that reaction.
  @Builder
  reactionsRow() {
    Flex({ wrap: FlexWrap.Wrap }) {
      ForEach(this.msg.reactions, (r: ReactionInfo) => {
        Row({ space: 4 }) {
          Text(r.emoji).fontSize(13);
          Text(`${r.count}`).fontSize(12).fontColor(r.isChosen ? Color.White : COLOR_TEXT_SECONDARY);
        }
        .backgroundColor(r.isChosen ? COLOR_PRIMARY : '#00000010')
        .borderRadius(11).padding({ left: 8, right: 8, top: 3, bottom: 3 })
        .margin({ right: 4, top: 4 });
      }, (r: ReactionInfo) => `rx_${r.emoji}`);
    }.constraintSize({ maxWidth: this.inlineMaxW() }).margin({ top: 4 });
  }

  private reactionChosen(emoji: string): boolean {
    for (const r of this.msg.reactions) {
      if (r.emoji === emoji) {
        return r.isChosen;
      }
    }
    return false;
  }

  @Builder
  menuRow(icon: string, label: string, danger: boolean, onTap: () => void) {
    Row({ space: 14 }) {
      SymbolGlyph($r(icon)).fontSize(19).fontColor([danger ? '#FF3B30' : COLOR_BUBBLE_TEXT]);
      Text(label).fontSize(16).fontColor(danger ? '#FF3B30' : COLOR_BUBBLE_TEXT).layoutWeight(1);
    }
    .width('100%').padding({ left: 16, right: 16, top: 11, bottom: 11 })
    .alignItems(VerticalAlign.Center)
    .onClick(onTap);
  }

  // Long-press context menu: quick-reaction row (tap an emoji to toggle it, the
  // chevron opens the full picker) over the standard message actions.
  @Builder
  msgContextMenu() {
    Column() {
      Row({ space: 2 }) {
        ForEach(QUICK_REACTIONS, (e: string) => {
          Text(e).fontSize(24)
            .padding({ left: 3, right: 3, top: 4, bottom: 4 })
            .onClick(() => { this.onSetReaction(this.msg.id, e, this.reactionChosen(e)); });
        }, (e: string) => e);
        Blank();
        // Round "expand" button → opens the full emoji reaction picker.
        Row() {
          SymbolGlyph($r('sys.symbol.chevron_down')).fontSize(15).fontColor([COLOR_BUBBLE_TEXT]);
        }
        .width(30).height(30).borderRadius(15).backgroundColor('#0000000F')
        .justifyContent(FlexAlign.Center)
        .onClick(() => { this.onOpenReactions(this.msg.id); });
      }
      .width('100%').padding({ left: 12, right: 10, top: 8, bottom: 8 })
      .alignItems(VerticalAlign.Center);
      Divider().color($r('app.color.divider')).strokeWidth(0.7);
      this.menuRow('sys.symbol.arrowshape_turn_up_left', '回复', false, () => { this.onReplyTo(this.msg.id); });
      this.menuRow('sys.symbol.plus_square_on_square', '复制文本', false, () => { this.onCopyText(this.msg.id); });
      this.menuRow('sys.symbol.link', '拷贝消息链接', false, () => { this.onCopyLink(this.msg.id); });
      this.menuRow('sys.symbol.arrowshape_turn_up_right', '转发', false, () => { this.onForwardMsg(this.msg.id); });
      this.menuRow('sys.symbol.exclamationmark_circle', '举报', true, () => { this.onReportMsg(this.msg.id); });
      this.menuRow('sys.symbol.checkmark_circle', '选择', false, () => { this.onSelectMsg(this.msg.id); });
    }
    .width(262)
    .padding({ top: 6, bottom: 6 });
  }

  @Builder
  content() {
    if (this.msg.replyText !== '') {
      Column() {
        Text(this.msg.replySenderName).fontSize(12).fontColor(COLOR_PRIMARY).maxLines(1)
          .constraintSize({ maxWidth: this.inlineMaxW() }).textOverflow({ overflow: TextOverflow.Ellipsis });
        Text(this.msg.replyText).fontSize(12).fontColor(COLOR_TEXT_SECONDARY).maxLines(1)
          .constraintSize({ maxWidth: this.inlineMaxW() }).textOverflow({ overflow: TextOverflow.Ellipsis });
      }
      .alignItems(HorizontalAlign.Start)
      .border({ width: { left: 2 }, color: COLOR_PRIMARY })
      .padding({ left: 6, top: 2, bottom: 2 }).margin({ bottom: 4 })
      // Tap the quote → jump to the original message.
      .onClick(() => {
        if (this.msg.replyToMessageId !== 0) {
          this.onReplyTap(this.msg.replyToMessageId);
        }
      });
    }
    if (this.albumPaths.length > 1) {
      this.albumGrid();
      if (this.albumCaption !== '') {
        // Rich caption: links/@mentions/#hashtags stay tappable in albums too.
        this.richContent(this.albumCaption, this.albumCaptionEntities, this.inlineMaxW(),
          this.timeReserveInText());
      }
    } else if (this.msg.contentType === 'text') {
      this.richContent(this.msg.text, this.msg.textEntities, this.inlineMaxW(),
        this.timeReserveInText());
      if (this.msg.linkTitle !== '' || this.msg.linkSiteName !== '' || this.msg.linkDescription !== '') {
        this.linkPreviewCard();
      }
    } else if (this.msg.contentType === 'photo' || this.msg.contentType === 'video') {
      Stack() {
        if (this.msg.photoPath !== '') {
          // Keep the thumbnail mounted while fullscreen preview is open. ArkUI's
          // geometry transition can re-parent this Image node; with LazyForEach
          // recycling that occasionally restored only the placeholder/background
          // or an undecoded blank node after returning to the chat.
          Image(this.msg.photoPath.startsWith('/') ? `file://${this.msg.photoPath}` : this.msg.photoPath)
            .width(this.mediaBox().width).height(this.mediaBox().height).borderRadius(8).objectFit(ImageFit.Cover);
        } else {
          Stack() {
            Column().width(this.mediaBox().width).height(this.mediaBox().height).borderRadius(8).backgroundColor('#D8D8D8');
            if (this.msg.photoPath === '') {
              this.loadingRing(36, this.msg.photoProgress);
            }
          }.width(this.mediaBox().width).height(this.mediaBox().height);
        }
        if (this.msg.contentType === 'video') {
          this.playBadge(Math.min(58, Math.min(this.mediaBox().width, this.mediaBox().height) * 0.36));
          Text(this.formatDuration(this.msg.videoDuration))
            .fontSize(11).fontColor(Color.White).backgroundColor('#00000066')
            .borderRadius(4).padding({ left: 5, right: 5, top: 1, bottom: 1 })
            .position({ x: 8, y: 8 });
        }
      }
      .width(this.mediaBox().width).height(this.mediaBox().height)
      .onClick((e: ClickEvent) => { this.onMediaTap(this.msg.id, e.windowX, e.windowY); });
      // Media caption shown below the media, within the same bubble.
      if (this.msg.text !== '') {
        this.richContent(this.msg.text, this.msg.textEntities, this.inlineMaxW(),
          this.timeReserveInText());
      }
    } else if (this.msg.contentType === 'voice') {
      // Voice note with live playback progress — VoiceBubble subscribes to the
      // shared player itself, so ticks don't depend on this row re-rendering.
      VoiceBubble({
        msgId: this.msg.id,
        durationSec: this.msg.videoDuration,
        isOutgoing: this.msg.isOutgoing,
        voicePath: this.msg.videoPath,
        onNeedDownload: (): void => { this.onVoiceTap(this.msg.id); }
      });
    } else if (this.msg.contentType === 'file') {
      // Document card: icon circle + file name + size (download progress /
      // "已下载" once local). Tap opens/downloads; the top-right arrow saves a
      // copy to a user-chosen location.
      Stack({ alignContent: Alignment.TopEnd }) {
        Row({ space: 10 }) {
          Stack() {
            Circle({ width: 42, height: 42 }).fill(this.msg.isOutgoing ? '#5CA853' : COLOR_PRIMARY);
            if (this.msg.videoPath === '' && this.msg.videoProgress > 0 && this.msg.videoProgress < 100) {
              Progress({ value: this.msg.videoProgress, total: 100, type: ProgressType.Ring })
                .width(42).height(42).color(Color.White);
              Text(`${this.msg.videoProgress}`).fontSize(11).fontColor(Color.White);
            } else {
              SymbolGlyph($r(this.msg.videoPath !== '' ? 'sys.symbol.checkmark' : 'sys.symbol.doc_text'))
                .fontSize(20).fontColor([Color.White]);
            }
          }.width(42).height(42);
          Column({ space: 2 }) {
            Text(this.msg.videoFileName !== '' ? this.msg.videoFileName : '文件')
              .fontSize(15).fontColor(COLOR_BUBBLE_TEXT).fontWeight(FontWeight.Medium)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              .constraintSize({ maxWidth: this.inlineMaxW() - 84 });
            Text(this.fileSubtitle())
              .fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
          }.alignItems(HorizontalAlign.Start);
        }
        .alignItems(VerticalAlign.Center)
        .padding({ top: 2, bottom: 2, right: 30 })
        .onClick(() => { this.onFileTap(this.msg.id); });
        SymbolGlyph($r('sys.symbol.arrow_down_circle'))
          .fontSize(20).fontColor([COLOR_TEXT_SECONDARY])
          .onClick(() => { this.onFileSave(this.msg.id); });
      }
      if (this.msg.text !== '') {
        this.richContent(this.msg.text, this.msg.textEntities, this.inlineMaxW(),
          this.timeReserveInText());
      }
    } else if (this.msg.contentType === 'emoji' || this.msg.contentType === 'customEmoji') {
      // Animated-emoji fallback: the emoji itself, big and bare (no bubble).
      Text(this.msg.text).fontSize(56).padding({ bottom: 4 });
    } else if (this.msg.contentType === 'sticker') {
      // Sticker, bare (no bubble): TGS animates via Lottie once its source file
      // is local; static WEBP (and WEBM's raster still) render as an image.
      // 聊天设置 → 减弱动态效果: show the sticker's static thumbnail instead of
      // spinning up a Lottie/video player for every one of them.
      if (this.reduceAnim && this.msg.photoPath !== '') {
        Image(this.msg.photoPath.startsWith('/') ? `file://${this.msg.photoPath}` : this.msg.photoPath)
          .width(this.stickerW()).height(this.stickerH()).objectFit(ImageFit.Contain);
      } else if (this.msg.stickerFormat === 'tgs' && this.msg.stickerPath !== '') {
        TgsStickerView({ tgsPath: this.msg.stickerPath, thumbPath: this.msg.photoPath,
          boxWidth: this.stickerW(), boxHeight: this.stickerH() });
      } else if (this.msg.stickerFormat === 'webm' && this.msg.stickerPath !== '') {
        SmartLoopVideo({ videoPath: this.msg.stickerPath, thumbPath: this.msg.photoPath,
          boxWidth: this.stickerW(), boxHeight: this.stickerH() });
      } else if (this.msg.photoPath !== '') {
        Image(this.msg.photoPath.startsWith('/') ? `file://${this.msg.photoPath}` : this.msg.photoPath)
          .width(this.stickerW()).height(this.stickerH()).objectFit(ImageFit.Contain)
          .transition(TransitionEffect.OPACITY.animation({ duration: 250, curve: Curve.EaseOut }));
      } else {
        Stack() {
          this.loadingRing(32, this.msg.photoProgress);
        }.width(this.stickerW()).height(this.stickerH());
      }
    } else {
      Text() {
        Span(this.msg.placeholderLabel).fontColor(COLOR_TEXT_SECONDARY);
        Span(this.timeReserve()).fontSize(14).fontColor(Color.Transparent);
      }.fontSize(this.msgTextSize);
    }
  }

  // Document card subtitle: size while idle, percent while downloading, 已下载 when local.
  private fileSubtitle(): string {
    if (this.msg.videoPath !== '') {
      return `${formatFileSize(this.msg.videoFileSize)} · 已下载`;
    }
    if (this.msg.videoProgress > 0 && this.msg.videoProgress < 100) {
      return `下载中 ${this.msg.videoProgress}%`;
    }
    return formatFileSize(this.msg.videoFileSize);
  }

  // Big bare emoji / stickers render without bubble background/tail, like bare media.
  private isBareEmoji(): boolean {
    return this.msg.contentType === 'emoji' || this.msg.contentType === 'sticker'
      || this.msg.contentType === 'customEmoji';
  }

  // Sticker display box: longest side capped, aspect preserved (512 fallback).
  private stickerW(): number {
    const w = this.msg.photoWidth > 0 ? this.msg.photoWidth : 512;
    const h = this.msg.photoHeight > 0 ? this.msg.photoHeight : 512;
    return w >= h ? STICKER_MAX : Math.round(STICKER_MAX * (w / h));
  }

  private stickerH(): number {
    const w = this.msg.photoWidth > 0 ? this.msg.photoWidth : 512;
    const h = this.msg.photoHeight > 0 ? this.msg.photoHeight : 512;
    return h >= w ? STICKER_MAX : Math.round(STICKER_MAX * (h / w));
  }

  // Whether the timestamp overlay should reserve space at the end of the last
  // text line (only when the time actually lands there — not when reactions
  // or a comments bar sit below the text).
  private timeReserveInText(): boolean {
    return this.msg.reactions.length === 0;
  }

  // Bare media at the bubble's bottom edge → the timestamp needs a translucent
  // chip over the image instead of plain gray text.
  private timeOnMedia(): boolean {
    if (this.msg.reactions.length > 0) {
      return false;
    }
    if (this.albumPaths.length > 1) {
      return this.albumCaption === '';
    }
    if (this.isBareEmoji()) {
      return true;
    }
    return (this.msg.contentType === 'photo' || this.msg.contentType === 'video') && this.msg.text === '';
  }

  // Timestamp (+ send status) overlaid at the bubble's bottom-right, sharing
  // the last line with the message text (space reserved by timeReserve()).
  @Builder
  timeOverlay() {
    Row({ space: 4 }) {
      Text(formatTime(this.msg.date, this.nowSec)).fontSize(11)
        .fontColor(this.timeOnMedia() ? Color.White : COLOR_TEXT_SECONDARY);
      if (this.msg.isOutgoing) {
        this.statusIcon();
      }
    }
    .padding(this.timeOnMedia() ? { left: 5, right: 5, top: 1, bottom: 1 } : { left: 0 })
    .backgroundColor(this.timeOnMedia() ? '#00000066' : Color.Transparent)
    .borderRadius(8)
    .margin(this.timeOnMedia() ? { right: 6, bottom: 6 } : { right: 0, bottom: 2 });
  }

  // Service/system messages (title/photo changes, joins, pins, ...) render as
  // a centered pill, never as a left/right chat bubble. A "video chat started"
  // pill is tappable — but only while the chat's video chat is still live —
  // and opens the live viewer with that call's id.
  private liveVideoChatTappable(): boolean {
    return this.msg.isVideoChatStarted && this.liveGroupCallId > 0;
  }

  @Builder
  systemPill() {
    Text(this.msg.placeholderLabel)
      .fontSize(12).fontColor(COLOR_TEXT_SECONDARY)
      .textAlign(TextAlign.Center)
      .constraintSize({ maxWidth: this.screenW * 0.8 })
      .backgroundColor($r('app.color.system_pill')).borderRadius(10)
      .padding({ left: 10, right: 10, top: 4, bottom: 4 })
      .onClick(this.liveVideoChatTappable()
        ? (() => { this.onLiveStreamTap(this.liveGroupCallId); })
        : undefined);
  }

  build() {
    if (this.msg.contentType === 'hidden') {
      // Filtered service notice (e.g. channel paid-DM price) — render nothing.
      Column().height(0);
    } else if (this.msg.contentType === 'system') {
      Column() {
        if (this.dateLabel !== '') {
          Text(this.dateLabel)
            .fontSize(12).fontColor(COLOR_TEXT_SECONDARY).fontWeight(FontWeight.Medium)
            .backgroundColor($r('app.color.system_pill')).borderRadius(11)
            .padding({ left: 10, right: 10, top: 3, bottom: 3 })
            .margin({ bottom: 4 });
        }
        this.systemPill();
      }.width('100%').alignItems(HorizontalAlign.Center).padding({ top: 3, bottom: 3 });
    } else {
    Column() {
      if (this.dateLabel !== '') {
        // Day-change separator pill, centered ("7-6" / "2024-12-31").
        Row() {
          Text(this.dateLabel)
            .fontSize(12).fontColor(COLOR_TEXT_SECONDARY).fontWeight(FontWeight.Medium)
            .backgroundColor($r('app.color.system_pill')).borderRadius(11)
            .padding({ left: 10, right: 10, top: 3, bottom: 3 });
        }.width('100%').justifyContent(FlexAlign.Center).padding({ top: 5, bottom: 3 });
      }
      if (this.showUnreadDivider) {
        Text('未读消息')
          .fontSize(12).fontColor(COLOR_TEXT_SECONDARY)
          .width('100%').textAlign(TextAlign.Center)
          .backgroundColor($r('app.color.system_pill'))
          .padding({ top: 3, bottom: 3 }).margin({ bottom: 4 });
      }
      Row() {
      if (this.isGroup && !this.msg.isOutgoing) {
        if (this.showAvatar) {
          AvatarView({ avatarPath: this.msg.senderAvatarPath, initials: this.msg.senderInitials,
            colorSeed: this.msg.senderId, avatarSize: 32 })
            .margin({ right: 6 })
            .onClick(() => {
              // Group message avatar → that user's profile page.
              if (this.msg.senderIsUser && this.msg.senderId > 0) {
                this.onAvatarTap(this.msg.senderId);
              }
            });
        } else {
          // Mid-run row: keep the avatar column's width so bubbles stay aligned.
          Column().width(38);
        }
      }
      // Telegram-style bubble tail poking out of the bottom corner (left for
      // incoming, right for outgoing); the adjacent bubble corner is squared off.
      if (!this.msg.isOutgoing && !this.isBareEmoji()) {
        Polygon({ width: 8, height: 12 })
          .points([[8, 0], [0, 12], [8, 12]])
          .fill(COLOR_BUBBLE_IN)
          .margin({ right: -1 });
      }
      Column() {
        if (this.msg.forwardFrom !== '') {
          // Tappable when the origin is known — opens the original post, or the
          // author's chat. A hidden-origin forward carries no ids and stays inert.
          Text(`转发自 ${this.msg.forwardFrom}`).fontSize(13).fontColor(COLOR_PRIMARY)
            .fontWeight(FontWeight.Medium).margin({ bottom: 2 })
            .constraintSize({ maxWidth: this.inlineMaxW() })
            .onClick(() => {
              if (this.msg.forwardOriginChatId !== 0 || this.msg.forwardOriginUserId !== 0) {
                this.onForwardTap(this.msg.forwardOriginChatId, this.msg.forwardOriginMsgId,
                  this.msg.forwardOriginUserId);
              }
            });
        }
        if (this.isGroup && !this.msg.isOutgoing && this.msg.senderName !== '' && this.showSenderName) {
          Text(this.msg.senderName).fontSize(14).fontColor(this.senderColor()).fontWeight(FontWeight.Medium).margin({ bottom: 2 });
        }
        // Inline timestamp: overlaid at the content's bottom-right, sharing the
        // last text line (which reserves invisible tail space for it).
        Stack({ alignContent: Alignment.BottomEnd }) {
          Column() {
            this.content();
            if (this.msg.reactions.length > 0) {
              this.reactionsRow();
            }
          }.alignItems(HorizontalAlign.Start);
          this.timeOverlay();
        }
        if (this.isChannel && this.msg.commentCount > 0) {
          this.commentsRow();
        }
      }
      .alignItems(HorizontalAlign.Start)
      .constraintSize({ maxWidth: '78%' })
      .backgroundColor(this.isBareEmoji() ? Color.Transparent
        : (this.msg.isOutgoing ? COLOR_BUBBLE_OUT : COLOR_BUBBLE_IN))
      // The tail corner stays tight (min 2vp) however round the rest gets.
      .borderRadius({
        topLeft: this.bubbleRadius, topRight: this.bubbleRadius,
        bottomLeft: this.msg.isOutgoing ? this.bubbleRadius : 2,
        bottomRight: this.msg.isOutgoing ? 2 : this.bubbleRadius
      })
      .padding(this.isBareEmoji() ? 0 : 8)
      .shadow(this.isBareEmoji() ? { radius: 0, color: Color.Transparent, offsetX: 0, offsetY: 0 }
        : { radius: 2, color: '#14000000', offsetX: 0, offsetY: 1 })
      .onAreaChange((_old: Area, area: Area) => { this.bubbleW = area.width as number; })
      .bindContextMenu(this.msgContextMenu(), ResponseType.LongPress);
      if (this.msg.isOutgoing && !this.isBareEmoji()) {
        Polygon({ width: 8, height: 12 })
          .points([[0, 0], [8, 12], [0, 12]])
          .fill(COLOR_BUBBLE_OUT)
          .margin({ left: -1 });
      }
      }
      .width('100%').padding({ left: 10, right: 10, top: 3, bottom: 3 })
      .justifyContent(this.msg.isOutgoing ? FlexAlign.End : FlexAlign.Start)
      .alignItems(VerticalAlign.Bottom);
      if (this.msg.inlineButtons.length > 0) {
        this.inlineKeyboard();
      }
    }.width('100%')
    // A restrained message entrance: a short rise and fade feels responsive
    // without detaching the bubble from its final position.
    .transition(this.animateIn
      ? TransitionEffect.translate({ y: 16 })
        .combine(TransitionEffect.OPACITY)
        .animation({ duration: 220, curve: Curve.FastOutSlowIn })
      : TransitionEffect.IDENTITY);
    }
  }
}
