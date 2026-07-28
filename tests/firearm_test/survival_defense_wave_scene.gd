extends Node2D
class_name SurvivalDefenseWaveController

@export_category("生存模式配置")
@export_range(0, 99999, 1) var initial_points := 100

@onready var player: Node2D = $Player
@onready var wave_spawner: SquadWaveSpawner = $EnemyWaveSpawner
@onready var wave_label: Label = $CanvasLayer/WaveHud/Margin/VBox/Wave
@onready var remaining_label: Label = $CanvasLayer/WaveHud/Margin/VBox/Remaining
@onready var ammo_label: Label = $CanvasLayer/WaveHud/Margin/VBox/Ammo
@onready var status_label: Label = $CanvasLayer/WaveHud/Margin/VBox/Status
@onready var squad_commands_label: RichTextLabel = $CanvasLayer/SquadCommandPanel/Margin/VBox/Commands

var _countdown_deadline_msec := 0
var _countdown_wave_number := 0
var _active_wave_number := 0
var _hud_refresh_timer := 0.0

func _ready() -> void:
	SurvivalEconomy.reset(initial_points)
	GlobalPlayer.set_active_pawn(player)
	wave_spawner.wave_countdown_started.connect(_on_wave_countdown_started)
	wave_spawner.wave_spawned.connect(_on_wave_spawned)
	wave_spawner.wave_cleared.connect(_on_wave_cleared)
	wave_spawner.all_waves_completed.connect(_on_all_waves_completed)
	SurvivalEconomy.points_changed.connect(_on_points_changed)
	call_deferred("_bind_player_weapon")
	status_label.text = "守住中心阵地，消灭敌人获取积分"

func _process(delta: float) -> void:
	_hud_refresh_timer -= delta
	if _hud_refresh_timer > 0.0:
		return
	_hud_refresh_timer = 0.2
	_update_wave_hud()
	_update_squad_commands()

func _bind_player_weapon() -> void:
	var weapon := player.get("firearm_weapon") as FirearmWeapon
	if weapon == null:
		ammo_label.text = "武器尚未准备"
		return
	weapon.ammo_changed.connect(_on_ammo_changed)
	weapon.weapon_changed.connect(_on_weapon_changed)
	_on_ammo_changed(weapon.magazine_ammo, weapon.reserve_ammo)
	_on_weapon_changed(weapon.weapon_data)

func _on_wave_countdown_started(wave_number: int, seconds: float) -> void:
	_countdown_wave_number = wave_number
	_countdown_deadline_msec = Time.get_ticks_msec() + int(seconds * 1000.0)
	status_label.text = "整理弹药、购买装备并调整防线"

func _on_wave_spawned(wave_number: int, _squads: Array[SquadGroup]) -> void:
	_active_wave_number = wave_number
	_countdown_deadline_msec = 0
	status_label.text = "敌军进入防区"

func _on_wave_cleared(wave_number: int) -> void:
	status_label.text = "第 %d 波已肃清" % wave_number

func _on_all_waves_completed() -> void:
	_countdown_deadline_msec = 0
	status_label.text = "全部防守波次完成"

func _on_points_changed(_points: int, delta: int) -> void:
	if delta > 0:
		status_label.text = "获得 %d 积分，可按 B 打开商城" % delta

func _on_ammo_changed(magazine: int, reserve: int) -> void:
	ammo_label.text = "弹药 %d / %d" % [magazine, reserve]

func _on_weapon_changed(data: WeaponData) -> void:
	if data != null:
		ammo_label.tooltip_text = data.weapon_name

func _update_wave_hud() -> void:
	if wave_spawner.completed:
		wave_label.text = "防守完成"
		remaining_label.text = "阵地安全"
		return
	if _countdown_deadline_msec > 0:
		var seconds_left := maxi(0, ceili(float(_countdown_deadline_msec - Time.get_ticks_msec()) / 1000.0))
		wave_label.text = "第 %d 波倒计时：%d 秒" % [_countdown_wave_number, seconds_left]
	else:
		wave_label.text = "第 %d / %d 波  %s" % [_active_wave_number, wave_spawner.waves.size(), _get_wave_name(_active_wave_number)]
	remaining_label.text = "剩余敌人：%d" % _count_alive_wave_enemies()

func _get_wave_name(wave_number: int) -> String:
	var index := wave_number - 1
	if index < 0 or index >= wave_spawner.waves.size() or wave_spawner.waves[index] == null:
		return "准备中"
	return wave_spawner.waves[index].wave_name

