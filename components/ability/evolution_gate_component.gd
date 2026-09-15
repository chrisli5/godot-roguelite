class_name EvolutionGateComponent
extends Node

enum EvolutionState { TIER_1_BASE, TIER_2_EVOLVED, TIER_3_APEX }

@export_group("System State Monitoring")
var current_state: EvolutionState = EvolutionState.TIER_1_BASE
var is_permanently_overclocked: bool = false


## Evaluates structural morphology parameters and recipe matches string-free using direct arrays.
func evaluate_evolution_recipes(
	available_evolutions: Array[UpgradeTracker], 
	infusion_levels: Array[int], 
	active_tags: Array[Tags.Type]
) -> Array[UpgradeTracker]:
	
	var eligible_evos: Array[UpgradeTracker] = []
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
	for tracker in available_evolutions:
		var definition = tracker.definition
		if not is_instance_valid(definition) or tracker.current_purchases >= tracker.max_purchases: 
			continue
		
		if definition.payload_type != UpgradeDefinition.PayloadType.ABILITY_UNLOCK:
			continue

		# Order-Agnostic Subset Check: Loops through recipe_requirements directly.
		# Framework elements like Tags.Type.INFUSION are separated out, removing layout friction.
		var recipe_satisfied = true
		for required_tag in definition.recipe_requirements:
			if not active_tags.has(required_tag):
				recipe_satisfied = false
				break
				
		if not recipe_satisfied: 
			continue

		eligible_evos.append(tracker)
			
	return eligible_evos


## Advances the local state machine when an evolution is successfully selected
func advance_evolution_state() -> void:
	if current_state == EvolutionState.TIER_1_BASE:
		current_state = EvolutionState.TIER_2_EVOLVED
	elif current_state == EvolutionState.TIER_2_EVOLVED:
		current_state = EvolutionState.TIER_3_APEX
