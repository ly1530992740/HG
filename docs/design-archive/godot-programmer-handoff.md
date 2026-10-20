# 程序交接手册 — Programmer Handoff

> 目标读者：程序 AI（只写功能代码，不碰模型/动画/美术数值）
> 项目：Holstin 风格二战生存战术游戏 · Godot 4.x
> 日期：2026-08-04 · 资产版本：v2（Holstin 风格）
> 本文档所有 API 签名已与源码逐字核对（2026-08-04）。

---

## 0. 交接原则（先读这页）

**程序 AI 永远不碰的**：模型几何、动画数值、像素绘制、配色。全部封装在 7 个资产入口后面。

**程序 AI 只做的**：
1. 实例化资产节点、调用公开方法、连接信号
2. 写 12 个功能模块的游戏逻辑
3. 完成 4 处模型替换（一行路径/类型改动）

**验证方式**：每个模块附验收标准（可测行为），全部在 Godot 编辑器内 F6 独立运行验证。

---

## 1. 资产使用总览（7 个入口）

所有资产在 `res://render/` 与 `res://combat3d/`，纯代码生成，零外部美术文件。

| # | 入口 | 文件 | 用途 |
|---|------|------|------|
| 1 | `HolstinCharacterVisual3D` | `combat3d/holstin_character_visual_3d.gd` | 3D 角色模型 + 11 姿态动画 |
| 2 | `VoxelBuildingGenerator` | `render/voxel_building_generator.gd` | 6 生活建筑 + 3 采集点 |
| 3 | `BuildingAnimation` | `render/building_animation.gd` | 建筑动画组件（建造/受损/生长/烟） |
| 4 | `CombatEffects2D` | `render/combat_effects_2d.gd` | 血迹/枪火/5 资源 UI 图标 |
| 5 | `HolstinPalette` | `render/holstin_palette.gd` | 全局配色（改色不改模型） |
| 6 | `HolstinCameraController` | `render/camera_controller_3d.gd` | 双视角相机（等距 + 越肩 TPS） |
| 7 | `HolstinPixelSprites` | `render/holstin_pixel_sprites.gd` | 2D 像素：顶视 16 方向 + 肩后动画集 |

另有替换适配器 `HolstinSoldierAdapter`（`render/holstin_soldier_adapter.gd`），见第 3 节。

### 1.1 角色 — HolstinCharacterVisual3D

```gdscript
# 创建（faction 必须在 _ready() 前设置）
var soldier := HolstinCharacterVisual3D.new()
soldier.faction = HolstinCharacterVisual3D.Faction.ALLY   # ALLY / ENEMY / VILLAGER / MEDIC
add_child(soldier)

# 每帧驱动动画：pose = 姿态枚举，frame = 动画帧号（递增，约 60/s）
soldier.update_pose(HolstinCharacterVisual3D.Pose.WALK, frame)
```

姿态枚举（11 种）：

```gdscript
enum Pose { IDLE, WALK, AIM, FIRE, RELOAD, DEATH, WORK_CHOP, WORK_FARM, WORK_BUILD, RESCUE, CARRY }
```

| 姿态 | 用途 |
|------|------|
| WORK_CHOP | 砍树（采集点联动） |
| WORK_FARM | 耕种（农牧场生产联动） |
| WORK_BUILD | 建造动作（建造过程联动） |
| RESCUE | 抬担架（医疗兵救人） |
| CARRY | 负重行走（背包/负重系统联动） |

### 1.2 建筑 — VoxelBuildingGenerator

```gdscript
enum BuildingType { FARM, FACTORY, MEDICAL, BARRACKS, MESS, WAREHOUSE, TREE, ROCK, SCRAP }

var visual := VoxelBuildingGenerator.build(VoxelBuildingGenerator.BuildingType.FARM)
visual.position = build_position          # 原点在地面中心，+Y 向上
add_child(visual)

# 采集点耗尽：主体隐藏，显示残骸
VoxelBuildingGenerator.set_depleted(tree_node)

# 几何约定：0.5m 体素块粒度；坐标原点 = 地面中心
```

### 1.3 建筑动画 — BuildingAnimation

