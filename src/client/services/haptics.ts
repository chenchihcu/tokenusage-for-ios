/** Short vibration feedback where the browser supports it; silently does nothing elsewhere. */
class HapticsService {
  impactLight(): void {
    this.vibrate(15);
  }

  impactMedium(): void {
    this.vibrate(30);
  }

  impactHeavy(): void {
    this.vibrate(50);
  }

  notificationWarning(): void {
    this.vibrate([30, 60, 30]);
  }

  notificationError(): void {
    this.vibrate([50, 80, 50, 80]);
  }

  private vibrate(pattern: number | number[]): void {
    if (typeof navigator !== 'undefined' && typeof navigator.vibrate === 'function') {
      try {
        navigator.vibrate(pattern);
      } catch {}
    }
  }
}

export const haptic = new HapticsService();
