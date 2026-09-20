class_name RadialPulseGeometry
extends GeometryDriver

@export_group("Physics Hardware Configuration")
@export_flags_2d_physics var enemy_collision_mask: int = 4
@export var base_radius: float = 64.0
@export var max_results_buffer: int = 64

var _circle_shape: CircleShape2D


func _ready() -> void:
	_circle_shape = CircleShape2D.new()
	_circle_shape.radius = base_radius


## Executes an instantaneous hardware query using passed vectors
func execute_delivery(
	global_origin: Vector2, 
	_target_direction: Vector2,
	_current_speed: float, 
	current_aoe_scale: float, 
	final_payload: HitPayload
) -> void:
	var space_state := get_viewport().get_world_2d().direct_space_state
	if not space_state:
		return

	# 1. Update the local radius boundary utilizing your player scaling metrics
	_circle_shape.radius = base_radius * current_aoe_scale

	# 2. Delegate the raw hardware search step up to our static helper engine module
	var intersections := SpatialQuery.query_shape_intersections(
		space_state, 
		_circle_shape, 
		global_origin, # Uses the precise coordinate passed from above
		enemy_collision_mask, 
		max_results_buffer
	)

	# 3. Resolve combat impacts blindly across the returned target array slice
	for result in intersections:
		var target_collider = result.get("collider") as Node2D
		if is_instance_valid(target_collider) and target_collider is HurtboxComponent:
			var hurtbox = target_collider as HurtboxComponent
			hurtbox.take_hit(final_payload)
