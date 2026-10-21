// Survival/Durability：建筑受损、维修和摧毁状态。
import { EventTarget } from 'cc';

export class Durability {
  readonly events = new EventTarget();
  current: number;
  destroyed = false;
  constructor(public maximum = 100) { this.current = maximum; }
  damage(amount: number): number {
    if (this.destroyed || amount <= 0) return 0;
    const applied = Math.min(this.current, amount); this.current -= applied;
    this.events.emit('damaged', this.ratio());
    if (this.current <= 0) { this.destroyed = true; this.events.emit('destroyed'); }
    return applied;
  }
  repair(amount: number): number {
    if (this.destroyed || amount <= 0) return 0;
    const restored = Math.min(this.maximum - this.current, amount); this.current += restored;
    if (restored) this.events.emit('repaired', this.ratio());
    return restored;
  }
  ratio(): number { return Math.max(0, Math.min(1, this.current / Math.max(1, this.maximum))); }
  damageVisualRatio(): number { const lost = 1 - this.ratio(); return lost >= 0.9 ? 0.9 : lost >= 0.6 ? 0.6 : lost >= 0.3 ? 0.3 : 0; }
}
