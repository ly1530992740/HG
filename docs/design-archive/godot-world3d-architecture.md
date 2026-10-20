# world3d 敌人 AI 大世界 — 模块架构与事件协议

> 版本：v3.0 ｜ 日期：2026-08-08 ｜ 作者：eng-lead（程基岩）
> 范围：`world3d/` 功能模块 + `world3d/defense_slot_3d.gd` + `world3d/sandbox/` 沙盒 + `tests/world3d/` 十二链路验收
> 关联：`game_design_doc.md` §4.1 AI 生态系统 / §4.2 威胁值 / §4.3 辎重补给线 / §4.4 玩家游击队战术手段 / §4.5 占领解放区 / §4.6 经济系统
> 迭代三增量：沙盒 V2 全面整改（面板不挡点选/全指令）+ 阵地扩展（铁丝网/玩家预设防线/兵力重建）+ 玩法铺全（偷袭/破坏通信/驻守/解放区自产/缴获经济）+ 县城手动指令（绕过评估）

---

## 1. 设计总纲

### 1.1 一句话
敌人 AI 大世界 = **1 个县城唯一决策中枢 + N 个村落领主（只感知上报执行）+ 1 条辎重固定路线 + 1 个威胁值总开关**，全部通过 `WorldRegistry3D` 事件总线解耦，规则涌现、无脚本演出。

### 1.2 依赖方向（唯一允许的引用关系）

```
                ┌────────────────────────────────────────────┐
                │            WorldRegistry3D                 │
                │  实体登记表  +  事件总线（唯一通信通道）        │
                └───────▲───────────────────▲───────────────┘
                        │ 只经总线收发消息     │ 只向总线登记/查询
        ┌───────────────┴───────┐   ┌───────┴────────────────┐
        │ 业务模块（互相零引用）   │   │ 实体（登记进 registry）   │
        │ CountySeatCommanderAI  │   │ CountySeatEntity3D     │
        │ VillageLordAI (HFSM)   │   │ VillageEntity3D        │
        │ ThreatLevelSystem      │   │ RoutePath3D           │
        │ SupplyConvoy3D         │   │ SupplyConvoy3D         │
        └────────────────────────┘   └────────────────────────┘
                        ▲
        ┌───────────────┴───────────────────────────────┐
        │ WorldDirector3D（装配器：接线 + 执行县城指令）    │
        │ 唯一允许 new 业务模块的地方；注入 route/数据依赖   │
        └───────────────────────────────────────────────┘
```

**铁律（grep 可验证）**：
- `world3d/` 内业务模块的实例化点：`world_director_3d.gd` 是唯一装配器（生成 `SupplyConvoy3D`、实例化 ai3d 小队预制体、执行 build_defense）。
- 业务模块互相**不持有节点引用**，一律通过 `WorldRegistry3D.find(get_tree())` 拿总线、经 `publish_*` / 信号收发消息。
- 例外说明：`SupplyConvoy3D` 持有的 `route` 是**装配器注入的数据依赖**（非模块间消息）；`VillageLordAI3D` 持有自己的 `village`（实体归属）、`CountySeatCommanderAI3D` 持有自己的 `county`（实体归属）、`DefenseSlot3D` 是村落实体子节点（组件归属），属"组件-宿主"关系而非模块耦合。
- 装配器职责：迭代二起 ai3d 小队（守军/护卫/增援/攻打部队）的实例化全部由 `WorldDirector3D` 完成，`VillageEntity3D`/`SupplyConvoy3D` 只暴露挂点（`garrison_root`/`escort_root`）与状态，不实例化小队。

### 1.3 装配器唯一直连的信号（依赖注入）
特征模块之间有几处"信号→方法"的跨模块接线，**只能由装配器完成**（模块自身不引用对方）：
| 装配器接线 | 说明 |
|---|---|
| `calendar.settlement_tick → threat.decay(1.0)` | 每日威胁衰减 |
| `calendar.settlement_tick → commander.on_daily_tick(day)` | 县城每日决策节拍（重试 pending 辎重） |
| `threat.tier_changed → commander.apply_threat_tier(tier)` | 威胁档位驱动县城决策强度（V3 链路） |
| `threat.tier_changed → 各领主.notify_threat_tier(tier)` | 威胁档位注入村落领主（防御评估感知"有威胁"，V4 链路） |

