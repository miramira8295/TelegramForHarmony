import { getTdClient } from '../../tdkit/Globals';
import { TgsStickerView } from './TgsStickerView';
import { SmartLoopVideo } from '../common/SmartLoopVideo';
import { TdObject, TdRequest, TdError } from '../../tdkit/TdTypes';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';

export interface StickerItem {
  fileId: number;   // the sticker's own file (what gets sent)
  width: number;
  height: number;
  thumbPath: string; // raster thumbnail local path ('' while downloading)
  thumbFileId: number; // raster thumbnail file id (0 if none)
  emoji: string;
  format: string;    // 'webp' | 'tgs' | 'webm' | 'unicode'
  srcPath: string;   // local TGS source path ('' until downloaded) — drives animation
  customEmojiId: string; // custom emoji id ('' for regular stickers)
}

// One row of the continuous grid: a full-width pack header or a sticker cell.
interface FlatEntry {
  kind: string;   // 'header' | 'sticker'
  title: string;
  setIdx: number; // owning pack index — drives the tab highlight while scrolling
  sticker: StickerItem | null;
}

// Minimal IDataSource so the grid virtualizes (only visible cells mount their
// Lottie canvases — a full set would otherwise run 100+ animations at once).
class StickerDataSource implements IDataSource {
  private items: FlatEntry[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): FlatEntry {
    return this.items[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    this.listeners = this.listeners.filter((l: DataChangeListener) => l !== listener);
  }

  update(next: FlatEntry[]): void {
    this.items = next;
    for (const l of this.listeners) {
      l.onDatasetChange([{ type: DataOperationType.RELOAD } as DataReloadOperation]);
    }
  }
}

interface StickerSetTab {
  id: string;    // int64 set id — kept as the string TDLib's JSON delivers
  title: string;
  iconPath: string; // pack cover thumbnail for the tab strip ('' = text fallback)
  iconText: string; // emoji glyph tab icon (classic unicode packs)
  loaded: boolean;
  stickers: StickerItem[];
}

// A built-in unicode emoji section shown as a synthetic pack before the
// network packs (the chat panel's classic emoji).
export interface ClassicPack {
  title: string;
  icon: string;
  emoji: string[];
}

const SET_LIMIT: number = 20;

// Sticker picker for the input panel: installed sticker sets as horizontal
// tabs, the selected set as a grid. Tapping a sticker sends it.
// stickerType 'custom_emoji' (+ includeTrending) turns it into the emoji
// library used by the avatar builder — installed emoji packs plus the
// server's trending packs, like the official client.
@Component
export struct StickerPicker {
  onPick: (s: StickerItem) => void = (): void => {};
  stickerType: string = 'regular'; // 'regular' | 'custom_emoji'
  includeTrending: boolean = false;
  classicPacks: ClassicPack[] = []; // built-in unicode sections, shown first
  // false = static thumbnails only (no Lottie/ijkplayer cells) — used by the
  // avatar picker dialog where a grid full of players stutters.
  animate: boolean = true;
  @State sets: StickerSetTab[] = [];
  @State curSet: number = 0;
  @State loading: boolean = true;
  private gridData: StickerDataSource = new StickerDataSource();

  aboutToAppear(): void {
    if (this.classicPacks.length > 0) {
      this.sets = this.classicPacks.map((c: ClassicPack, i: number): StickerSetTab => ({
        id: `classic_${i}`,
        title: c.title,
        iconPath: '',
        iconText: c.icon,
        loaded: true,
        stickers: c.emoji.map((ch: string): StickerItem => ({
          fileId: 0, width: 0, height: 0, thumbPath: '', thumbFileId: 0, emoji: ch, format: 'unicode', srcPath: '', customEmojiId: ''
        }))
      }));
      this.loading = false;
      this.refreshGrid();
    }
    this.loadSets();
  }

  private typeObj(): TdObject {
    return {
      '@type': this.stickerType === 'custom_emoji' ? 'stickerTypeCustomEmoji' : 'stickerTypeRegular'
    } as TdObject;
  }

