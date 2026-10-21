// Combat/BattlefieldRegistry：全局战斗实体索引，供感知和小队查询敌我。
import { EventTarget, Vec2 } from 'cc';
export interface CombatActor { id: string; team: string; position: Vec2; alive: boolean; component?: unknown; }
export class BattlefieldRegistry {
  readonly events = new EventTarget(); readonly actors = new Map<string, CombatActor>();
  register(actor: CombatActor): void { this.actors.set(actor.id, actor); this.events.emit('registered', actor); }
  unregister(id: string): void { const actor = this.actors.get(id); if (actor) this.events.emit('unregistered', actor); this.actors.delete(id); }
  findHostiles(team: string, origin: Vec2, radius = Infinity): CombatActor[] { return [...this.actors.values()].filter((actor) => actor.alive && actor.team !== team && Vec2.distance(actor.position, origin) <= radius); }
}
