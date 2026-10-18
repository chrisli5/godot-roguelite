class_name AbilityContainer
extends Node2D

@export var base_ability_scene: PackedScene

## Hotbar slots are 1-4. Slot 0 is reserved for the Character Core (player stats)
## and never holds an Ability.
const MIN_SLOT: int = 1
const MAX_SLOT: int = 4
var abilities: Dictionary[int, Ability] = {}
var _entity_root: Node2D = null


func _ready() -> void:
	_entity_root = get_parent() as Node2D


## SCENARIO A: First-Time Slot Deployment (Empty Slate Node Initialization)
func add_ability_from_data(ability_data: AbilityData) -> Ability:
	if ability_data == null or not base_ability_scene is PackedScene:
		push_error("AbilityContainer: Cannot mount ability. Provided AbilityData or its generic base scene is null.")
		return null
	
	var slot_index: int = ability_data.slot_index
	if slot_index < MIN_SLOT or slot_index > MAX_SLOT:
		push_error("AbilityContainer: Hotbar slot index %d is out of bounds (valid: %d-%d)." % [slot_index, MIN_SLOT, MAX_SLOT])
		return null
		
	var new_ability_instance: Node = base_ability_scene.instantiate()
	if not new_ability_instance is Ability:
		push_error("AbilityContainer: Instantiated asset root is not of type 'Ability'.")
		new_ability_instance.queue_free()
		return null
		
	var ability: Ability = new_ability_instance as Ability
	
	# Clear out overlapping weapon wrappers cleanly from memory if slots clash
	if abilities.has(slot_index):
		remove_ability_by_slot(slot_index)
		
	add_child(ability)
	abilities[slot_index] = ability
	
	# Inject spatial references safely BEFORE initializing strategies
	if is_instance_valid(_entity_root):
		ability.initialize_caster_context(_entity_root)

	# The owning player's ledger (null when the owner is not a Player, e.g. an enemy)
	var ledger: RunLedgerComponent = null
	var owner_player := _entity_root as Player
	if is_instance_valid(owner_player):
		ledger = owner_player.run_ledger_component

	# Configure slot context routing indices (1-4 matching hotbar slots).
	# Tags first: the stats container reads them while building its initial values.
	if is_instance_valid(ability.tag_component):
		ability.tag_component.configure_slot_context(slot_index, ledger)

	if is_instance_valid(ability.stats_container):
		ability.stats_container.configure_slot_context(slot_index, ledger, ability.tag_component)
		ability.stats_container.initialize_profile(ability_data.stats_profile)

	# The tracker keeps no levels of its own: it answers from the ledger for this slot.
	if is_instance_valid(ability.infusion_tracker_component):
		ability.infusion_tracker_component.configure_slot_context(slot_index, ledger)

	# Same for Overclock: the gate answers from the ledger for this slot.
	if is_instance_valid(ability.evolution_gate_component):
		ability.evolution_gate_component.configure_slot_context(slot_index, ledger)

	# --- UNIFIED STRATEGY CONTRACT HANDOFF ---
	# Automatically configures spatial query parameters and custom sorting hooks contextually
	ability.swap_runtime_strategies(ability_data)
	
	return ability


## SCENARIO B: Strategy Geometry Swap / Overclock Variant Mutation
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


func add_stat_modifier_to_slot(slot_index: int, modifier: StatModifier) -> void:
	var ability: Ability = get_ability_by_slot(slot_index)
	if ability == null:
		push_error("[ABILITYCONTAINER] Cannot add modifier. Ability on slot index %d not found." % slot_index)
		return
		
	if ability.stats_container == null:
		push_error("[ABILITYCONTAINER] Cannot add modifier. Targeted ability does not have an assigned 'stats_container'.")
		return
		
	# Adds cleanly into the local transient pool (equipment, local status effects, etc.)
	ability.stats_container.add_modifier(modifier)


func remove_stat_modifier_from_slot(slot_index: int, modifier: StatModifier) -> void:
	var ability: Ability = get_ability_by_slot(slot_index)
	if ability == null or ability.stats_container == null:
		return
		
	ability.stats_container.remove_modifier(modifier)


func get_active_abilities() -> Array[Ability]:
	var ordered_list: Array[Ability] = []
	for i in range(MIN_SLOT, MAX_SLOT + 1):
		if abilities.has(i) and is_instance_valid(abilities[i]):
			ordered_list.append(abilities[i])
	return ordered_list
