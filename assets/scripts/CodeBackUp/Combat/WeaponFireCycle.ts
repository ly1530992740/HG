// Combat：统一管理射击间隔、弹匣、备弹和换弹状态。
import { EventTarget } from 'cc';
export type WeaponFamily = 'bolt_rifle' | 'smg' | 'lmg' | 'pistol' | 'shotgun';
export interface WeaponDefinition { id: string; family: WeaponFamily; damage: number; fireInterval: number; magazine: number; reload: number; }
export const WEAPONS: Record<string, WeaponDefinition> = {
  rifle: { id: 'rifle', family: 'bolt_rifle', damage: 34, fireInterval: 0.55, magazine: 5, reload: 2 },
  smg: { id: 'smg', family: 'smg', damage: 18, fireInterval: 0.12, magazine: 24, reload: 1.7 },
  lmg: { id: 'lmg', family: 'lmg', damage: 22, fireInterval: 0.16, magazine: 40, reload: 2.5 },
  pistol: { id: 'pistol', family: 'pistol', damage: 24, fireInterval: 0.28, magazine: 12, reload: 1.4 },
};
export class WeaponFireCycle {
  readonly events = new EventTarget(); definition: WeaponDefinition; ammo: number; reserve: number; cooldown = 0; reloadTime = 0;
  constructor(weaponId = 'rifle', reserve = 96) { this.definition = WEAPONS[weaponId] || WEAPONS.rifle; this.ammo = this.definition.magazine; this.reserve = reserve; }
  update(dt: number): void { this.cooldown = Math.max(0, this.cooldown - dt); if (this.reloadTime > 0) { this.reloadTime = Math.max(0, this.reloadTime - dt); if (!this.reloadTime) this.finishReload(); } }
  fire(): boolean {
    // 关键：任何武器都必须经过同一个冷却与弹药检查。
    if (this.reloadTime || this.cooldown || this.ammo <= 0) return false;
    this.ammo--;
    this.cooldown = this.definition.fireInterval;
    this.events.emit('fired', this.definition);
    if (!this.ammo) this.reload();
    return true;
  }
  reload(): boolean { if (this.reloadTime || this.ammo >= this.definition.magazine || this.reserve <= 0) return false; this.reloadTime = this.definition.reload; this.events.emit('reload-started'); return true; }
  private finishReload(): void { const moved = Math.min(this.definition.magazine - this.ammo, this.reserve); this.ammo += moved; this.reserve -= moved; this.events.emit('reloaded', this.ammo, this.reserve); }
}
