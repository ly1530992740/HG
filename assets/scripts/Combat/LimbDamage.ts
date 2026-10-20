// Combat/LimbDamage：记录头部、身体和四肢的累计伤口。
import { EventTarget } from 'cc';
import { HitLocation } from './DamageRules';
export class LimbDamageComponent {
  readonly events = new EventTarget();
  readonly wounds: Record<HitLocation, number> = { head: 0, body: 0, limb: 0 };
  apply(location: HitLocation, amount: number): void { this.wounds[location] += Math.max(0, amount); this.events.emit('wound', location, this.wounds[location]); }
  isDisabled(location: HitLocation): boolean { return location === 'limb' && this.wounds.limb >= 40; }
}
