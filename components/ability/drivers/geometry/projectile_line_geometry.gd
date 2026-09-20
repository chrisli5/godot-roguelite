# res://components/ability/drivers/geometry/projectile_line_driver.gd
class_name ProjectileLineDriver
extends GeometryDriver

@export_group("Sub-Component Isolation Links")
## Blind factory module handling raw scene instantiation and scene tree mounting
@export var spawner_component: ProjectileSpawnerComponent

@export_group("Pattern Layout Overrides")
## The total number of missiles spawned per execution tick (e.g., 1 for base, 3 for shotgun Overclock)
@export var projectile_count: int = 1
## The angular spread spread between splitting shots in degrees (e.g., 15.0)
@export var spread_angle_degrees: float = 15.0


## Dictates the exact geometric arrangement of missiles fired, completely free of scene tree mounting logic
func execute_delivery(
	global_origin: Vector2, 
	target_direction: Vector2, 
	current_speed: float, 
	current_aoe_scale: float, 
	final_payload: HitPayload
) -> void:
	
	if not is_instance_valid(spawner_component):
		push_error("ProjectileLineDriver: Required spawner sub-component configuration link is missing.")
		return
		
	var base_direction := target_direction if target_direction != Vector2.ZERO else Vector2.RIGHT
	var base_angle := base_direction.angle()
	
	# --- GEOMETRIC SHAPE ENFORCEMENT LOOP ---
	# The driver calculates the spatial blueprint layout, passing the vectors down to the factory tool
	for i in range(projectile_count):
		var final_direction := base_direction
		
		# If multi-shot layout parameters are active, compute the angular layout configuration splits
		if projectile_count > 1:
			var offset_step := i - (projectile_count - 1) / 2.0
			var angle_offset := deg_to_rad(offset_step * spread_angle_degrees)
			final_direction = Vector2.from_angle(base_angle + angle_offset)
			
		# Delegate object allocation completely down to the isolated spawning module lane
		spawner_component.spawn_projectile(
			global_origin, 
			final_direction, 
			current_speed, 
			final_payload
		)
		delivery_finished.emit()
