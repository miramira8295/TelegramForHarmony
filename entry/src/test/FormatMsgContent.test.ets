import { describe, it, expect } from '@ohos/hypium';
import { formatMsgContent } from '../main/ets/util/formatMsgContent';
import { TdObject } from '../main/ets/tdkit/TdTypes';

function textMsg(t: string): TdObject {
  const ft: TdObject = { '@type': 'formattedText' }; ft['text'] = t;
  const c: TdObject = { '@type': 'messageText' }; c['text'] = ft;
  const m: TdObject = { '@type': 'message' }; m['content'] = c;
  return m;
}
function photoMsg(fileId: number): TdObject {
  const file: TdObject = { '@type': 'file' }; file['id'] = fileId;
  const size: TdObject = { '@type': 'photoSize' }; size['photo'] = file;
  const photo: TdObject = { '@type': 'photo' }; photo['sizes'] = [size];
  const c: TdObject = { '@type': 'messagePhoto' }; c['photo'] = photo;
  const m: TdObject = { '@type': 'message' }; m['content'] = c;
  return m;
}
function stickerMsg(): TdObject {
  const c: TdObject = { '@type': 'messageSticker' };
  const m: TdObject = { '@type': 'message' }; m['content'] = c;
  return m;
}

export default function formatMsgContentTest() {
  describe('formatMsgContent', () => {
    it('text', 0, () => {
      const r = formatMsgContent(textMsg('hi'));
      expect(r.contentType).assertEqual('text');
      expect(r.text).assertEqual('hi');
    });
    it('photo', 0, () => {
      const r = formatMsgContent(photoMsg(42));
      expect(r.contentType).assertEqual('photo');
      expect(r.photoFileId).assertEqual(42);
    });
    it('other_has_placeholder', 0, () => {
      const r = formatMsgContent(stickerMsg());
      expect(r.contentType).assertEqual('other');
      expect(r.placeholderLabel.length > 0).assertTrue();
    });
  });
}