---

## 2. 事件协议（三种消息字段定义）

所有消息为 Dictionary，`type` 字段路由。**禁止模块间直发自定义消息类型**，必须走三种之一。

### 2.1 ReportMessage（村落 → 县城 上报）
| 字段 | 类型 | 说明 |
|---|---|---|
| `type` | `&"report"` | 固定 |
| `from_id` | String | 上报方（村落/辎重队 entity_id） |
| `to_id` | String | 接收方（`"county_seat"` 或目标村落） |
| `report_kind` | StringName | `resource_shortage` / `under_attack` / `supply_delivered` |
| `payload` | Dictionary | 见下表 |

| report_kind | payload 字段 |
|---|---|
| `resource_shortage` | `summary: {res: {amount, threshold, need}}` |
| `under_attack` | `garrison_count: int` |
| `supply_delivered` | `convoy_id: String, cargo: Dictionary` |
| `request_defense_build` | `slot_type: int, slot_index: int, cost: Dictionary`（村落→县城 阵地建造请求） |
| `defense_request_rejected` | `reason: String`（县城→村落 拒绝回执，观察/日志用） |

### 2.2 CommandMessage（县城 → 村落 指令）
| 字段 | 类型 | 说明 |
|---|---|---|
| `type` | `&"command"` | 固定 |
| `from_id` | String | 县城 entity_id |
| `to_id` | String | 目标村落 entity_id |
| `command` | StringName | `send_supply` / `reinforce` / `abandon` |
| `payload` | Dictionary | 见下表 |

| command | payload 字段 | 谁执行 |
|---|---|---|
| `send_supply` | `convoy_id, cargo, route_id, target_village_id` | **WorldDirector3D** 生成辎重队（含真实护卫小队） |
| `reinforce` | `squad_size, from_county_id` | **WorldDirector3D** 生成真实 Enemy3D 增援小队 + **领主** 进入守军死战 |
| `abandon` | `reason` | **领主** 弃村撤退 |
| `build_defense` | `slot_index, slot_type, cost` | **WorldDirector3D** 驱动村落槽位 EMPTY→BUILDING→BUILT（县城已在 Commander 侧扣费） |

### 2.3 BehaviorEvent（玩家行为 → 系统）
| 字段 | 类型 | 说明 |
|---|---|---|
| `type` | `&"behavior"` | 固定 |
| `from_id` | String | 行为主体（`"player"`） |
| `event` | StringName | `looted_convoy` / `attacked_village` / `occupied_village` / `destroyed_comm` / `killed_japanese` |
| `payload` | Dictionary | `village_id` / `convoy_id` 等 |

| event | payload | 谁订阅 |
|---|---|---|
| `attacked_village` | `village_id` | 目标村落领主（置感知标志→上报）；**其他村落领主**（邻近被攻→警觉窗口，防御评估） |
| `looted_convoy` | `convoy_id` | 目标辎重队（销毁）+ 威胁系统（+权重）+ 沙盒玩家经济（缴获入账） |
| `raided_village` | `village_id, stolen` | 威胁系统（+权重）；沙盒 UI 先扣村落资源再发布（偷袭偷资源，§4.4） |
| `destroyed_comm` | `village_id` | 威胁系统（+权重）；村落 CommPlaceholder 置 destroyed（上报延迟机制下轮） |
| `manual_defense_request` | `village_id, slot_index` | 目标村落领主（→ 转 request_defense_build 上报） |
| 其余 | 视后续接入 | 威胁系统（+权重） |

### 2.4 威胁值权重（ThreatLevelSystem3D.behavior_weights）
| 事件 | 权重 |
|---|---|
| `looted_convoy` | +20 |
| `occupied_village` | +25 |
| `attacked_village` | +10 |
| `raided_village` | +8 |
| `destroyed_comm` | +5 |
| `killed_japanese` | +1 |

档位阈值 `tier_thresholds = [25, 60, 100]` → 0★隐匿(<25) / 2★警戒(<60) / 3★围剿(<100) / 4★决战(≥100)。

---

## 3. 模块清单与单一职责

