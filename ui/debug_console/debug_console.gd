class_name DebugConsoleUI
extends CanvasLayer

@export_group("UI Layout Bindings")
@export var level_up_button: Button
@export var upgrades_scroll_container: VBoxContainer

# Keep track of whether options have already been built to prevent redundant executions
var _is_ui_populated: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	
	if is_instance_valid(level_up_button):
		level_up_button.pressed.connect(_on_simulate_level_up_pressed)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F1:
			visible = not visible
			print("[DEBUG CONSOLE] Visibility toggled: ", visible)
			
			# Reactively populate options exactly when the console is first opened!
			if visible and not _is_ui_populated:
				populate_simulation_options()


## SIMULATION AREA A: Progression System
func _on_simulate_level_up_pressed() -> void:
	var player = instance_from_id(EventBus.active_player_instance_id) as Player
	if not is_instance_valid(player) or not is_instance_valid(player.progression_component):
		push_warning("DebugConsole: No active player character found to level up.")
		return
		
	player.progression_component.gain_experience(100.0)
	print("[DEBUG SIMULATION] Forced player experience gain transaction.")


## SIMULATION AREA B: Upgrades & Infusion Mounting (Now explicitly controlled)
func populate_simulation_options() -> void:
	# Clear previous visual row elements safely
	for child in upgrades_scroll_container.get_children():
		child.queue_free()
		
	var upgrade_manager = get_tree().root.find_child("UpgradeManager", true, false) as UpgradeManager
	if not is_instance_valid(upgrade_manager):
		push_warning("DebugConsole: UpgradeManager instance missing from world root layout.")
		return
		
	var processed_ids: Array[String] = []
	
	for profile in upgrade_manager.master_upgrade_pool:
		if not is_instance_valid(profile) or profile.definition_bundle.is_empty(): 
			continue
			
		for definition in profile.definition_bundle:
			if not is_instance_valid(definition) or definition.upgrade_id.is_empty():
				continue
				
			if processed_ids.has(definition.upgrade_id):
				continue
				
			processed_ids.append(definition.upgrade_id)
			_create_simulation_row(definition, profile.total_tiers)
			
	# Toggle flag true so we don't rebuild row widgets unless manually cleared or re-called
	_is_ui_populated = true


func _create_simulation_row(definition: UpgradeDefinition, max_tiers: int) -> void:
	print("btn")
	var row_btn = Button.new()
	row_btn.text = "Grant: %s (%s)" % [definition.display_name, UpgradeDefinition.PayloadType.keys()[definition.payload_type]]
	row_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	
	row_btn.pressed.connect(func() -> void:
		_simulate_upgrade_grant(definition, max_tiers)
	)
	
	upgrades_scroll_container.add_child(row_btn)


func _simulate_upgrade_grant(definition: UpgradeDefinition, max_tiers: int) -> void:
	var player = instance_from_id(EventBus.active_player_instance_id) as Player
	if not is_instance_valid(player):
		push_warning("DebugConsole: Cannot grant upgrade. Active player context missing.")
		return
		
	var mock_tracker = UpgradeTracker.new()
	mock_tracker.definition = definition
	mock_tracker.max_purchases = max_tiers
	
	var existing_tier = player.run_ledger_component.purchase_registry.get(definition.upgrade_id, 0)
	mock_tracker.current_purchases = existing_tier
	
	var choice = UpgradeChoice.new()
	choice.source_tracker = mock_tracker
	
	if definition.is_infusion():
		choice.target_slot_index = 1
		choice.target_display_name = "Slot 1 (Debug Direct)"
	else:
		choice.target_slot_index = definition.restrict_to_slot
		choice.target_display_name = "Debug Direct Injection"
		
	print("[DEBUG SIMULATION] Injecting upgrade directly: ", definition.display_name)
	player.apply_contextual_upgrade(choice)
