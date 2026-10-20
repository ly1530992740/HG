# Cocos 核心代码框架

这份文档描述 `cocos_project/assets/scripts` 的职责边界和数据流。代码按“谁负责什么”分组，避免把 Godot 原项目的场景、AI 和渲染依赖重新带入核心玩法。

## 代码框架图

```mermaid
flowchart LR
    Input[键盘输入\nWASD / E / B / SPACE] --> Player[Player\n移动与射击]
    Player -->|消耗弹药| State[GameState\n资源 / 天数 / 人口 / 分数]
    Player -->|命中| Enemy[Enemy\n追击与受伤]

    Resource[ResourceNode\n采集点] -->|E 采集| State
    Build[Building\n农场 / 工厂 / 医疗] -->|周期产出| State
    State -->|状态事件| HUD[HudView\n资源与事件显示]

    State --> Wave[WaveDirector\n按天数推进]
    Wave -->|生成| Enemy
    Enemy -->|攻击人口| State

    State --> Survival[SurvivalDirector\n生存服务组合根]
    Survival --> Inventory[Inventory / Backpack]
    Survival --> Construction[Construction / Durability / Population]
    Survival --> Shop[Economy / Shop / Pickups / Allies]
    Survival --> NPC[NPC HFSM\n疲劳 / 恐慌 / 工作]

    Enemy --> Combat[CombatDirector\nDamage / Health / Soldier]
    Combat --> Squad[SquadCoordinator\nPerception -> Belief -> Utility -> HTN]
    Squad --> StateChart[SoldierStateChart\nIdle / Order / Survival / Dead]

    Root[GameRoot\n场景装配器] --> State
    Root --> Player
    Root --> Resource
    Root --> Build
    Root --> Wave
    Root --> HUD
    Root --> Survival
    Root --> Combat
```

### 一次完整交互

```mermaid
sequenceDiagram
    participant User as 玩家
    participant Root as GameRoot
    participant Node as ResourceNode
    participant State as GameState
    participant Hud as HudView

    User->>Root: 按 E
    Root->>Node: canGather()
    Node->>State: add(resourceType, amount)
    loop 每帧刷新
        Root->>Hud: setStatus(state)
    end
    Root->>Hud: showMessage(采集结果)
```

## 分类思维导图

```mermaid
mindmap
  root((Cocos 核心玩法))
    Core
      GameState
        资源账本
        人口
        天数
        分数
        EventTarget 事件
      GameRoot
        创建场景对象
        连接输入
        组装组件
    Player
      WASD 移动
      SPACE 射击
      弹药消耗
      最近目标命中
    Enemy
      追击玩家
      距离攻击
      受伤与死亡
      击杀奖励
    Build
      Farm
        生产食物
      Factory
        生产弹药
      Medical
        生产医疗
      工人分配
    Resource
      资源类型
        Food
        Ammo
        Material
        Medical
      周期采集
      库存耗尽
    Wave
      天数计时
      首波日期
      波次强度
      敌人生成
    HUD
      资源状态
      天数与分数
      操作提示
      事件消息
```

## 依赖规则

1. `GameState` 是资源、人口、天数和分数的权威状态；资源、建筑和敌人不直接互相修改库存。
2. `Player`、`ResourceNode`、`Building`、`Enemy`、`WaveDirector` 属于玩法层，只依赖 `Core/GameState` 或自己的领域组件。
3. `HUD/HudView` 只读取状态并显示文字，不参与资源扣除、生产或伤害计算。
4. `Core/GameRoot` 可以依赖所有模块，因为它是启动场景的组装层；其他模块不应反向依赖 `GameRoot`。

## 扩展顺序

先在现有模块内补数值和测试，再增加 Prefab 与美术资源；新增系统时按同样规则创建目录，并通过 `GameState.events` 连接跨模块通知。复杂小队 AI、3D 模型和旧中世纪分支属于后续独立模块，不放回核心目录。