  private loadSets(): void {
    const req: TdRequest = { '@type': 'getInstalledStickerSets' };
    req['sticker_type'] = this.typeObj();
    getTdClient().send(req).then((res: TdObject) => {
      const raw = (res['sets'] as TdObject[] | undefined) ?? [];
      const tabs: StickerSetTab[] = [];
      for (const s of raw.slice(0, SET_LIMIT)) {
        const id = `${s['id']}`; // int64 arrives as a string in TDLib JSON — keep verbatim
        tabs.push({
          id,
          title: (s['title'] as string | undefined) ?? '',
          iconPath: '',
          iconText: '',
          loaded: false,
          stickers: []
        });
        this.resolveTabIcon(id, s);
      }
      this.sets = [...this.sets, ...tabs];
      this.loading = false;
      if (this.classicPacks.length === 0 && tabs.length > 0) {
        this.selectSet(0);
      } else {
        this.refreshGrid();
      }
      if (this.includeTrending) {
        this.loadTrending();
      }
    }).catch((e: TdError) => {
      console.error(`StickerPicker.getInstalledStickerSets failed: ${e.message}`);
      this.loading = false;
      if (this.includeTrending) {
        this.loadTrending();
      }
    });
  }

  // Server-trending packs appended after the installed ones (deduped).
  private loadTrending(): void {
    const req: TdRequest = { '@type': 'getTrendingStickerSets' };
    req['sticker_type'] = this.typeObj();
    req['offset'] = 0;
    req['limit'] = 30;
    getTdClient().send(req).then((res: TdObject) => {
      const raw = (res['sets'] as TdObject[] | undefined) ?? [];
      const known = new Set<string>(this.sets.map((t: StickerSetTab) => t.id));
      const extra: StickerSetTab[] = [];
      for (const s of raw) {
        const id = `${s['id']}`;
        if (known.has(id)) {
          continue;
        }
        known.add(id);
        extra.push({
          id,
          title: (s['title'] as string | undefined) ?? '',
          iconPath: '',
          iconText: '',
          loaded: false,
          stickers: []
        });
        this.resolveTabIcon(id, s);
      }
      if (extra.length > 0) {
        const hadNone = this.sets.length === 0;
        this.sets = [...this.sets, ...extra];
        this.loading = false;
        if (hadNone) {
          this.selectSet(0);
        }
      }
    }).catch((e: TdError) => {
      console.error(`StickerPicker.getTrendingStickerSets failed: ${e.message}`);
    });
  }

  // Only raster thumbnails render in an Image — animated (tgs/webm) covers
  // would show as a blank tab.
  private rasterThumbFile(thumb: TdObject | undefined): TdObject | undefined {
    if (thumb === undefined) {
      return undefined;
    }
    const fmt = thumb['format'] as TdObject | undefined;
    const name = fmt !== undefined ? ((fmt['@type'] as string | undefined) ?? '') : '';
    const isRaster = name === 'thumbnailFormatWebp' || name === 'thumbnailFormatJpeg'
      || name === 'thumbnailFormatPng';
    return isRaster ? (thumb['file'] as TdObject | undefined) : undefined;
  }

  // Pack cover → tab icon (thumbnail of the set's thumbnail or first cover).
  private resolveTabIcon(setId: string, info: TdObject): void {
    let file = this.rasterThumbFile(info['thumbnail'] as TdObject | undefined);
    if (file === undefined) {
      const covers = (info['covers'] as TdObject[] | undefined) ?? [];
      if (covers.length > 0) {
        file = this.rasterThumbFile(covers[0]['thumbnail'] as TdObject | undefined);
      }
    }
    const fileId = file !== undefined ? ((file['id'] as number | undefined) ?? 0) : 0;
    if (fileId === 0) {
      return;
    }
    const req: TdRequest = { '@type': 'downloadFile' };
    req['file_id'] = fileId;
    req['priority'] = 1;
    req['synchronous'] = true;
    getTdClient().send(req).then((f: TdObject) => {
      const local = f['local'] as TdObject | undefined;
      const path = local !== undefined ? ((local['path'] as string | undefined) ?? '') : '';
      if (path === '') {
        return;
      }
      this.sets = this.sets.map((t: StickerSetTab): StickerSetTab => t.id === setId
        ? { id: t.id, title: t.title, iconPath: path, iconText: t.iconText, loaded: t.loaded, stickers: t.stickers } : t);
    }).catch((e: TdError) => {
      console.error(`StickerPicker.resolveTabIcon failed: ${e.message}`);
    });
  }

