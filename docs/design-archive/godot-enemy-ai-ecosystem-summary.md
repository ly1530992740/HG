# 敌人 AI 生态系统总结：县城 + 村长 + 玩家村庄

> **用途**：给外部 AI（Debug/开发新功能/QA）的生态架构输入。基于当前代码实况（2026-08-10）。
> **配套文档**：`docs/ai_ecosystem_summary.md`（生态角色职责详版 + 威胁行为权重表 + 玩法平衡点讨论底稿）。本文聚焦：架构总览 + 县城/村长/玩家村 + 数据流 + **功能缺口清单**。
> **一句话**：敌人 AI = **1 个县城决策中枢 + N 个村庄领主（感知-上报-执行）+ 辎重补给线 + 威胁值总开关**，全部经 `WorldRegistry3D` 事件总线解耦，规则涌现无脚本演出。玩家村庄是这套生态里的"异类"（脱离敌军指挥）。

---

## 1. 总体架构

```
                    ┌─────────────────────────────────────────┐
                    │            WorldRegistry3D              │
                    │  实体登记表 + 事件总线（唯一通信通道）       │
                    └──────▲────────────────────▲────────────┘
                           │ 只经总线收发           │ 只登记/查询
        ┌──────────────────┴──────┐      ┌────────┴───────────────┐
        │    业务模块（互不引用）    │      │ 实体（登记进总线）        │
        │ CountySeatCommanderAI3D │      │ CountySeatEntity3D     │
        │ VillageLordAI3D (×N)    │      │ VillageEntity3D (×N)   │
        │ ThreatLevelSystem3D     │      │ RoutePath3D / 辎重      │
        └─────────────────────────┘      └────────────────────────┘
                           ▲
        ┌──────────────────┴──────────────────────────────────┐
        │ WorldDirector3D（唯一装配器：接线 + 执行县城指令落地）   │
        │ 实例化守军/护卫/增援/攻击队/扫荡队/大扫荡队              │
        └─────────────────────────────────────────────────────┘
```

**三条铁律**（grep 可验证）：
1. 业务模块互相**零节点引用**，只经总线收发 `ReportMessage` / `CommandMessage` / `BehaviorEvent`。
2. `WorldDirector3D` 是唯一装配器（唯一 `new` 业务模块/小队的地方，唯一跨模块信号接线处）。
3. `VillageEntity3D`/`SupplyConvoy3D` 只暴露挂点（`garrison_root`/`escort_root`）与状态，不实例化小队。

---

## 2. 县城生态系统（决策中枢）

### 2.1 实体层 `CountySeatEntity3D`
- **县城库存**：food/ammo/medical/material 账本（`ResourceLedger`）。
- **兵力池** `troop_pool`：县城可派出的士兵总数（每日恢复 + 征兵消耗）。
- 关键判定：`can_send_supply(cost)`（库存够不够派辎重）、`spend_supply_cost(cost)`（扣费）。

### 2.2 决策层 `CountyCommanderAI3D`（HFSM 上层的"中枢大脑"）

**输入（上报路由 `_on_report_received`）**：
| report_kind | 处理 |
|---|---|
| `resource_shortage` | 记 pending → `_try_send_supply`（库存够 → 派辎重；不够 → 每日结算重试） |
| `supply_late`（辎重逾期） | 记 pending 重发 + 发布 `supply_late_confirmed` 行为事件（WorldDirector 收口 → 威胁 +8） |
| `under_attack` | 评估是否增援（`_score_village` 价值分 × 决策强度 ≥ 阈值 + 兵力够 → `reinforce` 指令；只派**敌占村**，玩家村被攻不增援） |
| `request_defense_build` | 评估（成本 ≤ 库存、价值分达标）→ `build_defense` 批准 / `REJECT_BUILD` |
| `enemy_position` | 记录 `last_known_enemy_position`（精确位置，供大扫荡）+ 触发扫荡评估 |

**输出（决策枚举）**：`SEND_SUPPLY / REINFORCE / BUILD_DEFENSE / REJECT_BUILD / SWEEP / ABANDON / DEFEND`

