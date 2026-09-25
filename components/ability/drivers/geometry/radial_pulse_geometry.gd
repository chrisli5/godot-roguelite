class_name RadialPulseGeometry
extends GeometryDriver

@export_group("Physics Hardware Configuration")
@export_flags_2d_physics var enemy_collision_mask: int = 4
@export var max_results_buffer: int = 64

var _circle_shape: CircleShape2D


func _ready() -> void:
	_circle_shape = CircleShape2D.new()
	_circle_shape.radius = 48.0


func execute_geometry(
	global_origin: Vector2, 
	_target_direction: Vector2,
	final_payload: CombatPayload
) -> void:
	var space_state := get_viewport().get_world_2d().direct_space_state
	if not space_state:
		return
		
	if not is_instance_valid(final_payload):
		return
		
	var has_stats := is_instance_valid(final_payload.stats_source)
	var stats = final_payload.stats_source
	var aoe_radius = stats.get_stat_value(Stat.Type.AOE_RADIUS, 48.0) if has_stats else 48.0
	_circle_shape.radius = aoe_radius

	var intersections := SpatialQuery.query_shape_intersections(
		space_state, 
		_circle_shape, 
		global_origin,
		enemy_collision_mask, 
		max_results_buffer
	)

	for result in intersections:
		var target_collider = result.get("collider") as Node2D
		if is_instance_valid(target_collider) and target_collider is HurtboxComponent:
			var hurtbox = target_collider as HurtboxComponent
			hurtbox.take_hit(final_payload)
