# AI 小队战斗系统增强设计 —— 战术意图补全

> 目标文件：`ai3d/squad/*` 决策管线（Godot 4，GDScript）
> 范围：Utility 意图选择 → HTN 任务分解 → Utility 评分 → 各意图执行逻辑
> 原则：先审计现状（已读源码），标出"已有/缺失/改造"，每个数值给 rationale 或 [PLACEHOLDER]

---

## 0. Fun Hypothesis 与边界声明

**Fun Hypothesis**：AI 小队的"聪明"不来自单兵枪法，而来自**意图级团队决策**——玩家（或旁观调试者）能读懂"这队人在干什么、为什么这么干"。

**Design Pillars**：
1. 每个意图必须服务明确的**战术动机**（什么局势触发、为什么）
2. **决策可解释**：Utility 分层贡献、HTN 方法选择、角色分配都进 decision_trace
3. **韧性优先**：所有依赖"全队同步"的意图必须有超时兜底，避免死锁
4. **成员级同步复用现有调度器**：不重造轮子

**假设清单**（四要素定界）：
- 平台：Godot 4 桌面/可导出场景；品类：战术小队（俯视/第三人称）；目标用户：开发者调试 + AI 行为验证
- 单局规模：小队 3–8 人，敌人 ≤ 12，单次遭遇 30s–5min
- **若实测单局时长/规模翻倍，本设计中的超时阈值和角色配比需整体重画**

---

## 1. 现状审计结论（已读源码）

| 你列的意图 | 现状 | 判定 |
|---|---|---|
| ADVANCE_TO_OBJECTIVE | `mission_cover_advance` / `mission_move` | ✅ 已有 |
| REACT_TO_UNKNOWN_FIRE | **无** | ❌ 新增 |
| PREPARE_AMBUSH | `AMBUSH` 候选 + `aim→volley`，但无部署链 | 🔶 补部署链 |
| CONTACT_DRILL | `CONTACT_COVER`（已确认接触后触发） | ✅ 已有 |
| GAIN_FIRE_SUPERIORITY | `ESTABLISH_BASE_OF_FIRE` / `FIX_AND_SUPPRESS`（两战术同走 `_compile_base_of_fire`） | 🔶 去重 + 区分 |
| MANEUVER_ON_ENEMY | `SUPPRESS_AND_FLANK` / `DIRECT_ASSAULT`；`BOUNDING_ADVANCE` 单次跃进 | 🔶 补交换循环 |
| SEARCH_OR_PROBE | `RECON_SPLIT`（部分） | ✅ 部分已有 |
| OCCUPY_AND_DEFEND | `DEFEND_CONTACT` / `hold_objective`（部分） | 🔶 补阵地分配+预备队 |
| CONSOLIDATE_AND_REGROUP | 走 `recover_in_cover`（缺换弹/集合/重分配） | 🔶 改造 |
| DISENGAGE | `BREAK_CONTACT`（单次 RETURN_TO_ORIGIN） | 🔶 补交替撤退 |

**现有可复用机制（关键）**：
- `squad_task_scheduler_3d.gd` 的 `mark_member_succeeded` + `minimum_success_count` → **成员级同步**（就位后同步开火的地基）
- `squad_role_allocator_3d.gd` 的 6 角色 + 回溯分配 → 可直接复用给伏击/防御部署
- `squad_mission_controller_3d.gd` 的 `State` 枚举 → 任务四阶段已具备（APPROACHING/CLEARING/HOLDING/RETURNING）
- **缺口**：调度器**无任务超时上限**（`_evaluate_task` 只按成功数判定，无 deadlock 保护）——伏击/交替跃进必须补

---

## 2. 五缺口具体设计

### 2.1 REACT_TO_UNKNOWN_FIRE（新增）

**触发**：收到 GUNSHOT/DAMAGE/NEAR_MISS 报告，但**该方向无 VISUAL 接触**（`belief` 无对应 contact_id），且 squad 当前非 `CONTACT_COVER`。

**Utility 评分**（`squad_utility_evaluator_3d.gd` 新增候选）：

