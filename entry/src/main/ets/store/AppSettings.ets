import { preferences } from '@kit.ArkData';
import { common, ConfigurationConstant } from '@kit.AbilityKit';

// User settings that outlive the process. Each one is mirrored into AppStorage
// so any component can bind it with @StorageProp and re-render on change, while
// Preferences keeps the value across restarts.
//
// Only settings the app actually honours live here — a switch that changes
// nothing is worse than no switch at all.

const STORE_NAME: string = 'app_settings';

// AppStorage keys (also the Preferences keys — one name per setting).
export const KEY_TEXT_SIZE: string = 'msgTextSize';        // message font size, vp
export const KEY_BUBBLE_RADIUS: string = 'bubbleRadius';   // message corner radius, vp
export const KEY_THREE_LINES: string = 'chatListThreeLines'; // chat list row shows 2 or 3 lines
export const KEY_NIGHT_MODE: string = 'nightMode';         // 'system' | 'dark' | 'light'
export const KEY_REDUCE_ANIM: string = 'reduceAnimations'; // stop autoplaying animated stickers
export const KEY_SEND_BY_ENTER: string = 'sendByEnter';    // Enter sends instead of newline

export const TEXT_SIZE_MIN: number = 12;
export const TEXT_SIZE_MAX: number = 24;
export const TEXT_SIZE_DEFAULT: number = 16;
export const RADIUS_MIN: number = 0;
export const RADIUS_MAX: number = 20;
export const RADIUS_DEFAULT: number = 17;

export const NIGHT_SYSTEM: string = 'system';
export const NIGHT_DARK: string = 'dark';
export const NIGHT_LIGHT: string = 'light';

let store: preferences.Preferences | null = null;
let appContext: common.Context | null = null;

function colorModeOf(nightMode: string): ConfigurationConstant.ColorMode {
  if (nightMode === NIGHT_DARK) {
    return ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
  }
  if (nightMode === NIGHT_LIGHT) {
    return ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  }
  return ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET; // follow the system
}

// Push the stored night mode to the app — NOT_SET means "follow the system".
export function applyNightMode(nightMode: string): void {
  if (appContext === null) {
    return;
  }
  try {
    (appContext as common.Context).getApplicationContext().setColorMode(colorModeOf(nightMode));
  } catch (e) {
    console.error(`AppSettings.applyNightMode failed: ${e}`);
  }
}

// Load everything into AppStorage. Call once at startup, before the first page
// renders, so components never flash the default value.
export async function initSettings(context: common.Context): Promise<void> {
  appContext = context;
  try {
    store = await preferences.getPreferences(context, STORE_NAME);
    const s = store as preferences.Preferences;
    AppStorage.setOrCreate(KEY_TEXT_SIZE, await s.get(KEY_TEXT_SIZE, TEXT_SIZE_DEFAULT) as number);
    AppStorage.setOrCreate(KEY_BUBBLE_RADIUS, await s.get(KEY_BUBBLE_RADIUS, RADIUS_DEFAULT) as number);
    AppStorage.setOrCreate(KEY_THREE_LINES, await s.get(KEY_THREE_LINES, false) as boolean);
    AppStorage.setOrCreate(KEY_REDUCE_ANIM, await s.get(KEY_REDUCE_ANIM, false) as boolean);
    AppStorage.setOrCreate(KEY_SEND_BY_ENTER, await s.get(KEY_SEND_BY_ENTER, false) as boolean);
    const night = await s.get(KEY_NIGHT_MODE, NIGHT_SYSTEM) as string;
    AppStorage.setOrCreate(KEY_NIGHT_MODE, night);
    applyNightMode(night);
  } catch (e) {
    console.error(`AppSettings.initSettings failed: ${e}`);
    // Defaults still populate AppStorage so the UI works without persistence.
    AppStorage.setOrCreate(KEY_TEXT_SIZE, TEXT_SIZE_DEFAULT);
    AppStorage.setOrCreate(KEY_BUBBLE_RADIUS, RADIUS_DEFAULT);
    AppStorage.setOrCreate(KEY_THREE_LINES, false);
    AppStorage.setOrCreate(KEY_NIGHT_MODE, NIGHT_SYSTEM);
    AppStorage.setOrCreate(KEY_REDUCE_ANIM, false);
    AppStorage.setOrCreate(KEY_SEND_BY_ENTER, false);
  }
}

// Write-through: AppStorage first (instant UI), Preferences after (durable).
function persist(key: string, value: preferences.ValueType): void {
  if (store === null) {
    return;
  }
  const s = store as preferences.Preferences;
  s.put(key, value).then(() => s.flush()).catch((e: Object) => {
    console.error(`AppSettings.persist(${key}) failed: ${JSON.stringify(e)}`);
  });
}

export function setNumber(key: string, value: number): void {
  AppStorage.setOrCreate(key, value);
  persist(key, value);
}

export function setBoolean(key: string, value: boolean): void {
  AppStorage.setOrCreate(key, value);
  persist(key, value);
}

export function setNightMode(value: string): void {
  AppStorage.setOrCreate(KEY_NIGHT_MODE, value);
  persist(KEY_NIGHT_MODE, value);
  applyNightMode(value);
}

// Read helpers for non-component code (components use @StorageProp instead).
export function textSize(): number {
  return AppStorage.get<number>(KEY_TEXT_SIZE) ?? TEXT_SIZE_DEFAULT;
}

export function reduceAnimations(): boolean {
  return AppStorage.get<boolean>(KEY_REDUCE_ANIM) ?? false;
}