  // --- search (searchStickers over public packs) ---
  @State searchQuery: string = '';
  @State searchItems: StickerItem[] = [];
  private searchTimer: number = -1;
  private searchSeq: number = 0;

  private onSearchChanged(v: string): void {
    this.searchQuery = v;
    if (this.searchTimer !== -1) {
      clearTimeout(this.searchTimer);
    }
    this.searchTimer = setTimeout(() => {
      this.searchTimer = -1;
      this.runStickerSearch();
    }, 300);
  }

  private runStickerSearch(): void {
    const q = this.searchQuery.trim();
    const seq = ++this.searchSeq;
    if (q === '') {
      this.searchItems = [];
      this.refreshGrid();
      return;
    }
    const req: TdRequest = { '@type': 'searchStickers' };
    req['sticker_type'] = this.typeObj();
    // Both fields set: emoji input matches by emoji, words match by keyword
    // (whichever this TDLib build supports wins; extras are ignored).
    req['emojis'] = q;
    req['query'] = q;
    req['limit'] = 60;
    getTdClient().send(req).then((res: TdObject) => {
      if (seq !== this.searchSeq) {
        return;
      }
      const raw = (res['stickers'] as TdObject[] | undefined) ?? [];
      const items: StickerItem[] = [];
      for (const st of raw) {
        const file = st['sticker'] as TdObject | undefined;
        const fileId = file !== undefined ? ((file['id'] as number | undefined) ?? 0) : 0;
        if (fileId === 0) {
          continue;
        }
        const fmt = st['format'] as TdObject | undefined;
        const fmtName = fmt !== undefined ? ((fmt['@type'] as string | undefined) ?? '') : '';
        const format = fmtName === 'stickerFormatWebp' ? 'webp'
          : (fmtName === 'stickerFormatTgs' ? 'tgs' : 'webm');
        const fullType = st['full_type'] as TdObject | undefined;
        const ceId = fullType !== undefined
          && ((fullType['@type'] as string | undefined) ?? '') === 'stickerFullTypeCustomEmoji'
          ? `${fullType['custom_emoji_id']}` : '';
        const rasterThumb = this.rasterThumbFile(st['thumbnail'] as TdObject | undefined);
        items.push({
          fileId,
          width: (st['width'] as number | undefined) ?? 512,
          height: (st['height'] as number | undefined) ?? 512,
          thumbPath: '',
          thumbFileId: rasterThumb !== undefined ? ((rasterThumb['id'] as number | undefined) ?? 0) : 0,
          emoji: (st['emoji'] as string | undefined) ?? '',
          format, srcPath: '', customEmojiId: ceId
        });
        this.downloadSearchThumb(fileId, st['thumbnail'] as TdObject | undefined);
      }
      this.searchItems = items;
      this.refreshGrid();
    }).catch((e: TdError) => {
      console.error(`StickerPicker.searchStickers failed: ${e.message}`);
    });
  }

