// Survival/Pickups：弹药和武器拾取物的逻辑入口。
import { EventTarget } from 'cc';
import { GameState } from '../Core/GameState';
import { Inventory } from './Inventory';

export class AmmoPickup {
  readonly events = new EventTarget();
  constructor(public amount = 20) {}
  collect(state: GameState): number { const accepted = state.add('ammo', this.amount); if (accepted) this.events.emit('collected', accepted); return accepted; }
}
export class WeaponPickup {
  readonly events = new EventTarget();
  constructor(public weaponId = 'rifle', public ammo = 12) {}
  collect(state: GameState, inventory?: Inventory): boolean {
    const accepted = inventory ? inventory.addItem({ type: this.weaponId, amount: 1, maxStack: 1 }) : state.add('weapon', 1);
    if (accepted) { state.add('ammo', this.ammo); this.events.emit('collected', this.weaponId); return true; }
    return false;
  }
}
