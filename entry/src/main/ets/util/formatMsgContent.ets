import { TdObject } from '../tdkit/TdTypes';
import { formatPreview } from './formatPreview';

export interface MsgContent {
  contentType: string;
  text: string;
  photoFileId: number;
  photoWidth: number;
  photoHeight: number;
  placeholderLabel: string;
  entities: TdObject[];
  linkSiteName: string;
  linkTitle: string;
  linkDescription: string;
  linkDescriptionEntities: TdObject[];
  linkPhotoFileId: number;
  linkUrl: string;
  videoDuration: number; // seconds, 0 for non-video content
  videoFileId: number;   // full-resolution video file id, 0 for non-video content
  videoFileSize: number; // bytes, 0 when unknown/non-video
  videoMimeType: string; // e.g. video/mp4, video/webm
  videoFileName: string; // original file name, '' when unknown/non-video
  photoFullFileId: number; // full-resolution photo file id, 0 when no upgrade exists
  isAnimation?: boolean;   // Telegram GIF/messageAnimation, not a normal video
  stickerFileId?: number;  // animated sticker source file (TGS), 0/absent otherwise
  customEmojiId?: string;  // single custom-emoji text message (resolved async)
  stickerFormat?: string;  // 'webp' | 'tgs' | 'webm', absent for non-stickers
}

interface PhotoSize {
  fileId: number;
  width: number;
  height: number;
}

// Types whose LinkPreviewType variant carries a `photo` field (see td_api.tl).
const LINK_PREVIEW_PHOTO_TYPES: string[] = ['linkPreviewTypeArticle', 'linkPreviewTypePhoto', 'linkPreviewTypeApp', 'linkPreviewTypeWebApp'];

interface LinkPreviewInfo {
  siteName: string;
  title: string;
  description: string;
  descriptionEntities: TdObject[];
  photoFileId: number;
  url: string;
}

const EMPTY_LINK_PREVIEW: LinkPreviewInfo = { siteName: '', title: '', description: '', descriptionEntities: [], photoFileId: 0, url: '' };

// A URL/message-link preview attached to a text message (TDLib messageText.link_preview).
function parseLinkPreview(content: TdObject): LinkPreviewInfo {
  const lp = content['link_preview'] as TdObject | undefined;
  if (lp === undefined) {
    return EMPTY_LINK_PREVIEW;
  }
  const descFt = lp['description'] as TdObject | undefined;
  const lpType = lp['type'] as TdObject | undefined;
  const typeName = lpType !== undefined ? ((lpType['@type'] as string | undefined) ?? '') : '';
  let photoFileId = 0;
  if (lpType !== undefined && LINK_PREVIEW_PHOTO_TYPES.indexOf(typeName) >= 0) {
    photoFileId = largestPhotoSize(lpType['photo'] as TdObject | undefined).fileId;
  }
  return {
    siteName: (lp['site_name'] as string | undefined) ?? '',
    title: (lp['title'] as string | undefined) ?? '',
    description: descFt !== undefined ? ((descFt['text'] as string | undefined) ?? '') : '',
    descriptionEntities: textEntities(descFt),
    photoFileId,
    url: (lp['url'] as string | undefined) ?? ''
  };
}

function textEntities(ft: TdObject | undefined): TdObject[] {
  if (ft === undefined) {
    return [];
  }
  return (ft['entities'] as TdObject[] | undefined) ?? [];
}

function largestPhotoSize(photo: TdObject | undefined): PhotoSize {
  if (photo === undefined) {
    return { fileId: 0, width: 0, height: 0 };
  }
  const sizes = photo['sizes'] as TdObject[] | undefined;
  if (sizes === undefined || sizes.length === 0) {
    return { fileId: 0, width: 0, height: 0 };
  }
  const last = sizes[sizes.length - 1];
  const file = last['photo'] as TdObject | undefined;
  return {
    fileId: file !== undefined ? ((file['id'] as number | undefined) ?? 0) : 0,
    width: (last['width'] as number | undefined) ?? 0,
    height: (last['height'] as number | undefined) ?? 0
  };
}

