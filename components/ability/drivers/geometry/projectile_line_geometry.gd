# res://components/ability/drivers/geometry/projectile_line_driver.gd
class_name ProjectileLineGeometry
extends GeometryDriver

@export_group("Sub-Component Isolation Links")
@export var targeting_component: NearestTargetingComponent
@export var spawner_component: ProjectileSpawnerComponent


func execute_delivery(current_speed: float, current_aoe_scale: float, final_payload: HitPayload) -> void:
	if not is_instance_valid(targeting_component) or not is_instance_valid(spawner_component):
		push_error("ProjectileLineDriver: Required isolation sub-components are invalid or missing.")
		return
		
	# 1. Spatial target calculation
	var target: Node2D = targeting_component.get_nearest_target(global_position)
	if not is_instance_valid(target):
		return
		
	# 2. Compute delivery vectors
	var fire_direction: Vector2 = (target.global_position - global_position).normalized()
	
	# 3. Instantly pass packet down to spawning modules
	spawner_component.spawn_projectile(
		global_position, 
		fire_direction, 
		current_speed, 
		final_payload
	)
