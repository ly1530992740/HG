// HUD/WeaponCrosshair：根据武器散布显示准星间距。
import { _decorator, Color, Component, Graphics, Node } from 'cc';
const { ccclass, property } = _decorator;
@ccclass('WeaponCrosshair')
export class WeaponCrosshair extends Component { @property spread = 18; initialize(): void { const graphics = this.node.addComponent(Graphics); graphics.strokeColor = Color.WHITE; graphics.lineWidth = 2; graphics.moveTo(-this.spread, 0); graphics.lineTo(-5, 0); graphics.moveTo(this.spread, 0); graphics.lineTo(5, 0); graphics.moveTo(0, -this.spread); graphics.lineTo(0, -5); graphics.moveTo(0, this.spread); graphics.lineTo(0, 5); graphics.stroke(); } setSpread(value: number): void { this.spread = value; } }
