import { TdObject } from '../tdkit/TdTypes';

function captionText(content: TdObject): string {
  const cap = content['caption'] as TdObject | undefined;
  if (cap === undefined) {
    return '';
  }
  const t = cap['text'] as string | undefined;
  return t ?? '';
}

function mediaLabel(icon: string, word: string, content: TdObject): string {
  const cap = captionText(content);
  return cap !== '' ? `${icon} ${cap}` : `${icon} ${word}`;
}

export function formatPreview(message: TdObject | null): string {
  if (message === null) {
    return '';
  }
  const rawContent = message['content'];
  if (rawContent === undefined || rawContent === null) {
    return '';
  }
  const content = rawContent as TdObject;
  const type = content['@type'] as string;
  if (type === 'messageText') {
    const text = content['text'] as TdObject | undefined;
    if (text === undefined) {
      return '';
    }
    const inner = text['text'] as string | undefined;
    return inner ?? '';
  }
  if (type === 'messagePhoto') {
    return mediaLabel('📷', 'Photo', content);
  }
  if (type === 'messageVideo') {
    return mediaLabel('📹', 'Video', content);
  }
  if (type === 'messageVoiceNote') {
    return '🎤 Voice message';
  }
  if (type === 'messageDocument') {
    return mediaLabel('📎', 'File', content);
  }
  if (type === 'messageSticker') {
    const st = content['sticker'] as TdObject | undefined;
    const emoji = st !== undefined ? (st['emoji'] as string) : '';
    return emoji !== '' && emoji !== undefined ? `${emoji} Sticker` : 'Sticker';
  }
  if (type === 'messageAnimation') {
    return 'GIF';
  }
  if (type === 'messageAudio') {
    return '🎵 Audio';
  }
  if (type === 'messageLocation') {
    return '📍 Location';
  }
  return 'Message';
}
