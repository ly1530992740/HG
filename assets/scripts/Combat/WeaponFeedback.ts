// Combat/WeaponFeedback：枪口闪光和后坐力反馈的视觉事件。
import { EventTarget } from 'cc';
export class WeaponFeedback { readonly events = new EventTarget(); muzzleVisible = false; recoil = 0; flash(duration = 0.06): void { this.muzzleVisible = true; this.recoil = 1; this.events.emit('muzzle-flash'); setTimeout(() => { this.muzzleVisible = false; }, duration * 1000); } update(dt: number): void { this.recoil = Math.max(0, this.recoil - dt * 8); } }
