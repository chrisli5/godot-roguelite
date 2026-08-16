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
var _physics_query: PhysicsShapeQueryParameters2D
var _circle_shape: CircleShape2D


func _ready() -> void:
	_initialize_physics_parameters()


func _initialize_physics_parameters() -> void:
	_circle_shape = CircleShape2D.new()
	_circle_shape.radius = max_range
	
	_physics_query = PhysicsShapeQueryParameters2D.new()
	_physics_query.shape = _circle_shape
	_physics_query.collision_mask = enemy_collision_mask
	_physics_query.collide_with_areas = true   # Set to true if enemies use Area2D
	_physics_query.collide_with_bodies = false  # Set to true if enemies use CharacterBody2D


## Uses Godot's spatial partitioning system to instantly find the closest target inside an area
func get_nearest_target(origin: Vector2) -> Node2D:
	# 1. Acquire the low-level Direct Space State pointer for the active world frame
	var space_state = (get_parent() as Node2D).get_world_2d().direct_space_state
	if not is_instance_valid(space_state):
		return null
		
	# 2. Shift the intersection search circle position to our active skill location origin
	_physics_query.transform = Transform2D(0, origin)
	
	# 3. Query the physics server layout directly (extremely fast O(log N) lookup)
	var intersections: Array[Dictionary] = space_state.intersect_shape(_physics_query, max_results_buffer)
	if intersections.is_empty():
		return null
		
	var nearest: Node2D = null
	var shortest_dist_squared = max_range * max_range
	
	# 4. Cycle only through the small buffered slice returned by the spatial hardware tree
	for result in intersections:
		var target_collider = result.get("collider") as Node2D
		if not is_instance_valid(target_collider):
			continue
			
		var dist_squared = origin.distance_squared_to(target_collider.global_position)
		
		if dist_squared < shortest_dist_squared:
			shortest_dist_squared = dist_squared
			nearest = target_collider
			
	return nearest


## Allows you to safely scale or adjust the range dynamically during gameplay modifications
func update_max_range(new_range: float) -> void:
	max_range = new_range
	if _circle_shape:
		_circle_shape.radius = new_range
