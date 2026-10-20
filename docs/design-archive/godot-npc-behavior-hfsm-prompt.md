# 程序 AI 任务提示词 — NPC 行为 HFSM 系统（v2）

> 给程序 AI 的完整任务书。**v2 在 v1（`npc_behavior_hfsm_prompt.md`）基础上演进**，本文件是唯一权威版本，v1 仅作历史参考。
> 日期：2026-08-04 · 状态：设计已定稿，等待实现
> 已与 `programmer_handoff.md` 资产接口逐字核对。本任务**只写功能代码**。

---

## 0. 角色边界（先读）

- **你只做**：功能模块游戏逻辑、实例化资产节点、调用公开方法、连接信号。
- **你永远不碰**：模型几何、动画数值、像素绘制、配色。全部封装在资产入口后面。
- **动画的唯一接口**：`HolstinCharacterVisual3D.update_pose(pose, frame)` —— 你只负责"哪个状态播哪个姿态 + 每帧递增 frame"，姿态枚举和帧率是资产侧的事（见 `npc_animation_art_doc.md`）。
- **禁止**：创建新的 .tscn/.tres 美术资产、修改 `render/` 与 `combat3d/` 下的任何文件。

---

## 1. 任务概述

### 1.1 v2 相对 v1 的变更（为什么升级）

| # | 变更 | v1 行为 | v2 行为 | 动机 |
|---|------|---------|---------|------|
| 1 | **主动感知层** | 只响应 `WaveDirector` 波次警报信号 / 受击 | 新增 `PerceptionComponent`：敌人实体进入感知半径即响应，**不等波次警报** | 玩家明确要求"察觉感知到敌人活动会回到营房内"——非战斗人员要有自己的眼睛 |
| 2 | **恐慌传染** | 无，NPC 独立决策 | 新增 `PanicContagion`：恐慌者广播恐惧脉冲，邻居按概率相继恐慌（多米诺波浪） | 玩家拍板"恐慌会传染"。传染 = 敌人的软攻击，恐慌造成的生产停摆就是恐惧的机会成本 |
| 3 | **医疗兵预留接口** | 医疗兵在 MEDICAL 周边待命播 IDLE，无任何医疗逻辑 | 新增 `HealTargetProvider` 抽象接口（当前返回 null），未来伤员安全后自动进医疗室回血 | 玩家拍板"预留接口，后续接受伤士兵回血功能" |
| 4 | **程序动画感** | 状态 → 姿态机械映射 | 状态切换的**中断/过渡帧**、恐慌波浪的**群体节奏**由程序侧保证时序（每 NPC 独立时基，脉冲传播不瞬移） | 玩家要求"非战斗人员像程序动画一样执行动作"——表现细节在美术文档，程序侧负责"时间" |

### 1.2 v2 交付四件事

1. `PerceptionComponent` — 主动感知（视觉/威胁半径，0.5s tick）
2. `PanicContagion` — 恐慌传染（恐惧脉冲广播 + 概率 + 免疫冷却）
3. `HealTargetProvider` — 医疗兵预留接口（返回 null 的实现 + 未来扩展点）
4. `VillagerHFSM` v2 — 在 v1 状态机基础上接入感知/传染，掩体选择升级（营房优先 + 容量）

### 1.3 最终效果（验收目标）

- 农民自动走向 FARM 生产，伐木工自动走向 TREE 采集搬运（同 v1）
- **非波次敌人进入感知半径 → 村民逃入掩体 → 敌人离开 + 安全确认期 → 恢复生产**
- **一个村民恐慌 → 8m 内邻居相继恐慌（多米诺）→ 全部躲好 → 传染停止**
- 刚恢复的村民 10s 免疫传染（防反复横跳），但被真敌人贴近仍会直接逃跑
- 医疗兵在 MEDICAL 周边待命，接口存在但无伤者可治
- 波次警报 → 全体非战斗 NPC 逃入掩体（同 v1）
- 玩家指令只对士兵生效（同 v1，不变）

---

## 2. 架构总览