  private downloadSearchThumb(stickerFileId: number, thumb: TdObject | undefined): void {
    const file = thumb !== undefined ? (thumb['file'] as TdObject | undefined) : undefined;
    const fileId = file !== undefined ? ((file['id'] as number | undefined) ?? 0) : 0;
    if (fileId === 0) {
      return;
    }
    const req: TdRequest = { '@type': 'downloadFile' };
    req['file_id'] = fileId;
    req['priority'] = 1;
    req['synchronous'] = true;
    getTdClient().send(req).then((f: TdObject) => {
      const local = f['local'] as TdObject | undefined;
      const path = local !== undefined ? ((local['path'] as string | undefined) ?? '') : '';
      if (path === '') {
        return;
      }
      this.searchItems = this.searchItems.map((it: StickerItem): StickerItem => it.fileId === stickerFileId
        ? {
          fileId: it.fileId, width: it.width, height: it.height,
          thumbPath: path, thumbFileId: it.thumbFileId, emoji: it.emoji,
          format: it.format, srcPath: it.srcPath, customEmojiId: it.customEmojiId
        } : it);
      if (this.searchQuery.trim() !== '') {
        this.refreshGrid();
      }
    }).catch((e: TdError) => {
      console.error(`StickerPicker.downloadSearchThumb failed: ${e.message}`);
    });
  }

  // The grid shows sets[anchor..] as ONE continuous scroll; packs load in
  // order as the user scrolls down, and the tab highlight follows the pack
  // at the top of the viewport. Tapping a tab re-anchors the grid there.
  private anchor: number = 0;
  private flatEntries: FlatEntry[] = [];
  private gridScroller: Scroller = new Scroller();
  private loadingSet: boolean = false;

  private selectSet(idx: number): void {
    this.curSet = idx;
    this.anchor = idx;
    this.refreshGrid();
    this.gridScroller.scrollToIndex(0);
    if (idx >= 0 && idx < this.sets.length && !this.sets[idx].loaded) {
      this.loadSetContents(idx);
    }
  }

  // Load the next unloaded pack after the anchor (keeps the flat list contiguous).
  private loadNextSet(): void {
    for (let i = this.anchor; i < this.sets.length; i++) {
      if (!this.sets[i].loaded) {
        this.loadSetContents(i);
        return;
      }
    }
  }

  private flatten(): FlatEntry[] {
    const out: FlatEntry[] = [];
    for (let i = this.anchor; i < this.sets.length; i++) {
      const t = this.sets[i];
      if (!t.loaded) {
        break; // contiguity: stop at the first not-yet-loaded pack
      }
      out.push({ kind: 'header', title: t.title, setIdx: i, sticker: null });
      for (const st of t.stickers) {
        out.push({ kind: 'sticker', title: '', setIdx: i, sticker: st });
      }
    }
    return out;
  }

  // Scroll position → owning pack: highlight its tab and keep it visible.
  private onGridScrolled(first: number, last: number): void {
    if (this.searchQuery.trim() !== '') {
      return;
    }
    if (first >= 0 && first < this.flatEntries.length) {
      const owner = this.flatEntries[first].setIdx;
      if (owner !== this.curSet) {
        this.curSet = owner;
        this.tabScroller.scrollTo({
          xOffset: Math.max(0, owner * 44 - 120), yOffset: 0,
          animation: { duration: 200, curve: Curve.EaseOut }
        });
      }
    }
    if (last >= this.flatEntries.length - 12 && !this.loadingSet) {
      this.loadNextSet();
    }
  }

  private tabScroller: Scroller = new Scroller();

