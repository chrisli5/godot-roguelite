class_name Fireball
extends Ability

@export var default_speed: float = 400.0
@export var default_lifetime: float = 3.0

## Node path hook to our blackboxed child scene component
@export_group("Components")
@export var projectile_spawner: ProjectileSpawnerComponent

func _ready() -> void:
	if projectile_spawner:
		projectile_spawner.projectile_impacted.connect(_on_fireball_impact)


func cast(caster: Entity, _target: Entity) -> void:
	if not projectile_spawner:
		return
		
	# Establish local base values
	var final_speed: float = default_speed
	var final_lifetime: float = default_lifetime
	var target_direction: Vector2 = Vector2.RIGHT
	
	# Pull dynamically modified scaling numbers using our local profile container
	if stats_container:
		final_speed = stats_container.get_stat_value(Stat.Type.SPEED, default_speed)
		# Assuming a hypothetical duration modifier setup exists:
		# final_lifetime = stats_container.get_stat_value(Stat.Type.DURATION, default_lifetime)
	
	# Inject pure numeric state variables cleanly across architectural boundaries
	projectile_spawner.spawn(caster.global_position, target_direction, final_speed, final_lifetime)

func _on_fireball_impact(hit_target: Node2D) -> void:
	# Process damage rules or status effects here based on local stats data
	print("Fireball ability confirmed hit on: ", hit_target.name)