```
NPC (Node3D)
├── VillagerHFSM            # 状态机，每帧驱动动画，0.3s tick 决策
├── JobAllocator            # 派活（单例或 Autoload，全场景一个，v1 不变）
├── FatigueComponent        # 村民专用：0..100 体力（v1 不变）
├── PerceptionComponent     # [v2 新增] 主动感知：0.5s tick
├── PanicContagion          # [v2 新增] 恐慌传染：接收/广播恐惧脉冲
├── HealTargetProvider      # [v2 新增] 医疗兵预留接口（其余职业返回 null）
├── [现有] NavigationAgent / 移动组件   # 复用 ai3d squad 寻路管线
└── [现有] HolstinSoldierAdapter       # 资产入口，只调 update_pose()
```

**决策器与状态机分离（强制，同 v1）**：HFSM 只回答"怎么执行"，JobAllocator 只回答"派什么活"，PerceptionComponent 只回答"有没有威胁"。

**信号流（新）**：
```
WaveDirector.wave_announced ──→ 全体 NPC → ALERT（广播，最强信号）
PerceptionComponent.敌人进感知半径 ──→ 本 NPC → ALERT（视觉）
PerceptionComponent.敌人进威胁半径 ──→ 本 NPC → 直接 FLEE（恐慌）
PanicContagion.fear_pulse 接收 ──→ 本 NPC → 概率判定 → ALERT（传染）
```

---

## 3. VillagerHFSM — 状态定义（v2 完整版）

### L0 根状态

| 状态 | 说明 |
|------|------|
| ALIVE | 默认。进入时切到 AUTONOMOUS 的 IDLE |
| DEAD | 终态。播 `DEATH` 一次，之后停摆，不再 tick |

### L1 行为模式（三选一，互斥）

| 模式 | 适用 | 说明 |
|------|------|------|
| AUTONOMOUS | 所有 NPC | 默认自主工作循环 |
| PLAYER_ORDER | **仅士兵** | 玩家指令接管；村民/医疗兵永不进入 |
| ALERT | 所有 NPC | 威胁响应，优先级最高 |

### L2 子状态

**AUTONOMOUS**（6 个，同 v1，不变）：

| 状态 | 进入条件 | 行为 | 退出条件 |
|------|---------|------|---------|
| IDLE | 默认 / 派活失败 / 工位丢失 | 原地待机，播 IDLE | JobAllocator 派到活 |
| TO_WORK | 派到工位 | 寻路到工位，播 WALK | 到达 → WORK |
| WORK | 到达工位 | 按工位类型循环播动画，驱动生产/采集 | 产出周期完成 → 判定下一步 |
| CARRY | 产出需要搬运 | 短距离往返仓库，播 CARRY | 往返完成 → 回 WORK 或 TO_BARRACKS |
| TO_BARRACKS | fatigue ≥ 80 | 寻路到 BARRACKS，播 WALK | 到达 → REST |
| REST | 到达营房 | 播 IDLE，恢复 fatigue | fatigue ≤ 20 → IDLE |

**WORK 内的产出判定**（同 v1）：需搬运 → CARRY；不需搬运 → 查 fatigue，≥ 80 去 TO_BARRACKS，否则回 WORK。

**PLAYER_ORDER**（仅士兵，4 个，同 v1）：`MOVE / GATHER / BUILD / ATTACK`。玩家指令期间 ALERT 仍可打断。

**ALERT**（2 个，v2 更新掩体选择）：

| 状态 | 行为 | 退出 |
|------|------|------|
| FLEE_TO_SHELTER | 寻路到**最近可躲藏建筑**，播 WALK | 到达 → SHELTERED |
| SHELTERED | 躲藏播 IDLE | 安全确认期结束 → 回 AUTONOMOUS 的 IDLE |

**掩体选择规则（v2 新增）**：
- 候选 = BARRACKS / MEDICAL / MESS / WAREHOUSE / FACTORY（FARM 是田，不可躲；TREE/ROCK/SCRAP 是采集点，不可躲）
- 选"最近候选"；距离差 ≤ 2m 时 **BARRACKS 优先**（营房语义正确）
- 每建筑有 `shelter_capacity`（表见 §10），**满员则选下一个**，全部满员 → 停在原地播 IDLE（不反复寻路，防抖）

**SHELTERED 退出条件（v2 细化）**：满足以下任一即恢复：
- 收到 `WaveDirector.wave_cleared` 信号（波次结束）
- 无波次时：本 NPC 感知范围内无敌方实体，且已持续 `safe_confirm_time`（安全确认期）

