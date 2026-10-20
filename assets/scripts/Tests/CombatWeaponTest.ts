// Tests/CombatWeaponTest：验证伤害倍率、生命死亡、武器冷却和换弹。
import { _decorator } from 'cc';
import { CombatDamageRules } from '../Combat/DamageRules';
import { HealthComponent } from '../Combat/Health';
import { WeaponFireCycle } from '../Combat/WeaponFireCycle';
import { TestBase } from './TestBase';

const { ccclass } = _decorator;

@ccclass('CombatWeaponTest')
export class CombatWeaponTest extends TestBase {
  onLoad(): void {
    const head = CombatDamageRules.resolve(40, 'head');
    const limb = CombatDamageRules.resolve(40, 'limb');
    this.assert(head.amount === 80 && head.critical, '头部伤害倍率');
    this.assert(limb.amount === 26 && !limb.critical, '四肢伤害倍率');

    const health = new HealthComponent(100);
    this.assert(health.applyDamage(40) === 40 && health.current === 60, '生命受伤');
    this.assert(health.heal(15) === 15 && health.current === 75, '生命治疗');
    this.assert(health.applyDamage(100) === 75 && health.dead, '生命归零触发死亡');

    const weapon = new WeaponFireCycle('pistol', 12);
    this.assert(weapon.ammo === 12 && weapon.reserve === 12, '武器初始化弹药');
    this.assert(weapon.fire() && weapon.ammo === 11, '武器射击消耗弹药');
    this.assert(!weapon.fire(), '武器射击冷却');
    weapon.update(0.3);
    this.assert(weapon.fire(), '武器冷却结束可再次射击');
    weapon.ammo = 0;
    this.assert(weapon.reload() && weapon.reloadTime > 0, '武器开始换弹');
    weapon.update(2);
    this.assert(weapon.ammo > 0 && weapon.reserve < 12, '武器换弹完成');
    this.finish('Combat + Weapon');
  }
}
