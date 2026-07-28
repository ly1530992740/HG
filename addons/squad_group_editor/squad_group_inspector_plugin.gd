@tool
extends EditorInspectorPlugin

const SHOOTER_SCENE := preload("res://unit/goblins/goblin shooter.tscn")

const PRESETS := [
	{"label": "步枪兵", "role": SquadCombatRole.Type.RIFLEMAN, "loadout": 0},
	{"label": "精确射手", "role": SquadCombatRole.Type.MARKSMAN, "loadout": 0},
	{"label": "机枪兵", "role": SquadCombatRole.Type.MACHINE_GUNNER, "loadout": 0},
	{"label": "霰弹突击兵", "role": SquadCombatRole.Type.SHOTGUNNER, "loadout": 0},
	{"label": "手枪侦察兵", "role": SquadCombatRole.Type.PISTOL_SCOUT, "loadout": 0},
	{"label": "冲锋枪兵", "role": SquadCombatRole.Type.RIFLEMAN, "loadout": 1},
	{"label": "近战兵", "role": SquadCombatRole.Type.MELEE, "loadout": 2},
]

const PROPERTY_LABELS := {
	# 小队 Group
	"squad_id": "小队 ID",
	"combat_team": "战斗阵营",
	"squad_display_name": "小队显示名称",
	"can_target_players": "可以攻击玩家",
	"team_color": "队伍颜色",
	"free_when_all_members_dead": "全员阵亡后删除小队节点",
	"empty_cleanup_delay": "小队清理延迟",
	"member_root_path": "成员容器路径",
	"member_actor_paths": "手工成员路径",
	"propagate_group_identity": "同步 Group 阵营信息",
	"editor_spawn_center": "添加士兵中心",
	"editor_spawn_area": "添加士兵随机范围",
	"battlefield_analyzer_path": "态势分析模块路径",
	"route_analyzer_path": "路线分析模块路径",

	# 小队长
	"auto_discover_members": "自动发现成员",
	"command_mode": "指挥模式",
	"elect_squad_leader": "选举小队长",
	"context_refresh_interval": "态势刷新间隔",
	"order_interval": "命令间隔",
	"initial_cover_duration": "初始找掩体时长",
	"assault_charge_chance": "突击概率",
	"contact_report_delay_min": "最短敌情上报延迟",
	"contact_report_delay_max": "最长敌情上报延迟",
	"search_order_interval": "搜索命令间隔",
	"search_step_distance": "每次搜索推进距离",
	"search_movement_enabled": "允许搜索移动",
	"hold_search_until_first_contact": "首次接敌前原地等待",
	"search_direction_override": "固定搜索方向",
	"search_expansion_step": "搜索范围扩展步长",
	"search_max_expansion_rings": "最大搜索扩展圈数",
	"shared_target_memory_seconds": "共享目标记忆秒数",
	"surprise_command_delay_min": "受袭最短反应延迟",
	"surprise_command_delay_max": "受袭最长反应延迟",
	"ambush_timeout": "伏击最长等待时间",
	"ambush_ready_ratio_required": "伏击最低就位比例",
	"ambush_danger_close_distance": "伏击危险距离",
	"allow_silent_ambush": "允许静默伏击",
	"use_shared_ambush_cover": "允许共用伏击掩体",
	"ambush_opening_volley_duration": "伏击齐射持续时间",
	"ambush_aim_quality_required": "伏击最低瞄准质量",
	"ambush_aim_timeout": "伏击瞄准超时",
	"ambush_max_cover_groups": "伏击最多掩体组数",
	"ambush_cover_score_tolerance": "伏击掩体评分容差",
	"ambush_load_balance_weight": "伏击掩体分流权重",
	"ambush_formation_identification_radius": "伏击阵形识别半径",
	"ambush_min_approach_progress": "伏击最低接近进度",

	# Qwen
	"llm_endpoint": "Qwen 服务地址",
	"llm_timeout_seconds": "Qwen 超时秒数",
	"llm_min_decision_interval": "最短决策间隔",
	"llm_max_tokens": "最大输出 Token",
	"commander_display_name": "小队长显示名称",
	"debug_show_full_prompt": "显示完整提示词",
	"initial_guard_enabled": "开局请求警戒决策",
	"status_label_path": "状态文本路径",
	"input_label_path": "态势输入文本路径",
	"output_label_path": "模型输出文本路径",
	"orders_label_path": "GOAP 命令文本路径",

	# 态势与路线分析
	"strong_firepower_threshold": "强火力阈值",
	"overwhelming_firepower_threshold": "极强火力阈值",
	"include_unconfirmed_hostiles": "包含未确认敌人",
	"route_clearance": "路线离墙距离",
	"endpoint_clearance": "路线端点绕行距离",
	"minimum_route_wall_length": "候选掩体最短长度",
	"minimum_forward_alignment": "最低前进方向一致度",
	"minimum_route_capacity": "路线最低容纳人数",
	"max_candidates_per_side": "每侧最多候选路线",
	"distance_weight": "移动距离权重",
	"exposure_weight": "暴露风险权重",
	"capacity_bonus": "掩护容量加分",
	"side_distance_bonus": "侧向距离加分",

	# 成员配置与士兵
	"member_id": "士兵编号",
	"position": "出生位置",
	"combat_role": "兵种",
	"firearm_loadout": "枪械配置",
	"initial_facing_direction": "初始朝向",
	"lock_steady_morale": "锁定稳定士气",
	"max_health": "最大生命值",
	"health": "当前生命值",
	"SPEED": "移动速度",
	"STOP_DISTANCE": "停止距离",
	"ATTACK_DISTANCE": "基础攻击距离",
	"KNOCKBACK_FORCE": "击退力度",
	"KNOCKBACK_DECAY": "击退衰减",
	"target_groups": "可搜索目标组",
	"will_profile": "意志配置",
	"team_display_name": "队伍显示名称",
	"death_cleanup_delay": "尸体清理延迟",
	"death_audio_enabled": "启用死亡音效",
	"awards_player_score": "被玩家击杀时奖励积分",
	"score_reward": "击杀积分",
	"drops_ammo_on_death": "死亡时掉落弹药",
	"ammo_drop_amount": "掉落弹药数量",
	"detect_range": "检测距离",
	"attack_range": "射击距离",
	"keep_distance": "保持距离",
	"autonomous_goap_enabled": "启用单兵自主 GOAP",
	"defense_anchor": "防守中心",
	"defense_radius": "防守半径",
	"defense_arrival_radius": "集结到达距离",
	"maximum_cover_move_distance": "最大找掩体距离",
	"fire_cooldown": "射击冷却",
	"projectile_damage": "子弹伤害",
	"projectile_speed": "子弹速度",
	"projectile_lifetime": "子弹存在时间",
	"spread_degrees": "基础散布角度",
	"magazine_size": "弹匣容量",
	"reserve_ammo": "备用弹药",
	"reload_time": "装弹时间",
	"hit_groups": "可命中目标组",
	"melee_trigger_distance": "切换近战距离",
	"melee_attack_distance": "近战攻击距离",
	"melee_damage": "近战伤害",
	"ai_decision_interval": "AI 判断间隔",
	"target_refresh_interval": "目标刷新间隔",
	"surprise_reaction_min": "最短受惊时间",
	"surprise_reaction_max": "最长受惊时间",
	"allow_cover_lateral_reposition": "受压时允许沿掩体换位",
	"standard_sight_range": "标准视野距离",
	"standard_field_of_view": "标准视野角度",
	"marksman_aim_sight_range": "精确射手瞄准视距",
	"marksman_aim_field_of_view": "精确射手瞄准视野角度",

	# 波次生成
	"waves": "敌军波次",
	"auto_start": "场景启动后自动开始",
	"first_wave_delay": "第一波倒计时",
	"between_wave_delay": "波次间隔倒计时",
	"spawn_radius": "随机生成半径",
	"minimum_spawn_radius": "最小生成半径",
	"show_spawn_radius_preview": "在场景中显示生成半径",
	"spawn_on_outer_ring": "仅在最外圈生成",
	"face_spawn_center": "生成后朝向中心",
	"assign_primary_target": "生成后指定首要目标",
	"primary_target_path": "首要目标节点路径",
	"initial_points": "初始积分",
	"clear_check_interval": "全灭检查间隔",
	"spawned_squads_parent_path": "生成小队的父节点路径",
	"wave_name": "波次名称",
	"squads": "本波小队配置",
	"squad_scene": "小队预制体",
	"count": "生成数量",
	"spawn_radius_override": "单项生成半径覆盖",
}

