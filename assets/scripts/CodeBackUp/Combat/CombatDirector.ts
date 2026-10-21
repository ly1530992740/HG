// 战斗组合器：注册士兵、维护战场索引，并驱动每个小队的决策循环。
import { EventTarget } from 'cc';
import { GameState } from '../Core/GameState';
import { BattlefieldRegistry } from './BattlefieldRegistry';
import { Soldier } from './Soldier';
import { SquadCoordinator } from '../AI/SquadCoordinator';

export class CombatDirector {
  readonly events = new EventTarget(); readonly registry = new BattlefieldRegistry(); readonly squads = new Map<string, SquadCoordinator>();
  constructor(public state: GameState) {}
  registerSoldier(soldier: Soldier): void {
    // 先注册到全局战场，再加入对应队伍，感知系统才能找到敌我双方。
    soldier.configure(this.registry, this.state);
    let squad = this.squads.get(soldier.team);
    if (!squad) { squad = new SquadCoordinator(this.registry, soldier.team, []); this.squads.set(soldier.team, squad); }
    squad.addSoldier(soldier);
    this.events.emit('soldier-registered', soldier);
  }
  update(dt: number): void { for (const squad of this.squads.values()) squad.update(dt); }
}
