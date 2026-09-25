# ================================================
# FILE: components/upgrade/upgrade_ledger_component.gd
# ================================================
class_name UpgradeLedgerComponent
extends Node

# Running memory tracker arrays serving choices straight to the dynamic UI
var available_upgrades: Array[UpgradeTracker] = []
var available_evolutions: Array[UpgradeTracker] = []
var overclock_tracker: UpgradeTracker = null

# Centralized ledger runtime purchase log framework
var purchase_levels: Dictionary[String, int] = {}

# Pre-compiled local O(1) cache pools served to the UI
var _cached_eligible_upgrades: Array[UpgradeTracker] = []
var _cached_eligible_evolutions: Array[UpgradeTracker] = []


## STREAMLINED INGESTION PIPELINE: 
## Can be safely called by Player, Base Ability, or even future systems like Trinkets/Items.
func initialize_ledger(blueprints: Array[UpgradeBlueprintProfile]) -> void:
	available_upgrades.clear()
	available_evolutions.clear()
	overclock_tracker = null
	
	for profile in blueprints:
		if not is_instance_valid(profile):
			continue
			
		# Generate pristine stable memory instances of trackers from configuration files
		for tracker in profile.generate_trackers():
			var definition = tracker.definition
			if not is_instance_valid(definition):
				continue
				
			# Route definitions neatly using existing data-driven payload tags
			if definition.payload_type == UpgradeDefinition.PayloadType.ABILITY_UNLOCK:
				# Check if this tracker is flagged explicitly as an Overclock state module
				if definition.draft_behavior_tags.has(Tags.Type.OVERCLOCK):
					overclock_tracker = tracker
				else:
					available_evolutions.append(tracker)
			else:
				available_upgrades.append(tracker)


func get_cached_upgrades() -> Array[UpgradeTracker]: return _cached_eligible_upgrades
func get_cached_evolutions() -> Array[UpgradeTracker]: return _cached_eligible_evolutions

func log_purchase_entry(base_upgrade_id: String) -> void:
	purchase_levels[base_upgrade_id] = purchase_levels.get(base_upgrade_id, 0) + 1

func clear_caches() -> void:
	_cached_eligible_upgrades.clear()
	_cached_eligible_evolutions.clear()

func overwrite_cached_pools(upgrades: Array[UpgradeTracker], evolutions: Array[UpgradeTracker]) -> void:
	_cached_eligible_upgrades = upgrades
	_cached_eligible_evolutions = evolutions


func compile_standard_eligible_pool(player_character_level: int) -> void:
	clear_caches()
	
	var compiled_upgrades: Array[UpgradeTracker] = []
	var compiled_evolutions: Array[UpgradeTracker] = []
	
	# --- OPTIMIZATION STEP 1: PARSE LINEAR WEAPON / CORE MODIFIERS ---
	for tracker in available_upgrades:
		var definition = tracker.definition
		if not is_instance_valid(definition) or tracker.current_purchases >= tracker.max_purchases:
			continue
			
		# Dynamic level step gating calculation pass (Single Value Scaling integration)
		var dynamic_req_level = tracker.required_character_level + (tracker.current_purchases * 2)
		if player_character_level < dynamic_req_level:
			continue
			
		# Symmetrically synchronize UI display numerals on the fly
		tracker.tier_index = tracker.current_purchases + 1
		compiled_upgrades.append(tracker)
		
	# --- OPTIMIZATION STEP 2: PARSE STRUCTURAL / FIRST-TIME UNLOCKS ---
	for tracker in available_evolutions:
		var definition = tracker.definition
		if not is_instance_valid(definition) or tracker.current_purchases >= tracker.max_purchases:
			continue
			
		if player_character_level < tracker.required_character_level:
			continue
			
		tracker.tier_index = tracker.current_purchases + 1
		compiled_evolutions.append(tracker)

	overwrite_cached_pools(compiled_upgrades, compiled_evolutions)
