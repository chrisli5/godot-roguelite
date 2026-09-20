# res://components/ability/drivers/geometry/orbiting_ring_driver.gd
class_name OrbitingRingDriver
extends GeometryDriver

@export_group("Physics Hardware Configuration")
## The collision layer used by your enemies (e.g., Layer 3 = Mask 4)
@export_flags_2d_physics var enemy_collision_mask: int = 4
## The absolute maximum number of close targets the physics engine should fetch per shard check
@export var max_results_buffer: int = 16

@export_group("Orbital Configuration")
## The total number of sub-collision zones distributed around the circumference (e.g., 4 or 6 shards)
@export var shard_count: int = 4
## The base radius distance from the player origin to the orbiting perimeter path in pixels
@export var base_orbit_radius: float = 80.0
## The individual collision hitbox radius size of each orbiting shard before AoE scaling
@export var shard_hitbox_radius: float = 24.0
## How fast the ring barrier spins around the character origin (defined in degrees per second)
@export var rotation_speed_degrees: float = 90.0

# Pre-allocated circle shape reused across execution queries to eliminate memory churn
var _shard_shape: CircleShape2D
# Running internal angular state tracker advanced during frame processing passes
var _current_orbit_angle_rad: float = 0.0

# Trailing runtime tracker tracking remaining time slice values
var _duration_left: float = 0.0
# Cache reference to the running payload data asset to distribute across frame ticks
var _active_payload: HitPayload = null


func _ready() -> void:
	_shard_shape = CircleShape2D.new()
	_shard_shape.radius = shard_hitbox_radius
	
	# Keep the driver's process ticking asleep by default until explicitly awakened by a cast command
	set_physics_process(false)


## Awakens the driver to begin continuous frame processing.
## Injected directly by the parent orchestrator on timer completion ticks.
func execute_delivery(
	global_origin: Vector2, 
	target_direction: Vector2, 
	current_speed: float, 
	current_aoe_scale: float, 
	final_payload: HitPayload
) -> void:
	
	_active_payload = final_payload
	
	# Determine duration scaling parameters dynamically based on current stats configuration
	# (e.g., harvesting values from your Fire Duration or baseline skill arrays)
	_duration_left = 3.0 # Default fallback: 3-second active lifespan
	
	# Force set the loop processing line alive right now
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	# 1. Update active lifespan thresholds
	_duration_left -= delta
	if _duration_left <= 0.0:
		_terminate_active_delivery()
		return
		
	# 2. Advance rotation math coordinates relative to the frame processing time steps
	var speed_rad := deg_to_rad(rotation_speed_degrees)
	_current_orbit_angle_rad = wrapf(_current_orbit_angle_rad + (speed_rad * delta), 0.0, TAU)
	
	# 3. Parent-Mediated Origin Verification
	# Query your parent wrapper directly to retrieve the player's real-time global origin position vector
	var parent_wrapper := get_parent() as Node2D
	if not is_instance_valid(parent_wrapper) or not is_instance_valid(_active_payload):
		_terminate_active_delivery()
		return
		
	# Harvest running AoE sizing stats dynamically from memory registers
	var current_aoe_scale: float = 1.0
	if "stats_container" in parent_wrapper and parent_wrapper.stats_container:
		current_aoe_scale = parent_wrapper.stats_container.get_stat_value(Stat.Type.ACCELERATION, 1.0)

	# 4. Recalibrate physical layout boundary variables
	_shard_shape.radius = shard_hitbox_radius * current_aoe_scale
	var adjusted_orbit_radius := base_orbit_radius * current_aoe_scale
	var angle_step := TAU / shard_count
	
	var space_state := get_viewport().get_world_2d().direct_space_state
	if not space_state:
		return

	# --- SYSTEMIC DISTRIBUTED SCAN LOOP ---
	for i in range(shard_count):
		# Compute the unique coordinates vector for this shard on the ring path
		var shard_angle := _current_orbit_angle_rad + (i * angle_step)
		var offset_vector := Vector2.from_angle(shard_angle) * adjusted_orbit_radius
		var shard_global_position := parent_wrapper.global_position + offset_vector

		# 5. Direct hardware tree lookup via your query utility (automatically handles debug drawing)
		var intersections := SpatialQuery.query_shape_intersections(
			space_state,
			_shard_shape,
			shard_global_position,
			enemy_collision_mask,
			max_results_buffer
		)

		# 6. Distribute damage packs blindly down into hit receivers
		for result in intersections:
			var target_collider = result.get("collider") as Node2D
			if is_instance_valid(target_collider) and target_collider is HurtboxComponent:
				target_collider.take_hit(_active_payload)


func _terminate_active_delivery() -> void:
	set_physics_process(false)
	_active_payload = null
	
	# REACTIVE INVERSION OF CONTROL Handoff:
	# Alert the parent Ability wrapper to instantly commence its downtime cooldown phase!
	delivery_finished.emit()
