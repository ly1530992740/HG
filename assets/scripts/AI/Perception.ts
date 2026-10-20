// AI/Perception：扫描战场敌人并报告视觉/听觉接触。
import { EventTarget, Vec2 } from 'cc';
import { BattlefieldRegistry } from '../Combat/BattlefieldRegistry';
import { CombatContact } from '../Combat/Contact';
import { Soldier } from '../Combat/Soldier';
export class SoldierPerception {
  readonly events = new EventTarget(); lastContact: ReturnType<typeof CombatContact.report> | null = null;
  constructor(public owner: Soldier, public sightRange = 320, public hearingRange = 420) {}
  scan(registry: BattlefieldRegistry): ReturnType<typeof CombatContact.report>[] { const contacts = registry.findHostiles(this.owner.team, this.owner.position2D, this.sightRange).map((actor) => { const hostile = (actor as any).component as Soldier; return hostile ? CombatContact.report(this.owner, hostile) : null; }).filter(Boolean) as ReturnType<typeof CombatContact.report>[]; if (contacts[0]) { this.lastContact = contacts[0]; this.events.emit('contact-spotted', contacts[0]); } return contacts; }
  hear(position: Vec2, confidence = 0.5): void { if (Vec2.distance(this.owner.position2D, position) <= this.hearingRange) this.events.emit('sound-heard', position.clone(), confidence); }
}
