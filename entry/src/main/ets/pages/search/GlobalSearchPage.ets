import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { getTdClient } from '../../tdkit/Globals';
import { openLocalFile } from '../../util/openLocalFile';
import { formatFileSize } from '../../util/formatFileSize';
import { TdObject, TdRequest, TdError } from '../../tdkit/TdTypes';
import { GlobalSearchStore, SearchRow } from '../../store/GlobalSearchStore';
import { AvatarView } from '../chatlist/AvatarView';
import { formatPreview } from '../../util/formatPreview';
import { formatTime } from '../../util/formatTime';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';

interface FoundItem {
  chatId: number;
  messageId: number;
  chatTitle: string;
  preview: string;
  date: number;
  // 媒体 tab extras (unused elsewhere).
  thumbPath: string;
  isVideo: boolean;
  duration: string;
  // chat avatar for list rows
  avatarPath: string;
  initials: string;
  isChannelChat: boolean; // resolved chat type — 频道 tab filters messages by it
}

const TABS: string[] = ['聊天', '频道', '应用', '帖子', '公开贴文', '媒体', '下载', '链接', '文件', '音频', '语音'];
const TAB_CHATS: number = 0;
const TAB_CHANNELS: number = 1;
const TAB_APPS: number = 2;
const TAB_POSTS: number = 3;
const TAB_PUBLIC_POSTS: number = 4;
const TAB_MEDIA: number = 5;
const TAB_DOWNLOADS: number = 6;
const TAB_LINKS: number = 7;
const TAB_FILES: number = 8;
const TAB_AUDIO: number = 9;
const TAB_VOICE: number = 10;

// TDLib message filter for the typed-message tabs ('' = no filter).
function filterTypeForTab(tab: number): string {
  if (tab === TAB_MEDIA) {
    return 'searchMessagesFilterPhotoAndVideo';
  } else if (tab === TAB_LINKS) {
    return 'searchMessagesFilterUrl';
  } else if (tab === TAB_FILES) {
    return 'searchMessagesFilterDocument';
  } else if (tab === TAB_AUDIO) {
    return 'searchMessagesFilterAudio';
  } else if (tab === TAB_VOICE) {
    return 'searchMessagesFilterVoiceNote';
  }
  return '';
}

// mm:ss badge for video thumbnails.
function durationLabel(totalSeconds: number): string {
  const m = Math.floor(totalSeconds / 60);
  const s = totalSeconds % 60;
  return `${m}:${`${s}`.padStart(2, '0')}`;
}
const SEARCH_DEBOUNCE_MS: number = 300;
// Photos below this size are almost certainly auto-downloaded thumbnails, not
// media the user pulled down — keep them out of the downloads list.
const MIN_PHOTO_BYTES: number = 100 * 1024;
const MAX_DOWNLOAD_ITEMS: number = 300;
// Cap on pages fetched automatically when a tab's filter hides every hit.
const MAX_AUTO_PAGES: number = 5;

interface DownloadItem {
  path: string;
  name: string;
  kind: string;    // 'photo' | 'video' | 'file'
  sizeLabel: string;
  mtime: number;   // ms — sort key
  dateLabel: string;
  fileId: number;  // >0 for download-manager items (live progress via updateFile)
  progress: number; // 0-99 while downloading, 100 when complete
}

// Global search (Telegram-style): an empty query shows frequent contacts and
// recently opened chats; a typed query searches chats/channels by name or
// messages ("帖子") globally.
@Entry
@Component
struct GlobalSearchPage {
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @State query: string = '';
  @State tab: number = 0;
  @State topUsers: SearchRow[] = [];
  @State recent: SearchRow[] = [];
  @State chatResults: SearchRow[] = [];
  @State chatSearching: boolean = false;
  @State joinedChannels: SearchRow[] = [];
  @State similarChannels: SearchRow[] = [];
  @State apps: SearchRow[] = [];
  // 帖子 (message) search state.
  @State items: FoundItem[] = [];
  @State loading: boolean = false;
  @State nextOffset: string = '';
  @State searchedOnce: boolean = false;
  private nowSec: number = Math.floor(Date.now() / 1000);
  private seq: number = 0;
  private pagingBusy: boolean = false;
  private autoPages: number = 0; // consecutive auto-fetched pages that rendered nothing
  private debounceTimer: number = -1;
  private store: GlobalSearchStore | null = null;
  private unsub: (() => void) | null = null;
  // Sliding selection pill (same pattern as the chat-list tab bar): frames are
  // recorded per pill; the pill interpolates during content swipes.
  @State indicatorX: number = 8;
  @State indicatorW: number = 0;
  @State indicatorH: number = 30;
  private tabXs: number[] = [];
  private tabWs: number[] = [];
  private tabsWidth: number = 0;
  private tabViewW: number = 0;
  private tabScroller: Scroller = new Scroller();
  private controller: TabsController = new TabsController();

  private moveIndicatorTo(pos: number): void {
    const n = TABS.length;
    if (this.tabWs.length === 0) {
      return;
    }
    const p = Math.max(0, Math.min(n - 1, pos));
    const i0 = Math.floor(p);
    const i1 = Math.min(n - 1, i0 + 1);
    const f = p - i0;
    const x0 = this.tabXs[i0] ?? 8;
    const x1 = this.tabXs[i1] ?? x0;
    const w0 = this.tabWs[i0] ?? 0;
    const w1 = this.tabWs[i1] ?? w0;
    this.indicatorX = x0 + (x1 - x0) * f;
    this.indicatorW = w0 + (w1 - w0) * f;
  }

  private ensureTabVisible(index: number): void {
    const x = this.tabXs[index] ?? 0;
    const w = this.tabWs[index] ?? 0;
    if (w === 0 || this.tabViewW === 0) {
      return;
    }
    const off = this.tabScroller.currentOffset().xOffset;
    let target = -1;
    if (x < off + 8) {
      target = Math.max(0, x - 8);
    } else if (x + w > off + this.tabViewW - 8) {
      target = x + w - this.tabViewW + 8;
    }
    if (target >= 0) {
      this.tabScroller.scrollTo({ xOffset: target, yOffset: 0, animation: { duration: 200, curve: Curve.EaseOut } });
    }
  }

  // Tab became current (tap or settled swipe): update state, settle the pill,
  // keep it visible, and fire the tab's data loads.
  private onTabSelected(index: number): void {
    this.tab = index;
    animateTo({ duration: 200, curve: Curve.EaseOut }, () => { this.moveIndicatorTo(index); });
    this.ensureTabVisible(index);
    if (index === TAB_DOWNLOADS) {
      this.loadDownloads();
      this.loadActiveDownloads();
    }
    this.runSearch();
  }

