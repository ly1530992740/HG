# 敌人 AI「村长县城生态系统」总结

> 主理人：游承峰 ｜ 整理日期：2026-08-10 ｜ 依据：当前代码实况（village_lord_ai_3d.gd / county_commander_ai_3d.gd / threat_level_system_3d.gd / supply_convoy_3d.gd / game_calendar_3d.gd / world_registry_3d.gd / world_director_3d.gd）
> 用途：作为玩法讨论底稿 + 后续给外部 AI 的架构审查文档核心章节。

---

## 1. 一句话

**1 个县城（唯一决策中枢）+ N 个村庄领主（只感知上报执行）+ 1 套威胁值（总开关）+ 1 条辎重补给线**，全部通过 `WorldRegistry3D` 事件总线解耦；规则涌现、无脚本演出；玩家的每步操作都在生态里留下可被"感知 → 上报 → 决策 → 执行"消化的事件。

---

## 2. 生态角色与职责

### 2.1 村庄领主 `VillageLordAI3D`（每村一个，HFSM）
**定位：只感知、上报、执行县城指令，不做战略决策。**

**生命周期状态**（Godot StateChart 实现）：

```
Idle ──缺资源──▶ ShortageWait ──辎重送达──▶ Idle
  │                │
  ├─被攻打─▶ UnderAttack ──县城增援──▶ FightToDeath（坚守至死）
  │              │
  │              ├─县城放弃──▶ Retreat（撤退，村落入敌占）
  │              └─攻击被击退─▶ Idle
  └─被解放─▶ Liberated（玩家控制；被日军重占则回 Idle）
```

**感知循环**（每 0.5 秒一拍，玩家村不参与）：
| 感知 | 触发 | 上报 |
|---|---|---|
| ① 缺资源 | 食物/弹药/医疗低于阈值 | `resource_shortage` |
| ② 被攻打 | 外部行为事件置位 | `under_attack` |
| ③ 防御建造请求 | 每日评估/威胁感知/邻近被攻/UI 手动 | `request_defense_build` |
| ④ 辎重逾期 | 预期辎重超时未达 | `supply_late` |
| ⑤ 敌人位置 | 侦察小队发现 | `enemy_position` |

**关键约束**：
- **通信被毁 → 上报阻断**（`is_comm_destroyed()` 检查）——领主照常感知（状态机正常迁移）但发布被拦截 → 县城"不知道" → 不补给不求援 → **断供战术成立**。
- 玩家村（解放/驻守）不受日军领主指挥：不感知、不上报、不评估防御。

### 2.2 县城指挥官 `CountySeatCommanderAI3D`（全局唯一）
**定位：唯一决策中枢。** 消费领主上报 → 按数值评分 + 决策强度（威胁档位倍率）做决定 → 发布 Command → 装配器落地。

**决策枚举**：`SEND_SUPPLY / REINFORCE / ABANDON / DEFEND / BUILD_DEFENSE / REJECT_BUILD / SWEEP`

| 上报 | 县城决策 |
|---|---|
| `resource_shortage` | 记 pending → 县城库存够 → 派辎重；不够 → 等每日结算重试 |
| `under_attack` | 村庄价值分 ≥ 20×强度 且兵力池够 → 增援；分低 → 放弃（abandon）；**玩家村一律不增援** |
| `request_defense_build` | 价值分 ≥ 15 且库存够 → 批准建造；否则拒绝 |
| `supply_late` | 重发辎重 + 发布警戒事件（威胁 +8） |
| `enemy_position` | 记录精确位置 → 立即评估扫荡 |

**扫荡（模块 E）**：威胁 ≥ 60 + 冷却 120s → 选最近且通信完好的敌占村 → 以"精确敌人位置（否则威胁事件位置）"为中心生成 **3 个模糊侦察点** → 命令村庄派侦察小队逐点扫 → 发现敌人自动上报精确位置。

**威胁档位倍率** `[1.0, 1.5, 2.2, 3.0]`：威胁越高压决策强度越高（阈值 × 倍率 → 更积极增援/防御）。

### 2.3 威胁系统 `ThreatLevelSystem3D`（生态总开关）
- 档位阈值 `[25, 60, 100]`，上限 150，每日衰减 2。
- **行为权重**（玩家行动 → 威胁值）：