func _count_alive_wave_enemies() -> int:
	var alive := 0
	for squad in wave_spawner.active_squads:
		if not is_instance_valid(squad):
			continue
		for actor in squad.get_configured_member_actors():
			if is_instance_valid(actor) and actor.is_combat_alive():
				alive += 1
	return alive

func _update_squad_commands() -> void:
	var squads: Array[SquadGroup] = []
	for candidate in get_tree().get_nodes_in_group("squad_group"):
		if candidate is SquadGroup:
			squads.append(candidate as SquadGroup)
	squads.sort_custom(func(a: SquadGroup, b: SquadGroup):
		return _get_squad_name(a).naturalnocasecmp_to(_get_squad_name(b)) < 0
	)
	if squads.is_empty():
		squad_commands_label.text = "暂无小队"
		return
	var lines: PackedStringArray = []
	for squad in squads:
		if not lines.is_empty():
			lines.append("")
		lines.append("【%s】" % _get_squad_name(squad))
		if not squad is SquadCoordinator or (squad as SquadCoordinator).leader == null:
			lines.append("队长：无")
			lines.append("指令：空")
			continue
		var coordinator := squad as SquadCoordinator
		var leader_name := "小队长"
		if is_instance_valid(coordinator.leader.actor):
			leader_name = coordinator.leader.actor.name
			if coordinator.leader.actor.has_method("get_combat_role_label"):
				leader_name = coordinator.leader.actor.get_combat_role_label()
		lines.append("队长：%s" % leader_name)
		lines.append("指令：%s" % _get_commander_summary(coordinator))
	squad_commands_label.text = "\n".join(lines)

func _get_squad_name(squad: SquadGroup) -> String:
	if not squad.squad_display_name.is_empty():
		return squad.squad_display_name
	return String(squad.squad_id) if squad.squad_id != &"" else squad.name

func _get_commander_summary(coordinator: SquadCoordinator) -> String:
	var parts: PackedStringArray = []
	if coordinator is LlmSquadCoordinator:
		var llm := coordinator as LlmSquadCoordinator
		var llm_plan := String(llm.last_llm_plan)
		if LlmSquadCoordinator.PLAN_LABELS.has(llm_plan):
			parts.append(String(LlmSquadCoordinator.PLAN_LABELS[llm_plan]))
	var board := coordinator.get_blackboard()
	var tactical_plan := String(board.get_fact(&"tactical_plan", ""))
	var plan_label := _get_plan_label(tactical_plan)
	if not plan_label.is_empty() and not parts.has(plan_label):
		parts.append(plan_label)
	var order := board.current_order
	if order != null:
		var order_label := _get_order_label(order.type)
		if not parts.has(order_label):
			parts.append(order_label)
	return "、".join(parts) if not parts.is_empty() else "待命"

func _get_plan_label(plan_name: String) -> String:
	match plan_name:
		"SEARCH_HALT": return "原地警戒"
		"SEARCH_SWEEP": return "队形搜索"
		"CONTACT_TO_COVER": return "接敌找掩体"
		"CONTACT_BASE_OF_FIRE": return "建立火力线"
		"SUPPRESS_AND_FLANK": return "压制包抄"
		"AGGRESSIVE_ENVELOPMENT": return "强攻合围"
		"HOLD_DEFENSIVE_LINE": return "固守防线"
		"COVERING_RETREAT": return "掩护撤退"
		"AMBUSH_SETUP": return "静默伏击"
		"AMBUSH_OPEN_FIRE", "AMBUSH_VOLLEY": return "伏击开火"
		"AUTONOMOUS_GOAP": return "自主进攻"
	return ""

func _get_order_label(order_type: SquadOrder.Type) -> String:
	match order_type:
		SquadOrder.Type.HOLD: return "待命"
		SquadOrder.Type.TAKE_COVER: return "寻找掩体"
		SquadOrder.Type.SUPPRESS: return "火力压制"
		SquadOrder.Type.FOCUS_FIRE: return "集中射击"
		SquadOrder.Type.ADVANCE: return "向前推进"
		SquadOrder.Type.RETREAT: return "撤退"
		SquadOrder.Type.STAY_HIDDEN: return "保持隐蔽"
		SquadOrder.Type.OVERWATCH: return "观察警戒"
		SquadOrder.Type.FLANK_LEFT: return "左侧包抄"
		SquadOrder.Type.FLANK_RIGHT: return "右侧包抄"
		SquadOrder.Type.AMBUSH_POSITION: return "伏击就位"
		SquadOrder.Type.SEARCH_AREA: return "区域搜索"
	return "待命"
