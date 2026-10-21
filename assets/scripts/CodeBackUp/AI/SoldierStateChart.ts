// AI：单兵状态机。危险时进入 survival-override，压制解除后恢复原指令。
import { EventTarget } from 'cc';
import { Soldier } from '../Combat/Soldier';
import { SquadDirective } from './Directives';
export type SoldierRootState = 'idle-security' | 'execute-order' | 'survival-override' | 'dead';
export class SoldierStateChart {
  readonly events = new EventTarget(); state: SoldierRootState = 'idle-security'; private directive: SquadDirective | null = null;
  constructor(public soldier: Soldier) { soldier.events.on('died', () => this.setState('dead'), this); soldier.suppression.events.on('pinned', () => this.setState('survival-override'), this); }
  setDirective(directive: SquadDirective | null): void { this.directive = directive; if (directive && this.state !== 'dead') this.setState('execute-order'); }
  update(): void { if (this.soldier.dead) return; if (this.state === 'survival-override' && !this.soldier.suppression.pinned) this.setState(this.directive ? 'execute-order' : 'idle-security'); }
  private setState(next: SoldierRootState): void {
    if (next === this.state) return;
    // 关键：状态改变通过事件广播，动画、HUD 和调试面板都可以订阅而不耦合状态机。
    this.state = next;
    this.events.emit('state-changed', next);
  }
}
