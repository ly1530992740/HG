// Playtest/PlayerPlayground：只装配 GameState + Player，用于验证移动、输入和状态基础。
import { _decorator, Color, Node } from 'cc';
import { GameState } from '../Core/GameState';
import { Player } from '../Player/Player';
import { PlaytestBase } from './PlaytestBase';

const { ccclass } = _decorator;

@ccclass('PlayerPlayground')
export class PlayerPlayground extends PlaytestBase {
  private state!: GameState;
  private player!: Player;

  onLoad(): void {
    this.createStage('PLAYER PLAYGROUND', 'WASD / 方向键移动   |   SPACE 测试射击输入   |   ESC 返回编辑器');
    this.state = this.node.addComponent(GameState);
    const playerNode = new Node('Player');
    this.worldRoot!.addChild(playerNode);
    this.player = playerNode.addComponent(Player);
    this.player.configure(this.state, this.worldRoot!);
    this.circle(playerNode, new Color(70, 190, 255), 20);
    this.showMessage('玩家已生成，可以开始移动');
  }

  update(): void {
    if (this.hud) this.hud.string = `位置 X ${this.player.node.position.x.toFixed(0)}  Y ${this.player.node.position.y.toFixed(0)}\n生命 ${this.player.health}  弹药 ${this.state.resources.ammo}`;
  }
}
