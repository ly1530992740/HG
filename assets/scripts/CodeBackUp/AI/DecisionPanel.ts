// AI/DecisionPanel：只读展示 AI 最近一次决策，不参与决策计算。
import { _decorator, Component, Label, Node } from 'cc';
import { DecisionTrace } from './DecisionTrace';
const { ccclass } = _decorator;
@ccclass('DecisionPanel')
export class DecisionPanel extends Component {
  private label: Label | null = null; initialize(): void { const node = new Node('DecisionTrace'); this.node.addChild(node); this.label = node.addComponent(Label); this.label.fontSize = 12; }
  updateTrace(trace: DecisionTrace): void { const item = trace.latest(); if (item && this.label) this.label.string = `AI: ${item.choice} (${item.score.toFixed(2)})\n${item.reason}`; }
}
