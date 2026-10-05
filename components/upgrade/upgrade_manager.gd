class_name UpgradeManager
extends Node

## Holds the raw full collection of available run upgrades that can be rolled.
## Typically seeded from a master Act database resource or individual player configuration arrays.
@export var master_upgrade_pool: Array[UpgradeBlueprintProfile] = []

var _cached_full_pool: Array[UpgradeChoice] = []
var _level_up_queue: Array[int] = []
var _is_presenting_ui: bool = false


func _ready() -> void:
	EventBus.player_leveled_up.connect(_on_player_leveled_up)
	EventBus.upgrade_selected.connect(_on_ui_upgrade_selected)
	EventBus.upgrade_reroll_requested.connect(reroll_current_options)
	EventBus.infusion_allocation_confirmed.connect(_on_infusion_allocation_confirmed)


func _on_player_leveled_up(new_level: int) -> void:
	_level_up_queue.append(new_level)
	if not _is_presenting_ui:
		_try_process_next_level_up()


func _try_process_next_level_up() -> void:
	if _level_up_queue.is_empty():
		get_tree().paused = false
		_is_presenting_ui = false
		return
		
	_is_presenting_ui = true
	get_tree().paused = true 

	var current_player: Player = instance_from_id(EventBus.active_player_instance_id) as Player
	var next_level_to_process: int = _level_up_queue.pop_front()
	
	if is_instance_valid(current_player):
		# Pass the central player reference and level context to compile our subset pool
		_cached_full_pool = generate_selection_pool(current_player, next_level_to_process)
		var rolled_options = _roll_random_subset(_cached_full_pool, 3)
		EventBus.upgrade_options_ready.emit(rolled_options)


func trigger_initial_draft_event() -> void:
	var current_player: Player = instance_from_id(EventBus.active_player_instance_id) as Player
	if not is_instance_valid(current_player):
		return
		
	_is_presenting_ui = true
	get_tree().paused = true
	
	var available_choices: Array[UpgradeChoice] = _generate_initial_ability_pool(current_player)
	if available_choices.is_empty():
		get_tree().paused = false
		_is_presenting_ui = false
		return

	var rolled_options = _roll_random_subset(available_choices, 3)
	EventBus.upgrade_options_ready.emit(rolled_options)


func trigger_infusion_draft_event() -> void:
	var current_player: Player = instance_from_id(EventBus.active_player_instance_id) as Player
	if not is_instance_valid(current_player):
		return
		
	_is_presenting_ui = true
	get_tree().paused = true
	
	var available_choices: Array[UpgradeChoice] = _generate_infusion_pool(current_player)
	if available_choices.is_empty():
		get_tree().paused = false
		_is_presenting_ui = false
		return
		
	_cached_full_pool = available_choices
	var rolled_options = _roll_random_subset(_cached_full_pool, 3)
	EventBus.upgrade_options_ready.emit(rolled_options)


func _generate_initial_ability_pool(_target_player: Player) -> Array[UpgradeChoice]:
	var ability_pool: Array[UpgradeChoice] = []
	
	for profile in master_upgrade_pool:
		if not is_instance_valid(profile): continue
		for definition in profile.definition_bundle:
			if definition.payload_type == UpgradeDefinition.PayloadType.ABILITY_UNLOCK:
				var choice = UpgradeChoice.new()
				
				# Wrap into a dummy template tracker for UI consumption cards
				var tracker := UpgradeTracker.new()
				tracker.definition = definition
				
				choice.source_tracker = tracker
				choice.target_slot_index = 0
				ability_pool.append(choice)
				
	return ability_pool


func _generate_infusion_pool(target_player: Player) -> Array[UpgradeChoice]:
	var infusion_pool: Array[UpgradeChoice] = []

	for profile in master_upgrade_pool:
		if not is_instance_valid(profile): continue
		for definition in profile.definition_bundle:
			if definition.is_infusion():
				var current_tier = target_player.run_ledger.purchase_registry.get(definition.upgrade_id, 0)
				if current_tier >= profile.total_tiers: continue
				
				var choice = UpgradeChoice.new()
				var tracker := UpgradeTracker.new()
				tracker.definition = definition
				tracker.current_purchases = current_tier
				tracker.max_purchases = profile.total_tiers
				
				choice.source_tracker = tracker
				choice.target_slot_index = 0
				choice.target_display_name = "Global Elements"
				infusion_pool.append(choice)
		
	return infusion_pool


