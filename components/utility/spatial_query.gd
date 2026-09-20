class_name SpatialQuery
extends RefCounted


const ENABLE_VISUAL_DEBUG: bool = true
const DEBUG_COLOR_DEFAULT := Color(1.0, 0.3, 0.3, 1.0) # Vibrant coral neon split
const DEBUG_FLASH_DURATION: float = 0.15 # Running flash time slice (roughly 9 engine frames)


## Executes a direct-space shape intersection check against Godot's physics hardware.
## Returns a raw Array of Dictionary intersections.
static func query_shape_intersections(
	space_state: PhysicsDirectSpaceState2D,
	shape: Shape2D,
	global_pos: Vector2,
	collision_mask: int,
	max_results: int,
	collide_with_areas: bool = true,
	collide_with_bodies: bool = false
) -> Array[Dictionary]:
	
	if not is_instance_valid(space_state) or not is_instance_valid(shape):
		return []

	# --- 1. DYNAMIC DEBUG INTERCEPT INTERACTION ---
	if ENABLE_VISUAL_DEBUG and OS.is_debug_build():
		DebugSpatialVisualizer.register_debug_draw(
			shape, 
			global_pos, 
			DEBUG_COLOR_DEFAULT, 
			DEBUG_FLASH_DURATION
		)

	# Allocate transient query parameters on the spot
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0, global_pos)
	query.collision_mask = collision_mask
	query.collide_with_areas = collide_with_areas
	query.collide_with_bodies = collide_with_bodies

	return space_state.intersect_shape(query, max_results)