| 变量 | 来源 | 贡献 | rationale |
|---|---|---|---|
| base | 固定 | 200 | 最高优先级（未确认火力=最高威胁） |
| suppression | snapshot | +suppression_ratio×60 | 越被压制越需立即找掩护 |
| has_visual | belief | ×0（有视觉接触时此候选被 CONTACT_COVER 抢占） | 防止与 CONTACT_DRILL 竞争 |
| sector_count | 未知方向扇区数 | +sector×15 | 多个未知方向需更高警惕 |

**HTN 分解**（`squad_htn_planner_3d.gd` 新增 `_compile_react_unknown_fire`）：

```
REACT_TO_UNKNOWN_FIRE
├─ [立即] TAKE_COVER 远离未知火力来源方向（WEAPONS_HOLD）
│    └─ 每个成员：找掩护 → 朝向火力来源，压制观察
├─ [下一步] 尝试识别来源（RECON_SPLIT 或 SEARCH_LAST_CONTACT）
└─ 若 3s 内出现 VISUAL 接触 → 切换 CONTACT_COVER / DEFEND_CONTACT
```

**执行细节**：
- 复用 `contact_cover` 但 `target_position` = 离开火力轴线的侧向掩护点（非直接冲向来源）
- 需要**新增** `SquadDirective3D.Type` 或复用 `HOLD_SECTOR` + 朝向来源
- **超时兜底**：1.5s 内没找到掩护 → 就地 PRONE，避免全员暴露

---

### 2.2 PREPARE_AMBUSH（补部署链）

**现状**：`_compile_ambush` 只有 `ambush_aim → ambush_volley`，全部成员同时 aim，无隐蔽接近、无角色分工、无就位同步。

**改造为五阶段**：

```
PREPARE_AMBUSH
├─ 1. SECTOR_PICK：选择伏击阵地（面向敌人接近方向的扇形，含交叉射界）
├─ 2. STEALTH_APPROACH：全员 WEAPONS_HOLD 隐蔽移动到位
│     └─ 角色分配：BASE_OF_FIRE（机枪/精确射手主射）/ MANEUVER_WING（交叉侧射）/ SECURITY（后方警戒）
├─ 3. AIM_AND_SETTLE：就位成员 AIM_CONTACT，规则 WEAPONS_HOLD（不射击）
├─ 4. VOLLEY：minimum_success_count=就位人数阈值 → 同步开火（复用 `_evaluate_task` 成员级同步）
└─ 5. 途中被发现 → 取消伏击，切换 CONTACT_COVER；超时 → 用已就位人员开火或取消
```

**关键改动**：
1. **新增伏击状态机**（`SquadAmbushState3D` 或并入 `squad_advanced_tactics_3d.gd`）：`PLANNING → APPROACHING → SETTLING → ENGAGING`，供 Utility 判断是否已进入伏击、防止重复重规划打断
2. **HTN 拆分角色任务**：BASE_OF_FIRE/WING 走不同的 `TAKE_COVER` 任务（不同 target_position），SECURITY 走后方 `HOLD_SECTOR`
3. **就位同步**：`ambush_aim` 任务 `minimum_success_count = ceil(就位数×0.7)`，成员到位后 `mark_member_succeeded` → 触发 `ambush_volley`
4. **超时兜底**（需给调度器补能力，见 §3）：超时就位上限（如 8s）→ 用已就位人员开火
5. **WEAPONS_HOLD 移动**：`STEALTH_APPROACH` 阶段所有移动任务 RoE = `WEAPONS_HOLD`（现在 `_compile_ambush` 只有 aim 用 WEAPONS_HOLD，移动没有）

**Utility 触发条件**（已有 AMBUSH 候选需加 gate）：
- 敌人未警觉（`average_awareness < 0.45`，现有）
- 我方未受压制（`suppression_ratio < 0.1`，现有）
- **有隐蔽接近路线**（新增 gate）：`influence.score_route` 到伏击阵地 > 阈值，且存在至少 1 个 `BASE_OF_FIRE` 合格成员

---

### 2.3 真正的交替跃进与交替撤退

**现状问题**：`BOUNDING_ADVANCE` 只生成一次 `bound_move`（移动 5m），没有"压制组→移动组→交换角色→再移动"的循环；`BREAK_CONTACT` 单次 `RETURN_TO_ORIGIN`。

**改造：跃进=两个子任务的循环**

