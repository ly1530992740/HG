// HUD：只读取 GameState 并显示状态，不修改任何玩法数据。
import { _decorator, Color, Component, Label, Node } from 'cc';
import { GameState } from '../Core/GameState';

const { ccclass } = _decorator;

/** Presentation-only HUD. It reads game state but never changes gameplay data. */
@ccclass('HudView')
export class HudView extends Component {
  private statusLabel: Label | null = null;
  private messageLabel: Label | null = null;

  initialize(): void {
    const statusNode = new Node('Status');
    this.node.addChild(statusNode);
    statusNode.setPosition(-450, 260);
    this.statusLabel = statusNode.addComponent(Label);
    this.statusLabel.fontSize = 16;
    this.statusLabel.lineHeight = 22;
    this.statusLabel.color = Color.WHITE;

    const helpNode = new Node('Help');
    this.node.addChild(helpNode);
    helpNode.setPosition(-450, -270);
    const helpLabel = helpNode.addComponent(Label);
    helpLabel.fontSize = 14;
    helpLabel.color = new Color(190, 205, 215);
    helpLabel.string = '核心循环：采集资源 -> 建造/生产 -> 防守波次';

    const messageNode = new Node('Message');
    this.node.addChild(messageNode);
    messageNode.setPosition(0, 250);
    this.messageLabel = messageNode.addComponent(Label);
    this.messageLabel.fontSize = 22;
    this.messageLabel.color = new Color(255, 220, 120);
  }

  setStatus(state: GameState): void {
    // 关键：HUD 每帧使用同一个状态快照更新文本，避免各系统分别拼接资源数字。
    if (!this.statusLabel) return;
    this.statusLabel.string = `DAY ${state.day}   FOOD ${state.resources.food}   AMMO ${state.resources.ammo}   MAT ${state.resources.material}   MED ${state.resources.medical}   SCORE ${state.score}\nWASD 移动  SPACE 射击  E 采集  B 建造农场`;
  }

  showMessage(text: string): void {
    if (this.messageLabel) this.messageLabel.string = text;
  }
}
