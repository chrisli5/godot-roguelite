@abstract
class_name Entity
extends CharacterBody2D

signal died

@export_group("Components")
@export var ability_container: AbilityContainer
@export var stats_container: StatsContainer
@export var health_component: HealthComponent
@export var hurtbox_component: HurtboxComponent
@export var movement_component: MovementComponent
@export var status_effect_component: StatusEffectComponent
@export var tag_component: TagComponent


func _ready() -> void:
	var required_entity_components: Array[String] = [
		"ability_container",
		"stats_container",
		"health_component",
		"hurtbox_component",
		"movement_component",
		"status_effect_component",
		"tag_component"
	]
	
	if not ValidationUtility.validate_components(self, required_entity_components):
		#set_physics_process(false)
		return
	
	
	if is_instance_valid(stats_container):
		stats_container.stat_updated.connect(_on_stat_updated)
	
	if is_instance_valid(health_component) and is_instance_valid(stats_container):
		var base_max_health = stats_container.get_stat_value(Stat.Type.MAX_HEALTH, 100.0)
		health_component.update_max_health(base_max_health, false)
		health_component.set_to_full()
		health_component.health_depleted.connect(_on_health_depleted)
			
	if is_instance_valid(hurtbox_component):
		hurtbox_component.hit_received.connect(_on_hit_received)


func _on_stat_updated(stat_type: Stat.Type, new_value: float) -> void:
	if stat_type == Stat.Type.MAX_HEALTH and is_instance_valid(health_component):
		health_component.update_max_health(new_value, true)


func _on_hit_received(payload: HitPayload) -> void:
	if is_instance_valid(health_component):
		health_component.take_damage(payload.final_damage)
		
	if is_instance_valid(status_effect_component):
		for effect in payload.status_effects_to_apply:
			status_effect_component.apply_effect(effect)


func _on_health_depleted() -> void:
	died.emit()
	queue_free()
