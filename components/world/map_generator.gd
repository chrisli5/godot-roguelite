class_name MapGenerator
extends Node

@export_group("Infrastructure Connections")
@export var transition_manager: SceneTransitionManager

@export_group("Campaign Rule Assets")
## The structural ruleset defining themes and monster profiles for the current act
@export var current_act_config: ActConfiguration

# Live run tracking memory
var _current_run_graph: Dictionary = {} # Stores room link structures {"room_0_0": ["room_1_0", "room_1_1"]}
var _completed_rooms: Array[String] = []
var _active_room_id: String = ""


func _ready() -> void:
	# Wire global communication channels cleanly
	EventBus.new_run_started.connect(_on_new_run_started)
	EventBus.room_completion_confirmed.connect(_on_room_completion_confirmed)
	EventBus.map_node_selected.connect(_on_map_node_selected)


# =============================================================================
# PHASE 1 & 2: INITIALIZE & VISUALIZE
# =============================================================================

func _on_new_run_started(act_config: ActConfiguration) -> void:
	if not is_instance_valid(act_config) or not is_instance_valid(transition_manager):
		push_error("MapGenerator: Run configurations are missing.")
		return
	
	current_act_config = act_config
	_clear_previous_run_data()
	_generate_procedural_run_graph()
	
	# Transition the view layer cleanly to your visual selection map tree scene layout
	transition_manager.transition_to_scene("map_screen_ui")


func _clear_previous_run_data() -> void:
	_current_run_graph.clear()
	_completed_rooms.clear()
	_active_room_id = ""


## Bakes a Slay the Spire style interconnected room array completely in memory
func _generate_procedural_run_graph() -> void:
	var total_floors: int = 15
	var branches_per_floor: int = 3
	
	for floor_idx in range(total_floors):
		for branch_idx in range(branches_per_floor):
			var unique_node_id = "node_f" + str(floor_idx) + "_b" + str(branch_idx)
			
			# 1. Automatically bake dynamic MapProfiles and SceneProfiles in RAM
			var procedural_profile = RuntimeLevelFactory.generate_procedural_level_profile(
				current_act_config, 
				floor_idx, 
				unique_node_id
			)
			
			# 2. Register it directly into our high-speed transition database lookup dictionary
			transition_manager.scene_database.register_procedural_profile(procedural_profile)
			
			# 3. Handle path connecting logic (e.g., node maps link forward to floor_idx + 1)
			_current_run_graph[unique_node_id] = _calculate_forward_connections(floor_idx, branch_idx)


func _calculate_forward_connections(current_floor: int, current_branch: int) -> Array[String]:
	var connections: Array[String] = []
	
	# Rule 1: The final floor before the boss always converges directly into the boss gate
	if current_floor >= 14: 
		return ["boss_node"]
		
	var next_floor: int = current_floor + 1
	var total_branches: int = 3 # Matches the branches_per_floor loop boundaries
	
	# Rule 2: Always guarantee a straight-forward path connection so the player is never trapped
	connections.append("node_f" + str(next_floor) + "_b" + str(current_branch))
	
	# Rule 3: Procedurally roll for a left-diagonal connection branch branch
	if current_branch > 0:
		if randf() < 0.40: # 40% chance to split or merge leftward
			connections.append("node_f" + str(next_floor) + "_b" + str(current_branch - 1))
			
	# Rule 4: Procedurally roll for a right-diagonal connection branch branch
	if current_branch < total_branches - 1:
		if randf() < 0.40: # 40% chance to split or merge rightward
			connections.append("node_f" + str(next_floor) + "_b" + str(current_branch + 1))
			
	# Optional Rule 5: Keep the array sorted numerically to ensure clean UI processing
	connections.sort()
	
	return connections

# =============================================================================
# PHASE 3: DEPLOY COMBAT ARENA
# =============================================================================

## Triggered when a user physically clicks a valid node dot container on the Map UI Screen
func _on_map_node_selected(target_node_id: String) -> void:
	if not _is_node_accessible(target_node_id):
		return
		
	_active_room_id = target_node_id
	print("target_node_id ", target_node_id)
	# Command transition pipeline to re-route to BaseWorld while injecting the mapped payload
	transition_manager.transition_to_scene(target_node_id)


func _is_node_accessible(node_id: String) -> bool:
	if _active_room_id.is_empty():
		# If it's a completely fresh run, they can choose any node sitting on floor index 0
		return node_id.contains("node_f0_")
		
	# Otherwise, verify if the requested key exists inside the active forward connections array
	var allowed_next_steps: Array = _current_run_graph.get(_active_room_id, [])
	return allowed_next_steps.has(node_id)

# =============================================================================
# PHASE 4: ROOM COMPLETION TERMINATION LOOP
# =============================================================================

## Triggered by the WorldManager when the last enemy wave clears out
func _on_room_completion_confirmed() -> void:
	_completed_rooms.append(_active_room_id)
	
	if _active_room_id == "boss_node":
		# Act complete! Route to campaign victory screens or subsequent Acts config loads
		EventBus.campaign_victory_triggered.emit()
		return
		
	# Clear out the active combat nodes, load the Map Screen UI back up to the interface frame
	transition_manager.transition_to_scene("map_screen_ui")
