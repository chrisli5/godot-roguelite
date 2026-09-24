class_name UpgradeManager
extends Node

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
	
	var next_level_to_process: int = _level_up_queue.pop_front()
	var current_player = EventBus.active_player
	
	if is_instance_valid(current_player) and current_player.has_method("compile_character_eligible_pool"):
		current_player.compile_character_eligible_pool(next_level_to_process)

	if is_instance_valid(current_player):
		_cached_full_pool = generate_selection_pool(current_player, next_level_to_process)
		var rolled_options = _roll_random_subset(_cached_full_pool, 3)
		EventBus.upgrade_options_ready.emit(rolled_options)


func trigger_infusion_draft_event() -> void:
	var current_player = EventBus.active_player
	if not is_instance_valid(current_player) or not is_instance_valid(current_player.upgrade_ledger_component):
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


func _generate_infusion_pool(target_player: Player) -> Array[UpgradeChoice]:
	var infusion_pool: Array[UpgradeChoice] = []
	var player_ledger = target_player.upgrade_ledger_component
	
	for tracker in player_ledger.available_infusions:
		var definition = tracker.definition
		if not is_instance_valid(definition) or tracker.current_purchases >= tracker.max_purchases:
			continue
			
		var choice = UpgradeChoice.new()
		choice.source_tracker = tracker
		choice.target_slot_index = 0
		choice.target_display_name = "Global Elements"
		infusion_pool.append(choice)
		
	return infusion_pool


func generate_selection_pool(target_player: Player, processing_level: int) -> Array[UpgradeChoice]:
	var full_pool: Array[UpgradeChoice] = []
	if not is_instance_valid(target_player) or not is_instance_valid(target_player.ability_container):
		return full_pool
		
	var container = target_player.ability_container

	for slot_idx in range(1, 5):
		var ability = container.get_ability_by_slot(slot_idx)
		if not is_instance_valid(ability): 
			continue

		ability.compile_eligible_pool(processing_level)
		_append_choices_from_ledger(full_pool, ability.upgrade_ledger_component, slot_idx, ability.display_name)

	var player_ledger = target_player.upgrade_ledger_component
	if is_instance_valid(player_ledger):
		_append_choices_from_ledger(full_pool, player_ledger, 0, "Character Core")
			
	return full_pool


func _append_choices_from_ledger(pool: Array[UpgradeChoice], ledger: UpgradeLedgerComponent, source_slot: int, target_name: String) -> void:
	for tracker in ledger.get_cached_upgrades():
		var choice = UpgradeChoice.new()
		choice.source_tracker = tracker
		choice.target_slot_index = source_slot 
		choice.target_display_name = target_name
		pool.append(choice)
		
	for tracker in ledger.get_cached_evolutions():
		var choice = UpgradeChoice.new()
		choice.source_tracker = tracker
		choice.target_display_name = target_name
		
		var definition = tracker.definition
		if source_slot == 0 and definition.payload_type == UpgradeDefinition.PayloadType.ABILITY_UNLOCK:
			var target_role_slot: int = definition.ability_data_payload.slot_index
			var container = EventBus.active_player.ability_container
			
			if is_instance_valid(container) and is_instance_valid(container.get_ability_by_slot(target_role_slot)):
				continue
				
			choice.target_slot_index = target_role_slot
			choice.target_display_name = "Unlock " + definition.ability_data_payload.display_name
		else:
			choice.target_slot_index = source_slot
			
		pool.append(choice)


## Stateless Tag-Based Click Intercept Resolution:
func _on_ui_upgrade_selected(chosen_choice: UpgradeChoice) -> void:
	var current_player = EventBus.active_player
	if not is_instance_valid(chosen_choice) or not is_instance_valid(current_player):
		return

	var definition = chosen_choice.definition
	if not is_instance_valid(definition):
		return

	# --- 1. OPTIMIZED ELEMENTAL INFUSIONS FILTERING ---
	# Looks explicitly at draft filter categories, leaving recipe arrays clean
	if definition.draft_behavior_tags.has(Tags.Type.INFUSION):
		print("[INFUSION CHOSEN] Passing entire choice package to allocation panel...")
		EventBus.infusion_allocation_requested.emit(chosen_choice)
		_cached_full_pool.clear()
		return 

	# --- 2. REGULAR PROGRESSION & UNLOCK RESOLUTION ---
	chosen_choice.source_tracker.current_purchases += 1
	var base_upgrade_id = definition.upgrade_id
	var current_level = current_player.progression_component.current_level if is_instance_valid(current_player.progression_component) else 1
	
	if chosen_choice.target_slot_index > 0:
		var ability = current_player.ability_container.get_ability_by_slot(chosen_choice.target_slot_index)
		if is_instance_valid(ability) and is_instance_valid(ability.upgrade_ledger_component):
			ability.upgrade_ledger_component.log_purchase_entry(base_upgrade_id)
			ability.compile_eligible_pool(current_level)
	else:
		var player_ledger = current_player.upgrade_ledger_component
		if is_instance_valid(player_ledger):
			player_ledger.log_purchase_entry(base_upgrade_id)
	
	current_player.apply_contextual_upgrade(chosen_choice)
	
	_cached_full_pool.clear()
	get_tree().process_frame.connect(_try_process_next_level_up, CONNECT_ONE_SHOT)


func _on_infusion_allocation_confirmed(finalized_choice: UpgradeChoice) -> void:
	# 1. Increment purchases on the player's core master element tracking card family
	finalized_choice.source_tracker.current_purchases += 1
	print("_on_infusion_allocation_confirmed")
	var current_player = EventBus.active_player
	if is_instance_valid(current_player):
		var player_ledger = current_player.upgrade_ledger_component
		if is_instance_valid(player_ledger):
			# Log purchase inside the single source of truth player memory ledger
			player_ledger.log_purchase_entry(finalized_choice.definition.upgrade_id)
		
		print("[UPGRADE MANAGER] Infusion placement locked. Forwarding finalized package to Player...")
		
		# --- THE CRITICAL FIX: INVOKE THE MUTATION PIPELINE ---
		# This routes the choice straight to Player._process_elemental_infusion() 
		# where the tags are updated and the Single Value Scaling stats are injected!
		current_player.apply_contextual_upgrade(finalized_choice)
		
	# 2. Clear out menu choice variable caches to prepare for subsequent queued transactions
	_is_presenting_ui = false
	_try_process_next_level_up()


func reroll_current_options() -> void:
	if not _is_presenting_ui or _cached_full_pool.is_empty():
		return

	var fresh_rolled_options: Array[UpgradeChoice] = _roll_random_subset(_cached_full_pool, 3)
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
