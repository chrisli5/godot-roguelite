class_name AbilityContainer
extends Node2D

var max_slots: int = 4
var abilities: Dictionary[int, Ability] = {}
var _entity_root: Node2D = null


func _ready() -> void:
	_entity_root = get_parent() as Node2D


func add_ability_from_data(ability_data: AbilityData) -> Ability:
	if ability_data == null or ability_data.base_ability_scene == null:
		push_error("AbilityContainer: Cannot mount ability. Provided AbilityData or its generic base scene is null.")
		return null
	
	var slot_index: int = ability_data.slot_index
	if slot_index < 0 or slot_index >= max_slots:
		push_error("AbilityContainer: Hotbar slot index %d is out of bounds." % slot_index)
		return null
		
	var new_ability_instance: Node = ability_data.base_ability_scene.instantiate()
	if not new_ability_instance is Ability:
		push_error("AbilityContainer: Instantiated asset root is not of type 'Ability'.")
		new_ability_instance.queue_free()
		return null
		
	var ability: Ability = new_ability_instance as Ability
	if ability_data.stats_profile and ability.stats_container:
		ability.stats_container.initialize_profile(ability_data.stats_profile)
	
	if abilities.has(slot_index):
		remove_ability_by_slot(slot_index)
		
	add_child(ability)
	abilities[slot_index] = ability
	if is_instance_valid(_entity_root):
		ability.initialize_caster_context(_entity_root)

	ability.swap_runtime_strategies(ability_data)
	
	return ability


func execute_ability_evolution(new_ability_data: AbilityData) -> Ability:
	if not is_instance_valid(new_ability_data):
		push_error("AbilityContainer: Evolved blueprint metadata template is empty.")
		return null
	
	var slot_index: int = new_ability_data.slot_index
	var target_ability = get_ability_by_slot(slot_index)
	
	if not is_instance_valid(target_ability):
		push_error("AbilityContainer: Target ability wrapper not found on slot index: " + str(slot_index))
		return null
	
	if is_instance_valid(_entity_root):
		target_ability.initialize_caster_context(_entity_root)
		
	target_ability.swap_runtime_strategies(new_ability_data)
	
	if is_instance_valid(target_ability.evolution_gate_component):
		target_ability.evolution_gate_component.advance_evolution_state()
	
	print("AbilityContainer: Unified Evolution completed for Wrapper Slot Index: ", slot_index)
	return target_ability


func remove_ability_by_slot(slot_index: int) -> void:
	if not abilities.has(slot_index):
		return
		
	var ability: Ability = abilities[slot_index]
	abilities.erase(slot_index)
	
	if is_instance_valid(ability):
		ability.queue_free()


func get_ability_by_slot(slot_index: int) -> Ability:
	return abilities.get(slot_index, null)


func add_stat_modifier_to_slot(slot_index: int, stat_type: Stat.Type, modifier: StatModifier) -> void:
	var ability: Ability = get_ability_by_slot(slot_index)
	if ability == null:
		push_error("[ABILITYCONTAINER] Cannot add modifier. Ability on slot index %d not found." % slot_index)
		return
		
	if ability.stats_container == null:
		push_error("[ABILITYCONTAINER] Cannot add modifier. Targeted ability does not have an assigned 'stats_container'.")
		return
		
	ability.stats_container.add_modifier(stat_type, modifier)


func remove_stat_modifier_from_slot(slot_index: int, stat_type: Stat.Type, modifier_id: String) -> void:
	var ability: Ability = get_ability_by_slot(slot_index)
	if ability == null:
		return
		
	if ability.stats_container == null:
		return
		
	ability.stats_container.remove_modifier(stat_type, modifier_id)


func add_infusion_tags_to_ability(slot_index: int, tags_to_add: Array[Tags.Type]) -> void:
	var ability = get_ability_by_slot(slot_index)
	
	if is_instance_valid(ability) and is_instance_valid(ability.tag_component):
		for tag in tags_to_add:
			ability.tag_component.add_tag(tag)


func get_active_abilities() -> Array[Ability]:
	var ordered_list: Array[Ability] = []
	
	# Sequentially loop through fixed slot bounds to handle empty index slots safely
	for i in range(max_slots):
		if abilities.has(i) and is_instance_valid(abilities[i]):
			ordered_list.append(abilities[i])
			
	return ordered_list


func apply_global_modifiers_to_ability(ability: Ability) -> void:
	var player = EventBus.active_player
	if is_instance_valid(player) and is_instance_valid(player.upgrade_ledger_component):
		var player_ledger = player.upgrade_ledger_component
		var weapon_tags = ability.tag_component.get_active_tags() if is_instance_valid(ability.tag_component) else []

		for tracker in player_ledger.available_upgrades:
			var definition = tracker.definition
			if not is_instance_valid(definition) or not definition.payload_type == UpgradeDefinition.PayloadType.STAT_MODIFIER:
				continue

			if not definition.global_modifier_tags.is_empty():
				var player_purchased_tier = player_ledger.purchase_levels.get(definition.upgrade_id, 0)
				
				# If the player has actually invested in this global modifier card
				if player_purchased_tier > 0:
					var tag_match_found = false
					for modifier_tag in definition.global_modifier_tags:
						if weapon_tags.has(modifier_tag):
							tag_match_found = true
							break
							
					# Symmetrically inject the historical global card straight into the new node!
					if tag_match_found:
						if is_instance_valid(ability.stats_container):
							var global_modifier_instance: StatModifier = definition.stat_modifier_payload.duplicate()
							global_modifier_instance.id = ModifierFactory.generate_id(
								ModifierFactory.OriginSource.GLOBAL_UPGRADE,
								tracker,
								ability
							)
							ability.stats_container.add_modifier(definition.target_stat_type, global_modifier_instance)