> 设计意图：安全确认期防止"敌人刚走就冲出去干活、敌人回头又跑"的反复横跳。3s 是 [PLACEHOLDER]。

### 全局中断（任意状态可触发，优先级从上到下）

1. 受击 / `WaveDirector` 波次警报 / Perception 感知到威胁 / 收到恐惧脉冲判定通过 → ALERT（士兵除外：士兵转战斗，走现有 ai3d 逻辑）
2. 玩家对士兵下指令 → PLAYER_ORDER
3. DEATH（HP 归零）→ L0 终态

---

## 4. PerceptionComponent — 感知层（v2 新增）

**职责**：以 0.5s tick 检测周围敌方实体，输出"警戒信号"或"恐慌信号"。只做检测与信号，不做决策。

### 4.1 接口

```gdscript
class_name PerceptionComponent extends Node
signal alert_triggered           # 敌人进入 perception_radius（警戒级）
signal panic_triggered           # 敌人进入 threat_radius（恐慌级）
signal danger_cleared            # 敌人全部离开感知范围（供安全确认期计时）

@export var perception_radius: float = 15.0   # [PLACEHOLDER] 见 §10
@export var threat_radius: float = 6.0        # [PLACEHOLDER] 见 §10
@export var tick_interval: float = 0.5        # [PLACEHOLDER] 感知刷新间隔
```

### 4.2 检测规则

- tick 时：收集 `perception_radius` 内所有 `is_hostile` 为 true 的实体（敌方单位，复用现有阵营判定）。
- 有敌对实体在 `threat_radius` 内 → 发 `panic_triggered`（最高优先）。
- 否则有敌对实体在 `perception_radius` 内 → 发 `alert_triggered`。
- 从"有"变"无" → 发 `danger_cleared`。
- **每 tick 只发一次信号**（状态变化才发，不重复发）。

### 4.3 与传染的接线

- `panic_triggered` → HFSM 进 ALERT（恐慌级，直接 FLEE）
- `alert_triggered` → HFSM 进 ALERT（同 FLEE，简化：不设 SUSPICIOUS 中间态，感知确认即逃——村民胆小，见即跑）
- `danger_cleared` → HFSM 的 SHELTERED 状态开始安全确认期计时

---

## 5. PanicContagion — 恐慌传染（v2 新增）

**职责**：恐慌者广播恐惧脉冲；接收者按概率相继恐慌。核心是**传播有时延、有衰减**——这是"多米诺波浪"的物理基础，也是程序动画感的时序来源。

### 5.1 接口

```gdscript
class_name PanicContagion extends Node
signal fear_pulse_received(from: Node3D)   # 本 NPC 被传染脉冲命中

@export var contagion_radius: float = 8.0      # [PLACEHOLDER] 传染半径
@export var pulse_interval: float = 0.8        # [PLACEHOLDER] 恐慌者广播间隔
@export var contagion_chance: float = 0.5      # [PLACEHOLDER] 单次脉冲传染概率
@export var immunity_time: float = 10.0        # [PLACEHOLDER] 恢复后免疫传染时长
```

### 5.2 广播规则（发射端）

- **仅在 FLEE_TO_SHELTER 状态广播**（逃跑中的人最吓人）。
- 每 `pulse_interval` 秒向 `contagion_radius` 内其他 NPC 发一次恐惧脉冲（信号或直接方法调用）。
- 进入 SHELTERED 后**停止广播**（躲好了就安静了——波浪在掩体处熄灭）。
- 广播不逐帧做：用定时器（0.8s），禁止 `_process` 轮询。

### 5.3 接收规则（接收端）

- 收到脉冲 → 若在 `immunity_time` 免疫期内 → 忽略。
- 否则按 `contagion_chance` 判定：
  - 通过 → 发 `fear_pulse_received` → HFSM 进 ALERT（FLEE）→ 自己也变成广播者（波浪延续）
  - 未通过 → 忽略（波浪自然衰减）
- **免疫只防传染，不防真实威胁**：即使免疫期内，被真敌人贴到 `threat_radius` 仍会直接恐慌（Perception 优先级高于传染）。

### 5.4 防失控设计（必须实现）

