class_name UpgradeManager
extends Node

signal upgrade_options_ready(options: Array[UpgradeChoice])

var _cached_full_pool: Array[UpgradeChoice] = []
var _level_up_queue: Array[int] = []
var _is_presenting_ui: bool = false

func _ready() -> void:
	EventBus.player_leveled_up.connect(_on_player_leveled_up)
	EventBus.upgrade_selected.connect(_on_ui_upgrade_selected)
	EventBus.upgrade_reroll_requested.connect(reroll_current_options)


func _on_player_leveled_up(new_level: int) -> void:
	var current_player = EventBus.active_player
	if not is_instance_valid(current_player): 
		return
		
	var player_global_tree = current_player.upgrade_tree_component
	if is_instance_valid(player_global_tree):
		player_global_tree.rebuild_upgrade_caches([] as Array[Tags.Type], new_level)
		
	_level_up_queue.append(new_level)
	_try_process_next_level_up()


func _try_process_next_level_up() -> void:
	if _is_presenting_ui or _level_up_queue.is_empty():
		return

	var current_player = EventBus.active_player
	if not is_instance_valid(current_player): 
		return

	_is_presenting_ui = true
	get_tree().paused = true
	
	var _processing_level = _level_up_queue.pop_front()
	_cached_full_pool = generate_selection_pool(current_player)
	
	var rolled_options: Array[UpgradeChoice] = _roll_random_subset(_cached_full_pool, 3)
	upgrade_options_ready.emit(rolled_options)


func reroll_current_options() -> void:
	# Enforce safety guard limits (E.g. spend a reroll currency token here if desired)
	if not _is_presenting_ui or _cached_full_pool.is_empty():
		return
		
	# Instantly roll a fresh subset deck without expensive hierarchy lookups
	var fresh_rolled_options: Array[UpgradeChoice] = _roll_random_subset(_cached_full_pool, 3)
	
	# Broadcast the fresh cards straight to the UI listeners to update the screen
	upgrade_options_ready.emit(fresh_rolled_options)


func _on_ui_upgrade_selected(chosen_choice: UpgradeChoice) -> void:
	var current_player = EventBus.active_player
	if not is_instance_valid(chosen_choice) or not is_instance_valid(current_player):
		return
		
	chosen_choice.source_tracker.current_purchases += 1
	var base_upgrade_id = chosen_choice.definition.upgrade_id
	
	# Extract situational variables to pass safely across the boundary interfaces
	var current_level = current_player.current_level if "current_level" in current_player else 1
	
	if chosen_choice.target_ability_id != 0:
		var ability = current_player.ability_container.get_ability_by_id(chosen_choice.target_ability_id)
		if is_instance_valid(ability) and is_instance_valid(ability.upgrade_tree):
			var active_tags = ability.tag_component.get_active_tags() if is_instance_valid(ability.tag_component) else []
			
			# Registers purchase and automatically forces an O(N) evaluation block right here
			ability.upgrade_tree.register_purchase(base_upgrade_id, active_tags, current_level)
	else:
		var player_tree = current_player.get_node_or_null("UpgradeTreeComponent") as UpgradeTreeComponent
		if is_instance_valid(player_tree):
			player_tree.register_purchase(base_upgrade_id, [], current_level)
	
	current_player.apply_contextual_upgrade(chosen_choice)
	_cached_full_pool.clear()
	_is_presenting_ui = false
	
	if _level_up_queue.is_empty():
		get_tree().paused = false
	else:
		get_tree().process_frame.connect(_try_process_next_level_up, CONNECT_ONE_SHOT)


func generate_selection_pool(target_player: Player) -> Array[UpgradeChoice]:
	var full_pool: Array[UpgradeChoice] = []
	if not is_instance_valid(target_player) or not is_instance_valid(target_player.ability_container):
		return full_pool

	# --- 1. Gather Upgrades and Evolutions From All Active Weapons ---
	var active_abilities = target_player.ability_container.get_active_abilities()
	for ability in active_abilities:
		if not ability is Ability or not is_instance_valid(ability.upgrade_tree_component): 
			continue

		_append_choices_from_tree(
			full_pool, 
			ability.upgrade_tree_component, 
			ability.get_instance_id(), 
			ability.display_name
		)

	# --- 2. Gather Upgrades and First-Time Unlocks From Player Global Core ---
	var player_global_tree = target_player.upgrade_tree_component
	if is_instance_valid(player_global_tree):		
		# Append global character buffs and brand new unowned ability unlocks (target_id = 0)
		_append_choices_from_tree(
			full_pool, 
			player_global_tree, 
			0, 
			"Character Core"
		)
			
	return full_pool


func _append_choices_from_tree(
	pool: Array[UpgradeChoice], 
	tree: UpgradeTreeComponent, 
	target_id: int, 
	target_display_name: String
) -> void:
	
	# 1. Map standard structural stat progression choices
	var cached_upgrades = tree.get_cached_upgrades()
	for tracker in cached_upgrades:
		var choice = UpgradeChoice.new()
		choice.source_tracker = tracker
		choice.target_ability_id = target_id
		choice.target_display_name = target_display_name
		pool.append(choice)
		
	# 2. Map structural unlock possibilities (Evolutions if ID > 0, New Skills if ID = 0)
	var cached_unlocks = tree.get_cached_evolutions()
	for tracker in cached_unlocks:
		var choice = UpgradeChoice.new()
		choice.source_tracker = tracker
		choice.target_ability_id = target_id
		choice.target_display_name = target_display_name
		pool.append(choice)


## Slices a duplicated copy of the selection array to deliver unique random options to the UI
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
