// Combat/Injury：流血和短暂硬直等受伤状态。
import { EventTarget } from 'cc';
export class InjuryComponent { readonly events = new EventTarget(); bleeding = 0; stunned = 0; apply(amount: number): void { this.bleeding += Math.max(0, amount * 0.1); this.stunned = Math.max(this.stunned, amount >= 30 ? 0.5 : 0); this.events.emit('injured', this.bleeding, this.stunned); } update(dt: number): void { this.bleeding = Math.max(0, this.bleeding - dt * 0.3); this.stunned = Math.max(0, this.stunned - dt); } }
