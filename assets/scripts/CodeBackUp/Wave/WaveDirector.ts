// Wave：按天数生成敌人。它只负责节奏和生成，不负责敌人自身行为。
import { _decorator, Color, Component, Graphics, Node } from 'cc';
import { Enemy } from '../Enemy/Enemy';
import { GameState } from '../Core/GameState';

const { ccclass, property } = _decorator;

@ccclass('WaveDirector')
export class WaveDirector extends Component {
  @property firstWaveDay = 2;
  @property dayDuration = 20;
  @property baseStrength = 3;
  @property strengthPerDay = 2;
  private elapsed = 0;
  private state: GameState | null = null;
  private root: Node | null = null;

  configure(state: GameState, root: Node): void { this.state = state; this.root = root; }
  update(dt: number): void {
    if (!this.state || !this.root || this.state.population <= 0) return;
    this.elapsed += dt;
    if (this.elapsed < this.dayDuration) return;
    // 一个完整白天结束后推进日期，再根据日期决定是否生成波次。
    this.elapsed = 0; this.state.day += 1;
    if (this.state.day >= this.firstWaveDay) this.spawnWave(this.baseStrength + (this.state.day - this.firstWaveDay) * this.strengthPerDay);
    this.state.events.emit('day-changed', this.state.day);
  }
  private spawnWave(count: number): void {
    for (let i = 0; i < count; i++) {
      const enemy = new Node(`Enemy_${this.state!.day}_${i}`); const component = enemy.addComponent(Enemy);
      const angle = (Math.PI * 2 * i) / count; enemy.setPosition(Math.cos(angle) * 360, Math.sin(angle) * 220);
      const graphics = enemy.addComponent(Graphics); graphics.fillColor = new Color(210, 70, 70); graphics.circle(0, 0, 15); graphics.fill();
      component.configure(this.root!.getChildByName('Player')!, this.state!); this.root!.addChild(enemy);
    }
    this.state!.events.emit('wave-started', count, this.state!.day);
  }
}