| # | 模块 | 文件 | 职责（单一） |
|---|---|---|---|
| 1 | WorldRegistry3D | `world_registry_3d.gd` | 实体登记/查询 + 事件总线（唯一通信通道） |
| 2 | GameCalendar3D | `game_calendar_3d.gd` | 日/小时推进 + 每日结算节拍（day_length_seconds @export，沙盒时间加速改此值） |
| 3 | CountySeatEntity3D | `county_seat_entity_3d.gd` | 县城资产：账本 + 兵力池 + 被占标记 |
| 4 | CountySeatCommanderAI3D | `county_commander_ai_3d.gd` | 县城唯一决策：上报→打分→发指令（含阵地建造批准/拒绝；`get_route_to` 供手动发辎重） |
| 5 | VillageEntity3D | `village_entity_3d.gd` | 村落状态机（合法迁移表）+ **owner（PUPPET/JAPANESE/PLAYER）** + 账本 + 守军挂点 + **通信破坏状态** + 防御槽位（8 槽） + **生产建筑挂点** |
| 6 | VillageLordAI3D | `village_lord_ai_3d.gd` | 领主 HFSM（godot_state_charts）：感知上报 + 执行指令 + 防御评估；玩家村落不生成领主 |
| 7 | ThreatLevelSystem3D | `threat_level_system_3d.gd` | 威胁值增长/衰减/档位/档位广播（含 raided_village 权重） |
| 8 | SupplyConvoy3D | `supply_convoy_3d.gd` | 辎重内容 + waypoint 移动 + 送达结算 + 被打劫销毁 |
| 9 | RoutePath3D | `route_path_3d.gd` | 路线数据 + 采样 API + 编辑器可视化（Path3D 薄封装） |
| 10 | WorldDirector3D | `world_director_3d.gd` | 装配接线 + 执行县城指令 + AI 小队装配（守军/护卫/增援/攻打）+ **rebuild_garrison 兵力重建** |
| 11 | DefenseSlot3D | `defense_slot_3d.gd` | 村落防御阵地槽位状态机（EMPTY/BUILDING/BUILT/DESTROYED）+ 占位视觉（含铁丝网） |
| 12 | SandboxConfig | `sandbox/sandbox_config.gd` | 沙盒配置资源（县城/村落/路线/威胁/数值；.tres 多套可换） |
| 13 | SandboxVillageConfig | `sandbox/sandbox_village_config.gd` | 单村配置（含 owner 与槽位初始 build_state） |
| 14 | FlyCamera3D | `sandbox/fly_camera_3d.gd` | 沙盒自由飞行相机（观察视角，无玩家角色） |
| 15 | SandboxUIPanel | `sandbox/sandbox_ui_panel.gd` | 沙盒指令面板 + 观察区（可折叠/拖动/半透明；全指令按钮；玩家资源 HUD） |
| 16 | SandboxPlayerEconomy | `sandbox/sandbox_player_economy.gd` | 沙盒玩家资源账本（缴获入账 / 解放奖励；武器医疗只进不出） |
| 17 | SandboxVillageProduction | `sandbox/sandbox_village_production.gd` | 解放区自产装配（复用 ProductionBuilding，产出入村落账本） |

---

## 4. 三链路消息时序

### 4.1 V1 辎重补给链路
```
VillageLord(伪军村)  GameCalendar   WorldRegistry3D  CommanderAI   Director   SupplyConvoy
      │                  │                │               │            │           │
      │ 感知 food<阈值     │                │               │            │           │
      │──send_event──→(HFSM→ShortageWait) │               │            │           │
      │──publish_report(resource_shortage)→│               │            │           │
      │                  │                │──report_received→│            │           │
      │                  │                │               │─评估(账本/状态)│           │
      │                  │                │               │─publish_command(send_supply)│
      │                  │                │←command_received───────────────│           │
      │                  │                │               │            │─SupplyConvoy3D.new()
      │                  │                │               │            │─set route/cargo
      │                  │                │               │            │─add_child(辎重)
      │                  │                │               │            │           │
      │                  │                │               │            │ 沿 Path3D 移动(progress 0→1)
      │                  │                │               │            │──delivery_completed──→│
      │                  │                │←publish_report(supply_delivered)──────────│
      │←report_received(supply_delivered)  │               │            │           │
      │ 账本 add_resource(cargo)           │               │            │           │
      │──send_event(supply_resolved)→Idle  │               │            │ queue_free
```

