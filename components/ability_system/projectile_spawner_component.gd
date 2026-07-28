class_name ProjectileSpawnerComponent
extends Node

## Emitted outwards to bubble up collision events to the parent ability handler
signal projectile_impacted(target: Node2D)

## The baseline projectile scene file (.tscn)
@export var projectile_scene: PackedScene

## Instantiates a projectile and injects fully processed, raw parameter data
func spawn(start_pos: Vector2, target_dir: Vector2, speed_value: float, lifetime_value: float) -> Projectile:
	if projectile_scene == null:
		push_error("ProjectileSpawnerComponent: Missing scene reference assignment.")
		return null
		
	var instance: Node = projectile_scene.instantiate()
	if not instance is Projectile:
		push_error("ProjectileSpawnerComponent: Target instance root is not a Projectile class.")
		instance.queue_free()
		return null
		
	var projectile: Projectile = instance as Projectile
	
	# Pure numerical assignment—no stat containers or dictionary lookups here
	projectile.base_speed = speed_value
	projectile.lifetime = lifetime_value
	projectile.spawn_position = start_pos
	projectile.direction = target_dir.normalized()
	
	# Bubble up the impact data blindly to whatever orchestrator spawned us
	projectile.collided.connect(func(target: Node2D) -> void:
		projectile_impacted.emit(target)
	)
	
	get_tree().current_scene.add_child(projectile)
	return projectile
