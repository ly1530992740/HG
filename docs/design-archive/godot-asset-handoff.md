# world3d 占位资产交接清单（美术 / 动画）

> 版本：v3.0 ｜ 日期：2026-08-08 ｜ 作者：eng-lead（程基岩）
> 用途：world3d 最小垂直切片全部使用最简单占位（Box3D/Capsule3D + 纯色），
> 本文逐项说明每个 placeholder「应替换成什么 + 挂点节点路径」。
> 原则：程序代码不依赖任何模型/动画/贴图，替换只动场景节点，代码零改动。
> 迭代三增量：铁丝网占位（§8.4）、玩家村落预设防线（§2.3）、通信破坏状态（§2.2）、解放区生产建筑占位（§9）。

---

## 0. 总览

| 类别 | 占位形态 | 替换目标 | 挂点路径 |
|---|---|---|---|
| 县城 | Box3D 6×2.4×6 暗红 + Label3D | 县城建筑组（县署/城墙/兵营） | `world3d_* / CountySeat / VisualPlaceholder` |
| 村落 | Box3D 4×2×4 土黄/暗红 + Label3D | 村落建筑组（民房/据点） | `world3d_* / <village_id> / VisualPlaceholder` |
| 辎重队 | Box3D 1.2×0.9×2 土黄 + 红旗 + Label3D | 马车/板车 + 辎重箱 + 旗帜 | `world3d_* / <convoy_id> / VisualPlaceholder` |
| 士兵（护卫/增援/守军） | **已接真实 ai3d Squad**（Soldier3D 自带模型） | 士兵模型（现有 ai3d Soldier3D） | 见 §3 |
| 机枪阵地 | 矮 Box 1.6×0.5×1.4 + 枪管圆柱 + Label3D | 机枪巢/沙袋掩体 | `world3d_* / <village_id> / DefenseSlot_0/1/3`（见 §8） |
| 哨塔 | 高柱 0.7×3.2×0.7 + 顶部平台 + Label3D | 瞭望塔/岗楼 | `world3d_* / <village_id> / DefenseSlot_2/4`（见 §8） |
| 铁丝网 | 三柱 + 两横铁丝条（金属灰）+ Label3D | 铁丝网卷/拒马 | `world3d_* / <village_id> / DefenseSlot_5/6/7`（见 §8.4） |
| 通信占位 | 小电台盒 + 状态 Label（完好/已毁） | 电台/电话线模型（破坏态切换） | `world3d_* / <village_id> / CommPlaceholder`（见 §2.2） |
| 生产建筑 | VoxelBuildingGenerator 程序化建筑 + 村民 Capsule | 农场/兵工厂/医疗站模型 | `world3d_* / <village_id> / <farm|factory|medical>_<msec>`（见 §9） |
| 路线 waypoint | Path3D 曲线 + 编辑器小球 | 公路/山路 mesh + 路标 | `world3d_* / RouteMain` |

---

## 1. 县城（CountySeatEntity3D）

- **挂点路径**：`<场景根>/CountySeat/VisualPlaceholder`（`_build_visual()` 自动创建）
- **当前占位**：BoxMesh 6×2.4×6，暗红 `#6b2920`，roughness 1.0；Label3D "县城/<entity_id>"（pixel_size 0.012，y+3.2）
- **应替换成**：县城主体（县署）+ 围墙 + 兵营；建议子节点：
  - `VisualPlaceholder/Main`（县署）
  - `VisualPlaceholder/Barracks`（兵营，增援出生视觉锚点）
  - `VisualPlaceholder/Flag`（日军旗，被占可换玩家旗）
- **程序引用**：仅位置 `CountySeat.global_position`；增援小队出生点取 `CountySeat.global_position`。

## 2. 村落（VillageEntity3D）

- **挂点路径**：`<场景根>/<village_id>/VisualPlaceholder`
- **当前占位**：BoxMesh 4×2×4，伪军村土黄 `#736b4d` / 日军村暗红 `#b73d33`；Label3D 显示 类型 + entity_id
- **应替换成**：村落建筑组（民房/据点/塔防），建议：
  - `VisualPlaceholder/Houses`（民房群）
  - `VisualPlaceholder/DefenseTower`（塔防占位，后续自动防御逻辑挂点）
  - `VisualPlaceholder/Flag`（敌占/解放旗帜切换）