// A smaller size for inline bubble display (fast to download); the largest
// size is downloaded separately, on demand, when the viewer is opened.
function inlinePhotoSize(photo: TdObject | undefined): PhotoSize {
  if (photo === undefined) {
    return { fileId: 0, width: 0, height: 0 };
  }
  const sizes = photo['sizes'] as TdObject[] | undefined;
  if (sizes === undefined || sizes.length === 0) {
    return { fileId: 0, width: 0, height: 0 };
  }
  const idx = Math.min(1, sizes.length - 1);
  const s = sizes[idx];
  const file = s['photo'] as TdObject | undefined;
  return {
    fileId: file !== undefined ? ((file['id'] as number | undefined) ?? 0) : 0,
    width: (s['width'] as number | undefined) ?? 0,
    height: (s['height'] as number | undefined) ?? 0
  };
}

// Caption of a media message (photo/video/etc.) — the text shown below the media.
function captionText(content: TdObject): string {
  const cap = content['caption'] as TdObject | undefined;
  if (cap === undefined) {
    return '';
  }
  return (cap['text'] as string | undefined) ?? '';
}

// A video's thumbnail image, used as its "photo" for grid/album/single display
// (actual playback is out of scope — the thumbnail + a play overlay stands in).
function videoThumbnail(video: TdObject | undefined): PhotoSize {
  if (video === undefined) {
    return { fileId: 0, width: 0, height: 0 };
  }
  const thumb = video['thumbnail'] as TdObject | undefined;
  if (thumb === undefined) {
    return { fileId: 0, width: (video['width'] as number | undefined) ?? 0, height: (video['height'] as number | undefined) ?? 0 };
  }
  const file = thumb['file'] as TdObject | undefined;
  return {
    fileId: file !== undefined ? ((file['id'] as number | undefined) ?? 0) : 0,
    width: (thumb['width'] as number | undefined) ?? 0,
    height: (thumb['height'] as number | undefined) ?? 0
  };
}

