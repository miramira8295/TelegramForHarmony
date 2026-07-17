import { TdObject } from '../tdkit/TdTypes';

// A styled inline run of text (part of a normal text segment).
export interface RichRun {
  text: string;
  bold: boolean;
  italic: boolean;
  link: boolean; // link / mention / hashtag / inline code → colored
  url: string;   // tap target ('' = not openable); drives onClick
}

// A block of a message: inline styled text, a pre/code block, or a blockquote.
export interface RichSegment {
  kind: string;    // 'text' | 'pre' | 'quote'
  runs: RichRun[]; // for kind === 'text' | 'quote' (quotes keep their inline links)
  text: string;    // raw text for kind === 'pre' | 'quote'
}

interface Ent {
  offset: number;
  length: number;
  type: string;
  url: string;    // for textEntityTypeTextUrl
  userId: number; // for textEntityTypeMentionName
}

function isBlock(t: string): boolean {
  return t === 'textEntityTypePre' || t === 'textEntityTypePreCode'
    || t === 'textEntityTypeBlockQuote' || t === 'textEntityTypeExpandableBlockQuote';
}

function isLink(t: string): boolean {
  return t === 'textEntityTypeTextUrl' || t === 'textEntityTypeUrl'
    || t === 'textEntityTypeMention' || t === 'textEntityTypeMentionName'
    || t === 'textEntityTypeHashtag' || t === 'textEntityTypeCashtag'
    || t === 'textEntityTypeBotCommand' || t === 'textEntityTypeEmailAddress'
    || t === 'textEntityTypeCode';
}

function readEntities(entities: TdObject[]): Ent[] {
  const out: Ent[] = [];
  for (const e of entities) {
    const t = e['type'] as TdObject | undefined;
    const type = t !== undefined ? ((t['@type'] as string | undefined) ?? '') : '';
    const url = t !== undefined ? ((t['url'] as string | undefined) ?? '') : '';
    const userId = t !== undefined ? ((t['user_id'] as number | undefined) ?? 0) : 0;
    out.push({
      offset: (e['offset'] as number | undefined) ?? 0,
      length: (e['length'] as number | undefined) ?? 0,
      type,
      url,
      userId
    });
  }
  return out;
}

function styleAt(pos: number, ents: Ent[]): RichRun {
  let bold = false;
  let italic = false;
  let link = false;
  for (const e of ents) {
    if (isBlock(e.type)) {
      continue;
    }
    if (pos >= e.offset && pos < e.offset + e.length) {
      if (e.type === 'textEntityTypeBold') {
        bold = true;
      } else if (e.type === 'textEntityTypeItalic') {
        italic = true;
      } else if (isLink(e.type)) {
        link = true;
      }
    }
  }
  return { text: '', bold, italic, link, url: '' };
}

// Resolve the tap target for a run at `pos` whose text is `runText`.
// '' means the run is styled as a link but has no openable target.
function linkTargetFor(pos: number, runText: string, ents: Ent[]): string {
  for (const e of ents) {
    if (isBlock(e.type) || !isLink(e.type)) {
      continue;
    }
    if (pos >= e.offset && pos < e.offset + e.length) {
      if (e.type === 'textEntityTypeTextUrl') {
        return e.url;
      }
      if (e.type === 'textEntityTypeUrl') {
        return runText;
      }
      if (e.type === 'textEntityTypeMention') {
        return `https://t.me/${runText.replace('@', '')}`;
      }
      if (e.type === 'textEntityTypeMentionName') {
        return `tg://user?id=${e.userId}`; // opens the profile card in-app
      }
      if (e.type === 'textEntityTypeEmailAddress') {
        return `mailto:${runText}`;
      }
      // Pseudo-scheme: the chat page turns hashtag taps into an in-chat search.
      if (e.type === 'textEntityTypeHashtag' || e.type === 'textEntityTypeCashtag') {
        return `tg-hashtag:${runText}`;
      }
      return '';
    }
  }
  return '';
}

// Split [start,end) into runs at inline-entity boundaries; style is constant
// within each run.
function buildRuns(text: string, start: number, end: number, ents: Ent[]): RichRun[] {
  const bounds: number[] = [start, end];
  for (const e of ents) {
    if (isBlock(e.type)) {
      continue;
    }
    const s = e.offset;
    const en = e.offset + e.length;
    if (s > start && s < end) {
      bounds.push(s);
    }
    if (en > start && en < end) {
      bounds.push(en);
    }
  }
  bounds.sort((a: number, b: number): number => a - b);
  const uniq: number[] = [];
  for (let k = 0; k < bounds.length; k++) {
    if (k === 0 || bounds[k] !== bounds[k - 1]) {
      uniq.push(bounds[k]);
    }
  }
  const runs: RichRun[] = [];
  for (let k = 0; k < uniq.length - 1; k++) {
    const s = uniq[k];
    const en = uniq[k + 1];
    if (en <= s) {
      continue;
    }
    const run = styleAt(s, ents);
    run.text = text.substring(s, en);
    if (run.link) {
      run.url = linkTargetFor(s, run.text, ents);
    }
    if (run.text.length > 0) {
      runs.push(run);
    }
  }
  return runs;
}

// Parse a TDLib formattedText (text + entities) into renderable segments.
export function parseFormattedText(text: string, entities: TdObject[]): RichSegment[] {
  const ents = readEntities(entities);
  const blocks: Ent[] = [];
  for (const e of ents) {
    if (isBlock(e.type)) {
      blocks.push(e);
    }
  }
  blocks.sort((a: Ent, b: Ent): number => a.offset - b.offset);
  const segments: RichSegment[] = [];
  const n = text.length;
  let cursor = 0;
  for (const b of blocks) {
    const bStart = Math.max(0, b.offset);
    const bEnd = Math.min(n, b.offset + b.length);
    if (bStart > cursor) {
      const runs = buildRuns(text, cursor, bStart, ents);
      if (runs.length > 0) {
        segments.push({ kind: 'text', runs, text: '' });
      }
    }
    const kind = (b.type === 'textEntityTypeBlockQuote' || b.type === 'textEntityTypeExpandableBlockQuote')
      ? 'quote' : 'pre';
    // Quotes keep their inline runs so links/mentions inside stay tappable.
    const quoteRuns = kind === 'quote' ? buildRuns(text, bStart, bEnd, ents) : [];
    segments.push({ kind, runs: quoteRuns, text: text.substring(bStart, bEnd) });
    cursor = bEnd;
  }
  if (cursor < n) {
    const runs = buildRuns(text, cursor, n, ents);
    if (runs.length > 0) {
      segments.push({ kind: 'text', runs, text: '' });
    }
  }
  if (segments.length === 0 && n > 0) {
    segments.push({ kind: 'text', runs: [{ text, bold: false, italic: false, link: false, url: '' }], text: '' });
  }
  return segments;
}
