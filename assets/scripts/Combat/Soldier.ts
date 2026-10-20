// Combat：玩家和 AI 共用的战斗实体，组合生命、武器、压制、伤口和背包组件。
import { _decorator, Component, EventTarget, Vec2 } from 'cc';
import { GameState } from '../Core/GameState';
import { Backpack } from '../Survival/Backpack';
import { CombatDamageRules, HitLocation } from './DamageRules';
import { BattlefieldRegistry } from './BattlefieldRegistry';
import { AimComponent } from './Aim';
import { HealthComponent } from './Health';
import { InjuryComponent } from './Injury';
import { LimbDamageComponent } from './LimbDamage';
import { SuppressionComponent } from './Suppression';
import { WeaponFireCycle } from './WeaponFireCycle';

const { ccclass, property } = _decorator;
@ccclass('Soldier')
export class Soldier extends Component {
  @property team = 'enemy'; @property soldierId = ''; @property moveSpeed = 80; @property sightRange = 320;
  readonly events = new EventTarget(); readonly position2D = new Vec2();
  readonly health = new HealthComponent(100); readonly aim = new AimComponent(); readonly injury = new InjuryComponent(); readonly limbs = new LimbDamageComponent(); readonly suppression = new SuppressionComponent(); readonly weapon = new WeaponFireCycle(); readonly backpack = new Backpack();
  private registry: BattlefieldRegistry | null = null; private state: GameState | null = null; target: Soldier | null = null; dead = false;
  configure(registry: BattlefieldRegistry, state?: GameState): void { this.registry = registry; this.state = state || null; this.soldierId ||= this.node.uuid; this.position2D.set(this.node.position.x, this.node.position.y); registry.register({ id: this.soldierId, team: this.team, position: this.position2D, alive: true, component: this }); this.health.events.on('died', () => this.die(), this); }
  update(dt: number): void { if (this.dead) return; this.weapon.update(dt); this.aim.update(dt); this.injury.update(dt); this.suppression.update(dt); this.position2D.set(this.node.position.x, this.node.position.y); if (this.target && !this.target.dead) this.stepTowardTarget(dt); }
  receiveDamage(baseDamage: number, location: HitLocation = 'body', armor = 0, instigator?: Soldier): number {
    if (this.dead) return 0;
    // 关键：先由统一伤害规则计算，再把结果分发给生命、部位、伤口和压制系统。
    const result = CombatDamageRules.resolve(baseDamage, location, armor);
    const applied = this.health.applyDamage(result.amount);
    this.limbs.apply(location, applied);
    this.injury.apply(applied);
    this.suppression.apply(applied * 0.8);
    this.events.emit('hit', result, instigator);
    return applied;
  }
  fireAt(target: Soldier): boolean { if (!this.weapon.fire()) return false; const location: HitLocation = Math.random() < 0.08 ? 'head' : Math.random() < 0.2 ? 'limb' : 'body'; target.receiveDamage(this.weapon.definition.damage, location, 0, this); this.events.emit('weapon-fired', target); return true; }
  private stepTowardTarget(dt: number): void { const direction = this.target!.position2D.clone().subtract(this.position2D); const distance = direction.length(); if (distance <= 100) { this.fireAt(this.target!); return; } direction.normalize(); this.node.setPosition(this.node.position.x + direction.x * this.moveSpeed * dt, this.node.position.y + direction.y * this.moveSpeed * dt); }
  private die(): void { if (this.dead) return; this.dead = true; this.events.emit('died', this); if (this.registry) this.registry.unregister(this.soldierId); if (this.state) { this.state.score += this.team === 'enemy' ? 10 : 0; this.state.events.emit('soldier-died', this); } }
}