| 风险 | 对策 |
|------|------|
| 全图无限传染 | 概率 < 1 自然衰减 + 广播只在 FLEE 时 + 躲进掩体即熄火 |
| 反复横跳 | `immunity_time` 免疫冷却 |
| 一锅端瞬移 | 脉冲按 0.8s 间隔传播，非瞬发——波浪有视觉传播速度 |

> 设计意图：传染是**敌人的软攻击手段**。一小股敌人摸进营地，村民会像涟漪一样接连逃跑，生产停摆——玩家能直观看到"恐慌"这种代价，且通过建营房/增援士兵来对冲。传染参数是全局的（Autoload 或单例配置），不做每 NPC 差异化。

---

## 6. HealTargetProvider — 医疗兵预留接口（v2 新增）

**职责**：定义"医疗兵该治谁"的抽象入口。当前版本实现为"无目标"，未来接伤员回血功能时只换实现，不动 HFSM 主循环。

### 6.1 接口

```gdscript
class_name HealTargetProvider extends Node
## 返回当前应治疗的伤者；无目标返回 null
func get_heal_target() -> Node3D:
    return null   # [v2] 占位：无伤者可治

## 未来版本签名（勿删注释，给后续实现者看）：
## 1. 监听伤员事件：士兵受伤（HP < 阈值）→ 记录为"待收治"
## 2. 伤员脱离战斗且安全（无敌对实体在感知半径内）→ 自动寻路进 MEDICAL → 躺床
## 3. 医疗兵进入 TREAT 状态（在 MEDICAL 内，对躺床伤员播 RESCUE 动画循环）
## 4. 治疗完成 → 伤员恢复，出床回归士兵逻辑
```

### 6.2 当前版本行为（v2 不变）

- 医疗兵 = JobAllocator P1 派到 MEDICAL 周边 3m 内待命，播 IDLE（"状态动画"）。
- `get_heal_target()` 恒返回 null → HFSM 永不进入 TREAT。
- 不响应伤员、不触发 RESCUE 姿态（RESCUE 资产已存在，见美术文档 §8，本阶段不驱动）。

### 6.3 挂载规则

- 仅医疗兵挂 `HealTargetProvider`；农民/伐木工/士兵不挂（返回 null 的默认实现也要在基类上，避免空指针）。

---

## 7. JobAllocator — 派活决策器（v2 更新）

同 v1 全部规则，仅两处更新：

| 优先级 | 条件 | 派给 | 目标 |
|-------|------|------|------|
| P0 | 警报中（ALERT 模式的 NPC） | — | 不派活（NPC 自己会去躲） |
| P1 | medical < 30 且空闲医疗兵 | 医疗兵 | MEDICAL（仅待命，见 §6） |
| P2 | food < 40 且空闲农民 | 农民 | 最近的 FARM |
| P3 | material < 50 且空闲伐木工 | 伐木工 | 最近的 TREE/ROCK/SCRAP |
| P4 | 士兵空闲 | 士兵 | BARRACKS 周边驻守（IDLE） |
| P5 | 其余 | — | 留在 IDLE 待机 |

**v2 更新 1（掩体容量）**：JobAllocator 不再把村民派到"满员建筑"？否——派活与躲藏独立，躲藏容量只在 ALERT 时查（见 §3 掩体规则）。本条只是确认：躲藏不影响派活，各管各的。

**v2 更新 2（派活抑制）**：传染波浪期间（近 5s 内有恐惧脉冲发生），JobAllocator 暂停派新活（P0 扩展为"警报中或传染刚发生"），避免"刚派活就恐慌又取消"的抖动。`contagion_suppression_time: float = 5.0` [PLACEHOLDER]。

---

## 8. 动画映射表（v2 更新）

| 状态 | 姿态 | 备注 |
|------|------|------|
| IDLE / REST / SHELTERED | `IDLE` | |
| TO_WORK / TO_BARRACKS / FLEE_TO_SHELTER | `WALK` | FLEE 时程序侧给 `walk_speed_multiplier = 1.8`（见 §9，资产侧根据乘数加速步频） |
| WORK（FARM） | `WORK_FARM` | |
| WORK（TREE / ROCK / SCRAP） | `WORK_CHOP` | |
| CARRY | `CARRY` | |
| DEAD | `DEATH` | 播放一次后停摆 |
| 士兵 PLAYER_ORDER 各状态 | `WALK / AIM / FIRE / RELOAD` | 复用现有 soldier 驱动逻辑，不改 |