```
BOUNDING_ADVANCE（循环）
└─ 每次迭代：
   ├─ bound_support：A组 SUPPRESS_CONTACT（压制，持续固定时长）
   └─ bound_move：B组 TAKE_COVER 前移 5m（依赖 support 完成）
   → 到达中点后：A/B 角色交换（`role_allocator.previous_roles` 提供连续性，主动翻转）
   → 重复直到到达目标 / 遇阻切换
```

**实现方式（推荐）**：
- **方案A（轻量，推荐）**：HTN 生成**单次双任务**，靠 `squad_advanced_tactics_3d.gd` 的 `_on_plan_completed` 检测目标未到 → 重新 `_compile_bounding_advance`，每次调用 `role_allocator` 前强制翻转 support/maneuver 角色分配（利用 `previous_roles` 反向，或加 `prefer_flipped` 标志）
- **方案B（重）**：HTN 显式展开 N 个任务序列。缺点：plan 变长、可维护性差，**不推荐**除非需要玩家可视化完整序列

**交替撤退（BREAK_CONTACT 改造）**：
```
BREAK_CONTACT（循环）
├─ rear_guard_suppress：A组压制敌人
└─ fallback_move：B组向 origin 交替后撤 5m（A 组掩护 B 组，B 到位后 B 掩护 A）
   → 重复直到全部撤回 origin / 无压力切换 DISENGAGE
```
- RoE：`RETURN_FIRE`（仅后撤时还击，不主动追击）

---

### 2.4 OCCUPY_AND_DEFEND 阵地部署

**现状**：`DEFEND_CONTACT`/`hold_objective` 按接触扇区把成员均匀分到防守位，**无"按入口/咽喉/设施/射界"的角色化分配，也无预备队**。

**改造**：
1. **新增阵地角色**：`SquadRoleAllocator3D` 增加 `ENTRY_GUARD` / `THROAT`（咽喉）/ `FACILITY`（设施）/ `SECTOR_WATCH`（射界），按阵地图元分配
2. **`_compile_defense` 改为按阵地分配**：
   - 从 `squad_advanced_tactics_3d.gd` 的 registered covers / structures 收集可用阵地
   - 咽喉/入口优先配给高威胁朝向成员
   - **保留 1 名 RESERVE**（现状 reserve 只在 `_compile_base_of_fire` 用）
3. **Utility 增加预备队权重**：成员 ≥ 5 时才启用 RESERVE 槽位（[PLACEHOLDER]，需 playtest 定）

---

### 2.5 CONSOLIDATE_AND_REGROUP

**现状**：`_average_ammo < 0.2` 触发 `CONSOLIDATE`，但 `_compile_...` 走的是 `recover_in_cover`，只有 TAKE_COVER + 暂停，**无换弹、无集合掉队、无重新分配**。

**改造为三阶段**：
```
CONSOLIDATE_AND_REGROUP
├─ 1. RALLY_POINT：全员向安全汇合点移动（TAKE_COVER，WEAPONS_HOLD）
├─ 2. REARM：低弹药成员执行 reload（新增 `REARM` 任务类型或复用 RECOVER_IN_COVER + 显式 reload 指令）
└─ 3. REALLOCATE：触发 FULL_TACTIC 重规划，`role_allocator` 按当前战力重新分配
```
- 需要**新增任务类型** `REARM`（或 `SquadTask3D.Type` 扩展），供调度器识别"换弹完成"（ammo 恢复到阈值）

---

## 3. 基础设施改造（跨意图共用）

### 3.1 调度器增加任务超时上限（最高优先级，阻塞项）

`_evaluate_task` 现在无超时保护，伏击/跃进可能死锁。**新增**：

```gdscript
# SquadTask3D 增加
var timeout_seconds := 0.0   # <=0 表示不超时
# SquadTaskScheduler3D._monitor_task_conditions 或新 _check_timeouts()
# 遍历 ACTIVE 任务，超时则：persistent 任务降级为已就位成员成功；普通任务标记失败 → 触发 plan_repair/replan
```

- 每个意图配置超时：AMBUSH 8s、BOUNDING_ADVANCE 单次迭代 6s、CONSOLIDATE 集合 5s
- **超时不是失败**：对伏击，超时后用已就位人员开火；对跃进，超时后保留已达位置重新同步