### 4.2 V2 攻打→增援 / V2b 攻打→弃村
```
玩家行为           WorldRegistry3D   VillageLord(日军村)  CommanderAI   Director
   │──publish_behavior(attacked_village, {village_id})──→│
   │                  │──behavior_event_received→│(_attacked=true)
   │                  │←感知→send_event(attacked)→(HFSM→UnderAttack)
   │                  │←publish_report(under_attack)──→│
   │                  │                │──report_received→│
   │                  │                │               │─_score_village() ≥ reinforce_threshold
   │                  │                │               │─publish_command(reinforce)
   │                  │←command_received───────────────│
   │                  │←command_received→│(send_event command_reinforce→FightToDeath)
   │                  │  守军死战：village→BESIEGED      │──spawn ReinforceSquad→
   │（V2b 低价值村：score < abandon_threshold → publish_command(abandon)
   │  → 领主 send_event command_abandon → Retreat → village→LIBERATED）
```

### 4.3 V3 威胁值档位链路
```
玩家行为(劫辎重) → WorldRegistry3D.behavior_event_received
   ├─→ ThreatLevelSystem3D.add_threat(+20)
   │      └─ tier_changed(0→1) ──(Director 接线)──→ Commander.apply_threat_tier(1)
   │             → decision_intensity 1.0→1.5（决策强度可观测）
   └─→ SupplyConvoy3D（convoy_id 匹配）→ mark_looted → convoy_destroyed → Director 收口
每日结算：GameCalendar3D.settlement_tick ──(Director 接线)──→ ThreatLevelSystem3D.decay(1.0)
```

### 4.4 V4 阵地建造链路（请求 → 评估批准/拒绝 → 指令 → BUILT）

**触发（村落领主感知）**：`defense_evaluation_enabled` 时，领主每拍评估：
- 有威胁 = 世界威胁档位 ≥1（Director 注入 notify_threat_tier）或 邻近村落被攻（警觉窗口）或 自身被攻 或 UI 手动请求
- 有空槽位（DefenseSlot3D.build_state == EMPTY）

**消息时序**：
```
VillageLord(村落)  WorldRegistry3D  CommanderAI  Director   DefenseSlot3D
   │─评估(有威胁+空槽位)─│              │           │            │
   │─publish_report(request_defense_build{slot_type,slot_index,cost})→│
   │                  │─report_received→│           │            │
   │                  │               │─校验：村落敌占/槽位可建/成本可付/价值分×强度≥阈值
   │                  │               │─批准：县城账本 try_spend(cost)
   │                  │               │─publish_command(build_defense{slot_index,slot_type,cost})→│
   │                  │←command_received─────────────────────────│            │
   │                  │               │           │─village.build_defense_slot(index)
   │                  │               │           │            │─EMPTY→BUILDING→(build_time_seconds)→BUILT
   │                  │←publish_report(defense_request_rejected)←─│（拒绝分支：县城库存不足/价值分不够/槽位占用）
```

**DefenseSlot3D 状态机**：`EMPTY → BUILDING → BUILT`（`DESTROYED` 为自动防御预留）。
- 槽位类型：`MACHINE_GUN_NEST 机枪阵地 / WATCHTOWER 哨塔 / BARBED_WIRE 铁丝网`；默认成本 `get_default_cost()`：机枪 {material:10, ammo:5}、哨塔 {material:15}、铁丝网 {material:4}。
- 默认村落实体槽位（8 槽）：机枪×3（slot 0/1/3）+ 哨塔×2（slot 2/4）+ 铁丝网×3（slot 5/6/7）；沙盒 `SandboxVillageConfig.slots` 可覆盖（含 `build_state` 初始状态）。
- **玩家村落预设防线**：`owner=PLAYER` 时所有槽位初始 `BUILT`（`apply_player_preset_defense`），进场景直接可见。
- 县城扣费发生在 Commander 批准时（原子 try_spend）；Director 只驱动槽位状态；**沙盒手动 build_defense 指令绕过评估**（Director 直接执行，县城不扣费）。
- 自动防御（机枪自动射击）本轮不做，槽位 `_process` 留 TODO 挂点。

