extends Node
class_name StaminaComponent3D

var maximum := 100.0
var current := 100.0
var run_cost_per_second := 20.0
var recovery_per_second := 15.0
var recovery_delay := 1.0
var required_to_resume := 25.0
var run_exhausted := false
var _recovery_timer := 0.0

func configure(maximum_stamina: float, run_cost: float, recovery: float, delay: float, resume_threshold: float) -> void:
	maximum = maxf(1.0, maximum_stamina)
	run_cost_per_second = maxf(0.0, run_cost)
	recovery_per_second = maxf(0.0, recovery)
	recovery_delay = maxf(0.0, delay)
	required_to_resume = clampf(resume_threshold, 0.0, maximum)
	current = maximum
	run_exhausted = false
	_recovery_timer = 0.0

func process(delta: float, running: bool, moving: bool) -> bool:
	var previous := current
	if running and moving:
		current = maxf(0.0, current - run_cost_per_second * delta)
		_recovery_timer = recovery_delay
		if current <= 0.0:
			run_exhausted = true
	else:
		_recovery_timer = maxf(0.0, _recovery_timer - delta)
		if _recovery_timer <= 0.0 and current < maximum:
			current = minf(maximum, current + recovery_per_second * delta)
			if run_exhausted and current >= required_to_resume:
				run_exhausted = false
	return not is_equal_approx(previous, current)

func can_run() -> bool:
	return not run_exhausted and current > 0.0
