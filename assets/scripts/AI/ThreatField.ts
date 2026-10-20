// AI/ThreatField：把记忆中的敌情转换为位置风险和撤离方向。
import { Vec2 } from 'cc';
import { WorkingMemory } from './WorkingMemory';
export class LocalThreatField {
  constructor(public memory: WorkingMemory) {}
  riskAt(position: Vec2): number { return this.memory.contacts.reduce((risk, contact) => { const distance = Vec2.distance(position, contact.position); return risk + Math.max(0, contact.confidence * 100 * (1 - distance / 500)); }, 0); }
  safestDirection(origin: Vec2): Vec2 { const threat = this.memory.bestThreat(); if (!threat) return new Vec2(); const direction = origin.clone().subtract(threat.position); return direction.normalize(); }
}