```gdscript
var anim := BuildingAnimation.attach(visual)   # visual = VoxelBuildingGenerator.build() 返回值

anim.play_construction(1.5)                    # 建造升起（信号 construction_finished）
anim.set_damage_ratio(0.4)                     # 受损：变暗 + 冒烟（0..1）
anim.set_growth_stage(2)                       # 田垄生长：0 裸土 / 1 发芽 / 2 成熟（FARM 专用）
anim.set_stock_ratio(0.8)                      # 仓库存量可视化（WAREHOUSE 专用，0..1）
anim.start_smoke(Vector3(0, 2.5, 0))           # 烟囱/炊烟循环
anim.stop_smoke()
```

### 1.4 2D 贴片 — CombatEffects2D

```gdscript
# 血迹（随机深红，scale_size 控制世界尺寸）
add_child(CombatEffects2D.make_blood_stain(2.0))

# 枪火（径向橙黄光晕）
add_child(CombatEffects2D.make_muzzle_flash(0.8))

# 资源 UI 图标（32×32 像素画，直接塞 TextureRect）
enum ResourceIcon { FOOD, AMMO, WEAPON, MATERIAL, MEDICAL }
$HUD/FoodIcon.texture = CombatEffects2D.make_resource_icon(CombatEffects2D.ResourceIcon.FOOD)
```

### 1.5 配色 — HolstinPalette

```gdscript
# 改色不改模型：任何资产都用 palette 常量
var mat := HolstinPalette.make_material(HolstinPalette.WOOD_DARK)
# 阵营配色组
var pal := HolstinPalette.get_faction_colors(HolstinCharacterVisual3D.Faction.ENEMY)
```

### 1.6 相机 — HolstinCameraController

```gdscript
var cam := HolstinCameraController.new()
add_child(cam)
cam.set_target(player_node)          # 跟踪目标
cam.set_mode(HolstinCameraController.CameraMode.ISOMETRIC)   # ISOMETRIC / TPS
cam.toggle_mode()                    # Tab/摇杆 切换
cam.rotate_yaw(90.0)                 # Q/E 或鼠标横向
cam.set_yaw(deg) / cam.add_pitch(delta_deg)
# 信号：mode_changed(mode)
```

### 1.7 2D 像素 — HolstinPixelSprites

```gdscript
# 顶视小人纹理（16 方向 × 2 行走相位）
# 布局：hframes = 16, vframes = 2；frame = 方向索引 + (行走 ? 16 : 0)
var tex := HolstinPixelSprites.create_holstin_top_down_texture(
    HolstinCharacterVisual3D.Faction.ALLY, 16)

# 肩后动画集（武器参数化，全 17 model）
# 返回 {"ready": Tex, "aim": Tex, "fire": Tex, "reload": Tex}
# 每张为横向 strip：240×336 帧，帧数 4/4/4/8
var wd := {"family": "bolt_rifle", "model": "long_rifle",
           "wood_color": Color(...), "metal_color": Color(...)}
var set := HolstinPixelSprites.new().create_holstin_shoulder_animation_set(wd)
```

---

## 2. 模型替换清单（4 处引用点 + 适配器）

**不做"直接换模型"，做"适配器替换"**：程序 AI 改 4 处，玩家/AI 500+ 行战斗代码一行不动。

| # | 文件 | 行 | 动作 |
|---|------|----|------|
| 1 | `ai3d/soldier_3d.tscn` | 9 | ext_resource path → `res://render/holstin_soldier_adapter.gd` |
| 2 | `survival3d/player/third_person_player_3d.gd` | 65 | 类型注解 `VoxelSoldierVisual3D` → `HolstinSoldierAdapter` |
| 3 | `combat3d/components/limb_damage_component_3d.gd` | 10, 13 | 同上 |
| 4 | `ai3d/structures/machine_gun_emplacement_3d.gd`、`watchtower_3d.gd` | — | 同上（如有引用） |

**适配器已实现的兼容 API**（签名与旧 VoxelSoldierVisual3D 一致）：

