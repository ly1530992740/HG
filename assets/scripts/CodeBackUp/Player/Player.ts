// Player：输入、移动和射击。具体伤害由 Enemy/Combat 模块承接。
import { _decorator, Component, EventKeyboard, Input, input, KeyCode, Node, Vec3 } from 'cc';
import { Enemy } from '../Enemy/Enemy';
import { GameState } from '../Core/GameState';

const { ccclass, property } = _decorator;

@ccclass('Player')
export class Player extends Component {
  @property moveSpeed = 140;
  @property fireCooldown = 0.22;
  @property damage = 40;
  @property maxHealth = 100;
  health = 100;
  private state: GameState | null = null;
  private root: Node | null = null;
  private keys = new Set<KeyCode>();
  private fireTimer = 0;

  configure(state: GameState, root: Node): void { this.state = state; this.root = root; this.health = this.maxHealth; }
  onLoad(): void {
    input.on(Input.EventType.KEY_DOWN, this.onKeyDown, this);
    input.on(Input.EventType.KEY_UP, this.onKeyUp, this);
  }
  onDestroy(): void {
    input.off(Input.EventType.KEY_DOWN, this.onKeyDown, this);
    input.off(Input.EventType.KEY_UP, this.onKeyUp, this);
  }
  private onKeyDown(event: EventKeyboard): void { this.keys.add(event.keyCode); if (event.keyCode === KeyCode.SPACE) this.shoot(); }
  private onKeyUp(event: EventKeyboard): void { this.keys.delete(event.keyCode); }
  private shoot(): void {
    // 关键：射击必须同时满足冷却、弹药和运行时依赖条件。
    if (!this.root || !this.state || this.fireTimer > 0 || this.state.resources.ammo <= 0) return;
    this.fireTimer = this.fireCooldown; this.state.spend({ ammo: 1 });
    const enemies = this.root.children.filter((node) => node.name.startsWith('Enemy'));
    let best: Node | null = null; let distance = 180;
    for (const enemy of enemies) { const d = Vec3.distance(enemy.position, this.node.position); if (d < distance) { best = enemy; distance = d; } }
    // 当前原型选择最近目标；后续可替换为射线检测或 CombatHitbox。
    if (best) { const component = best.getComponent(Enemy); if (component?.hit(this.damage)) this.state.score += 10; }
  }
  update(dt: number): void {
    this.fireTimer = Math.max(0, this.fireTimer - dt);
    const x = (this.keys.has(KeyCode.ARROW_RIGHT) || this.keys.has(KeyCode.KEY_D) ? 1 : 0) - (this.keys.has(KeyCode.ARROW_LEFT) || this.keys.has(KeyCode.KEY_A) ? 1 : 0);
    const y = (this.keys.has(KeyCode.ARROW_UP) || this.keys.has(KeyCode.KEY_W) ? 1 : 0) - (this.keys.has(KeyCode.ARROW_DOWN) || this.keys.has(KeyCode.KEY_S) ? 1 : 0);
    const length = Math.hypot(x, y) || 1;
    this.node.setPosition(this.node.position.x + x / length * this.moveSpeed * dt, this.node.position.y + y / length * this.moveSpeed * dt);
  }
}
