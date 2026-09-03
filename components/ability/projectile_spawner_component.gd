class_name ProjectileSpawnerComponent
extends Node

signal projectile_impacted(target: Node2D)

@export var projectile_scene: PackedScene


func spawn_projectile(start_pos: Vector2, target_dir: Vector2, speed_value: float, hit_payload: HitPayload) -> Projectile:
	if projectile_scene == null:
		push_error("ProjectileSpawnerComponent on '%s': Missing projectile scene reference." % get_parent().name)
		return null
		
	var instance: Node = projectile_scene.instantiate()
	if not instance is Projectile:
		push_error("ProjectileSpawnerComponent: Target instance root is not a Projectile class.")
		instance.queue_free()
		return null
		
	var projectile: Projectile = instance as Projectile
	
	# 1. Assign physical movement vectors
	projectile.base_speed = speed_value
	projectile.spawn_position = start_pos
	projectile.direction = target_dir.normalized()
	
	# 2. Directly inject the pre-packaged payload passed from the orchestrator
	projectile.hit_payload = hit_payload
	
	# 3. Bubble up impact data safely via signals
	projectile.collided.connect(func(target: Node2D) -> void:
		projectile_impacted.emit(target)
	)
	
	get_tree().current_scene.add_child(projectile)
	return projectile
