// Formats a message auto-delete duration (seconds) into a compact avatar badge
// label like "30s", "15m", "3h", "2d", "1w". Returns '' when disabled (<= 0).
export function formatTTL(seconds: number): string {
  if (seconds <= 0) {
    return '';
  }
  if (seconds < 60) {
    return `${seconds}s`;
  }
  if (seconds < 3600) {
    return `${Math.round(seconds / 60)}m`;
  }
  if (seconds < 86400) {
    return `${Math.round(seconds / 3600)}h`;
  }
  if (seconds < 604800) {
    return `${Math.round(seconds / 86400)}d`;
  }
  return `${Math.round(seconds / 604800)}w`;
}