**职业 → 目标建筑映射**（同 v1）：

| 职业 | 目标建筑 | WORK 姿态 | 搬运 |
|------|---------|-----------|------|
| 农民 | FARM | WORK_FARM | 否（直接入账） |
| 伐木工 | TREE / ROCK / SCRAP | WORK_CHOP | 是（CARRY 表演往返） |
| 医疗兵 | MEDICAL（周边待命） | IDLE | 否 |
| 士兵 | BARRACKS（驻守） | IDLE | 否 |

> **程序动画感（程序侧职责）**：姿态切换本身由资产处理过渡帧（美术文档 §5），程序侧只保证两件事：① frame 全局递增不重置（v1 已约定）；② **传染波浪的时序**——每个 NPC 是独立时基，脉冲到达时刻不同，天然产生"一个接一个转身"的效果。禁止做"全 NPC 同时切状态"的同步。

---

## 9. 失败状态表（v2 新增 2 条，其余同 v1）

| 场景 | 行为 |
|------|------|
| 工位被占 | 找下一工位；找不到 → IDLE 待下一 tick |
| WORK 目标建筑被摧毁/消失 | 立即回 IDLE 重新派活（先判 `is_instance_valid`） |
| 寻路失败 | 回 IDLE + 冷却 3s 再试（防抖） |
| 仓库满 | 跳过 CARRY，直接回 WORK 继续生产 |
| 采集点耗尽 | 换最近可用 TREE/ROCK/SCRAP |
| CARRY 目标仓库被拆 | 取消 CARRY，回 IDLE |
| **[v2] 掩体满员** | 选下一候选；全部满员 → 原地 IDLE（不反复寻路） |
| **[v2] 掩体在途中被摧毁** | 立即改选下一候选；无候选 → 原地 IDLE |
| **[v2] 恐慌波浪中目标建筑被拆** | 同"WORK 目标建筑被摧毁"：回 IDLE，传染判定不因拆建筑报错 |

---

## 10. 参数表（全部 [PLACEHOLDER]，带 rationale）

| 参数 | 值 | Rationale | 验证路径 |
|------|-----|-----------|---------|
| `perception_radius` | 15m [PLACEHOLDER] | 约等于等距相机 15m 可视半径，村民"看得到就躲" | playtest：敌人 15m 外靠近，村民应在敌人进 6m 前开始逃 |
| `threat_radius` | 6m [PLACEHOLDER] | 敌人近身即恐慌，给玩家留 6m 反应窗口 | playtest：士兵能否在村民全跑前接敌 |
| `perception_tick` | 0.5s [PLACEHOLDER] | 感知不需要每帧；0.5s 内敌人走不完 6m 威胁半径 | 性能预算：20 NPC × 0.5s tick |
| `contagion_radius` | 8m [PLACEHOLDER] | 约 2 个建筑间距，恐慌波浪跨建筑传播 | 验收 I：8m 内传播、8m 外免疫 |
| `pulse_interval` | 0.8s [PLACEHOLDER] | 波浪视觉传播速度；太快=瞬移，太慢=无感 | 验收 I：观察波浪传播是否"可见" |
| `contagion_chance` | 0.5 [PLACEHOLDER] | 50% 单跳衰减，约 3-4 跳自然熄灭 | 验收 I：波浪在 3-4 个村民后衰减 |
| `immunity_time` | 10s [PLACEHOLDER] | 防反复横跳；10s 约等于 2 个生产周期 | 验收 J |
| `safe_confirm_time` | 3s [PLACEHOLDER] | 敌人离开后确认期；太短=抖动，太长=过度停摆 | 验收 H |
| `shelter_capacity` | BARRACKS 10 / 其他 5 [PLACEHOLDER] | 营房大、生活建筑小；满员溢到下一建筑 | 验收 H：8 人村只建 1 个 MESS 时的行为 |
| `contagion_suppression_time` | 5s [PLACEHOLDER] | 传染后暂停派活，防派活/恐慌抖动 | 验收 I 观察派活稳定性 |
| `walk_speed_multiplier`（FLEE） | 1.8 [PLACEHOLDER] | 逃跑步频；由资产侧按乘数加速 | 视觉验收：恐慌跑明显快于普通 WALK |