- **状态色建议**：解放后可用蓝绿色调标识（程序已提供 `state_changed` 信号，美术侧监听切换贴图/颜色）。

### 2.1 守军挂点（重要）
- **挂点路径**：`<场景根>/<village_id>/GarrisonRoot/<Garrison Squad 根节点>`（迭代二起由 `WorldDirector3D._spawn_garrison` 实例化真实 Enemy3D 小队，节点名如 `ScoutRaiderSquad3D` / `HeavySupportSquad3D`，子成员 `Members/*`）
- **用途**：守军真实 `Soldier3D`。`garrison_count` 由程序维护并与小队成员数对齐（`_trim_squad_members` 精简）。
- **替换说明**：士兵模型即 `ai3d/soldier_3d.tscn` 自带（红队/蓝灰迷彩由 `_apply_team_visual` 自动切换），无需美术额外接。若要换日军/伪军外观，改 `HolstinSoldierAdapter` 派系配置即可，代码零改动。
- **当前状态（迭代二）**：从"无占位士兵"升级为"真实 ai3d 小队"，守军全灭 → 村落解放流程已接。

### 2.2 通信占位（信息战预留）
- **挂点路径**：`<场景根>/<village_id>/CommPlaceholder`
- **当前**：小电台盒（BoxMesh 0.8×0.5×0.4，完好黄绿 `#808052`）+ Label3D "通信完好/通信已毁"。`comm_destroyed` 为 true 时盒体变灰黑 `#474747`、Label 变"通信已毁"（破坏→视觉+日志+威胁+5；上报延迟机制下轮）。
- **应替换成**：电台（`Radio`）/ 电话线（`TelephoneLine`）模型 + 完好/毁坏两态；后续"破坏→上报延迟"逻辑在此挂交互碰撞体。

### 2.3 玩家村落（解放区）预设防线
- **挂点路径**：`<场景根>/<village_id>/DefenseSlot_*`（全部槽位）
- **当前**：`owner=PLAYER` 的村落在进场景时所有防御槽位直接 `BUILT`（占位防线：机枪/哨塔/铁丝网全绿），Label3D 显示状态。
- **应替换成**：玩家解放区的"预设防线"整体（沙袋/工事/铁丝网围栏），建议监听 `build_state_changed` 或轮询 `build_state` 切换显示。
- **程序引用**：`village.owner`（控制方）、`defense_slots[*].build_state`（防线状态）。

## 3. 士兵占位（护卫 / 增援 / 守军）

> 迭代二状态：三处已从占位士兵（CapsuleMesh）升级为**真实 ai3d Squad**（复用 `Prefab/Enemy3D/` 与 `Prefab/Ally3D/`，`Soldier3D` 自带视觉）。占位 `make_placeholder_soldier` 工厂保留作遗留兼容，新代码不再使用。

### 3.1 辎重护卫
- **挂点路径**：`<场景根>/<convoy_id>/EscortRoot/ScoutRaiderSquad3D/Members/*`（`WorldDirector3D._spawn_escort` 实例化，节点名带 `escort_<convoy_id>` squad_id）
- **当前**：scout 小队精简编（escort_count 默认 2 人），真实 `Soldier3D`；Director `_process` 每 tick `set_runtime_mission_target(辎重位置, 3)` 跟随。
- **应替换成**：无需替换（已用真实 ai3d 士兵模型）；如要改护卫外观走 `HolstinSoldierAdapter` 派系。

### 3.2 增援小队
- **挂点路径**：`<场景根>/<Director 子节点>`（节点名 `reinforce_<village_id>_<msec>`，成员 `EastReinforcementSquad3D/Members/*`）
- **当前**：真实 `east_reinforcement_squad_3d.tscn`（6 人），县城出发 `set_runtime_mission_target(村落,9)` 奔赴；到达后 `issue_defense_order` 并入防守。
- **应替换成**：无需替换；若增援需独特外观（如日军野战服）走 `Soldier3D` 配置。

