// Survival/Economy：击杀奖励点数和消费接口。
import { EventTarget } from 'cc';
import { GameState } from '../Core/GameState';

export class SurvivalEconomy {
  readonly events = new EventTarget();
  points = 0;
  constructor(public state: GameState) {}
  rewardKill(amount = 1): void { this.points += Math.max(0, amount); this.events.emit('points-changed', this.points); }
  spend(amount: number): boolean { if (amount <= 0 || this.points < amount) return false; this.points -= amount; this.events.emit('points-changed', this.points); return true; }
}
