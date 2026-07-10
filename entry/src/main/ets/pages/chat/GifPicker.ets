import { getTdClient } from '../../tdkit/Globals';
import { TdObject, TdRequest, TdError } from '../../tdkit/TdTypes';
import { COLOR_TEXT_SECONDARY } from '../../util/theme';

export interface GifItem {
  fileId: number;    // the animation file (what gets sent)
  width: number;
  height: number;
  duration: number;
  thumbPath: string; // raster thumbnail ('' while downloading)
}

// Saved-GIFs picker for the input panel. Tapping a GIF sends it.
@Component
export struct GifPicker {
  onPick: (g: GifItem) => void = (): void => {};
  @State gifs: GifItem[] = [];
  @State loading: boolean = true;

  aboutToAppear(): void {
    this.load();
  }

  private load(): void {
    const req: TdRequest = { '@type': 'getSavedAnimations' };
    getTdClient().send(req).then((res: TdObject) => {
      const raw = (res['animations'] as TdObject[] | undefined) ?? [];
      const items: GifItem[] = [];
      for (const a of raw) {
        const file = a['animation'] as TdObject | undefined;
        const fileId = file !== undefined ? ((file['id'] as number | undefined) ?? 0) : 0;
        if (fileId === 0) {
          continue;
        }
        items.push({
          fileId,
          width: (a['width'] as number | undefined) ?? 0,
          height: (a['height'] as number | undefined) ?? 0,
          duration: (a['duration'] as number | undefined) ?? 0,
          thumbPath: ''
        });
        this.downloadThumb(fileId, a['thumbnail'] as TdObject | undefined);
      }
      this.gifs = items;
      this.loading = false;
    }).catch((e: TdError) => {
      console.error(`GifPicker.getSavedAnimations failed: ${e.message}`);
      this.loading = false;
    });
  }

  private downloadThumb(gifFileId: number, thumb: TdObject | undefined): void {
    const format = thumb !== undefined ? (thumb['format'] as TdObject | undefined) : undefined;
    const formatName = format !== undefined ? ((format['@type'] as string | undefined) ?? '') : '';
    const isRaster = formatName === 'thumbnailFormatJpeg' || formatName === 'thumbnailFormatWebp'
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
      this.gifs = this.gifs.map((g: GifItem): GifItem =>
        g.fileId === gifFileId
          ? { fileId: g.fileId, width: g.width, height: g.height, duration: g.duration, thumbPath: path }
          : g);
    }).catch((e: TdError) => {
      console.error(`GifPicker.downloadThumb failed: ${e.message}`);
    });
  }

  build() {
    Column() {
      if (this.loading) {
        Column() {
          LoadingProgress().width(32).height(32).color(COLOR_TEXT_SECONDARY);
        }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
      } else if (this.gifs.length === 0) {
        Column() {
          Text('还没有保存的 GIF').fontSize(14).fontColor(COLOR_TEXT_SECONDARY);
        }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
      } else {
        Grid() {
          ForEach(this.gifs, (g: GifItem) => {
            GridItem() {
              if (g.thumbPath !== '') {
                Image(`file://${g.thumbPath}`)
                  .width('100%').aspectRatio(1).objectFit(ImageFit.Cover).borderRadius(6)
                  .onClick(() => { this.onPick(g); });
              } else {
                Column()
                  .width('100%').aspectRatio(1).borderRadius(6).backgroundColor('#E4E4E4')
                  .onClick(() => { this.onPick(g); });
              }
            }
          }, (g: GifItem) => `${g.fileId}_${g.thumbPath}`);
        }
        .columnsTemplate('1fr 1fr 1fr')
        .columnsGap(6).rowsGap(6)
        .padding({ left: 10, right: 10, top: 6, bottom: 6 })
        .layoutWeight(1).width('100%');
      }
    }
    .width('100%').height('100%');
  }
}
