// Date pill between messages when the calendar day changes ("7-6", or
// "2024-12-31" once the year differs from the current one).
export function formatDateSeparator(dateSec: number): string {
  const d = new Date(dateSec * 1000);
  const now = new Date();
  if (d.getFullYear() === now.getFullYear()) {
    return `${d.getMonth() + 1}-${d.getDate()}`;
  }
  return `${d.getFullYear()}-${d.getMonth() + 1}-${d.getDate()}`;
}

export function sameDay(aSec: number, bSec: number): boolean {
  const a = new Date(aSec * 1000);
  const b = new Date(bSec * 1000);
  return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
}
