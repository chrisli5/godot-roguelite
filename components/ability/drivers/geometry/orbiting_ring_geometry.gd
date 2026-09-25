class_name OrbitingRingDriver
extends GeometryDriver

@export var shard_scene_template: PackedScene

var rotation_speed: float = 0.0
var orbit_radius: float = 0.0
var shard_radius: float = 0.0
var shard_amount: int = 0 

var _active_shards: Array[OrbitingShard] = []
var _current_orbit_angle_rad: float = 0.0
var _duration_left: float = 0.0
var _active_payload: HitPayload = null


func _ready() -> void:
	set_physics_process(false)


func execute_geometry(
	_global_origin: Vector2, 
	_target_direction: Vector2,
	final_payload: HitPayload
) -> void:
	_terminate_active_delivery()
	if not is_instance_valid(shard_scene_template):
		push_error("OrbitingRingDriver: No shard scene template assigned in Inspector panel.")
		delivery_finished.emit()
		return
	
	_active_payload = final_payload
	if not is_instance_valid(_active_payload) or not is_instance_valid(_active_payload.caster):
		_terminate_active_delivery()
		return

	var has_stats := is_instance_valid(_active_payload.stats_source)
	var stats = _active_payload.stats_source
	
	rotation_speed = stats.get_stat_value(Stat.Type.ORBIT_ROTATION_SPEED, 90.0) if has_stats else 90.0
	orbit_radius = stats.get_stat_value(Stat.Type.ORBIT_RADIUS, 80.0) if has_stats else 80.0
	shard_radius = stats.get_stat_value(Stat.Type.AOE_RADIUS, 10.0) if has_stats else 10.0
	shard_amount = int(stats.get_stat_value(Stat.Type.PROJECTILE_AMOUNT, 3.0)) if has_stats else 1
	_duration_left = stats.get_stat_value(Stat.Type.DURATION, 1.0) if has_stats else 1.0
	
	for i in range(shard_amount):
		var shard = shard_scene_template.instantiate() as OrbitingShard
		if shard:
			shard.hit_payload = _active_payload
			shard.collision_radius = shard_radius
			add_child(shard)
			_active_shards.append(shard)
	
	_update_shard_positions()
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	_duration_left -= delta
	if _duration_left <= 0.0:
		_terminate_active_delivery()
		return

	var speed_rad := deg_to_rad(rotation_speed)
	_current_orbit_angle_rad = wrapf(_current_orbit_angle_rad + (speed_rad * delta), 0.0, TAU)

	_update_shard_positions()

func _update_shard_positions() -> void:
	# 1. Filter out dead shards to dynamically adjust spacing if one breaks
	_active_shards = _active_shards.filter(func(shard): return is_instance_valid(shard))
	
	var total_shards := _active_shards.size()
	if total_shards == 0 or not is_instance_valid(_active_payload.caster):
		_terminate_active_delivery()
		return
		
	var angle_step := TAU / total_shards
	
	for i in range(total_shards):
		var shard = _active_shards[i]
		var target_angle := _current_orbit_angle_rad + (i * angle_step)
		var offset_vector := Vector2.from_angle(target_angle) * orbit_radius
		
		shard.global_position = offset_vector + _active_payload.caster.global_position
		shard.scale = Vector2.ONE


func _terminate_active_delivery() -> void:
	set_physics_process(false)
	
	for shard in _active_shards:
		if is_instance_valid(shard):
			shard.queue_free()
			
	_active_shards.clear()
	_active_payload = null
	
	delivery_finished.emit()
