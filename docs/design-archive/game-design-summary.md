# HG 项目总结 — 游戏设计讨论版

> 用途：给游戏设计讨论的"现状底稿"。整理自代码结构与 `docs/` 各文档，日期 2026-08-05。
> 阅读顺序：项目定位 → 玩法循环 → 系统全景 → 资产现状 → 已拍板的设计决策 → **待讨论问题（核心）**。

---

## 一、项目定位

**Godot 4.7 · 3D 二战战术生存防守游戏**（Holstin 暗黑油画风格）：

- 第三人称玩家持枪，抵御**多波敌军 AI 小队**（侦察/步枪/突击/重火力）。
- 敌军小队**自主决策**：感知 → 信念 → 影响图 → Utility/HTN → 计划 → 单兵执行，而非脚本刷怪。
- 玩家一侧经营生存基地：采集 → 建造 → 生产 → 防守，形成**生存循环**。
- 项目还保留了 2D 中世纪策略原型（资源 + 建造 + 哥布林波次）作为**遗留分支**（已不参与主玩法）。

---

## 二、核心玩法循环

```
        ┌──────────────────────────────────────────────────┐
        │                                                  ▼
   白天：采集/建造/生产/分配人口/商店消费 ←── 资源账本（单一数据源）
        │                                                  │
        │  WaveDirector 按"天数"预告波次                    │
        ▼                                                  │
   夜间：敌军小队波次进攻（SquadWaveSpawner 环形刷怪）         │
        │                                                  │
        │  单兵感知→小队决策→压制/包抄/突击/潜入偷取           │
        ▼                                                  │
   战斗结算：击杀奖励点数 → 商店购买武器/友军/补给 ────────────┘
```

**两条玩法线**：
1. **经营线**（白天）：资源账本 → 采集点 / 生产建筑 / 点数经济三条来源 → 建造系统（预览→校验→扣费→动画）→ 防御建筑与仓库。
2. **战斗线**（夜间）：波次 → AI 小队三通道决策（高级战术 / 规则 / 实验性 Qwen）→ 单兵状态图执行 → 压制与生存打断。

---

## 三、系统模块全景（代码已落地）

### 3.1 生存经营模块（`survival3d/holstin/` — 交接手册 12 章全部实现）

| # | 模块 | 文件 | 状态 |
|---|------|------|------|
| 1 | 资源账本（5 资源/上限/原子事务） | `resource_ledger.gd` | ✅ 已实现 |
| 2 | 背包/仓库（槽位堆叠） | `inventory_component.gd` | ✅ 已实现 |
| 3 | 采集点（周期产出/耗尽/工具翻倍） | `gather_node.gd` | ✅ 已实现 |
| 4 | 建造系统（预览→校验→扣费→动画） | `construction_system.gd` + `building_recipe.gd` + `building_placement_service_3d.gd` | ✅ 已实现 |
| 5 | 生产建筑（农场/工厂/医疗，3 段生长） | `production_building.gd` | ✅ 已实现 |
| 6 | 耐久/维修 | `durability_component.gd` | ✅ 已实现 |
| 7 | 人口/职业转换 | `population_system.gd` | ✅ 已实现 |
| 8 | 玩家控制（指令系统） | `player_controller.gd` + `third_person_player_3d.gd` + `camera_director_3d.gd` | ✅ 已实现 |
| 9 | 天数波次导演 | `wave_director.gd` + `squad_wave_spawner_3d.gd` | ✅ 已实现 |
| 10 | 敌人 AI 大脑 | `enemy_director.gd` | ✅ 已实现 |
| 11 | 渲染管线（低分辨率后处理） | `render_pipeline.gd` + `render/shaders/` | ✅ 已实现 |
| 12 | 潜入偷取 | `steal_system.gd` | ✅ 已实现 |

### 3.2 战斗与三层 AI（`ai3d/` + `combat3d/`）

