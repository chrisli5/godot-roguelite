class_name SpatialQueryComponent
extends Node

@export_group("Physics Server Configuration")
@export_flags_2d_physics var target_collision_mask: int = 4
@export var max_results_buffer: int = 32

## Injected sorting callback template. Defaults to proximity sorting.
## Expected signature: func(a: Dictionary, b: Dictionary) -> bool
## Receives dictionary candidates structured as: { "component": HurtboxComponent, "dist_sq": float }
var active_sort_rule: Callable


func _ready() -> void:
	reset_to_defaults()


## Wipes out any active custom sorting rules injected by previous AbilityData profiles.
## This prevents custom weapon logic from bleeding into subsequent weapons during hot-swaps.
func reset_to_defaults() -> void:
	# Default fallback rule: Standard proximity sorting (closest enemies first)
	active_sort_rule = func(a: Dictionary, b: Dictionary) -> bool:
		return a["dist_sq"] < b["dist_sq"]


## Unified Contract: Takes an arbitrary center origin and a custom query shape.
## Returns a standard dictionary wrapper layout: { "origin": Vector2, "hit_nodes": Array[HurtboxComponent] }
func execute_spatial_query(query_origin: Vector2, query_shape: Shape2D) -> Dictionary:
	var results: Array[HurtboxComponent] = []
	
	var space_state := get_viewport().get_world_2d().direct_space_state
	if not space_state or not is_instance_valid(query_shape):
		return { "origin": query_origin, "hit_nodes": results }

	# Execute a direct shape intersection check against Godot's physics hardware server
	var intersections := SpatialQuery.query_shape_intersections(
		space_state, 
		query_shape, 
		query_origin, 
		target_collision_mask, 
		max_results_buffer
	)
	
	if intersections.is_empty():
		return { "origin": query_origin, "hit_nodes": results }

	# Filter intersection snapshots into a cleanly mapped array of valid candidates
	var candidates: Array[Dictionary] = []
	for intersect_data in intersections:
		var area = intersect_data.get("collider") as Area2D
		if is_instance_valid(area) and area is HurtboxComponent:
			var dist_sq := query_origin.distance_squared_to(area.global_position)
			candidates.append({
				"component": area,
				"dist_sq": dist_sq
			})
			
	if candidates.is_empty():
		return { "origin": query_origin, "hit_nodes": results }

	# SINGLE-PASS RUNTIME RESOLUTION:
	# Dynamically executes whatever sorting rule criteria is currently assigned to the driver
	candidates.sort_custom(active_sort_rule)
	
	# Pack sorted components sequentially into the final return array wrapper
	for entry in candidates:
		results.append(entry["component"])
		
	return { "origin": query_origin, "hit_nodes": results }