### 4.6 V6-V12 迭代三增量链路

**owner 概念（VillageOwner）**：村落当前控制方 = `PUPPET / JAPANESE / PLAYER`。
- 敌占态（ENEMY_OCCUPIED/UNDER_ATTACK/BESIEGED）owner 跟随 `village_type` 派系；解放/驻守态（LIBERATED/GARRISONED）owner 自动转 `PLAYER`（`transition_to` 内同步）。
- 玩家村落开局：沙盒配置 `owner=PLAYER` → 直接 GARRISONED + 预设防线全部 BUILT + **不生成日军领主**（解放区不受日军指挥链管辖）+ **不生成日军守军小队**（Director `_spawn_garrison` 跳过）。

**偷袭偷资源（raided_village）**：
```
玩家(UI) → compute_raid_stolen(村) = 各取 food/ammo/material/medical 30%
         → 村落账本 remove_resource（扣减）
         → 玩家经济 add_loot（入账，缴获来源）
         → publish BehaviorEvent(raided_village) → 威胁系统 +8
```

**破坏通信（destroyed_comm）**：`village.destroy_comm()` 置 `comm_destroyed=true` + 占位视觉变色（电台盒灰黑 + Label"通信已毁"）→ publish BehaviorEvent(destroyed_comm) → 威胁 +5。上报延迟机制（通信系统）下轮 TODO。

**驻守村落**：解放村 `transition_to(GARRISONED)`（合法迁移 LIBERATED→GARRISONED）→ owner 自动 PLAYER；敌占村直接驻守为非法迁移（被拒）。

**解放区自产（V11）**：`SandboxVillageProduction.build(village, type)` 复用 `ProductionBuilding`（survival3d/holstin，不改源文件）：
- farm 产 `{food:2}` / factory 产 `{material:2, ammo:1}` / medical 产 `{medical:1}`；
- 产出写入村落账本（`configure(village.ledger)`）；沙盒村民占位自动分配满足 `worker_required`。

**缴获经济（§4.6 玩家流）**：`SandboxPlayerEconomy` 持有玩家资源账本 + 兵力：
- 打劫辎重：`add_loot(convoy.cargo)`（food/ammo/medical/weapon 全入账，武器医疗只进不出）；
- 村落解放：`award_village_liberation()` 一次性奖励 `{food:10, ammo:6, weapon:1, material:8, medical:2}` + 兵力+2；
- HUD：面板观察区常显玩家资源摘要。

**县城手动指令（绕过评估）**：UI 构造 `CommandMessage` 直接 `publish_command`，不经 Commander 打分：
| 指令 | 效果 | 执行方 |
|---|---|---|
| `send_supply` | 直接生成辎重（cargo/route 取自 Commander 配置） | WorldDirector3D |
| `reinforce` | 直接生成增援小队 | WorldDirector3D |
| `abandon` | 敌占村领主直接撤退→解放（含 Idle 态，新增 Idle→Retreat 迁移） | VillageLordAI3D |
| `build_defense` | 直接建槽位（EMPTY→BUILDING→BUILT，县城不扣费） | WorldDirector3D |

**兵力增减（V8）**：UI/测试 `village.add_garrison(±n)` → `director.rebuild_garrison(village_id)`：先释放旧守军小队（断信号+queue_free）再按新 garrison_count 实例化真实小队（`_trim_squad_members` 对齐）。

### 4.5 V5 AI 小队对接链路（真实 ai3d Squad 装配）

