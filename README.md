# TelegramForHarmony

An open-source, unofficial **Telegram client for HarmonyOS NEXT**, built with
ArkTS/ArkUI on top of [TDLib](https://core.telegram.org/tdlib) (Telegram's
official client library) through a native N-API bridge.

## Features

- Phone number + code + 2FA password login
- Chat list with folders, archive, unread badges and live updates
- Full chat view: text with entities (links, mentions, code, quotes), photos
  (progressive low-res → full-res), photo/video albums (masonry layout),
  streaming video playback with full player controls, stickers (static WEBP,
  animated TGS via Lottie, WEBM video stickers), animated emoji, documents
  (download / open / save), link previews, replies with jump-to-original,
  forwards, reactions, channel comments, bot inline keyboards, pinned
  messages, date separators, unread boundary positioning
- Sending: text, `@` mention / `/` bot-command autocomplete, file attachments
- Fullscreen media viewer: hero open/close transitions, swipe between media,
  filmstrip, save to gallery
- Profiles: user/bot detail page (bio, usernames, business info, stories,
  gifts with Stars-based gift sending, groups in common), group/channel
  detail page (description, link, member list)

## Project layout

```
AppScope/            app-level config (bundle name, icon)
entry/src/main/ets/
  tdkit/             TDLib N-API bridge, client, auth service
  store/             immutable stores + subscription (chats, messages, profiles)
  pages/             ArkUI pages (login, chat list, chat, profiles)
  services/          video byte-range streaming over TDLib partial downloads
  util/              parsing/formatting helpers (rich text, albums, dates, ...)
entry/src/main/cpp/  native bridge (libentry.so → libtdjson.so)
entry/src/test/      unit tests (run via scripts/run-local-tests.sh)
scripts/             TDLib fetch/build scripts, local test gate
```

## Building

### Prerequisites

- **DevEco Studio 6.0+** (project targets `compatibleSdkVersion 6.0.0(20)`,
  `targetSdkVersion 6.1.1(24)`), with its bundled OpenHarmony SDK/NDK.
- `curl` and `file` (ship with macOS/Linux).

### 1. Get `libtdjson.so`

The app bundles TDLib as a prebuilt native library at
`entry/libs/arm64-v8a/libtdjson.so` (~32 MB, not committed). Pick one path:

**Path A — fetch a prebuilt binary (recommended):**

```bash
bash scripts/fetch-tdlib.sh [tag]   # downloads from this repo's GitHub Releases
```

Until a release with this asset is published, the script fails with a 404 on
purpose and points you to Path B.

**Path B — build from source (~10-15 min on a modern Mac):**

```bash
# C++ toolchain + deps: clang (Xcode CLT), cmake, ninja, gperf, patchelf
export OHOS_NDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony
bash scripts/build-tdlib.sh
```

This wraps [`ErBWs/tdlib-ohos-build`](https://github.com/ErBWs/tdlib-ohos-build)
end to end: cross-compiles OpenSSL (static) and TDLib (release **1.8.54**,
OpenSSL `1_1_1w`) for arm64-v8a with the DevEco NDK, pre-generates TDLib's
TL-schema sources on the host (mandatory when cross-compiling), normalizes
the SONAME to plain `libtdjson.so` with `patchelf` (without this the native
bridge fails to load **silently**), and copies the result into
`entry/libs/arm64-v8a/`. The script also applies several macOS compatibility
fixes to the upstream build scripts and is idempotent — safe to re-run.

### 2. Telegram API credentials

TDLib needs your own `api_id`/`api_hash` — this repo does not ship any.

1. Register an application at <https://my.telegram.org/apps>.
2. Copy `entry/src/main/ets/tdkit/ApiCredentials.template.ets` to
   `ApiCredentials.ets` (same directory) and fill in your values:

   ```ts
   export const API_ID: number = 123456;
   export const API_HASH: string = 'your_api_hash';
   ```

`ApiCredentials.ets` is gitignored — never commit real credentials, and
rotate them if they are ever exposed.

### 3. Signing

`build-profile.json5` ships with empty `signingConfigs`. Open the project in
DevEco Studio and use **File > Project Structure > Signing Configs >
Support HarmonyOS Auto-Sign** (Huawei Developer account) to generate a debug
certificate locally. No signing material needs to be committed or shared.

### 4. Build & run

Open in DevEco Studio and run on a HarmonyOS NEXT device/emulator, or from
the command line:

```bash
hvigorw --mode module -p module=entry@default -p product=default assembleHap
```

Run the unit test gate:

```bash
./scripts/run-local-tests.sh    # must print "LOCAL TESTS: PASS"
```

## Status & disclaimers

- Work in progress; UI aims to closely match the official Android client.
- This is an **unofficial** client. Use your own API credentials and follow
  the [Telegram API Terms of Service](https://core.telegram.org/api/terms).

## License

[Apache License 2.0](LICENSE)
