class_name ArcaneMissile
extends Ability

@export_group("Modular Behavioral Components")
@export var targeting_module: NearestTargetingComponent
@export var spawner_module: ProjectileSpawnerComponent

# Stats managed locally or scaled via Player modifiers
var base_damage: float = 15.0
var cooldown_duration: float = 0.8
var projectile_speed: float = 400.0

var _cooldown_timer: Timer

func _ready() -> void:
	# Enforce structural tracking tags string-free
	if is_instance_valid(tag_component):
		tag_component.add_tag(Tags.Type.METAMAGIC)
		tag_component.add_tag(Tags.Type.PROJECTILE)
		
	_setup_clock()


func _setup_clock() -> void:
	_cooldown_timer = Timer.new()
	_cooldown_timer.wait_time = cooldown_duration
	_cooldown_timer.autostart = true
	_cooldown_timer.timeout.connect(_on_fire_tick)
	add_child(_cooldown_timer)


func _on_fire_tick() -> void:
	# Check if components are valid before delegating action loops
	if not is_instance_valid(targeting_module) or not is_instance_valid(spawner_module):
		return
		
	# 1. Ask the targeting component for a target position
	var target = targeting_module.get_nearest_target(global_position)
	if not is_instance_valid(target):
		return
		
	var fire_direction = (target.global_position - global_position).normalized()
	var active_tags = tag_component.get_active_tags() if is_instance_valid(tag_component) else []
	
	# 2. Command the pattern spawner to execute the visual blast vector
	spawner_module.spawn_projectile(
		global_position, 
		fire_direction, 
		projectile_speed, 
		base_damage, 
		active_tags
	)