  private loadSetContents(idx: number): void {
    if (idx < 0 || idx >= this.sets.length || this.sets[idx].loaded || this.loadingSet) {
      return;
    }
    this.loadingSet = true;
    const setId = this.sets[idx].id;
    const req: TdRequest = { '@type': 'getStickerSet' };
    req['set_id'] = setId;
    getTdClient().send(req).then((res: TdObject) => {
      const raw = (res['stickers'] as TdObject[] | undefined) ?? [];
      const items: StickerItem[] = [];
      for (const st of raw) {
        const file = st['sticker'] as TdObject | undefined;
        const fileId = file !== undefined ? ((file['id'] as number | undefined) ?? 0) : 0;
        if (fileId === 0) {
          continue;
        }
        const fmt = st['format'] as TdObject | undefined;
        const fmtName = fmt !== undefined ? ((fmt['@type'] as string | undefined) ?? '') : '';
        const format = fmtName === 'stickerFormatWebp' ? 'webp'
          : (fmtName === 'stickerFormatTgs' ? 'tgs' : 'webm');
        const fullType = st['full_type'] as TdObject | undefined;
        const ceId = fullType !== undefined
          && ((fullType['@type'] as string | undefined) ?? '') === 'stickerFullTypeCustomEmoji'
          ? `${fullType['custom_emoji_id']}` : '';
        const rasterThumb = this.rasterThumbFile(st['thumbnail'] as TdObject | undefined);
        items.push({
          fileId,
          width: (st['width'] as number | undefined) ?? 512,
          height: (st['height'] as number | undefined) ?? 512,
          thumbPath: '',
          thumbFileId: rasterThumb !== undefined ? ((rasterThumb['id'] as number | undefined) ?? 0) : 0,
          emoji: (st['emoji'] as string | undefined) ?? '',
          format,
          srcPath: '',
          customEmojiId: ceId
        });
        this.downloadThumb(setId, fileId, st['thumbnail'] as TdObject | undefined);
        if (this.animate && (format === 'tgs' || format === 'webm')) {
          this.downloadSource(setId, fileId);
        }
      }
      let tgs = 0;
      let webm = 0;
      let webp = 0;
      for (const it of items) {
        if (it.format === 'tgs') { tgs++; } else if (it.format === 'webm') { webm++; } else { webp++; }
      }
      console.info(`StickerPicker: set ${setId} loaded ${items.length} stickers (tgs=${tgs} webm=${webm} webp=${webp})`);
      this.sets = this.sets.map((t: StickerSetTab): StickerSetTab =>
        t.id === setId ? { id: t.id, title: t.title, iconPath: t.iconPath, iconText: t.iconText, loaded: true, stickers: items } : t);
      this.loadingSet = false;
      this.refreshGrid();
    }).catch((e: TdError) => {
      this.loadingSet = false;
      console.error(`StickerPicker.getStickerSet failed: ${e.message}`);
    });
  }

  // Download the raster thumbnail (synchronous download — thumbs are tiny),
  // then patch it into the right set/sticker immutably.
  private downloadThumb(setId: string, stickerFileId: number, thumb: TdObject | undefined) {
    const format = thumb !== undefined ? (thumb['format'] as TdObject | undefined) : undefined;
    const formatName = format !== undefined ? ((format['@type'] as string | undefined) ?? '') : '';
    const isRaster = formatName === 'thumbnailFormatWebp' || formatName === 'thumbnailFormatJpeg'
      || formatName === 'thumbnailFormatPng';
    const thumbFile = thumb !== undefined && isRaster ? (thumb['file'] as TdObject | undefined) : undefined;
    const thumbFileId = thumbFile !== undefined ? ((thumbFile['id'] as number | undefined) ?? 0) : 0;
    if (thumbFileId === 0) {
      return;
    }
    const req: TdRequest = { '@type': 'downloadFile' };
    req['file_id'] = thumbFileId;
    req['priority'] = 1;
    req['synchronous'] = true;
    getTdClient().send(req).then((f: TdObject) => {
      const local = f['local'] as TdObject | undefined;
      const path = local !== undefined ? ((local['path'] as string | undefined) ?? '') : '';
      if (path === '') {
        return;
      }
      this.patchSticker(setId, stickerFileId, (s: StickerItem): StickerItem => ({
        fileId: s.fileId, width: s.width, height: s.height, thumbPath: path,
        thumbFileId: s.thumbFileId, emoji: s.emoji, format: s.format,
        srcPath: s.srcPath, customEmojiId: s.customEmojiId
      }));
    }).catch((e: TdError) => {
      console.error(`StickerPicker.downloadThumb failed: ${e.message}`);
    });
  }

  private patchSticker(setId: string, stickerFileId: number,
    patch: (s: StickerItem) => StickerItem): void {
    this.sets = this.sets.map((t: StickerSetTab): StickerSetTab => {
      if (t.id !== setId) {
        return t;
      }
      const stickers = t.stickers.map((s: StickerItem): StickerItem =>
        s.fileId === stickerFileId ? patch(s) : s);
      return { id: t.id, title: t.title, iconPath: t.iconPath, iconText: t.iconText, loaded: t.loaded, stickers };
    });
    this.refreshGrid();
  }