var _editor_plugin: EditorPlugin
var _inspector_anchors: Dictionary = {}

func setup(value: EditorPlugin) -> void:
	_editor_plugin = value

func _can_handle(object: Object) -> bool:
	return (
		object is SquadGroup
		or object is SquadMemberSpawn
		or object is SquadBattlefieldAnalyzer
		or object is SquadRouteAnalyzer
		or object is GoblinBase
		or object is SquadWaveSpawner
		or object is SquadWaveDefinition
		or object is SquadWaveEntry
		or object is SurvivalDefenseWaveController
	)

func _parse_begin(object: Object) -> void:
	if not object is SquadGroup:
		var localization_anchor := Control.new()
		localization_anchor.custom_minimum_size = Vector2.ZERO
		localization_anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_inspector_anchors[object.get_instance_id()] = localization_anchor
		add_custom_control(localization_anchor)
		return
	var group := object as SquadGroup
	var panel := VBoxContainer.new()
	_inspector_anchors[object.get_instance_id()] = panel
	panel.add_theme_constant_override("separation", 6)
	var title := Label.new()
	title.text = "添加场景士兵"
	title.add_theme_font_size_override("font_size", 14)
	panel.add_child(title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	panel.add_child(row)
	var preset_selector := OptionButton.new()
	preset_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for preset in PRESETS:
		preset_selector.add_item(String(preset.label))
	row.add_child(preset_selector)
	var add_button := Button.new()
	add_button.text = "添加士兵"
	add_button.tooltip_text = "按所选兵种创建可保存、可拖动的士兵场景节点"
	row.add_child(add_button)
	var status := Label.new()
	status.text = _get_member_count_text(group)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(status)
	add_button.pressed.connect(_on_add_soldier.bind(group, preset_selector, status))
	add_custom_control(panel)

func _parse_end(object: Object) -> void:
	var object_id := object.get_instance_id()
	var anchor := _inspector_anchors.get(object_id) as Control
	_inspector_anchors.erase(object_id)
	if anchor != null:
		call_deferred("_localize_property_labels", anchor)

func _localize_property_labels(anchor: Control) -> void:
	if not is_instance_valid(anchor):
		return
	var inspector: Node = anchor
	while inspector != null and not inspector is EditorInspector:
		inspector = inspector.get_parent()
	if inspector == null:
		return
	for child in inspector.find_children("*", "EditorProperty", true, false):
		var editor := child as EditorProperty
		var property_name := String(editor.get_edited_property())
		if PROPERTY_LABELS.has(property_name):
			editor.set_label(String(PROPERTY_LABELS[property_name]))
		_localize_enum_options(editor, property_name)

func _on_add_soldier(group: Node, selector: OptionButton, status: Label) -> void:
	if _editor_plugin == null or not is_instance_valid(group):
		return
	var member_root_path: NodePath = group.get("member_root_path")
	var member_root := group.get_node_or_null(member_root_path)
	if member_root == null:
		status.text = "添加失败：成员容器路径无效"
		return
	var edited_root := _editor_plugin.get_editor_interface().get_edited_scene_root()
	if edited_root == null or (edited_root != group and not edited_root.is_ancestor_of(group)):
		status.text = "添加失败：请先打开包含该小队的场景"
		return
	var preset_index := clampi(selector.selected, 0, PRESETS.size() - 1)
	var preset: Dictionary = PRESETS[preset_index]
	var actor := SHOOTER_SCENE.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node2D
	if actor == null:
		status.text = "添加失败：士兵场景无法实例化"
		return
	actor.name = _make_unique_soldier_name(group, member_root, String(preset.label))
	var spawn_center: Vector2 = group.get("editor_spawn_center")
	var spawn_area: Vector2 = group.get("editor_spawn_area")
	actor.position = spawn_center + _random_spawn_offset(spawn_area)
	actor.set("combat_role", int(preset.role))
	actor.set("firearm_loadout", int(preset.loadout))
	actor.set("squad_id", group.get("squad_id"))
	actor.set("combat_team", group.get("combat_team"))
	actor.set("can_target_players", group.get("can_target_players"))
	actor.set("team_display_name", group.get("squad_display_name"))
	actor.set("team_color", group.get("team_color"))
	actor.set("initial_facing_direction", Vector2.LEFT if group.get("combat_team") == &"bravo" else Vector2.RIGHT)
	actor.set("lock_steady_morale", true)
	var undo_redo := _editor_plugin.get_undo_redo()
	undo_redo.create_action("添加%s" % preset.label)
	undo_redo.add_do_method(member_root, &"add_child", actor, true)
	undo_redo.add_do_method(actor, &"set_owner", edited_root)
	undo_redo.add_undo_method(member_root, &"remove_child", actor)
	undo_redo.add_do_reference(actor)
	undo_redo.commit_action()
	var selection := _editor_plugin.get_editor_interface().get_selection()
	selection.clear()
	selection.add_node(actor)
	status.text = "已添加：%s，位置 %s" % [actor.name, actor.position.round()]

func _localize_enum_options(editor: EditorProperty, property_name: String) -> void:
	var labels: PackedStringArray = []
	match property_name:
		"combat_role":
			labels = PackedStringArray(["步枪兵", "精确射手", "机枪兵", "霰弹突击兵", "手枪侦察兵", "近战兵"])
		"firearm_loadout":
			labels = PackedStringArray(["按兵种默认", "冲锋枪", "仅近战武器"])
		"will_profile":
			labels = PackedStringArray(["狂热", "正规", "胆怯"])
		"command_mode":
			labels = PackedStringArray(["小队长统一指挥", "无小队长：单兵自主 GOAP"])
	if labels.is_empty():
		return
	for child in editor.find_children("*", "OptionButton", true, false):
		var option := child as OptionButton
		for index in mini(option.item_count, labels.size()):
			option.set_item_text(index, labels[index])

func _random_spawn_offset(area: Vector2) -> Vector2:
	var half_area := area.abs() * 0.5
	return Vector2(
		randf_range(-half_area.x, half_area.x),
		randf_range(-half_area.y, half_area.y)
	)

func _make_unique_soldier_name(group: Node, root: Node, role_label: String) -> String:
	var team_label := String(group.get("squad_display_name")).strip_edges()
	if team_label.is_empty():
		team_label = String(group.get("squad_id"))
	var base_name := "%s_%s" % [team_label, role_label]
	var index := 1
	var candidate := "%s_%02d" % [base_name, index]
	while root.has_node(NodePath(candidate)):
		index += 1
		candidate = "%s_%02d" % [base_name, index]
	return candidate

func _get_scene_member_count(group: Node) -> int:
	var member_root_path: NodePath = group.get("member_root_path")
	var member_root := group.get_node_or_null(member_root_path)
	if member_root == null:
		return 0
	var count := 0
	for child in member_root.get_children():
		if child is Node2D:
			count += 1
	return count

func _get_member_count_text(group: Node) -> String:
	return "场景成员：%d" % _get_scene_member_count(group)
