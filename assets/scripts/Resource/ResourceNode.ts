// Resource：可交互采集点。采集点不直接保存全局库存，只把产出交给 GameState。
import { _decorator, Component } from 'cc';
import { GameState, ResourceType } from '../Core/GameState';

const { ccclass, property } = _decorator;

@ccclass('ResourceNode')
export class ResourceNode extends Component {
  @property resourceType: ResourceType = 'material';
  @property gatherAmount = 5;
  @property stock = 60;
  @property gatherCooldown = 1.2;
  private elapsed = 0;

  gather(state: GameState): number {
    if (this.stock <= 0) return 0;
    const amount = Math.min(this.gatherAmount, this.stock);
    // 关键：以账本实际接收量为准，容量不足时采集点不会错误扣除全部库存。
    const accepted = state.add(this.resourceType, amount);
    this.stock -= accepted;
    this.elapsed = 0;
    if (this.stock <= 0) this.node.active = false;
    return accepted;
  }

  canGather(): boolean { return this.node.active && this.stock > 0 && this.elapsed >= this.gatherCooldown; }

  update(dt: number): void { this.elapsed += dt; }
}
