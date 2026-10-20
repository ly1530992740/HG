// Survival/Backpack：单个角色的轻量资源携带容器。
import { GameState, ResourceType } from '../Core/GameState';

/** Small per-actor resource ledger, equivalent to the Godot Backpack resource. */
export class Backpack {
  readonly resources: Record<ResourceType, number> = { food: 0, ammo: 0, weapon: 0, material: 0, medical: 0 };
  constructor(public perTypeCapacity = 20, public totalCapacity = 40) {}
  getTotal(): number { return Object.keys(this.resources).reduce((sum, key) => sum + this.resources[key as ResourceType], 0); }
  add(type: ResourceType, amount: number): number {
    const available = Math.min(this.perTypeCapacity - this.resources[type], this.totalCapacity - this.getTotal());
    const accepted = Math.max(0, Math.min(Math.floor(amount), available));
    this.resources[type] += accepted;
    return accepted;
  }
  transferToLedger(ledger: GameState, type: ResourceType, amount: number): number {
    const moved = Math.min(this.resources[type], Math.max(0, amount));
    const accepted = ledger.add(type, moved);
    this.resources[type] -= accepted;
    return accepted;
  }
}