export function formatMsgContent(message: TdObject): MsgContent {
  const content = message['content'] as TdObject | undefined;
  const type = content !== undefined ? (content['@type'] as string | undefined) : undefined;
  if (type === 'messageText') {
    const ft = content!['text'] as TdObject | undefined;
    const text = ft !== undefined ? ((ft['text'] as string | undefined) ?? '') : '';
    const lp: LinkPreviewInfo = parseLinkPreview(content!);
    // A message that is exactly one custom emoji renders as an animated
    // sticker (like the official client), not as its fallback character.
    const ents = textEntities(ft);
    if (ents.length === 1) {
      const et = ents[0]['type'] as TdObject | undefined;
      const etName = et !== undefined ? ((et['@type'] as string | undefined) ?? '') : '';
      const off = (ents[0]['offset'] as number | undefined) ?? -1;
      const len = (ents[0]['length'] as number | undefined) ?? 0;
      if (etName === 'textEntityTypeCustomEmoji') {
        console.info(`formatMsgContent customEmoji cand: off=${off} len=${len} textLen=${text.length}`);
      }
      if (etName === 'textEntityTypeCustomEmoji' && off === 0 && len >= text.length - 1 && len <= text.length) {
        return {
          contentType: 'customEmoji', text, photoFileId: 0, photoWidth: 0, photoHeight: 0,
          placeholderLabel: '', entities: [],
          customEmojiId: `${(et as TdObject)['custom_emoji_id']}`,
          linkSiteName: '', linkTitle: '', linkDescription: '', linkDescriptionEntities: [],
          linkPhotoFileId: 0, linkUrl: '',
          videoDuration: 0, videoFileId: 0, videoFileSize: 0, videoMimeType: '', videoFileName: '', photoFullFileId: 0
        };
      }
    }
    return {
      contentType: 'text', text, photoFileId: 0, photoWidth: 0, photoHeight: 0, placeholderLabel: '', entities: textEntities(ft),
      linkSiteName: lp.siteName, linkTitle: lp.title, linkDescription: lp.description,
      linkDescriptionEntities: lp.descriptionEntities, linkPhotoFileId: lp.photoFileId, linkUrl: lp.url,
      videoDuration: 0, videoFileId: 0, videoFileSize: 0, videoMimeType: '', videoFileName: '', photoFullFileId: 0
    };
  }
  if (type === 'messagePhoto') {
    const photo = content!['photo'] as TdObject | undefined;
    const size: PhotoSize = inlinePhotoSize(photo);
    const full: PhotoSize = largestPhotoSize(photo);
    return {
      contentType: 'photo',
      text: captionText(content!),
      photoFileId: size.fileId,
      photoWidth: size.width,
      photoHeight: size.height,
      placeholderLabel: '',
      entities: textEntities(content!['caption'] as TdObject | undefined),
      linkSiteName: '', linkTitle: '', linkDescription: '', linkDescriptionEntities: [], linkPhotoFileId: 0, linkUrl: '',
      videoDuration: 0, videoFileId: 0, videoFileSize: 0, videoMimeType: '', videoFileName: '', photoFullFileId: full.fileId !== size.fileId ? full.fileId : 0
    };
  }
  if (type === 'messageVideo') {
    const video = content!['video'] as TdObject | undefined;
    const size: PhotoSize = videoThumbnail(video);
    const videoFile = video !== undefined ? (video['video'] as TdObject | undefined) : undefined;
    const videoSize = videoFile !== undefined ? (((videoFile['size'] as number | undefined) ?? 0) || ((videoFile['expected_size'] as number | undefined) ?? 0)) : 0;
    return {
      contentType: 'video',
      text: captionText(content!),
      photoFileId: size.fileId,
      photoWidth: size.width,
      photoHeight: size.height,
      placeholderLabel: '',
      entities: textEntities(content!['caption'] as TdObject | undefined),
      linkSiteName: '', linkTitle: '', linkDescription: '', linkDescriptionEntities: [], linkPhotoFileId: 0, linkUrl: '',
      videoDuration: video !== undefined ? ((video['duration'] as number | undefined) ?? 0) : 0,
      videoFileId: videoFile !== undefined ? ((videoFile['id'] as number | undefined) ?? 0) : 0,
      videoFileSize: videoSize,
      videoMimeType: video !== undefined ? ((video['mime_type'] as string | undefined) ?? '') : '',
      videoFileName: video !== undefined ? ((video['file_name'] as string | undefined) ?? '') : '',
      photoFullFileId: 0
    };
  }
  // GIFs (messageAnimation) are MP4 loops — render through the video pipeline
  // (thumbnail + tap to play fullscreen).
  if (type === 'messageAnimation') {
    const anim = content!['animation'] as TdObject | undefined;
    const size: PhotoSize = videoThumbnail(anim);
    const animFile = anim !== undefined ? (anim['animation'] as TdObject | undefined) : undefined;
    const animSize = animFile !== undefined
      ? (((animFile['size'] as number | undefined) ?? 0) || ((animFile['expected_size'] as number | undefined) ?? 0)) : 0;
    return {
      contentType: 'video',
      isAnimation: true,
      text: captionText(content!),
      photoFileId: size.fileId,
      photoWidth: size.width,
      photoHeight: size.height,
      placeholderLabel: '',
      entities: textEntities(content!['caption'] as TdObject | undefined),
      linkSiteName: '', linkTitle: '', linkDescription: '', linkDescriptionEntities: [], linkPhotoFileId: 0, linkUrl: '',
      videoDuration: anim !== undefined ? ((anim['duration'] as number | undefined) ?? 0) : 0,
      videoFileId: animFile !== undefined ? ((animFile['id'] as number | undefined) ?? 0) : 0,
      videoFileSize: animSize,
      videoMimeType: anim !== undefined ? ((anim['mime_type'] as string | undefined) ?? '') : '',
      videoFileName: anim !== undefined ? ((anim['file_name'] as string | undefined) ?? '') : '',
      photoFullFileId: 0
    };
  }
  // Voice notes also reuse the video* slots (duration / file id / size / mime
  // / local path once downloaded).
  if (type === 'messageVoiceNote') {
    const vn = content!['voice_note'] as TdObject | undefined;
    const voiceFile = vn !== undefined ? (vn['voice'] as TdObject | undefined) : undefined;
    const voiceSize = voiceFile !== undefined
      ? (((voiceFile['size'] as number | undefined) ?? 0) || ((voiceFile['expected_size'] as number | undefined) ?? 0)) : 0;
    return {
      contentType: 'voice',
      text: captionText(content!),
      photoFileId: 0, photoWidth: 0, photoHeight: 0,
      placeholderLabel: '',
      entities: textEntities(content!['caption'] as TdObject | undefined),
      linkSiteName: '', linkTitle: '', linkDescription: '', linkDescriptionEntities: [], linkPhotoFileId: 0, linkUrl: '',
      videoDuration: vn !== undefined ? ((vn['duration'] as number | undefined) ?? 0) : 0,
      videoFileId: voiceFile !== undefined ? ((voiceFile['id'] as number | undefined) ?? 0) : 0,
      videoFileSize: voiceSize,
      videoMimeType: vn !== undefined ? ((vn['mime_type'] as string | undefined) ?? '') : '',
      videoFileName: '',
      photoFullFileId: 0
    };
  }
  // Documents reuse the video* slots (same semantics: a named, sized,
  // downloadable file with progress + local path once fetched).
  if (type === 'messageDocument') {
    const doc = content!['document'] as TdObject | undefined;
    const docFile = doc !== undefined ? (doc['document'] as TdObject | undefined) : undefined;
    const docSize = docFile !== undefined
      ? (((docFile['size'] as number | undefined) ?? 0) || ((docFile['expected_size'] as number | undefined) ?? 0)) : 0;
    return {
      contentType: 'file',
      text: captionText(content!),
      photoFileId: 0, photoWidth: 0, photoHeight: 0,
      placeholderLabel: '',
      entities: textEntities(content!['caption'] as TdObject | undefined),
      linkSiteName: '', linkTitle: '', linkDescription: '', linkDescriptionEntities: [], linkPhotoFileId: 0, linkUrl: '',
      videoDuration: 0,
      videoFileId: docFile !== undefined ? ((docFile['id'] as number | undefined) ?? 0) : 0,
      videoFileSize: docSize,
      videoMimeType: doc !== undefined ? ((doc['mime_type'] as string | undefined) ?? '') : '',
      videoFileName: doc !== undefined ? ((doc['file_name'] as string | undefined) ?? '') : '',
      photoFullFileId: 0
    };
  }
  if (type === 'messageSticker') {
    const parsed = stickerMsgContent(content!['sticker'] as TdObject | undefined);
    if (parsed !== null) {
      return parsed;
    }
  }
  // Single-emoji messages arrive as messageAnimatedEmoji; TDLib pre-resolves
  // the sticker (standard AND premium custom emoji) into animated_emoji.sticker.
  if (type === 'messageAnimatedEmoji') {
    const ae = content!['animated_emoji'] as TdObject | undefined;
    const parsed = stickerMsgContent(ae !== undefined ? (ae['sticker'] as TdObject | undefined) : undefined);
    if (parsed !== null) {
      return parsed;
    }
    const emoji = (content!['emoji'] as string | undefined) ?? '';
    if (emoji !== '') {
      return {
        contentType: 'emoji', text: emoji, photoFileId: 0, photoWidth: 0, photoHeight: 0, placeholderLabel: '', entities: [],
        linkSiteName: '', linkTitle: '', linkDescription: '', linkDescriptionEntities: [], linkPhotoFileId: 0, linkUrl: '',
        videoDuration: 0, videoFileId: 0, videoFileSize: 0, videoMimeType: '', videoFileName: '', photoFullFileId: 0
      };
    }
  }
  if (type === '__never__') {
    // (folded into stickerMsgContent below)
  }
  // Diagnostics for the "bare 'Message' bubble" reports — identifies which
  // TDLib content type still lacks a renderer.
  console.info(`formatMsgContent: unhandled content type ${type ?? 'undefined'} (msg ${message['id']})`);
  return {
    contentType: 'other', text: '', photoFileId: 0, photoWidth: 0, photoHeight: 0, placeholderLabel: formatPreview(message), entities: [],
    linkSiteName: '', linkTitle: '', linkDescription: '', linkDescriptionEntities: [], linkPhotoFileId: 0, linkUrl: '',
    videoDuration: 0, videoFileId: 0, videoFileSize: 0, videoMimeType: '', videoFileName: '', photoFullFileId: 0
  };
}

