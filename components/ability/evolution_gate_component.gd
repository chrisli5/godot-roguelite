class_name EvolutionGateComponent
extends Node

enum EvolutionState { TIER_1_BASE, TIER_2_EVOLVED, TIER_3_APEX }

@export_group("System State Monitoring")
var current_state: EvolutionState = EvolutionState.TIER_1_BASE
var is_permanently_overclocked: bool = false


func get_upgrade_id_from_element(element_tag: Tags.Type) -> String:
	match element_tag:
		Tags.Type.FIRE: return "inf_fire"
		Tags.Type.FROST: return "inf_frost"
		Tags.Type.WIND: return "inf_wind"
		Tags.Type.LIGHTNING: return "inf_lightning"
		Tags.Type.EARTH: return "inf_earth"
		_: return ""


## Evaluates structural morphology parameters and recipe matches to return valid mutation choices.
func evaluate_evolution_recipes(
	available_evolutions: Array[UpgradeTracker], 
	purchase_levels: Dictionary[String, int], 
	active_tags: Array[Tags.Type]
) -> Array[UpgradeTracker]:
	
	var eligible_evos: Array[UpgradeTracker] = []
	if is_permanently_overclocked:
		return eligible_evos

	# --- STEP 1: CALCULATE ACTIVE ELEMENT METRICS ---
	var active_socket_count: int = 0
	var elements_at_soft_cap_count: int = 0
	
	# Determine the exact soft cap target based on the current evolution tier state machine
	var current_soft_cap_ceiling = 3 if current_state == EvolutionState.TIER_1_BASE else 5
	
	for key in purchase_levels.keys():
		if key.begins_with("inf_") and purchase_levels[key] > 0:
			active_socket_count += 1
			if purchase_levels[key] >= current_soft_cap_ceiling:
				elements_at_soft_cap_count += 1

	# --- STEP 2: VERIFY SOFT LEVEL CAP THRESHOLDS ---
	var reached_soft_cap_milestone = false
	match current_state:
		EvolutionState.TIER_1_BASE:
			# Soft cap reached when exactly 2 unique element tracks hit Level 3
			if active_socket_count >= 2 and elements_at_soft_cap_count >= 2:
				reached_soft_cap_milestone = true
		EvolutionState.TIER_2_EVOLVED:
			# Apex tier reached when all 3 element tracks hit Level 5
			if active_socket_count >= 3 and elements_at_soft_cap_count >= 3:
				reached_soft_cap_milestone = true

	if not reached_soft_cap_milestone:
		return eligible_evos

	# --- STEP 3: UNORDERED MATHEMATICAL SET RECIPE MATCHING ---
	for tracker in available_evolutions:
		var definition = tracker.definition
		if not is_instance_valid(definition) or tracker.current_purchases >= tracker.max_purchases: 
			continue
		
		# Validate that this is a structural morphology swap layout card
		if definition.payload_type != UpgradeDefinition.PayloadType.ABILITY_UNLOCK:
			continue
			
		# Enforce character level gating boundaries
		if tracker.required_character_level > 1 and not definition.tags.has(Tags.Type.CROWD_CONTROL):
			# If it's labeled as an Overclock template, skip to avoid recipe mixing
			continue

		# Order-Agnostic Subset Check: Ensure the weapon houses ALL required elements string-free
		var recipe_satisfied = true
		for required_tag in definition.tags:
			if required_tag == Tags.Type.INFUSION: 
				continue
			if not active_tags.has(required_tag):
				recipe_satisfied = false
				break
				
		if not recipe_satisfied: 
			continue

		# Infusion Pacing Depth Check: Ensure every component element meets the required level threshold
		var all_infusions_meet_requirement = true
		for req_tag in definition.tags:
			if req_tag == Tags.Type.INFUSION: 
				continue
			var target_upgrade_key = get_upgrade_id_from_element(req_tag)
			var current_infusion_level = purchase_levels.get(target_upgrade_key, 0)
			
			if current_infusion_level < current_soft_cap_ceiling:
				all_infusions_meet_requirement = false
				break 
		
		if all_infusions_meet_requirement: 
			eligible_evos.append(tracker)
			
	return eligible_evos


func advance_evolution_state() -> void:
	if current_state == EvolutionState.TIER_1_BASE:
		current_state = EvolutionState.TIER_2_EVOLVED
	elif current_state == EvolutionState.TIER_2_EVOLVED:
		current_state = EvolutionState.TIER_3_APEX
