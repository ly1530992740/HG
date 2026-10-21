// Combat/Health：统一生命值、治疗和死亡事件。
import { EventTarget } from 'cc';

export class HealthComponent {
  readonly events = new EventTarget(); current: number; dead = false;
  constructor(public maximum = 100) { this.current = maximum; }
  applyDamage(amount: number): number {
    if (this.dead || amount <= 0) return 0;
    const applied = Math.min(this.current, amount); this.current -= applied;
    this.events.emit('changed', this.current, this.maximum);
    if (this.current <= 0) { this.dead = true; this.events.emit('died'); }
    return applied;
  }
  heal(amount: number): number { if (this.dead || amount <= 0) return 0; const restored = Math.min(this.maximum - this.current, amount); this.current += restored; if (restored) this.events.emit('changed', this.current, this.maximum); return restored; }
  ratio(): number { return Math.max(0, this.current / Math.max(1, this.maximum)); }
}
