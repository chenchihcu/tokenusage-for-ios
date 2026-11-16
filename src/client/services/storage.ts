import { Preferences } from '@capacitor/preferences';

const APP_GROUP_SUITE = 'group.com.chihfu.opentokenusage';

/**
 * iOS 本地偏好設定與安全沙盒抽象層 (相容 Web localStorage 與 App Group)
 */
export class SecureStorageService {
  private static configured = false;

  private static async ensureConfigured(): Promise<void> {
    if (this.configured) return;
    this.configured = true;
    try {
      await Preferences.configure({ group: APP_GROUP_SUITE });
    } catch {}
  }

  /**
   * 讀取字串偏好
   */
  static async getItem(key: string): Promise<string | null> {
    try {
      await this.ensureConfigured();
      const { value } = await Preferences.get({ key });
      if (value !== null) return value;
    } catch {}

    if (typeof window !== 'undefined' && window.localStorage) {
      return window.localStorage.getItem(key);
    }
    return null;
  }

  /**
   * 寫入字串偏好
   */
  static async setItem(key: string, value: string): Promise<void> {
    try {
      await this.ensureConfigured();
      await Preferences.set({ key, value });
    } catch {}

    if (typeof window !== 'undefined' && window.localStorage) {
      window.localStorage.setItem(key, value);
    }
  }

  /**
   * 移除特定偏好
   */
  static async removeItem(key: string): Promise<void> {
    try {
      await this.ensureConfigured();
      await Preferences.remove({ key });
    } catch {}

    if (typeof window !== 'undefined' && window.localStorage) {
      window.localStorage.removeItem(key);
    }
  }

  /**
   * 清空所有本地快取
   */
  static async clear(): Promise<void> {
    try {
      await this.ensureConfigured();
      await Preferences.clear();
    } catch {}

    if (typeof window !== 'undefined' && window.localStorage) {
      window.localStorage.clear();
    }
  }
}
