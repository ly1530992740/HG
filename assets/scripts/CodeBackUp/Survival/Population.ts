// Survival/Population：人口上限、职业转换和死亡记录。
import { EventTarget } from 'cc';

export type PopulationRole = 'villager' | 'soldier' | 'medic';
export interface PopulationMember { id: string; role: PopulationRole; alive: boolean; }

export class PopulationSystem {
  readonly events = new EventTarget();
  readonly members: PopulationMember[] = [];
  constructor(public maximum = 20) {}
  add(id: string, role: PopulationRole = 'villager'): boolean {
    if (this.members.length >= this.maximum) return false;
    this.members.push({ id, role, alive: true }); this.events.emit('changed', this.total(), this.roles()); return true;
  }
  changeRole(id: string, role: PopulationRole): boolean {
    const member = this.members.find((entry) => entry.id === id && entry.alive);
    if (!member) return false; member.role = role; this.events.emit('changed', this.total(), this.roles()); return true;
  }
  kill(id: string): boolean {
    const member = this.members.find((entry) => entry.id === id && entry.alive);
    if (!member) return false; member.alive = false; this.events.emit('changed', this.total(), this.roles()); return true;
  }
  total(): number { return this.members.filter((entry) => entry.alive).length; }
  roles(): Record<PopulationRole, number> { return { villager: this.members.filter((m) => m.alive && m.role === 'villager').length, soldier: this.members.filter((m) => m.alive && m.role === 'soldier').length, medic: this.members.filter((m) => m.alive && m.role === 'medic').length }; }
}
