// Shared palette and dimensions for the UI. Colors resolve through the
// resource system (resources/base|dark/element/color.json), so the whole app
// follows the system light/dark mode automatically.
export const COLOR_PRIMARY: ResourceColor = $r('app.color.primary');
export const COLOR_TEXT_PRIMARY: ResourceColor = $r('app.color.text_primary');
export const COLOR_TEXT_SECONDARY: ResourceColor = $r('app.color.text_secondary');
export const COLOR_MUTED_BADGE: ResourceColor = $r('app.color.badge_bg');
export const AVATAR_SIZE: number = 56;
export const ROW_PAD_H: number = 14;
export const ROW_PAD_V: number = 8;
// Avatar placeholder palette — identical in both modes (like official clients).
export const AVATAR_PALETTE: string[] = ['#E17076', '#7BC862', '#65AADD', '#EE7AAE', '#6EC9CB', '#EFA92E', '#FAA774', '#A695E7'];
export const COLOR_TAB_SELECTED: ResourceColor = $r('app.color.primary');
export const COLOR_TAB_UNSELECTED: ResourceColor = $r('app.color.text_secondary');
export const COLOR_BADGE_BG: ResourceColor = $r('app.color.badge_bg');
export const COLOR_TAB_PILL_BG: ResourceColor = $r('app.color.tab_pill_bg');
export const COLOR_BUBBLE_OUT: ResourceColor = $r('app.color.bubble_out');
export const COLOR_BUBBLE_IN: ResourceColor = $r('app.color.bubble_in');
export const COLOR_BUBBLE_TEXT: ResourceColor = $r('app.color.bubble_text');
// Frequently used surfaces (cards, headers, inputs) and page backgrounds.
export const COLOR_SURFACE: ResourceColor = $r('app.color.surface');
export const COLOR_PAGE_BG: ResourceColor = $r('app.color.page_bg');
export const COLOR_CHAT_BG: ResourceColor = $r('app.color.chat_bg');
export const COLOR_DIVIDER: ResourceColor = $r('app.color.divider');

// Bot-chosen button colors (TDLib buttonStyle*): dark blue / green / red,
// matching the official clients. Returns `fallback` for the default style.
export function botButtonBg(style: string, fallback: ResourceColor): ResourceColor {
  if (style === 'primary') {
    return $r('app.color.primary');
  }
  if (style === 'success') {
    return '#34C759';
  }
  if (style === 'danger') {
    return '#FF3B30';
  }
  return fallback;
}
