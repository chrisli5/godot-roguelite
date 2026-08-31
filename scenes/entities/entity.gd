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
			
	stats_container.initialize_profile(stats_profile)


@abstract
func _handle_movement_physics() -> void


func apply_contextual_upgrade(choice: UpgradeChoice) -> void:
	var definition = choice.definition
	if not is_instance_valid(definition):
		return
		
	# --- BRANCH A: CORE CHARACTER / MULTIPLIER UPGRADES (STAT_MODIFIER) ---
	if definition.payload_type == UpgradeDefinition.PayloadType.STAT_MODIFIER:
		if choice.target_slot_index > 0:
			# Route weapon stats (e.g. +5% Damage) directly to the target slot track
			if is_instance_valid(ability_container):
				ability_container.add_stat_modifier_to_slot(choice.target_slot_index, definition.target_stat_type, definition.modifier)
		else:
			# Apply player character core stat adjustments (e.g., Player Speed, Max Health)
			stats_container.add_modifier(definition.target_stat_type, definition.modifier)
		return

	# --- BRANCH B: STRUCTURAL MUTATIONS (ABILITY_UNLOCK) ---
	if definition.payload_type == UpgradeDefinition.PayloadType.ABILITY_UNLOCK:
		if not is_instance_valid(ability_container):
			return
			
		# Check if the player already owns a weapon node in that designated slot index track
		var existing_ability = ability_container.get_ability_by_slot(choice.target_slot_index)
		
		if not is_instance_valid(existing_ability):
			# SCENARIO 1: FIRST-TIME WEAPON UNLOCK
			# Slot index is empty -> Mount a fresh weapon instance directly into the role lane
			ability_container.add_ability_from_data(definition.ability_data_payload)
			print("[UNLOCK] New ability successfully mounted into static Slot: ", choice.target_slot_index)
		else:
			# SCENARIO 2: ABILITY EVOLUTION GEOMETRY SWAP
			# Slot is already occupied -> Execute a data-migrated hot-swap scene transition!
			ability_container.execute_ability_evolution(definition.ability_data_payload)
			print("[EVOLUTION] Active slot morphed. State data migrated cleanly on Slot: ", choice.target_slot_index)


func _route_infusion_tag_payload(choice: UpgradeChoice) -> void:
	if choice.target_slot_index <= 0:
		return
		
	var target_ability = ability_container.get_ability_by_id(choice.target_slot_index)
	if not is_instance_valid(target_ability):
		return
		
	if target_ability.tag_component:
		for tag in choice.definition.tags:
			target_ability.tag_component.add_tag(tag)
