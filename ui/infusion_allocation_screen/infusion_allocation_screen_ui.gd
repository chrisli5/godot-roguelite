class_name InfusionAllocationUI
extends CanvasLayer

@export_group("Layout Component Containers")
@export var weapon_rows_container: VBoxContainer

@export_group("UI Item Prefabs")
## Drag res://ui/infusion_allocation_screen/weapon_row_ui.tscn into this inspector slot
@export var weapon_row_scene: PackedScene

# Local caching registers mapping the active state of the current draft intercept
var _active_choice: UpgradeChoice = null
var _selected_element: Tags.Type = Tags.Type.NONE


func _ready() -> void:
	# Keep the interface screen hidden from the main viewport loop by default
	visible = false
	EventBus.infusion_allocation_requested.connect(_on_allocation_requested)


## Triggered by persistent controllers when an infusion upgrade card is selected
func _on_allocation_requested(chosen_choice: UpgradeChoice) -> void:
	if not is_instance_valid(chosen_choice) or not is_instance_valid(chosen_choice.definition):
		push_error("InfusionAllocationUI: Received empty or corrupt UpgradeChoice packet data.")
		return
		
	_active_choice = chosen_choice
	_selected_element = Tags.Type.NONE
	
	# Harvest the core element tag on the fly out of the choice taxonomy list array
	for tag in chosen_choice.definition.tags:
		if tag != Tags.Type.INFUSION:
			_selected_element = tag
			break
			
	if _selected_element == Tags.Type.NONE:
		push_error("InfusionAllocationUI: Failed to isolate a valid element tag inside card definition payload.")
		return
		
	# Reveal the pop-up canvas overlay panel layer
	visible = true
	_render_eligible_weapon_rows()


## Clears old visual elements out of the viewport tree layout container
func _clear_weapon_rows_view() -> void:
	if is_instance_valid(weapon_rows_container):
		for child in weapon_rows_container.get_children():
			child.queue_free()


## Dynamically compiles scannable row elements for each active weapon slot (1 to 4)
func _render_eligible_weapon_rows() -> void:
	_clear_weapon_rows_view()
	
	var player = EventBus.active_player
	if not is_instance_valid(player) or not is_instance_valid(player.ability_container):
		push_warning("InfusionAllocationUI: Accessing weapon fields failed. Active player or layout container missing.")
		return
		
	# Symmetrically cycle through hotbar slots 1 to 4 (Fixed bounds layout rules)
	for slot_idx in range(1, 5):
		var weapon: Ability = player.ability_container.get_ability_by_slot(slot_idx)
		if not is_instance_valid(weapon) or not is_instance_valid(weapon.infusion_tracker_component): 
			continue
			
		var is_allowed = true
		print(_selected_element)
		# --- DYNAMIC TYPE-SAFE CONSTRAINT AUDITING ---
		# Poll the streamlined tracker module directly using the selected element enum
		# Sibling reference parsing has been completely decoupled!
		is_allowed = weapon.infusion_tracker_component.is_element_socket_allowed(
			_selected_element,
			int(weapon.evolution_gate_component.current_state) if is_instance_valid(weapon.evolution_gate_component) else 0,
			weapon.evolution_gate_component.is_permanently_overclocked if is_instance_valid(weapon.evolution_gate_component) else false
		)
		print("is_allowed: ", is_allowed)
			
		# --- LAYOUT INSTANTIATION ---
		var row_instance = weapon_row_scene.instantiate()
		weapon_rows_container.add_child(row_instance)
		
		if row_instance is AbilityRowUI:
			# Command the blind UI row to parse type-safe level arrays on the fly
			row_instance.setup_row_display(
				weapon.display_name, 
				weapon.infusion_tracker_component.infusion_levels, 
				is_allowed
			)
			
			if is_allowed:
				# Bind click routines tightly to our deterministic slot indexes using Lambda wrappers
				row_instance.pressed.connect(func() -> void:
					_on_final_allocation_confirmed(_active_choice, slot_idx)
				)


## Triggered when a user successfully selects an eligible weapon row container node button
func _on_final_allocation_confirmed(chosen_choice: UpgradeChoice, target_slot_index: int) -> void:
	# 1. Stamp the choice structure with its concrete destination hotbar slot (1 to 4)
	chosen_choice.target_slot_index = target_slot_index
	
	print("[INFUSION UI] Allocation finalized for slot %d. Broadcasting package back to managers..." % target_slot_index)
	
	# 2. BUBBLE UP: Emit choices back into persistent global bus channels string-free
	EventBus.infusion_allocation_confirmed.emit(chosen_choice)
	
	# 3. Wipe layout memory cache lines, conceal the canvas panel, and resume standard frame execution passes
	_clear_weapon_rows_view()
	_active_choice = null
	_selected_element = Tags.Type.NONE
	visible = false
	get_tree().paused = false
