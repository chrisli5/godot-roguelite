class_name ArcaneMissile
extends Ability

@export_group("Modular Behavioral Components")
@export var targeting_component: NearestTargetingComponent
@export var spawner_component: ProjectileSpawnerComponent


var _cooldown_timer: Timer

func _ready() -> void:
	super()
	var required_subability_components: Array[String] = [
		"targeting_component",
		"spawner_component",
	]
	
	if not ValidationUtility.validate_components(self, required_subability_components):
		set_physics_process(false)
		return
	
	if is_instance_valid(tag_component):
		tag_component.add_tag(Tags.Type.METAMAGIC)
		tag_component.add_tag(Tags.Type.PROJECTILE)
		
	_setup_clock()


func _setup_clock() -> void:
	_cooldown_timer = Timer.new()
	
	var initial_cooldown = 0.8
	if is_instance_valid(stats_container):
		initial_cooldown = stats_container.get_stat_value(Stat.Type.COOLDOWN, 0.8)
		
	_cooldown_timer.wait_time = initial_cooldown
	_cooldown_timer.autostart = true
	_cooldown_timer.timeout.connect(_on_fire_tick)
	add_child(_cooldown_timer)


func _on_fire_tick() -> void:
	if not is_instance_valid(targeting_component) or not is_instance_valid(spawner_component):
		return

	var current_speed: float = 400.0
	if is_instance_valid(stats_container):
		current_speed = stats_container.get_stat_value(Stat.Type.SPEED, 400.0)
	
	# 3. Process spatial targeting
	var target = targeting_component.get_nearest_target(global_position)
	if not is_instance_valid(target):
		return
		
	var fire_direction = (target.global_position - global_position).normalized()
	var final_payload = CombatCalculations.generate_hit_payload(owner, stats_container, tag_component)
	
	spawner_component.spawn_projectile(
		global_position, 
		fire_direction, 
		current_speed, 
		final_payload
	)


func _on_stat_updated(stat_type: Stat.Type, new_value: float) -> void:
	if stat_type == Stat.Type.COOLDOWN and is_instance_valid(_cooldown_timer):
		_cooldown_timer.wait_time = new_value
