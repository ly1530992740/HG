// 生存、战斗、AI 的组合根：负责创建服务并在每帧驱动它们。
import { _decorator, Component } from 'cc';
import { GameState } from './GameState';
import { ConstructionSystem } from '../Survival/Construction';
import { PopulationSystem } from '../Survival/Population';
import { SurvivalEconomy } from '../Survival/Economy';
import { ShopService } from '../Survival/Shop';
import { StealSystem } from '../Survival/StealSystem';
import { AllyCommandController } from '../Survival/Allies';
import { CameraDirector } from '../Survival/CameraDirector';
import { RenderPipelineConfigService } from '../Survival/RenderPipeline';
import { NpcSystem } from '../AI/NPC';
import { CombatDirector } from '../Combat/CombatDirector';

const { ccclass, property } = _decorator;
/** Composition root for the migrated survival, combat and AI services. */
@ccclass('SurvivalDirector')
export class SurvivalDirector extends Component {
  @property({ type: GameState }) state: GameState | null = null;
  construction!: ConstructionSystem; population!: PopulationSystem; economy!: SurvivalEconomy; shop!: ShopService; steal!: StealSystem; allies!: AllyCommandController; camera!: CameraDirector; render!: RenderPipelineConfigService; npc!: NpcSystem; combat!: CombatDirector;
  onLoad(): void {
    // 关键：所有服务共享同一个 GameState，跨模块交易不会产生第二份资源账本。
    this.state ||= this.node.getComponent(GameState) || this.node.addComponent(GameState);
    this.construction = new ConstructionSystem(this.state);
    this.population = new PopulationSystem(20);
    this.economy = new SurvivalEconomy(this.state);
    this.shop = new ShopService(this.economy);
    this.steal = new StealSystem();
    this.allies = new AllyCommandController();
    this.camera = new CameraDirector();
    this.render = new RenderPipelineConfigService();
    this.npc = new NpcSystem(this.state);
    this.combat = new CombatDirector(this.state);
  }

  update(dt: number): void {
    // 每帧只驱动需要时间推进的系统；纯数据服务不在这里轮询。
    this.construction.update(dt);
    this.npc.update(dt, []);
    this.combat.update(dt);
  }
}
