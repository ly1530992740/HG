# NPC 行为系统 v2 — 设计交付摘要

> 日期：2026-08-04 · 项目：Holstin 风格二战生存战术游戏（Godot 4.x）

## 做了什么

在 v1（`npc_behavior_hfsm_prompt.md`）基础上，按用户拍板的 4 个决策升级非战斗人员（农民/医疗兵）行为系统，产出两套文档：

| 文档 | 读者 | 内容 |
|------|------|------|
| `docs/npc_behavior_hfsm_prompt_v2.md` | 程序 AI | 完整任务书：感知层、恐慌传染、医疗兵预留接口、掩体容量、验收 A-L |
| `docs/npc_animation_art_doc.md` | 美术/模型 | 动画表现规格：Pose 帧表、过渡帧、恐慌波浪、状态可视化、程序动画感四标准 |

## 关键设计决策（用户拍板 + 我的落地）

1. **无昼夜循环** → 感知靠 `PerceptionComponent`（0.5s tick，15m 警戒 / 6m 恐慌半径），不依赖 WaveDirector 波次信号（保留广播作为最强信号）
2. **玩家形态不变** → 村民/医疗兵永不进入 PLAYER_ORDER，指令只对士兵
3. **恐慌会传染** → `PanicContagion`：FLEE 时每 0.8s 广播恐惧脉冲，50% 概率传染，10s 免疫冷却，躲进掩体即熄火——波浪有传播速度、有衰减，防一锅端
4. **医疗兵预留接口** → `HealTargetProvider.get_heal_target()` 当前返回 null，未来接"伤员安全后自动进医疗室回血"（RESCUE 姿态已存在，伤者躺床姿态未来新增）

## 核心设计立场

- **传染 = 敌人的软攻击**：恐慌造成的生产停摆就是恐惧的机会成本，玩家用建营房/增援对冲
- **程序动画感拆成四条验收标准**：循环有节律 / 变化可预期 / 过渡有优先级（恐慌过渡 ≤0.2s 优先精修）/ 群体不同步（多米诺波浪，禁止同帧切换）
- **可读性兜底**：头顶状态图标（工具图标 / 白色 "!"），姿态 + 图标双通道，玩家扫一眼看清营地状态

## 全部数值为 [PLACEHOLDER]（带 rationale + 验证路径，见 v2 文档 §10）

perception 15m / threat 6m / contagion 8m / pulse 0.8s / chance 0.5 / immunity 10s / safe_confirm 3s / shelter_capacity 10/5 / FLEE speed 1.8

## 后续待办

- 程序 AI 按 v2 §13 实现顺序开工（感知 → 传染 → HFSM 接入 → 抑制 → 医疗兵占位）
- 验收 H-L（主动感知/传染/免疫/容量/表演节律）逐项过
- 美术侧优先做：恐慌跑变体 + WORK→跑 12 帧过渡 + 头顶图标（§9 清单）
- 未来：伤者躺床姿态（新增 Pose，程序零改动）、治疗流程接入 HealTargetProvider
