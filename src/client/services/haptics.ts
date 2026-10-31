import { Haptics, ImpactStyle, NotificationType } from '@capacitor/haptics';

/**
 * Apple HIG Taptic Engine 觸覺反饋服務 (具備跨平台與 Web 降級能力)
 */
class HapticsService {
  private isAvailable: boolean | null = null;

  /**
   * 輕微觸覺反饋 (Light Impact)
   * 用於：清單點擊、標籤切換、慣用手偏置選擇
   */
  async impactLight(): Promise<void> {
    try {
      await Haptics.impact({ style: ImpactStyle.Light });
    } catch {
      this.fallbackVibrate(15);
    }
  }

  /**
   * 中度觸覺反饋 (Medium Impact)
   * 用於：視圖模式切換 (⊞ ALL <-> ▤ DUO)、思考預算膠囊快選 (0K~100K)
   */
  async impactMedium(): Promise<void> {
    try {
      await Haptics.impact({ style: ImpactStyle.Medium });
    } catch {
      this.fallbackVibrate(30);
    }
  }

  /**
   * 重度觸覺反饋 (Heavy Impact)
   * 用於：專注模式全寬展開/還原、主按鈕操作
   */
  async impactHeavy(): Promise<void> {
    try {
      await Haptics.impact({ style: ImpactStyle.Heavy });
    } catch {
      this.fallbackVibrate(50);
    }
  }

  /**
   * 警告通知反饋 (Warning Notification)
   * 用於：配額低於 5% 耗盡脈動、Governing 瓶頸切換
   */
  async notificationWarning(): Promise<void> {
    try {
      await Haptics.notification({ type: NotificationType.Warning });
    } catch {
      this.fallbackVibrate([30, 60, 30]);
    }
  }

  /**
   * 錯誤與阻斷反饋 (Error Notification)
   * 用於：池級 Quota Hard Stop 配額硬阻斷、網路斷線
   */
  async notificationError(): Promise<void> {
    try {
      await Haptics.notification({ type: NotificationType.Error });
    } catch {
      this.fallbackVibrate([50, 80, 50, 80]);
    }
  }

  /**
   * Web/非 iOS 平台震動降級
   */
  private fallbackVibrate(pattern: number | number[]): void {
    if (typeof navigator !== 'undefined' && typeof navigator.vibrate === 'function') {
      try {
        navigator.vibrate(pattern);
      } catch {}
    }
  }
}

export const haptic = new HapticsService();
