// AI/Directives：小队下发给单兵的稳定指令数据结构。
import { Vec2 } from 'cc';
export type DirectiveType = 'move' | 'guard' | 'attack' | 'suppress' | 'flank' | 'recon' | 'withdraw' | 'take-cover';
export interface SquadDirective { type: DirectiveType; destination?: Vec2; targetId?: string; priority: number; version: number; }
export class DirectiveFactory { private version = 0; make(type: DirectiveType, destination?: Vec2, targetId?: string, priority = 1): SquadDirective { return { type, destination: destination?.clone(), targetId, priority, version: ++this.version }; } }