迭代二起，占位士兵替换为现成 ai3d 小队预制体（`Prefab/Enemy3D/`、`Prefab/Ally3D/`，复用不改）：
| 挂点 | 预制体 | 装配 |
|---|---|---|
| 村落守军 | 伪军 scout / 日军 heavy | `village.garrison_root.add_child(squad)`；`set_runtime_mission_target(村中心,8)` + `issue_defense_order(村中心,8)`；`squad_eliminated → 守军全灭 → occupied_village 行为 + 领主 notify_liberated → 村落解放` |
| 辎重护卫 | scout 精简（escort_count 2） | `convoy.escort_root.add_child(squad)`；Director `_process` 每 tick `set_runtime_mission_target(辎重当前位置, 3)` 跟随 |
| 增援小队 | east_reinforcement | 县城出发 `set_runtime_mission_target(村落,9)` + `set_known_combat_objective(攻打部队)`；到达 `issue_defense_order` 并入防守 |
| 攻打部队 | ally_defense（模拟游击队） | 沙盒 UI/测试调 `director.spawn_ally_attack(village_id, strength)`；走向村落 → 守军 RED 与游击队（PLAYER 队）感知交战 → 真实战斗；`squad_eliminated → 清理` |

守军数量与 `village.garrison_count` 对齐（`_trim_squad_members` 在 add_child 前精简成员）。攻打部队生成时同时发布 `attacked_village` 行为事件，驱动 V2/V2b 县城增援/弃村链路（规则涌现，无脚本演出）。

---

## 5. 关键架构决策（ADR 摘要）

| 决策 | 选择 | 备选 | 后果 |
|---|---|---|---|
| 模块通信 | 只经 WorldRegistry3D 事件总线 | 模块间直接信号/引用 | 可单测、可替换、可 grep 验证解耦 |
| 县城决策 | 轻量打分器（价值/兵力/距离权重） | 复用 ai3d Utility 管线 | 战略层可解释；战术层保持 ai3d 不动 |
| 领主 AI | godot_state_charts 程序化 HFSM | 手写枚举状态机 | 状态图可视化/可扩展，事件驱动清晰 |
| 辎重移动 | 原生 Path3D 采样（RoutePath3D 薄封装） | 手写 waypoint 插值 | 复用引擎曲线烘焙，路线可编辑 |
| 账本 | 直接实例化 ResourceLedger（审计见 §7） | 新建 LedgerInstance 包装 | 零改动现有引用；实体各持账本实例 |
| 波次防守 | survival3d/waves 完全不动 | 复用/改造 | 独立测试用，新域独立 |
| AI 小队装配 | 复用现成 Enemy3D/Ally3D 预制体（SquadCoordinator3D） | 新做定制小队 | 零改动 ai3d/；战术/感知/交战能力免费获得；装配点收敛在 Director |
| 阵地建造 | 槽位组件 DefenseSlot3D + 事件链路（请求→评估→指令） | 村落实体直接内置建造 | 槽位可复用/可替换；自动防御后续接入槽位挂点 |
| 沙盒观察 | FlyCamera3D + UI 指令面板替代玩家角色 | 保留玩家角色进场景 | 无玩家输入干扰，规则涌现更直观；模拟游击队用 Ally3D |
| 玩家经济载体 | SandboxPlayerEconomy（沙盒组合根持有账本） | 新建 world3d 业务模块 | 迭代三聚焦"玩法铺全"，经济归属沙盒便于观测；后续可提升为正式模块 |
| 解放区自产 | 复用 ProductionBuilding（实例化不改源文件） | 新建 world3d 生产模块 | 零改动 survival3d；产出入村落账本；SandboxVillageProduction 为唯一装配点 |
| 手动指令 | UI 直接 publish CommandMessage（绕过 Commander 评估） | 走 Commander 打分后下发 | 满足"手动操作任何指令"；弃村指令新增 Idle→Retreat 迁移 |
| 面板不挡交互 | 根 Control mouse_filter=IGNORE + 子按钮 PASS + 固定尺寸可折叠 | 全屏面板/仅缩小 | 面板外任意点击直达场景点选；折叠后场景全可视 |

---

## 6. 验证路径（对应设计文档 §8）

