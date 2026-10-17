# res://components/ability/infusion_tracker_component.gd
class_name InfusionTrackerComponent
extends Node
## Answers questions about an ability's infusion levels and which sockets it still accepts.
## It stores no levels of its own: the run ledger is the single source of truth, and this component
## reads the levels of its slot from it. The ability container wires the ledger and slot in.

const INFUSION_SOFT_CAP_T1: int = 3
const INFUSION_SOFT_CAP_T2: int = 5
const INFUSION_HARD_CAP: int = 15

var _slot_index: int = 0
var _ledger: RunLedgerComponent = null

## Levels in element order (Tags.get_index_from_element: Fire, Frost, Lightning, Wind, Earth), read from the ledger.
var infusion_levels: Array[int]:
	get:
		if is_instance_valid(_ledger):
			return _ledger.get_infusion_levels(_slot_index)
		var empty_levels: Array[int] = [0, 0, 0, 0, 0]
		return empty_levels

## Sum of all element levels.
var last_calculated_total_infusions: int:
	get:
		var total_count: int = 0
		for level in infusion_levels:
			total_count += level
		return total_count


## `ledger` is the owning player's run ledger (null for ledger-less owners, which then read all zeros).
func configure_slot_context(slot_idx: int, ledger: RunLedgerComponent = null) -> void:
	_slot_index = slot_idx
	_ledger = ledger


## Refactored: Leverages explicit type-safe EvolutionState boundaries
func is_element_socket_allowed(selected_element: Tags.Type, state: EvolutionGateComponent.EvolutionState, is_overclocked: bool) -> bool:
	var element_index = Tags.get_index_from_element(selected_element)
	if element_index == -1:
		return false

	var levels := infusion_levels
	var current_element_level = levels[element_index]

	# Overclock lifts only the per-element cap; the limit on how many elements may be active still applies.
	var cap_t1: int = INFUSION_HARD_CAP if is_overclocked else INFUSION_SOFT_CAP_T1
	var cap_t2: int = INFUSION_HARD_CAP if is_overclocked else INFUSION_SOFT_CAP_T2

	var active_socket_count: int = 0
	for level in levels:
		if level > 0:
			active_socket_count += 1

	match state:
		EvolutionGateComponent.EvolutionState.TIER_1_BASE:
			if current_element_level > 0:
				return current_element_level < cap_t1
			return active_socket_count < 2

		EvolutionGateComponent.EvolutionState.TIER_2_EVOLVED:
			if current_element_level > 0:
				return current_element_level < cap_t2
			return active_socket_count < 3

		EvolutionGateComponent.EvolutionState.TIER_3_APEX:
			return current_element_level < cap_t2

	return true
