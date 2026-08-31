class_name UpgradeManager
extends Node

var _cached_full_pool: Array[UpgradeChoice] = []
var _level_up_queue: Array[int] = []
var _is_presenting_ui: bool = false


func _ready() -> void:
	EventBus.player_leveled_up.connect(_on_player_leveled_up)
	EventBus.upgrade_selected.connect(_on_ui_upgrade_selected)
	EventBus.upgrade_reroll_requested.connect(reroll_current_options)


func _on_player_leveled_up(new_level: int) -> void:
	_level_up_queue.append(new_level)
	print("[PLAYER] ", "Level: ", new_level, " added to queue")
	if not _is_presenting_ui:
		_try_process_next_level_up()


## Pulls sequentially from the queue frame to keep level pools tightly synchronized
func _try_process_next_level_up() -> void:
	if _level_up_queue.is_empty():
		get_tree().paused = false
		_is_presenting_ui = false
		return
		
	_is_presenting_ui = true
	get_tree().paused = true 
	
	var next_level_to_process: int = _level_up_queue.pop_front()
	var current_player = EventBus.active_player
	
	if is_instance_valid(current_player) and current_player.has_method("compile_character_eligible_pool"):
		current_player.compile_character_eligible_pool(next_level_to_process)

	if is_instance_valid(current_player):
		_cached_full_pool = generate_selection_pool(current_player, next_level_to_process)
		var rolled_options = _roll_random_subset(_cached_full_pool, 3)
		print("[UPGRADE] Level: ", next_level_to_process, " upgrade options processed.")
		EventBus.upgrade_options_ready.emit(rolled_options)


func generate_selection_pool(target_player: Player, processing_level: int) -> Array[UpgradeChoice]:
	var full_pool: Array[UpgradeChoice] = []
	if not is_instance_valid(target_player) or not is_instance_valid(target_player.ability_container):
		return full_pool
		
	var container = target_player.ability_container

	# --- 1. Symmetrical Gathering from Fixed Structural Weapon Slots (1 to 4) ---
	# Starts at 1 to fully align with our Immutable 1-Based Slot Index design patterns
	for slot_idx in range(1, 5):
		var ability = container.get_ability_by_slot(slot_idx)
		if not is_instance_valid(ability): 
			continue

		ability.compile_eligible_pool(processing_level)
		_append_choices_from_ledger(full_pool, ability.upgrade_ledger_component, slot_idx, ability.display_name)

	# --- 2. Pure O(1) Symmetrical Fetch From Player Character Core Ledger (Index 0) ---
	var player_ledger = target_player.upgrade_ledger_component
	if is_instance_valid(player_ledger):
		_append_choices_from_ledger(full_pool, player_ledger, 0, "Character Core")
			
	return full_pool


## Reusable helper function that maps ledger caches onto abstract UI choice structures
func _append_choices_from_ledger(pool: Array[UpgradeChoice], ledger: UpgradeLedgerComponent, source_slot: int, target_name: String) -> void:
	# 1. Map standard linear stat upgrades (STAT_MODIFIER)
	for tracker in ledger.get_cached_upgrades():
		var choice = UpgradeChoice.new()
		choice.source_tracker = tracker
		choice.target_slot_index = source_slot # Maps straight to 0 for player stats, or 1-4 for weapon stats
		choice.target_display_name = target_name
		pool.append(choice)
		
	# 2. Map structural unlock possibilities (Evolutions if source_slot > 0, New Skills if source_slot == 0)
	for tracker in ledger.get_cached_evolutions():
		var choice = UpgradeChoice.new()
		choice.source_tracker = tracker
		choice.target_display_name = target_name
		
		var definition = tracker.definition
		# --- SYMMETRICAL ABILITY UNLOCK INTEGRATION ---
		if source_slot == 0 and definition.payload_type == UpgradeDefinition.PayloadType.ABILITY_UNLOCK:
			# Extract the targeted structural slot assignment straight from the ability role enum
			var target_role_slot: int = definition.ability_data_payload.slot_index
			var container = EventBus.active_player.ability_container
			
			# Safety Gate: If a skill already occupies this slot index, block the duplicate unlock drop
			if is_instance_valid(container) and is_instance_valid(container.get_ability_by_slot(target_role_slot)):
				continue
				
			# OVERWRITE DESTINATION: Symmetrically stamp the choice with its true, static slot role target
			choice.target_slot_index = target_role_slot
			choice.target_display_name = "Unlock " + definition.ability_data_payload.display_name
		else:
			# Standard Weapon Evolution path: retains its existing active slot position (1 to 4)
			choice.target_slot_index = source_slot
			
		pool.append(choice)


## Triggered by the UI View layer when a player clicks a choice card container node
func _on_ui_upgrade_selected(chosen_choice: UpgradeChoice) -> void:
	var current_player = EventBus.active_player
	if not is_instance_valid(chosen_choice) or not is_instance_valid(current_player):
		return

	chosen_choice.source_tracker.current_purchases += 1
	var base_upgrade_id = chosen_choice.definition.upgrade_id
	var current_level = current_player.current_level if "current_level" in current_player else 1
	
	# Route purchase logging based entirely on our unconvertible slot indexing rules
	if chosen_choice.target_slot_index > 0:
		var ability = current_player.ability_container.get_ability_by_slot(chosen_choice.target_slot_index)
		
		if is_instance_valid(ability) and is_instance_valid(ability.upgrade_ledger):
			# Log purchase inside the single source of truth data register ledger
			ability.upgrade_ledger.log_purchase_entry(base_upgrade_id)
			
			# Increment milestone specialty tokens if a custom payload card was chosen
			if chosen_choice.definition.has_meta("specialty_payload") and is_instance_valid(ability.infusion_tracker):
				ability.infusion_tracker.specialty_cards_purchased += 1
				
			# Refresh the weapon's local caches immediately following its selection transaction
			ability.compile_eligible_pool(current_level)
	else:
		# Player core character registers purchase entry inside its local ledger
		var player_ledger = current_player.upgrade_ledger_component
		if is_instance_valid(player_ledger):
			player_ledger.log_purchase_entry(base_upgrade_id)
	
	# Command player entity node to execute physical mutations or slot deployments
	current_player.apply_contextual_upgrade(chosen_choice)
	
	# Clear menu variable pools to prepare for subsequent steps
	_cached_full_pool.clear()
	get_tree().process_frame.connect(_try_process_next_level_up, CONNECT_ONE_SHOT)


func reroll_current_options() -> void:
	if not _is_presenting_ui or _cached_full_pool.is_empty():
		return

	var fresh_rolled_options: Array[UpgradeChoice] = _roll_random_subset(_cached_full_pool, 3)
	EventBus.upgrade_options_ready.emit(fresh_rolled_options)


func _roll_random_subset(pool: Array[UpgradeChoice], count: int) -> Array[UpgradeChoice]:
	var results: Array[UpgradeChoice] = []
	if pool.is_empty(): 
		return results
		
	# Duplicate array element pointers to prevent disrupting our master evaluation tracking records
	var working_pool = pool.duplicate()
	working_pool.shuffle()
	
	# Safely extract up to the requested card size restriction count boundary limit
	var actual_count = min(count, working_pool.size())
	for i in range(actual_count):
		results.append(working_pool[i])
		
	return results
