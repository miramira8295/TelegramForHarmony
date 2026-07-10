// Pack album photos into masonry rows (like Telegram's album grid): each row is
// scaled to exactly fill targetWidth while preserving every photo's aspect ratio,
// so row heights vary with the photos placed in them instead of a uniform square grid.

export interface AlbumCell {
  idx: number;
  width: number;
  height: number;
}

const BASE_HEIGHT: number = 130;
const MAX_PER_ROW: number = 3;

export function packAlbumRows(ratios: number[], targetWidth: number): AlbumCell[][] {
  const rows: AlbumCell[][] = [];
  let row: AlbumCell[] = [];
  let rowNaturalWidth = 0;

  const flush = (): void => {
    if (row.length === 0) {
      return;
    }
    const scale = targetWidth / rowNaturalWidth;
    const scaled: AlbumCell[] = [];
    for (const c of row) {
      scaled.push({ idx: c.idx, width: c.width * scale, height: c.height * scale });
    }
    rows.push(scaled);
    row = [];
    rowNaturalWidth = 0;
  };

  for (let i = 0; i < ratios.length; i++) {
    const ratio = ratios[i] > 0 ? ratios[i] : 1;
    const naturalWidth = BASE_HEIGHT * ratio;
    row.push({ idx: i, width: naturalWidth, height: BASE_HEIGHT });
    rowNaturalWidth += naturalWidth;
    if (rowNaturalWidth >= targetWidth || row.length >= MAX_PER_ROW) {
      flush();
    }
  }
  flush();
  return rows;
}