  aboutToAppear(): void {
    const store = new GlobalSearchStore(getTdClient());
    this.store = store;
    this.unsub = store.subscribe(() => {
      this.topUsers = store.topUsers;
      this.recent = store.recent;
      this.chatResults = store.results;
      this.chatSearching = store.searching;
      this.joinedChannels = store.joinedChannels;
      this.similarChannels = store.similarChannels;
      this.apps = store.apps;
    });
    store.open();
    const params = router.getParams() as Record<string, Object> | undefined;
    const q = params !== undefined ? (params['query'] as string | undefined) : undefined;
    if (q !== undefined && q !== '') {
      // Hashtag entry — straight into the 帖子 (global posts) tab.
      this.query = q;
      this.tab = TAB_POSTS;
      this.searchMessages('');
    }
  }

  aboutToDisappear(): void {
    if (this.unsubFile !== null) { this.unsubFile(); this.unsubFile = null; }
    if (this.debounceTimer !== -1) { clearTimeout(this.debounceTimer); this.debounceTimer = -1; }
    if (this.unsub !== null) { this.unsub(); this.unsub = null; }
    if (this.store !== null) { this.store.close(); this.store = null; }
  }

  private onQueryChanged(v: string): void {
    this.query = v;
    if (this.debounceTimer !== -1) {
      clearTimeout(this.debounceTimer);
    }
    this.debounceTimer = setTimeout(() => {
      this.debounceTimer = -1;
      this.runSearch();
    }, SEARCH_DEBOUNCE_MS);
  }

  @State downloads: DownloadItem[] = [];      // completed, from the filesystem scan
  @State activeDownloads: DownloadItem[] = []; // in-flight, from TDLib's download manager
  @State downloadsLoaded: boolean = false;
  private unsubFile: (() => void) | null = null;

  // Active (in-progress) downloads from TDLib's download manager. Fetched on
  // every 下载 tab visit; progress rows update live via updateFile.
  private loadActiveDownloads(): void {
    const req: TdRequest = { '@type': 'searchFileDownloads' };
    req['query'] = '';
    req['only_active'] = true;
    req['only_completed'] = false;
    req['offset'] = '';
    req['limit'] = 50;
    getTdClient().send(req).then((res: TdObject) => {
      const files = (res['files'] as TdObject[] | undefined) ?? [];
      const fresh: DownloadItem[] = [];
      for (const fd of files) {
        const fileId = (fd['file_id'] as number | undefined) ?? 0;
        if (fileId === 0) {
          continue;
        }
        const msg = fd['message'] as TdObject | undefined;
        fresh.push({
          path: '', name: this.downloadName(msg), kind: 'file',
          sizeLabel: '', mtime: ((fd['add_date'] as number | undefined) ?? 0) * 1000,
          dateLabel: '', fileId, progress: 0
        });
        this.refreshFileProgress(fileId);
      }
      this.activeDownloads = fresh;
      if (this.unsubFile === null && fresh.length > 0) {
        this.unsubFile = getTdClient().onUpdate('updateFile', (u: TdObject) => {
          const f = u['file'] as TdObject | undefined;
          if (f !== undefined) {
            this.applyDownloadFile(f);
          }
        });
      }
    }).catch((e: TdError) => {
      console.error(`GlobalSearchPage.searchFileDownloads failed: ${e.message}`);
    });
  }

  private downloadName(msg: TdObject | undefined): string {
    const content = msg !== undefined ? (msg['content'] as TdObject | undefined) : undefined;
    if (content !== undefined) {
      const doc = content['document'] as TdObject | undefined;
      const docName = doc !== undefined ? ((doc['file_name'] as string | undefined) ?? '') : '';
      if (docName !== '') {
        return docName;
      }
      const video = content['video'] as TdObject | undefined;
      const videoName = video !== undefined ? ((video['file_name'] as string | undefined) ?? '') : '';
      if (videoName !== '') {
        return videoName;
      }
    }
    return '媒体文件';
  }

  private refreshFileProgress(fileId: number): void {
    const req: TdRequest = { '@type': 'getFile' };
    req['file_id'] = fileId;
    getTdClient().send(req).then((f: TdObject) => { this.applyDownloadFile(f); })
      .catch((e: TdError) => { console.error(`GlobalSearchPage.getFile failed: ${e.message}`); });
  }

  private applyDownloadFile(file: TdObject): void {
    const id = (file['id'] as number | undefined) ?? 0;
    if (id === 0 || this.activeDownloads.findIndex((it: DownloadItem) => it.fileId === id) < 0) {
      return;
    }
    const local = file['local'] as TdObject | undefined;
    const done = local !== undefined ? ((local['is_downloading_completed'] as boolean | undefined) ?? false) : false;
    const path = local !== undefined ? ((local['path'] as string | undefined) ?? '') : '';
    const got = local !== undefined ? ((local['downloaded_size'] as number | undefined) ?? 0) : 0;
    const total = (file['expected_size'] as number | undefined) ?? ((file['size'] as number | undefined) ?? 0);
    const progress = done ? 100 : (total > 0 ? Math.min(99, Math.floor(got * 100 / total)) : 0);
    this.activeDownloads = this.activeDownloads.map((it: DownloadItem): DownloadItem => it.fileId === id
      ? {
        path: done ? path : it.path, name: it.name, kind: it.kind,
        sizeLabel: total > 0 ? formatFileSize(total) : it.sizeLabel,
        mtime: it.mtime, dateLabel: done ? '刚刚' : it.dateLabel,
        fileId: it.fileId, progress
      } : it);
  }

  // Scan TDLib's download directories for media/files already on disk,
  // newest first. Small photos are skipped (auto-downloaded thumbnails).
  private loadDownloads(): void {
    if (this.downloadsLoaded) {
      return;
    }
    this.downloadsLoaded = true;
    const base = `${(getContext(this) as common.UIAbilityContext).filesDir}/tdlib_files`;
    const dirs: string[][] = [
      ['videos', 'video'], ['documents', 'file'], ['animations', 'video'], ['photos', 'photo']
    ];
    const items: DownloadItem[] = [];
    for (const d of dirs) {
      const dir = `${base}/${d[0]}`;
      try {
        const names = fs.listFileSync(dir);
        for (const name of names) {
          const path = `${dir}/${name}`;
          try {
            const st = fs.statSync(path);
            if (!st.isFile() || st.size <= 0) {
              continue;
            }
            if (d[1] === 'photo' && st.size < MIN_PHOTO_BYTES) {
              continue;
            }
            items.push({
              path, name, kind: d[1],
              sizeLabel: formatFileSize(st.size),
              mtime: st.mtime * 1000,
              dateLabel: this.downloadDate(st.mtime),
              fileId: 0, progress: 100
            });
          } catch (e) {
            // unreadable entry — skip
          }
        }
      } catch (e) {
        // directory may not exist yet — fine
      }
    }
    items.sort((a: DownloadItem, b: DownloadItem) => b.mtime - a.mtime);
    this.downloads = items.slice(0, MAX_DOWNLOAD_ITEMS);
  }

