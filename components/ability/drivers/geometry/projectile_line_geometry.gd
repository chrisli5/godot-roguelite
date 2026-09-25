class_name ProjectileLineDriver
extends GeometryDriver

@export_group("Components")
@export var spawner_component: ProjectileSpawnerComponent

var spread_angle_degrees: float = 15.0


func execute_geometry(
	global_origin: Vector2, 
	target_direction: Vector2,
	final_payload: CombatPayload
) -> void:
	if not is_instance_valid(spawner_component):
		push_error("ProjectileLineDriver: Required spawner sub-component configuration link is missing.")
		return
		
	var base_direction := target_direction if target_direction != Vector2.ZERO else Vector2.RIGHT
	var base_angle := base_direction.angle()
	
	var stats = final_payload.stats_source
	var has_stats := is_instance_valid(stats)
	var projectile_amount: float = stats.get_stat_value(Stat.Type.PROJECTILE_AMOUNT, 1.0) if has_stats else 1.0
	
	for i in range(projectile_amount):
		var final_direction := base_direction

		if projectile_amount > 1:
			var offset_step := i - (projectile_amount - 1) / 2.0
			var angle_offset := deg_to_rad(offset_step * spread_angle_degrees)
			final_direction = Vector2.from_angle(base_angle + angle_offset)

		spawner_component.spawn_projectile(
			global_origin, 
			final_direction,
			final_payload
		)
		delivery_finished.emit()
