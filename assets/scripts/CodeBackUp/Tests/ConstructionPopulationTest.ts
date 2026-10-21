// Tests/ConstructionPopulationTest：验证配方扣费、建造进度、耐久和人口职业。
import { _decorator, Vec2 } from 'cc';
import { GameState } from '../Core/GameState';
import { ConstructionSystem } from '../Survival/Construction';
import { Durability } from '../Survival/Durability';
import { PopulationSystem } from '../Survival/Population';
import { TestBase } from './TestBase';

const { ccclass } = _decorator;

@ccclass('ConstructionPopulationTest')
export class ConstructionPopulationTest extends TestBase {
  onLoad(): void {
    const state = this.node.addComponent(GameState);
    const construction = new ConstructionSystem(state);
    const farm = construction.begin('farm', new Vec2(0, 0));
    this.assert(farm !== null, '建造配方创建');
    this.assert(state.resources.material === 20, '建造成功扣除建材');
    this.assert(construction.begin('factory', new Vec2(10, 0)) === null, '建筑重叠位置拒绝');
    construction.update(3);
    this.assert(farm?.built === true && farm.progress === 1, '建造进度完成');

    const durability = new Durability(100);
    this.assert(durability.damage(35) === 35 && durability.damageVisualRatio() === 0.3, '建筑受损比例');
    this.assert(durability.repair(20) === 20 && durability.current === 85, '建筑维修');
    this.assert(durability.damage(200) === 85 && durability.destroyed, '建筑摧毁');

    const population = new PopulationSystem(2);
    this.assert(population.add('worker-1', 'villager'), '增加村民');
    this.assert(population.add('worker-2', 'soldier'), '增加士兵');
    this.assert(!population.add('worker-3'), '人口上限拦截');
    this.assert(population.changeRole('worker-1', 'medic') && population.roles().medic === 1, '职业转换');
    this.assert(population.kill('worker-2') && population.total() === 1, '人口死亡减员');
    this.finish('Construction + Population');
  }
}
