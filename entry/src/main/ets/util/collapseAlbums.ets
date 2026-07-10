import { MessageEntry } from '../store/MessageEntry';
import { TdObject } from '../tdkit/TdTypes';
import { formatDateSeparator, sameDay } from './formatDateSeparator';

// A display row: a single message, or a collapsed run of album (media group)
// photos rendered as one grid bubble.
export interface AlbumGroup {
  key: string;
  head: MessageEntry;      // carries sender/name/time/status for the row
  memberIds: number[];     // message ids in this row (1 for a normal message)
  photoPaths: string[];    // album photo/video-thumbnail paths (empty for a non-album row)
  photoRatios: number[];   // width/height per photo, parallel to photoPaths (masonry layout)
  photoIsVideo: boolean[]; // parallel to photoPaths — true for video members (play icon overlay)
  photoProgress: number[]; // parallel to photoPaths — thumbnail download progress (0-100)
  caption: string;         // album caption (from whichever member carries text)
  captionEntities: TdObject[]; // the caption's TDLib entities (links/mentions/hashtags)
  dateLabel: string;       // date pill shown above this row when the day changes ('' = none)
  showAvatar: boolean;     // last row of a same-sender run — the only one with the avatar
  showSenderName: boolean; // first row of a same-sender run — the only one with the name
}

// Consecutive rows by the same sender form a "run": the sender name renders only
// on the first row and the avatar only on the last (Telegram style).
function sameRun(a: MessageEntry, b: MessageEntry): boolean {
  return a.senderId !== 0 && a.senderId === b.senderId
    && a.isOutgoing === b.isOutgoing
    && a.contentType !== 'system' && b.contentType !== 'system';
}

function aspectRatio(m: MessageEntry): number {
  if (m.photoWidth <= 0 || m.photoHeight <= 0) {
    return 1;
  }
  return m.photoWidth / m.photoHeight;
}

// Signature of the mutable fields a bubble renders that aren't already part of
// the key. Keys MUST change whenever rendered content changes: the LazyForEach
// data source diffs by key and skips notifications for key-equal rows.
function mutableSig(m: MessageEntry): string {
  // videoPath: voice/file/video rows change rendering once the file lands.
  let s = `${m.commentCount}_${m.forwardFrom}_${m.videoPath !== '' ? 'v' : ''}_${m.stickerPath !== '' ? 's' : ''}`;
  for (const r of m.reactions) {
    s += `|${r.emoji}${r.count}${r.isChosen ? 'c' : ''}`;
  }
  for (const row of m.inlineButtons) {
    for (const b of row) {
      s += `#${b.text}`;
    }
  }
  return s;
}

// Collapse consecutive photo messages that share a non-empty media_album_id into
// one AlbumGroup. Everything else passes through as a single-member group.
export function collapseAlbums(list: MessageEntry[]): AlbumGroup[] {
  const groups: AlbumGroup[] = [];
  let i = 0;
  let prevDate = 0;
  while (i < list.length) {
    const m = list[i];
    // Date pill above the first row of each calendar day (and the window's first row).
    const dateLabel: string = (prevDate === 0 || !sameDay(m.date, prevDate)) ? formatDateSeparator(m.date) : '';
    prevDate = m.date;
    if (m.albumId !== '' && (m.contentType === 'photo' || m.contentType === 'video')) {
      const memberIds: number[] = [];
      const photoPaths: string[] = [];
      const photoRatios: number[] = [];
      const photoIsVideo: boolean[] = [];
      const photoProgress: number[] = [];
      let caption = '';
      let captionEntities: TdObject[] = [];
      let j = i;
      while (j < list.length && list[j].albumId === m.albumId && (list[j].contentType === 'photo' || list[j].contentType === 'video')) {
        memberIds.push(list[j].id);
        photoPaths.push(list[j].photoPath);
        photoRatios.push(aspectRatio(list[j]));
        photoIsVideo.push(list[j].contentType === 'video');
        photoProgress.push(list[j].photoProgress);
        if (list[j].text !== '') {
          caption = list[j].text;
          captionEntities = list[j].textEntities;
        }
        j += 1;
      }
      groups.push({
        key: `a_${m.albumId}_${m.id}_${photoPaths.join('|')}_${photoProgress.join(',')}_${caption}_${dateLabel}_${mutableSig(m)}`,
        head: m,
        memberIds,
        photoPaths,
        photoRatios,
        photoIsVideo,
        photoProgress,
        caption,
        captionEntities,
        dateLabel,
        showAvatar: true,
        showSenderName: true
      });
      i = j;
    } else {
      groups.push({
        key: `${m.id}_${m.sendState}_${m.photoPath}_${m.photoProgress}_${m.text}_${m.replyText}_${m.senderAvatarPath}_${dateLabel}_${mutableSig(m)}`,
        head: m,
        memberIds: [m.id],
        photoPaths: [],
        photoRatios: [],
        photoIsVideo: [],
        photoProgress: [],
        caption: '',
        captionEntities: [],
        dateLabel,
        showAvatar: true,
        showSenderName: true
      });
      i += 1;
    }
  }
  // Second pass: mark run boundaries (a date pill between rows breaks the run).
  // The flags join the key so a row re-renders when a same-sender neighbor
  // arrives and its avatar/name visibility flips.
  for (let k = 0; k < groups.length; k++) {
    const next = k + 1 < groups.length ? groups[k + 1] : null;
    const prev = k - 1 >= 0 ? groups[k - 1] : null;
    groups[k].showAvatar = !(next !== null && next.dateLabel === '' && sameRun(groups[k].head, next.head));
    groups[k].showSenderName = !(prev !== null && groups[k].dateLabel === '' && sameRun(prev.head, groups[k].head));
    groups[k].key += `_${groups[k].showAvatar ? 'A' : 'a'}${groups[k].showSenderName ? 'N' : 'n'}`;
  }
  return groups;
}

// Display-row index containing a given message id (-1 if not present).
export function groupIndexOf(groups: AlbumGroup[], messageId: number): number {
  for (let i = 0; i < groups.length; i++) {
    if (groups[i].memberIds.indexOf(messageId) >= 0) {
      return i;
    }
  }
  return -1;
}