## MASTER COMPILED SELECTION POOL:
## Evaluates the player's single central ledger, looks up max ceilings from profiles,
## and contextually routes appropriate targets dynamically.
func generate_selection_pool(target_player: Player, processing_level: int) -> Array[UpgradeChoice]:
	var full_pool: Array[UpgradeChoice] = []
	var ledger := target_player.run_ledger_component
	var container := target_player.ability_container
	
	for profile in master_upgrade_pool:
		if not is_instance_valid(profile): continue
		
		for definition in profile.definition_bundle:
			var current_tier = ledger.purchase_registry.get(definition.upgrade_id, 0)
			
			# Ceiling Gating: Skip if player has already maxed out this card's tiers
			var max_allowed = 1 if definition.payload_type == UpgradeDefinition.PayloadType.ABILITY_UNLOCK else profile.total_tiers
			if current_tier >= max_allowed:
				continue
				
			# Level Gating: Dynamic scale calculation pass
			var dynamic_req_level = profile.initial_unlock_level + (current_tier * profile.levels_per_tier)
			if processing_level < dynamic_req_level:
				continue

			# Build core tracking instance container
			var tracker := UpgradeTracker.new()
			tracker.definition = definition
			tracker.current_purchases = current_tier
			tracker.max_purchases = max_allowed

			# --- CONTEXTUAL ROUTING MATRIX ---
			match definition.scope:
				UpgradeDefinition.ScopeType.CHARACTER_CORE:
					var choice = UpgradeChoice.new()
					choice.source_tracker = tracker
					choice.target_slot_index = 0
					choice.target_display_name = "Character Core"
					full_pool.append(choice)
					
				UpgradeDefinition.ScopeType.LOCAL_SLOT:
					# Direct Weapon Upgrade: Link context specifically to the target slot index lane
					var target_ability = container.get_ability_by_slot(definition.restrict_to_slot)
					if is_instance_valid(target_ability):
						var choice = UpgradeChoice.new()
						choice.source_tracker = tracker
						choice.target_slot_index = definition.restrict_to_slot
						choice.target_display_name = target_ability.display_name
						full_pool.append(choice)
						
				UpgradeDefinition.ScopeType.GLOBAL_TAG_MATCH:
					# Broad Passive: Loops through active weapons to see if ANY match the requested taxonomy tags
					var match_found := false
					for slot_idx in range(1, 5):
						var ability = container.get_ability_by_slot(slot_idx)
						if is_instance_valid(ability) and is_instance_valid(ability.tag_component):
							for req_tag in definition.target_tags:
								if ability.tag_component.has_tag(req_tag):
									match_found = true
									break
									
					if match_found:
						var choice = UpgradeChoice.new()
						choice.source_tracker = tracker
						choice.target_slot_index = 0
						choice.target_display_name = "Matching Active Tags"
						full_pool.append(choice)
						
	return full_pool


func _on_ui_upgrade_selected(chosen_choice: UpgradeChoice) -> void:
	var current_player: Player = instance_from_id(EventBus.active_player_instance_id) as Player
	if not is_instance_valid(chosen_choice) or not is_instance_valid(current_player):
		return

	# --- ELEMENTAL INFUSION RE-ROUTING ---
	if chosen_choice.is_infusion:
		print("[INFUSION DRAFT] Rerouting choices straight to the element allocation screen layout...")
		EventBus.infusion_allocation_requested.emit(chosen_choice)
		_cached_full_pool.clear()
		return 

	# Forward transaction package directly to the central Player RunLedger
	current_player.apply_contextual_upgrade(chosen_choice)
	
	_cached_full_pool.clear()
	# Resolve coroutine tree updates on the next process frame tick cleanly
	get_tree().process_frame.connect(_try_process_next_level_up, CONNECT_ONE_SHOT)


func _on_infusion_allocation_confirmed(finalized_choice: UpgradeChoice) -> void:
	var current_player: Player = instance_from_id(EventBus.active_player_instance_id) as Player
	
	if is_instance_valid(current_player):
		# Forward finalized placement data safely down to player mutation channels
		current_player.apply_contextual_upgrade(finalized_choice)
		
	_is_presenting_ui = false
	_try_process_next_level_up()


func reroll_current_options() -> void:
	if not _is_presenting_ui or _cached_full_pool.is_empty():
		return

	var fresh_rolled_options := _roll_random_subset(_cached_full_pool, 3)
	EventBus.upgrade_options_ready.emit(fresh_rolled_options)


func _roll_random_subset(pool: Array[UpgradeChoice], count: int) -> Array[UpgradeChoice]:
	var results: Array[UpgradeChoice] = []
	if pool.is_empty(): 
		return results
		
	var working_pool = pool.duplicate()
	working_pool.shuffle()
	
	var actual_count = min(count, working_pool.size())
	for i in range(actual_count):
		results.append(working_pool[i])
		
	return results
