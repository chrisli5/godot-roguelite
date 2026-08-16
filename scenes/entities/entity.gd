@abstract
class_name Entity
extends CharacterBody2D

signal died

@export_group("Components")
@export var ability_container: AbilityContainer
@export var stats_container: StatsContainer
@export var movement_component: MovementComponent
@export var status_effect_component: StatusEffectComponent
@export var tag_component: TagComponent

@export_group("Stats Profile")
@export var stats_profile: StatsProfile


func _ready() -> void:
	var components_valid: bool = true
	
	if not stats_container:
		push_error("Entity '%s' is missing a StatsContainer!" % name)
		components_valid = false
	if not stats_profile:
		push_error("Entity '%s' is missing a StatsProfile!" % name)
		components_valid = false
	if not movement_component:
		push_error("Entity '%s' is missing a MovementComponent!" % name)
		components_valid = false
	
	if not components_valid:
		return
		
	status_effect_component.modifier_addition_requested.connect(_on_add_stat_modifier_requested)
	status_effect_component.modifier_removal_requested.connect(_on_remove_stat_modifier_requested)
	
	stats_container.initialize_profile(stats_profile)


@abstract
func _handle_movement_physics() -> void


func add_stat_modifier(stat_type: Stat.Type, modifier: StatModifier, target_ability_id: int) -> void:
	if not is_instance_valid(modifier): return
	var active_stats_container = _resolve_stats_container(target_ability_id)
	if is_instance_valid(active_stats_container):
		active_stats_container.add_modifier(stat_type, modifier)


func remove_stat_modifier(stat_type: Stat.Type, modifier_id: String, target_ability_id: int) -> void:
	var active_stats_container = _resolve_stats_container(target_ability_id)
	if is_instance_valid(active_stats_container):
		active_stats_container.remove_modifier(stat_type, modifier_id)


func apply_contextual_upgrade(choice: UpgradeChoice) -> void:
	var definition: UpgradeDefinition = choice.definition
	if not is_instance_valid(definition):
		return
		
	# 1. Delegate infusion tags directly to the managing container component
	if definition.tags.has(Tags.Type.INFUSION) and choice.target_ability_id > 0:
		if is_instance_valid(ability_container):
			ability_container.add_infusion_tags_to_ability(choice.target_ability_id, definition.tags)
	
	# 2. Process systemic structural execution passes
	match definition.payload_type:
		UpgradeDefinition.PayloadType.STAT_MODIFIER:
			add_stat_modifier(definition.target_stat_type, definition.modifier, choice.target_ability_id)
			
		UpgradeDefinition.PayloadType.ABILITY_UNLOCK:
			if choice.target_ability_id > 0:
				if is_instance_valid(ability_container):
					ability_container.execute_ability_evolution(choice.target_ability_id, definition.ability_to_unlock)
			else: 
				if is_instance_valid(ability_container) and is_instance_valid(definition.ability_to_unlock):
					ability_container.add_ability_from_data(definition.ability_to_unlock)


func _resolve_stats_container(target_ability_id: int) -> StatsContainer:
	if target_ability_id > 0:
		if is_instance_valid(ability_container):
			var ability = ability_container.get_ability_by_id(target_ability_id)
			if is_instance_valid(ability) and is_instance_valid(ability.stats_container):
				return ability.stats_container
		return null
	return stats_container


func _route_infusion_tag_payload(choice: UpgradeChoice) -> void:
	if choice.target_ability_id <= 0:
		return
		
	var target_ability = ability_container.get_ability_by_id(choice.target_ability_id)
	if not is_instance_valid(target_ability):
		return
		
	if target_ability.tag_component:
		for tag in choice.definition.tags:
			target_ability.tag_component.add_tag(tag)


func _on_add_stat_modifier_requested(stat_type: Stat.Type, modifier: StatModifier, target_ability_id: int):
	add_stat_modifier(stat_type, modifier, target_ability_id)


func _on_remove_stat_modifier_requested(stat_type: Stat.Type, modifier_id: String, target_ability_id: int):
	remove_stat_modifier(stat_type, modifier_id, target_ability_id)