  private downloadDate(sec: number): string {
    const d = new Date(sec * 1000);
    return `${d.getFullYear()}-${d.getMonth() + 1}-${d.getDate()}`;
  }

  // Rows the current tab actually shows: the 频道 tab keeps only messages from
  // channels, so a page of hits can render as nothing at all.
  private visibleItems(): FoundItem[] {
    return this.tab === TAB_CHANNELS
      ? this.items.filter((it: FoundItem) => it.isChannelChat)
      : this.items;
  }

  // The 频道 filter can discard an entire page of hits, leaving a screen with
  // nothing to scroll — onReachEnd would never fire and the tab would look
  // empty while more pages exist. Pull the next pages ourselves, bounded.
  private maybeAutoPage(): void {
    if (this.tab !== TAB_CHANNELS || this.loading || this.pagingBusy) {
      return;
    }
    if (this.visibleItems().length > 0 || this.nextOffset === '' || this.autoPages >= MAX_AUTO_PAGES) {
      return;
    }
    this.autoPages += 1;
    this.searchMessages(this.nextOffset);
  }

  // True once paging has stopped for good — only then may the tab claim there
  // is nothing to show (a hit whose chat type is still resolving isn't a miss).
  private searchExhausted(): boolean {
    if (this.loading || this.pagingBusy) {
      return false;
    }
    return this.tab !== TAB_CHANNELS || this.nextOffset === '' || this.autoPages >= MAX_AUTO_PAGES;
  }

  private isFilterTab(): boolean {
    return filterTypeForTab(this.tab) !== '';
  }


  // Abandon whatever is in flight: the response of a superseded request must
  // neither land in the list nor leave the spinner running. Every path that
  // returns without starting a new request has to call this — a stale `loading`
  // is what makes a tab spin forever.
  private cancelInFlight(): void {
    this.seq++;
    this.pagingBusy = false;
    this.loading = false;
    this.nextOffset = '';
  }

  private runSearch(): void {
    if (this.tab === TAB_POSTS) {
      // Keyword post search burns server quota — never auto-fire; typing
      // resets back to the prompt with its explicit 搜索 button.
      this.cancelInFlight();
      this.searchedOnce = false;
      this.items = [];
      this.loadPostsQuota();
    } else if (this.tab === TAB_PUBLIC_POSTS) {
      // Free hashtag API — search right away.
      this.searchMessages('');
    } else if (this.isFilterTab()) {
      this.searchMessages('');
    } else if (this.tab === TAB_DOWNLOADS) {
      // Filtered client-side — nothing to fetch.
      this.cancelInFlight();
    } else {
      // 聊天/频道/应用: matched objects on top + a 消息 section below.
      if (this.tab !== TAB_APPS && this.store !== null) {
        this.store.searchChats(this.query);
      }
      this.searchMessages('');
      const q = this.query.trim();
      if (q.startsWith('#') && q.length > 1) {
        this.loadHashtagPosts('');
      } else {
        this.hashtagPosts = [];
      }
    }
  }

  @State postsQuota: string = '';

  // Remaining free public-post searches today (field names probed defensively —
  // the raw object is logged for calibration).
  private loadPostsQuota(): void {
    const req: TdRequest = { '@type': 'getPublicPostSearchLimits' };
    req['query'] = this.query.trim();
    getTdClient().send(req).then((res: TdObject) => {
      console.info(`GlobalSearchPage.postSearchLimits: ${JSON.stringify(res)}`);
      const remaining = (res['remaining_free_query_count'] as number | undefined)
        ?? ((res['remaining_count'] as number | undefined)
          ?? ((res['free_query_count'] as number | undefined) ?? -1));
      this.postsQuota = remaining >= 0 ? `今日剩余 ${remaining} 次免费搜索` : '';
    }).catch((e: TdError) => {
      console.error(`GlobalSearchPage.getPublicPostSearchLimits failed: ${e.message}`);
    });
  }

  private searchMessages(offset: string): void {
    const q = this.query.trim();
    const filterType = filterTypeForTab(this.tab);
    // posts: quota-limited keyword post search; tagposts: free hashtag post
    // search (公开贴文); filter: typed tabs (query optional); all: the 消息
    // section under 聊天/频道/应用.
    const mode: string = this.tab === TAB_POSTS ? 'posts'
      : (this.tab === TAB_PUBLIC_POSTS ? 'tagposts' : (filterType !== '' ? 'filter' : 'all'));
    if (q === '' && mode !== 'filter') {
      this.cancelInFlight();
      this.items = [];
      this.searchedOnce = false;
      return;
    }
    if (offset !== '') {
      // Scroll-driven pagination: one in-flight page at a time.
      if (this.pagingBusy) {
        return;
      }
      this.pagingBusy = true;
    }
    const seq = ++this.seq;
    this.loading = offset === '';
    const req: TdRequest = mode === 'posts' ? { '@type': 'searchPublicPosts' }
      : (mode === 'tagposts' ? { '@type': 'searchPublicMessagesByTag' } : { '@type': 'searchMessages' });
    if (mode === 'filter' || mode === 'all') {
      req['chat_list'] = { '@type': 'chatListMain' } as TdObject;
      if (filterType !== '') {
        req['filter'] = { '@type': filterType } as TdObject;
      }
    }
    if (mode === 'tagposts') {
      // The hashtag API wants a tag — prefix bare keywords with '#'.
      req['tag'] = q.startsWith('#') ? q : `#${q}`;
    } else {
      req['query'] = q;
    }
    req['offset'] = offset;
    req['limit'] = 30;
    getTdClient().send(req).then((res: TdObject) => {
      this.pagingBusy = false;
      if (seq !== this.seq) {
        return;
      }
      this.loading = false;
      this.searchedOnce = true;
      this.nextOffset = (res['next_offset'] as string | undefined) ?? '';
      const msgs = (res['messages'] as TdObject[] | undefined) ?? [];
      const fresh: FoundItem[] = [];
      for (const m of msgs) {
        const item = this.parseFoundMessage(m);
        if (item === null) {
          continue;
        }
        if (this.tab === TAB_MEDIA) {
          this.parseMediaThumb(m, item);
        }
        fresh.push(item);
      }
      this.items = offset === '' ? fresh : [...this.items, ...fresh];
      if (this.tab === TAB_POSTS) {
        this.loadPostsQuota(); // a search just burned one — refresh the count
      }
      // Whether a hit belongs to a channel is only known once getChat resolves,
      // so the 频道 filter cannot be judged here — maybeAutoPage() runs again as
      // each chat lands (see resolveTitle).
      if (offset === '') {
        this.autoPages = 0;
      }
      this.maybeAutoPage();
    }).catch((e: TdError) => {
      this.pagingBusy = false;
      this.loading = false;
      this.searchedOnce = true;
      console.error(`GlobalSearchPage.searchMessages failed: ${e.message}`);
    });
  }

