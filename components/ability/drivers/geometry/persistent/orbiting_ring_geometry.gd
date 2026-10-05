class_name OrbitingRingGeometry
extends PersistentGeometry

@export var shard_scene_template: PackedScene

var rotation_speed: float = 0.0
var orbit_radius: float = 0.0
var _active_shards: Array[OrbitingShard] = []
var _current_orbit_angle_rad: float = 0.0
var _shard_amount: int = 0


## Step 1: Handle unique first-frame spawning logic cleanly
func _on_persistent_started(spawn_origin: Vector2, _query_results: Dictionary) -> void:
	var stats = instance_from_id(_active_payload.stats_container_id)
	var has_stats := is_instance_valid(stats)
	
	rotation_speed = stats.get_final_stat_value(Stat.Type.ORBIT_ROTATION_SPEED) if has_stats else 90.0
	orbit_radius = stats.get_final_stat_value(Stat.Type.ORBIT_RADIUS) if has_stats else 80.0
	_shard_amount = int(stats.get_final_stat_value(Stat.Type.PROJECTILE_AMOUNT)) if has_stats else 1
	
	for i in range(_shard_amount):
		var shard = shard_scene_template.instantiate() as OrbitingShard
		if shard:
			shard.initialize_volume(spawn_origin, Vector2.ZERO, 0, _active_payload)
			add_child(shard)
			_active_shards.append(shard)
	
	_update_shard_positions()


## Step 2: Handle unique frame-by-frame angular velocity math updates
func _update_persistent_step(delta: float) -> void:
	var speed_rad := deg_to_rad(rotation_speed)
	_current_orbit_angle_rad = wrapf(_current_orbit_angle_rad + (speed_rad * delta), 0.0, TAU)
	_update_shard_positions()


## Step 3: Handle unique end-of-lifecycle garbage collection cleanup loops
func _on_persistent_terminated() -> void:
	for shard in _active_shards:
		if is_instance_valid(shard):
			shard.queue_free()
	_active_shards.clear()


func _update_shard_positions() -> void:
	_active_shards = _active_shards.filter(func(shard): return is_instance_valid(shard))
	var total_shards := _active_shards.size()
	if total_shards == 0:
		return
		
	var angle_step := TAU / total_shards
	for i in range(total_shards):
		var shard = _active_shards[i]
		var target_angle := _current_orbit_angle_rad + (i * angle_step)
		var offset_vector := Vector2.from_angle(target_angle) * orbit_radius
		
		# _cached_caster is safely provided automatically by the parent class framework!
		shard.global_position = offset_vector + _cached_caster.global_position