| 设计验证项 | 本切片落地 |
|---|---|
| 5. 县城收到缺资源上报→按优先级派辎重，可被劫 | V1（送达）+ H 劫辎重（V3 权重）+ V12 手动 send_supply |
| 1. 打劫辎重→威胁值上升 | V3-1/3-3 |
| 4. 威胁值 2★→村落出兵 | V3-2（决策强度上升，为村落出兵预留开关） |
| 2. 破坏通信→上报延迟 | CommPlaceholder 破坏状态已接（V-UI 手动）；延迟逻辑留待下一迭代 |
| 3. 攻占村落→驻守 | 状态机含 LIBERATED/GARRISONED 迁移；V5 守军全灭→解放流程已接；V10 驻守迁移 |
| 6. 总攻县城 | 县城 occupied 标记已备，总攻流程留待联调 |
| 7. 无脚本演出 | 全部行为经事件总线注入，headless 验收即证据 |
| 偷袭村落（§4.4） | V9：偷资源→村落扣减+玩家入账+威胁上升 |
| 破坏通信（§4.4） | UI 按钮 + destroyed_comm 行为事件（威胁+5） |
| 转移（§4.4） | UI 按钮：威胁值重置为 0 |
| 解放区自产（§4.5） | V11：farm cycle 后村落 food+；factory/medical 同理 |
| 缴获经济（§4.6） | V9-2 玩家入账；打劫辎重 add_loot；解放奖励 award_village_liberation |
| 玩家村落预设防线 | V7：owner=PLAYER + 全槽 BUILT + 无日军守军 |
| 兵力增减重建 | V8：garrison_count 变更→真实守军小队重建 |
| 县城手动指令 | V12：send_supply/reinforce/abandon/build_defense 直接生效 |

headless 运行：`Godot_v4.7-stable_win64.exe --headless --path . res://tests/world3d/world3d_acceptance_test.tscn`
输出 `WORLD3D_ACCEPTANCE_OK` + PASS（V1×5 / V2×5 / V2b×3 / V3×6 / V4×7 / V5×10 / V6×3 / V7×4 / V8×4 / V9×3 / V10×4 / V11×4 / V12×4）。

---

## 7. ResourceLedger 改造审计结论

- **现状**：`ResourceLedger`（survival3d/holstin/resource_ledger.gd）同时是 Autoload `HolstinResources`（project.godot:29）和可实例化类（`class_name ResourceLedger`）。
- **破坏面 grep 结果**：全项目仅 `project.godot:29` 引用 `HolstinResources`；`ResourceLedger.new()` 已被 tests/npc_v2 直接使用。
- **结论**：**不需要改造**。新建代码直接 `ResourceLedger.new()` 作为县城/村落实体各自的账本实例即可，现有 Autoload 与引用零改动。资源类型 5 种（food/ammo/weapon/material/medical）与设计一致。

---

## 8. 已知限制与后续

1. **通信系统仅占位**：`CommPlaceholder` 已有 destroyed 状态（破坏→视觉+日志+威胁），但**上报延迟机制**未接，待下一迭代接入电台/电话线（破坏后村落上报延迟/县城迟响应）。
2. **单路线约束**：`_pick_route_to` 选"终点最近村落的路线"；多路线/多村落共享时按优先级扩展（§4.1.2 资源分配优先级）。
3. **威胁档位只驱动决策强度**：2★村落出兵、3★围攻/偷家窗口、4★收缩回缩等行为强度未接线，属后续迭代（档位信号已就绪）。
4. **阵地自动防御未做**：DefenseSlot3D BUILT 后仅占位 Mesh；机枪自动射击 TODO 挂点已留，下轮接 ai3d weapon_component。
5. **攻打部队清理依赖小队自清**：Ally3D `free_when_all_members_dead=true` 自动释放；村落解放后 `_active_attacks` 追踪由 squad_eliminated 清理，若村落提前解放需等待小队自然清场。
6. **沙盒点选依赖地面碰撞**：实体本身无碰撞体，点选通过"地面命中点+最近实体"判定；小队通过成员碰撞向上找 SquadCoordinator3D。
7. **生产建筑依赖 render/ 模块**：`ProductionBuilding` 依赖 `VoxelBuildingGenerator/BuildingAnimation`（render/），实例化复用未改源文件；若后续渲染管线调整需同步验证。
8. **玩家村落守军未接真实小队**：兵力增减对玩家村落只改 `garrison_count` 数值（无日军守军）；玩家驻守部队（Ally3D）对接留待战斗生态联调。
9. **沙盒玩家经济为组合根持有**：`SandboxPlayerEconomy`/`SandboxVillageProduction` 属沙盒装配辅助，未进事件总线；后续如需跨系统经济结算可提升为正式模块。
