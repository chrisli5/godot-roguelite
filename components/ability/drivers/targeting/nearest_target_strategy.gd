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


func get_targeting_data(global_origin: Vector2, query_radius: float, max_targets: int = 1) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	
	var space_state := get_viewport().get_world_2d().direct_space_state
	if not space_state or max_targets <= 0:
		return results
		
	if is_instance_valid(_circle_shape) and query_radius > 0.0:
		_circle_shape.radius = query_radius
		max_query_radius = query_radius
		
	var intersections := SpatialQuery.query_shape_intersections(
		space_state, _circle_shape, global_origin, enemy_collision_mask, max_results_buffer
	)
	
	if intersections.is_empty():
		return results
		
	var valid_candidates: Array[Dictionary] = []
	for result in intersections:
		var target = result.get("collider") as Node2D
		if is_instance_valid(target) and target is HurtboxComponent:
			var dist_squared := global_origin.distance_squared_to(target.global_position)
			valid_candidates.append({
				"node": target,
				"dist_sq": dist_squared
			})
			
	if valid_candidates.is_empty():
		return results
		
	# Sort closest to furthest
	valid_candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["dist_sq"] < b["dist_sq"]
	)
	
	# Slice matching the strict max_targets contract parameter bounds
	var limit = min(max_targets, valid_candidates.size())
	for i in range(limit):
		var candidate = valid_candidates[i]
		var target_collider: Node2D = candidate["node"]
		var target_vector := (target_collider.global_position - global_origin).normalized()
		
		results.append({
			"direction": target_vector,
			"target_id": target_collider.get_instance_id()
		})
		
	return results
