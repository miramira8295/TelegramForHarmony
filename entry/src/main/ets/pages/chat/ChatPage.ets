import { router, promptAction } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { picker, fileIo as fs } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { VoiceRecorder } from '../../services/VoiceRecorder';
import { formatDateSeparator } from '../../util/formatDateSeparator';
import { resolveEmojiStatus } from '../../util/emojiStatus';
import { TgsStickerView } from './TgsStickerView';
import { WebmStickerView } from './WebmStickerView';
import { EmojiPanel } from './EmojiPanel';
import { StickerItem } from './StickerPicker';
import { GifItem } from './GifPicker';
import { getVoicePlayback } from '../../services/VoicePlayback';
import { openLocalFile } from '../../util/openLocalFile';
import { saveMediaToGallery, saveFileToLocal } from '../../util/mediaSaver';
import { getTdClient, getUserStore, getChatStore } from '../../tdkit/Globals';
import { MessageStore } from '../../store/MessageStore';
import { MessageEntry } from '../../store/MessageEntry';
import { ChatEntry } from '../../store/ChatEntry';
import { MessageBubble } from './MessageBubble';
import { StreamingVideoPlayer } from './StreamingVideoPlayer';
import { AlbumGroupDataSource } from './AlbumGroupDataSource';
import { collapseAlbums, groupIndexOf, AlbumGroup } from '../../util/collapseAlbums';
import { AvatarView } from '../chatlist/AvatarView';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { normalizeTelegramLink, bareUsernameOf, inviteLinkOf } from '../../util/linkNav';
import { openInviteLink } from '../../util/openTelegramLink';
import { openUrl } from '../../util/openUrl';
import { TdObject, TdRequest, TdError } from '../../tdkit/TdTypes';
import { searchMentions, loadBotCommands, MentionItem, CommandItem } from '../../store/InputSuggestions';

const PINNED_SEG_MAX: number = 5;
// Scroll-to-bottom FAB: beyond this many groups from the end, reload the newest
// page instead of scrolling row by row through the loaded history.
const JUMP_RELOAD_THRESHOLD: number = 40;
const VIEWER_CHROME_BG: string = '#6e3e3e40';
// Emoji offered in the full reaction picker (opened from the long-press menu's
// chevron). Ordered roughly like the official client's reaction sheet.
const REACTION_EMOJIS: string[] = [
  '❤️', '👍', '👎', '🔥', '🥰', '👏', '😁', '🤔', '🤯', '😱', '🤬', '😢',
  '🎉', '🤩', '🤮', '💩', '🙏', '👌', '🕊️', '🤡', '🥱', '🥴', '😍', '🐳',
  '❤️‍🔥', '🌚', '🌭', '💯', '🤣', '⚡', '🍌', '🏆', '💔', '🤨', '😐', '🍓',
  '🍾', '💋', '🖕', '😈', '😴', '😭', '🤓', '👻', '👀', '🎃', '🙈', '😇',
  '😨', '🤝', '✍️', '🤗', '🫡', '🎅', '🎄', '☃️', '💅', '🤪', '🗿', '🆒',
  '💘', '🙉', '🦄', '😘', '💊', '🙊', '😎', '👾', '🤷', '😡'
];

@Entry
@Preview
@Component
struct ChatPage {
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;  // ✅ 新增
  @StorageProp('keyboardHeightVp') keyboardH: number = 0;
  @State messages: MessageEntry[] = [];
  // Rendered through the LazyForEach data source (incremental notifications keep
  // scroll position on prepend); the plain array mirror serves index lookups.
  private groups: AlbumGroup[] = [];
  private groupsData: AlbumGroupDataSource = new AlbumGroupDataSource();
  @State subtitle: string = '';
  @State title: string = '';
  @State avatarPath: string = '';
  @State initials: string = '?';
  @State draft: string = '';
  @State replyToId: number = 0;      // message being replied to (0 = none)
  @State replyToName: string = '';
  @State replyToText: string = '';
  @State showReactionSheet: boolean = false; // full emoji reaction picker
  @State reactionTargetId: number = 0;
  @State nowSec: number = 0;
  @State viewerMsgId: number = 0;
  @State chromeVisible: boolean = true;
  @State viewerDlPercent: number = 100; // active video's download progress (top chrome)
  @State viewerInitIdx: number = 0; // Swiper's initial page when the viewer opens
  private viewerSwiperCtrl: SwiperController = new SwiperController();
  @State swipeDir: number = 1; // 1 = advancing forward (next), -1 = going back — drives the slide direction
  // Window coordinates (vp) of the tap that opened the viewer — anchor for its
  // expand-from-tap open / shrink-back-to-tap close transition.
  @State tapX: number = 0;
  @State tapY: number = 0;
  @State pinnedPreview: string = '';
  @State pinnedCount: number = 0;
  private chatId: number = 0;
  // >0: comment-thread view over the linked discussion group (see onCommentTap)
  private threadRootId: number = 0;
  @State isGroup: boolean = false;
  @State isChannel: boolean = false;
  private store: MessageStore | null = null;
  private scroller: Scroller = new Scroller();
  private didInitialScroll: boolean = false;
  private lastMaxId: number = 0;
  @State atBottom: boolean = true;
  @State isMuted: boolean = false;
  @State unreadBadge: number = 0;
  private firstUnreadId: number = 0;
  private curStartIdx: number = -1; // topmost visible row index (from onScrollIndex)
  private pendingScrollBottom: boolean = false; // snap to the end once jumpToLatest's page arrives
  // @State: the segment indicator renders from this — a plain field wouldn't
  // trigger a re-render when scrolling/tapping moves the shown pinned index.
  @State pinnedCycle: number = 0;
  private pendingJumpId: number = 0;
  // One-shot gate for loading older pages: a fast fling to the very top used to
  // chain-load page after page (the list stays pinned at the edge, so the
  // trigger zone never clears). Re-armed when the user scrolls clear of the
  // top zone or starts a new touch gesture.
  private olderArmed: boolean = true;
  // Jump-target highlight: a translucent overlay over the target row that
  // gently blinks twice after a reply/pinned/link jump lands.
  @State flashTop: number = 0;
  @State flashHeight: number = 0;
  @State flashAlpha: number = 0;
  @State flashShown: boolean = false;
  private flashSeq: number = 0;
  // Floating date chip: shows the topmost visible message's date while the
  // list scrolls, fades out shortly after scrolling stops (the in-list date
  // pills stay — this is the always-visible companion).
  @State floatDate: string = '';
  @State floatDateShown: boolean = false;
  private floatDateHideTimer: number = -1;
  // Message id of a video waiting to be saved to the gallery once downloaded.
  private pendingGallerySaveId: number = 0;
  // Message id of a document waiting for the "save as" picker once downloaded.
  private pendingFileSaveId: number = 0;
  // Messages with id above this slide in from the bottom (live arrivals only —
  // 0 disables, so rows created while scrolling history never animate).
  @State freshSinceId: number = 0;
  private freshClearSeq: number = 0;
  private prependRestoreSeq: number = 0;
  // '@' mention / '/' command suggestion panels above the input bar.
  @State mentionItems: MentionItem[] = [];
  @State commandItems: CommandItem[] = [];
  private allCommands: CommandItem[] = [];
  private commandsLoaded: boolean = false;
  private mentionSeq: number = 0; // drops stale searchChatMembers responses
  // Bot "菜单" pill (private bot chats with registered commands).
  @State botMenuAvailable: boolean = false;
  private botProbed: boolean = false;
  // Emoji panel above the input bar.
  @State showEmojiPanel: boolean = false;
  // Voice recording state.
  @State isRecording: boolean = false;
  @State recordSeconds: number = 0;
  private recordTimer: number = -1;
  private voiceRec: VoiceRecorder | null = null;
  @State headerMenuShow: boolean = false; // header ⋮ dropdown
  // In-chat message search (search-mode header + result navigation).
  @State searchMode: boolean = false;
  // Multi-select mode (entered via the long-press menu's 选择 item).
  @State selecting: boolean = false;
  @State selectedIds: number[] = [];
  @State searchQuery: string = '';
  @State searchResults: number[] = []; // message ids, newest → oldest
  @State searchTotal: number = 0;
  @State searchIdx: number = 0;        // 0-based index into searchResults
  private searchSeq: number = 0;       // drops stale responses
  private unsubMsg: (() => void) | null = null;
  private unsubSub: (() => void) | null = null;
  // Peer's premium emoji status (private chats) shown beside the header title.
  @State headerEmojiPath: string = '';
  @State headerEmojiFormat: string = '';
  private headerEmojiFetched: boolean = false;
  private unsubChat: (() => void) | null = null;
  private unsubPinned: (() => void) | null = null;
  private unsubHeaderAvatar: (() => void) | null = null;
  private unsubHeaderTitle: (() => void) | null = null;

