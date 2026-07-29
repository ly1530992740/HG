extends Node3D

func _ready() -> void:
	$World/Player3D.global_position = Vector3.ZERO
	$World/CameraDirector3D._snap_to_top_down()
	var spawner := $EnemyWaveSpawner3D as SquadWaveSpawner3D
	spawner.wave_countdown_started.connect(func(number, seconds): print("[WAVE3D] 第%d波将在%.1f秒后生成" % [number, seconds]))
	spawner.wave_spawned.connect(func(number, squads): print("[WAVE3D] 第%d波生成%d支规则+GOAP小队" % [number, squads.size()]))
	spawner.wave_cleared.connect(func(number): print("[WAVE3D] 第%d波已清除" % number))
	spawner.all_waves_completed.connect(func(): print("[WAVE3D] 全部波次完成"))
