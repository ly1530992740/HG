// Combat/Hitbox：把命中位置和伤害规则连接起来。
import { EventTarget, Vec2 } from 'cc';
import { CombatDamageRules, HitLocation } from './DamageRules';

export class CombatHitbox {
  readonly events = new EventTarget();
  constructor(public ownerId: string, public location: HitLocation = 'body', public radius = 20, public position = new Vec2()) {}
  receive(baseDamage: number, armor = 0): number {
    const result = CombatDamageRules.resolve(baseDamage, this.location, armor);
    this.events.emit('hit', result); return result.amount;
  }
}
