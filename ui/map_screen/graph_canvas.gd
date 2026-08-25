class_name GraphCanvas
extends Control

var _stored_graph: Dictionary = {}
var _stored_positions: Dictionary = {}


func draw_graph_lines(run_graph: Dictionary, pixel_positions: Dictionary) -> void:
	_stored_graph = run_graph
	_stored_positions = pixel_positions
	# Forces Godot to clear its canvas and trigger a fresh _draw() callback pass next frame
	queue_redraw()


func _draw() -> void:
	if _stored_graph.is_empty() or _stored_positions.is_empty():
		return
		
	var line_color = Color(0.0, 0.0, 1.0, 1.0) # Slate line default
	var line_thickness = 3.0
	
	# Loop through every node to draw paths forward to its connected steps
	for parent_id in _stored_graph.keys():
		if not _stored_positions.has(parent_id): continue
		var start_pos: Vector2 = _stored_positions[parent_id]
		
		var connections: Array = _stored_graph[parent_id]
		for child_id in connections:
			if not _stored_positions.has(child_id): continue
			var end_pos: Vector2 = _stored_positions[child_id]
			
			# Low-level native vector render call running straight on your GPU matrix
			draw_line(start_pos, end_pos, line_color, line_thickness, true)
