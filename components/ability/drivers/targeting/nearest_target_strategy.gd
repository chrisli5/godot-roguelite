class_name NearestTargetStrategy
extends TargetingStrategy

@export_group("Physics Hardware Configuration")
@export_flags_2d_physics var enemy_collision_mask: int = 1
@export var max_results_buffer: int = 32
@export var max_query_radius: float = 100.0

var _circle_shape: CircleShape2D


func _ready() -> void:
	_circle_shape = CircleShape2D.new()
	_circle_shape.radius = max_query_radius


func get_targeting_data(global_origin: Vector2, query_radius: float) -> Dictionary:
	var space_state := get_viewport().get_world_2d().direct_space_state
	if not space_state:
		return { "direction": Vector2.RIGHT, "target_node": null }
		
	if is_instance_valid(_circle_shape) and query_radius > 0.0:
		_circle_shape.radius = query_radius
		max_query_radius = query_radius
		
	var intersections := SpatialQuery.query_shape_intersections(
		space_state, _circle_shape, global_origin, enemy_collision_mask, max_results_buffer
	)
	
	if intersections.is_empty():
		return { "direction": Vector2.RIGHT, "target_node": null }
		
	var nearest_collider: HurtboxComponent = null
	var shortest_dist_squared := max_query_radius * max_query_radius
	
	for result in intersections:
		var target = result.get("collider") as Node2D
		if is_instance_valid(target) and target is HurtboxComponent:
			var dist_squared := global_origin.distance_squared_to(target.global_position)
			if dist_squared < shortest_dist_squared:
				shortest_dist_squared = dist_squared
				nearest_collider = target
				
	if is_instance_valid(nearest_collider):
		var target_vector := (nearest_collider.global_position - global_origin).normalized()
		return {
			"direction": target_vector,
			"target_node": nearest_collider # Pass the live reference back up the chain!
		}
		
	return { "direction": Vector2.RIGHT, "target_node": null }