### 3.3 村落守军
- **挂点路径**：`<场景根>/<village_id>/GarrisonRoot/<Scout|Heavy>Squad3D/Members/*`
- **当前**：伪军村 scout（3 人弱编）、日军村 heavy（5 人强编），按 `garrison_count` 精简对齐；`issue_defense_order(村中心,8)` 装配防御。
- **应替换成**：无需替换（真实 ai3d 士兵）。

### 3.4 攻打部队（模拟玩家游击队）
- **挂点路径**：`<场景根>/<Director 子节点>`（节点名 `ally_attack_<village_id>_<msec>`，成员 `AllyDefenseSquad3D/Members/*`）
- **当前**：`ally_defense_squad_3d.tscn`（Ally 蓝队，3 人），由沙盒 UI/测试 `spawn_ally_attack` 生成，走向村落与守军 RED 真实交战。
- **应替换成**：无需替换；后续若玩家游击队有专属模型，换该预制体内部 `Soldier3D` 即可。

## 4. 辎重队（SupplyConvoy3D）

- **挂点路径**：`<场景根>/<convoy_id>/VisualPlaceholder`
- **当前占位**：BoxMesh 1.2×0.9×2（土黄 `#b8852e`）+ 红旗 BoxMesh 0.9×0.5×0.05（红 `#d93333`）+ Label3D "辎重/<id>"
- **应替换成**：板车/马车 + 可数箱包（food/ammo/medical 分色）+ 旗杆；建议：
  - `VisualPlaceholder/Cart`（车体）
  - `VisualPlaceholder/Cargo`（货物，可做被打劫后的空车态）
  - `VisualPlaceholder/Flag`
- **进度标识**：`progress_updated(convoy_id, progress)` 信号可用于动画（如车轮转动、烟尘）。

## 5. 路线（RoutePath3D）

- **挂点路径**：`<场景根>/RouteMain`
- **当前**：Path3D 曲线（编辑器中每个 waypoint 有半透明小球 `WaypointMarker_*`，仅编辑器可见）。
- **应替换成**：沿曲线铺设的公路/山路 mesh + 路标；程序只读 `sample_point(progress)`，替换不动代码。
- **注意**：`sample_point` 假设 RoutePath3D 单位缩放、无旋转；若美术旋转路线，需同步更新采样逻辑。

## 6. 占位颜色速查

| 对象 | 色值 | 说明 |
|---|---|---|
| 县城 | `#6b2920` | 暗红 |
| 伪军村 | `#736b4d` | 土黄（弱） |
| 日军村 | `#b73d33` | 暗红（强） |
| 辎重车体 | `#b8852e` | 土黄 |
| 辎重旗 | `#d93333` | 红 |
| 护卫兵 | `#6b5a47` | 土黄 |
| 增援兵 | `#4d6b4d` | 军绿 |

---

## 7. 替换验收清单（美术交付时对照）

- [ ] 县城/村落：删除 `VisualPlaceholder` 下占位 mesh，换成建筑组；程序引用（entity.global_position / garrison_root / comm_placeholder / defense_slots）不动
- [ ] 士兵：三处已是真实 `Soldier3D`（GarrisonRoot / EscortRoot / reinforce_*）；如需换外观走 `HolstinSoldierAdapter` 派系，勿改 `ai3d/soldier_3d.tscn` 结构
- [ ] 辎重：`VisualPlaceholder` 换车模 + 货物；确认 `Label3D` 可去掉后 HUD 仍有辎重进度（HUD 读信号，不读 Label3D）
- [ ] 路线：沿 Path3D 铺路；确认 RoutePath3D 保持单位缩放/无旋转
- [ ] 防御阵地：`DefenseSlot_0/1/3`（机枪阵地）、`DefenseSlot_2/4`（哨塔）、`DefenseSlot_5/6/7`（铁丝网）换模型；程序只读 `build_state` / `global_position` / `slot_type`，替换后重跑验收确认全 PASS
- [ ] 生产建筑：`<village_id>/<farm|factory|medical>_*` 换模型（现状为 render/ 程序化体素建筑）；程序只读 `production_type` / `growth_stage` / `assigned_workers` / `production_completed` 信号，替换后重跑 V11 确认产出入账
- [ ] 玩家村落预设防线：解放区整体防线替换后确认 V7 断言（owner=PLAYER + 全槽 BUILT）仍通过