  aboutToAppear(): void {
    this.nowSec = Math.floor(Date.now() / 1000);
    const params = router.getParams() as Record<string, Object> | undefined;
    this.chatId = params !== undefined ? (params['chatId'] as number) : 0;
    const jumpTo = params !== undefined ? (params['jumpTo'] as number | undefined) : undefined;
    this.threadRootId = params !== undefined ? ((params['threadRootId'] as number | undefined) ?? 0) : 0;
    this.refreshHeader();
    this.unsubChat = getChatStore().subscribe(() => { this.refreshHeader(); }, 'main');
    const store = new MessageStore(getTdClient(), getUserStore(), this.chatId, this.threadRootId);
    this.store = store;
    this.unsubMsg = store.subscribe((list: MessageEntry[]) => {
      const maxId: number = list.length > 0 ? list[list.length - 1].id : 0;
      const groups: AlbumGroup[] = collapseAlbums(list);
      let prependAnchorId: number = 0;
      let prependAnchorY: number = 0;
      if (this.didInitialScroll && this.groups.length > 0 && groups.length > this.groups.length) {
        const previousFirstIndex: number = groupIndexOf(groups, this.groups[0].head.id);
        const visibleIndex: number = this.curStartIdx;
        if (previousFirstIndex > 0 && visibleIndex >= 0 && visibleIndex < this.groups.length) {
          prependAnchorId = this.groups[visibleIndex].head.id;
          try {
            prependAnchorY = this.scroller.getItemRect(visibleIndex).y;
          } catch (e) {
            prependAnchorY = 0;
          }
        }
      }
      this.messages = list;
      this.groups = groups;
      this.groupsData.update(groups);
      if (prependAnchorId > 0) {
        this.restorePrependAnchor(groups, prependAnchorId, prependAnchorY);
      }
      // isChannel resolves asynchronously (getSupergroup round-trip) after the
      // first message page can already be showing, so refresh it every notify.
      this.isChannel = this.store !== null ? this.store.getIsChannel() : false;
      // Private chat peer resolved → probe once for bot commands (humans
      // return an empty list); a non-empty catalog shows the 菜单 pill.
      if (!this.botProbed && this.store !== null && this.store.getPeerUserId() > 0) {
        this.botProbed = true;
        loadBotCommands(getTdClient(), this.chatId, this.store.getPeerUserId())
          .then((items: CommandItem[]) => {
            this.allCommands = items;
            this.commandsLoaded = true;
            this.botMenuAvailable = items.length > 0;
          });
      }
      if (!this.didInitialScroll && list.length > 0) {
        // First real page: jump to the first unread message (Android-style);
        // fully-read chats land at the bottom. (Never anchor on
        // last_read_inbox_message_id here — it only tracks incoming messages,
        // so with an outgoing tail it points at a stale mid-history position.)
        this.didInitialScroll = true;
        this.lastMaxId = maxId;
        const fu: number = this.store !== null ? this.store.getFirstUnreadId() : 0;
        const gidx: number = fu > 0 ? groupIndexOf(groups, fu) : -1;
        this.firstUnreadId = fu > 0 && gidx >= 0 ? groups[gidx].head.id : 0;
        this.isGroup = this.store !== null ? this.store.getIsGroup() : false;
        if (gidx >= 0) {
          // Landing mid-history at the unread boundary: atBottom defaults to
          // true, and the bottom-glue branch below would otherwise drag the
          // view to the tail (chain-loading every newer page) before the
          // first scroll event corrects it.
          this.atBottom = false;
          this.scroller.scrollToIndex(gidx, false, ScrollAlign.START);
        } else {
          this.scroller.scrollEdge(Edge.Bottom);
        }
      } else if (this.didInitialScroll && maxId > this.lastMaxId) {
        // Only follow to the bottom for genuinely new messages AND only when the
        // user is already near the bottom — never yank them down while they read
        // history or on photo/read-receipt updates.
        // Mark the arrivals as fresh for a beat so their bubbles gently enter;
        // rows rebuilt while scrolling history never animate.
        this.freshSinceId = this.lastMaxId;
        const clearSeq = ++this.freshClearSeq;
        setTimeout(() => {
          if (clearSeq === this.freshClearSeq) {
            this.freshSinceId = 0;
          }
        }, 1500);
        this.lastMaxId = maxId;
        if (this.atBottom) {
          this.scroller.scrollEdge(Edge.Bottom);
        }
      } else if (this.didInitialScroll && this.atBottom && this.viewerMsgId === 0
        && (this.store === null || !this.store.getHasMoreNewer())) {
        // In-place content growth (thumbnails, reply quotes, forward headers
        // filling in async) changes row heights; when the user is at the
        // bottom, stay glued there instead of letting the tail drift. Never
        // glue while unloaded newer pages exist — being at the window's edge
        // there is NOT the live tail, and gluing chain-loads every page.
        // Also never glue while the media viewer is open: hiding its thumbnail
        // collapses that row, which can fake an at-bottom state.
        this.scroller.scrollEdge(Edge.Bottom);
      }
      // jumpToLatest's newest page arrived — snap to the end. The dataset was
      // just replaced wholesale, so scroll once now and once after the List has
      // laid the new rows out: the immediate call alone lands at the top of the
      // reloaded page because the final row heights aren't known yet.
      if (this.pendingScrollBottom && list.length > 0) {
        this.pendingScrollBottom = false;
        this.lastMaxId = maxId;
        this.atBottom = true;
        this.scroller.scrollEdge(Edge.Bottom);
        setTimeout(() => { this.scroller.scrollEdge(Edge.Bottom); }, 60);
      }
      // A video queued for gallery save finished downloading — save it now.
      if (this.pendingGallerySaveId !== 0) {
        const pe = list.find((m: MessageEntry) => m.id === this.pendingGallerySaveId);
        if (pe !== undefined && pe.videoPath !== '') {
          this.pendingGallerySaveId = 0;
          saveMediaToGallery(getContext(this) as common.UIAbilityContext, pe.videoPath, true);
        }
      }
      // A document queued for "save as" finished downloading — open the picker.
      if (this.pendingFileSaveId !== 0) {
        const fe = list.find((m: MessageEntry) => m.id === this.pendingFileSaveId);
        if (fe !== undefined && fe.videoPath !== '') {
          this.pendingFileSaveId = 0;
          saveFileToLocal(getContext(this) as common.UIAbilityContext, fe.videoPath, fe.videoFileName);
        }
      }
      // A pinned/quoted jump target that had to be loaded has now arrived — scroll to it.
      if (this.pendingJumpId !== 0) {
        const jumpTargetId: number = this.pendingJumpId;
        const jg: number = groupIndexOf(groups, jumpTargetId);
        if (jg >= 0) {
          this.pendingJumpId = 0;
          this.scroller.scrollToIndex(jg, false, ScrollAlign.START);
          // loadAround replaces the window wholesale (list RELOAD) — the
          // immediate scroll can be swallowed before the new rows lay out.
          // Re-issue once layout settles (index recomputed: prepends may have
          // shifted it) and flash after that.
          setTimeout(() => {
            const jg2: number = groupIndexOf(this.groups, jumpTargetId);
            if (jg2 >= 0) {
              this.scroller.scrollToIndex(jg2, false, ScrollAlign.START);
              this.flashAtIndex(jg2);
            }
          }, 80);
        }
      }
    });
    this.unsubSub = store.subscribeSubtitle((s: string) => {
      this.subtitle = s;
      this.fetchHeaderEmojiStatus();
    });
    this.unsubHeaderTitle = store.subscribeHeaderTitle((t: string) => {
      // Fallback header for chats not yet in ChatStore (e.g. opened by t.me link).
      if (t !== '' && this.title === '') {
        this.title = t;
        this.initials = t.substring(0, 1).toUpperCase();
      }
    });
    this.unsubHeaderAvatar = store.subscribeHeaderAvatar((p: string) => {
      if (p !== '') {
        this.avatarPath = p;
        // MessageStore resolves the chat photo independently of ChatStore/FileService
        // (e.g. for a channel only ever surfaced under a folder tab, whose avatar
        // download may never have fired/retried there) — backfill the list entry too,
        // so the chat list shows the avatar without depending on that separate path.
        getChatStore().setAvatarPath(this.chatId, p);
      }
    });
    this.unsubPinned = store.subscribePinned((s: string) => {
      this.pinnedPreview = s;
      this.pinnedCount = this.store !== null ? this.store.getPinnedIds().length : 0;
      this.pinnedCycle = 0;
    });
    if (jumpTo !== undefined && jumpTo > 0) {
      // Opened via a message link: load straight around the target message,
      // without racing an additional latest-history request.
      this.didInitialScroll = true;
      this.pendingJumpId = jumpTo;
      store.open(jumpTo);
    } else if (this.threadRootId > 0) {
      // Comment thread: start at the TOP — the root post — not the newest reply.
      this.didInitialScroll = true;
      this.pendingJumpId = this.threadRootId;
      store.open(this.threadRootId);
    } else {
      store.open();
    }
  }

  aboutToDisappear(): void {
    this.cancelRecording();
    getVoicePlayback().stop();
    if (this.unsubMsg !== null) { this.unsubMsg(); this.unsubMsg = null; }
    if (this.unsubSub !== null) { this.unsubSub(); this.unsubSub = null; }
    if (this.unsubChat !== null) { this.unsubChat(); this.unsubChat = null; }
    if (this.unsubPinned !== null) { this.unsubPinned(); this.unsubPinned = null; }
    if (this.unsubHeaderAvatar !== null) { this.unsubHeaderAvatar(); this.unsubHeaderAvatar = null; }
    if (this.unsubHeaderTitle !== null) { this.unsubHeaderTitle(); this.unsubHeaderTitle = null; }
    if (this.store !== null) { this.store.close(); this.store = null; }
  }

  // Open/close wrapped in animateTo so the geometryTransition pairing (viewer
  // ↔ tapped thumbnail) animates as a hero expand/shrink.
  private openViewer(messageId: number): void {
    this.viewerDlPercent = 100; // fresh page — player reports real progress
    animateTo({ duration: 300, curve: Curve.Friction }, () => {
      this.onMediaTap(messageId);
    });
  }

  private closeViewer(): void {
    animateTo({ duration: 300, curve: Curve.Friction }, () => {
      this.viewerMsgId = 0;
    });
  }

  // System back (gesture/hardware button): close the fullscreen viewer first
  // if it's open, rather than popping all the way back to the chat list.
  onBackPress(): boolean {
    if (this.viewerMsgId !== 0) {
      this.closeViewer();
      return true;
    }
    if (this.selecting) {
      this.exitSelect();
      return true;
    }
    if (this.searchMode) {
      this.exitSearch();
      return true;
    }
    return false;
  }

  // Private chat: the peer's emoji status appears beside the header title.
  private fetchHeaderEmojiStatus(): void {
    if (this.headerEmojiFetched || this.store === null) {
      return;
    }
    const uid = this.store.getPeerUserId();
    if (uid <= 0) {
      return;
    }
    this.headerEmojiFetched = true;
    const req: TdRequest = { '@type': 'getUser' };
    req['user_id'] = uid;
    getTdClient().send(req).then((user: TdObject) => {
      resolveEmojiStatus(user['emoji_status'] as TdObject | undefined, (path: string, format: string) => {
        this.headerEmojiPath = path;
        this.headerEmojiFormat = format;
      });
    }).catch((e: TdError) => {
      console.error(`ChatPage.fetchHeaderEmojiStatus failed: ${e.message}`);
    });
  }

  // Refresh the floating date chip from the topmost visible row and (re)arm
  // its fade-out. Only meaningful once the initial positioning has settled.
  private updateFloatDate(start: number): void {
    if (!this.didInitialScroll || start < 0 || start >= this.groups.length) {
      return;
    }
    const g = this.groups[start];
    if (g.head.date > 0) {
      this.floatDate = formatDateSeparator(g.head.date);
      this.floatDateShown = true;
    }
    if (this.floatDateHideTimer !== -1) {
      clearTimeout(this.floatDateHideTimer);
    }
    this.floatDateHideTimer = setTimeout(() => {
      this.floatDateHideTimer = -1;
      this.floatDateShown = false;
    }, 1000);
  }

  // The banner tracks the scroll position: it shows the newest pinned message
  // strictly ABOVE the viewport top (the one a tap would jump to). Scrolling
  // past a pinned message therefore switches the banner to its neighbor, and
  // after a tap-jump lands this naturally advances to the next older one.
  private updatePinnedFromScroll(start: number): void {
    if (this.store === null || this.pinnedCount === 0 || start < 0 || start >= this.groups.length) {
      return;
    }
    const ids: number[] = this.store.getPinnedIds(); // newest → oldest
    const previews: string[] = this.store.getPinnedPreviews();
    const topId: number = this.groups[start].head.id;
    let idx = -1;
    for (let i = 0; i < ids.length; i++) {
      if (ids[i] < topId) {
        idx = i;
        break;
      }
    }
    if (idx < 0) {
      idx = ids.length - 1; // viewport is above every pinned message → nearest is the oldest
    }
    if (idx !== this.pinnedShownIdx()) {
      this.pinnedCycle = idx;
      if (idx < previews.length) {
        this.pinnedPreview = previews[idx];
      }
    }
  }

  // Tap the pinned banner: jump to the pinned message it currently shows.
  // Once at/above the oldest pinned message, tapping wraps back to the bottom.
  private onPinnedTap(): void {
    if (this.store === null) {
      return;
    }
    const ids: number[] = this.store.getPinnedIds();
    if (ids.length === 0) {
      return;
    }
    const idx: number = this.pinnedShownIdx();
    const targetId: number = ids[idx];
    const topId: number = this.curStartIdx >= 0 && this.curStartIdx < this.groups.length
      ? this.groups[this.curStartIdx].head.id : 0;
    if (idx === ids.length - 1 && topId !== 0 && topId <= targetId) {
      this.atBottom = true;
      this.scroller.scrollEdge(Edge.Bottom);
      return;
    }
    const gidx: number = groupIndexOf(this.groups, targetId);
    if (gidx >= 0) {
      this.scroller.scrollToIndex(gidx, false, ScrollAlign.START);
      this.flashAtIndex(gidx);
    } else {
      this.pendingJumpId = targetId;
      this.store.loadAround(targetId);
    }
  }

  // Bottom inset for bars (empirically tuned on device): with the keyboard up
  // the bar needs lifting clear of the IME edge; without it the layout already
  // sits above the gesture bar, so only minimal padding applies.
  private bottomInset(): number {
    return this.keyboardH > 0 ? Math.max(this.bottomSafe, 12) : this.bottomSafe;
  }

  // Fire at most one loadOlder per arm (see olderArmed).
  private maybeLoadOlder(): void {
    if (this.olderArmed && this.store !== null) {
      this.olderArmed = false;
      this.store.loadOlder();
    }
  }

  // A history page is inserted before the current window. Keep the exact
  // message and its partial row offset under the user's finger; the newly
  // loaded rows should only appear as they continue scrolling upward.
  private restorePrependAnchor(groups: AlbumGroup[], messageId: number, itemY: number): void {
    const targetIndex: number = groupIndexOf(groups, messageId);
    if (targetIndex < 0) {
      return;
    }
    const seq: number = ++this.prependRestoreSeq;
    setTimeout((): void => {
      if (seq !== this.prependRestoreSeq || this.pendingJumpId !== 0 || this.pendingScrollBottom) {
        return;
      }
      this.scroller.scrollToIndex(targetIndex, false, ScrollAlign.START);
      if (itemY < 0) {
        this.scroller.scrollBy(0, -itemY);
      }
    }, 0);
  }

  private refreshHeader(): void {
    if (this.threadRootId > 0) {
      // Comment-thread view: fixed title, the rest of the header still shows
      // the discussion group's avatar/mute state.
      this.title = '评论';
    }
    const e: ChatEntry | undefined = getChatStore().entryOf(this.chatId);
    if (e !== undefined) {
      if (this.threadRootId === 0) {
        this.title = e.title;
      }
      // Don't clobber a MessageStore-resolved avatar (channels/folders) with an empty one.
      if (e.avatarPath !== '') { this.avatarPath = e.avatarPath; }
      this.initials = e.initials;
      this.isMuted = e.isMuted;
      this.unreadBadge = e.unreadCount; // live unread count for the scroll-to-bottom badge
    }
  }

