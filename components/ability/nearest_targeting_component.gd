class_name NearestTargetingComponent
extends Node

@export_group("Physics Overlap Configuration")
## The collision layer used by your enemies (ensure this matches your Project Settings)
@export_flags_2d_physics var enemy_collision_mask: int = 1
## The absolute maximum number of close targets the physics engine should fetch per frame pass
@export var max_results_buffer: int = 32

@export_group("Performance & Proximity Tuning")
## The maximum operational radius of this targeting circle component
@export var max_range: float = 500.0

# Pre-allocated parameters node to reuse across execution passes, preventing memory churn
var _circle_shape: CircleShape2D


func _ready() -> void:
	_initialize_physics_parameters()


func _initialize_physics_parameters() -> void:
	_circle_shape = CircleShape2D.new()
	_circle_shape.radius = max_range


func get_nearest_target(origin: Vector2) -> Node2D:
	var space_state := get_viewport().get_world_2d().direct_space_state
	if not is_instance_valid(space_state):
		return null
			
	var intersections := SpatialQuery.query_shape_intersections(
		space_state, _circle_shape, origin, enemy_collision_mask, max_results_buffer
	)

	var nearest_target: Node2D = null
	var shortest_dist_sq := max_range * max_range
	
	for result in intersections:
		var collider = result.get("collider") as Node2D
		if is_instance_valid(collider):
			var dist_sq := origin.distance_squared_to(collider.global_position)
			if dist_sq < shortest_dist_sq:
				shortest_dist_sq = dist_sq
				nearest_target = collider
	
	return nearest_target


func update_max_range(new_range: float) -> void:
	max_range = new_range
	if _circle_shape:
		_circle_shape.radius = new_range