  private parseFoundMessage(m: TdObject): FoundItem | null {
    const chatId = (m['chat_id'] as number | undefined) ?? 0;
    const messageId = (m['id'] as number | undefined) ?? 0;
    if (chatId === 0 || messageId === 0) {
      return null;
    }
    this.resolveTitle(chatId);
    const cachedTitle = this.titles.get(chatId) ?? '';
    return {
      chatId, messageId, chatTitle: cachedTitle,
      preview: formatPreview(m),
      date: (m['date'] as number | undefined) ?? 0,
      thumbPath: '', isVideo: false, duration: '',
      avatarPath: this.avatarCache.get(chatId) ?? '',
      initials: cachedTitle.length > 0 ? cachedTitle.substring(0, 1).toUpperCase() : '?',
      isChannelChat: this.channelFlags.get(chatId) ?? false
    };
  }

  // #tag queries: public posts carrying the hashtag, previewed above the
  // regular results ("公开贴文") with a 显示更多 expander.
  @State hashtagPosts: FoundItem[] = [];

  private loadHashtagPosts(offset: string): void {
    const tag = this.query.trim();
    const req: TdRequest = { '@type': 'searchPublicMessagesByTag' };
    req['tag'] = tag;
    req['offset'] = offset;
    req['limit'] = 5;
    getTdClient().send(req).then((res: TdObject) => {
      const msgs = (res['messages'] as TdObject[] | undefined) ?? [];
      const fresh: FoundItem[] = [];
      for (const m of msgs) {
        const item = this.parseFoundMessage(m);
        if (item !== null) {
          fresh.push(item);
        }
      }
      this.hashtagPosts = offset === '' ? fresh : [...this.hashtagPosts, ...fresh];
    }).catch((e: TdError) => {
      console.error(`GlobalSearchPage.searchPublicMessagesByTag failed: ${e.message}`);
    });
  }

  // 媒体 grid: extract the thumbnail file (photo 'm' size / video thumbnail)
  // and kick its download; the cell fills in when the file lands.
  private parseMediaThumb(m: TdObject, item: FoundItem): void {
    const content = m['content'] as TdObject | undefined;
    if (content === undefined) {
      return;
    }
    let thumbId = 0;
    const photo = content['photo'] as TdObject | undefined;
    if (photo !== undefined) {
      const sizes = (photo['sizes'] as TdObject[] | undefined) ?? [];
      let pick: TdObject | undefined = undefined;
      for (const s of sizes) {
        if ((s['type'] as string | undefined) === 'm') {
          pick = s;
        }
      }
      if (pick === undefined && sizes.length > 0) {
        pick = sizes[0];
      }
      const f = pick !== undefined ? (pick['photo'] as TdObject | undefined) : undefined;
      thumbId = f !== undefined ? ((f['id'] as number | undefined) ?? 0) : 0;
    }
    const video = content['video'] as TdObject | undefined;
    if (video !== undefined) {
      item.isVideo = true;
      item.duration = durationLabel((video['duration'] as number | undefined) ?? 0);
      const thumb = video['thumbnail'] as TdObject | undefined;
      const f = thumb !== undefined ? (thumb['file'] as TdObject | undefined) : undefined;
      thumbId = f !== undefined ? ((f['id'] as number | undefined) ?? 0) : 0;
    }
    if (thumbId === 0) {
      return;
    }
    const req: TdRequest = { '@type': 'downloadFile' };
    req['file_id'] = thumbId;
    req['priority'] = 1;
    req['synchronous'] = true;
    getTdClient().send(req).then((f: TdObject) => {
      const local = f['local'] as TdObject | undefined;
      const path = local !== undefined ? ((local['path'] as string | undefined) ?? '') : '';
      if (path === '') {
        return;
      }
      this.items = this.items.map((it: FoundItem): FoundItem => it.messageId === item.messageId
        ? {
          chatId: it.chatId, messageId: it.messageId, chatTitle: it.chatTitle,
          preview: it.preview, date: it.date,
          thumbPath: path, isVideo: it.isVideo, duration: it.duration,
          avatarPath: it.avatarPath, initials: it.initials, isChannelChat: it.isChannelChat
        } : it);
    }).catch((e: TdError) => {
      console.error(`GlobalSearchPage.mediaThumb failed: ${e.message}`);
    });
  }

  // Resolved-chat caches. All three must be cached together: resolveTitle()
  // short-circuits on a title cache hit, so anything it resolves but does not
  // cache (the channel flag, once) would stay at its default on every later
  // search — which silently emptied the 频道 tab, whose message section filters
  // on exactly that flag.
  private titles: Map<number, string> = new Map();
  private avatarCache: Map<number, string> = new Map();
  private channelFlags: Map<number, boolean> = new Map();

  private resolveTitle(chatId: number): void {
    if (this.titles.has(chatId)) {
      return;
    }
    this.titles.set(chatId, '');
    const req: TdRequest = { '@type': 'getChat' };
    req['chat_id'] = chatId;
    getTdClient().send(req).then((chat: TdObject) => {
      const title = (chat['title'] as string | undefined) ?? '';
      this.titles.set(chatId, title);
      const type = chat['type'] as TdObject | undefined;
      const isChannel = type !== undefined
        && ((type['@type'] as string | undefined) ?? '') === 'chatTypeSupergroup'
        && (((type as TdObject)['is_channel'] as boolean | undefined) ?? false);
      this.channelFlags.set(chatId, isChannel);
      this.maybeAutoPage();
      this.patchItems(chatId, (it: FoundItem): FoundItem => ({
        chatId: it.chatId, messageId: it.messageId, chatTitle: title,
        preview: it.preview, date: it.date,
        thumbPath: it.thumbPath, isVideo: it.isVideo, duration: it.duration,
        avatarPath: it.avatarPath,
        initials: title.length > 0 ? title.substring(0, 1).toUpperCase() : '?',
        isChannelChat: isChannel
      }));
      const photo = chat['photo'] as TdObject | undefined;
      const small = photo !== undefined ? (photo['small'] as TdObject | undefined) : undefined;
      const fileId = small !== undefined ? ((small['id'] as number | undefined) ?? 0) : 0;
      if (fileId > 0) {
        const dl: TdRequest = { '@type': 'downloadFile' };
        dl['file_id'] = fileId;
        dl['priority'] = 1;
        dl['synchronous'] = true;
        getTdClient().send(dl).then((f: TdObject) => {
          const local = f['local'] as TdObject | undefined;
          const path = local !== undefined ? ((local['path'] as string | undefined) ?? '') : '';
          if (path !== '') {
            this.avatarCache.set(chatId, path);
            this.patchItems(chatId, (it: FoundItem): FoundItem => ({
              chatId: it.chatId, messageId: it.messageId, chatTitle: it.chatTitle,
              preview: it.preview, date: it.date,
              thumbPath: it.thumbPath, isVideo: it.isVideo, duration: it.duration,
              avatarPath: path, initials: it.initials, isChannelChat: it.isChannelChat
            }));
          }
        }).catch((e: TdError) => {
          console.error(`GlobalSearchPage.avatar download failed: ${e.message}`);
        });
      }
    }).catch((e: TdError) => {
      console.error(`GlobalSearchPage.getChat failed: ${e.message}`);
    });
  }

