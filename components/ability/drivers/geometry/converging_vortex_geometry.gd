class_name ConvergingVortexDriver
extends GeometryDriver

@export_group("Physics Hardware Configuration")
@export_flags_2d_physics var enemy_collision_mask: int = 4
@export var max_results_buffer: int = 64

@export_group("Vortex Parameter Defaults")
## The continuous pixel velocity speed applied to pull enemies toward the center point.
@export var horizontal_suction_force: float = 450.0


func execute_geometry(
	global_origin: Vector2, 
	target_direction: Vector2,
	target_instance_id: int,
	final_payload: CombatPayload
) -> void:
	var hurtbox = instance_from_id(target_instance_id) as HurtboxComponent
	if not is_instance_valid(hurtbox):
		return

	var stats = instance_from_id(final_payload.stats_container_id)
	var has_stats := is_instance_valid(stats)
	var max_radius = stats.get_stat_value(Stat.Type.AOE_RADIUS, 160.0) if has_stats else 160.0

	hurtbox.take_hit(final_payload)

	var entity = hurtbox.owner_entity as CharacterBody2D
	if is_instance_valid(entity):
		var pull_vector: Vector2 = global_origin - entity.global_position
		var distance: float = pull_vector.length()
		
		if distance > 8.0:
			var pull_direction: Vector2 = pull_vector.normalized()
			var falloff_weight: float = 1.0 - (distance / max_radius)
			var calculated_force: float = horizontal_suction_force * (1.0 + falloff_weight)
				
				# Mutate physics registers directly
			entity.velocity += pull_direction * calculated_force

	delivery_finished.emit()
