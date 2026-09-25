class_name DebugSpatialVisualizer
extends Node2D

static var instance: DebugSpatialVisualizer = null

## The running memory buffer queue holding shapes currently waiting to be rendered on canvas
var _draw_queue: Array[Dictionary] = []


func _enter_tree() -> void:
	# Enforce structural singleton references cleanly within the viewport hierarchy
	instance = self


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _process(delta: float) -> void:
	if _draw_queue.is_empty():
		return
		
	var expired_indices: Array[int] = []
	
	# 1. Update running frame lifetime clocks sequentially
	for i in range(_draw_queue.size()):
		_draw_queue[i]["lifetime"] -= delta
		if _draw_queue[i]["lifetime"] <= 0.0:
			expired_indices.append(i)
			
	# 2. Purge staled indicators backward to preserve index order positions
	expired_indices.reverse()
	for idx in expired_indices:
		_draw_queue.remove_at(idx)
		
	# 3. Request an immediate low-level canvas redraw callback step from the engine
	queue_redraw()


## Public Request Hook: Adds a spatial shape query configuration data map straight into the render queue
static func register_debug_draw(shape: Shape2D, new_position: Vector2, color: Color, duration: float) -> void:
	if not OS.is_debug_build() or not is_instance_valid(instance):
		return
		
	var package := {
		"shape": shape.duplicate(), # Duplicate to protect against concurrent modification crashes
		"position": new_position,
		"color": color,
		"lifetime": duration
	}
	instance._draw_queue.append(package)


func _draw() -> void:
	# Cycle through every queued configuration element to draw native vectors directly on your GPU
	for item in _draw_queue:
		var shape: Shape2D = item["shape"]
		var global_pos: Vector2 = item["position"]
		var color: Color = item["color"]
		
		# Translate global world space down to this canvas container's relative space coordinates
		var local_pos := to_local(global_pos)
		
		# --- GEOMETRIC SHAPE EVALUATION MATRIX ---
		if shape is CircleShape2D:
			var radius: float = (shape as CircleShape2D).radius
			# Draw a hollow border ring first, then a translucent fill circle
			draw_circle(local_pos, radius, Color(color, 0.15))
			draw_arc(local_pos, radius, 0.0, TAU, 32, color, 1.5, true)
			
		elif shape is RectangleShape2D:
			var size: Vector2 = (shape as RectangleShape2D).size
			var rect := Rect2(local_pos - (size / 2.0), size)
			draw_rect(rect, Color(color, 0.15), true)
			draw_rect(rect, color, false, 1.5)
		
		elif shape is ConvexPolygonShape2D:
			var points: PackedVector2Array = (shape as ConvexPolygonShape2D).points
			var local_points := PackedVector2Array()
			
			# Project points relative to the query center origin
			for pt in points:
				local_points.append(local_pos + pt)
				
			if local_points.size() > 2:
				draw_polygon(local_points, [Color(color, 0.15)])
				# Close the perimeter path with lines
				for i in range(local_points.size()):
					var next_idx := (i + 1) % local_points.size()
					draw_line(local_points[i], local_points[next_idx], color, 1.5, true)
