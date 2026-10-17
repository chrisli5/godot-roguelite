class_name DebugHub
extends CanvasLayer
## Debug only (debug builds). One panel for every debug tool, toggled with F1, which is the only debug hotkey.
## The panel is built in code; the logic behind each button lives in DebugActions.

const BURN: StatusEffect = preload("res://resources/status_effects/burn.tres")
const CHILL: StatusEffect = preload("res://resources/status_effects/chill.tres")

@export_group("Simulated Source Stats")
@export var debug_dot_damage: float = 5.0
@export var debug_duration_bonus: float = 3.0

var _watcher: DebugStatusWatcher
var _grant_list: VBoxContainer
var _element_picker: OptionButton
var _slot_picker: OptionButton
var _infusion_result: Label


func _ready() -> void:
	if not OS.is_debug_build():
		queue_free()
		return
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	# The watcher keeps logging while the panel is closed.
	_watcher = DebugStatusWatcher.new()
	add_child(_watcher)
	_build_ui()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F1:
		visible = not visible
		if visible:
			_refresh()
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------------------------------------
# Layout
# ---------------------------------------------------------------------------------------------

func _build_ui() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(8, 8)
	panel.custom_minimum_size = Vector2(380, 0)
	add_child(panel)

	var root := VBoxContainer.new()
	panel.add_child(root)

	var hint := Label.new()
	hint.text = "F1 toggles this panel"
	root.add_child(hint)

	var tabs := TabContainer.new()
	root.add_child(tabs)
	tabs.add_child(_build_run_tab())
	tabs.add_child(_build_combat_tab())


func _build_run_tab() -> Control:
	var tab := VBoxContainer.new()
	tab.name = "Run"

	tab.add_child(_make_button("Level up (+100 XP)", _on_level_up_pressed))
	tab.add_child(_make_button("Respawn player (tests run persistence)", _on_respawn_pressed))

	tab.add_child(_make_section_label("Infusion"))
	tab.add_child(_make_button("Draft infusion (real flow)", _on_draft_infusion_pressed))
	var grant_row := HBoxContainer.new()
	_element_picker = OptionButton.new()
	_slot_picker = OptionButton.new()
	grant_row.add_child(_element_picker)
	grant_row.add_child(_slot_picker)
	grant_row.add_child(_make_button("Grant infusion (rule-respecting)", _on_grant_infusion_pressed))
	tab.add_child(grant_row)
	_infusion_result = Label.new()
	_infusion_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_infusion_result.custom_minimum_size = Vector2(360, 0)
	tab.add_child(_infusion_result)

	tab.add_child(_make_section_label("Grant card (bypass rules)"))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(360, 180)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_grant_list = VBoxContainer.new()
	_grant_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_grant_list)
	tab.add_child(scroll)
	return tab


func _build_combat_tab() -> Control:
	var tab := VBoxContainer.new()
	tab.name = "Combat"
	tab.add_child(_make_button("Burn nearest enemy", _on_status_pressed.bind(BURN)))
	tab.add_child(_make_button("Chill nearest enemy", _on_status_pressed.bind(CHILL)))

	var log_box := CheckBox.new()
	log_box.text = "Log enemy status events"
	log_box.button_pressed = DebugStatusWatcher.enabled
	log_box.toggled.connect(func(pressed: bool) -> void: DebugStatusWatcher.enabled = pressed)
	tab.add_child(log_box)

	var shapes_box := CheckBox.new()
	shapes_box.text = "Show spatial query shapes"
	shapes_box.button_pressed = DebugSpatialVisualizer.enabled
	shapes_box.toggled.connect(func(pressed: bool) -> void: DebugSpatialVisualizer.enabled = pressed)
	tab.add_child(shapes_box)
	return tab


