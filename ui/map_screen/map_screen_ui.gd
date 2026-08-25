class_name MapScreenUI
extends CanvasLayer

@export_group("UI Scene Assembly Templates")
@export var node_button_scene: PackedScene

@export_group("Internal Layer Hooks")
@export var nodes_layer: Control
@export var graph_canvas: Control # Reference to the drawing canvas layer

@export_group("Layout Tuning Metrics")
@export var horizontal_spacing: float = 180.0
@export var vertical_spacing: float = 150.0
@export var margin_offset: Vector2 = Vector2(100, 100)


func _ready() -> void:
	# Redraw and repopulate the graph layout fields on load
	_build_visual_graph_tree()


func _build_visual_graph_tree() -> void:
	# Clear out any old residual UI child nodes from previous frame passes
	for child in nodes_layer.get_children():
		child.queue_free()
		
	var map_gen = get_node_or_null("/root/Main/MapGenerator") as MapGenerator
	if not is_instance_valid(map_gen):
		push_error("MapScreenUI: MapGenerator root singleton is inaccessible.")
		return
		
	# Dictionary to cache UI button pixel positions for our line drawer path steps: {"node_f0_b0": Vector2(x,y)}
	var node_positions: Dictionary = {}
	
	# --- Step 1: Draw Nodes and Calculate Spatial Coordinates ---
	for node_id in map_gen._current_run_graph.keys():
		# Parse out floor and branch indices from string keys: "node_f3_b1" -> floor 3, branch 1
		var indices = _extract_indices_from_id(node_id)
		var floor_idx: int = indices[0]
		var branch_idx: int = indices[1]
		
		# Compute standard grid layout positions. Floors stack upward vertically.
		var screen_pos = Vector2(
			margin_offset.x + (branch_idx * horizontal_spacing),
			margin_offset.y + (floor_idx * vertical_spacing)
		)
		
		# Determine state coloring based on accessibility rules
		var node_color = Color.DARK_SLATE_GRAY # Default locked state
		if map_gen._completed_rooms.has(node_id):
			node_color = Color.MEDIUM_AQUAMARINE # Cleared room
		elif map_gen._is_node_accessible(node_id):
			node_color = Color.GOLD # Available right now!
			
		# Instantiate and mount the node button asset into the container frame
		var button_instance = node_button_scene.instantiate() as MapNodeButton
		nodes_layer.add_child(button_instance)
		button_instance.position = screen_pos
		button_instance.setup_node_visuals(node_id, "Room " + str(floor_idx), node_color)
		
		# Cache the central position of this button icon frame for line routing hooks
		node_positions[node_id] = screen_pos + (button_instance.custom_minimum_size / 2.0)
		
	# --- Step 2: Feed Line Anchors into the Drawing Canvas Layer ---
	if graph_canvas and graph_canvas.has_method("draw_graph_lines"):
		graph_canvas.draw_graph_lines(map_gen._current_run_graph, node_positions)


func _extract_indices_from_id(node_id: String) -> Array[int]:
	# Concrete extraction logic safely parsing "node_fX_bY" keys string-free
	var parts = node_id.split("_")
	var floor_num = parts[1].replace("f", "").to_int()
	var branch_num = parts[2].replace("b", "").to_int()
	return [floor_num, branch_num]
