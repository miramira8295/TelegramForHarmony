import { describe, it, expect } from '@ohos/hypium';
import { formatPreview } from '../main/ets/util/formatPreview';
import { TdObject } from '../main/ets/tdkit/TdTypes';

function msg(content: TdObject): TdObject {
  const m: TdObject = { '@type': 'message' };
  m['content'] = content;
  return m;
}

export default function formatPreviewTest() {
  describe('formatPreview', () => {
    it('null_message_empty', 0, () => {
      expect(formatPreview(null)).assertEqual('');
    });
    it('text', 0, () => {
      const text: TdObject = { '@type': 'formattedText' };
      text['text'] = 'hello world';
      const c: TdObject = { '@type': 'messageText' };
      c['text'] = text;
      expect(formatPreview(msg(c))).assertEqual('hello world');
    });
    it('photo_no_caption', 0, () => {
      const cap: TdObject = { '@type': 'formattedText' };
      cap['text'] = '';
      const c: TdObject = { '@type': 'messagePhoto' };
      c['caption'] = cap;
      expect(formatPreview(msg(c))).assertEqual('📷 Photo');
    });
    it('photo_with_caption', 0, () => {
      const cap: TdObject = { '@type': 'formattedText' };
      cap['text'] = 'beach';
      const c: TdObject = { '@type': 'messagePhoto' };
      c['caption'] = cap;
      expect(formatPreview(msg(c))).assertEqual('📷 beach');
    });
    it('sticker_with_emoji', 0, () => {
      const st: TdObject = { '@type': 'sticker' };
      st['emoji'] = '🎉';
      const c: TdObject = { '@type': 'messageSticker' };
      c['sticker'] = st;
      expect(formatPreview(msg(c))).assertEqual('🎉 Sticker');
    });
    it('voice', 0, () => {
      const c: TdObject = { '@type': 'messageVoiceNote' };
      expect(formatPreview(msg(c))).assertEqual('🎤 Voice message');
    });
    it('unknown_fallback', 0, () => {
      const c: TdObject = { '@type': 'messagePoll' };
      expect(formatPreview(msg(c))).assertEqual('Message');
    });
    it('video_no_caption', 0, () => {
      const c: TdObject = { '@type': 'messageVideo' };
      expect(formatPreview(msg(c))).assertEqual('📹 Video');
    });
    it('video_with_caption', 0, () => {
      const cap: TdObject = { '@type': 'formattedText' }; cap['text'] = 'trip';
      const c: TdObject = { '@type': 'messageVideo' }; c['caption'] = cap;
      expect(formatPreview(msg(c))).assertEqual('📹 trip');
    });
    it('document', 0, () => {
      const c: TdObject = { '@type': 'messageDocument' };
      expect(formatPreview(msg(c))).assertEqual('📎 File');
    });
    it('animation', 0, () => {
      const c: TdObject = { '@type': 'messageAnimation' };
      expect(formatPreview(msg(c))).assertEqual('GIF');
    });
    it('audio', 0, () => {
      const c: TdObject = { '@type': 'messageAudio' };
      expect(formatPreview(msg(c))).assertEqual('🎵 Audio');
    });
    it('location', 0, () => {
      const c: TdObject = { '@type': 'messageLocation' };
      expect(formatPreview(msg(c))).assertEqual('📍 Location');
    });
    it('sticker_no_emoji', 0, () => {
      const st: TdObject = { '@type': 'sticker' }; st['emoji'] = '';
      const c: TdObject = { '@type': 'messageSticker' }; c['sticker'] = st;
      expect(formatPreview(msg(c))).assertEqual('Sticker');
    });
    it('text_missing_inner', 0, () => {
      const inner: TdObject = { '@type': 'formattedText' };
      const c: TdObject = { '@type': 'messageText' }; c['text'] = inner;
      expect(formatPreview(msg(c))).assertEqual('');
    });
    it('null_content_no_crash', 0, () => {
      const m = JSON.parse('{"@type":"message","content":null}') as TdObject;
      expect(formatPreview(m)).assertEqual('');
    });
  });
}
