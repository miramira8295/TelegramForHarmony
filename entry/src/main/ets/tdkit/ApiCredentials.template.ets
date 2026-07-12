// Copy this file to ApiCredentials.ets (same directory), then generate the packed
// values from your own credentials obtained at https://my.telegram.org/apps :
//
//   node scripts/gen-creds.mjs <api_id> <api_hash>
//
// Paste the three constants it prints below. The real ApiCredentials.ets is
// gitignored — never commit it. Values are obfuscated (not encrypted), which
// only raises the bar against casual extraction from the packaged app.
import { decodeEnv, RuntimeEnv } from './credCodec';

const _n: number = 0;
const _r: number = 0;
const _s: string = '';

const _env: RuntimeEnv = decodeEnv(_n, _r, _s);
export const clientRev: number = _env.id;
export const clientSig: string = _env.token;