| 行为事件 | 威胁 |
|---|---|
| 占领村庄 occupied_village | +25 |
| 截获辎重 looted_convoy | +20 |
| 攻打村庄 attacked_village | +10 |
| 掠夺村庄 raided_village | +8 |
| 破坏电台 destroyed_comm | +5 |
| 摧毁工事 destroyed_defense | +5 |
| **击杀日军 killed_japanese** | **+1** |

- 档位变化 → 广播给县城（决策强度）与领主（防御感知"有威胁"）。

### 2.4 辎重补给线 `SupplyConvoy3D`
- 县城发 `send_supply` → 沿固定路线（县城→村）→ **护卫小队守卫式跟随**（FOLLOW 指令）→ 送达 → 村账本入账。
- **受击停止**：被打即原地停（halted），5 秒无受击自动恢复。
- **截获判定**：护卫全灭 → `looted` → 货物缴给最近玩家小队/玩家经济 + 威胁 +20。
- **逾期判定**：村庄登记预期辎重（ETA）→ 超时未达 → `supply_late` 上报。

### 2.5 日历 `GameCalendar3D`
- 每日结算节拍（`settlement_tick`）驱动：县城重试 pending 辎重、村落食物日耗、威胁衰减、电台/仓库自动修复、饥荒掉血、**大扫荡检查（第 7 天 + 有精确位置 → 重火力精确攻占）**。

### 2.6 事件总线 `WorldRegistry3D`（唯一通信通道）
```
ReportMessage（村→县）：resource_shortage / under_attack / request_defense_build / supply_late / enemy_position
CommandMessage（县→执行）：send_supply / reinforce / abandon / build_defense / sweep
BehaviorEvent（行为→威胁/收口）：looted_convoy / occupied_village / destroyed_comm / supply_late_confirmed …
```
业务模块互相零引用，全部经总线；装配器 `WorldDirector3D` 唯一接线 + 落地指令（spawn 辎重/增援/扫荡队、执行建造）。

---

## 3. 生态闭环链路（四条）

```
【补给闭环】村缺资源 →(report) 县城 →(command send_supply) 辎重+护卫 → 送达入账 →(resolve) 村回 Idle
            玩家破坏点：拆电台（断上报）/ 伏击辎重（截获+威胁）

【防御闭环】领主评估威胁+空槽位 →(report) 县城评估价值分 →(command build_defense) 装配器建造
            玩家破坏点：直接攻打工事（摧毁→耗材重建）

【求援闭环】村被攻打 →(report) 县城评分+兵力池 →(command reinforce/abandon) 增援或放弃
            玩家破坏点：拆电台（孤立村庄，县城不知情不增援）

【威胁闭环】玩家行为 →(behavior) 威胁值+档位 → 县城扫荡(3模糊点) → 侦察发现 →(enemy_position) 精确位置
            → 第7天 → 大扫荡精确攻占 → 村庄易主
```

---

## 4. 设计亮点（生态的"活"来源）

1. **信息不对称**：县城只知道"上报的内容"——拆电台就"致盲"它；扫荡是"模糊侦察→精确上报"的两段式情报链。
2. **数值化决策**：增援/放弃/建防都走"村庄价值分 × 决策强度"对比阈值，非拍脑袋。
3. **威胁是玩家行为的积分榜**：干什么涨多少清清楚楚（占村 25 > 截辎重 20 > 杀兵 1）。
4. **断供战术可成立**：电台破坏→上报阻断→县城不知→村持续缺粮→守军饿到 50%→弱化攻占。
5. **一切经总线**：加新模块只需接入总线协议，业务模块互不感知。

---

## 5. 待讨论的玩法平衡点

1. **威胁积分**：击杀日军仅 +1（杀一百个兵才 +100）——"杀敌"几乎不刺激生态，只有大动作（占村/截辎重）才涨。是否合理？
2. **县城兵力池**：只增不减？增援/扫荡/大扫荡派兵后兵力池是否要恢复（否则长期玩家必赢）？
3. **村庄价值分公式**（`_score_village`）：决定增援/放弃/建防，是生态平衡的命门——需要显式化并讨论。
4. **日军主动反击**：目前只有"扫荡+大扫荡"两类进攻性行为；日常是否有"骚扰式袭击"玩家村的需求？
5. **大扫荡后村庄易主**：村庄被日军重占后玩家失去解放区，如何让玩家"夺回"（二次解放）——目前领主 HFSM 支持 REOCCUPIED 回 Idle，但玩法闭环是否顺畅？

---

*待确认后并入 `docs/ai_review_codebase_guide.md` §1 玩法章节，供外部 AI 审查时对齐玩法意图。*
