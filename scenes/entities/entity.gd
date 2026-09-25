@abstract
class_name Entity
extends CharacterBody2D

signal died

@export_group("Components")
@export var ability_container: AbilityContainer
@export var stats_container: StatsContainer
@export var health_component: HealthComponent
@export var hurtbox_component: HurtboxComponent
@export var status_effect_component: StatusEffectComponent
@export var tag_component: TagComponent
@export var movement_strategy: MovementStrategy

@export_group("Stats Profile")
@export var stats_profile: StatsProfile


func _ready() -> void:
	var required_entity_components: Array[String] = [
		"ability_container",
		"stats_container",
		"health_component",
		"hurtbox_component",
		"movement_strategy",
		"status_effect_component",
		"tag_component"
	]
	
	if not ComponentValidator.validate_components(self, required_entity_components):
		#set_physics_process(false)
		return
	
	
	if is_instance_valid(stats_container):
		stats_container.stat_updated.connect(_on_stat_updated)
		if "stats_profile" in self and self.stats_profile:
			stats_container.initialize_profile(self.stats_profile)
	
	if is_instance_valid(health_component) and is_instance_valid(stats_container):
		health_component.health_depleted.connect(_on_health_depleted)
		health_component.bind_to_stats(stats_container)
			
	if is_instance_valid(hurtbox_component):
		hurtbox_component.hit_received.connect(_on_hit_received)


func _on_stat_updated(stat_type: Stat.Type, new_value: float) -> void:
	if stat_type == Stat.Type.MAX_HEALTH and is_instance_valid(health_component):
		health_component.update_max_health(new_value, true)


func _on_hit_received(payload: CombatPayload) -> void:
	if is_instance_valid(health_component):
		health_component.take_damage(payload.final_damage)
		
	if is_instance_valid(status_effect_component):
		for effect in payload.status_effects_to_apply:
			status_effect_component.apply_effect(effect)


func _on_health_depleted() -> void:
	died.emit()
	queue_free()
