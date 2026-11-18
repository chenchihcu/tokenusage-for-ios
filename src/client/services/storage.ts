/**
 * Browser storage for display-only data (no tokens or secrets are stored here).
 * Every call tolerates storage being unavailable (private mode, blocked site data).
 */
export class SecureStorageService {
  static async getItem(key: string): Promise<string | null> {
    try {
      return window.localStorage.getItem(key);
    } catch {
      return null;
    }
  }

  static async setItem(key: string, value: string): Promise<void> {
    try {
      window.localStorage.setItem(key, value);
    } catch {}
  }

  static async removeItem(key: string): Promise<void> {
    try {
      window.localStorage.removeItem(key);
    } catch {}
  }

  static async clear(): Promise<void> {
    try {
      window.localStorage.clear();
    } catch {}
  }
}
