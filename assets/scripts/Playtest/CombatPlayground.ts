// Playtest/CombatPlayground：真实 Player + Enemy 组合，用于观察射击、命中、追击和人口伤害。
import { _decorator, Color, Node } from 'cc';
import { GameState } from '../Core/GameState';
import { Enemy } from '../Enemy/Enemy';
import { Player } from '../Player/Player';
import { PlaytestBase } from './PlaytestBase';

const { ccclass } = _decorator;

@ccclass('CombatPlayground')
export class CombatPlayground extends PlaytestBase {
  private state!: GameState;
  private player!: Player;

  onLoad(): void {
    this.createStage('COMBAT PLAYGROUND', 'WASD / 方向键移动   |   SPACE 射击最近敌人   |   敌人会追击并伤害人口');
    this.state = this.node.addComponent(GameState);
    const playerNode = new Node('Player');
    this.worldRoot!.addChild(playerNode);
    this.player = playerNode.addComponent(Player);
    this.player.configure(this.state, this.worldRoot!);
    this.circle(playerNode, new Color(70, 190, 255), 20);
    this.spawnEnemy('Enemy_A', 250, 80, 70);
    this.spawnEnemy('Enemy_B', -260, 60, 55);
    this.spawnEnemy('Enemy_C', 160, -170, 45);
    this.showMessage('敌人已生成，按 SPACE 射击');
  }

  private spawnEnemy(name: string, x: number, y: number, health: number): void {
    const enemyNode = new Node(name);
    this.worldRoot!.addChild(enemyNode);
    enemyNode.setPosition(x, y);
    const enemy = enemyNode.addComponent(Enemy);
    enemy.health = health;
    enemy.configure(this.worldRoot!.getChildByName('Player')!, this.state);
    this.circle(enemyNode, new Color(220, 75, 75), 17);
  }

  update(): void {
    if (this.hud) this.hud.string = `人口 ${this.state.population}  分数 ${this.state.score}  弹药 ${this.state.resources.ammo}\n剩余敌人 ${this.worldRoot!.children.filter((child) => child.name.startsWith('Enemy')).length}`;
  }
}