  // Mark read up to the bottom-most visible message, so only what the user has
  // actually scrolled past gets marked read (entering without scrolling leaves
  // the rest unread).
  private markVisibleRead(end: number): void {
    if (this.store === null || end < 0 || end >= this.groups.length) {
      return;
    }
    const g: AlbumGroup = this.groups[end];
    let maxId: number = 0;
    for (const id of g.memberIds) {
      if (id > maxId) {
        maxId = id;
      }
    }
    if (maxId > 0) {
      this.store.markViewed(maxId);
    }
  }

  // A tapped in-message link: Telegram links (t.me/<name>, t.me/<name>/<msgId>,
  // @<name>) resolve via TDLib and open the target chat inside the app, jumped
  // to the specific message when the link points to one; everything else opens
  // in the system browser.
  private onLinkTap(url: string): void {
    // Hashtag tap → global search across all chats.
    if (url.startsWith('tg-hashtag:')) {
      const tag = url.substring('tg-hashtag:'.length);
      if (tag !== '') {
        const params: Record<string, Object> = { 'query': tag };
        router.pushUrl({ url: 'pages/search/GlobalSearchPage', params: params });
      }
      return;
    }
    // Text mention (no username): the entity carries the user id directly.
    if (url.startsWith('tg://user?id=')) {
      const uid = Number(url.substring('tg://user?id='.length));
      if (uid > 0) {
        const params: Record<string, Object> = { 'userId': uid };
        router.pushUrl({ url: 'pages/profile/ProfilePage', params: params });
      }
      return;
    }
    // Private invite link (t.me/+hash): preview → confirm → join in-app.
    const invite = inviteLinkOf(url);
    if (invite !== '') {
      openInviteLink(getContext(this) as common.UIAbilityContext, invite, url);
      return;
    }
    // '@name' / t.me/<name> with no message id: resolve the username — a user
    // opens the profile card, a group/channel opens its chat.
    const bareName = bareUsernameOf(url);
    if (bareName !== '') {
      this.openByUsername(bareName, url);
      return;
    }
    const tgUrl = normalizeTelegramLink(url);
    if (tgUrl === '') {
      openUrl(getContext(this) as common.UIAbilityContext, url);
      return;
    }
    const req: TdRequest = { '@type': 'getMessageLinkInfo' };
    req['url'] = tgUrl;
    getTdClient().send(req).then((info: TdObject) => {
      const chatId = info['chat_id'] as number | undefined;
      if (chatId === undefined || chatId === 0) {
        openUrl(getContext(this) as common.UIAbilityContext, url);
        return;
      }
      const msg = info['message'] as TdObject | undefined;
      const msgId = msg !== undefined ? (msg['id'] as number | undefined) : undefined;
      // A link to a message already in this chat: scroll in place (same as the
      // pinned-message jump) instead of pushing a duplicate ChatPage instance —
      // that duplication was why repeat taps looked like they did nothing.
      if (chatId === this.chatId) {
        if (msgId !== undefined && msgId > 0) {
          const gidx = groupIndexOf(this.groups, msgId);
          if (gidx >= 0) {
            this.scroller.scrollToIndex(gidx, false, ScrollAlign.START);
            this.flashAtIndex(gidx);
          } else {
            this.pendingJumpId = msgId;
            if (this.store !== null) { this.store.loadAround(msgId); }
          }
        }
        return;
      }
      const params: Record<string, Object> = { 'chatId': chatId };
      if (msgId !== undefined && msgId > 0) {
        params['jumpTo'] = msgId;
      }
      router.pushUrl({ url: 'pages/chat/ChatPage', params: params });
    }).catch((e: TdError) => {
      console.error(`ChatPage.getMessageLinkInfo failed: ${e.message}`);
      openUrl(getContext(this) as common.UIAbilityContext, url);
    });
  }

  // Resolve a bare @username: a user opens the profile card; a group/channel
  // opens its chat page. `original` is the raw tapped URL for the browser
  // fallback when the username doesn't resolve.
  private openByUsername(name: string, original: string): void {
    const req: TdRequest = { '@type': 'searchPublicChat' };
    req['username'] = name;
    getTdClient().send(req).then((chat: TdObject) => {
      const chatId = (chat['id'] as number | undefined) ?? 0;
      const type = chat['type'] as TdObject | undefined;
      const typeName = type !== undefined ? ((type['@type'] as string | undefined) ?? '') : '';
      if (typeName === 'chatTypePrivate') {
        const uid = ((type as TdObject)['user_id'] as number | undefined) ?? 0;
        if (uid > 0) {
          const params: Record<string, Object> = { 'userId': uid };
          router.pushUrl({ url: 'pages/profile/ProfilePage', params: params });
          return;
        }
      }
      if (chatId !== 0) {
        const params: Record<string, Object> = { 'chatId': chatId };
        router.pushUrl({ url: 'pages/chat/ChatPage', params: params });
        return;
      }
      openUrl(getContext(this) as common.UIAbilityContext, original);
    }).catch((e: TdError) => {
      console.error(`ChatPage.searchPublicChat(${name}) failed: ${e.message}`);
      openUrl(getContext(this) as common.UIAbilityContext, original);
    });
  }

  // Reply-quote tap: jump to the quoted original message (same in-place scroll
  // as a same-chat link jump).
  // --- in-chat search ---
  private enterSearch(): void {
    this.searchMode = true;
    this.searchQuery = '';
    this.searchResults = [];
    this.searchTotal = 0;
    this.searchIdx = 0;
  }

  private exitSearch(): void {
    this.searchMode = false;
    this.searchQuery = '';
    this.searchResults = [];
    this.searchTotal = 0;
    this.searchIdx = 0;
    this.searchSeq++;
    this.cancelFlash();
  }

  // Run a search page. fromMsgId 0 = fresh search; otherwise fetch the page
  // older than that message (pagination for the ∧ button past the first 50).
  private runSearch(fromMsgId: number, thenJumpTo: number): void {
    const q = this.searchQuery.trim();
    if (q === '') {
      return;
    }
    const seq = ++this.searchSeq;
    const req: TdRequest = { '@type': 'searchChatMessages' };
    req['chat_id'] = this.chatId;
    req['query'] = q;
    req['from_message_id'] = fromMsgId;
    req['offset'] = 0;
    req['limit'] = 50;
    getTdClient().send(req).then((res: TdObject) => {
      if (seq !== this.searchSeq || !this.searchMode) {
        return;
      }
      const msgs = (res['messages'] as TdObject[] | undefined) ?? [];
      const ids: number[] = [];
      for (const m of msgs) {
        const id = (m['id'] as number | undefined) ?? 0;
        if (id > 0) {
          ids.push(id);
        }
      }
      this.searchTotal = (res['total_count'] as number | undefined) ?? ids.length;
      this.searchResults = fromMsgId === 0 ? ids : [...this.searchResults, ...ids];
      if (this.searchResults.length === 0) {
        promptAction.showToast({ message: '未找到相关消息', duration: 1500 });
        return;
      }
      this.jumpToResult(thenJumpTo);
    }).catch((e: TdError) => {
      console.error(`ChatPage.searchChatMessages failed: ${e.message}`);
    });
  }

  private jumpToResult(idx: number): void {
    if (idx < 0 || idx >= this.searchResults.length) {
      return;
    }
    this.searchIdx = idx;
    this.onReplyTap(this.searchResults[idx]); // same jump + double-blink flash
  }

  // ∧ = older result. Past the loaded window → fetch the next page first.
  private searchOlder(): void {
    const next = this.searchIdx + 1;
    if (next < this.searchResults.length) {
      this.jumpToResult(next);
    } else if (this.searchResults.length < this.searchTotal && this.searchResults.length > 0) {
      this.runSearch(this.searchResults[this.searchResults.length - 1], next);
    }
  }

  // ∨ = newer result.
  private searchNewer(): void {
    if (this.searchIdx > 0) {
      this.jumpToResult(this.searchIdx - 1);
    }
  }

  private onReplyTap(messageId: number): void {
    if (messageId <= 0) {
      return;
    }
    const gidx = groupIndexOf(this.groups, messageId);
    if (gidx >= 0) {
      this.scroller.scrollToIndex(gidx, false, ScrollAlign.START);
      this.flashAtIndex(gidx);
    } else if (this.store !== null) {
      this.pendingJumpId = messageId;
      this.store.loadAround(messageId);
    }
  }

  // Gently blink the row at gidx twice — visual confirmation of where a
  // reply/pinned/link jump landed. Waits a beat for the scroll to settle so
  // getItemRect sees the laid-out row.
  private flashAtIndex(gidx: number): void {
    const seq = ++this.flashSeq;
    setTimeout(() => {
      if (seq !== this.flashSeq) {
        return;
      }
      let top = 0;
      let height = 0;
      try {
        const rect = this.scroller.getItemRect(gidx);
        top = rect.y;
        height = rect.height;
      } catch (e) {
        return; // row not laid out (jump superseded) — skip the highlight
      }
      if (height <= 0) {
        return;
      }
      this.flashTop = top;
      this.flashHeight = height;
      this.flashShown = true;
      this.flashAlpha = 0;
      this.runBlink(seq, 2);
    }, 150);
  }

  private runBlink(seq: number, remaining: number): void {
    if (seq !== this.flashSeq) {
      return;
    }
    if (remaining <= 0) {
      this.flashShown = false;
      this.flashAlpha = 0;
      return;
    }
    animateTo({ duration: 320, curve: Curve.EaseInOut }, () => { this.flashAlpha = 1; });
    setTimeout(() => {
      if (seq !== this.flashSeq) {
        return;
      }
      animateTo({ duration: 320, curve: Curve.EaseInOut }, () => { this.flashAlpha = 0; });
      setTimeout(() => { this.runBlink(seq, remaining - 1); }, 340);
    }, 340);
  }

  // Any new touch cancels the highlight (it's viewport-anchored, so it would
  // visibly detach from the row once the user scrolls).
  private cancelFlash(): void {
    this.flashSeq++;
    this.flashShown = false;
    this.flashAlpha = 0;
  }

  // "N Comments" tap: resolve the channel post's discussion thread and open it
  // as a normal chat page on the linked discussion group, jumped to the post.
  private onCommentTap(messageId: number): void {
    const req: TdRequest = { '@type': 'getMessageThread' };
    req['chat_id'] = this.chatId;
    req['message_id'] = messageId;
    getTdClient().send(req).then((info: TdObject) => {
      const discussionChatId = info['chat_id'] as number | undefined;
      const threadId = info['message_thread_id'] as number | undefined;
      if (discussionChatId === undefined) {
        return;
      }
      const params: Record<string, Object> = { 'chatId': discussionChatId };
      if (threadId !== undefined && threadId > 0) {
        // Thread-scoped view: only this post's replies (getMessageThreadHistory),
        // not the whole discussion group's history.
        params['threadRootId'] = threadId;
      }
      router.pushUrl({ url: 'pages/chat/ChatPage', params: params });
    }).catch((e: TdError) => {
      console.error(`ChatPage.getMessageThread failed: ${e.message}`);
    });
  }

  // Open the fullscreen viewer for a photo/video message. Photos still upgrade
  // to full-res on demand; videos are streamed by the fullscreen AVPlayer.
  private onMediaTap(messageId: number): void {
    if (this.store === null) {
      return;
    }
    const idx = this.messages.findIndex((m: MessageEntry) => m.id === messageId);
    if (idx < 0) {
      return;
    }
    const m = this.messages[idx];
    if (m.contentType === 'photo') {
      this.store.requestFullPhoto(messageId);
    }
    // Position the viewer Swiper on the tapped album member.
    const sib = this.siblingIdsFor(messageId);
    this.viewerInitIdx = Math.max(0, sib.indexOf(messageId));
    this.viewerMsgId = messageId;
    this.chromeVisible = true;
  }

  // Album member ids for an arbitrary message (single-element list when the
  // message isn't part of a multi-item album).
  private siblingIdsFor(messageId: number): number[] {
    for (const g of this.groups) {
      if (g.memberIds.indexOf(messageId) >= 0 && g.memberIds.length > 1) {
        return g.memberIds;
      }
    }
    return [messageId];
  }

  private toggleChrome(): void {
    this.chromeVisible = !this.chromeVisible;
  }

  private viewerEntry(): MessageEntry | null {
    const idx = this.messages.findIndex((m: MessageEntry) => m.id === this.viewerMsgId);
    return idx >= 0 ? this.messages[idx] : null;
  }

  private viewerFileName(): string {
    const e = this.viewerEntry();
    return e !== null ? e.videoFileName : '';
  }

  // The album (media group) containing the viewer's current message, if any.
  private viewerGroup(): AlbumGroup | null {
    for (const g of this.groups) {
      if (g.memberIds.indexOf(this.viewerMsgId) >= 0) {
        return g;
      }
    }
    return null;
  }

