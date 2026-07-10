import { getTdClient } from '../../tdkit/Globals';
import { TgsStickerView } from './TgsStickerView';
import { WebmStickerView } from './WebmStickerView';
import { TdObject, TdRequest, TdError } from '../../tdkit/TdTypes';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';

export interface StickerItem {
  fileId: number;   // the sticker's own file (what gets sent)
  width: number;
  height: number;
  thumbPath: string; // raster thumbnail local path ('' while downloading)
  emoji: string;
  format: string;    // 'webp' | 'tgs' | 'webm'
  srcPath: string;   // local TGS source path ('' until downloaded) — drives animation
}

// Minimal IDataSource so the grid virtualizes (only visible cells mount their
// Lottie canvases — a full set would otherwise run 100+ animations at once).
class StickerDataSource implements IDataSource {
  private items: StickerItem[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): StickerItem {
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

  update(next: StickerItem[]): void {
    this.items = next;
    for (const l of this.listeners) {
      l.onDatasetChange([{ type: DataOperationType.RELOAD } as DataReloadOperation]);
    }
  }
}

interface StickerSetTab {
  id: string;    // int64 set id — kept as the string TDLib's JSON delivers
  title: string;
  loaded: boolean;
  stickers: StickerItem[];
}

const SET_LIMIT: number = 20;

// Sticker picker for the input panel: installed sticker sets as horizontal
// tabs, the selected set as a grid. Tapping a sticker sends it.
@Component
export struct StickerPicker {
  onPick: (s: StickerItem) => void = (): void => {};
  @State sets: StickerSetTab[] = [];
  @State curSet: number = 0;
  @State loading: boolean = true;
  private gridData: StickerDataSource = new StickerDataSource();

  aboutToAppear(): void {
    this.loadSets();
  }

  private loadSets(): void {
    const req: TdRequest = { '@type': 'getInstalledStickerSets' };
    req['sticker_type'] = { '@type': 'stickerTypeRegular' } as TdObject;
    getTdClient().send(req).then((res: TdObject) => {
      const raw = (res['sets'] as TdObject[] | undefined) ?? [];
      const tabs: StickerSetTab[] = [];
      for (const s of raw.slice(0, SET_LIMIT)) {
        tabs.push({
          id: `${s['id']}`, // int64 arrives as a string in TDLib JSON — keep verbatim
          title: (s['title'] as string | undefined) ?? '',
          loaded: false,
          stickers: []
        });
      }
      this.sets = tabs;
      this.loading = false;
      if (tabs.length > 0) {
        this.selectSet(0);
      }
    }).catch((e: TdError) => {
      console.error(`StickerPicker.getInstalledStickerSets failed: ${e.message}`);
      this.loading = false;
    });
  }

  private selectSet(idx: number): void {
    this.curSet = idx;
    if (idx < 0 || idx >= this.sets.length || this.sets[idx].loaded) {
      this.refreshGrid();
      return;
    }
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
        items.push({
          fileId,
          width: (st['width'] as number | undefined) ?? 512,
          height: (st['height'] as number | undefined) ?? 512,
          thumbPath: '',
          emoji: (st['emoji'] as string | undefined) ?? '',
          format,
          srcPath: ''
        });
        this.downloadThumb(setId, fileId, st['thumbnail'] as TdObject | undefined);
        if (format === 'tgs' || format === 'webm') {
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
        t.id === setId ? { id: t.id, title: t.title, loaded: true, stickers: items } : t);
      this.refreshGrid();
    }).catch((e: TdError) => {
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
        emoji: s.emoji, format: s.format, srcPath: s.srcPath
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
      return { id: t.id, title: t.title, loaded: t.loaded, stickers };
    });
    this.refreshGrid();
  }

  private refreshGrid(): void {
    this.gridData.update(this.currentStickers());
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
        emoji: s.emoji, format: s.format, srcPath: path
      }));
    }).catch((e: TdError) => {
      console.error(`StickerPicker.downloadSource failed: ${e.message}`);
    });
  }

  private currentStickers(): StickerItem[] {
    return this.curSet >= 0 && this.curSet < this.sets.length ? this.sets[this.curSet].stickers : [];
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
        // Set tabs.
        Scroll() {
          Row({ space: 4 }) {
            ForEach(this.sets, (t: StickerSetTab, idx: number) => {
              Text(t.title)
                .fontSize(13).maxLines(1)
                .fontColor(this.curSet === idx ? COLOR_PRIMARY : COLOR_TEXT_PRIMARY)
                .fontWeight(this.curSet === idx ? FontWeight.Bold : FontWeight.Normal)
                .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                .backgroundColor(this.curSet === idx ? '#EDF3FA' : Color.Transparent)
                .borderRadius(13)
                .onClick(() => { this.selectSet(idx); });
            }, (t: StickerSetTab) => t.id);
          }.padding({ left: 8, right: 8 });
        }
        .scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
        .width('100%').height(36);
        // Sticker grid for the selected set.
        Grid() {
          // LazyForEach: only visible cells mount, so at most a screenful of
          // Lottie canvases animate at once.
          LazyForEach(this.gridData, (s: StickerItem) => {
            GridItem() {
              if (s.format === 'tgs' && s.srcPath !== '') {
                Column() {
                  TgsStickerView({ tgsPath: s.srcPath, thumbPath: s.thumbPath, boxWidth: 62, boxHeight: 62 });
                }
                .width('100%').aspectRatio(1)
                .justifyContent(FlexAlign.Center)
                .onClick(() => { this.onPick(s); });
              } else if (s.format === 'webm' && s.srcPath !== '') {
                Column() {
                  WebmStickerView({ webmPath: s.srcPath, thumbPath: s.thumbPath, boxWidth: 62, boxHeight: 62 });
                }
                .width('100%').aspectRatio(1)
                .justifyContent(FlexAlign.Center)
                .onClick(() => { this.onPick(s); });
              } else if (s.thumbPath !== '') {
                Image(`file://${s.thumbPath}`)
                  .width('100%').aspectRatio(1).objectFit(ImageFit.Contain)
                  .onClick(() => { this.onPick(s); });
              } else {
                Text(s.emoji).fontSize(30).textAlign(TextAlign.Center)
                  .width('100%').aspectRatio(1)
                  .onClick(() => { this.onPick(s); });
              }
            }
          }, (s: StickerItem) => `${s.fileId}_${s.thumbPath}_${s.srcPath}`);
        }
        .columnsTemplate('1fr 1fr 1fr 1fr 1fr')
        .columnsGap(8).rowsGap(8)
        .padding({ left: 10, right: 10, top: 4, bottom: 4 })
        .layoutWeight(1).width('100%');
      }
    }
    .width('100%').height('100%');
  }
}
