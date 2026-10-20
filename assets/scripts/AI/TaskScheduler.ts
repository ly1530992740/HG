// AI/TaskScheduler：把 HTN 任务轮流分配给存活队员。
import { Soldier } from '../Combat/Soldier';
import { SquadTask } from './HtnPlanner';
export class TaskScheduler { dispatch(soldiers: Soldier[], tasks: SquadTask[]): void { soldiers.forEach((soldier, index) => { const task = tasks[index % Math.max(1, tasks.length)]; (soldier as any).currentTask = task?.action || 'guard'; }); } }
