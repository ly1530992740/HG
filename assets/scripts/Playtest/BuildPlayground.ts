// Playtest/BuildPlayground：真实采集点 + ConstructionSystem + Building，用于验证经营建造闭环。
import { _decorator, Color, EventKeyboard, Input, input, KeyCode, Node, Vec2 } from 'cc';
import { Building } from '../Build/Building';
import { GameState, ResourceType } from '../Core/GameState';
import { Player } from '../Player/Player';
import { ResourceNode } from '../Resource/ResourceNode';
import { ConstructionSystem } from '../Survival/Construction';
import { PlaytestBase } from './PlaytestBase';

const { ccclass } = _decorator;

@ccclass('BuildPlayground')
export class BuildPlayground extends PlaytestBase {
  private state!: GameState;
  private player!: Player;
  private construction!: ConstructionSystem;
  private builtCount = 0;

  onLoad(): void {
    this.createStage('BUILD PLAYGROUND', 'WASD 移动   |   E 采集附近资源   |   B 建造农场   |   R 修理最近建筑');
    this.state = this.node.addComponent(GameState);
    this.construction = new ConstructionSystem(this.state);
    const playerNode = new Node('Player');
    this.worldRoot!.addChild(playerNode);
    this.player = playerNode.addComponent(Player);
    this.player.configure(this.state, this.worldRoot!);
    this.circle(playerNode, new Color(70, 190, 255), 20);
    this.spawnResource('WoodNode', 'material', -180, 80, new Color(175, 125, 60));
    this.spawnResource('FoodNode', 'food', 170, -80, new Color(80, 190, 90));
    input.on(Input.EventType.KEY_DOWN, this.onKeyDown, this);
    this.showMessage('靠近资源点按 E，收集建材后按 B');
  }

  onDestroy(): void { input.off(Input.EventType.KEY_DOWN, this.onKeyDown, this); }

  private spawnResource(name: string, type: ResourceType, x: number, y: number, color: Color): void {
    const resourceNode = new Node(name);
    this.worldRoot!.addChild(resourceNode);
    resourceNode.setPosition(x, y);
    const resource = resourceNode.addComponent(ResourceNode);
    resource.resourceType = type;
    resource.stock = 100;
    this.circle(resourceNode, color, 24);
  }

  private onKeyDown(event: EventKeyboard): void {
    if (event.keyCode === KeyCode.KEY_E) {
      const resourceNode = this.worldRoot!.children.find((child) => child.getComponent(ResourceNode) && Vec2.distance(new Vec2(child.position.x, child.position.y), new Vec2(this.player.node.position.x, this.player.node.position.y)) < 75);
      const resource = resourceNode?.getComponent(ResourceNode);
      if (resource?.canGather()) this.showMessage(`采集 ${resource.gather(this.state)} ${resource.resourceType}`);
    }
    if (event.keyCode === KeyCode.KEY_B) {
      const position = new Vec2(this.player.node.position.x + 65, this.player.node.position.y);
      const building = this.construction.begin('farm', position);
      if (!building) { this.showMessage('建造失败：建材不足或位置重叠'); return; }
      const node = new Node(`Building_${++this.builtCount}`);
      this.worldRoot!.addChild(node);
      node.setPosition(position.x, position.y);
      const visual = node.addComponent(Building);
      // 建筑视觉节点先显示施工状态，只有 ConstructionSystem 发出完成事件后才开始生产。
      this.construction.events.once('construction-finished', (finished) => {
        if (finished !== building) return;
        visual.configure(this.state);
        visual.assignWorker();
        this.showMessage('农场建造完成，开始生产食物');
      });
      this.rectangle(node, new Color(180, 120, 65), 58, 44);
      this.showMessage('农场建造中，3 秒后完成');
    }
    if (event.keyCode === KeyCode.KEY_R) {
      const placed = this.construction.buildings[0];
      if (!placed) { this.showMessage('还没有可维修建筑'); return; }
      const restored = placed.durability.repair(20);
      this.showMessage(`维修 ${restored} 点耐久`);
    }
  }

  update(dt: number): void {
    this.construction.update(dt);
    if (this.hud) this.hud.string = `食物 ${this.state.resources.food}  建材 ${this.state.resources.material}  弹药 ${this.state.resources.ammo}\n建造中 ${this.construction.buildings.filter((building) => !building.built).length}  已建造 ${this.construction.buildings.filter((building) => building.built).length}`;
  }
}
