// AI/RoleAllocator：为队员分配 leader/scout/support/assault 角色。
import { Soldier } from '../Combat/Soldier';
export type SquadRole = 'leader' | 'assault' | 'support' | 'scout';
export interface RoleAssignment { soldier: Soldier; role: SquadRole; }
export class RoleAllocator { assign(soldiers: Soldier[]): RoleAssignment[] { return soldiers.map((soldier, index) => ({ soldier, role: index === 0 ? 'leader' : index % 3 === 1 ? 'scout' : index % 3 === 2 ? 'support' : 'assault' })); } }
