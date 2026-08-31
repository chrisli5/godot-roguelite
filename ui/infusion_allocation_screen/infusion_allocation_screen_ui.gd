#=============================================================================
# FILE: res://components/ui/infusion/infusion_allocation_ui.gd
#=============================================================================
class_name InfusionAllocationUI
extends Control

@export_group("Layout Component Containers")
@export var element_buttons_container: HBoxContainer
@export var weapon_rows_container: VBoxContainer

@export_group("UI Item Prefabs")
@export var element_button_scene: PackedScene
@export var weapon_row_scene: PackedScene

var _selected_element: Tags.Type = Tags.Type.NONE
var _rolled_elements: Array[Tags.Type] = []


func _ready() -> void:
	visible = false
	EventBus.infusion_allocation_requested.connect(_on_allocation_requested)


func _on_allocation_requested(element_pool: Array[Tags.Type]) -> void:
	_rolled_elements = element_pool
	_selected_element = Tags.Type.NONE
	visible = true
	
	_render_element_selection_view()
	_clear_weapon_rows_view()


func _render_element_selection_view() -> void:
	for child in element_buttons_container.get_children():
		child.queue_free()
		
	for element in _rolled_elements:
		var btn = element_button_scene.instantiate() as Button
		element_buttons_container.add_child(btn)
		btn.text = Tags.get_tag_name(element)
		btn.pressed.connect(_on_element_button_pressed.bind(element))


func _on_element_button_pressed(chosen_element: Tags.Type) -> void:
	_selected_element = chosen_element
	_render_eligible_weapon_rows()


func _clear_weapon_rows_view() -> void:
	for child in weapon_rows_container.get_children():
		child.queue_free()


func _render_eligible_weapon_rows() -> void:
	_clear_weapon_rows_view()
	
	var player = EventBus.active_player
	if not is_instance_valid(player) or not is_instance_valid(player.ability_container):
		return
		
	var active_weapons = player.ability_container.get_active_abilities()
	
	for weapon in active_weapons:
		if not weapon is Ability or not is_instance_valid(weapon.upgrade_ledger): 
			continue
			
		var ledger = weapon.upgrade_ledger
		var element_key = ledger.get_upgrade_id_from_element(_selected_element)
		var is_allowed = true
		
		if weapon.has_node("InfusionTrackerComponent"):
			var tracker = weapon.get_node("InfusionTrackerComponent") as InfusionTrackerComponent
			var state_gate = int(weapon.evolution_gate.current_state) if is_instance_valid(weapon.evolution_gate) else 0
			var is_oc = weapon.evolution_gate.is_permanently_overclocked if is_instance_valid(weapon.evolution_gate) else false
			
			var dummy_def = UpgradeDefinition.new()
			dummy_def.upgrade_id = element_key
			dummy_def.tags = [_selected_element, Tags.Type.INFUSION]
			
			is_allowed = tracker.is_infusion_card_allowed(dummy_def, state_gate, is_oc, ledger.purchase_levels)
			
		var row = weapon_row_scene.instantiate()
		weapon_rows_container.add_child(row)
		row.setup_row_display(weapon.display_name, ledger.purchase_levels, is_allowed)
		
		if is_allowed:
			row.clicked.connect(_on_final_allocation_confirmed.bind(weapon.ability_id, element_key))


func _on_final_allocation_confirmed(ability_id: int, upgrade_id: String) -> void:
	EventBus.infusion_socket_confirmed.emit(ability_id, _selected_element, upgrade_id)
	visible = false
	get_tree().paused = false