```gdscript
func configure(faction: Faction) -> void            # JAPANESE→ENEMY, RED_ARMY/BLUE_ALLY→ALLY
func update_pose(delta, velocity, movement_mode, stance, aimed, firing, dead,
                 weapon_family := "bolt_rifle", blind_fire := false,
                 structure_pose := 0, structure_entry_progress := 1.0) -> void
func add_bullet_wound(hit_position: Vector3, impact_normal := Vector3.UP, hit_location := "") -> void
func play_hit(_location := "body") -> void           # 受击红闪
func play_death() -> void                            # 死亡姿态
func is_limb_detached(location: String) -> bool      # 恒 false（新模型无肢体分离）
func get_weapon_pivot_pose(weapon_family, stance, aimed, blind_fire) -> Transform3D
func get_character() -> HolstinCharacterVisual3D
func set_carry_mode(enabled: bool) -> void           # 负重行走
# 静态转发（肩后动画集）
static func create_red_army_shoulder_animation_set(weapon_definition := {}) -> Dictionary
static func create_red_army_shoulder_texture(weapon_definition := {}) -> Texture2D
static func create_top_down_texture(legacy_faction = Faction.RED_ARMY, direction_steps := 16) -> ImageTexture
```

> **注意**：`play_hit` / `play_death` / `is_limb_detached` / `get_weapon_pivot_pose` 是 2026-08-04 补齐的——旧版适配器缺这 4 个方法会导致 soldier_3d.gd 运行时报错。替换前确认你手上的 adapter 是最新版。

---

## 3. 功能模块（12 章）

每章八节模板：职责 → 数据模型 → 组件结构 → 交互流程 → 参数表 → 验收标准 → 资产调用示例 → 待填数值。

### 第 1 章 资源账本（ResourceLedger）— 纯逻辑，无资产

- **职责**：5 资源（食物/弹药/武器/建材/医疗）存储、上限、溢出处理；全局唯一实例（Autoload 或单例）。
- **数据模型**：

```gdscript
class_name ResourceLedger extends Node
signal resources_changed(resources: Dictionary)     # {"food": 12, "ammo": 0, ...}

@export var storage_capacity: int = 200             # [PLACEHOLDER]
var resources: Dictionary = {"food": 0, "ammo": 0, "weapon": 0, "material": 0, "medical": 0}
```

- **交互流程**：`add_resource(type, amount) -> int 实收`（超上限丢弃）→ 发信号 → UI 刷新。
- **验收标准**：① 添加超上限资源只收到容量值；② 5 种资源独立计数；③ 信号每次变更必发。
- **资产调用**：无（UI 图标用 `CombatEffects2D.make_resource_icon`）。
- **待填数值**：`storage_capacity`、各资源起始值。

### 第 2 章 背包/仓库（InventoryComponent）

- **职责**：角色背包（有限格）+ 仓库容量可视化（建筑资产联动）。
- **数据模型**：

```gdscript
class_name InventoryComponent extends Node
signal stack_changed(slot: int, item: Dictionary)

@export var slots: int = 12                         # [PLACEHOLDER]
var stacks: Array[Dictionary] = []
```

- **交互流程**：拾取 → 找同类型堆叠 → 否则空位 → 信号通知 UI。仓库节点挂 `set_stock_ratio(存量/容量)`。
- **验收标准**：① 同类型自动堆叠；② 满格拒绝拾取并提示；③ 仓库货堆随存量增减。
- **资产调用**：

```gdscript
warehouse_visual = VoxelBuildingGenerator.build(BuildingType.WAREHOUSE)
anim = BuildingAnimation.attach(warehouse_visual)
anim.set_stock_ratio(used / capacity)
```

### 第 3 章 采集（GatherInteraction）

- **职责**：玩家接近采集点 → 交互键 → 持续采集动画 → 按工具倍率产出 → 储量耗尽转残骸。
- **数据模型**：

```gdscript
class_name GatherNode extends Node3D
signal depleted
@export var resource_type: String = "material"      # material / weapon / food
@export var yield_per_cycle: int = 2                # [PLACEHOLDER]
@export var total_stock: int = 30                   # [PLACEHOLDER]
@export var gather_time: float = 1.2                # [PLACEHOLDER]
```

- **交互流程**：玩家进入范围 → 显示提示 → 按住交互 → 角色 `WORK_CHOP` 动画循环 → 每周期产出入账本 → 耗尽 `set_depleted()` + `depleted` 信号。
- **验收标准**：① 无工具也能采但倍率 0.5×；② 耗尽后无法再采且显示残骸；③ 动画与产出节奏同步。
- **资产调用**：