  private refreshTimer: number = -1;

  // Debounced: a freshly opened set fires one thumb + one source patch per
  // sticker in quick succession; reloading the grid for each one rebuilds
  // visible cells (and their native players) dozens of times.
  private refreshGrid(): void {
    if (this.refreshTimer !== -1) {
      return;
    }
    this.refreshTimer = setTimeout(() => {
      this.refreshTimer = -1;
      if (this.searchQuery.trim() !== '') {
        this.flatEntries = this.searchItems.map((st: StickerItem): FlatEntry =>
          ({ kind: 'sticker', title: '', setIdx: -1, sticker: st }));
      } else {
        this.flatEntries = this.flatten();
      }
      this.gridData.update(this.flatEntries);
    }, 80);
  }

  aboutToDisappear(): void {
    if (this.refreshTimer !== -1) {
      clearTimeout(this.refreshTimer);
      this.refreshTimer = -1;
    }
  }

  // Sticker source download (small) → animate the grid cell (Lottie / ijk).
  private downloadSource(setId: string, stickerFileId: number): void {
    const req: TdRequest = { '@type': 'downloadFile' };
    req['file_id'] = stickerFileId;
    req['priority'] = 1;
    req['synchronous'] = true;
    getTdClient().send(req).then((f: TdObject) => {
      const local = f['local'] as TdObject | undefined;
      const path = local !== undefined ? ((local['path'] as string | undefined) ?? '') : '';
      if (path === '') {
        return;
      }
      this.patchSticker(setId, stickerFileId, (s: StickerItem): StickerItem => ({
        fileId: s.fileId, width: s.width, height: s.height, thumbPath: s.thumbPath,
        thumbFileId: s.thumbFileId, emoji: s.emoji, format: s.format,
        srcPath: path, customEmojiId: s.customEmojiId
      }));
    }).catch((e: TdError) => {
      console.error(`StickerPicker.downloadSource failed: ${e.message}`);
    });
  }

  // Emoji grids use smaller cells (8 columns) — less canvas area per Lottie.
  private cellPx(): number {
    return this.stickerType === 'custom_emoji' ? 38 : 62;
  }

  @Builder
  stickerCell(s: StickerItem) {
    if (this.animate && s.format === 'tgs' && s.srcPath !== '') {
      Column() {
        TgsStickerView({ tgsPath: s.srcPath, thumbPath: s.thumbPath, boxWidth: this.cellPx(), boxHeight: this.cellPx() });
      }
      .width('100%').aspectRatio(1)
      .justifyContent(FlexAlign.Center)
      .onClick(() => { this.onPick(s); });
    } else if (this.animate && s.format === 'webm' && s.srcPath !== '') {
      Column() {
        SmartLoopVideo({ videoPath: s.srcPath, thumbPath: s.thumbPath, boxWidth: this.cellPx(), boxHeight: this.cellPx() });
      }
      .width('100%').aspectRatio(1)
      .justifyContent(FlexAlign.Center)
      .onClick(() => { this.onPick(s); });
    } else if (s.thumbPath !== '') {
      Image(`file://${s.thumbPath}`)
        .width('100%').aspectRatio(1).objectFit(ImageFit.Contain)
        .onClick(() => { this.onPick(s); });
    } else {
      Text(s.emoji).fontSize(this.stickerType === 'custom_emoji' ? 26 : 30).textAlign(TextAlign.Center)
        .width('100%').aspectRatio(1)
        .onClick(() => { this.onPick(s); });
    }
  }