### 3.2 GAIN_FIRE_SUPERIORITY 去重

`ESTABLISH_BASE_OF_FIRE` 与 `FIX_AND_SUPPRESS` 走同一 `_compile_base_of_fire`，区别只在 Utility 权重。建议：
- `ESTABLISH_BASE_OF_FIRE`：机枪压制建立优势（机动前提）
- `FIX_AND_SUPPRESS`：轻步兵钉住敌人（防逃跑/准备追击）
- 拆成两个 HTN 编译分支或至少改 reason 区分，避免行为上"两战术重复"的观感

---

## 4. 改动文件清单

| 文件 | 改动类型 | 内容 |
|---|---|---|
| `squad_utility_evaluator_3d.gd` | 修改 | 新增 REACT_TO_UNKNOWN_FIRE 候选；AMBUSH 加隐蔽路线 gate；DEFEND 加预备队权重 |
| `squad_htn_planner_3d.gd` | 修改 | 新增 `_compile_react_unknown_fire`；重写 `_compile_ambush`（五阶段）；改造 `_compile_bounding_advance`/`_compile_break_contact`（循环）；改造 `_compile_defense`（阵地角色）；新增 `_compile_consolidate` |
| `squad_plan_compiler_3d.gd` | 修改 | 新增伏击/跃进/撤退/巩固的 plan 构造（多任务、依赖链、RoE） |
| `squad_role_allocator_3d.gd` | 修改 | 新增 ENTRY_GUARD/THROAT/FACILITY/SECTOR_WATCH 角色 + `prefer_flipped` 跃进交换标志 |
| `squad_task_scheduler_3d.gd` | 修改 | 新增任务超时上限检查（§3.1） |
| `squad_task_3d.gd` | 修改 | 新增 `timeout_seconds` 字段；新增 `REARM` 任务类型 |
| `squad_advanced_tactics_3d.gd` | 修改 | 新增伏击状态机；跃进/撤退的循环重触发逻辑；重规划时传 consolidated 状态 |
| `squad_mission_controller_3d.gd` | 不变 | 任务四阶段已覆盖（需确认 CLEARING 阶段能调 REACT_TO_UNKNOWN_FIRE，验证而非改） |

**新增文件**（可选，视实现方式）：
- `squad_ambush_state_3d.gd`：伏击状态机（推荐独立，便于调试）
- 若不独立，则并入 `squad_advanced_tactics_3d.gd`

---

## 5. 验证路径（先定义"坏掉长什么样"）

**失败信号定义**（每个 playtest 前必须明确）：
- **A（死锁）**：伏击/跃进在目标未达成时停止响应 > 5s，且无任何任务状态变化 → 调度器超时失效
- **B（反战术）**：伏击开火时敌人已警觉但仍全员开火；跃进时 A/B 组同时移动无人压制 → 同步/角色交换失效
- **C（不可解释）**：decision_trace 显示意图跳变 < 2s 内发生 > 3 次 → Utility 候选竞争/重规划过频

**验收标准**：
1. 伏击从触发到开火完整走完五阶段，且途中被发现能干净切换 CONTACT_COVER
2. 交替跃进至少完成 2 次角色交换（A→B→A）不中断
3. 防御部署按入口/咽喉/射界分配，且 ≥5 人时留 RESERVE
4. 未知火力 1s 内小队进入掩护，3s 内尝试识别来源
5. 巩固阶段低弹药成员完成 reload 后触发重分配

---

## 6. 待确认问题

1. **调度器超时语义**：超时后是"用已就位成员继续"还是"整体降级"？我倾向前者（韧性），但需你确认伏击意图想要的行为
2. **伏击状态机放哪**：独立 `squad_ambush_state_3d.gd` 还是并入 `squad_advanced_tactics_3d.gd`？取决于你调试习惯
3. **跃进循环方案**：方案A（重触发+角色翻转）轻量但每轮重规划；方案B（显式展开）可读但 plan 长。默认方案A
4. **REARM 是新增任务类型还是复用**：取决于弹药恢复是否已有独立指令（需查 `soldier_weapon_component_3d.gd`）
5. 所有未 playtest 的数值（伏击超时 8s、跃进迭代 6s、就位阈值 0.7 等）均标 **[PLACEHOLDER · 附假设与验证路径]**
