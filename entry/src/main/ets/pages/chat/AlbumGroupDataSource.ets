import { AlbumGroup } from '../../util/collapseAlbums';

// LazyForEach data source for the message list.
//
// Why this exists: List.maintainVisibleContentPosition (keep scroll position
// when older pages are prepended) ONLY works with LazyForEach fine-grained
// notifications — with plain ForEach the list stays index-anchored and jumps
// to the top of every newly prepended page.
//
// update() diffs the old/new group lists by key (common prefix + suffix) and
// emits the minimal notification: ADD for pure prepend/append, CHANGE for
// in-place mutations, DELETE for removals, RELOAD only for complex mixed edits.
export class AlbumGroupDataSource implements IDataSource {
  private groups: AlbumGroup[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number {
    return this.groups.length;
  }

  getData(index: number): AlbumGroup {
    return this.groups[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    this.listeners = this.listeners.filter((l: DataChangeListener) => l !== listener);
  }

  update(next: AlbumGroup[]): void {
    const prev = this.groups;
    this.groups = next;
    const minLen = Math.min(prev.length, next.length);
    let p = 0;
    while (p < minLen && prev[p].key === next[p].key) {
      p++;
    }
    let s = 0;
    while (s < minLen - p && prev[prev.length - 1 - s].key === next[next.length - 1 - s].key) {
      s++;
    }
    const oldMid = prev.length - p - s;
    const newMid = next.length - p - s;
    if (oldMid === 0 && newMid === 0) {
      return; // keys identical — nothing to tell the list
    }
    if (oldMid === newMid) {
      // Same-length middle region: in-place item changes (photo arrived,
      // send state advanced, reactions updated, ...).
      const ops: DataOperation[] = [];
      for (let i = 0; i < oldMid; i++) {
        ops.push({ type: DataOperationType.CHANGE, index: p + i } as DataChangeOperation);
      }
      this.notify(ops);
      return;
    }
    if (oldMid === 0) {
      // Pure insert (prepend when p === 0 — the case scroll position must survive).
      this.notify([{ type: DataOperationType.ADD, index: p, count: newMid } as DataAddOperation]);
      return;
    }
    if (newMid === 0) {
      this.notify([{ type: DataOperationType.DELETE, index: p, count: oldMid } as DataDeleteOperation]);
      return;
    }
    // Insert + in-place changes in one notify. This is the NORMAL page case,
    // not a rare one: prepending an older page always mutates the old first
    // row's key (its date pill moves away / its sender-run flags flip), and
    // appending a same-sender message flips the old last row's avatar flag.
    // Falling back to RELOAD here would rebuild the list and lose the scroll
    // anchor — the "jumps to the top of the loaded page" bug.
    // All op indexes reference the ORIGINAL dataset.
    if (newMid > oldMid) {
      const added = newMid - oldMid;
      // Append case: surviving old rows pair with the FRONT of the new middle.
      let frontAligned = true;
      for (let i = 0; i < oldMid; i++) {
        if (next[p + i].head.id !== prev[p + i].head.id) {
          frontAligned = false;
          break;
        }
      }
      // Prepend case: surviving old rows pair with the BACK of the new middle.
      let backAligned = !frontAligned;
      if (backAligned) {
        for (let i = 0; i < oldMid; i++) {
          if (next[p + added + i].head.id !== prev[p + i].head.id) {
            backAligned = false;
            break;
          }
        }
      }
      if (frontAligned || backAligned) {
        const ops: DataOperation[] = [];
        for (let i = 0; i < oldMid; i++) {
          ops.push({ type: DataOperationType.CHANGE, index: p + i } as DataChangeOperation);
        }
        ops.push({
          type: DataOperationType.ADD,
          index: backAligned ? p : p + oldMid,
          count: added
        } as DataAddOperation);
        this.notify(ops);
        return;
      }
    }
    // Genuinely mixed structural edit (e.g. a loadAround window replacement).
    this.notify([{ type: DataOperationType.RELOAD } as DataReloadOperation]);
  }

  private notify(ops: DataOperation[]): void {
    for (const l of this.listeners) {
      l.onDatasetChange(ops);
    }
  }
}