  // Sibling message ids for swipe/filmstrip navigation — just the current
  // message when it isn't part of a multi-item album.
  private viewerSiblingIds(): number[] {
    const g = this.viewerGroup();
    if (g !== null && g.memberIds.length > 1) {
      return g.memberIds;
    }
    return this.viewerMsgId !== 0 ? [this.viewerMsgId] : [];
  }

  private viewerSiblingPath(id: number): string {
    const g = this.viewerGroup();
    if (g !== null) {
      const idx = g.memberIds.indexOf(id);
      if (idx >= 0 && idx < g.photoPaths.length) {
        return g.photoPaths[idx];
      }
    }
    const idx2 = this.messages.findIndex((m: MessageEntry) => m.id === id);
    return idx2 >= 0 ? this.messages[idx2].photoPath : '';
  }

  private viewerSiblingIsVideo(id: number): boolean {
    const idx = this.messages.findIndex((m: MessageEntry) => m.id === id);
    return idx >= 0 && this.messages[idx].contentType === 'video';
  }

  private entryById(id: number): MessageEntry | null {
    const idx = this.messages.findIndex((m: MessageEntry) => m.id === id);
    return idx >= 0 ? this.messages[idx] : null;
  }

  // Best available image for a viewer page: full-res once downloaded, else thumbnail.
  private photoSrcFor(id: number): string {
    const e = this.entryById(id);
    if (e === null) {
      return '';
    }
    const p = e.photoFullPath !== '' ? e.photoFullPath : e.photoPath;
    return p.startsWith('/') ? `file://${p}` : p;
  }

  // Programmatic paging: the Swiper animates the transition; onChange keeps
  // viewerMsgId in sync.
  private switchViewer(delta: number): void {
    if (delta > 0) {
      this.viewerSwiperCtrl.showNext();
    } else {
      this.viewerSwiperCtrl.showPrevious();
    }
  }

  // Filmstrip tap: page the Swiper to the tapped album member.
  private jumpToSibling(id: number): void {
    const i = this.viewerSiblingIds().indexOf(id);
    if (i >= 0) {
      this.viewerSwiperCtrl.changeIndex(i, true);
    }
  }

  // Swiper page settled on a new album member.
  private resetViewerDl(): void {
    this.viewerDlPercent = 100;
  }

  private onViewerPageChange(index: number): void {
    const ids = this.viewerSiblingIds();
    if (index < 0 || index >= ids.length) {
      return;
    }
    const id = ids[index];
    if (id === this.viewerMsgId) {
      return;
    }
    this.viewerMsgId = id;
    this.resetViewerDl();
    if (this.store !== null && !this.viewerSiblingIsVideo(id)) {
      this.store.requestFullPhoto(id);
    }
  }

  private viewerIsVideo(): boolean {
    const e = this.viewerEntry();
    return e !== null && e.contentType === 'video';
  }

  private viewerVideoSrc(): string {
    const e = this.viewerEntry();
    const p = e !== null ? e.videoPath : '';
    return p.startsWith('/') ? `file://${p}` : p;
  }

  private viewerVideoProgress(): number {
    const e = this.viewerEntry();
    return e !== null ? e.videoProgress : 0;
  }

  private viewerVideoReady(): boolean {
    const e = this.viewerEntry();
    return e !== null && e.videoPath !== '';
  }

  private viewerVideoFileId(): number {
    const e = this.viewerEntry();
    return e !== null ? e.videoFileId : 0;
  }

  private viewerVideoFileSize(): number {
    const e = this.viewerEntry();
    return e !== null ? e.videoFileSize : 0;
  }

  private viewerVideoMimeType(): string {
    const e = this.viewerEntry();
    return e !== null ? e.videoMimeType : '';
  }

  private viewerVideoWidth(): number {
    const e = this.viewerEntry();
    return e !== null ? e.photoWidth : 0;
  }

  private viewerVideoHeight(): number {
    const e = this.viewerEntry();
    return e !== null ? e.photoHeight : 0;
  }

  private viewerPhotoSrc(): string {
    const e = this.viewerEntry();
    if (e === null) {
      return '';
    }
    const p = e.photoFullPath !== '' ? e.photoFullPath : e.photoPath;
    return p.startsWith('/') ? `file://${p}` : p;
  }

  private viewerPhotoUpgrading(): boolean {
    const e = this.viewerEntry();
    return e !== null && e.photoFullPath === '' && e.photoFullFileId !== 0;
  }

  private viewerPhotoProgress(): number {
    const e = this.viewerEntry();
    return e !== null ? e.photoFullProgress : 0;
  }

  // Fullscreen viewer content: a Swiper over the album's members, so pages
  // follow the finger and slide continuously to the neighbor. Only the CURRENT
  // page mounts a video player; inactive video pages show their thumbnail.
  @Builder
  viewerContent() {
    Swiper(this.viewerSwiperCtrl) {
      ForEach(this.viewerSiblingIds(), (id: number) => {
        Stack() {
          if (this.viewerSiblingIsVideo(id)) {
            if (id === this.viewerMsgId && this.viewerVideoFileId() !== 0) {
              StreamingVideoPlayer({
                fileId: this.viewerVideoFileId(),
                fileSize: this.viewerVideoFileSize(),
                mimeType: this.viewerVideoMimeType(),
                videoWidth: this.viewerVideoWidth(),
                videoHeight: this.viewerVideoHeight(),
                showControls: this.chromeVisible,
                onDownloadProgress: (p: number): void => { this.viewerDlPercent = p; },
                onBackgroundTap: () => { this.toggleChrome(); },
                onSwipeNext: () => { this.switchViewer(1); },
                onSwipePrev: () => { this.switchViewer(-1); }
              });
            } else {
              if (this.viewerSiblingPath(id) !== '') {
                Image(this.viewerSiblingPath(id).startsWith('/')
                  ? `file://${this.viewerSiblingPath(id)}` : this.viewerSiblingPath(id))
                  .objectFit(ImageFit.Contain).width('100%').height('100%');
              }
              Stack() {
                Circle({ width: 56, height: 56 }).fill('#00000066');
                Text('▶').fontSize(24).fontColor(Color.White);
              }.width(56).height(56);
            }
          } else {
            if (this.photoSrcFor(id) !== '') {
              Image(this.photoSrcFor(id))
                .objectFit(ImageFit.Contain).width('100%').height('100%')
                .onClick(() => { this.closeViewer(); });
            }
          }
        }.width('100%').height('100%');
      }, (id: number) => `vm_${id}`);
    }
    .indicator(false)
    .loop(false)
    .index(this.viewerInitIdx)
    .onChange((i: number) => { this.onViewerPageChange(i); })
    .width('100%').height('100%');
    if (!this.viewerIsVideo() && this.viewerPhotoUpgrading()) {
      // Centered progress ring, same chrome style as the top-left close button.
      Stack() {
        Progress({ value: this.viewerPhotoProgress(), total: 100, type: ProgressType.Ring })
          .width(48).height(48).color(Color.White);
        Text(`${this.viewerPhotoProgress()}%`).fontSize(11).fontColor(Color.White);
      }
      .padding(12)
      .backgroundColor(VIEWER_CHROME_BG).borderRadius(36);
    }
  }

  // Thumbnail strip for the current message's album (photo/video list) —
  // tap a thumbnail to switch the viewer to that item.
  @Builder
  viewerFilmstrip() {
    Scroll() {
      Row({ space: 6 }) {
        ForEach(this.viewerSiblingIds(), (id: number) => {
          Stack() {
            if (this.viewerSiblingPath(id) !== '') {
              Image(this.viewerSiblingPath(id).startsWith('/') ? `file://${this.viewerSiblingPath(id)}` : this.viewerSiblingPath(id))
                .width(52).height(52).borderRadius(6).objectFit(ImageFit.Cover);
            } else {
              Column().width(52).height(52).borderRadius(6).backgroundColor('#333333');
            }
            if (this.viewerSiblingIsVideo(id)) {
              Text('▶').fontSize(14).fontColor(Color.White);
            }
          }
          .width(52).height(52)
          .border({ width: id === this.viewerMsgId ? 2 : 0, color: Color.White })
          .borderRadius(6)
          .onClick(() => { this.jumpToSibling(id); });
        }, (id: number) => `film_${id}`);
      }.padding({ left: 12, right: 12 });
    }.scrollable(ScrollDirection.Horizontal).width('100%');
  }

  // Bot inline-keyboard callback button: send the payload to the bot. The bot
  // reacts by editing the message / sending a new one (handled by updates).
  private onBotCallback(messageId: number, data: string): void {
    const payload: TdObject = { '@type': 'callbackQueryPayloadData' };
    payload['data'] = data;
    const req: TdRequest = { '@type': 'getCallbackQueryAnswer' };
    req['chat_id'] = this.chatId;
    req['message_id'] = messageId;
    req['payload'] = payload;
    getTdClient().send(req).catch((e: TdError) => {
      console.error(`ChatPage.getCallbackQueryAnswer failed: ${e.message}`);
    });
  }

  // Header avatar/title tap → detail page: users/bots get the personal
  // profile, groups/channels the chat profile.
  private openProfile(): void {
    const uid = this.store !== null ? this.store.getPeerUserId() : 0;
    if (uid > 0) {
      const params: Record<string, Object> = { 'userId': uid };
      router.pushUrl({ url: 'pages/profile/ProfilePage', params: params });
    } else {
      const params: Record<string, Object> = { 'chatId': this.chatId };
      router.pushUrl({ url: 'pages/profile/ChatProfilePage', params: params });
    }
  }

  // Refresh the '@' mention / '/' command suggestion panels for the new draft.
  private updateSuggestions(v: string): void {
    const cmd = v.match(/^\/([a-zA-Z0-9_]*)$/);
    if (cmd !== null) {
      this.mentionItems = [];
      this.refreshCommands();
      return;
    }
    this.commandItems = [];
    const at = v.match(/(?:^|\s)@([a-zA-Z0-9_]*)$/);
    if (at !== null && this.isGroup && !this.isChannel) {
      this.refreshMentions(at[1]);
      return;
    }
    this.mentionItems = [];
  }

  private refreshCommands(): void {
    if (!this.commandsLoaded) {
      this.commandsLoaded = true;
      const peer = this.store !== null ? this.store.getPeerUserId() : 0;
      loadBotCommands(getTdClient(), this.chatId, peer).then((items: CommandItem[]) => {
        this.allCommands = items;
        this.applyCommandFilter();
      });
      return; // the panel appears once the catalog resolves
    }
    this.applyCommandFilter();
  }

  // Filter against the CURRENT draft, so a slow catalog load can't show stale results.
  private applyCommandFilter(): void {
    const m = this.draft.match(/^\/([a-zA-Z0-9_]*)$/);
    if (m === null) {
      this.commandItems = [];
      return;
    }
    const q = m[1].toLowerCase();
    this.commandItems = this.allCommands.filter((c: CommandItem) => c.command.toLowerCase().includes(q));
  }

  private refreshMentions(query: string): void {
    const seq = ++this.mentionSeq;
    searchMentions(getTdClient(), this.chatId, query).then((items: MentionItem[]) => {
      // Drop the response if a newer query fired or the '@' trigger is gone.
      if (seq !== this.mentionSeq || this.draft.match(/(?:^|\s)@([a-zA-Z0-9_]*)$/) === null) {
        return;
      }
      this.mentionItems = items;
    });
  }

  // Replace the trailing '@token' with the chosen member.
  private pickMention(item: MentionItem): void {
    const idx = this.draft.lastIndexOf('@');
    const head = idx >= 0 ? this.draft.substring(0, idx) : this.draft;
    const token = item.username !== '' ? `@${item.username}` : item.name;
    this.draft = `${head}${token} `;
    this.mentionItems = [];
  }

  private pickCommand(item: CommandItem): void {
    this.draft = '';
    this.commandItems = [];
    if (this.store !== null) {
      this.atBottom = true;
      this.store.send(`/${item.command}`);
    }
  }

  // Viewer "保存到相册": photos save right away (full-res preferred); a video
  // that isn't fully local yet starts its download and saves automatically on
  // completion (see the pendingGallerySaveId check in the store subscription).
  private saveViewerMedia(): void {
    const e = this.entryById(this.viewerMsgId);
    if (e === null) {
      return;
    }
    const ctx = getContext(this) as common.UIAbilityContext;
    if (e.contentType === 'video') {
      if (e.videoPath !== '') {
        saveMediaToGallery(ctx, e.videoPath, true);
      } else {
        this.pendingGallerySaveId = e.id;
        if (this.store !== null) {
          this.store.requestVideoDownload(e.id, true);
        }
        promptAction.showToast({ message: '视频下载中，完成后自动保存到相册', duration: 2500 });
      }
      return;
    }
    const path = e.photoFullPath !== '' ? e.photoFullPath : e.photoPath;
    if (path !== '') {
      saveMediaToGallery(ctx, path, false);
    } else {
      promptAction.showToast({ message: '图片尚未加载完成', duration: 2000 });
    }
  }

