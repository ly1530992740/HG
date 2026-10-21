// Core：启动场景的装配器。它负责创建组件，不承载具体战斗算法。
import { _decorator, Camera, Canvas, Component, Color, EventKeyboard, Graphics, Input, input, KeyCode, Node, Vec3 } from 'cc';
import { Building } from '../Build/Building';
import { HudView } from '../HUD/HudView';
import { GameState, ResourceType } from './GameState';
import { Player } from '../Player/Player';
import { ResourceNode } from '../Resource/ResourceNode';
import { WaveDirector } from '../Wave/WaveDirector';
import { SurvivalDirector } from './SurvivalDirector';
import { WeaponCrosshair } from '../HUD/WeaponCrosshair';

const { ccclass, property } = _decorator;

@ccclass('GameRoot')
export class GameRoot extends Component {
  @property({ type: GameState }) state: GameState | null = null;
  @property({ type: Player }) player: Player | null = null;
  @property({ type: WaveDirector }) waveDirector: WaveDirector | null = null;
  @property({ type: SurvivalDirector }) survival: SurvivalDirector | null = null;
  private hud: HudView | null = null;

  onLoad(): void {
    // 关键：先创建状态，再把同一个状态对象注入玩家、波次和生存服务。
    this.state ||= this.node.addComponent(GameState);
    this.player ||= this.node.getChildByName('Player')?.getComponent(Player) || null;
    this.waveDirector ||= this.node.addComponent(WaveDirector);
    this.survival ||= this.node.getComponent(SurvivalDirector) || this.node.addComponent(SurvivalDirector);
    this.buildArena(); this.player?.configure(this.state, this.node); this.waveDirector.configure(this.state, this.node);
    this.state.events.on('wave-started', (count: number, day: number) => this.showMessage(`第 ${day} 天：敌军来袭 x${count}`), this);
    this.state.events.on('day-changed', (day: number) => this.showMessage(`第 ${day} 天`), this);
    input.on(Input.EventType.KEY_DOWN, this.onKeyDown, this);
  }

  onDestroy(): void { input.off(Input.EventType.KEY_DOWN, this.onKeyDown, this); }

  private onKeyDown(event: EventKeyboard): void {
    if (!this.player || !this.state) return;
    if (event.keyCode === KeyCode.KEY_E) {
      // E：只寻找玩家附近的采集点，实际扣库存由 ResourceNode 调用 GameState 完成。
      const node = this.node.children.find((child) => child.getComponent(ResourceNode) && Vec3.distance(child.position, this.player!.node.position) < 70);
      const resource = node?.getComponent(ResourceNode);
      if (resource?.canGather()) this.showMessage(`采集 +${resource.gather(this.state)} ${resource.resourceType}`);
    }
    if (event.keyCode === KeyCode.KEY_B && this.state.spend({ material: 20 })) {
      // B：建造前先扣除建材；失败时 spend 返回 false，不会生成建筑。
      this.addBuilding(`Farm_${this.state.score}`, 'farm', this.player.node.position.x + 55, this.player.node.position.y);
      this.showMessage('已建造农场，自动生产食物');
    }
  }

  update(): void { if (this.hud && this.state) this.hud.setStatus(this.state); }
  private buildArena(): void {
    // 演示场景使用代码生成基础图形，后续可将这些节点替换为 Cocos Prefab。
    const cameraNode = new Node('Camera'); this.node.addChild(cameraNode); cameraNode.setPosition(0, 0, 1000);
    const camera = cameraNode.addComponent(Camera); camera.projection = Camera.ProjectionType.ORTHO; camera.orthoHeight = 540; camera.clearColor = new Color(18, 24, 30, 255);
    const playerNode = this.node.getChildByName('Player') || new Node('Player'); if (!playerNode.parent) this.node.addChild(playerNode);
    playerNode.setPosition(0, 0); this.player ||= playerNode.addComponent(Player); this.draw(playerNode, new Color(80, 190, 255), 18);
    this.addResource('Wood', 'material', -170, 80); this.addResource('Food', 'food', 150, -70); this.addBuilding('Farm', 'farm', -100, -100);
    const canvasNode = new Node('Canvas'); this.node.addChild(canvasNode); canvasNode.addComponent(Canvas);
    this.hud = canvasNode.addComponent(HudView); this.hud.initialize();
    const crosshairNode = new Node('Crosshair'); canvasNode.addChild(crosshairNode); crosshairNode.setPosition(0, 0); const crosshair = crosshairNode.addComponent(WeaponCrosshair); crosshair.initialize();
  }
  private addResource(name: string, type: ResourceType, x: number, y: number): void { const node = new Node(name); this.node.addChild(node); node.setPosition(x, y); const resource = node.addComponent(ResourceNode); resource.resourceType = type; this.draw(node, type === 'food' ? new Color(90, 190, 90) : new Color(180, 140, 70), 22); }
  private addBuilding(name: string, type: 'farm' | 'factory' | 'medical' | 'turret', x: number, y: number): void { const node = new Node(name); this.node.addChild(node); node.setPosition(x, y); const building = node.addComponent(Building); building.buildingType = type; building.configure(this.state!); building.assignWorker(); this.draw(node, new Color(170, 110, 70), 34); }
  private draw(node: Node, color: Color, radius: number): void { const graphics = node.addComponent(Graphics); graphics.fillColor = color; graphics.circle(0, 0, radius); graphics.fill(); }
  private showMessage(text: string): void { this.hud?.showMessage(text); }
}
