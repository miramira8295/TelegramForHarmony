import { TdObject } from '../tdkit/TdTypes';
import { parseFormattedText, RichRun, RichSegment } from './richText';

// Turn text (+ optional TDLib entities) into renderable runs with tappable
// links. With entities, defer to the rich-text parser; plain strings (channel
// descriptions carry no entities) get regex-based URL/@mention detection.
export function linkifyRuns(text: string, entities: TdObject[]): RichRun[] {
  if (text === '') {
    return [];
  }
  if (entities.length > 0) {
    const segments: RichSegment[] = parseFormattedText(text, entities);
    const runs: RichRun[] = [];
    for (const seg of segments) {
      if (seg.kind === 'text') {
        for (const r of seg.runs) {
          runs.push(r);
        }
      } else {
        runs.push({ text: seg.text, bold: false, italic: false, link: false, url: '' });
      }
    }
    return runs;
  }
  return regexLinkify(text);
}

const LINK_RE: RegExp = /(https?:\/\/[^\s]+|t\.me\/[A-Za-z0-9_/+]+|@[A-Za-z0-9_]{3,32})/g;

function regexLinkify(text: string): RichRun[] {
  const runs: RichRun[] = [];
  let last = 0;
  LINK_RE.lastIndex = 0;
  let m = LINK_RE.exec(text);
  while (m !== null) {
    if (m.index > last) {
      runs.push({ text: text.substring(last, m.index), bold: false, italic: false, link: false, url: '' });
    }
    const token = m[0];
    const url = token.startsWith('t.me/') ? `https://${token}` : token;
    runs.push({ text: token, bold: false, italic: false, link: true, url });
    last = m.index + token.length;
    m = LINK_RE.exec(text);
  }
  if (last < text.length) {
    runs.push({ text: text.substring(last), bold: false, italic: false, link: false, url: '' });
  }
  return runs;
}
