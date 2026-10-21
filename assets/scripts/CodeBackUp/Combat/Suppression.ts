// Combat/Suppression：承受火力后进入 pinned 状态，驱动单兵生存覆盖。
import { EventTarget } from 'cc';
export class SuppressionComponent { readonly events = new EventTarget(); value = 0; pinned = false; apply(amount: number): void { this.value = Math.min(100, this.value + Math.max(0, amount)); const wasPinned = this.pinned; this.pinned = this.value >= 60; if (this.pinned !== wasPinned) this.events.emit(this.pinned ? 'pinned' : 'unpinned'); } update(dt: number): void { this.value = Math.max(0, this.value - dt * 12); if (this.pinned && this.value < 35) { this.pinned = false; this.events.emit('unpinned'); } } }