---

## 9. 解放区生产建筑占位（迭代三新增）

### 9.1 农场 / 兵工厂 / 医疗站
- **挂点路径**：`<场景根>/<village_id>/farm_<msec>`、`factory_<msec>`、`medical_<msec>`（`SandboxVillageProduction.build` 动态创建）
- **当前占位**：复用 `render/voxel_building_generator.gd` 的程序化体素建筑（FARM 田垄 / FACTORY 烟囱 / MEDICAL 红十字）+ `render/building_animation.gd`（烟囱冒烟、farm 生长 3 阶段）；村民占位 = CapsuleMesh 土黄 `#9e8059`（`VillagerPlaceholder_*`）。
- **应替换成**：解放区功能性建筑模型 + 村民模型；程序只读 `production_type` / `growth_stage`（0..2）/ `assigned_workers.size()` / `production_completed(output)` 信号（产出已写入村落账本，UI 轮询显示）。
- **交接注意**：建筑产出与账本已由 `ProductionBuilding` 完成（survival3d/holstin，未改动），美术替换只动视觉节点。

---

## 8. 防御阵地占位（迭代二新增）

### 8.1 机枪阵地（MACHINE_GUN_NEST）
- **挂点路径**：`<场景根>/<village_id>/DefenseSlot_0`、`DefenseSlot_1`（默认 2 个；沙盒可用 SandboxConfig 覆盖）
- **当前占位**：矮 BoxMesh 1.6×0.5×1.4 + 枪管 CylinderMesh（高 1.0，半径 0.07）+ Label3D「机枪阵地/状态」；建造状态配色：EMPTY 灰 / BUILDING 琥珀 / BUILT 军绿。
- **应替换成**：机枪巢/沙袋掩体 + 机枪模型（自动射击动画挂点）；建议子节点 `DefenseSlot_*/Gun`（枪口，后续射击弹道锚点）。
- **程序引用**：`build_state`（状态）、`global_position`（位置）、`slot_type`（类型）。

### 8.2 哨塔（WATCHTOWER）
- **挂点路径**：`<场景根>/<village_id>/DefenseSlot_2`
- **当前占位**：高柱 BoxMesh 0.7×3.2×0.7 + 顶部平台 1.2×0.2×1.2 + Label3D「哨塔/状态」；BUILT 配色木棕。
- **应替换成**：瞭望塔/岗楼模型（顶部可站人，后续驻守/射击挂点）。
- **程序引用**：同上。

### 8.3 状态与交接注意事项
- `DefenseSlot3D` 状态机：EMPTY→BUILDING→BUILT（DESTROYED 预留）。美术只需按状态切换模型显示（监听 `build_state_changed(slot_index, state)` 或轮询 `build_state`）。
- 自动防御（机枪射击）本轮不做；`_process` 内 TODO 挂点已留，下轮在 BUILT 后接 ai3d weapon_component。

### 8.4 铁丝网（BARBED_WIRE，迭代三新增）
- **挂点路径**：`<场景根>/<village_id>/DefenseSlot_5/6/7`（默认 3 处；沙盒可覆盖）
- **当前占位**：三根立柱（BoxMesh 0.08×0.6×0.08）+ 两横铁丝条（BoxMesh 1.7×0.04×0.04，金属灰 `#6b6b73`）+ 两端斜刺圆柱 + Label3D「铁丝网/状态」；BUILT 配色金属灰 `#8c8c99`（柱体），横丝恒定金属灰。
- **应替换成**：铁丝网卷/拒马/鹿砦模型（低矮、带刺）；建议子节点 `DefenseSlot_*/Barb`（刺尖，后续伤害判定锚点）。
- **程序引用**：`build_state` / `global_position` / `slot_type`（与其他槽位一致）。