**扫荡侦察（模块 E）**：威胁 ≥ `sweep_threat_threshold`(60) + 冷却 `sweep_cooldown_seconds`(120s) → 选最近**通信完好**的敌占村 → 发 `sweep` 指令（3 个模糊点，中心 = 精确敌位优先 / 威胁事件位置 / 县城）→ 侦察小队逐点推进，发现敌人自动上报精确位置。

**每日节拍 `on_daily_tick`**：重试所有 `_pending_shortages`（县城攒够货后补发辎重）。

**威胁注入**：`apply_threat_level()`（WorldDirector 每帧喂当前威胁值）→ `_check_sweep_trigger()`；`apply_threat_tier()`（档位变化 → 决策强度缩放，倍率 `[1.0, 1.5, 2.2, 3.0]`——威胁越高决策越积极）。

**威胁行为权重**（玩家行动 → 威胁值，生态"积分榜"）：
| 行为事件 | 威胁 |
|---|---|
| 占领村庄 `occupied_village` | +25 |
| 截获辎重 `looted_convoy` | +20 |
| 攻打村庄 `attacked_village` | +10 |
| 掠夺村庄 `raided_village` | +8 |
| 破坏电台 `destroyed_comm` | +5 |
| 摧毁工事 `destroyed_defense` | +5 |
| 击杀日军 `killed_japanese` | +1 |
（档位阈值 [25, 60, 100]，上限 150，每日衰减 2）

---

## 3. 村庄生态系统（领主感知-上报-执行）

### 3.1 实体层 `VillageEntity3D`
- **状态机**：`ENEMY_OCCUPIED → UNDER_ATTACK → BESIEGED → LIBERATED / GARRISONED`
- **归属**：`VillageOwner { PUPPET(伪军), JAPANESE(日军), PLAYER(八路军) }`；`is_player_owned()`
- **资源账本**：food/ammo/medical/material；`is_short_of_resources()`（低于阈值）
- **防御槽位** `defense_slots[]`：EMPTY/BUILDING/BUILT/DESTROYED，敌占村预设建 3 个（2 机枪+1 塔），玩家村全建
- **电台** `comm_placeholder`（RadioStation3D 实体）：被摧毁 → `comm_destroyed=true` → 上报阻断；3 天自动修复
- **仓库** `warehouse`：血量/可收缴/1 天自动修复
- **守军** `garrison_root`：守军小队挂点（WorldDirector 生成 + 自动布防）
- **预期辎重登记** `_expected_supplies`：辎重出发时登记 → 逾期检测
- **每日结算 `on_daily_tick`**：食物消耗（守军数 × 1）→ 不足上报；电台/仓库修复计时；饥荒掉血（食物 0 → 守军每日扣 10% 至 50% 地板）
- **解放区生产** `production_buildings`：解放/驻守村可自产 food/material/ammo/medical

### 3.2 领主层 `VillageLordAI3D`（HFSM，每村一个）
**状态**：`NONE → IDLE → SHORTAGE_WAIT → UNDER_ATTACK → FIGHT_TO_DEATH → RETREAT → LIBERATED`

**感知循环（`_check_perception`，每 `check_interval` 一拍）**：
| # | 感知 | 动作 |
|---|---|---|
| 1 | 缺资源 | 上报 `resource_shortage`（带冷却）→ SHORTAGE_WAIT；资源恢复 → SUPPLY_RESOLVED |
| 2 | 被攻打（外部置位 `_attacked`） | 上报 `under_attack` 求援 |
| 3 | 防御建造请求（每日评估/威胁感知/UI 手动） | 上报 `request_defense_build` |
| 4 | 预期辎重逾期 | 上报 `supply_late`（县城重发 + 威胁） |

**关键约束**：
- **玩家村不受日军领主指挥**：`village.is_player_owned()` → 不感知不上报不评估防御（解放区自治）。
- **通信被毁**：感知照常（HFSM 正常迁移），但**上报发布被阻断**（`_publish_*` 检查 `is_comm_destroyed`）→ "破坏电台→县城不知情→断供"战术成立。

**命令执行**：收到县城 `CommandMessage`（send_supply 落地在装配器；reinforce/build_defense/sweep 也由装配器执行，领主主要做状态迁移与上报）。

---

## 4. 玩家村庄（village_b，生态里的"异类"）

