# res://components/ability/evolution_gate_component.gd
class_name EvolutionGateComponent
extends Node

enum EvolutionState { TIER_1_BASE, TIER_2_EVOLVED, TIER_3_APEX }

@export_group("System State Monitoring")
var current_state: EvolutionState = EvolutionState.TIER_1_BASE
var is_permanently_overclocked: bool = false


## Refactored: Evaluates hand-crafted unlock recipes strictly from definitions rather than local trackers
func evaluate_evolution_recipes(
	available_definitions: Array[UpgradeDefinition], 
	infusion_levels: Array[int], 
	active_tags: Array[Tags.Type]
) -> Array[UpgradeDefinition]:
	
	var eligible_evos: Array[UpgradeDefinition] = []
	if is_permanently_overclocked:
		return eligible_evos

	# --- STEP 1: CALCULATE ACTIVE ELEMENT METRICS ---
	var active_socket_count: int = 0
	var elements_at_soft_cap_count: int = 0
	
	var current_soft_cap_ceiling = 3 if current_state == EvolutionState.TIER_1_BASE else 5
	
	for level in infusion_levels:
		if level > 0:
			active_socket_count += 1
			if level >= current_soft_cap_ceiling:
				elements_at_soft_cap_count += 1

	# --- STEP 2: VERIFY SOFT LEVEL CAP THRESHOLDS ---
	var reached_soft_cap_milestone = false
	match current_state:
		EvolutionState.TIER_1_BASE:
			if active_socket_count >= 2 and elements_at_soft_cap_count >= 2:
				reached_soft_cap_milestone = true
		EvolutionState.TIER_2_EVOLVED:
			if active_socket_count >= 3 and elements_at_soft_cap_count >= 3:
				reached_soft_cap_milestone = true

	if not reached_soft_cap_milestone:
		return eligible_evos

	# --- STEP 3: CATEGORIZED RECIPE PATTERN MATCHING ---
	for definition in available_definitions:
		if not is_instance_valid(definition) or definition.payload_type != UpgradeDefinition.PayloadType.ABILITY_UNLOCK:
			continue

		var recipe_satisfied = true
		for required_tag in definition.recipe_requirements:
			if not active_tags.has(required_tag):
				recipe_satisfied = false
				break
				
		if not recipe_satisfied: 
			continue

		eligible_evos.append(definition)
			
	return eligible_evos


func advance_evolution_state() -> void:
	if current_state == EvolutionState.TIER_1_BASE:
		current_state = EvolutionState.TIER_2_EVOLVED
	elif current_state == EvolutionState.TIER_2_EVOLVED:
		current_state = EvolutionState.TIER_3_APEX