**决策链路**：`SoldierPerceptionComponent3D`（感知）→ `SquadBeliefState3D`（信念）→ `SquadDecisionSnapshot3D`（快照）→ `SquadInfluenceMap3D`（影响图）→ `SquadUtilityEvaluator3D`（18 种战术候选打分）→ `SquadHtnPlanner3D`（HTN 任务图）→ `SquadRoleAllocator3D`（角色分配）→ `SquadTaskScheduler3D`（调度）→ `SquadDirectiveDispatcher3D`（分发）→ `SoldierStateChart3D`（单兵执行）。

| 层 | 实现 | 说明 |
|----|------|------|
| 单兵 | `soldier_3d.gd` + `soldier_state_chart_3d.gd` | DEAD / SURVIVAL_OVERRIDE / EXECUTE_ORDER / IDLE_SECURITY；被压制保存指令、危险下降恢复 |
| 小队 | `squad_coordinator_3d.gd` + `squad_advanced_tactics_3d.gd` 等 30+ 文件 | 三通道：高级战术（正式）/ 规则（GUARD/AMBUSH/COVER_ATTACK/SUPPRESS_FLANK/ASSAULT）/ Qwen（实验性，白名单校验，非法回退） |
| NPC（非战斗人员） | `ai3d/npc/` 12 文件：`villager_hfsm.gd` + 感知/恐慌传染/疲劳/医疗/工位分配 + `npc_system.gd` 装配器 | ✅ 已实现并通过验收（`tests/npc_v2/`，14 项 PASS：掩体容量/主动感知/恐慌传染/免疫） |

**武器系统**：`WeaponFireCycle3D`（射击节奏：栓动步枪/SMG/LMG/手枪/霰弹枪）+ `survival3d/weapons/`（`weapon_catalog_3d` 目录 / `weapon_model_factory_3d` 模型工厂 / `weapon_feedback_3d` 反馈）。

**其他战斗组件**：`combat3d/`（伤害规则、命中盒、战场注册表）、`combat/`（瞄准/隐蔽/受伤）、压制系统、火力优势评估。

### 3.3 经济 / 商店 / UI（`survival3d/`）

- `economy/survival_economy_3d.gd`：点数经济（击杀奖励 + 商店扣点）。
- `shop/survival_purchase_service_3d.gd`：商店购买（武器/友军/补给落地）。
- `rewards/combat_reward_service_3d.gd`：战斗奖励回流。
- `ui/`：`battle_hud_3d`（HUD）、`weapon_spread_crosshair_3d`（扩散准星）、`qwen_debug_panel_3d`（LLM 调试面板）。
- `allies/player_squad_command_controller_3d.gd`：玩家指挥友军小队。

### 3.4 渲染与资产层（`render/` + `combat3d/`，纯代码生成，7 大入口）

| 入口 | 内容 |
|------|------|
| `HolstinCharacterVisual3D` | 3D 角色 + 11 姿态动画（IDLE/WALK/AIM/FIRE/RELOAD/DEATH/WORK_*/RESCUE/CARRY） |
| `VoxelBuildingGenerator` | 9 种建筑/采集点（体素，0.5m 粒度） |
| `BuildingAnimation` | 建造升起/受损冒烟/生长分阶/仓库存量 |
| `CombatEffects2D` | 血迹/枪火/5 资源图标 |
| `HolstinPalette` | 全局配色（改色不改模型） |
| `HolstinCameraController` | 等距 + 越肩 TPS 双视角 |
| `HolstinPixelSprites` | 2D 像素贴片（顶视 16 方向 + 肩后动画集） |

外加 `HolstinSoldierAdapter`（模型替换适配器，兼容旧 API 签名）。

### 3.5 AI 生成资产（2026-08-04 ~ 08-05）

- **3D 模型**（混元3D API，4/4 成功）：士兵、碉堡、沙袋掩体、中正式步枪（GLB + OBJ）。
- **TPS 2D 动画**（AI 生图 + Python 去背景）：Idle 4 帧 / Fire 7 帧 / Reload 7 帧，最终版 `frames_alpha/` 为真正 RGBA 透明底（含 Fire v3 侧视版）。
- **NPC 图标**：64×64 strip（斧/锄/感叹号）。

