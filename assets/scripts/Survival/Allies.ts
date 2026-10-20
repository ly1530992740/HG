// Survival/Allies：玩家对友军小队发布跟随、移动、攻击和驻守指令。
import { EventTarget, Vec2 } from 'cc';

export type AllyOrder = 'follow' | 'move' | 'attack' | 'hold';
export interface AllyMember { id: string; position: Vec2; order: AllyOrder; target?: Vec2; }
export class AllyCommandController {
  readonly events = new EventTarget();
  readonly allies: AllyMember[] = [];
  register(id: string, position = new Vec2()): AllyMember { const member = { id, position: position.clone(), order: 'follow' as AllyOrder }; this.allies.push(member); return member; }
  issue(order: AllyOrder, target?: Vec2): number { for (const ally of this.allies) { ally.order = order; ally.target = target?.clone(); } this.events.emit('order-issued', order, target); return this.allies.length; }
}