  private patchItems(chatId: number, fn: (it: FoundItem) => FoundItem): void {
    this.items = this.items.map((it: FoundItem): FoundItem => it.chatId === chatId ? fn(it) : it);
    this.hashtagPosts = this.hashtagPosts.map((it: FoundItem): FoundItem => it.chatId === chatId ? fn(it) : it);
  }

  // Opening a chat that a typed query matched carries the query along: the chat
  // page lands in its in-chat search, showing that chat's hits for the same
  // words. Landing rows (frequent/recent) have no query, so they open normally.
  private openChat(chatId: number): void {
    const params: Record<string, Object> = { 'chatId': chatId };
    const q = this.query.trim();
    if (q !== '') {
      params['searchQuery'] = q;
    }
    router.pushUrl({ url: 'pages/chat/ChatPage', params: params });
  }

  // App (mini-app bot) rows open the bot's chat — running the web app itself
  // needs a WebView container we don't have yet.
  private openApp(userId: number): void {
    const req: TdRequest = { '@type': 'createPrivateChat' };
    req['user_id'] = userId;
    req['force'] = false;
    getTdClient().send(req).then((chat: TdObject) => {
      const id = (chat['id'] as number | undefined) ?? 0;
      if (id !== 0) {
        this.openChat(id);
      }
    }).catch((e: TdError) => {
      console.error(`GlobalSearchPage.openApp failed: ${e.message}`);
    });
  }

  // A message hit lands on that message AND carries the query, so the chat opens
  // in its in-chat search with the tapped message as the current hit — ∧/∨ then
  // walk this chat's other hits for the same words.
  private openResult(it: FoundItem): void {
    const params: Record<string, Object> = { 'chatId': it.chatId, 'jumpTo': it.messageId };
    const q = this.query.trim();
    if (q !== '') {
      params['searchQuery'] = q;
    }
    router.pushUrl({ url: 'pages/chat/ChatPage', params: params });
  }

  @Builder
  searchBar() {
    Row({ space: 8 }) {
      SymbolGlyph($r('sys.symbol.magnifyingglass')).fontSize(18).fontColor([COLOR_TEXT_SECONDARY])
        .margin({ left: 14 });
      TextInput({ text: this.query, placeholder: '搜索聊天' })
        .layoutWeight(1).height(44).fontSize(17)
        .backgroundColor(Color.Transparent).padding(0)
        .placeholderColor(COLOR_TEXT_SECONDARY)
        .defaultFocus(true)
        .onChange((v: string) => { this.onQueryChanged(v); })
        .onSubmit(() => { this.runSearch(); });
      SymbolGlyph($r('sys.symbol.xmark')).fontSize(18).fontColor([COLOR_TEXT_SECONDARY])
        .margin({ right: 14 })
        .onClick(() => {
          if (this.query === '') {
            router.back();
          } else {
            this.query = '';
            this.chatResults = [];
            this.items = [];
            this.searchedOnce = false;
          }
        });
    }
    .width('100%').height(52)
    .backgroundColor($r('app.color.surface')).borderRadius(26)
    .alignItems(VerticalAlign.Center);
  }

  @Builder
  tabsBar() {
    Scroll(this.tabScroller) {
      Stack({ alignContent: Alignment.TopStart }) {
        // Sliding selection pill behind the labels — follows the finger
        // during content swipes (same as the chat-list tab bar).
        Row()
          .width(this.indicatorW).height(this.indicatorH)
          .borderRadius(this.indicatorH / 2)
          .backgroundColor($r('app.color.selected_pill'))
          .position({ x: this.indicatorX, y: (44 - this.indicatorH) / 2 });
        Row({ space: 6 }) {
          ForEach(TABS, (t: string, idx: number) => {
            Text(t)
              .fontSize(15)
              .fontWeight(this.tab === idx ? FontWeight.Medium : FontWeight.Normal)
              .fontColor(this.tab === idx ? COLOR_PRIMARY : COLOR_TEXT_PRIMARY)
              .borderRadius(17)
              .padding({ left: 16, right: 16, top: 7, bottom: 7 })
              .onAreaChange((_old: Area, area: Area) => {
                this.tabXs[idx] = area.position.x as number;
                this.tabWs[idx] = area.width as number;
                this.indicatorH = area.height as number;
                if (idx === this.tab) {
                  this.moveIndicatorTo(idx);
                }
              })
              .onClick(() => { this.controller.changeIndex(idx); });
          }, (t: string) => t);
        }.padding({ left: 8, right: 8 }).height(44);
      }
    }
    .scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
    .width('100%')
    .backgroundColor($r('app.color.surface')).borderRadius(24)
    .margin({ top: 8 })
    .onAreaChange((_old: Area, area: Area) => { this.tabViewW = area.width as number; });
  }

  @Builder
  chatRow(r: SearchRow, showDivider: boolean) {
    Column() {
      if (showDivider) {
        Divider().color($r('app.color.divider')).strokeWidth(0.7).margin({ left: 72 });
      }
      Row({ space: 12 }) {
        AvatarView({ avatarPath: r.avatarPath, initials: r.initials, colorSeed: r.chatId, avatarSize: 48 });
        Column({ space: 3 }) {
          Text(r.title !== '' ? r.title : '…')
            .fontSize(16).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
          if (r.subtitle !== '') {
            Text(r.subtitle).fontSize(13).fontColor(COLOR_TEXT_SECONDARY)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
          }
        }.alignItems(HorizontalAlign.Start).layoutWeight(1);
      }
      .width('100%').padding({ left: 14, right: 14, top: 8, bottom: 8 })
      .alignItems(VerticalAlign.Center)
      .onClick(() => { this.openChat(r.chatId); });
    }
  }

