// Tests/ResourceInventoryTest：验证 GameState 资源账本和 Inventory 槽位堆叠。
import { _decorator } from 'cc';
import { GameState } from '../Core/GameState';
import { Inventory } from '../Survival/Inventory';
import { TestBase } from './TestBase';

const { ccclass } = _decorator;

@ccclass('ResourceInventoryTest')
export class ResourceInventoryTest extends TestBase {
  onLoad(): void {
    const state = this.node.addComponent(GameState);
    state.storageCapacity = 50;
    state.resources.material = 45;
    this.assert(state.add('material', 10) === 5, '资源容量限制', `当前值=${state.resources.material}`);
    this.assert(state.resources.material === 50, '资源账本实际收取数量');
    this.assert(state.spend({ material: 20 }) && state.resources.material === 30, '资源原子扣费');
    this.assert(!state.spend({ ammo: 999 }), '资源不足时拒绝扣费');
    this.assert(state.remove('material', 8) === 8 && state.resources.material === 22, '资源移除');

    const inventory = new Inventory(2, 5);
    this.assert(inventory.addItem({ type: 'ammo', amount: 8 }) === 8, '背包堆叠同类物品');
    this.assert(inventory.count('ammo') === 8, '背包统计物品数量');
    this.assert(inventory.addItem({ type: 'ammo', amount: 5 }) === 2, '背包满格时拒绝溢出');
    this.assert(inventory.removeItem('ammo', 4) === 4 && inventory.count('ammo') === 6, '背包移除物品');
    this.finish('Resource + Inventory');
  }
}
