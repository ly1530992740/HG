# Cocos 代码引用关系

图中箭头方向表示“左侧模块引用右侧模块”。例如 `GameRoot -> Player` 表示 `Core/GameRoot.ts` 通过 import 使用 `Player/Player.ts`。

## 1. TypeScript Import 关系

```mermaid
flowchart LR
  subgraph Core[Core 核心层]
    Root[Core/GameRoot.ts]
    State[Core/GameState.ts]
    Director[Core/SurvivalDirector.ts]
  end

  subgraph Gameplay[玩法入口]
    Player[Player/Player.ts]
    Enemy[Enemy/Enemy.ts]
    Resource[Resource/ResourceNode.ts]
    Build[Build/Building.ts]
    Wave[Wave/WaveDirector.ts]
    HUD[HUD/HudView.ts]
    Crosshair[HUD/WeaponCrosshair.ts]
  end

  subgraph Survival[Survival 生存模块]
    Inventory[Survival/Inventory.ts]
    Backpack[Survival/Backpack.ts]
    Construction[Survival/Construction.ts]
    Durability[Survival/Durability.ts]
    Population[Survival/Population.ts]
    Economy[Survival/Economy.ts]
    Shop[Survival/Shop.ts]
    Steal[Survival/StealSystem.ts]
    Pickups[Survival/Pickups.ts]
    Allies[Survival/Allies.ts]
    Camera[Survival/CameraDirector.ts]
    Render[Survival/RenderPipeline.ts]
    Visual[Survival/VisualAdapter.ts]
  end

  subgraph Combat[Combat 战斗模块]
    CombatDirector[Combat/CombatDirector.ts]
    Registry[Combat/BattlefieldRegistry.ts]
    Soldier[Combat/Soldier.ts]
    Damage[Combat/DamageRules.ts]
    Health[Combat/Health.ts]
    Hitbox[Combat/Hitbox.ts]
    Limb[Combat/LimbDamage.ts]
    Aim[Combat/Aim.ts]
    Injury[Combat/Injury.ts]
    Concealment[Combat/Concealment.ts]
    Suppression[Combat/Suppression.ts]
    WeaponCycle[Combat/WeaponFireCycle.ts]
    WeaponCatalog[Combat/WeaponCatalog.ts]
    WeaponFeedback[Combat/WeaponFeedback.ts]
    Ballistics[Combat/PlayerBallistics.ts]
    Contact[Combat/Contact.ts]
  end

  subgraph AI[AI 决策模块]
    Perception[AI/Perception.ts]
    Memory[AI/WorkingMemory.ts]
    Threat[AI/ThreatField.ts]
    Belief[AI/BeliefState.ts]
    Utility[AI/UtilityEvaluator.ts]
    Directives[AI/Directives.ts]
    HTN[AI/HtnPlanner.ts]
    Roles[AI/RoleAllocator.ts]
    Tasks[AI/TaskScheduler.ts]
    Chart[AI/SoldierStateChart.ts]
    Squad[AI/SquadCoordinator.ts]
    NPC[AI/NPC.ts]
    Qwen[AI/QwenBrain.ts]
    Trace[AI/DecisionTrace.ts]
    Panel[AI/DecisionPanel.ts]
  end

  Root --> State
  Root --> Director
  Root --> Player
  Root --> Resource
  Root --> Build
  Root --> Wave
  Root --> HUD
  Root --> Crosshair

  Player --> State
  Player --> Enemy
  Enemy --> State
  Resource --> State
  Build --> State
  Wave --> State
  Wave --> Enemy
  HUD --> State

  Director --> State
  Director --> Construction
  Director --> Population
  Director --> Economy
  Director --> Shop
  Director --> Steal
  Director --> Allies
  Director --> Camera
  Director --> Render
  Director --> NPC
  Director --> CombatDirector
  Construction --> State
  Backpack --> State
  Shop --> Economy
  Steal --> State
  Pickups --> State

  CombatDirector --> State
  CombatDirector --> Registry
  CombatDirector --> Soldier
  CombatDirector --> Squad
  Soldier --> State
  Soldier --> Backpack
  Soldier --> Registry
  Soldier --> Damage
  Soldier --> Health
  Soldier --> Limb
  Soldier --> Aim
  Soldier --> Injury
  Soldier --> Suppression
  Soldier --> WeaponCycle
  Hitbox --> Damage
  WeaponCatalog --> WeaponCycle
  Ballistics --> Aim
  Contact --> Soldier

  Squad --> Soldier
  Squad --> Registry
  Squad --> Perception
  Squad --> Memory
  Squad --> Threat
  Squad --> Belief
  Squad --> Utility
  Squad --> Directives
  Squad --> HTN
  Squad --> Roles
  Squad --> Tasks
  Squad --> Chart
  Perception --> Registry
  Perception --> Contact
  Perception --> Soldier
  Belief --> Memory
  Threat --> Memory
  Utility --> Belief
  HTN --> Directives
  Tasks --> HTN
  Chart --> Soldier
  Qwen --> Directives
  Panel --> Trace
```