  build() {
    Column() {
      if (this.loading) {
        Column() {
          LoadingProgress().width(32).height(32).color(COLOR_TEXT_SECONDARY);
        }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
      } else if (this.sets.length === 0) {
        Column() {
          Text('没有已安装的贴纸包').fontSize(14).fontColor(COLOR_TEXT_SECONDARY);
        }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
      } else {
        // Pack tabs: cover thumbnails (official-style), title initial fallback.
        Scroll(this.tabScroller) {
          Row({ space: 6 }) {
            ForEach(this.sets, (t: StickerSetTab, idx: number) => {
              Column() {
                if (t.iconPath !== '') {
                  Image(`file://${t.iconPath}`)
                    .width(30).height(30).objectFit(ImageFit.Contain);
                } else if (t.iconText !== '') {
                  Text(t.iconText).fontSize(22);
                } else {
                  Text(t.title.length > 0 ? t.title.substring(0, 1) : '?')
                    .fontSize(15).fontWeight(FontWeight.Medium)
                    .fontColor(this.curSet === idx ? COLOR_PRIMARY : COLOR_TEXT_PRIMARY);
                }
              }
              .width(38).height(38)
              .justifyContent(FlexAlign.Center)
              .backgroundColor(this.curSet === idx && this.searchQuery.trim() === ''
                ? $r('app.color.selected_pill') : Color.Transparent)
              .borderRadius(10)
              .onClick(() => {
                this.searchQuery = '';
                this.searchItems = [];
                this.selectSet(idx);
              });
            }, (t: StickerSetTab) => `${t.id}_${t.iconPath}`);
          }.padding({ left: 8, right: 8 });
        }
        .scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
        .width('100%').height(44);
        // Search bar (searches public packs by emoji/keyword).
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.magnifyingglass')).fontSize(15).fontColor([COLOR_TEXT_SECONDARY]);
          TextInput({ text: this.searchQuery, placeholder: '搜索' })
            .fontSize(14).layoutWeight(1).height(30)
            .backgroundColor(Color.Transparent).padding(0)
            .placeholderColor(COLOR_TEXT_SECONDARY)
            .onChange((v: string) => { this.onSearchChanged(v); });
          if (this.searchQuery !== '') {
            SymbolGlyph($r('sys.symbol.xmark')).fontSize(14).fontColor([COLOR_TEXT_SECONDARY])
              .onClick(() => {
                this.searchQuery = '';
                this.searchItems = [];
                this.refreshGrid();
              });
          }
        }
        .width('92%').height(34)
        .padding({ left: 12, right: 12 })
        .backgroundColor($r('app.color.surface_alt')).borderRadius(17)
        .alignItems(VerticalAlign.Center)
        .margin({ top: 2, bottom: 4 });
        // Continuous grid: every loaded pack in one scroll, section headers
        // between packs; the tab strip follows the pack at the viewport top.
        Grid(this.gridScroller) {
          // LazyForEach: only visible cells mount, so at most a screenful of
          // Lottie canvases animate at once.
          LazyForEach(this.gridData, (e: FlatEntry) => {
            if (e.kind === 'header') {
              GridItem() {
                Text(e.title)
                  .fontSize(13).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_SECONDARY)
                  .width('100%')
                  .padding({ top: 8, bottom: 2 });
              }
              .columnStart(0).columnEnd(this.stickerType === 'custom_emoji' ? 7 : 4);
            } else if (e.sticker !== null) {
              GridItem() {
                this.stickerCell(e.sticker);
              }
            }
          }, (e: FlatEntry) => e.kind === 'header'
            ? `h_${e.setIdx}_${e.title}`
            : `${e.sticker!.fileId}_${e.sticker!.emoji}_${e.sticker!.thumbPath}_${e.sticker!.srcPath}`);
        }
        .columnsTemplate(this.stickerType === 'custom_emoji'
          ? '1fr 1fr 1fr 1fr 1fr 1fr 1fr 1fr' : '1fr 1fr 1fr 1fr 1fr')
        .columnsGap(6).rowsGap(6)
        .padding({ left: 10, right: 10, top: 4, bottom: 4 })
        .layoutWeight(1).width('100%')
        .onScrollIndex((first: number, last: number) => { this.onGridScrolled(first, last); });
      }
    }
    .width('100%').height('100%');
  }
}
