class_name ProjectileGeometry
extends GeometryDriver

@export_group("Components")
@export var spawner_component: ProjectileSpawnerComponent

@export_group("Spreading Math Defaults")
@export var spread_angle_degrees: float = 15.0

func _ready() -> void:
	var required_components: Array[String] = [
		"spawner_component",
	]
	
	if not ComponentValidator.validate_components(self, required_components):
		set_physics_process(false)
		return

## Virtual Method: Intended to be completely overridden by child classes
func execute_geometry(_query_results: Dictionary, _final_payload: CombatPayload) -> void:
	push_error("Abstract method 'execute_geometry' not implemented on " + name)
	delivery_finished.emit()


## UTILITY HELPER 1: Handles the math for standard fan/scatter multishot deployment.
## Call this from child classes when they want standard multi-shot scattering.
func _spawn_scatter_projectiles(
	origin: Vector2, 
	base_direction: Vector2, 
	tracked_id: int, 
	payload: CombatPayload
) -> void:
	if not is_instance_valid(spawner_component):
		return

	var base_angle := base_direction.angle()
	var stats: Node = instance_from_id(payload.stats_container_id)
	var has_stats := is_instance_valid(stats)
	var projectile_amount: float = stats.get_final_stat_value(Stat.Type.PROJECTILE_AMOUNT) if has_stats else 1.0
	
	for i in range(projectile_amount):
		var final_direction := base_direction

		if projectile_amount > 1:
			var offset_step := i - (projectile_amount - 1) / 2.0
			var angle_offset := deg_to_rad(offset_step * spread_angle_degrees)
			final_direction = Vector2.from_angle(base_angle + angle_offset)

		spawner_component.spawn_projectile(origin, final_direction, tracked_id, payload)


## UTILITY HELPER 2: Standardizes payload duplication and targeting instance stamps
func _prepare_custom_payload(tracked_id: int, base_payload: CombatPayload) -> CombatPayload:
	var customized_payload := base_payload.duplicate() as CombatPayload
	if tracked_id > 0:
		customized_payload.caster_instance_id = tracked_id
	return customized_payload
