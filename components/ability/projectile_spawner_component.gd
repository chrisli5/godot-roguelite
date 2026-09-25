class_name ProjectileSpawnerComponent
extends Node

signal projectile_impacted(target: Node2D)

@export var projectile_scene: PackedScene


func spawn_projectile(start_pos: Vector2, target_dir: Vector2, hit_payload: CombatPayload) -> Projectile:
	if projectile_scene == null:
		push_error("ProjectileSpawnerComponent: Missing projectile scene prefab configuration reference.")
		return null
		
	var instance: Node = projectile_scene.instantiate()
	if not instance is Projectile:
		push_error("ProjectileSpawnerComponent: Instantiated root is not of type Projectile.")
		instance.queue_free()
		return null
		
	var projectile: Projectile = instance as Projectile
	
	# Clean, single-line contract handoff. No leaking internal parameters!
	projectile.initialize_projectile(start_pos, target_dir, hit_payload)
	projectile.collided.connect(_on_projectile_collided)
	
	# Add cleanly straight to the dynamic current active scene tree level pipeline
	EventBus.spawn_requested.emit(projectile)
	return projectile


func _on_projectile_collided(target: Node2D) -> void:
	projectile_impacted.emit(target)
