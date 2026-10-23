class_name SpatialQuery
extends RefCounted


const ENABLE_VISUAL_DEBUG: bool = true
const DEBUG_COLOR_DEFAULT := Color(1.0, 0.3, 0.3, 1.0)
const DEBUG_FLASH_DURATION: float = 0.05


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


## Finds the enemy hurtboxes that overlap `shape` at `global_pos`, in the order the physics server returns them.
## Player hurtboxes and `exclude_instance_id` are skipped. Not sorted, not de-duplicated.
static func query_enemy_hurtboxes(
	space_state: PhysicsDirectSpaceState2D,
	shape: Shape2D,
	global_pos: Vector2,
	exclude_instance_id: int = 0
) -> Array[HurtboxComponent]:
	var intersections := query_shape_intersections(
		space_state, shape, global_pos, CombatPhysics.ENEMY_HURTBOX_MASK, CombatPhysics.MAX_QUERY_RESULTS
	)
	return filter_enemy_hurtboxes(intersections, exclude_instance_id)


## Keeps the colliders of `intersections` that are valid enemy hurtboxes: drops null and non-hurtbox colliders,
## player hurtboxes and `exclude_instance_id`. Keeps the order and any repeats.
static func filter_enemy_hurtboxes(intersections: Array[Dictionary], exclude_instance_id: int = 0) -> Array[HurtboxComponent]:
	var hurtboxes: Array[HurtboxComponent] = []
	for result in intersections:
		var hurtbox := result.get("collider") as HurtboxComponent
		if not is_instance_valid(hurtbox) or hurtbox.is_player_hurtbox:
			continue
		if hurtbox.get_instance_id() == exclude_instance_id:
			continue
		hurtboxes.append(hurtbox)
	return hurtboxes
