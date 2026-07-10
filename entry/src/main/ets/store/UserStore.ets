import { TdClient } from '../tdkit/TdClient';
import { TdObject } from '../tdkit/TdTypes';

export class UserStore {
  private names: Map<number, string> = new Map();
  private photos: Map<number, number> = new Map();

  constructor(client: TdClient) {
    client.onUpdate('updateUser', (u: TdObject) => this.onUser(u));
  }

  displayName(userId: number): string {
    return this.names.get(userId) ?? '';
  }

  // Small profile-photo file id for a user (0 if none / not yet known).
  photoFileId(userId: number): number {
    return this.photos.get(userId) ?? 0;
  }

  private onUser(update: TdObject): void {
    const user = update['user'] as TdObject | undefined;
    if (user === undefined) {
      return;
    }
    const id = user['id'] as number | undefined;
    if (id === undefined) {
      return;
    }
    const first = (user['first_name'] as string | undefined) ?? '';
    const last = (user['last_name'] as string | undefined) ?? '';
    const name = `${first} ${last}`.trim();
    this.names.set(id, name);
    const pp = user['profile_photo'] as TdObject | undefined;
    const small = pp !== undefined ? (pp['small'] as TdObject | undefined) : undefined;
    this.photos.set(id, small !== undefined ? ((small['id'] as number | undefined) ?? 0) : 0);
  }
}
