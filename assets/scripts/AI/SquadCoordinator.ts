// AI 主链：感知 -> 工作记忆 -> 信念快照 -> Utility -> HTN -> 单兵状态机。
import { EventTarget, Vec2 } from 'cc';
import { BattlefieldRegistry } from '../Combat/BattlefieldRegistry';
import { Soldier } from '../Combat/Soldier';
import { SoldierPerception } from './Perception';
import { WorkingMemory } from './WorkingMemory';
import { LocalThreatField } from './ThreatField';
import { SquadBeliefState } from './BeliefState';
import { DirectiveFactory, SquadDirective } from './Directives';
import { UtilityEvaluator } from './UtilityEvaluator';
import { HtnPlanner } from './HtnPlanner';
import { RoleAllocator } from './RoleAllocator';
import { TaskScheduler } from './TaskScheduler';
import { SoldierStateChart } from './SoldierStateChart';

export class SquadCoordinator {
  readonly events = new EventTarget(); readonly memory = new WorkingMemory(); readonly threatField = new LocalThreatField(this.memory); readonly belief = new SquadBeliefState(this.memory); readonly directives = new DirectiveFactory(); readonly utility = new UtilityEvaluator(); readonly planner = new HtnPlanner(); readonly roles = new RoleAllocator(); readonly scheduler = new TaskScheduler(); readonly charts = new Map<Soldier, SoldierStateChart>(); currentDirective: SquadDirective | null = null;
  private elapsed = 0;
  constructor(public registry: BattlefieldRegistry, public team: string, public soldiers: Soldier[]) { for (const soldier of [...soldiers]) this.addSoldier(soldier); }
  addSoldier(soldier: Soldier): void {
    if (this.soldiers.indexOf(soldier) < 0) this.soldiers.push(soldier);
    this.roles.assign(this.soldiers);
    this.charts.set(soldier, new SoldierStateChart(soldier));
    const perception = new SoldierPerception(soldier);
    // 感知只负责报告接触，记忆和战术选择由协调器统一完成。
    perception.events.on('contact-spotted', (contact) => this.memory.remember(contact.hostile, contact.position, contact.confidence), this);
  }

  update(dt: number): void {
    this.elapsed += dt;
    this.memory.update(dt);
    for (const soldier of this.soldiers) {
      if (soldier.dead) continue;
      const hostile = this.registry.findHostiles(this.team, soldier.position2D, soldier.sightRange)[0];
      if (hostile) {
        const target = (hostile as any).component as Soldier;
        if (target) this.memory.remember(target, target.position2D, 1);
      }
      this.charts.get(soldier)?.update();
    }
    // 关键：降低重规划频率，避免每帧重复计算 Utility/HTN。
    if (this.elapsed < 1) return;
    this.elapsed = 0;
    this.replan();
  }

  private replan(): void {
    const snapshot = this.belief.snapshot();
    const type = this.utility.choose(snapshot);
    const target = this.memory.bestThreat();
    // 关键：把一次战术选择固化成带版本号的指令，单兵状态机按这个版本执行。
    this.currentDirective = this.directives.make(type, target?.position || new Vec2(), target?.target.soldierId, this.utility.score(type, snapshot));
    const tasks = this.planner.plan(this.currentDirective);
    this.scheduler.dispatch(this.soldiers.filter((soldier) => !soldier.dead), tasks);
    for (const chart of this.charts.values()) chart.setDirective(this.currentDirective);
    this.events.emit('decision', this.currentDirective, snapshot, tasks);
  }
}