  // Empty-query landing: frequent contacts strip + recently opened list.
  @Builder
  landing() {
    Scroll() {
      Column() {
        if (this.topUsers.length > 0) {
          Scroll() {
            Row({ space: 18 }) {
              ForEach(this.topUsers, (r: SearchRow) => {
                Column({ space: 6 }) {
                  AvatarView({ avatarPath: r.avatarPath, initials: r.initials, colorSeed: r.chatId, avatarSize: 62 });
                  Text(r.title).fontSize(13).fontColor(COLOR_TEXT_PRIMARY)
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                    .constraintSize({ maxWidth: 70 });
                }
                .onClick(() => { this.openChat(r.chatId); });
              }, (r: SearchRow) => `top_${r.chatId}_${r.avatarPath}_${r.title}`);
            }.padding({ left: 16, right: 16, top: 14, bottom: 12 });
          }
          .scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
          .width('100%')
          .backgroundColor($r('app.color.surface'));
        }
        if (this.recent.length > 0) {
          Row() {
            Text('最近访问').fontSize(14).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_SECONDARY)
              .layoutWeight(1);
            Text('全部清空').fontSize(14).fontColor(COLOR_PRIMARY)
              .onClick(() => { if (this.store !== null) { this.store.clearRecent(); } });
          }
          .width('100%').padding({ left: 16, right: 16, top: 10, bottom: 6 })
          .backgroundColor($r('app.color.page_bg'));
          Column() {
            ForEach(this.recent, (r: SearchRow, idx: number) => {
              this.chatRow(r, idx > 0);
            }, (r: SearchRow) => `recent_${r.chatId}_${r.avatarPath}_${r.title}_${r.subtitle}`);
          }
          .width('100%')
          .backgroundColor($r('app.color.surface'));
        }
      }.width('100%');
    }
    .layoutWeight(1).width('100%')
    .align(Alignment.Top)
    .edgeEffect(EdgeEffect.Spring)
    .scrollBar(BarState.Off);
  }

  @Builder
  sectionHeader(label: string) {
    Text(label).fontSize(14).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_SECONDARY)
      .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 6 });
  }

  // 频道 tab landing: joined channels + server-recommended channels.
  @Builder
  channelsLanding() {
    Scroll() {
      Column() {
        if (this.joinedChannels.length > 0) {
          this.sectionHeader('已加入的频道');
          Column() {
            ForEach(this.joinedChannels, (r: SearchRow, idx: number) => {
              this.chatRow(r, idx > 0);
            }, (r: SearchRow) => `jc_${r.chatId}_${r.avatarPath}_${r.subtitle}`);
          }.width('100%').backgroundColor($r('app.color.surface'));
        }
        if (this.similarChannels.length > 0) {
          this.sectionHeader('相似频道');
          Column() {
            ForEach(this.similarChannels, (r: SearchRow, idx: number) => {
              this.chatRow(r, idx > 0);
            }, (r: SearchRow) => `sc_${r.chatId}_${r.avatarPath}_${r.subtitle}`);
          }.width('100%').backgroundColor($r('app.color.surface'));
        }
        if (this.joinedChannels.length === 0 && this.similarChannels.length === 0) {
          Text('加载中...').fontSize(14).fontColor(COLOR_TEXT_SECONDARY).margin({ top: 48 });
        }
      }.width('100%');
    }
    .layoutWeight(1).width('100%')
    .align(Alignment.Top)
    .edgeEffect(EdgeEffect.Spring)
    .scrollBar(BarState.Off);
  }

  @Builder
  appRow(r: SearchRow, showDivider: boolean) {
    Column() {
      if (showDivider) {
        Divider().color($r('app.color.divider')).strokeWidth(0.7).margin({ left: 72 });
      }
      Row({ space: 12 }) {
        AvatarView({ avatarPath: r.avatarPath, initials: r.initials, colorSeed: r.userId, avatarSize: 48 });
        Column({ space: 3 }) {
          Text(r.title !== '' ? r.title : '…')
            .fontSize(16).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
          if (r.subtitle !== '') {
            Text(r.subtitle).fontSize(13).fontColor(COLOR_TEXT_SECONDARY)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
          }
        }.alignItems(HorizontalAlign.Start).layoutWeight(1);
        Text('打开').fontSize(14).fontWeight(FontWeight.Medium).fontColor(Color.White)
          .backgroundColor(COLOR_PRIMARY).borderRadius(15)
          .padding({ left: 16, right: 16, top: 6, bottom: 6 })
          .onClick(() => { this.openApp(r.userId); });
      }
      .width('100%').padding({ left: 14, right: 14, top: 8, bottom: 8 })
      .alignItems(VerticalAlign.Center)
      .onClick(() => { this.openApp(r.userId); });
    }
  }

  // 应用 tab: top-grossing mini apps; a typed query filters by name.
  @Builder
  appsList() {
    Scroll() {
      Column() {
        this.sectionHeader('热门应用');
        Column() {
          ForEach(this.apps.filter((r: SearchRow) =>
            this.query.trim() === '' || r.title.toLowerCase().includes(this.query.trim().toLowerCase())),
            (r: SearchRow, idx: number) => {
              this.appRow(r, idx > 0);
            }, (r: SearchRow) => `app_${r.userId}_${r.avatarPath}_${r.title}_${r.subtitle}`);
        }.width('100%').backgroundColor($r('app.color.surface'));
        if (this.apps.length === 0) {
          Text('加载中...').fontSize(14).fontColor(COLOR_TEXT_SECONDARY).margin({ top: 48 });
        }
      }.width('100%');
    }
    .layoutWeight(1).width('100%')
    .align(Alignment.Top)
    .edgeEffect(EdgeEffect.Spring)
    .scrollBar(BarState.Off);
  }

  @Builder
  downloadRow(it: DownloadItem, showDivider: boolean) {
    Column() {
      if (showDivider) {
        Divider().color($r('app.color.divider')).strokeWidth(0.7).margin({ left: 72 });
      }
      Row({ space: 12 }) {
        if (it.kind === 'photo') {
          Image(`file://${it.path}`)
            .width(48).height(48).borderRadius(8).objectFit(ImageFit.Cover);
        } else {
          Row() {
            SymbolGlyph($r(it.kind === 'video' ? 'sys.symbol.play_fill' : 'sys.symbol.doc_text'))
              .fontSize(20).fontColor([Color.White]);
          }
          .width(48).height(48).borderRadius(8).backgroundColor(COLOR_PRIMARY)
          .justifyContent(FlexAlign.Center);
        }
        Column({ space: 3 }) {
          Text(it.name).fontSize(15).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
          if (it.progress < 100) {
            Progress({ value: it.progress, total: 100, type: ProgressType.Linear })
              .width('92%').height(4).color(COLOR_PRIMARY);
            Text(`${it.sizeLabel !== '' ? it.sizeLabel + ' · ' : ''}下载中 ${it.progress}%`)
              .fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
          } else {
            Text(`${it.sizeLabel}${it.dateLabel !== '' ? ' · ' + it.dateLabel : ''}`)
              .fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
          }
        }.alignItems(HorizontalAlign.Start).layoutWeight(1);
      }
      .width('100%').padding({ left: 14, right: 14, top: 8, bottom: 8 })
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        if (it.progress >= 100 && it.path !== '') {
          openLocalFile(getContext(this) as common.UIAbilityContext, it.path, '');
        }
      });
    }
  }

  // 下载 tab: everything TDLib has downloaded to disk, newest first; a typed
  // query filters by file name.
  // In-flight items (dedup'd against the completed scan by path) lead the
  // list, then completed files, newest first.
  private mergedDownloads(): DownloadItem[] {
    const donePaths = new Set<string>();
    const active = this.activeDownloads.filter((it: DownloadItem) => {
      if (it.progress >= 100 && it.path !== '') {
        donePaths.add(it.path);
      }
      return true;
    });
    const completed = this.downloads.filter((it: DownloadItem) => !donePaths.has(it.path));
    const q = this.query.trim().toLowerCase();
    return [...active, ...completed].filter((it: DownloadItem) =>
      q === '' || it.name.toLowerCase().includes(q));
  }

  @Builder
  downloadsList() {
    List() {
      ForEach(this.mergedDownloads(), (it: DownloadItem, idx: number) => {
        ListItem() {
          this.downloadRow(it, idx > 0);
        }.backgroundColor($r('app.color.surface'));
      }, (it: DownloadItem) => `dl_${it.fileId}_${it.path}_${it.progress}`);
      if (this.downloads.length === 0 && this.activeDownloads.length === 0) {
        ListItem() {
          Text('暂无下载记录').fontSize(14).fontColor(COLOR_TEXT_SECONDARY)
            .width('100%').textAlign(TextAlign.Center).padding({ top: 48 });
        }
      }
    }
    .layoutWeight(1).width('100%');
  }

  // 聊天/频道 tabs: name-search results (频道 keeps only channels).
  @Builder
  chatResultsList() {
    if (this.chatSearching && this.chatResults.length === 0) {
      Column() {
        LoadingProgress().width(36).height(36).color(COLOR_TEXT_SECONDARY);
      }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
    } else if (this.chatResults.filter((r: SearchRow) => this.tab === 0 || r.isChannel).length === 0) {
      Column() {
        Text(this.tab === 1 ? '未找到相关频道' : '未找到相关聊天')
          .fontSize(14).fontColor(COLOR_TEXT_SECONDARY);
      }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
    } else {
      List() {
        ForEach(this.chatResults.filter((r: SearchRow) => this.tab === 0 || r.isChannel),
          (r: SearchRow, idx: number) => {
            ListItem() {
              this.chatRow(r, idx > 0);
            }.backgroundColor($r('app.color.surface'));
          }, (r: SearchRow) => `res_${r.chatId}_${r.avatarPath}_${r.title}_${r.subtitle}`);
      }
      .layoutWeight(1).width('100%');
    }
  }

  // 媒体 tab: 3-column photo/video thumbnail grid.
  @Builder
  mediaGrid() {
    if (this.loading) {
      Column() {
        LoadingProgress().width(36).height(36).color(COLOR_TEXT_SECONDARY);
      }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
    } else if (this.items.length === 0 && this.searchedOnce) {
      Column() {
        Text('没有媒体消息').fontSize(14).fontColor(COLOR_TEXT_SECONDARY);
      }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
    } else {
      Grid() {
        ForEach(this.items, (it: FoundItem) => {
          GridItem() {
            Stack({ alignContent: Alignment.BottomEnd }) {
              if (it.thumbPath !== '') {
                Image(`file://${it.thumbPath}`)
                  .width('100%').height('100%').objectFit(ImageFit.Cover);
              } else {
                Column().width('100%').height('100%').backgroundColor($r('app.color.surface_alt'));
              }
              if (it.isVideo) {
                Row({ space: 3 }) {
                  SymbolGlyph($r('sys.symbol.play_fill')).fontSize(10).fontColor([Color.White]);
                  Text(it.duration).fontSize(11).fontColor(Color.White);
                }
                .backgroundColor('#00000066').borderRadius(8)
                .padding({ left: 5, right: 5, top: 1, bottom: 1 })
                .margin({ right: 4, bottom: 4 });
              }
            }
            .width('100%').aspectRatio(1)
            .clip(true)
            .onClick(() => { this.openResult(it); });
          }
        }, (it: FoundItem) => `m_${it.chatId}_${it.messageId}_${it.thumbPath}`);
      }
      .columnsTemplate('1fr 1fr 1fr')
      .columnsGap(2).rowsGap(2)
      .layoutWeight(1).width('100%')
      .onReachEnd(() => {
        if (this.nextOffset !== '' && !this.loading) {
          this.searchMessages(this.nextOffset);
        }
      });
    }
  }

  @Builder
  msgRow(it: FoundItem) {
    Row({ space: 12 }) {
      AvatarView({ avatarPath: it.avatarPath, initials: it.initials, colorSeed: it.chatId, avatarSize: 44 });
      Column({ space: 3 }) {
        Row() {
          Text(it.chatTitle !== '' ? it.chatTitle : '...')
            .fontSize(15).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1);
          Text(formatTime(it.date, this.nowSec)).fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
        }.width('100%');
        Text(it.preview).fontSize(14).fontColor(COLOR_TEXT_SECONDARY)
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis });
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1);
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ left: 14, right: 14, top: 10, bottom: 10 })
    .backgroundColor($r('app.color.surface'))
    .onClick(() => { this.openResult(it); });
  }

  // 聊天/频道/应用 with a typed query: matched objects on top, hashtag public
  // posts (for #tags) above them, and a 消息 message-results section below —
  // Telegram's combined layout.
  @Builder
  combinedResults() {
    Scroll() {
      Column() {
        if (this.hashtagPosts.length > 0) {
          Row() {
            Text('公开贴文').fontSize(14).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_SECONDARY)
              .layoutWeight(1);
            Text('显示更多 ›').fontSize(14).fontColor(COLOR_PRIMARY)
              .onClick(() => {
                // Full list lives in the dedicated 公开贴文 tab (free API).
                this.controller.changeIndex(TAB_PUBLIC_POSTS);
              });
          }.width('100%').padding({ left: 16, right: 16, top: 10, bottom: 6 });
          Column() {
            ForEach(this.hashtagPosts.slice(0, 3), (it: FoundItem, idx: number) => {
              if (idx > 0) {
                Divider().color($r('app.color.divider')).strokeWidth(0.7).margin({ left: 70 });
              }
              this.msgRow(it);
            }, (it: FoundItem) => `ht_${it.chatId}_${it.messageId}_${it.chatTitle}_${it.avatarPath}`);
          }.width('100%');
        }
        if (this.tab === TAB_APPS) {
          Column() {
            ForEach(this.apps.filter((r: SearchRow) =>
              r.title.toLowerCase().includes(this.query.trim().toLowerCase())),
              (r: SearchRow, idx: number) => {
                this.appRow(r, idx > 0);
              }, (r: SearchRow) => `capp_${r.userId}_${r.avatarPath}_${r.title}`);
          }.width('100%').backgroundColor($r('app.color.surface'));
        } else {
          Column() {
            ForEach(this.chatResults.filter((r: SearchRow) => this.tab === TAB_CHATS || r.isChannel),
              (r: SearchRow, idx: number) => {
                this.chatRow(r, idx > 0);
              }, (r: SearchRow) => `cres_${r.chatId}_${r.avatarPath}_${r.title}_${r.subtitle}`);
          }.width('100%').backgroundColor($r('app.color.surface'));
        }
        this.sectionHeader('消息');
        if (this.loading && this.items.length === 0) {
          Row() {
            LoadingProgress().width(26).height(26).color(COLOR_TEXT_SECONDARY);
          }.width('100%').justifyContent(FlexAlign.Center).padding(16);
        } else {
          Column() {
            ForEach(this.visibleItems(), (it: FoundItem, idx: number) => {
              if (idx > 0) {
                Divider().color($r('app.color.divider')).strokeWidth(0.7).margin({ left: 70 });
              }
              this.msgRow(it);
            }, (it: FoundItem) => `cm_${it.chatId}_${it.messageId}_${it.chatTitle}_${it.avatarPath}`);
          }.width('100%');
          if (this.visibleItems().length === 0 && this.searchedOnce && this.searchExhausted()) {
            Text('未找到相关消息').fontSize(14).fontColor(COLOR_TEXT_SECONDARY)
              .width('100%').textAlign(TextAlign.Center).padding(16);
          }
          // Only while a page is actually being fetched — `nextOffset !== ''`
          // alone would leave a spinner parked under an idle list.
          if (this.pagingBusy) {
            Row() {
              LoadingProgress().width(22).height(22).color(COLOR_TEXT_SECONDARY);
            }.width('100%').justifyContent(FlexAlign.Center).padding(10);
          }
        }
      }.width('100%');
    }
    .layoutWeight(1).width('100%')
    .align(Alignment.Top)
    .edgeEffect(EdgeEffect.Spring)
    .scrollBar(BarState.Off)
    .onReachEnd(() => {
      if (this.nextOffset !== '' && !this.loading) {
        this.searchMessages(this.nextOffset);
      }
    });
  }

  // 帖子 tab prompt: explicit search button (each run burns server quota).
  @Builder
  postsPrompt() {
    Column({ space: 10 }) {
      Text('全局搜索').fontSize(17).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY);
      Text('输入关键词搜索公开频道的帖子')
        .fontSize(14).fontColor(COLOR_TEXT_SECONDARY);
      if (this.query.trim() !== '') {
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.magnifyingglass')).fontSize(16).fontColor([Color.White]);
          Text(`搜索 ${this.query.trim()}`)
            .fontSize(16).fontWeight(FontWeight.Medium).fontColor(Color.White)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: 200 });
          SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(14).fontColor([Color.White]);
        }
        .backgroundColor(COLOR_PRIMARY).borderRadius(24)
        .padding({ left: 22, right: 22, top: 12, bottom: 12 })
        .margin({ top: 6 })
        .onClick(() => { this.searchMessages(''); });
      }
      if (this.postsQuota !== '') {
        Text(this.postsQuota).fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
      }
    }
    .layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
  }

  @Builder
  messageResults() {
    if (this.loading) {
      Column() {
        LoadingProgress().width(36).height(36).color(COLOR_TEXT_SECONDARY);
      }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
    } else if (this.items.length === 0 && this.searchedOnce) {
      Column() {
        Text(this.tab === TAB_LINKS ? '没有链接消息'
          : (this.tab === TAB_FILES ? '没有文件消息'
            : (this.tab === TAB_AUDIO ? '没有音频消息'
              : (this.tab === TAB_VOICE ? '没有语音消息'
                : (this.tab === TAB_PUBLIC_POSTS ? '没有相关公开贴文' : '未找到相关消息')))))
          .fontSize(14).fontColor(COLOR_TEXT_SECONDARY);
      }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
    } else {
      List() {
        ForEach(this.items, (it: FoundItem) => {
          ListItem() {
            this.msgRow(it);
          }
        }, (it: FoundItem) => `${it.chatId}_${it.messageId}_${it.chatTitle}_${it.avatarPath}`);
        // Spin only while a page is in flight — a spinner parked under an idle
        // list reads as "stuck loading".
        if (this.pagingBusy) {
          ListItem() {
            Row() {
              LoadingProgress().width(22).height(22).color(COLOR_TEXT_SECONDARY);
            }.width('100%').justifyContent(FlexAlign.Center).padding(10);
          }
        }
      }
      .layoutWeight(1).width('100%')
      .divider({ strokeWidth: 0.7, color: $r('app.color.divider'), startMargin: 14, endMargin: 14 })
      // Prefetch the next page a few rows before the bottom (no tap needed).
      .onScrollIndex((_start: number, end: number) => {
        if (this.nextOffset !== '' && !this.loading && end >= this.items.length - 5) {
          this.searchMessages(this.nextOffset);
        }
      });
    }
  }

  @Builder
  tabBody(idx: number) {
    if (idx === TAB_DOWNLOADS) {
      this.downloadsList();
    } else if (idx === TAB_APPS && this.query.trim() === '') {
      this.appsList();
    } else if (idx === TAB_MEDIA) {
      this.mediaGrid();
    } else if (filterTypeForTab(idx) !== '') {
      // 链接/文件/音频/语音: typed-message results, query optional.
      this.messageResults();
    } else if (idx === TAB_POSTS) {
      // Prompt (with explicit 搜索 button) until a search actually ran.
      if (this.loading || this.searchedOnce) {
        this.messageResults();
      } else {
        this.postsPrompt();
      }
    } else if (idx === TAB_PUBLIC_POSTS) {
      if (this.query.trim() === '') {
        Column({ space: 8 }) {
          Text('公开贴文').fontSize(17).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY);
          Text('输入话题关键词搜索公开频道的贴文')
            .fontSize(14).fontColor(COLOR_TEXT_SECONDARY);
        }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
      } else {
        this.messageResults();
      }
    } else if (this.query.trim() === '') {
      if (idx === TAB_CHATS) {
        this.landing();
      } else {
        this.channelsLanding();
      }
    } else {
      this.combinedResults();
    }
  }

  build() {
    Column() {
      Column() {
        this.searchBar();
        this.tabsBar();
      }
      .width('100%').padding({ left: 12, right: 12, top: this.topSafe + 10, bottom: 8 });

      Tabs({ controller: this.controller, index: this.tab }) {
        ForEach(TABS, (t: string, idx: number) => {
          TabContent() {
            Column() {
              this.tabBody(idx);
            }.width('100%').height('100%');
          }
        }, (t: string) => t);
      }
      .barHeight(0)
      .layoutWeight(1)
      .onAreaChange((_old: Area, area: Area) => { this.tabsWidth = area.width as number; })
      // Content swipe in progress: the pill tracks the finger continuously.
      .onGestureSwipe((index: number, event: TabsAnimationEvent) => {
        if (this.tabsWidth > 0) {
          this.moveIndicatorTo(index - event.currentOffset / this.tabsWidth);
        }
      })
      .onAnimationStart((_index: number, targetIndex: number) => {
        animateTo({ duration: 250, curve: Curve.EaseOut }, () => { this.moveIndicatorTo(targetIndex); });
        this.ensureTabVisible(targetIndex);
      })
      .onChange((index: number) => { this.onTabSelected(index); });
    }
    .width('100%').height('100%')
    .backgroundColor($r('app.color.page_bg'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]);
  }
}
