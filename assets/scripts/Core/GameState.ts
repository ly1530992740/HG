// Core：全局玩法状态。其他模块只能通过这里修改资源、人口、天数和分数。
import { _decorator, Component, EventTarget } from 'cc';

const { ccclass, property } = _decorator;

export type ResourceType = 'food' | 'ammo' | 'weapon' | 'material' | 'medical';
export type ResourceMap = Record<ResourceType, number>;

/**
 * 全局状态单例组件。
 * 关键规则：资源变化必须经过 add/remove/spend，避免玩家、建筑和敌人各自维护一份库存。
 */
@ccclass('GameState')
export class GameState extends Component {
  @property({ tooltip: 'Maximum amount of each resource.' }) storageCapacity = 200;
  readonly events = new EventTarget();
  resources: ResourceMap = { food: 20, ammo: 30, weapon: 1, material: 40, medical: 5 };
  day = 1;
  score = 0;
  population = 3;

  add(type: ResourceType, amount: number): number {
    if (amount <= 0) return 0;
    // 关键：限制单种资源的容量，返回值表示实际收到的数量。
    const accepted = Math.min(Math.floor(amount), Math.max(0, this.storageCapacity - this.resources[type]));
    if (accepted > 0) {
      this.resources[type] += accepted;
      // 关键：所有 UI 和系统都通过这个事件得知资源已经改变。
      this.events.emit('resources-changed', this.resources);
    }
    return accepted;
  }

  remove(type: ResourceType, amount: number): number {
    if (amount <= 0) return 0;
    const removed = Math.min(Math.floor(amount), Math.max(0, this.resources[type]));
    if (removed > 0) {
      this.resources[type] -= removed;
      this.events.emit('resources-changed', this.resources);
    }
    return removed;
  }

  canAfford(cost: Partial<ResourceMap>): boolean {
    return Object.keys(cost).every((key) => this.resources[key as ResourceType] >= (cost[key as ResourceType] || 0));
  }

  spend(cost: Partial<ResourceMap>): boolean {
    // 关键：先整体校验，再整体扣除，避免扣到一半时资源不足。
    if (!this.canAfford(cost)) return false;
    for (const key of Object.keys(cost)) this.resources[key as ResourceType] -= cost[key as ResourceType] || 0;
    this.events.emit('resources-changed', this.resources);
    return true;
  }

  damagePopulation(): void {
    this.population = Math.max(0, this.population - 1);
    this.events.emit('population-changed', this.population);
  }

  healPopulation(amount = 1): number {
    const restored = Math.min(Math.max(0, amount), 20 - this.population);
    this.population += restored;
    if (restored > 0) this.events.emit('population-changed', this.population);
    return restored;
  }
}