| 维度 | 敌占村（a/c） | 玩家村（b） |
|---|---|---|
| 守军队伍 | RED（伪军/日军） | **PLAYER（八路军）**，`can_target_players=false` |
| 守军布防 | 有工事自动布防（同机制） | 同机制（deploy_defense） |
| 预设防线 | 3 个（2 机枪 + 1 塔） | **全部槽位** force_build |
| 领主指挥 | 有（感知/上报/求援/防御请求） | **无**（脱离敌军指挥，自治） |
| 县城增援 | 被攻打 → 可能增援 | **永不增援**（`spawn_reinforcement` 对玩家村直接拒绝） |
| 辎重 | 缺资源 → 县城派辎重 | **不享受**县城补给（缺粮靠自己生产/缴获） |
| 生产建筑 | 无 | 解放后自产（farm/factory/medical） |
| 饥荒 | 断供后掉血至 50% | 同规则（食物耗尽同样掉血） |
| 被全灭 | 村庄易主（→ LIBERATED 归玩家） | 守军全灭 → 村庄易主（→ ENEMY_OCCUPIED） |

**玩家村对生态的"攻击面"**（即玩家玩法入口）：
1. **伏击辎重**：在路线上埋伏（草丛隐蔽）→ 截获 → 缴获货物（优先入小队 `carried_ledger`）。
2. **断供**：拆 village_a/c 电台 → 上报阻断 → 缺粮 → 守军饥荒 → 攻占。
3. **攻打村庄**：`spawn_ally_attack` 攻击队 → 守军全灭 → `_on_garrison_squad_eliminated` → 村庄解放（LIBERATED）+ 威胁 +25。
4. **拆工事**：攻打机枪/塔（有血量可摧毁）→ 削弱守军防御。
5. **缴仓库**：仓库可毁 → 收缴资源。

---

## 5. 生态闭环数据流（关键链路）

```
【补给闭环】领主感知缺粮 → 上报 shortage → 县城记 pending → 库存够 → send_supply
  → WorldDirector 生成辎重（带护卫 FOLLOW）→ 送达 → 领主入账 → 继续消耗 →（循环）
  → 被伏击：护卫全灭 → looted → 缴获 + 威胁 +15

【求援闭环】领主被攻打 → 上报 under_attack → 县城评估 → reinforce（敌占村）
  → WorldDirector 生成增援（RED）→ 行军支援

【扫荡闭环】辎重被灭/逾期 → 威胁上升 → apply_threat_level → 威胁≥60 → sweep 指令
  → 侦察小队 3 点扫 → 发现玩家 → 上报 enemy_position → 县城记录精确位置

【大扫荡闭环】有精确位置 + 日历 day%7==0 → _spawn_county_sweep_attack
  → 重火力大部队精确攻占 → 守军全灭 → 村庄易主（威胁再 +25）

【断供→饥荒】玩家拆电台 → comm_destroyed → 上报阻断 → 无辎重 → 食物 0
  → 每日饥荒掉血至 50% → 玩家攻占（虚弱守军）→ LIBERATED
```

---

## 6. 事件总线协议（WorldRegistry3D）

```gdscript
ReportMessage   {"type":"report",  "from_id", "to_id", "report_kind":StringName, "payload":{}}
CommandMessage  {"type":"command", "from_id", "to_id", "command":StringName,    "payload":{}}
BehaviorEvent   {"type":"event",   "from_id", "event":StringName,               "payload":{}}
# 静态构造：make_report / make_command / make_behavior_event
# 发布：publish_report / publish_command / publish_behavior_event（模块经信号订阅）
# 实体：register_entity(node, id) / get_entity / get_entities_of_kind("village"/"convoy"/...)
```

**装配器唯一直连信号**（WorldDirector `_wire_if_possible`）：
| 接线 | 作用 |
|---|---|
| `calendar.settlement_tick → _on_settlement_tick` | 威胁衰减 + 县城每日决策 + 每日经济（食物消耗/县城收入/兵力池） |
| `calendar.day_ticked → _on_day_ticked` | 大扫荡触发（day%7） |
| `threat.tier_changed → _on_tier_changed` | 威胁档位 → 县城决策强度 |
| `registry.command_received → _on_command_received` | 执行县城指令（send_supply/reinforce/build_defense/sweep） |
| `registry.behavior_event_received → _on_behavior_event` | 行为事件收口（looted_convoy → 威胁+15；supply_late_confirmed → 威胁+8） |

