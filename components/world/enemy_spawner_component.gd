class_name EnemySpawner
extends Node

signal wave_completed(wave_index: int)
signal campaign_cleared

@export var enemy_scene: PackedScene
@export var wave_manifest: Array[EnemyWaveProfile] = []

var _current_wave_idx: int = 0
var _current_wave_spawned_count: int = 0
var _wave_runtime_timer: Timer
var _spawn_interval_timer: Timer


func _ready() -> void:
	if wave_manifest.is_empty():
		push_warning("EnemySpawnerComponent: Wave manifest array is empty. No enemies will deploy.")
		return

func start_spawn() -> void:
	_setup_spawner_clocks()
	_start_wave_segment(_current_wave_idx)


func _setup_spawner_clocks() -> void:
	_wave_runtime_timer = Timer.new()
	_wave_runtime_timer.one_shot = true
	_wave_runtime_timer.timeout.connect(_on_wave_duration_expired)
	add_child(_wave_runtime_timer)
	
	_spawn_interval_timer = Timer.new()
	_spawn_interval_timer.timeout.connect(_on_spawn_interval_tick)
	add_child(_spawn_interval_timer)


func _start_wave_segment(index: int) -> void:
	if index >= wave_manifest.size():
		_spawn_interval_timer.stop()
		_wave_runtime_timer.stop()
		campaign_cleared.emit()
		print("[SPAWNER] All wave segments successfully exhausted.")
		return
		
	_current_wave_idx = index
	_current_wave_spawned_count = 0
	
	var active_profile: EnemyWaveProfile = wave_manifest[_current_wave_idx]
	if not is_instance_valid(active_profile):
		return
		
	print("[SPAWNER] Commencing Wave %d | Count target: %d" % [_current_wave_idx + 1, active_profile.total_spawn_count])
	
	_wave_runtime_timer.start(active_profile.wave_duration)
	_spawn_interval_timer.start(active_profile.spawn_interval)


func _on_spawn_interval_tick() -> void:
	var active_profile: EnemyWaveProfile = wave_manifest[_current_wave_idx]
	if not is_instance_valid(active_profile) or active_profile.enemy_data_pool.is_empty():
		return
		
	if _current_wave_spawned_count >= active_profile.total_spawn_count:
		_spawn_interval_timer.stop()
		return
		
	_execute_monster_instantiation(active_profile)


func _execute_monster_instantiation(profile: EnemyWaveProfile) -> void:
	if profile.enemy_data_pool.is_empty() or not is_instance_valid(enemy_scene):
		return

	var enemy_instance = enemy_scene.instantiate()
	
	if enemy_instance is Enemy:
		var pool_idx := randi() % profile.enemy_data_pool.size()
		var chosen_data: EnemyData = profile.enemy_data_pool[pool_idx]
		
		var x_coord: int = randi_range(0, 100)
		var y_coord: int = randi_range(0, 100)
		
		enemy_instance.initialize_entity(chosen_data)
		enemy_instance.global_position = Vector2(x_coord, y_coord)
		
		EventBus.spawn_requested.emit(enemy_instance)
		_current_wave_spawned_count += 1


func _on_wave_duration_expired() -> void:
	print("[SPAWNER] Wave segment %d timeline cutoff cleared." % (_current_wave_idx + 1))
	wave_completed.emit(_current_wave_idx)

	_start_wave_segment(_current_wave_idx + 1)
