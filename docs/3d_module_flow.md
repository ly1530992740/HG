# 3D 程序模块调用流程

## 总体模块调用

```mermaid
flowchart LR
    Scene["3D 场景 / BattlefieldShell3D"]
    Registry["BattlefieldRegistry3D<br/>战场对象注册表"]

    subgraph Player["玩家域 survival3d/player"]
        Input["输入映射"] --> PlayerController["ThirdPersonPlayer3D<br/>移动、姿态、武器状态协调"]
        PlayerController --> Camera["CameraDirector3D<br/>俯视 / 越肩切换"]
        PlayerController --> Accuracy["PlayerAccuracyComponent3D<br/>瞄准、后坐、散布"]
        PlayerController --> Ballistics["PlayerBallisticsComponent3D<br/>射线、命中、曳光弹"]
        PlayerController --> PlayerHealth["HealthComponent3D"]
        PlayerController --> PlayerStamina["StaminaComponent3D"]
    end

    subgraph Squad["小队决策域 ai3d/squad"]
        Coordinator["SquadCoordinator3D<br/>决策周期与任务图"]
        Situation["SquadSituationAnalyzer3D<br/>兵力、血量、敌情"]
        Route["SquadRouteAnalyzer3D<br/>侧路、掩体、暴露度"]
        Rules["SquadRuleDecision3D<br/>确定性规则决策"]
        Qwen["QwenSquadBrain3D<br/>可选总体意图"]
        Directive["SquadDirective3D<br/>单兵/多人命令数据"]

        Coordinator --> Situation
        Coordinator --> Route
        Situation --> Rules
        Route --> Rules
        Rules -->|"默认 / Qwen 失败回退"| Coordinator
        Situation -->|"结构化态势"| Qwen
        Route -->|"候选路线"| Qwen
        Qwen -->|"合法总体意图"| Coordinator
        Coordinator -->|"任务图分阶段派发"| Directive
    end

    subgraph Soldier["单兵执行域 ai3d"]
        Actor["Soldier3D<br/>单兵状态协调"]
        GOAP["GoapAgent<br/>选择当前 Action"]
        Goal["SoldierDirectiveGoal3D"]
        Action["SoldierDirectiveAction3D<br/>移动、掩体、瞄准、射击"]
        Perception["SoldierPerceptionComponent3D"]
        Weapon["SoldierWeaponComponent3D"]
        SoldierHealth["HealthComponent3D"]
        SoldierStamina["StaminaComponent3D"]
        Cover["TacticalCover3D<br/>尺寸、槽位、侧翼路径"]

        Directive --> Actor
        Actor -->|"更新世界状态"| GOAP
        Goal --> GOAP
        GOAP --> Action
        Action --> Actor
        Actor --> Perception
        Actor --> Weapon
        Actor --> SoldierHealth
        Actor --> SoldierStamina
        Action --> Cover
    end

    subgraph Combat["战斗与奖励域"]
        Hitbox["CombatHitbox3D"]
        RewardSignal["death_reward_requested 信号"]
        Reward["CombatRewardService3D"]
        Economy["SurvivalEconomy"]
        AmmoDrop["AmmoPickup3D"]

        Ballistics --> Hitbox
        Weapon --> Hitbox
        Hitbox --> PlayerHealth
        Hitbox --> SoldierHealth
        SoldierHealth --> RewardSignal
        RewardSignal --> Reward
        Reward --> Economy
        Reward --> AmmoDrop
    end

    subgraph Survival["生存模式域 survival3d"]
        Wave["SquadWaveSpawner3D"]
        WaveData["SquadWaveDefinition3D<br/>SquadWaveEntry3D"]
        Prefab["Enemy3D / Ally3D 小队 Prefab"]
        ShopUI["SurvivalShopController3D<br/>商城 UI 协调"]
        Catalog["ShopCatalogRepository3D<br/>读取 JSON"]
        Purchase["SurvivalPurchaseService3D<br/>武器 / 队友交付"]
        Building["BuildingPlacementService3D<br/>预览与放置"]
        AllyCommand["PlayerSquadCommandController3D"]

        WaveData --> Wave
        Wave --> Prefab
        Prefab --> Coordinator
        ShopUI --> Catalog
        ShopUI --> Economy
        ShopUI --> Purchase
        ShopUI --> Building
        Purchase --> Prefab
        AllyCommand -->|"集结并防守"| Coordinator
    end

    Scene --> Registry
    Scene --> PlayerController
    Scene --> Wave
    Scene --> ShopUI
    Registry -.->|"查询战斗单位"| Situation
    Registry -.->|"查询掩体"| Route
    Registry -.->|"查询敌人"| Perception
    Registry -.->|"查询友军小队"| AllyCommand
    Actor --> Registry
    Coordinator --> Registry
    Cover --> Registry
```

实线表示命令或数据流；虚线表示只读查询。`ai3d` 不直接调用积分、商店或掉落物，死亡奖励通过信号跨域传递。

## 一次 AI 决策到执行

```mermaid
sequenceDiagram
    participant C as SquadCoordinator3D
    participant S as SituationAnalyzer
    participant R as RouteAnalyzer
    participant D as Rules / Qwen
    participant U as SquadDirective3D
    participant A as Soldier3D
    participant G as GOAP
    participant X as DirectiveAction

    C->>S: 汇总存活成员、敌情、战力、血量
    C->>R: 分析掩体、侧路、距离与暴露度
    C->>D: 提交结构化态势和候选路线
    alt Qwen 开启且返回合法意图
        D-->>C: AMBUSH / COVER_ATTACK / SUPPRESS_FLANK / ASSAULT
    else Qwen 关闭、超时或输出非法
        D-->>C: 确定性规则方案
    end
    C->>C: 把总体方案展开为分阶段任务图
    C->>U: 为一个或多个成员生成命令
    U->>A: receive_directive
    A->>G: 写入目标和世界状态
    G->>X: 选择当前最低代价 Action
    X->>A: 移动 / 占据掩体 / 瞄准 / 射击
    A-->>C: directive_completed
    C->>C: 全组满足阶段条件后推进下一阶段
```

## 关键边界

| 模块 | 负责 | 不负责 |
| --- | --- | --- |
| `SquadCoordinator3D` | 决策周期、总体战术、分工和执行顺序 | 单帧移动、命中计算、积分发放 |
| `QwenSquadBrain3D` | 从结构化态势选择合法总体意图 | 直接控制士兵坐标或绕过 GOAP |
| `GoapAgent` + `SoldierDirectiveAction3D` | 为当前命令选择和执行动作 | 改变全队总体战术 |
| `BattlefieldRegistry3D` | 提供战斗单位、士兵、小队、掩体查询 | 战术判断 |
| `CombatRewardService3D` | 监听死亡信号并发积分、生成弹药 | AI 死亡逻辑 |
| `SurvivalShopController3D` | UI 状态与购买流程协调 | JSON 解析、具体生成、建筑几何放置 |
