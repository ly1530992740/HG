// Playtest/AIPlayground：只装配 Soldier + BattlefieldRegistry + SquadCoordinator，观察 AI 小队交火。
import { _decorator, Color, Label, Node } from 'cc';
import { SquadCoordinator } from '../AI/SquadCoordinator';
import { GameState } from '../Core/GameState';
import { BattlefieldRegistry } from '../Combat/BattlefieldRegistry';
import { CombatDirector } from '../Combat/CombatDirector';
import { Soldier } from '../Combat/Soldier';
import { PlaytestBase } from './PlaytestBase';

const { ccclass } = _decorator;

@ccclass('AIPlayground')
export class AIPlayground extends PlaytestBase {
  private state!: GameState;
  private combat!: CombatDirector;
  private redSquad!: SquadCoordinator;
  private blueSquad!: SquadCoordinator;
  private decisionLabel: Label | null = null;

  onLoad(): void {
    this.createStage('AI PLAYGROUND', '自动运行：感知 -> 信念 -> Utility -> HTN -> 单兵状态机 -> 交火');
    this.state = this.node.addComponent(GameState);
    this.combat = new CombatDirector(this.state);
    const red: Soldier[] = [];
    const blue: Soldier[] = [];
    red.push(this.spawnSoldier('Red_Leader', 'red', -260, -60, new Color(235, 90, 90)));
    red.push(this.spawnSoldier('Red_Support', 'red', -260, 70, new Color(235, 120, 120)));
    blue.push(this.spawnSoldier('Blue_Leader', 'blue', 260, 60, new Color(80, 140, 255)));
    blue.push(this.spawnSoldier('Blue_Support', 'blue', 260, -70, new Color(100, 170, 255)));
    red.forEach((soldier) => this.combat.registerSoldier(soldier));
    blue.forEach((soldier) => this.combat.registerSoldier(soldier));
    this.redSquad = this.combat.squads.get('red')!;
    this.blueSquad = this.combat.squads.get('blue')!;
    for (let i = 0; i < red.length; i++) red[i].target = blue[i];
    for (let i = 0; i < blue.length; i++) blue[i].target = red[i];
    const labelNode = new Node('Decisions');
    this.uiRoot!.addChild(labelNode);
    labelNode.setPosition(-450, 120);
    this.decisionLabel = labelNode.addComponent(Label);
    this.sizeLabel(this.decisionLabel, 900, 120, 0, 1);
    this.decisionLabel.fontSize = 14;
    this.decisionLabel.color = Color.WHITE;
    this.decisionLabel.horizontalAlign = Label.HorizontalAlign.LEFT;
    this.decisionLabel.verticalAlign = Label.VerticalAlign.TOP;
    this.showMessage('两支小队已部署，等待 AI 首次重规划');
  }

  private spawnSoldier(name: string, team: string, x: number, y: number, color: Color): Soldier {
    const node = new Node(name);
    this.worldRoot!.addChild(node);
    node.setPosition(x, y);
    const soldier = node.addComponent(Soldier);
    soldier.team = team;
    soldier.soldierId = name;
    this.circle(node, color, 18);
    return soldier;
  }

  update(dt: number): void {
    this.combat.update(dt);
    if (this.decisionLabel) {
      const red = this.redSquad?.currentDirective?.type || '等待';
      const blue = this.blueSquad?.currentDirective?.type || '等待';
      this.decisionLabel.string = `RED  ${red}\nBLUE ${blue}\n红队存活 ${this.redSquad?.soldiers.filter((soldier) => !soldier.dead).length || 0}\n蓝队存活 ${this.blueSquad?.soldiers.filter((soldier) => !soldier.dead).length || 0}`;
    }
  }
}
