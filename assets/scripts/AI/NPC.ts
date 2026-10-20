// AI/NPC：村民 HFSM、疲劳、恐慌传染、职业和 NPC 系统装配。
import { EventTarget, Vec2 } from 'cc';
import { GameState } from '../Core/GameState';

export type NpcState = 'work' | 'idle' | 'flee' | 'panic' | 'heal';
export type JobType = 'gather' | 'build' | 'medical' | 'guard';
export interface NpcJob { type: JobType; target?: string; }

export class FatigueComponent { value = 0; constructor(public fatiguePerSecond = 0.04, public recoveryPerSecond = 0.08) {} update(dt: number, working: boolean): void { this.value = Math.max(0, Math.min(1, this.value + (working ? this.fatiguePerSecond : -this.recoveryPerSecond) * dt)); } }
export class PanicContagion { readonly events = new EventTarget(); panic = 0; immune = false; update(dt: number, nearbyPanic: number): void { if (this.immune) return; this.panic = Math.max(0, Math.min(1, this.panic + (nearbyPanic * 0.12 - 0.04) * dt)); if (this.panic >= 0.75) this.events.emit('panic'); } }
export class PerceptionComponent { threat = 0; constructor(public sightRange = 220) {} scan(position: Vec2, threats: Vec2[]): number { this.threat = threats.reduce((max, threat) => Math.max(max, Math.max(0, 1 - Vec2.distance(position, threat) / this.sightRange)), 0); return this.threat; } }
export class JobAllocator { private jobs = new Map<string, NpcJob>(); assign(id: string, job: NpcJob): void { this.jobs.set(id, job); } get(id: string): NpcJob | undefined { return this.jobs.get(id); } }

export class VillagerHFSM {
  readonly events = new EventTarget(); state: NpcState = 'idle'; readonly fatigue = new FatigueComponent(); readonly panic = new PanicContagion(); readonly perception = new PerceptionComponent();
  constructor(public id: string, public position = new Vec2(), public job: NpcJob = { type: 'gather' }) { this.panic.events.on('panic', () => this.setState('panic'), this); }
  update(dt: number, threatPositions: Vec2[], nearbyPanic = 0): void { const threat = this.perception.scan(this.position, threatPositions); this.panic.update(dt, nearbyPanic); this.fatigue.update(dt, this.state === 'work'); if (this.state === 'panic' || this.panic.panic > 0.65) this.setState('flee'); else if (threat > 0.8) this.setState('flee'); else if (this.fatigue.value > 0.85) this.setState('idle'); else this.setState(this.job.type === 'medical' && threat < 0.2 ? 'heal' : 'work'); }
  private setState(next: NpcState): void { if (next !== this.state) { this.state = next; this.events.emit('state-changed', next); } }
}

export class NpcSystem {
  readonly events = new EventTarget(); readonly villagers: VillagerHFSM[] = []; readonly jobs = new JobAllocator();
  constructor(public state: GameState) {}
  add(id: string, job: NpcJob = { type: 'gather' }): VillagerHFSM { const npc = new VillagerHFSM(id, new Vec2(), job); this.villagers.push(npc); this.jobs.assign(id, job); npc.events.on('state-changed', (next) => this.events.emit('npc-state-changed', npc, next), this); return npc; }
  update(dt: number, threatPositions: Vec2[]): void { const panic = this.villagers.reduce((sum, npc) => sum + npc.panic.panic, 0) / Math.max(1, this.villagers.length); for (const npc of this.villagers) npc.update(dt, threatPositions, panic); }
}
