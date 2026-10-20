# Godot -> Cocos 迁移状态

目标版本：Cocos Creator 3.8.8。当前实现采用“模块职责等价迁移”：每个 Godot 生存、战斗和 AI 模块都有对应的 Cocos TypeScript 入口，并通过 `Core/SurvivalDirector.ts` 统一组装。Cocos 版本使用 2D 数据和组件接口，原 Godot 的 3D 场景、模型和资源序列化不直接复制。

## 已搬迁的 Godot 生存模块

| Godot 来源 | Cocos 对应 | 状态 |
|---|---|---|
| `resource_ledger.gd` | `Core/GameState.ts` | 资源账本、容量、事务扣费，并增加 weapon 类型 |
| `inventory_component.gd` | `Survival/Inventory.ts` | 槽位、堆叠、移除、拒绝事件 |
| `backpack.gd` | `Survival/Backpack.ts` | 单兵容量、总容量、转入主账本 |
| `gather_node.gd` | `Resource/ResourceNode.ts` | 周期采集、资源耗尽 |
| `construction_system.gd` | `Survival/Construction.ts` | 配方、成本、位置校验、建造进度 |
| `building_recipe.gd` | `Survival/Construction.ts` | `BuildingRecipe` 和默认四类配方 |
| `building_placement_service_3d.gd` | `Survival/Construction.ts` | 最小位置重叠校验 |
| `production_building.gd` | `Build/Building.ts` | 工人、农场/工厂/医疗周期产出 |
| `durability_component.gd` | `Survival/Durability.ts` | 受损、维修、摧毁、损坏比例 |
| `population_system.gd` | `Survival/Population.ts` | 人口上限、职业、死亡、角色统计 |
| `wave_director.gd` | `Wave/WaveDirector.ts` | 天数、首波日期、强度递增和生成 |
| `enemy_director.gd` | `Enemy/Enemy.ts`、`Combat/CombatDirector.ts` | 单体追击，以及战场注册入口 |
| `survival_economy_3d.gd` | `Survival/Economy.ts` | 击杀点数和消费 |
| `survival_purchase_service_3d.gd` | `Survival/Shop.ts` | 武器、友军、补给购买 |
| `shop_catalog_repository_3d.gd` | `Survival/Shop.ts` | 默认商品目录 |
| `steal_system.gd` | `Survival/StealSystem.ts` | 资源转移、容量回滚、视野发现、警报 |
| `combat_reward_service_3d.gd` | `Survival/Economy.ts` | 击杀奖励入口 |
| `ammo_pickup_3d.gd`、`weapon_pickup_3d.gd` | `Survival/Pickups.ts` | 弹药和武器拾取 |
| `player_squad_command_controller_3d.gd` | `Survival/Allies.ts` | 友军跟随、移动、攻击、驻守指令 |
| `camera_director_3d.gd` | `Survival/CameraDirector.ts` | 等距/第三人称模式、旋转和俯仰数据 |
| `render_pipeline.gd`、像素后处理 | `Survival/RenderPipeline.ts` | 低分辨率、暗角、颗粒和调色配置入口 |
| Holstin 角色适配器 | `Survival/VisualAdapter.ts` | 阵营、姿态和动画帧数据接口 |

## 已搬迁的战斗模块

| Godot 来源 | Cocos 对应 |
|---|---|
| `combat_damage_rules_3d.gd` | `Combat/DamageRules.ts` |
| `health_component_3d.gd` | `Combat/Health.ts` |
| `combat_hitbox_3d.gd` | `Combat/Hitbox.ts` |
| `limb_damage_component_3d.gd` | `Combat/LimbDamage.ts` |
| `battlefield_registry_3d.gd` | `Combat/BattlefieldRegistry.ts` |
| `aim_component.gd` | `Combat/Aim.ts` |
| `concealment_component.gd` | `Combat/Concealment.ts` |
| `injury_component.gd` | `Combat/Injury.ts` |
| `suppression_component_3d.gd` | `Combat/Suppression.ts` |
| `weapon_fire_cycle_3d.gd` | `Combat/WeaponFireCycle.ts` |
| `weapon_catalog_3d.gd` | `Combat/WeaponCatalog.ts` |
| `weapon_feedback_3d.gd` | `Combat/WeaponFeedback.ts` |
| `player_accuracy_component_3d.gd` | `Combat/PlayerBallistics.ts` (`PlayerAccuracy`) |
| `player_ballistics_component_3d.gd` | `Combat/PlayerBallistics.ts` (`PlayerBallistics`) |
| `soldier_3d.gd` | `Combat/Soldier.ts` |
| `combat_contact_3d.gd` | `Combat/Contact.ts` |

## 已搬迁的 AI 模块

| Godot AI 层 | Cocos 对应 |
|---|---|
| 单兵感知 | `AI/Perception.ts` |
| 工作记忆 | `AI/WorkingMemory.ts` |
| 局部威胁场 | `AI/ThreatField.ts` |
| 小队指令 | `AI/Directives.ts` |
| 小队信念状态/快照 | `AI/BeliefState.ts` |
| Utility 战术选择 | `AI/UtilityEvaluator.ts` |
| HTN 任务规划 | `AI/HtnPlanner.ts` |
| 角色分配 | `AI/RoleAllocator.ts` |
| 任务调度 | `AI/TaskScheduler.ts` |
| 单兵状态图 | `AI/SoldierStateChart.ts` |
| 小队协调器 | `AI/SquadCoordinator.ts` |
| Qwen 实验层白名单回退 | `AI/QwenBrain.ts` |
| 决策追踪/调试面板 | `AI/DecisionTrace.ts`、`AI/DecisionPanel.ts` |
| NPC 感知、疲劳、恐慌、职业、HFSM、系统装配 | `AI/NPC.ts` |

## 仍然存在的差异

这些不是“没有迁移入口”，而是原 Godot 的 3D/资源实现没有直接复制：

- Godot 的 3D `Node3D`、`CharacterBody3D`、`NavigationAgent3D`、碰撞体和真实物理，需要换成 Cocos 3D 节点、物理和导航组件。
- `HolstinCharacterVisual3D`、体素建筑、枪械模型、动画、材质、纹理和音频没有自动转换；Cocos 侧已有 `VisualAdapter` 和渲染配置接口。
- `SquadCoordinator` 当前使用简化的 2D 风险和 Utility 规则，HTN/角色/状态机链路已经存在，但没有逐项复刻 Godot 的全部数值和战术动作。
- `QwenBrain` 当前只做合法指令解析和安全回退，不连接外部模型服务。
- Godot 的 `.tscn` 场景、Prefab、测试场景和旧 2D 中世纪分支没有逐文件转成 Cocos Prefab。

## 统一入口

`Core/SurvivalDirector.ts` 创建并更新：

```text
GameState
├── ConstructionSystem
├── PopulationSystem
├── SurvivalEconomy / ShopService
├── StealSystem / Pickups / Allies
├── CameraDirector / RenderPipelineConfigService
├── NpcSystem
└── CombatDirector
    ├── BattlefieldRegistry
    └── SquadCoordinator -> Perception -> Belief -> Utility -> HTN -> StateChart
```

因此，生存、战斗、AI 三个方向的模块入口都已经搬到 Cocos；下一阶段是把这些逻辑接口逐步接到真实 Cocos 3D Prefab、导航、物理和美术资源上。