## 2. 运行时调用关系

```mermaid
sequenceDiagram
  participant Scene as Main.scene
  participant Root as GameRoot
  participant State as GameState
  participant Survival as SurvivalDirector
  participant Player as Player
  participant Wave as WaveDirector
  participant Enemy as Enemy
  participant Combat as CombatDirector
  participant Squad as SquadCoordinator
  participant HUD as HudView

  Scene->>Root: onLoad()
  Root->>State: addComponent / 获取唯一状态
  Root->>Survival: 创建生存、战斗、AI 服务
  Root->>Player: configure(State, RootNode)
  Root->>Wave: configure(State, RootNode)

  loop 每帧
    Root->>HUD: setStatus(State)
    Survival->>Survival: update construction / NPC / combat
    Wave->>State: 推进天数
  end

  Player->>State: spend({ ammo: 1 })
  Player->>Enemy: hit(damage)
  Enemy->>State: damagePopulation()

  Wave->>Enemy: spawnWave()
  Combat->>Squad: update(delta)
  Squad->>Squad: perception -> memory -> belief
  Squad->>Squad: Utility -> HTN -> directive
  Squad->>Player: 或敌方 Soldier 执行指令
```

## 3. 事件和数据所有权

```mermaid
flowchart TB
  State[(GameState 唯一状态源)]
  State -->|resources-changed| HUD[HudView]
  State -->|population-changed| NPC[NpcSystem / HUD]
  State -->|day-changed| Wave[WaveDirector]
  State -->|soldier-died| Economy[SurvivalEconomy]

  Resource[ResourceNode] -->|add| State
  Building[Building] -->|add 生产资源| State
  Shop[ShopService] -->|购买结果| Economy
  Steal[StealSystem] -->|remove/add 原子转移| State
  Soldier[Soldier] -->|受伤/死亡事件| Combat[CombatDirector]
  Perception[SoldierPerception] -->|contact-spotted| Squad[SquadCoordinator]
  Squad -->|SquadDirective| Chart[SoldierStateChart]
  Chart -->|state-changed| Debug[DecisionPanel / HUD]
```

## 4. 依赖边界

- `Core/GameState` 不依赖业务模块，是资源、人口、天数和分数的权威来源。
- `Core/GameRoot` 和 `Core/SurvivalDirector` 可以依赖所有模块，负责装配和驱动。
- `Player`、`Enemy`、`ResourceNode`、`Building`、`WaveDirector` 是场景玩法入口。
- `Survival` 负责经营系统；`Combat` 负责战斗规则和战斗实体；`AI` 负责感知、规划和指令。
- `HUD` 只能读取状态和事件，不应直接扣资源或修改敌人生命。
- `AI/QwenBrain` 只能生成经过白名单校验的 `SquadDirective`，不能直接访问场景或资源账本。
