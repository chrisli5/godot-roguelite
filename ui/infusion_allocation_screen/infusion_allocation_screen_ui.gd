class_name InfusionAllocationUI
extends CanvasLayer

@export_group("Layout Component Containers")
@export var weapon_rows_container: VBoxContainer

@export_group("UI Item Prefabs")
@export var weapon_row_scene: PackedScene

# Local caching registers mapping the active state of the current draft intercept
var _active_choice: UpgradeChoice = null
var _selected_element: Tags.Type = Tags.Type.NONE


func _ready() -> void:
	visible = false
	EventBus.infusion_allocation_requested.connect(_on_allocation_requested)
	_connect_to_ledger_signals()


func _connect_to_ledger_signals() -> void:
	var current_player = instance_from_id(EventBus.active_player_instance_id) as Player
	if is_instance_valid(current_player) and is_instance_valid(current_player.run_ledger):
		current_player.run_ledger.ui_inventory_changed.connect(_on_ui_inventory_changed)


## Triggered by drafting components when an elemental infusion upgrade card is selected
func _on_allocation_requested(chosen_choice: UpgradeChoice) -> void:
	if not is_instance_valid(chosen_choice) or not is_instance_valid(chosen_choice.definition):
		push_error("InfusionAllocationUI: Received empty or corrupt UpgradeChoice packet data.")
		return
		
	_active_choice = chosen_choice
	_selected_element = chosen_choice.infusion_element
	
	if _selected_element == Tags.Type.NONE:
		push_error("InfusionAllocationUI: Failed to isolate a valid element tag inside card definition payload.")
		return
		
	visible = true
	_render_eligible_weapon_rows()


## Clears old visual row frame instances instantly from the viewport tree container
func _clear_weapon_rows_view() -> void:
	if is_instance_valid(weapon_rows_container):
		for child in weapon_rows_container.get_children():
			child.queue_free()


## Dynamically compiles scannable row elements for each active weapon slot
func _render_eligible_weapon_rows() -> void:
	_clear_weapon_rows_view()
	
	var player = instance_from_id(EventBus.active_player_instance_id) as Player
	if not is_instance_valid(player) or not is_instance_valid(player.ability_container):
		push_warning("InfusionAllocationUI: Accessing weapon fields failed. Active player or layout container missing.")
		return
		
	# Symmetrically cycle through hotbar lanes 1 to 4
	for slot_idx in range(1, 5):
		var weapon: Ability = player.ability_container.get_ability_by_slot(slot_idx)
		if not is_instance_valid(weapon) or not is_instance_valid(weapon.infusion_tracker_component): 
			continue
			
		# Poll the streamlined tracker module directly using the selected element enum
		var is_allowed = weapon.infusion_tracker_component.is_element_socket_allowed(
			_selected_element,
			int(weapon.evolution_gate_component.current_state) if is_instance_valid(weapon.evolution_gate_component) else 0,
			weapon.evolution_gate_component.is_permanently_overclocked if is_instance_valid(weapon.evolution_gate_component) else false
		)
			
		# Instantiate layout row instances into the container frame layout
		var row_instance = weapon_row_scene.instantiate()
		weapon_rows_container.add_child(row_instance)
		
		if row_instance is AbilityRowUI:
			row_instance.setup_row_display(
				weapon.display_name, 
				weapon.infusion_tracker_component.infusion_levels, 
				is_allowed
			)
			
			if is_allowed:
				# Bind click routines tightly to our deterministic slot indices via Lambdas
				row_instance.pressed.connect(func() -> void:
					_on_final_allocation_confirmed(_active_choice, slot_idx)
				)


## Triggered when a user successfully selects an eligible weapon row container node button
func _on_final_allocation_confirmed(chosen_choice: UpgradeChoice, target_slot_index: int) -> void:
	chosen_choice.target_slot_index = target_slot_index
	
	print("[INFUSION UI] Allocation finalized for slot %d. Broadcasting package back to managers..." % target_slot_index)
	
	# Bubble up: Emit choices back into global persistent event channels string-free
	EventBus.infusion_allocation_confirmed.emit(chosen_choice)
	
	_clear_weapon_rows_view()
	_active_choice = null
	_selected_element = Tags.Type.NONE
	visible = false
	get_tree().paused = false


## INTERCEPT LINK: Triggered by the player's centralized RunLedger when a purchase concludes
func _on_ui_inventory_changed() -> void:
	# Only spend performance overhead to re-render lines if the pop-up panel is physically open
	if visible and _active_choice != null:
		print("[INFUSION UI RE-RENDER] Centralized inventory changed signal received. Updating view panels...")
		_render_eligible_weapon_rows()
