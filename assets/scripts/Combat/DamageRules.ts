// Combat：所有命中位置的伤害倍率集中在这里，避免各武器重复实现。
export type HitLocation = 'head' | 'body' | 'limb';
export interface DamageResult { amount: number; killed: boolean; location: HitLocation; critical: boolean; }
export class CombatDamageRules {
  static resolve(baseDamage: number, location: HitLocation, armor = 0): DamageResult {
    // 头部暴击、四肢减伤、身体使用基础伤害。
    const multiplier = location === 'head' ? 2 : location === 'limb' ? 0.65 : 1;
    const amount = Math.max(0, Math.round(baseDamage * multiplier - Math.max(0, armor)));
    return { amount, killed: false, location, critical: location === 'head' };
  }
}