func _make_button(text: String, handler: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.pressed.connect(handler)
	return button


func _make_section_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label


# ---------------------------------------------------------------------------------------------
# Refresh (every time the panel is opened)
# ---------------------------------------------------------------------------------------------

func _refresh() -> void:
	_refresh_grant_list()
	_refresh_infusion_pickers()


func _refresh_grant_list() -> void:
	for child in _grant_list.get_children():
		child.queue_free()
	var manager := DebugActions.find_upgrade_manager(get_tree())
	if not is_instance_valid(manager):
		push_warning("DebugHub: UpgradeManager instance missing from world root layout.")
		return
	for entry in DebugActions.grantable_cards(manager):
		var definition: UpgradeDefinition = entry["definition"]
		var total_tiers: int = entry["total_tiers"]
		var label := "Grant: %s (%s)" % [definition.display_name, UpgradeDefinition.PayloadType.keys()[definition.payload_type]]
		_grant_list.add_child(_make_button(label, _on_grant_card_pressed.bind(definition, total_tiers)))


func _refresh_infusion_pickers() -> void:
	var previous_element := _element_picker.selected
	var previous_slot := _slot_picker.selected
	_element_picker.clear()
	_slot_picker.clear()

	var manager := DebugActions.find_upgrade_manager(get_tree())
	for definition in DebugActions.grantable_infusions(manager):
		var element := definition.get_infusion_element()
		_element_picker.add_item(String(Tags.Type.keys()[element]))
		_element_picker.set_item_metadata(_element_picker.item_count - 1, definition)

	var player := DebugActions.find_player()
	for slot in range(AbilityContainer.MIN_SLOT, AbilityContainer.MAX_SLOT + 1):
		var ability_name := "empty"
		if is_instance_valid(player) and is_instance_valid(player.ability_container):
			var ability := player.ability_container.get_ability_by_slot(slot)
			if is_instance_valid(ability):
				ability_name = ability.display_name
		_slot_picker.add_item("Slot %d: %s" % [slot, ability_name])
		_slot_picker.set_item_metadata(_slot_picker.item_count - 1, slot)

	if previous_element >= 0 and previous_element < _element_picker.item_count:
		_element_picker.select(previous_element)
	if previous_slot >= 0 and previous_slot < _slot_picker.item_count:
		_slot_picker.select(previous_slot)


# ---------------------------------------------------------------------------------------------
# Button handlers
# ---------------------------------------------------------------------------------------------

func _on_level_up_pressed() -> void:
	DebugActions.level_up(DebugActions.find_player())


func _on_respawn_pressed() -> void:
	DebugActions.respawn_player(self)


func _on_draft_infusion_pressed() -> void:
	DebugActions.draft_infusion(DebugActions.find_upgrade_manager(get_tree()))


func _on_grant_card_pressed(definition: UpgradeDefinition, total_tiers: int) -> void:
	DebugActions.grant_card(DebugActions.find_player(), definition, total_tiers)


func _on_grant_infusion_pressed() -> void:
	if _element_picker.selected < 0 or _slot_picker.selected < 0:
		_infusion_result.text = "Refused: no infusion card or slot to choose from."
		return
	var definition := _element_picker.get_item_metadata(_element_picker.selected) as UpgradeDefinition
	var slot: int = _slot_picker.get_item_metadata(_slot_picker.selected)
	var element := int(definition.get_infusion_element())
	var reason := DebugActions.grant_infusion(DebugActions.find_player(), DebugActions.find_upgrade_manager(get_tree()), definition, element, slot)
	if reason.is_empty():
		_infusion_result.text = "OK: %s into slot %d" % [Tags.Type.keys()[element], slot]
	else:
		_infusion_result.text = "Refused: %s" % reason
	# Slot labels and the grant list can change with a grant.
	_refresh_infusion_pickers()


func _on_status_pressed(effect: StatusEffect) -> void:
	var enemy := DebugActions.find_nearest_enemy(get_tree())
	if enemy != null:
		_watcher.watch_with_ticks(enemy)
	if not DebugActions.apply_status_to_nearest(get_tree(), effect, debug_dot_damage, debug_duration_bonus):
		push_warning("DebugHub: no enemy to apply a status to.")
