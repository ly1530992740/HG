// AI/WorkingMemory：保存短期敌情记忆，并随时间降低有效性。
import { Vec2 } from 'cc';
import { Soldier } from '../Combat/Soldier';
export interface MemoryContact { target: Soldier; position: Vec2; confidence: number; age: number; }
export class WorkingMemory {
  contacts: MemoryContact[] = [];
  remember(target: Soldier, position = target.position2D, confidence = 1): void { const existing = this.contacts.find((entry) => entry.target === target); if (existing) Object.assign(existing, { position: position.clone(), confidence, age: 0 }); else this.contacts.push({ target, position: position.clone(), confidence, age: 0 }); }
  update(dt: number, maxAge = 8): void { for (const contact of this.contacts) contact.age += dt; this.contacts = this.contacts.filter((contact) => contact.age <= maxAge && !contact.target.dead); }
  bestThreat(): MemoryContact | null { return this.contacts.sort((a, b) => (b.confidence - b.age * 0.1) - (a.confidence - a.age * 0.1))[0] || null; }
}
