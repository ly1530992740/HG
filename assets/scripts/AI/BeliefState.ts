// AI/BeliefState：把多个接触记忆压缩成小队决策快照。
import { Vec2 } from 'cc';
import { WorkingMemory } from './WorkingMemory';
export interface BeliefSnapshot { hostileCount: number; strongestContact: string | null; threatPosition: Vec2 | null; confidence: number; }
export class SquadBeliefState { constructor(public memory: WorkingMemory) {} snapshot(): BeliefSnapshot { const best = this.memory.bestThreat(); return { hostileCount: this.memory.contacts.length, strongestContact: best?.target.soldierId || null, threatPosition: best?.position.clone() || null, confidence: best?.confidence || 0 }; } }