  // Document card tap: download on first tap, open with a system app once local.
  private onFileTap(messageId: number): void {
    const m = this.messages.find((x: MessageEntry) => x.id === messageId);
    if (m === undefined || this.store === null) {
      return;
    }
    if (m.videoPath !== '') {
      openLocalFile(getContext(this) as common.UIAbilityContext, m.videoPath, m.videoMimeType);
    } else {
      this.store.requestVideoDownload(messageId, true);
    }
  }

  // Document card save arrow: opens the system "save as" picker once the file
  // is local; otherwise starts the download and saves automatically when done.
  private onFileSave(messageId: number): void {
    const m = this.messages.find((x: MessageEntry) => x.id === messageId);
    if (m === undefined || this.store === null) {
      return;
    }
    if (m.videoPath !== '') {
      saveFileToLocal(getContext(this) as common.UIAbilityContext, m.videoPath, m.videoFileName);
    } else {
      this.pendingFileSaveId = messageId;
      this.store.requestVideoDownload(messageId, true);
      promptAction.showToast({ message: '文件下载中，完成后选择保存位置', duration: 2500 });
    }
  }

  // --- header "more" menu actions ---
  private toggleChatMute(): void {
    const settings: TdObject = { '@type': 'chatNotificationSettings' };
    settings['use_default_mute_for'] = false;
    settings['mute_for'] = this.isMuted ? 0 : 2147483647; // 0 = unmute, max = forever
    const req: TdRequest = { '@type': 'setChatNotificationSettings' };
    req['chat_id'] = this.chatId;
    req['notification_settings'] = settings;
    getTdClient().send(req).catch((e: TdError) => {
      console.error(`ChatPage.toggleChatMute failed: ${e.message}`);
    });
  }

  private confirmClearHistory(): void {
    AlertDialog.show({
      message: '确定清空此聊天的历史记录吗？',
      autoCancel: true,
      primaryButton: {
        value: '取消',
        action: (): void => {}
      },
      secondaryButton: {
        value: '清空',
        fontColor: '#FF3B30',
        action: (): void => {
          const req: TdRequest = { '@type': 'deleteChatHistory' };
          req['chat_id'] = this.chatId;
          req['remove_from_chat_list'] = false;
          req['revoke'] = false;
          getTdClient().send(req).then(() => {
            promptAction.showToast({ message: '聊天记录已清空', duration: 2000 });
          }).catch((e: TdError) => {
            console.error(`ChatPage.deleteChatHistory failed: ${e.message}`);
            promptAction.showToast({ message: '清空失败', duration: 2000 });
          });
        }
      }
    });
  }

  private confirmLeaveChat(): void {
    AlertDialog.show({
      message: `确定退出「${this.title}」吗？`,
      autoCancel: true,
      primaryButton: {
        value: '取消',
        action: (): void => {}
      },
      secondaryButton: {
        value: '退出',
        fontColor: '#FF3B30',
        action: (): void => {
          const req: TdRequest = { '@type': 'leaveChat' };
          req['chat_id'] = this.chatId;
          getTdClient().send(req).then(() => {
            router.back();
          }).catch((e: TdError) => {
            console.error(`ChatPage.leaveChat failed: ${e.message}`);
            promptAction.showToast({ message: '退出失败', duration: 2000 });
          });
        }
      }
    });
  }

  @Builder
  headerMenuRow(symbol: string, label: string, danger: boolean, onTap: () => void) {
    Row({ space: 10 }) {
      SymbolGlyph($r(symbol)).fontSize(18)
        .fontColor([danger ? '#FF3B30' : COLOR_TEXT_PRIMARY]);
      Text(label).fontSize(15).fontColor(danger ? '#FF3B30' : COLOR_TEXT_PRIMARY);
    }
    .width('100%').padding({ left: 14, right: 14, top: 11, bottom: 11 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.headerMenuShow = false;
      onTap();
    });
  }

  @Builder
  headerMenu() {
    Column() {
      this.headerMenuRow('sys.symbol.magnifyingglass', '搜索', false, () => { this.enterSearch(); });
      Divider().color($r('app.color.divider')).strokeWidth(0.7);
      this.headerMenuRow('sys.symbol.info_circle', '资料', false, () => { this.openProfile(); });
      Divider().color($r('app.color.divider')).strokeWidth(0.7);
      this.headerMenuRow(this.isMuted ? 'sys.symbol.bell' : 'sys.symbol.bell_slash',
        this.isMuted ? '取消静音' : '静音', false, () => { this.toggleChatMute(); });
      Divider().color($r('app.color.divider')).strokeWidth(0.7);
      this.headerMenuRow('sys.symbol.xmark_circle', '清空聊天记录', false, () => { this.confirmClearHistory(); });
      if (this.isGroup) {
        Divider().color($r('app.color.divider')).strokeWidth(0.7);
        this.headerMenuRow('sys.symbol.trash', this.isChannel ? '退出频道' : '退出群组', true,
          () => { this.confirmLeaveChat(); });
      }
    }
    .width(200)
    .backgroundColor($r('app.color.surface'))
    .borderRadius(12);
  }

  // Horizontal center (vp, window coords) of the smiley button — the anchor
  // the emoji panel scales out of / back into.
  private emojiBtnCx: number = 48;
  @State inputBarH: number = 60; // measured input bar height — anchors the emoji overlay
  // "Fake" animation: the open/close transition flies an empty white shell;
  // the real panel content (hundreds of emoji + sticker players) mounts only
  // after the animation lands, so frames stay cheap.
  @State panelContentReady: boolean = false;
  private panelReadySeq: number = 0;
  // Show/hide the emoji/sticker panel with an animated slide (animateTo also
  // animates the list resize above it).
  private setEmojiPanel(show: boolean): void {
    if (this.showEmojiPanel === show) {
      return;
    }
    const seq = ++this.panelReadySeq;
    if (show) {
      animateTo({ duration: 220, curve: Curve.EaseOut }, () => {
        this.showEmojiPanel = true;
      });
      setTimeout(() => {
        if (seq === this.panelReadySeq && this.showEmojiPanel) {
          this.panelContentReady = true; // content pops in after the shell lands
        }
      }, 240);
    } else {
      this.panelContentReady = false; // unmount the heavy content first
      animateTo({ duration: 220, curve: Curve.EaseOut }, () => {
        this.showEmojiPanel = false;
      });
    }
  }

  // 菜单 pill: toggle the full bot-command catalog in the suggestion panel.
  private toggleBotMenu(): void {
    if (this.commandItems.length > 0) {
      this.commandItems = [];
    } else {
      this.mentionItems = [];
      this.setEmojiPanel(false);
      this.commandItems = this.allCommands;
    }
  }

  private insertEmoji(e: string): void {
    this.draft = `${this.draft}${e}`;
  }

  // Copy a picker URI into the sandbox so TDLib can read it; '' on failure.
  private copyUriToCache(uri: string): string {
    try {
      const name = decodeURIComponent(uri.substring(uri.lastIndexOf('/') + 1));
      const dest = `${(getContext(this) as common.UIAbilityContext).cacheDir}/send_${Date.now()}_${name}`;
      const src = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      fs.copyFileSync(src.fd, dest);
      fs.closeSync(src);
      return dest;
    } catch (e) {
      console.error(`ChatPage.copyUriToCache failed: ${e}`);
      return '';
    }
  }

  // Voice bubble asked for its file (eager download hasn't landed yet).
  private onVoiceTap(messageId: number): void {
    if (this.store !== null) {
      this.store.requestVideoDownload(messageId);
    }
    promptAction.showToast({ message: '语音加载中，请稍候', duration: 1500 });
  }

  // Paperclip → 照片或视频: system photo picker, send each as photo/video.
  private pickAndSendMedia(): void {
    const photoPicker = new photoAccessHelper.PhotoViewPicker();
    const opts = new photoAccessHelper.PhotoSelectOptions();
    opts.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_VIDEO_TYPE;
    opts.maxSelectNumber = 9;
    photoPicker.select(opts).then((res: photoAccessHelper.PhotoSelectResult) => {
      const caption = this.draft.trim();
      let usedCaption = false;
      for (const uri of res.photoUris) {
        const path = this.copyUriToCache(uri);
        if (path === '' || this.store === null) {
          continue;
        }
        const ext = path.substring(path.lastIndexOf('.') + 1).toLowerCase();
        const isVideo = ext === 'mp4' || ext === 'mov' || ext === 'mkv' || ext === 'avi' || ext === 'webm';
        this.atBottom = true;
        if (isVideo) {
          this.store.sendVideo(path, usedCaption ? '' : caption);
        } else {
          this.store.sendPhoto(path, usedCaption ? '' : caption);
        }
        usedCaption = true;
      }
      if (usedCaption && caption !== '') {
        this.draft = '';
      }
    }).catch((e: Object) => {
      console.error(`ChatPage.pickAndSendMedia failed: ${JSON.stringify(e)}`);
    });
  }

  // --- voice recording (mic button) ---
  private startRecording(): void {
    const rec = new VoiceRecorder();
    this.voiceRec = rec;
    rec.start(getContext(this) as common.UIAbilityContext).then((ok: boolean) => {
      if (!ok) {
        this.voiceRec = null;
        promptAction.showToast({ message: '无法开始录音（请检查麦克风权限）', duration: 2500 });
        return;
      }
      this.isRecording = true;
      this.recordSeconds = 0;
      this.recordTimer = setInterval(() => { this.recordSeconds += 1; }, 1000);
    });
  }

  private stopRecordTimer(): void {
    if (this.recordTimer !== -1) {
      clearInterval(this.recordTimer);
      this.recordTimer = -1;
    }
  }

  private finishRecording(): void {
    const rec = this.voiceRec;
    this.voiceRec = null;
    this.stopRecordTimer();
    this.isRecording = false;
    if (rec === null) {
      return;
    }
    rec.stop().then((duration: number) => {
      if (rec.path !== '' && this.store !== null) {
        this.atBottom = true;
        this.store.sendVoiceNote(rec.path, duration);
      }
    });
  }

  private cancelRecording(): void {
    const rec = this.voiceRec;
    this.voiceRec = null;
    this.stopRecordTimer();
    this.isRecording = false;
    if (rec !== null) {
      rec.cancel();
    }
  }

  private formatRecSeconds(): string {
    const m = Math.floor(this.recordSeconds / 60);
    const s = this.recordSeconds % 60;
    return `${m}:${`${s}`.padStart(2, '0')}`;
  }

  // Paperclip: pick a document, copy it into the app sandbox (TDLib can't read
  // picker URIs), then send it as a document message.
  private pickAndSendFile(): void {
    const docPicker = new picker.DocumentViewPicker(getContext(this) as common.UIAbilityContext);
    const opts = new picker.DocumentSelectOptions();
    opts.maxSelectNumber = 1;
    docPicker.select(opts).then((uris: string[]) => {
      if (uris.length === 0) {
        return;
      }
      try {
        const uri = uris[0];
        const name = decodeURIComponent(uri.substring(uri.lastIndexOf('/') + 1));
        const dest = `${(getContext(this) as common.UIAbilityContext).cacheDir}/send_${Date.now()}_${name}`;
        const src = fs.openSync(uri, fs.OpenMode.READ_ONLY);
        fs.copyFileSync(src.fd, dest);
        fs.closeSync(src);
        if (this.store !== null) {
          this.atBottom = true;
          this.store.sendDocument(dest, this.draft.trim());
          this.draft = '';
        }
      } catch (e) {
        console.error(`ChatPage.pickAndSendFile copy failed: ${e}`);
        promptAction.showToast({ message: '文件读取失败', duration: 2000 });
      }
    }).catch((e: Object) => {
      console.error(`ChatPage.pickAndSendFile select failed: ${JSON.stringify(e)}`);
    });
  }

  private doSend(): void {
    const t = this.draft.trim();
    if (t === '' || this.store === null) {
      return;
    }
    this.atBottom = true; // sending my own message always follows to the bottom
    this.store.send(t, this.replyToId);
    this.draft = '';
    this.clearReply();
    this.mentionItems = [];
    this.commandItems = [];
  }

