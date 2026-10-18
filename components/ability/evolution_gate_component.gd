# res://components/ability/evolution_gate_component.gd
class_name EvolutionGateComponent
extends Node

enum EvolutionState { TIER_1_BASE, TIER_2_EVOLVED, TIER_3_APEX }

@export_group("System State Monitoring")
var current_state: EvolutionState = EvolutionState.TIER_1_BASE

## Read-only. Overclock lives in the run ledger; there is no stored copy.
var is_permanently_overclocked: bool:
	get:
		return is_instance_valid(_ledger) and _ledger.is_overclocked(_slot_index)

var _slot_index: int = 0
var _ledger: RunLedgerComponent


## `ledger` is the owning player's run ledger (null for ledger-less owners, which are never overclocked).
func configure_slot_context(slot_idx: int, ledger: RunLedgerComponent = null) -> void:
	_slot_index = slot_idx
	_ledger = ledger


## Soft cap per element for the current state (tier 1 = 3, later tiers = 5).
func _get_soft_cap_ceiling() -> int:
	if current_state == EvolutionState.TIER_1_BASE:
		return InfusionTrackerComponent.INFUSION_SOFT_CAP_T1
	return InfusionTrackerComponent.INFUSION_SOFT_CAP_T2


## True once enough elements are active and at the soft cap to unlock the next step.
## Tier 1: 2 active and 2 at level 3+. Tier 2: 3 active and 3 at level 5+. Tier 3: never.
func has_reached_soft_cap_milestone(infusion_levels: Array[int]) -> bool:
	var active_socket_count: int = 0
	var elements_at_soft_cap_count: int = 0
	var ceiling := _get_soft_cap_ceiling()

	for level in infusion_levels:
		if level > 0:
			active_socket_count += 1
			if level >= ceiling:
				elements_at_soft_cap_count += 1

	match current_state:
		EvolutionState.TIER_1_BASE:
			return active_socket_count >= 2 and elements_at_soft_cap_count >= 2
		EvolutionState.TIER_2_EVOLVED:
			return active_socket_count >= 3 and elements_at_soft_cap_count >= 3
	return false


## True if this ability should currently be offered an evolution / Overclock choice.
func is_offer_eligible(infusion_levels: Array[int]) -> bool:
	return not is_permanently_overclocked and has_reached_soft_cap_milestone(infusion_levels)


## True if every element in `recipe` is at or above the current soft cap. An empty recipe never matches.
## A recipe may name fewer elements than are active.
func meets_recipe(recipe: Array[Tags.Type], infusion_levels: Array[int]) -> bool:
	if recipe.is_empty():
		return false

	var ceiling := _get_soft_cap_ceiling()
	for element in recipe:
		var element_index := Tags.get_index_from_element(element)
		if element_index == -1 or element_index >= infusion_levels.size():
			return false
		if infusion_levels[element_index] < ceiling:
			return false
	return true


## Evolution cards (ABILITY_UNLOCK with evolves_from) that evolve `ability_data` and whose recipe is met.
## Returns nothing unless this ability is currently offer-eligible.
func evaluate_evolution_recipes(
	available_definitions: Array[UpgradeDefinition],
	infusion_levels: Array[int],
	ability_data: AbilityData
) -> Array[UpgradeDefinition]:
	var eligible_evos: Array[UpgradeDefinition] = []
	if not is_offer_eligible(infusion_levels):
		return eligible_evos

	for definition in available_definitions:
		if not is_instance_valid(definition) or definition.payload_type != UpgradeDefinition.PayloadType.ABILITY_UNLOCK:
			continue
		if not _is_same_ability_data(definition.evolves_from, ability_data):
			continue
		if not meets_recipe(definition.recipe_requirements, infusion_levels):
			continue
		eligible_evos.append(definition)

	return eligible_evos


## Same resource by path when both have one, otherwise by identity. Null never matches.
func _is_same_ability_data(a: AbilityData, b: AbilityData) -> bool:
	if a == null or b == null:
		return false
	if not a.resource_path.is_empty() and not b.resource_path.is_empty():
		return a.resource_path == b.resource_path
	return a == b


func advance_evolution_state() -> void:
	if current_state == EvolutionState.TIER_1_BASE:
		current_state = EvolutionState.TIER_2_EVOLVED
	elif current_state == EvolutionState.TIER_2_EVOLVED:
		current_state = EvolutionState.TIER_3_APEX


func restore_state(saved_state: EvolutionState) -> void:
	current_state = saved_state
