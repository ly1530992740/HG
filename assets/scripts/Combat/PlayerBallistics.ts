// Combat/PlayerBallistics：玩家精度、移动惩罚和射击方向散布。
import { Vec2 } from 'cc';
import { AimComponent } from './Aim';
export class PlayerAccuracy { settle = 0; constructor(public aim: AimComponent) {} update(dt: number, moving: boolean): void { this.settle = Math.max(0, Math.min(1, this.settle + (moving ? -dt : dt) * 1.5)); } spread(): number { return this.aim.getSpread() + (1 - this.settle) * 2; } }
export class PlayerBallistics { constructor(public accuracy: PlayerAccuracy) {} getShotDirection(forward: Vec2): Vec2 { const direction = forward.clone(); const spread = this.accuracy.spread() * Math.PI / 180; const angle = (Math.random() - 0.5) * spread; const x = direction.x * Math.cos(angle) - direction.y * Math.sin(angle); const y = direction.x * Math.sin(angle) + direction.y * Math.cos(angle); return new Vec2(x, y).normalize(); } }
