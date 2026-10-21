// Survival/CameraDirector：相机模式和角度数据，具体 Camera 节点由场景层绑定。
import { EventTarget } from 'cc';
export type CameraMode = 'isometric' | 'third-person';
export class CameraDirector {
  readonly events = new EventTarget(); mode: CameraMode = 'isometric'; yaw = 0; pitch = 45;
  toggle(): CameraMode { this.mode = this.mode === 'isometric' ? 'third-person' : 'isometric'; this.events.emit('mode-changed', this.mode); return this.mode; }
  rotateYaw(delta: number): void { this.yaw = (this.yaw + delta) % 360; }
  setPitch(value: number): void { this.pitch = Math.max(-80, Math.min(80, value)); }
}
