// Tests/SurvivalIntegrationTest：验证资源、建造、经济、商店和偷取的跨模块协作。
import { _decorator, Vec2 } from 'cc';
import { GameState } from '../Core/GameState';
import { ConstructionSystem } from '../Survival/Construction';
import { SurvivalEconomy } from '../Survival/Economy';
import { ShopService } from '../Survival/Shop';
import { StealSystem } from '../Survival/StealSystem';
import { TestBase } from './TestBase';

const { ccclass } = _decorator;

@ccclass('SurvivalIntegrationTest')
export class SurvivalIntegrationTest extends TestBase {
  onLoad(): void {
    const base = this.node.addComponent(GameState);
    const raider = new GameState();
    const construction = new ConstructionSystem(base);
    const building = construction.begin('turret', new Vec2(0, 0));
    this.assert(building !== null && base.resources.material === 0, '建造系统消耗资源账本');

    const economy = new SurvivalEconomy(base);
    economy.rewardKill(10);
    const shop = new ShopService(economy);
    this.assert(shop.purchase('medical_pack')?.id === 'medical_pack', '击杀奖励可购买补给');
    this.assert(economy.points === 5, '商店正确扣除点数');

    raider.resources.material = 10;
    base.resources.material = 0;
    const steal = new StealSystem();
    const received = steal.steal(raider, base, 'material', 6);
    this.assert(received === 6 && base.resources.material === 6, '偷取资源转入玩家账本');
    this.assert(raider.resources.material === 4, '偷取资源从来源扣除');
    this.finish('Survival Integration');
  }
}
