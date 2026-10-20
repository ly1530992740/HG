// Enemy：最小敌人行为。它只负责追击和攻击，不负责波次生成。
import { _decorator, Component, Node, Vec3 } from 'cc';
import { GameState } from '../Core/GameState';

const { ccclass, property } = _decorator;

@ccclass('Enemy')
export class Enemy extends Component {
  @property moveSpeed = 42;
  @property attackRange = 42;
  @property attackCooldown = 1;
  @property health = 60;
  private target: Node | null = null;
  private state: GameState | null = null;
  private attackTimer = 0;

  configure(target: Node, state: GameState): void { this.target = target; this.state = state; }
  hit(damage: number): boolean {
    this.health -= damage;
    if (this.health > 0) return false;
    this.state?.events.emit('enemy-defeated', this.node);
    this.node.destroy();
    return true;
  }

  update(dt: number): void {
    if (!this.target || !this.state) return;
    this.attackTimer -= dt;
    const direction = new Vec3(); Vec3.subtract(direction, this.target.position, this.node.position);
    const distance = direction.length();
    if (distance > this.attackRange) {
      // 距离较远时追击目标；到达攻击距离后进入人口伤害逻辑。
      direction.normalize();
      this.node.setPosition(this.node.position.x + direction.x * this.moveSpeed * dt, this.node.position.y + direction.y * this.moveSpeed * dt);
    } else if (this.attackTimer <= 0) {
      this.attackTimer = this.attackCooldown;
      this.state.damagePopulation();
    }
  }
}