```gdscript
# 采集点：TREE / ROCK / SCRAP
visual = VoxelBuildingGenerator.build(VoxelBuildingGenerator.BuildingType.TREE)
soldier.update_pose(HolstinCharacterVisual3D.Pose.WORK_CHOP, frame)
VoxelBuildingGenerator.set_depleted(visual)   # 耗尽
CombatEffects2D.make_muzzle_flash(0.5)        # 可选：砍石火花
```

### 第 4 章 建造 3D 化（ConstructionSystem）

- **职责**：建造菜单 → ghost 预览（网格吸附/合法性）→ 确认扣资源 → 生成建筑 + 升起动画。
- **数据模型**：

```gdscript
class_name BuildingRecipe extends Resource
@export var building_type: VoxelBuildingGenerator.BuildingType
@export var cost: Dictionary                      # {"material": 30, ...} [PLACEHOLDER]
@export var build_time: float = 3.0               # [PLACEHOLDER]
```

- **交互流程**：选配方 → ghost 半透明预览（合法绿/非法红）→ 确认 → 扣资源 → 实例化 + `play_construction` → 完成后可用。
- **验收标准**：① 网格吸附正确；② 资源不足无法确认；③ 建造动画完整升起（信号触发收尾）。
- **资产调用**：

```gdscript
var visual := VoxelBuildingGenerator.build(recipe.building_type)
visual.position = snapped_pos
add_child(visual)
var anim := BuildingAnimation.attach(visual)
anim.play_construction(build_time)
anim.construction_finished.connect(_on_built)
```

### 第 5 章 生产（ProductionSystem）

- **职责**：农牧场（工人 → 田垄生长 → 收粮）、兵工厂（产弹药/武器）、医疗室（产医疗包）。
- **数据模型**：

```gdscript
class_name ProductionBuilding extends Node3D
@export var production_type: String = "farm"      # farm / factory / medical
@export var cycle_time: float = 10.0              # [PLACEHOLDER]
@export var output: Dictionary                    # {"food": 2} [PLACEHOLDER]
@export var worker_required: int = 1
```

- **交互流程**：分配人口 → 开始循环 → 田垄 `set_growth_stage(0→1→2)` 或烟囱 `start_smoke()` → 产出入账本 → 工人 `WORK_FARM` 动画。
- **验收标准**：① 无工人不生产；② 生长阶段按时间推进；③ 产出准时入账本。
- **资产调用**：

```gdscript
anim.set_growth_stage(stage)          # 0 裸土 → 1 发芽 → 2 成熟
anim.start_smoke(Vector3(0, 2.5, 0))  # 兵工厂/食堂炊烟
villager.update_pose(HolstinCharacterVisual3D.Pose.WORK_FARM, frame)
```

### 第 6 章 维护/耐久（DurabilityComponent）

- **职责**：建筑受击扣耐久 → 受损表现（变暗冒烟）→ 耐久归零摧毁 → 维修交互恢复。
- **数据模型**：

```gdscript
class_name DurabilityComponent extends Node
signal damaged(ratio: float)
signal destroyed
@export var max_durability: float = 100.0          # [PLACEHOLDER]
var durability: float
```

- **验收标准**：① 受损比例驱动外观（0.3/0.6/0.9 三档）；② 维修逐步恢复；③ 归零触发摧毁逻辑。
- **资产调用**：`anim.set_damage_ratio(1.0 - durability / max_durability)`。

### 第 7 章 人口/职业（PopulationSystem）

- **职责**：人口上限、职业转换（村民↔士兵↔医疗兵）、死亡减员。
- **数据模型**：

```gdscript
class_name PopulationSystem extends Node
signal population_changed(total: int, roles: Dictionary)
@export var max_population: int = 20               # [PLACEHOLDER]
```

- **验收标准**：① 转换即时换阵营外观；② 上限拦截；③ 死亡减员正确。
- **资产调用**：

```gdscript
# 换职业 = 换 faction 重建
visual.configure(HolstinSoldierAdapter.Faction.RED_ARMY)  # 村民 → 士兵
```

### 第 8 章 玩家控制（PlayerController）

- **职责**：TPS 移动射击（复用现有 `third_person_player_3d.gd`）+ 指令系统（移动/采集/建造/攻击目标）。
- **验收标准**：① 替换适配器后移动/射击/弹孔不崩；② 双视角切换流畅；③ 指令下达后寻路执行。
- **资产调用**：适配器替换（见第 2 节）+ `HolstinCameraController` + 肩后动画集。

