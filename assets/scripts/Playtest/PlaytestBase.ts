// Playtest：可操作场景共用的相机、舞台、文字 HUD 和绘图工具。
import { _decorator, Camera, Canvas, Color, Component, Graphics, Label, Node, UITransform } from 'cc';

const { ccclass } = _decorator;

@ccclass('PlaytestBase')
export class PlaytestBase extends Component {
  protected hud: Label | null = null;
  protected message: Label | null = null;
  protected uiRoot: Node | null = null;
  /** 所有游戏内 2D 物体必须放在 Canvas(RenderRoot2D) 下才会进入 Cocos 的 2D 渲染批次。 */
  protected worldRoot: Node | null = null;

  protected createStage(title: string, help: string): void {
    const cameraNode = new Node('Camera');
    this.node.addChild(cameraNode);
    cameraNode.setPosition(0, 0, 1000);
    const camera = cameraNode.addComponent(Camera);
    camera.projection = Camera.ProjectionType.ORTHO;
    camera.orthoHeight = 270;
    camera.clearColor = new Color(18, 24, 30, 255);

    const canvas = new Node('Canvas');
    this.node.addChild(canvas);
    const canvasComponent = canvas.addComponent(Canvas);
    // Canvas 使用明确的游戏相机，避免预览场景依赖编辑器自动创建的相机。
    canvasComponent.cameraComponent = camera;
    canvasComponent.alignCanvasWithScreen = false;
    camera.orthoHeight = 270;

    this.uiRoot = canvas;
    this.worldRoot = new Node('World');
    canvas.addChild(this.worldRoot);
    const titleNode = new Node('Title');
    canvas.addChild(titleNode);
    titleNode.setPosition(-450, 245);
    const titleLabel = titleNode.addComponent(Label);
    this.sizeLabel(titleLabel, 900, 42, 0, 1);
    titleLabel.fontSize = 22;
    titleLabel.horizontalAlign = Label.HorizontalAlign.LEFT;
    titleLabel.color = new Color(255, 220, 120);
    titleLabel.string = title;

    const helpNode = new Node('Help');
    canvas.addChild(helpNode);
    helpNode.setPosition(-450, -255);
    const helpLabel = helpNode.addComponent(Label);
    this.sizeLabel(helpLabel, 900, 36, 0, 0);
    helpLabel.fontSize = 14;
    helpLabel.horizontalAlign = Label.HorizontalAlign.LEFT;
    helpLabel.color = new Color(190, 205, 215);
    helpLabel.string = help;

    const hudNode = new Node('HUD');
    canvas.addChild(hudNode);
    hudNode.setPosition(-450, 205);
    this.hud = hudNode.addComponent(Label);
    this.sizeLabel(this.hud, 900, 76, 0, 1);
    this.hud.fontSize = 15;
    this.hud.lineHeight = 21;
    this.hud.horizontalAlign = Label.HorizontalAlign.LEFT;
    this.hud.verticalAlign = Label.VerticalAlign.TOP;
    this.hud.color = Color.WHITE;

    const messageNode = new Node('Message');
    canvas.addChild(messageNode);
    messageNode.setPosition(0, 220);
    this.message = messageNode.addComponent(Label);
    this.sizeLabel(this.message, 800, 42, 0.5, 0.5);
    this.message.fontSize = 18;
    this.message.color = new Color(120, 220, 255);
  }

  protected circle(node: Node, color: Color, radius: number): void {
    const graphics = node.addComponent(Graphics);
    graphics.fillColor = color;
    graphics.circle(0, 0, radius);
    graphics.fill();
  }

  protected rectangle(node: Node, color: Color, width: number, height: number): void {
    const graphics = node.addComponent(Graphics);
    graphics.fillColor = color;
    graphics.rect(-width / 2, -height / 2, width, height);
    graphics.fill();
  }

  protected showMessage(text: string): void {
    if (this.message) this.message.string = text;
  }

  /** 设置标签实际绘制区域，避免默认的小尺寸裁掉长文本。 */
  protected sizeLabel(label: Label, width: number, height: number, anchorX: number, anchorY: number): void {
    const transform = label.getComponent(UITransform)!;
    transform.setContentSize(width, height);
    transform.setAnchorPoint(anchorX, anchorY);
  }
}
