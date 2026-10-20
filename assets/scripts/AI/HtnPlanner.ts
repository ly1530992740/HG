// AI/HtnPlanner：将高层小队指令拆成可执行任务序列。
import { DirectiveType, SquadDirective } from './Directives';
export interface SquadTask { name: string; action: DirectiveType; completed: boolean; }
export class HtnPlanner { plan(directive: SquadDirective): SquadTask[] { const tasks: SquadTask[] = []; if (directive.type === 'withdraw') tasks.push({ name: 'find-safe-route', action: 'withdraw', completed: false }); else if (directive.type === 'attack' || directive.type === 'suppress') { tasks.push({ name: 'move-to-position', action: 'move', completed: false }); tasks.push({ name: 'engage-target', action: directive.type, completed: false }); } else tasks.push({ name: directive.type, action: directive.type, completed: false }); return tasks; } }