---

## 11. 验收标准（坏掉长什么样）

每项在 Godot 编辑器 F6 独立场景验证。A-G 同 v1，H-K 为 v2 新增：

- **A 农民**：自动走向 FARM → WORK_FARM → 产出入账 → 疲劳回营 → 恢复出工（同 v1）。
- **B 伐木工**：走向 TREE → WORK_CHOP → CARRY 往返 → stock_ratio 上涨（同 v1）。
- **C 医疗兵**：MEDICAL 周边待命播 IDLE；`get_heal_target()` 返回 null。
- **D 波次警报**：wave_announced → 全体逃入掩体 → wave_cleared → 恢复（同 v1）。
- **E 士兵指令**：玩家指令 → 执行 → 回驻守（同 v1）。
- **F 卡死测试**：目标建筑被拆/寻路失败，3s 内回 IDLE，无悬空引用报错（同 v1）。
- **G 性能**：20 NPC 同屏稳定 60fps（同 v1）。
- **H 主动感知**：无波次时，放 1 个敌对单位从 20m 外走近 → 村民在敌人进入 6m 前开始逃 → 全躲好 → 敌人离开 3s 后恢复生产。**失败信号**：村民在敌人贴脸后才逃，或敌人走后 < 1s 就恢复。
- **I 恐慌传染**：2 个村民相距 6m，人工触发 1 个恐慌 → 另一个在 ≤ 1.6s 内相继恐慌；相距 12m 的第三个不恐慌。**失败信号**：传染瞬发（< 0.2s）或无限蔓延到 12m 外。
- **J 免疫冷却**：村民恢复后 10s 内，邻居再次恐慌不传染他；但真敌人进 6m 他仍会逃。**失败信号**：免疫期内被传染，或免疫期内被真敌人贴脸不逃。
- **K 掩体容量**：8 村民只建 1 个容量 5 的 MESS → 5 人进 MESS，3 人进下一候选；全满员 → 原地 IDLE 不卡死。
- **L 表演节律**：恐慌波浪时，村民转身逃跑是**依次**发生（间隔肉眼可辨），不是同帧全转。**失败信号**：全体同帧切换。

---

## 12. 文件结构建议（组件化，符合代码规范）

```
ai3d/npc/villager_hfsm.gd        # HFSM v2（接入感知/传染，掩体容量）
ai3d/npc/job_allocator.gd        # 派活决策器 v2（传染抑制）
ai3d/npc/fatigue_component.gd    # 体力组件（v1 不变）
ai3d/npc/perception_component.gd # [v2 新增] 感知层
ai3d/npc/panic_contagion.gd      # [v2 新增] 恐慌传染（广播/接收/免疫）
ai3d/npc/heal_target_provider.gd # [v2 新增] 医疗兵预留接口
```

- 静态类型、信号 snake_case、组件化。
- 所有新数值必须进参数表并标 [PLACEHOLDER]（见 §10），禁止 magic number。
- 不改动 `render/`、`combat3d/`、现有 ai3d 战斗逻辑。
- **PanicContagion 的广播用 Area3D + 定时器**（0.8s），禁止每帧 `_process` 查距离。

---

## 13. 实现顺序建议

1. PerceptionComponent（最独立，先做）→ 验 H 前半
2. PanicContagion 广播/接收（定时器 + 概率 + 免疫）→ 验 I、J
3. VillagerHFSM 接入感知/传染（ALERT 触发链 + 掩体选择 + 容量）→ 验 H、K、L
4. JobAllocator 传染抑制 → 回归验收 A、B
5. HealTargetProvider 占位实现 → 验 C
6. 失败状态表 v2 逐条过 → 验 F，全量回归 → 验 G

---

## 附：与 v1 / 资产文档的关系

- v1 `npc_behavior_hfsm_prompt.md`：本文件唯一权威，v1 仅历史参考。
- `programmer_handoff.md`：资产接口契约（第 1 章 7 入口、第 5 章 ProductionBuilding、第 3 章 GatherNode `auto_gather`、第 9 章 WaveDirector），签名已核对。
- `npc_animation_art_doc.md`：美术侧表现文档（Pose 清单、过渡帧、状态可视化、恐慌波浪表现）。程序侧不读它，但 §8 的映射表与它一一对应。
