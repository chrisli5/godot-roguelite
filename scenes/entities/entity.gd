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
@export var sprite_node: Sprite2D

var entity_data: EntityData = null

func _ready() -> void:
	var required_entity_components: Array[String] = [
		"ability_container",
		"stats_container",
		"health_component",
		"hurtbox_component",
		"status_effect_component",
		"tag_component",
		"sprite_node",
	]
	
	if not ComponentValidator.validate_components(self, required_entity_components):
		#set_physics_process(false)
		return
	
	if is_instance_valid(health_component) and is_instance_valid(stats_container):
		health_component.health_depleted.connect(_on_health_depleted)
		health_component.bind_to_stats(stats_container)
			
	if is_instance_valid(hurtbox_component):
		hurtbox_component.hit_received.connect(_on_hit_received)
		hurtbox_component.owner_entity = self
		
	if is_instance_valid(entity_data):
		_configure_base_entity_layers()


func _configure_base_entity_layers() -> void:
	if entity_data.sprite_texture and is_instance_valid(sprite_node):
		sprite_node.texture = entity_data.sprite_texture

	if entity_data.stats_profile and is_instance_valid(stats_container):
		stats_container.initialize_profile(entity_data.stats_profile)

	if entity_data.movement_strategy_scene is PackedScene:
		if is_instance_valid(movement_strategy):
			movement_strategy.queue_free()
			
		var move_inst = entity_data.movement_strategy_scene.instantiate() as MovementStrategy
		if move_inst:
			add_child(move_inst)
			movement_strategy = move_inst


func initialize_entity(incoming_data: EntityData) -> void:
	entity_data = incoming_data


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