---

## 7. 已有功能 vs 待完成功能模块（给外部 AI 的开发清单）

### 7.1 已有（生态核心已闭环）
- ✅ 县城：辎重派遣（pending/重试）、增援（敌占村）、防御建造批准、扫荡、敌人位置、大扫荡、每日节拍
- ✅ 村庄：领主 HFSM 感知-上报-执行、缺粮/被攻/防御请求/辎重逾期、通信阻断、饥荒、电台/仓库修复
- ✅ 玩家村：自治（脱离指挥）、PLAYER 守军 + 自动布防、全建防线、生产建筑、无县城增援
- ✅ 辎重：路线移动/受击停止/护卫 FOLLOW/截获缴获
- ✅ 威胁系统 + 扫荡/大扫荡链路
- ✅ 事件总线 + 装配器 + 防御性修复（§文档 4）

### 7.2 待完成/可加强（缺口，按优先级）
| # | 缺口 | 现状 | 建议方向 |
|---|---|---|---|
| 1 | **玩家主动建造链路** | 工事建造走县城 AI（村请求→县批准→装配器执行）；玩家经济→建造的 UI 消耗链路弱 | 玩家经济 + 村庄槽位直接建造指令 |
| 2 | **塔内残兵僵持** | 攻方感知穿透 + 打塔→塔毁→守军暴露，但塔内 1-2 残兵可能长时间僵持 | 加强毁塔（近战攻塔/结构易损区） |
| 3 | **守军高级战术 DEFEND** | 布防用简单模式（稳定但无包抄/压制表现） | 高级战术新增 DEFEND mission 类型 |
| 4 | **玩家手动开火完整链路** | 剧本用 AUTONOMOUS_ATTACK 锁计划修复；"选中小队→点选开火"手动链路待窗口模式确认 | 手动开火指令 + 目标锁定 UI |
| 5 | **大扫荡"村庄易主"演出** | 链路通，但塔内守军可能挡住易主 | 依赖 #2 后完整验证 |
| 6 | **村庄失守后遗症** | 村庄易主已实现；失守后县城"复仇/反扑"行为单一 | 可加"夺回村庄"县城决策 |
| 7 | **多村联动** | 村间互不感知（只有上报县城）；"邻近村被攻→支援"缺失 | 领主感知邻近村状态（VillageLord 有 `_neighbor_attacked` 雏形） |
| 8 | **通信战纵深** | 电台 3 天自动修复；"玩家持续压制通信"无收益设计 | 断联期间村内恐慌/逃兵等次级效果 |

### 7.3 待讨论的玩法平衡点（见 `ai_ecosystem_summary.md` §5 详版）
1. **威胁积分**：击杀日军仅 +1——"杀敌"几乎不刺激生态，只有大动作（占村/截辎重）才涨。是否合理？
2. **县城兵力池**：只增不减？增援/扫荡/大扫荡派兵后是否恢复（否则长期玩家必赢）？
3. **村庄价值分公式**（`_score_village`）：决定增援/放弃/建防，是生态平衡命门——需显式化讨论。
4. **日军主动反击**：目前只有"扫荡+大扫荡"两类进攻；是否需要日常"骚扰式袭击"玩家村？
5. **二次解放**：村庄被重占后玩家如何"夺回"（HFSM 支持 REOCCUPIED 回 Idle，但玩法闭环是否顺畅）？

---

## 8. 验证入口

```bash
# 自动化 QA（108/108）：覆盖生态各模块（M/E/G/H/R 等系列断言）
Godot_v4.7-stable_win64.exe --headless --path "D:/project/HG" "res://tests/world3d/world3d_module_qa_test.tscn"

# 真实沙盒（21 步自动模拟 + 手动操作）：
Godot_v4.7-stable_win64.exe --path "D:/project/HG" "res://tests/world3d/world3d_manual_test.tscn"

# 剧本验证（埋伏/断供→饥荒→攻占/大扫荡）：
Godot_v4.7-stable_win64.exe --headless --path "D:/project/HG" "res://tests/world3d/world3d_scenario_verify.tscn"
```

*游戏开发工作室主理人游承峰整理，2026-08-10。*