---

## 四、已拍板的设计决策（避免重复讨论）

1. **资产与程序分离**：程序 AI 只调 7 个资产入口，不碰模型/动画/配色数值。
2. **模型替换用适配器**（`HolstinSoldierAdapter`），玩家/AI 战斗代码零改动。
3. **AI 决策分三层**：单兵状态图（生存本能）→ 小队 Utility/HTN（战术）→ NPC HFSM（非战斗人员）。
4. **Qwen LLM 仅实验性**：正式战斗预置与波次强制关闭，输出白名单校验。
5. **压制是个人状态**，小队火力优劣单独聚合；射击节奏统一由 `WeaponFireCycle3D` 管理。
6. **资源账本是单一数据源**：所有增减/校验/支付必经账本，容量上限 200。
7. **视觉风格**：Holstin 暗黑油画风，低分辨率 SubViewport + 后处理（暗角/颗粒/调色）。
8. **路径规划强制走热图**（`SquadHeatmapRoutePlanner3D`）：局部转向只做短物理绕行，不可绕过热图路线。

---

## 五、待讨论问题（设计讨论焦点）

> 按优先级排序，是本次讨论的核心内容。

1. **NPC 行为 HFSM v2 已落地，但"生活感"是否达到设计目标？**
   核心代码已实现并通过 14 项自动验收（主动感知、恐慌传染、免疫、掩体容量等），
   但完整流程（与 GatherNode/WaveDirector 的手动场景串测、人工 15 分钟流程）待补。
   → 决策点：恐慌传染对防守压力的影响是否符合预期？NPC 巡逻/作息节奏如何与波次配合？

2. **数值体系全面占位**：12 个模块的 `storage_capacity / yield / cost / build_time / cycle_time / max_population / first_wave_day` 等全是 `[PLACEHOLDER]`。
   → 决策点：经济曲线怎么定？采集/生产/点数三条来源各占多少权重？一局多少天、几波、胜利条件是什么？

3. **波次节奏衔接**：`WaveDirector`（按天数）与 `SquadWaveSpawner3D`（环形刷怪、注入任务目标）如何配合？首波在哪一天、强度曲线形状？

4. **潜入偷取的玩法定位**：正面防守是主线，`StealSystem`（潜行接近→偷资源→被发现风险）是"软攻击"。它服务于什么目标——资源补充？侦察？惩罚纵深防御？

5. **队伍构成与指挥深度**：玩家可以指挥友军小队（`PlayerSquadCommandController3D`），指令粒度到哪一层（移动/攻击/占位）？是否与敌方 AI 用同一套战术管线？

6. **武器成长线**：商店购买的武器如何与 `WeaponFireCycle3D` 枪族联动？玩家武器池多大、数值差异怎么设计（伤害/射速/后座/扩散）？

7. **渲染管线性能取舍**：320×180 低分辨率 + 后处理是风格核心，但百人同屏（交接手册性能目标）下能否扛住？降质策略？

8. **2D 遗留分支去留**：`buildings/`、`Main/`、`global.gd` 等 2D 中世纪系统不再被 3D 使用——保留（可挖素材）还是清理（降低维护噪音）？

---

## 六、文档索引

> 项目文档已精简为两份手册（2026-08-10）：本文档负责**玩法/设计讨论**，`programmer_handoff.md` 负责**程序实现交接**。其余过程性文档（QA 报告、资产交接、AI 生态总结、架构图等）已归档删除，如有需要可从回收站恢复。

| 文档 | 内容 |
|------|------|
| `docs/game_design_summary.md` | **本文档**：设计讨论底稿 |
| `docs/programmer_handoff.md` | 程序交接手册（12 模块规格 + 验收标准 + 模型替换清单） |
