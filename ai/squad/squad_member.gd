extends Node
class_name SquadMember

signal member_died(member: SquadMember)
signal order_received(order: SquadOrder)
signal role_changed(is_leader: bool)
signal intent_changed(intent: String, action: String, plan: String)
signal task_received(assignment: SquadTaskAssignment)
signal task_state_reported(member: SquadMember, assignment: SquadTaskAssignment, state: SquadTask.State, detail: String)

@export var squad_id: StringName = &"default"

var actor: Node2D = null
var coordinator: Node = null
var blackboard: SquadBlackboard = null
var current_order: SquadOrder = null
var current_task: SquadTaskAssignment = null
var current_task_state: SquadTask.State = SquadTask.State.CANCELLED
var is_leader := false
var intent_text := "自主接敌"
var action_text := "观察战场"
var plan_text := "选择目标 -> 射击"

var _role_label: Label = null
var _status_refresh_timer := 0.0

func _ready() -> void:
	add_to_group("squad_member")
	call_deferred("_register_with_coordinator")

func _process(delta: float) -> void:
	_status_refresh_timer -= delta
	if _status_refresh_timer <= 0.0:
		_status_refresh_timer = 0.2
		_update_role_label()

func setup(new_actor: Node2D, new_squad_id: StringName = &"default") -> void:
	actor = new_actor
	squad_id = new_squad_id
	_setup_role_label()
	if actor.has_signal("died") and not actor.is_connected("died", _on_actor_died):
		actor.connect("died", _on_actor_died)
	call_deferred("_register_with_coordinator")

func assign_coordinator(new_coordinator: Node, new_blackboard: SquadBlackboard) -> void:
	coordinator = new_coordinator
	blackboard = new_blackboard
	var perception := actor.get("perception_component") as PerceptionComponent if actor else null
	var existing_contact := perception.get_best_contact() if perception else null
	if existing_contact != null and coordinator.has_method("report_contact"):
		coordinator.report_contact(self, existing_contact)
	_update_role_label()
	sync_goap_state()

func clear_coordinator(expected_coordinator: Node) -> void:
	if coordinator != expected_coordinator:
		return
	coordinator = null
	blackboard = null
	current_order = null
	current_task = null
	current_task_state = SquadTask.State.CANCELLED
	set_is_leader(false)
	_update_role_label()

func set_is_leader(value: bool) -> void:
	if is_leader == value:
		return
	is_leader = value
	_update_role_label()
	sync_goap_state()
	role_changed.emit(is_leader)

func receive_order(order: SquadOrder) -> void:
	if order == null or order.is_expired() or not order.applies_to(self):
		return
	if current_order != null and order.version < current_order.version:
		return
	current_order = order
	intent_text = "执行命令: %s" % order.get_type_name()
	action_text = "等待 GOAP 规划"
	plan_text = "命令 v%d" % order.version
	sync_goap_state()
	intent_changed.emit(intent_text, action_text, plan_text)
	order_received.emit(current_order)

func receive_task(assignment: SquadTaskAssignment) -> void:
	if assignment == null or assignment.task == null:
		return
	if current_task != null and not assignment.is_newer_than(current_task):
		return
	current_task = assignment
	current_task_state = SquadTask.State.ACTIVE
	current_order = null
	intent_text = "任务：%s" % assignment.task.get_type_name()
	action_text = "等待 GOAP 规划"
	plan_text = "态势%d / 计划%d / 任务%s" % [assignment.situation_version, assignment.plan_version, assignment.task.task_id]
	sync_goap_state()
	intent_changed.emit(intent_text, action_text, plan_text)
	task_received.emit(assignment)

func cancel_task(situation_version: int, plan_version: int, reason: String = "cancelled") -> void:
	if current_task == null:
		return
	if current_task.situation_version != situation_version or current_task.plan_version != plan_version:
		return
	report_task_state(SquadTask.State.CANCELLED, reason)
	current_task = null
	sync_goap_state()

func get_current_task() -> SquadTaskAssignment:
	return current_task

func report_task_state(state: SquadTask.State, detail: String = "") -> void:
	if current_task == null or current_task_state == state:
		return
	current_task_state = state
	task_state_reported.emit(self, current_task, state, detail)

func report_task_ready(detail: String = "ready") -> void:
	report_task_state(SquadTask.State.READY, detail)

func report_task_succeeded(detail: String = "completed") -> void:
	report_task_state(SquadTask.State.SUCCEEDED, detail)

func report_task_failed(detail: String = "failed") -> void:
	report_task_state(SquadTask.State.FAILED, detail)

func get_current_order() -> SquadOrder:
	if current_order != null and current_order.is_expired():
		current_order = null
		sync_goap_state()
	return current_order

func set_ai_status(intent: String, action: String, plan: String = "") -> void:
	intent_text = intent
	action_text = action
	if not plan.is_empty():
		plan_text = plan
	_update_role_label()
	intent_changed.emit(intent_text, action_text, plan_text)

func _register_with_coordinator() -> void:
	if actor == null or not is_inside_tree() or coordinator != null:
		return
	for node in get_tree().get_nodes_in_group("squad_coordinator"):
		if node.get("squad_id") == squad_id and node.has_method("register_member"):
			node.register_member(self)
			return

