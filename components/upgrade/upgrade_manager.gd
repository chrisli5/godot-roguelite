class_name UpgradeManager
extends Node

signal upgrade_options_ready(options: Array[UpgradeChoice])

var _level_up_queue: Array[int] = []
var _is_presenting_ui: bool = false

func _ready() -> void:
	EventBus.player_leveled_up.connect(_on_player_leveled_up)
	EventBus.upgrade_selected.connect(_on_ui_upgrade_selected)


func _on_player_leveled_up(new_level: int) -> void:
	_level_up_queue.append(new_level)
	_try_process_next_level_up()


func _try_process_next_level_up() -> void:
	if _is_presenting_ui or _level_up_queue.is_empty():
		return

	var current_player = EventBus.active_player
	if not is_instance_valid(current_player): 
		return

	_is_presenting_ui = true
	
	var _processing_level = _level_up_queue.pop_front()

	get_tree().paused = true
	
	var full_pool: Array[UpgradeChoice] = generate_selection_pool(current_player)
	var rolled_options: Array[UpgradeChoice] = _roll_random_subset(full_pool, 3)
	
	upgrade_options_ready.emit(rolled_options)

## Intercepts user card selection events to apply state updates and resume the game loop
func _on_ui_upgrade_selected(chosen_choice: UpgradeChoice) -> void:
	var current_player = EventBus.active_player
	if not is_instance_valid(chosen_choice) or not is_instance_valid(current_player):
		return
		
	# 1. Increment purchase limits directly through the tracker resource pointer
	chosen_choice.source_tracker.current_purchases += 1
	var upgrade_id = chosen_choice.definition.upgrade_id
	
	# 2. Route purchase history tracking lists cleanly based on intent targets
	if chosen_choice.target_ability_id != 0:
		var ability = current_player.ability_container.get_ability_by_id(chosen_choice.target_ability_id)
		if is_instance_valid(ability) and is_instance_valid(ability.upgrade_tree):
			ability.upgrade_tree.register_purchase(upgrade_id)
	else:
		var player_tree = current_player.get_node_or_null("UpgradeTreeComponent") as UpgradeTreeComponent
		if is_instance_valid(player_tree):
			player_tree.register_purchase(upgrade_id)
	
	# 3. Hand off raw context values to the player actor execution layer
	current_player.apply_contextual_upgrade(chosen_choice)
	
	# 4. Turn off the active presentation lock flag
	_is_presenting_ui = false
	
	# 5. Check if more level-ups are waiting in line before unpausing the game
	if _level_up_queue.is_empty():
		get_tree().paused = false
	else:
		# Process the next level up on the next frame to allow previous changes to settle
		get_tree().process_frame.connect(_try_process_next_level_up, CONNECT_ONE_SHOT)

## Compiles an unbloated flat array list containing all currently eligible upgrade choices
func generate_selection_pool(target_player: Player) -> Array[UpgradeChoice]:
	var full_pool: Array[UpgradeChoice] = []
	if not is_instance_valid(target_player) or not is_instance_valid(target_player.ability_container):
		return full_pool
		
	var active_abilities = target_player.ability_container.get_active_abilities()
	
	# --- 1. Gather Active Ability Upgrades ---
	for ability in active_abilities:
		if not ability is Ability: 
			continue
			
		# Pure direct memory reference checking—avoids get_node_or_null lookup bloat
		var tree_component = ability.upgrade_tree
		if not is_instance_valid(tree_component): 
			continue
			
		var ability_level: int = ability.current_level if "current_level" in ability else 1
		var eligible_trackers = tree_component.get_eligible_upgrades(ability_level)
		
		for tracker in eligible_trackers:
			var choice = UpgradeChoice.new()
			choice.source_tracker = tracker
			choice.target_ability_id = ability.ability_id
			choice.target_display_name = ability.display_name if "display_name" in ability else "Ability"
			full_pool.append(choice)
			
	# --- 2. Gather Player Global Character Upgrades ---
	var player_tree = target_player.get_node_or_null("UpgradeTreeComponent") as UpgradeTreeComponent
	if is_instance_valid(player_tree):
		var player_level: int = target_player.current_level if "current_level" in target_player else 1
		var eligible_trackers = player_tree.get_eligible_upgrades(player_level)
		
		for tracker in eligible_trackers:
			var choice = UpgradeChoice.new()
			choice.source_tracker = tracker
			choice.target_ability_id = 0 
			choice.target_display_name = "Core Stats"
			full_pool.append(choice)
			
	return full_pool

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