  private findMsg(messageId: number): MessageEntry | null {
    for (const m of this.messages) {
      if (m.id === messageId) {
        return m;
      }
    }
    return null;
  }

  private clearReply(): void {
    this.replyToId = 0;
    this.replyToName = '';
    this.replyToText = '';
  }

  // Long-press menu: reply. Populates the reply preview above the input bar;
  // doSend() then attaches reply_to.
  private startReply(messageId: number): void {
    const m = this.findMsg(messageId);
    if (m === null) {
      return;
    }
    this.replyToId = messageId;
    this.replyToName = m.senderName !== '' ? m.senderName : this.title;
    this.replyToText = m.text !== '' ? m.text : '[媒体]';
  }

  // --- multi-select ---
  private enterSelect(messageId: number): void {
    ContextMenu.close();
    this.selecting = true;
    this.selectedIds = [messageId];
  }

  private exitSelect(): void {
    this.selecting = false;
    this.selectedIds = [];
  }

  private rowSelected(g: AlbumGroup): boolean {
    for (const id of g.memberIds) {
      if (this.selectedIds.indexOf(id) >= 0) {
        return true;
      }
    }
    return false;
  }

  // Toggle a whole display row (an album row selects all its members).
  private toggleSelectRow(g: AlbumGroup): void {
    if (g.head.contentType === 'system' || g.head.contentType === 'hidden') {
      return;
    }
    if (this.rowSelected(g)) {
      this.selectedIds = this.selectedIds.filter((id: number) => g.memberIds.indexOf(id) < 0);
    } else {
      this.selectedIds = [...this.selectedIds, ...g.memberIds];
    }
  }

