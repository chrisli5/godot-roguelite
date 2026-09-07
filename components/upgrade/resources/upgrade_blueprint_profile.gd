class_name UpgradeBlueprintProfile
extends Resource

@export_group("Blueprint Configuration Bundle")
## The list of upgrade definitions managed by this profile tracker family.
## For single-line progression lines (like Movement Speed), simply add one definition template here.
@export var definition_bundle: Array[UpgradeDefinition] = []

@export_group("Gating & Ceiling Metrics")
## The total purchase ceiling allowed for each card family in this bundle.
## Set this to 1 for unique items like first-time skill unlocks or evolutions.
@export var total_tiers: int = 5
@export var initial_unlock_level: int = 1
@export var levels_per_tier: int = 1


## UNIFIED TRACKER GENERATION PIPELINE:
## Bakes exactly ONE stable, persistent tracker object in RAM for each definition template.
func generate_trackers() -> Array[UpgradeTracker]:
	var generated_list: Array[UpgradeTracker] = []
	
	for template in definition_bundle:
		if not is_instance_valid(template): 
			continue
			
		# 1. Instantiate a single persistent tracker to hold this card family's run state
		var tracker = UpgradeTracker.new()
		
		# Isolate a pristine data copy of the asset definition to prevent global file bleeding
		tracker.definition = template.duplicate(true)
		
		# 2. Assign standard structural properties uniformly
		tracker.required_character_level = initial_unlock_level
		tracker.required_infusion_level = 1 
		tracker.current_purchases = 0
		tracker.tier_index = 1
		
		# 3. Handle maximum purchase bounds contextually based on payload type
		if template.payload_type == UpgradeDefinition.PayloadType.ABILITY_UNLOCK:
			# Structural morphological swaps and first-time skill unlocks can only be bought once
			tracker.max_purchases = 1
		else:
			# Linear cards and socketed infusions scale up to your predefined ceiling parameters
			tracker.max_purchases = total_tiers
			
		generated_list.append(tracker)
		
	return generated_list
