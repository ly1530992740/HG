// Tests/SquadAiTest：验证 Utility、HTN、指令版本和 NPC 恐慌/疲劳状态。
import { _decorator, Vec2 } from 'cc';
import { BeliefSnapshot } from '../AI/BeliefState';
import { DirectiveFactory } from '../AI/Directives';
import { HtnPlanner } from '../AI/HtnPlanner';
import { UtilityEvaluator } from '../AI/UtilityEvaluator';
import { NpcSystem } from '../AI/NPC';
import { GameState } from '../Core/GameState';
import { TestBase } from './TestBase';

const { ccclass } = _decorator;

@ccclass('SquadAiTest')
export class SquadAiTest extends TestBase {
  onLoad(): void {
    const utility = new UtilityEvaluator();
    const empty: BeliefSnapshot = { hostileCount: 0, strongestContact: null, threatPosition: null, confidence: 0 };
    const heavy: BeliefSnapshot = { hostileCount: 4, strongestContact: 'enemy-1', threatPosition: new Vec2(10, 10), confidence: 0.9 };
    this.assert(utility.choose(empty) === 'guard', '无敌情时选择警戒');
    this.assert(utility.choose(heavy) === 'suppress', '多敌人时选择压制');
    this.assert(utility.choose(heavy, 0.1) === 'withdraw', '低士气时选择撤退');

    const factory = new DirectiveFactory();
    const directive = factory.make('attack', new Vec2(20, 20), 'enemy-1');
    const planner = new HtnPlanner();
    const tasks = planner.plan(directive);
    this.assert(directive.version === 1, '指令版本递增');
    this.assert(tasks.length === 2 && tasks[0].action === 'move' && tasks[1].action === 'attack', 'HTN 拆分移动和攻击任务');

    const state = this.node.addComponent(GameState);
    const npcSystem = new NpcSystem(state);
    const npc = npcSystem.add('villager-1', { type: 'gather' });
    npcSystem.update(1, [new Vec2(1000, 1000)]);
    this.assert(npc.state === 'work', 'NPC 无威胁时工作');
    npc.panic.panic = 0.9;
    npcSystem.update(0.1, []);
    this.assert(npc.state === 'flee' || npc.state === 'panic', 'NPC 高恐慌时逃离');
    this.finish('Squad AI + NPC');
  }
}
