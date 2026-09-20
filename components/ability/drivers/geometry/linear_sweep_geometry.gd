class_name LinearSweepDriver
extends GeometryDriver

@export_group("Physics Hardware Configuration")
@export_flags_2d_physics var enemy_collision_mask: int = 4
@export var max_results_buffer: int = 64

@export_group("Sweep Geometry Parameters")
@export var strike_length: float = 120.0
@export var cone_angle_degrees: float = 60.0


func execute_delivery(
	global_origin: Vector2, 
	target_direction: Vector2,
	_current_speed: float, 
	current_aoe_scale: float, 
	final_payload: HitPayload
) -> void:
	
	var space_state := get_viewport().get_world_2d().direct_space_state
	if not space_state: return

	# 1. Build procedural wedge directly facing the pre-calculated vector direction
	var adjusted_length := strike_length * current_aoe_scale
	var half_arc_rad := deg_to_rad(cone_angle_degrees / 2.0)
	var base_angle := target_direction.angle()

	var vertex_left := Vector2.from_angle(base_angle - half_arc_rad) * adjusted_length
	var vertex_right := Vector2.from_angle(base_angle + half_arc_rad) * adjusted_length

	var wedge_shape := ConvexPolygonShape2D.new()
	wedge_shape.points = PackedVector2Array([Vector2.ZERO, vertex_left, vertex_right])

	# 2. Query hardware server
	var intersections := SpatialQuery.query_shape_intersections(
		space_state, wedge_shape, global_origin, enemy_collision_mask, max_results_buffer
	)

	# 3. Distribute hits
	for result in intersections:
		var target_collider = result.get("collider") as Node2D
		if is_instance_valid(target_collider) and target_collider is HurtboxComponent:
			target_collider.take_hit(final_payload)
	
	delivery_finished.emit()