func _setup_role_label() -> void:
	if actor == null or _role_label != null:
		return
	_role_label = Label.new()
	_role_label.name = "SquadRoleLabel"
	_role_label.position = Vector2(-110, -174)
	_role_label.size = Vector2(220, 92)
	_role_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_role_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_role_label.add_theme_font_size_override("font_size", 17)
	_role_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_role_label.add_theme_constant_override("outline_size", 3)
	_role_label.z_index = 12
	actor.add_child(_role_label)
	_update_role_label()

func _update_role_label() -> void:
	if _role_label == null:
		return
	_role_label.visible = coordinator != null
	var role_name := "队长" if is_leader else "士兵"
	var profile_name := "未知"
	var state_name := "未知"
	var injury_name := "无伤"
	var suppression_name := "平静"
	var suppression_value := 0
	var team_name := "小队"
	var team_color := Color(0.82, 0.9, 1.0)
	var combat_role_name := "步枪兵"
	if actor:
		if actor.has_method("get_combat_team_label"):
			team_name = actor.get_combat_team_label()
		if actor.has_method("get_combat_team_color"):
			team_color = actor.get_combat_team_color()
		if actor.has_method("get_combat_role_label"):
			combat_role_name = actor.get_combat_role_label()
		var will := actor.get("will_component") as WillComponent
		if will:
			profile_name = _get_profile_label(will.profile)
			state_name = _get_state_label(will.mental_state)
		var injury := actor.get("injury_component") as InjuryComponent
		if injury:
			injury_name = injury.get_summary()
		var suppression := actor.get("suppression_component") as SuppressionComponent
		if suppression:
			suppression_name = _get_suppression_label(suppression.level)
			suppression_value = int(round(suppression.suppression))
	var order_name := _get_order_label(current_order.type) if current_order else "无"
	_role_label.text = "%s %s | %s | %s\n%s | 压制:%d %s | 伤:%s\n命令:%s | 行动:%s" % [team_name, role_name, profile_name, state_name, combat_role_name, suppression_value, suppression_name, injury_name, order_name, _get_short_action()]
	_role_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.18) if is_leader else team_color.lightened(0.2))

func _get_profile_label(value: WillComponent.Profile) -> String:
	match value:
		WillComponent.Profile.INDOCTRINATED:
			return "洗脑"
		WillComponent.Profile.TIMID:
			return "胆小"
	return "正常"

func _get_state_label(value: WillComponent.MentalState) -> String:
	match value:
		WillComponent.MentalState.ZEALOUS:
			return "狂热"
		WillComponent.MentalState.AFRAID:
			return "恐惧"
		WillComponent.MentalState.RECOVERING:
			return "恢复中"
		WillComponent.MentalState.BROKEN:
			return "崩溃"
		WillComponent.MentalState.SURRENDERED:
			return "投降"
	return "稳定"

func _get_suppression_label(value: SuppressionComponent.Level) -> String:
	match value:
		SuppressionComponent.Level.ALERT:
			return "警觉"
		SuppressionComponent.Level.PINNED:
			return "被压制"
		SuppressionComponent.Level.OVERWHELMED:
			return "火力崩溃"
	return "平静"

func _get_order_label(value: SquadOrder.Type) -> String:
	match value:
		SquadOrder.Type.SEARCH_AREA:
			return "区域搜索"
		SquadOrder.Type.AMBUSH_POSITION:
			return "伏击就位"
		SquadOrder.Type.TAKE_COVER:
			return "进入掩体"
		SquadOrder.Type.STAY_HIDDEN:
			return "保持隐蔽"
		SquadOrder.Type.FOCUS_FIRE:
			return "集中射击"
		SquadOrder.Type.SUPPRESS:
			return "火力压制"
		SquadOrder.Type.ADVANCE:
			return "推进"
		SquadOrder.Type.RETREAT:
			return "撤退"
		SquadOrder.Type.OVERWATCH:
			return "警戒"
		SquadOrder.Type.FLANK_LEFT:
			return "左翼包抄"
		SquadOrder.Type.FLANK_RIGHT:
			return "右翼包抄"
	return "待命"

func _get_short_action() -> String:
	if "掩体" in action_text:
		return "移动到掩体"
	if "隐蔽" in action_text:
		return "保持隐蔽"
	if "集中" in action_text or "精准" in action_text:
		return "精准射击"
	if "压制" in action_text or "盲射" in action_text:
		return "盲射压制"
	if "推进" in action_text:
		return "移动射击"
	if "撤退" in action_text or "撤离" in action_text:
		return "撤离战斗"
	if "规划" in action_text or "等待" in action_text:
		return "规划中"
	return action_text.left(8)

func sync_goap_state() -> void:
	if actor == null:
		return
	var agent := actor.find_child("GoapAgent", true, false) as GoapAgent
	if agent == null:
		return
	var world_state := agent.get_world_state()
	if world_state == null:
		return
	world_state.set_state(&"is_squad_leader", is_leader)
	world_state.set_state(&"has_squad_order", current_order != null)
	world_state.set_state(&"squad_order_type", current_order.type if current_order else -1)
	world_state.set_state(&"squad_order_version", current_order.version if current_order else 0)
	world_state.set_state(&"has_squad_task", current_task != null)
	world_state.set_state(&"squad_task_type", current_task.task.type if current_task else -1)
	world_state.set_state(&"squad_task_token", current_task.token() if current_task else &"")
	world_state.set_state(&"completed_task_token", &"")
	world_state.set_state(&"at_task_destination", false)
	world_state.set_state(&"task_target_acquired", false)
	world_state.set_state(&"task_aimed", false)
	agent.request_replan()

func _on_actor_died(_dead_actor: Node = null) -> void:
	member_died.emit(self)