### 第 9 章 波次系统（WaveDirector）

- **职责**：X 天触发 → 强度表生成波次 → 预告 UI → 生成敌人（复用 ai3d squad 管线）。
- **数据模型**：

```gdscript
class_name WaveDirector extends Node
signal wave_announced(day: int, strength: int)
@export var first_wave_day: int = 3                # [PLACEHOLDER]
@export var wave_strength_curve: Curve             # [PLACEHOLDER]
```

- **验收标准**：① 波次按表触发；② 强度随天数增长；③ 预告提前展示。
- **资产调用**：敌人用 `HolstinCharacterVisual3D.Faction.ENEMY`。

### 第 10 章 敌人 AI 大脑（EnemyDirector）

- **职责**：巡逻/响应枪声/搜索/攻击基地建筑——镜像 ai3d squad 决策管线（有现成 `squad_utility_evaluator_3d.gd` 等）。
- **验收标准**：① 听到枪声响应；② 攻击建筑触发耐久；③ 死亡减员。
- **资产调用**：`Faction.ENEMY` + `CombatEffects2D.make_blood_stain`。

### 第 11 章 渲染管线接入（RenderPipeline）

- **职责**：320×180 低分辨率 SubViewport + `holstin_post.gdshader` 后处理挂接（shader 在 `render/shaders/`）。
- **验收标准**：① 全场景低分辨率渲染；② 后处理生效（暗角/颗粒/调色）；③ 双视角共用管线。
- **资产调用**：shader 文件 + `HolstinPalette`。

### 第 12 章 潜入偷取（StealSystem）

- **职责**：读敌人巡逻 → 潜行接近 → 交互偷取资源 → 被发现风险。
- **验收标准**：① 偷取成功入账本；② 被发现触发警戒。
- **资产调用**：通用交互 + `CombatEffects2D`（无新资产）。

---

## 4. 测试流程

**分层测试**（每层都有明确入口）：

### 4.1 资产冒烟（替换后立刻做，5 分钟）

1. 打开任意含 AI 士兵的场景（如 `ai3d` 内测试场景），F6 运行。
2. 确认：士兵显示为 Holstin 体素造型、走路/瞄准/开火/死亡动画正常。
3. 打开玩家场景，F6：移动、射击、弹孔、越肩视角正常。
4. 打开建筑场景：`VoxelBuildingGenerator` 9 种建筑逐一实例化显示正常。

### 4.2 模块测试（每章独立 F6）

| 模块 | 测试场景 | 关键断言 |
|------|---------|---------|
| 资源账本 | 空场景 + 脚本 | 5 资源独立、上限、信号 |
| 采集 | 放 1 个 TREE | 按住交互 → 产出 → 耗尽残骸 |
| 建造 | 放 1 个 ghost | 吸附/成本/升起动画 |
| 生产 | 放 1 个 FARM + 工人 | 生长分阶 → 产出 |
| 波次 | 空场景 | 预告 → 生成 → 强度表 |

### 4.3 集成测试（完整流程）

天 1 采集 → 天 2 建造基地 → 天 3 第一波防守 → 医疗兵救人 → 潜入偷取。全程无报错、无资源穿模、无敌对 AI 卡死。

---

## 5. 验收流程（发布门槛）

| 关卡 | 标准 | 通过条件 |
|------|------|---------|
| **资产验收** | 4 处替换完成，无运行时报错 | 资产冒烟 3 步全过 |
| **模块验收** | 12 章逐章行为符合验收标准 | 每章断言全绿 |
| **集成验收** | 完整流程 15 分钟无崩溃 | 流程测试通过 |
| **代码规范** | 静态类型、信号 snake_case、组件化 | 无未类型 var、无 get_node 硬编码路径 |
| **性能** | 百人同屏 + 20 建筑 | 无 `_process` 轮询状态、无每帧新建资源 |

**退出条件**：以上 5 关全过 → 资产/功能交接完成，可进入玩法打磨。

---

## 附：替换后第一件事（程序 AI 启动清单）

```bash
1. 拉取最新代码（适配器含 4 个新方法）
2. 按第 2 节改 4 处引用点
3. 跑 4.1 资产冒烟
4. 从第 1 章资源账本开始逐章实现
```
