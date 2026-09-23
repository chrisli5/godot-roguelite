class_name ProjectileSpawnerComponent
extends Node

signal projectile_impacted(target: Node2D)

@export var projectile_scene: PackedScene


func spawn_projectile(
	start_pos: Vector2, 
	target_dir: Vector2, 
	stats_source: StatsContainer,
	hit_payload: HitPayload
) -> Projectile:
	if projectile_scene == null:
		push_error("ProjectileSpawnerComponent on '%s': Missing projectile scene reference." % get_parent().name)
		return null
		
	var instance: Node = projectile_scene.instantiate()
	if not instance is Projectile:
		push_error("ProjectileSpawnerComponent: Target instance root is not a Projectile class.")
		instance.queue_free()
		return null
		
	var projectile: Projectile = instance as Projectile
	projectile.collided.connect(_on_projectile_collided)
	projectile.hit_payload = hit_payload
	
	projectile.spawn_position = start_pos
	projectile.direction = target_dir.normalized()
	
	projectile.movement_speed = stats_source.get_stat_value(Stat.Type.PROJECTILE_MOVEMENT_SPEED, 400.0)
	projectile.collision_radius = stats_source.get_stat_value(Stat.Type.AOE_RADIUS, 10)

	
	get_tree().current_scene.add_child(projectile)
	return projectile


func _on_projectile_collided(target: Node2D) -> void:
	projectile_impacted.emit(target)
