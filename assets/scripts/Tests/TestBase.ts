// Tests：所有模块测试场景共用的输出和断言基类。
import { _decorator, Color, Component, Label, Node } from 'cc';

const { ccclass } = _decorator;

@ccclass('TestBase')
export class TestBase extends Component {
  protected lines: string[] = [];
  protected passed = 0;
  protected failed = 0;

  protected assert(condition: boolean, name: string, detail = ''): void {
    if (condition) {
      this.passed++;
      this.lines.push(`PASS  ${name}`);
      console.log(`[TEST PASS] ${name}`);
    } else {
      this.failed++;
      this.lines.push(`FAIL  ${name}${detail ? `: ${detail}` : ''}`);
      console.error(`[TEST FAIL] ${name}`, detail);
    }
  }

  protected finish(title: string): void {
    const status = this.failed === 0 ? 'PASS' : 'FAIL';
    const output = [`${status}  ${title}`, `通过 ${this.passed} / 失败 ${this.failed}`, '', ...this.lines].join('\n');
    console.log(`[${status}] ${title}: ${this.passed} passed, ${this.failed} failed`);
    const labelNode = new Node('TestResult');
    this.node.addChild(labelNode);
    labelNode.setPosition(-440, 230);
    const label = labelNode.addComponent(Label);
    label.fontSize = 16;
    label.lineHeight = 22;
    label.color = this.failed === 0 ? new Color(100, 230, 130) : new Color(255, 100, 100);
    label.string = output;
  }
}
