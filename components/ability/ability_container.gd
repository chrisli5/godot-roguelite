class_name AbilityContainer
extends Node2D

var abilities: Dictionary[int, Ability] = {}


func add_ability_from_data(data: AbilityData) -> Ability:
	if data == null or data.ability_scene == null:
		push_error("AbilityContainer: Cannot add ability. Provided AbilityData or its scene is null.")
		return null
		
	var new_ability_instance: Node = data.ability_scene.instantiate()
	if not new_ability_instance is Ability:
		push_error("AbilityContainer: Instantiated scene root is not of type 'Ability'.")
		new_ability_instance.queue_free()
		return null
		
	var ability: Ability = new_ability_instance as Ability
	ability.display_name = data.display_name
	
	if data.stats_profile:
		if ability.stats_container:
			ability.stats_container.initialize_profile(data.stats_profile)
		else:
			push_warning("AbilityContainer: AbilityData contains a 'stats_profile', but the instantiated scene '%s' does not have an assigned 'stats_container'. Profile initialization skipped." % data.ability_scene.resource_path)
	
	
	add_child(ability)
	
	var instance_id: int = ability.get_instance_id()
	abilities[instance_id] = ability
	
	return ability


func execute_ability_evolution(old_ability_id: int, new_ability_data: AbilityData) -> Ability:
	if not is_instance_valid(new_ability_data):
		push_error("AbilityContainer: Evolved AbilityData payload template is empty.")
		return null
		
	var old_ability = get_ability_by_id(old_ability_id)
	if not is_instance_valid(old_ability):
		push_error("AbilityContainer: Cannot find target ability ID: " + str(old_ability_id))
		return null
		
	remove_ability_by_id(old_ability_id)
	
	var evolved_ability = add_ability_from_data(new_ability_data)
	
	print("AbilityContainer: Successfully hot-swapped ability instance frames.")
	return evolved_ability


func remove_ability_by_id(ability_instance_id: int) -> void:
	if not abilities.has(ability_instance_id):
		return
		
	var ability: Ability = abilities[ability_instance_id]
	abilities.erase(ability_instance_id)
	
	if is_instance_valid(ability):
		ability.queue_free()


func get_ability_by_id(ability_instance_id: int) -> Ability:
	if abilities.has(ability_instance_id):
		return abilities[ability_instance_id]
	return null


func add_modifier_to_ability(ability_instance_id: int, stat_type: Stat.Type, modifier: StatModifier) -> void:
	var ability: Ability = get_ability_by_id(ability_instance_id)
	if ability == null:
		push_error("AbilityContainer: Cannot add modifier. Ability with instance ID %d not found." % ability_instance_id)
		return
		
	if ability.stats_container == null:
		push_error("AbilityContainer: Cannot add modifier. Targeted ability does not have an assigned 'stats_container'.")
		return
		
	ability.stats_container.add_modifier(stat_type, modifier)


func remove_modifier_from_ability(ability_instance_id: int, stat_type: Stat.Type, modifier_id: String) -> void:
	var ability: Ability = get_ability_by_id(ability_instance_id)
	if ability == null:
		return
		
	if ability.stats_container == null:
		return
		
	ability.stats_container.remove_modifier(stat_type, modifier_id)


func add_infusion_tags_to_ability(ability_id: int, tags_to_add: Array[Tags.Type]) -> void:
	var ability = get_ability_by_id(ability_id)
	
	if is_instance_valid(ability) and is_instance_valid(ability.tag_component):
		for tag in tags_to_add:
			ability.tag_component.add_tag(tag)


func get_active_abilities() -> Array:
	return abilities.values()
