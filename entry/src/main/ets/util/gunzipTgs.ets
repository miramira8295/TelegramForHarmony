import { zlib } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';

const CHUNK: number = 256 * 1024;

// Decompress a Telegram .tgs sticker (gzipped Lottie JSON) into the JSON text.
// Returns '' on any failure so callers can fall back to the static thumbnail.
export async function gunzipTgs(tgsPath: string): Promise<string> {
  try {
    const gz = zlib.createGZipSync();
    await gz.gzopen(tgsPath, 'rb');
    const chunks: Uint8Array[] = [];
    let n = 0;
    do {
      const buf = new ArrayBuffer(CHUNK);
      n = await gz.gzread(buf);
      if (n > 0) {
        chunks.push(new Uint8Array(buf, 0, n).slice());
      }
    } while (n === CHUNK);
    await gz.gzclose();
    let total = 0;
    for (const c of chunks) {
      total += c.length;
    }
    const all = new Uint8Array(total);
    let off = 0;
    for (const c of chunks) {
      all.set(c, off);
      off += c.length;
    }
    return util.TextDecoder.create('utf-8').decodeToString(all);
  } catch (e) {
    console.error(`gunzipTgs(${tgsPath}) failed: ${e}`);
    return '';
  }
}