  private copySelected(): void {
    const sorted = [...this.selectedIds].sort((a: number, b: number) => a - b);
    const parts: string[] = [];
    for (const id of sorted) {
      const m = this.findMsg(id);
      if (m !== null && m.text !== '') {
        parts.push(m.text);
      }
    }
    if (parts.length === 0) {
      promptAction.showToast({ message: '没有可复制的文本', duration: 1500 });
      return;
    }
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, parts.join('\n\n'));
    pasteboard.getSystemPasteboard().setData(data).then(() => {
      promptAction.showToast({ message: `已复制 ${parts.length} 条消息`, duration: 1200 });
      this.exitSelect();
    }).catch((e: Object) => { console.error(`ChatPage.copySelected failed: ${JSON.stringify(e)}`); });
  }

  private deleteSelected(): void {
    const n = this.selectedIds.length;
    if (n === 0) {
      return;
    }
    promptAction.showDialog({
      title: `删除 ${n} 条消息?`,
      message: '"为所有人删除"仅在权限允许时生效',
      buttons: [
        { text: '取消', color: '#8E8E93' },
        { text: '为我删除', color: '#FF3B30' },
        { text: '为所有人删除', color: '#FF3B30' }
      ]
    }).then((r) => {
      if (r.index !== 1 && r.index !== 2) {
        return;
      }
      const req: TdRequest = { '@type': 'deleteMessages' };
      req['chat_id'] = this.chatId;
      req['message_ids'] = [...this.selectedIds];
      req['revoke'] = r.index === 2;
      getTdClient().send(req).then(() => {
        this.exitSelect();
      }).catch((e: TdError) => {
        console.error(`ChatPage.deleteMessages failed: ${e.message}`);
        promptAction.showToast({ message: `删除失败：${e.message}`, duration: 2000 });
      });
    });
  }

  private copyMessageText(messageId: number): void {
    const m = this.findMsg(messageId);
    if (m === null || m.text === '') {
      promptAction.showToast({ message: '没有可复制的文本', duration: 1500 });
      return;
    }
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, m.text);
    pasteboard.getSystemPasteboard().setData(data).then(() => {
      promptAction.showToast({ message: '已复制', duration: 1200 });
    }).catch((e: Object) => { console.error(`ChatPage.copyMessageText failed: ${JSON.stringify(e)}`); });
  }

  private copyMessageLink(messageId: number): void {
    if (this.store === null) {
      return;
    }
    this.store.messageLink(messageId, (url: string) => {
      if (url === '') {
        promptAction.showToast({ message: '无法获取链接（可能是私密聊天）', duration: 1800 });
        return;
      }
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, url);
      pasteboard.getSystemPasteboard().setData(data).then(() => {
        promptAction.showToast({ message: '链接已复制', duration: 1200 });
      }).catch((e: Object) => { console.error(`ChatPage.copyMessageLink failed: ${JSON.stringify(e)}`); });
    });
  }

  private toggleReaction(messageId: number, emoji: string, isChosen: boolean): void {
    if (this.store !== null) {
      this.store.setReaction(messageId, emoji, isChosen);
    }
  }

  private openReactionSheet(messageId: number): void {
    this.reactionTargetId = messageId;
    this.showReactionSheet = true;
  }

  // Pick from the full emoji sheet — always adds the reaction to the target.
  private pickReaction(emoji: string): void {
    if (this.store !== null && this.reactionTargetId !== 0) {
      this.store.setReaction(this.reactionTargetId, emoji, false);
    }
    this.showReactionSheet = false;
  }

  @Builder
  circleButton(symbol: string, onTap: () => void) {
    Row() {
      SymbolGlyph($r(symbol)).fontSize(22).fontColor([COLOR_TEXT_PRIMARY]);
    }
    .width(40).height(40).borderRadius(20).backgroundColor($r('app.color.surface'))
    .justifyContent(FlexAlign.Center)
    .shadow({ radius: 4, color: '#12000000', offsetX: 0, offsetY: 1 })
    .onClick(onTap);
  }

  // Multi-select header: ✕ / count / copy / delete.
  @Builder
  selectionHeader() {
    Row({ space: 8 }) {
      this.circleButton('sys.symbol.xmark', () => { this.exitSelect(); });
      Text(`已选择 ${this.selectedIds.length}`)
        .fontSize(17).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY)
        .layoutWeight(1).margin({ left: 6 });
      this.circleButton('sys.symbol.plus_square_on_square', () => { this.copySelected(); });
      Row() {
        SymbolGlyph($r('sys.symbol.trash')).fontSize(22).fontColor(['#FF3B30']);
      }
      .width(40).height(40).borderRadius(20).backgroundColor($r('app.color.surface'))
      .justifyContent(FlexAlign.Center)
      .shadow({ radius: 4, color: '#12000000', offsetX: 0, offsetY: 1 })
      .onClick(() => { this.deleteSelected(); });
    }
    .width('100%').padding({ left: 12, right: 12, top: this.topSafe + 10, bottom: 10 })
    .alignItems(VerticalAlign.Center);
  }

  // Search-mode header: back button + a full-width query input.
  @Builder
  searchHeader() {
    Row({ space: 8 }) {
      this.circleButton('sys.symbol.chevron_left', () => { this.exitSearch(); });
      TextInput({ text: this.searchQuery, placeholder: '搜索' })
        .layoutWeight(1).height(40)
        .backgroundColor($r('app.color.surface')).borderRadius(20)
        .defaultFocus(true)
        .onChange((v: string) => { this.searchQuery = v; })
        .onSubmit(() => { this.runSearch(0, 0); });
    }
    .width('100%').padding({ left: 12, right: 12, top: this.topSafe + 10, bottom: 10 })
    .alignItems(VerticalAlign.Center);
  }

  @Builder
  header() {
    Row() {
      this.circleButton('sys.symbol.chevron_left', () => { router.back(); });
      AvatarView({ avatarPath: this.avatarPath, initials: this.initials, colorSeed: this.chatId, avatarSize: 40 })
        .margin({ left: 8 })
        .onClick(() => { this.openProfile(); });
      Column() {
        Row() {
          // No layoutWeight on the title: the bell sits right next to the text
          // instead of being pushed to the pill's far edge.
          Text(this.title).fontSize(16).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .flexShrink(1)
            .constraintSize({ maxWidth: '88%' });
          if (this.headerEmojiPath !== '') {
            if (this.headerEmojiFormat === 'tgs') {
              TgsStickerView({ tgsPath: this.headerEmojiPath, boxWidth: 18, boxHeight: 18 })
                .margin({ left: 4 });
            } else if (this.headerEmojiFormat === 'webm') {
              WebmStickerView({ webmPath: this.headerEmojiPath, boxWidth: 18, boxHeight: 18 })
                .margin({ left: 4 });
            } else {
              Image(`file://${this.headerEmojiPath}`).width(18).height(18).objectFit(ImageFit.Contain)
                .margin({ left: 4 });
            }
          }
          if (this.isMuted) {
            SymbolGlyph($r('sys.symbol.bell_slash')).fontSize(15).fontColor([COLOR_TEXT_SECONDARY])
              .margin({ left: 4 });
          }
        }.width('100%').alignItems(VerticalAlign.Center);
        if (this.subtitle !== '') {
          Text(this.subtitle).fontSize(12).fontColor(COLOR_TEXT_SECONDARY).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis }).margin({ top: 1 });
        }
      }
      .alignItems(HorizontalAlign.Start).layoutWeight(1).margin({ left: 8, right: 10 })
      .padding({ left: 12, right: 12, top: 5, bottom: 5 })
      .borderRadius(20).backgroundColor($r('app.color.surface'))
      .shadow({ radius: 4, color: '#12000000', offsetX: 0, offsetY: 1 })
      .onClick(() => { this.openProfile(); });
      Row() {
        SymbolGlyph($r('sys.symbol.more')).fontSize(22).fontColor([COLOR_TEXT_PRIMARY]);
      }
      .width(40).height(40).borderRadius(20).backgroundColor($r('app.color.surface'))
      .justifyContent(FlexAlign.Center)
      .shadow({ radius: 4, color: '#12000000', offsetX: 0, offsetY: 1 })
      .bindMenu(this.headerMenuShow, this.headerMenu(), {
        onDisappear: (): void => { this.headerMenuShow = false; }
      })
      .onClick(() => { this.headerMenuShow = true; });
    }.width('100%').padding({ left: 12, right: 12, top: this.topSafe + 10, bottom: 10 })
    .alignItems(VerticalAlign.Center);
  }

  // Suggestion panel above the input bar: group members for a trailing '@',
  // bot commands for a leading '/'.
  @Builder
  suggestionPanel() {
    List() {
      ForEach(this.mentionItems, (it: MentionItem) => {
        ListItem() {
          Row({ space: 10 }) {
            AvatarView({ avatarPath: '', initials: it.name.substring(0, 1).toUpperCase(),
              colorSeed: it.userId, avatarSize: 32 });
            Text(it.name).fontSize(15).fontColor(COLOR_TEXT_PRIMARY).maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis });
            if (it.username !== '') {
              Text(`@${it.username}`).fontSize(13).fontColor(COLOR_TEXT_SECONDARY).maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis });
            }
          }
          .width('100%').padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .alignItems(VerticalAlign.Center)
          .onClick(() => { this.pickMention(it); });
        }
      }, (it: MentionItem) => `m${it.userId}`);
      ForEach(this.commandItems, (it: CommandItem) => {
        ListItem() {
          Row({ space: 10 }) {
            Text(`/${it.command}`).fontSize(15).fontColor(COLOR_PRIMARY);
            Text(it.description).fontSize(13).fontColor(COLOR_TEXT_SECONDARY).maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1);
          }
          .width('100%').padding({ left: 14, right: 14, top: 10, bottom: 10 })
          .alignItems(VerticalAlign.Center)
          .onClick(() => { this.pickCommand(it); });
        }
      }, (it: CommandItem) => `c${it.command}`);
    }
    .width('100%')
    .constraintSize({ maxHeight: 240 })
    .backgroundColor($r('app.color.surface'))
    .divider({ strokeWidth: 0.7, color: $r('app.color.divider'), startMargin: 14, endMargin: 14 });
  }

  // Reply preview strip above the input bar (Telegram style): accent bar, sender
  // name, message excerpt, and an ✕ to cancel.
  @Builder
  replyPreview() {
    Row({ space: 10 }) {
      SymbolGlyph($r('sys.symbol.arrowshape_turn_up_left')).fontSize(20).fontColor([COLOR_PRIMARY]);
      Column({ space: 1 }) {
        Text(this.replyToName).fontSize(13).fontColor(COLOR_PRIMARY).fontWeight(FontWeight.Medium)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
        Text(this.replyToText).fontSize(13).fontColor(COLOR_TEXT_SECONDARY)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
      }.alignItems(HorizontalAlign.Start).layoutWeight(1);
      SymbolGlyph($r('sys.symbol.xmark')).fontSize(18).fontColor([COLOR_TEXT_SECONDARY])
        .onClick(() => { this.clearReply(); });
    }
    .width('100%').padding({ left: 16, right: 16, top: 7, bottom: 7 })
    .backgroundColor($r('app.color.surface'))
    .border({ width: { top: 0.7 }, color: $r('app.color.divider') })
    .alignItems(VerticalAlign.Center);
  }

  // Full emoji reaction picker (opened from the long-press menu chevron): a
  // bottom sheet grid; tapping an emoji adds it as a reaction to the target.
  @Builder
  reactionSheet() {
    Column() {
      Column().layoutWeight(1)
        .onClick(() => { this.showReactionSheet = false; });
      Column({ space: 8 }) {
        Row().width(40).height(4).borderRadius(2).backgroundColor('#D0D0D0');
        Text('选择表情回应').fontSize(15).fontColor(COLOR_TEXT_PRIMARY).fontWeight(FontWeight.Medium);
        Scroll() {
          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
            ForEach(REACTION_EMOJIS, (e: string) => {
              Text(e).fontSize(28).padding(7)
                .onClick(() => { this.pickReaction(e); });
            }, (e: string) => e);
          }.width('100%');
        }.constraintSize({ maxHeight: 300 }).scrollBar(BarState.Off);
      }
      .width('100%').padding({ left: 10, right: 10, top: 10, bottom: 20 + this.bottomInset() })
      .backgroundColor($r('app.color.surface'))
      .borderRadius({ topLeft: 18, topRight: 18 });
    }
    .width('100%').height('100%')
    .backgroundColor('#00000066');
  }

  @Builder
  inputBar() {
    Row({ space: 8 }) {
      if (this.isRecording) {
        // Recording mode: red dot + timer, 取消, send.
        Row({ space: 8 }) {
          Circle({ width: 10, height: 10 }).fill('#FF3B30');
          Text(this.formatRecSeconds()).fontSize(16).fontColor(COLOR_TEXT_PRIMARY);
          Text('正在录音...').fontSize(14).fontColor(COLOR_TEXT_SECONDARY);
        }.layoutWeight(1).alignItems(VerticalAlign.Center);
        Button('取消').fontSize(14).fontColor(COLOR_TEXT_SECONDARY)
          .backgroundColor(Color.Transparent)
          .onClick(() => { this.cancelRecording(); });
        Button() {
          SymbolGlyph($r('sys.symbol.paperplane')).fontSize(22).fontColor([Color.White]);
        }
        .width(44).height(44).backgroundColor(COLOR_PRIMARY).borderRadius(22)
        .onClick(() => { this.finishRecording(); });
      } else {
        if (this.botMenuAvailable) {
          // Bot 菜单 pill — toggles the full command catalog.
          Row({ space: 4 }) {
            SymbolGlyph($r('sys.symbol.line_3_horizontal')).fontSize(16).fontColor([Color.White]);
            Text('菜单').fontSize(14).fontColor(Color.White);
          }
          .padding({ left: 10, right: 12, top: 7, bottom: 7 })
          .backgroundColor(COLOR_PRIMARY).borderRadius(17)
          .onClick(() => { this.toggleBotMenu(); });
        }
        SymbolGlyph($r(this.showEmojiPanel ? 'sys.symbol.face_smiling_fill' : 'sys.symbol.face_smiling'))
          .fontSize(24).fontColor([this.showEmojiPanel ? COLOR_PRIMARY : COLOR_TEXT_SECONDARY])
          .onAreaChange((_old: Area, area: Area) => {
            const gx = area.globalPosition.x as number;
            this.emojiBtnCx = gx + (area.width as number) / 2;
          })
          .onClick(() => {
            this.setEmojiPanel(!this.showEmojiPanel);
            this.mentionItems = [];
            this.commandItems = [];
          });
        TextInput({ text: this.draft, placeholder: 'Message' })
          .layoutWeight(1).onChange((v: string) => {
            this.draft = v;
            this.updateSuggestions(v);
          })
          .onFocus(() => { this.setEmojiPanel(false); });
        SymbolGlyph($r('sys.symbol.paperclip')).fontSize(24).fontColor([COLOR_TEXT_SECONDARY])
          .bindMenu([
            { value: '照片或视频', action: (): void => { this.pickAndSendMedia(); } } as MenuElement,
            { value: '文件', action: (): void => { this.pickAndSendFile(); } } as MenuElement
          ]);
        // Mic ↔ send swap: outgoing icon shrinks/fades while the incoming one
        // scales in (the send button adds a small un-rotate flourish).
        Stack() {
          if (this.draft.trim() === '') {
            Button() {
              SymbolGlyph($r('sys.symbol.mic')).fontSize(22).fontColor([Color.White]);
            }
            .width(44).height(44).backgroundColor(COLOR_PRIMARY).borderRadius(22)
            .transition(TransitionEffect.OPACITY
              .combine(TransitionEffect.scale({ x: 0.3, y: 0.3 }))
              .animation({ duration: 200, curve: Curve.EaseOut }))
            .onClick(() => { this.startRecording(); });
          } else {
            Button() {
              SymbolGlyph($r('sys.symbol.paperplane')).fontSize(22).fontColor([Color.White]);
            }
            .width(44).height(44).backgroundColor(COLOR_PRIMARY).borderRadius(22)
            .transition(TransitionEffect.OPACITY
              .combine(TransitionEffect.scale({ x: 0.3, y: 0.3 }))
              .combine(TransitionEffect.rotate({ angle: -45 }))
              .animation({ duration: 200, curve: Curve.EaseOut }))
            .onClick(() => { this.doSend(); });
          }
        }.width(44).height(44);
      }
    }.width('100%').padding({ left: 12, right: 12, top: 8, bottom: this.bottomInset() })
    .alignItems(VerticalAlign.Center)
    .onAreaChange((_old: Area, area: Area) => { this.inputBarH = area.height as number; });
  }

  // Segmented indicator like Telegram: short vertical bars, the currently-shown
  // pinned message highlighted. A sliding window of up to PINNED_SEG_MAX bars so
  // the highlight moves on every tap (and the window scrolls past the window size).
  private pinnedShownIdx(): number {
    return Math.min(this.pinnedCycle, Math.max(0, this.pinnedCount - 1));
  }

  private pinnedSegCount(): number {
    return Math.min(this.pinnedCount, PINNED_SEG_MAX);
  }

  // Segments run oldest (top) → newest (bottom), so the newest pinned message
  // highlights the BOTTOM bar. pinnedShownIdx() is in newest-first space and
  // gets flipped into this display space.
  private pinnedDispActive(): number {
    return Math.max(0, this.pinnedCount - 1 - this.pinnedShownIdx());
  }

  private pinnedSegStart(): number {
    const n: number = this.pinnedSegCount();
    if (this.pinnedCount <= n) {
      return 0;
    }
    const s: number = this.pinnedDispActive() - (n - 1);
    return Math.max(0, Math.min(s, this.pinnedCount - n));
  }

  private pinnedSegs(): number[] {
    const n: number = this.pinnedSegCount();
    const a: number[] = [];
    for (let i = 0; i < n; i++) {
      a.push(i);
    }
    return a;
  }

  private pinnedActiveSeg(): number {
    return this.pinnedDispActive() - this.pinnedSegStart();
  }

  @Builder
  pinnedBanner() {
    Row() {
      Column() {
        ForEach(this.pinnedSegs(), (i: number) => {
          Column().width(3).layoutWeight(1)
            .backgroundColor(i === this.pinnedActiveSeg() ? COLOR_PRIMARY : '#6e3e3e40')
            .borderRadius(1.5).margin({ top: 1, bottom: 1 });
        }, (i: number) => `seg_${i}_${i === this.pinnedActiveSeg()}`);
      }.height(34).width(3);
      Column() {
        Text('置顶消息').fontSize(12).fontColor(COLOR_PRIMARY).fontWeight(FontWeight.Medium);
        Text(this.pinnedPreview).fontSize(13).fontColor(COLOR_TEXT_PRIMARY)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
      }.alignItems(HorizontalAlign.Start).layoutWeight(1).margin({ left: 8 });
    }
    .width('100%').padding({ left: 12, right: 16, top: 6, bottom: 6 })
    .backgroundColor($r('app.color.surface')).alignItems(VerticalAlign.Center)
    .onClick(() => { this.onPinnedTap(); });
  }

  @Builder
  scrollFab() {
    Column() {
      if (this.unreadBadge > 0) {
        Text(`${this.unreadBadge}`)
          .fontSize(12).fontColor(Color.White).backgroundColor(COLOR_PRIMARY)
          .constraintSize({ minWidth: 22 }).height(20).borderRadius(10)
          .textAlign(TextAlign.Center).padding({ left: 6, right: 6 }).margin({ bottom: 3 });
      }
      Button() {
        SymbolGlyph($r('sys.symbol.chevron_down')).fontSize(22).fontColor([COLOR_TEXT_PRIMARY]);
      }
      .width(46).height(46).borderRadius(23).backgroundColor($r('app.color.surface'))
      .shadow({ radius: 6, color: '#26000000', offsetX: 0, offsetY: 2 })
      .onClick(() => {
        this.atBottom = true;
        // Far from the live tail — unloaded pages below, OR a long stretch of
        // already-loaded history (scrollToIndex over thousands of lazy rows
        // still lays them out one by one and visibly crawls): drop the loaded
        // window and reload just the newest page.
        const farFromEnd: boolean = this.groups.length - this.curStartIdx > JUMP_RELOAD_THRESHOLD;
        if (this.store !== null && (this.store.getHasMoreNewer() || farFromEnd)) {
          this.pendingScrollBottom = true;
          this.store.jumpToLatest();
        } else {
          // Close to the end and fully loaded — snap instantly, no animated crawl.
          this.scroller.scrollToIndex(Math.max(0, this.groups.length - 1), false, ScrollAlign.END);
        }
      });
    }
    .alignItems(HorizontalAlign.End);
  }

  build() {
    Stack() {
      Column() {
        if (this.selecting) {
          this.selectionHeader();
        } else if (this.searchMode) {
          this.searchHeader();
        } else {
          this.header();
        }
        if (this.pinnedPreview !== '') {
          this.pinnedBanner();
        }
        Stack() {
        List({ scroller: this.scroller }) {
          // LazyForEach (not ForEach) is required for maintainVisibleContentPosition
          // to hold the scroll position when older pages are prepended above.
          LazyForEach(this.groupsData, (g: AlbumGroup) => {
            ListItem() {
              Stack({ alignContent: Alignment.Start }) {
              // Selection mode shifts the row right into a left check gutter
              // (instead of overlaying the check on the avatars).
              Row() {
              if (this.selecting && g.head.contentType !== 'system' && g.head.contentType !== 'hidden') {
                Column() {
                  if (this.rowSelected(g)) {
                    SymbolGlyph($r('sys.symbol.checkmark_circle'))
                      .fontSize(22).fontColor([COLOR_PRIMARY]);
                  } else {
                    Row()
                      .width(20).height(20).borderRadius(10)
                      .border({ width: 1.5, color: '#8E8E93' });
                  }
                }
                .width(34)
                .justifyContent(FlexAlign.Center)
                .alignItems(HorizontalAlign.Center);
              }
              Column() {
              MessageBubble({ msg: g.head, nowSec: this.nowSec, isGroup: this.isGroup, isChannel: this.isChannel,
                showUnreadDivider: this.firstUnreadId !== 0 && g.head.id === this.firstUnreadId,
                dateLabel: g.dateLabel,
                albumPaths: g.photoPaths, albumRatios: g.photoRatios,
                albumMemberIds: g.memberIds, albumIsVideo: g.photoIsVideo,
                albumProgress: g.photoProgress, albumCaption: g.caption,
                albumCaptionEntities: g.captionEntities,
                hiddenMediaId: this.viewerMsgId,
                onMediaTap: (id: number, x: number, y: number): void => {
                  this.tapX = x;
                  this.tapY = y;
                  this.openViewer(id);
                },
                onLinkTap: (u: string): void => { this.onLinkTap(u); },
                onCommentTap: (id: number): void => { this.onCommentTap(id); },
                onBotCallback: (id: number, data: string): void => { this.onBotCallback(id, data); },
                onAvatarTap: (uid: number): void => {
                  const params: Record<string, Object> = { 'userId': uid };
                  router.pushUrl({ url: 'pages/profile/ProfilePage', params: params });
                },
                onReplyTap: (id: number): void => { this.onReplyTap(id); },
                onFileTap: (id: number): void => { this.onFileTap(id); },
                onFileSave: (id: number): void => { this.onFileSave(id); },
                onVoiceTap: (id: number): void => { this.onVoiceTap(id); },
                onSetReaction: (id: number, emoji: string, chosen: boolean): void => { this.toggleReaction(id, emoji, chosen); },
                onReplyTo: (id: number): void => { this.startReply(id); },
                onCopyText: (id: number): void => { this.copyMessageText(id); },
                onCopyLink: (id: number): void => { this.copyMessageLink(id); },
                onForwardMsg: (id: number): void => { promptAction.showToast({ message: '转发功能开发中', duration: 1500 }); },
                onReportMsg: (id: number): void => { promptAction.showToast({ message: '举报功能开发中', duration: 1500 }); },
                onSelectMsg: (id: number): void => { this.enterSelect(id); },
                onOpenReactions: (id: number): void => { this.openReactionSheet(id); },
                showAvatar: g.showAvatar,
                showSenderName: g.showSenderName,
                animateIn: this.freshSinceId !== 0 && g.head.id > this.freshSinceId });
              }
              .layoutWeight(1);
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)
              .backgroundColor(this.selecting && this.rowSelected(g) ? $r('app.color.select_highlight') : Color.Transparent)
              // Selection mode: the row itself takes every tap (children are
              // excluded from hit-testing), so any tap toggles selection.
              .hitTestBehavior(this.selecting && g.head.contentType !== 'system' && g.head.contentType !== 'hidden'
                ? HitTestMode.Block : HitTestMode.Default)
              .onClick(() => {
                if (this.selecting) {
                  this.toggleSelectRow(g);
                }
              });
              }
            }
          }, (g: AlbumGroup) => g.key);
        }
        .width('100%').height('100%')
        // Keep the visible messages pinned in place when an older page is
        // prepended above — without this, the List stays index-anchored and
        // visibly jumps to the top of the newly loaded page.
        .maintainVisibleContentPosition(true)
        .onReachStart(() => { this.maybeLoadOlder(); })
        // Each new touch gesture re-arms one older-page load: a fling that ends
        // pinned at the very top (start index never leaves the trigger zone)
        // would otherwise never re-arm, leaving the user unable to load more.
        .onTouch((e: TouchEvent) => {
          if (e.type === TouchType.Down) {
            this.olderArmed = true;
            // The highlight overlay is viewport-anchored — drop it as soon as
            // the user starts interacting, before it can detach from its row.
            this.cancelFlash();
            // Tapping outside the emoji/sticker panel dismisses it.
            this.setEmojiPanel(false);
          }
        })
        .onScrollIndex((start: number, end: number) => {
          // Freeze the at-bottom flag while the media viewer is open — the
          // hidden thumbnail collapses its row, faking a near-bottom index.
          if (this.viewerMsgId === 0) {
            this.atBottom = end >= this.groups.length - 2;
          }
          this.curStartIdx = start;
          this.updateFloatDate(start);
          this.markVisibleRead(end);
          this.updatePinnedFromScroll(start);
          // Prefetch: kick off the previous/next page a few rows before the edge,
          // so scrolling never actually hits an empty top/bottom. loadOlder is
          // one-shot per arm (see maybeLoadOlder) so a fling that stays pinned
          // at the top can't chain-load page after page.
          if (start > 4) {
            this.olderArmed = true; // moved clear of the top zone — re-arm
          } else {
            this.maybeLoadOlder();
          }
          if (this.store !== null && end >= this.groups.length - 5) {
            this.store.loadNewer();
          }
        });
        // Jump-target highlight overlay (gentle double blink over the row a
        // reply/pinned/link jump just landed on). Coordinates come from
        // scroller.getItemRect, which is relative to the List — hence the Stack.
        if (this.flashShown) {
          Column()
            .width('100%').height(this.flashHeight)
            .backgroundColor('#4D67A0DC')
            .borderRadius(8)
            .opacity(this.flashAlpha)
            .position({ x: 0, y: this.flashTop })
            .hitTestBehavior(HitTestMode.None);
        }
        // Floating date chip at the top of the viewport — tracks the topmost
        // visible message while scrolling, fades away when scrolling stops.
        if (this.floatDate !== '') {
          Row() {
            Text(this.floatDate)
              .fontSize(12).fontColor(COLOR_TEXT_SECONDARY).fontWeight(FontWeight.Medium)
              .backgroundColor($r('app.color.system_pill')).borderRadius(11)
              .padding({ left: 10, right: 10, top: 3, bottom: 3 });
          }
          .width('100%').justifyContent(FlexAlign.Center).margin({ top: 8 })
          .opacity(this.floatDateShown ? 1 : 0)
          .animation({ duration: 250, curve: Curve.EaseOut })
          .hitTestBehavior(HitTestMode.None);
        }
        }
        .layoutWeight(1).width('100%')
        .alignContent(Alignment.TopStart);
        if (this.mentionItems.length > 0 || this.commandItems.length > 0) {
          this.suggestionPanel();
        }
        if (this.searchMode) {
          // Search bottom bar: current position / total matches.
          Row() {
            Text(this.searchResults.length > 0
              // Counted from the oldest match: the newest (entry point) reads
              // total/total and going up (older) counts down.
              ? `${this.searchTotal - this.searchIdx} / ${this.searchTotal}`
              : (this.searchTotal === 0 && this.searchQuery.trim() !== '' ? '' : '输入关键词搜索'))
              .fontSize(15).fontColor(COLOR_TEXT_PRIMARY);
            Blank().layoutWeight(1);
          }
          .width('100%').padding({ left: 20, right: 20, top: 12, bottom: 4 + this.bottomInset() })
          .backgroundColor($r('app.color.surface'));
        } else {
          if (this.replyToId !== 0) {
            this.replyPreview();
          }
          this.inputBar();
        }
      }
      .width('100%').height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.chat_bg'));

      // Emoji/sticker panel OVERLAYS the chat (not in the layout flow): the
      // message list keeps its height, so its scrollbar/FAB stay put, and the
      // open/close animation doesn't relayout the LazyForEach every frame.
      if (this.showEmojiPanel) {
        // Full-height wrapper only positions the panel above the input bar;
        // Transparent hit-testing lets taps outside the panel reach the list.
        Column() {
          Column() {
            if (this.panelContentReady) {
              EmojiPanel({
                onPick: (e: string): void => { this.insertEmoji(e); },
                onPickCustomEmoji: (e: string, ceId: string): void => {
                  if (this.store !== null) {
                    this.atBottom = true;
                    this.store.sendCustomEmoji(e, ceId);
                  }
                },
                onPickSticker: (s: StickerItem): void => {
                  if (this.store !== null) {
                    this.atBottom = true;
                    this.store.sendSticker(s.fileId, s.width, s.height);
                  }
                },
                onPickGif: (g: GifItem): void => {
                  if (this.store !== null) {
                    this.atBottom = true;
                    this.store.sendAnimation(g.fileId, g.width, g.height, g.duration);
                  }
                }
              });
            }
          }
          .width('100%').height(300)
          .backgroundColor($r('app.color.surface'))
          .shadow({ radius: 12, color: '#22000000', offsetX: 0, offsetY: -2 })
          // Hero-style: grow out of the smiley button, shrink back into it.
          .transition(TransitionEffect.scale({ x: 0.05, y: 0.05, centerX: this.emojiBtnCx, centerY: '100%' })
            .combine(TransitionEffect.OPACITY)
            .animation({ duration: 220, curve: Curve.EaseOut }));
        }
        .width('100%').height('100%')
        .justifyContent(FlexAlign.End)
        .padding({ bottom: this.inputBarH })
        // None (not Transparent): the wrapper itself never hit-tests, so the
        // panel child blocks touches over its own area (Transparent leaked
        // panel taps through to the list, whose onTouch dismissed the panel),
        // while the area outside the panel still reaches the list/input bar.
        .hitTestBehavior(HitTestMode.None);
      }
      if (this.showReactionSheet) {
        this.reactionSheet();
      }
      // Search result navigation: ∧ older match / ∨ newer match, right edge.
      if (this.searchMode && this.searchResults.length > 0) {
        Column({ space: 10 }) {
          Row() {
            SymbolGlyph($r('sys.symbol.chevron_up')).fontSize(22).fontColor([COLOR_TEXT_PRIMARY]);
          }
          .width(46).height(46).borderRadius(23).backgroundColor($r('app.color.surface'))
          .justifyContent(FlexAlign.Center)
          .shadow({ radius: 6, color: '#26000000', offsetX: 0, offsetY: 2 })
          .opacity(this.searchIdx + 1 < this.searchTotal ? 1 : 0.4)
          .onClick(() => { this.searchOlder(); });
          Row() {
            SymbolGlyph($r('sys.symbol.chevron_down')).fontSize(22).fontColor([COLOR_TEXT_PRIMARY]);
          }
          .width(46).height(46).borderRadius(23).backgroundColor($r('app.color.surface'))
          .justifyContent(FlexAlign.Center)
          .shadow({ radius: 6, color: '#26000000', offsetX: 0, offsetY: 2 })
          .opacity(this.searchIdx > 0 ? 1 : 0.4)
          .onClick(() => { this.searchNewer(); });
        }
        .position({ x: '100%', y: '100%' })
        .markAnchor({ x: '100%', y: '100%' })
        .offset({ x: -14, y: -(152 + this.bottomInset()) });
      }
      if (!this.atBottom && !this.searchMode) {
        Column() {
          this.scrollFab();
        }
        .width('100%').height('100%')
        .justifyContent(FlexAlign.End).alignItems(HorizontalAlign.End)
        .padding({ right: 14, bottom: 72 })
        .hitTestBehavior(HitTestMode.Transparent);
      }

      if (this.viewerMsgId !== 0) {
        Stack() {
          this.viewerContent();
          if (this.chromeVisible) {
            // Content-height wrapper pinned to the top — a full-screen wrapper here
            // (default hit-test mode) would block ALL touches on the player below it.
            Row() {
              Row({ space: 10 }) {
                Stack() {
                  Circle({ width: 36, height: 36 }).fill('#00000000');
                  SymbolGlyph($r('sys.symbol.xmark')).fontSize(18).fontColor([Color.White]);
                }
                .width(40).height(40)
                .onClick(() => { this.closeViewer(); });
                if (this.viewerFileName() !== '') {
                  Text(this.viewerFileName()).fontSize(13).fontColor($r('app.color.surface_alt')).fontWeight(FontWeight.Medium)
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                    .flexShrink(1)
                    .constraintSize({ maxWidth: 220 });
                }
              }
              .padding({ left: 12, right: 14, top: 10, bottom: 10 })
              .backgroundColor(VIEWER_CHROME_BG)
              .borderRadius(18)
              .alignItems(VerticalAlign.Center)
              .flexShrink(1);
              Blank().layoutWeight(1).hitTestBehavior(HitTestMode.None);
              // Video download ring — between the title and the ⋮ menu; fixed
              // size so it can never squeeze the menu button out.
              if (this.viewerDlPercent < 100) {
                Stack() {
                  Progress({ value: this.viewerDlPercent, total: 100, type: ProgressType.Ring })
                    .width(30).height(30).color(Color.White);
                  Text(`${this.viewerDlPercent}`).fontSize(9).fontColor(Color.White);
                }
                .width(38).height(38)
                .backgroundColor(VIEWER_CHROME_BG).borderRadius(19)
                .margin({ right: 8 })
                .flexShrink(0);
              }
              // "⋮" menu — 保存到相册 etc.
              Stack() {
                Circle({ width: 36, height: 36 }).fill(VIEWER_CHROME_BG);
                SymbolGlyph($r('sys.symbol.more')).fontSize(18).fontColor([Color.White]);
              }
              .width(40).height(40)
              .bindMenu([{
                value: '保存到相册',
                action: (): void => { this.saveViewerMedia(); }
              } as MenuElement]);
            }
            .width('100%')
            .position({ x: 0, y: 0 })
            .padding({ left: 12, right: 12, top: this.topSafe + 12 });
          }
          if (this.chromeVisible && this.viewerSiblingIds().length > 1) {
            Column() {
              this.viewerFilmstrip();
            }
            .width('100%').height('100%')
            .justifyContent(FlexAlign.End)
            .padding({ bottom: this.viewerIsVideo() ? 110 : 30 })
            .hitTestBehavior(HitTestMode.Transparent);
          }
        }
        .width('100%').height('100%').backgroundColor(Color.Black)
        // Hero transition: paired (same id) with the tapped thumbnail, which is
        // removed while the viewer is open — the viewer expands out of the
        // thumbnail's frame on open and shrinks back into it on close.
        .geometryTransition(`media_${this.viewerMsgId}`, { follow: true })
        .transition(TransitionEffect.OPACITY.animation({ duration: 300, curve: Curve.Friction }))
      }
    }.width('100%').height('100%');
  }
}
