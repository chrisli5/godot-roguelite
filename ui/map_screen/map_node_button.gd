class_name MapNodeButton
extends TextureButton

## The logical coordinate tracking ID linked to this button (e.g., "node_f3_b1")
var logical_node_id: String = ""


func setup_node_visuals(node_id: String, display_name: String, state_color: Color) -> void:
	logical_node_id = node_id
	modulate = state_color
	tooltip_text = display_name


func _pressed() -> void:
	# Alert the global network highway that a player clicked this specific coordinate
	EventBus.map_node_selected.emit(logical_node_id)