// Shared sticker → MsgContent parser (messageSticker and animated-emoji
// stickers): WEBP renders directly, TGS/WEBM animate from the source file
// with the raster thumbnail as placeholder. null when nothing is renderable.
function stickerMsgContent(sticker: TdObject | undefined): MsgContent | null {
  {
    const format = sticker !== undefined ? (sticker['format'] as TdObject | undefined) : undefined;
    const formatName = format !== undefined ? ((format['@type'] as string | undefined) ?? '') : '';
    // Keep Telegram's Unicode alternative even when an animated sticker file
    // is available. Embedded consumers (for example the livestream overlay)
    // can show this immediately without having to host another media player.
    const fallbackEmoji = sticker !== undefined ? ((sticker['emoji'] as string | undefined) ?? '') : '';
    const stickerFile = sticker !== undefined ? (sticker['sticker'] as TdObject | undefined) : undefined;
    const thumb = sticker !== undefined ? (sticker['thumbnail'] as TdObject | undefined) : undefined;
    // Only raster thumbnails are Image-decodable — a thumbnail can itself be
    // TGS/WEBM (ExtDecoder "Failed to match desc" otherwise).
    const thumbFormat = thumb !== undefined ? (thumb['format'] as TdObject | undefined) : undefined;
    const thumbFormatName = thumbFormat !== undefined ? ((thumbFormat['@type'] as string | undefined) ?? '') : '';
    const thumbIsRaster = thumbFormatName === 'thumbnailFormatWebp' || thumbFormatName === 'thumbnailFormatJpeg'
      || thumbFormatName === 'thumbnailFormatPng' || thumbFormatName === 'thumbnailFormatGif';
    const thumbFile = thumb !== undefined && thumbIsRaster ? (thumb['file'] as TdObject | undefined) : undefined;
    // Static WEBP renders directly. TGS (Lottie) and WEBM (looping ijkplayer)
    // animate once the source file downloads — the raster thumbnail is the
    // placeholder until then.
    const stickerFileId = stickerFile !== undefined ? ((stickerFile['id'] as number | undefined) ?? 0) : 0;
    const thumbFileId = thumbFile !== undefined ? ((thumbFile['id'] as number | undefined) ?? 0) : 0;
    const isWebp = formatName === 'stickerFormatWebp';
    const fileId = isWebp ? stickerFileId : thumbFileId;
    if (fileId !== 0 || (!isWebp && stickerFileId !== 0)) {
      return {
        contentType: 'sticker', text: fallbackEmoji,
        photoFileId: fileId,
        photoWidth: sticker !== undefined ? ((sticker['width'] as number | undefined) ?? 0) : 0,
        photoHeight: sticker !== undefined ? ((sticker['height'] as number | undefined) ?? 0) : 0,
        placeholderLabel: '', entities: [],
        linkSiteName: '', linkTitle: '', linkDescription: '', linkDescriptionEntities: [], linkPhotoFileId: 0, linkUrl: '',
        videoDuration: 0, videoFileId: 0, videoFileSize: 0, videoMimeType: '', videoFileName: '', photoFullFileId: 0,
        stickerFileId: isWebp ? 0 : stickerFileId, // TGS and WEBM both need the source file

        stickerFormat: isWebp ? 'webp' : (formatName === 'stickerFormatTgs' ? 'tgs' : 'webm')
      };
    }
    // No renderable file at all → the sticker's emoji, big and bare.
    if (fallbackEmoji !== '') {
      return {
        contentType: 'emoji', text: fallbackEmoji, photoFileId: 0, photoWidth: 0, photoHeight: 0, placeholderLabel: '', entities: [],
        linkSiteName: '', linkTitle: '', linkDescription: '', linkDescriptionEntities: [], linkPhotoFileId: 0, linkUrl: '',
        videoDuration: 0, videoFileId: 0, videoFileSize: 0, videoMimeType: '', videoFileName: '', photoFullFileId: 0
      };
    }
    return null;
  }
}
