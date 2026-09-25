class_name SceneTransitionManager
extends Node

@export_group("Database Dependencies")
@export var scene_database: SceneDatabase

@export_group("Data-Driven World Configurations")
@export_file("*.tscn") var base_world_scene_path: String = "res://scenes/world/world.tscn"

## Target container bucket where dynamic scenes are mounted
var scene_container: Node = null
var _is_transitioning: bool = false
var _target_scene_path: String = ""
var _loading_progress_array: Array = []

# --- NEW CACHE TRACKER PAYLOAD ---
## Holds onto the active level's data resource while the thread compile runs in the background.
var _active_map_profile_payload: MapProfile = null


func _ready() -> void:
	EventBus.scene_change_requested.connect(transition_to_scene)
	set_process(false)
	
	if is_instance_valid(scene_database):
		scene_database.initialize_database()


func initialize_context(target_container: Node) -> void:
	scene_container = target_container


## Core thread handler entry hook managing contextual target path re-routing
func transition_to_scene(target_scene_id: String) -> void:
	if _is_transitioning or not is_instance_valid(scene_container) or not is_instance_valid(scene_database): 
		return
		
	var profile: SceneProfile = scene_database.get_profile(target_scene_id)
	if not is_instance_valid(profile):
		push_error("SceneTransitionManager: Requested scene_id not found: " + target_scene_id)
		return
		
	# --- CONTEXTUAL ROUTING BRANCH ---
	var next_scene_path: String = ""
	_active_map_profile_payload = null # Reset payload wrapper defaults
	
	if profile.category == SceneProfile.SceneCategory.GAMEPLAY_LEVEL:
		# If it's a level, override the loading path to look at our single structural world frame
		next_scene_path = base_world_scene_path
		_active_map_profile_payload = profile.map_profile
		
		if not is_instance_valid(_active_map_profile_payload):
			push_error("SceneTransitionManager: Gameplay level is missing its MapProfile payload asset.")
			return
	else:
		# Otherwise, route normally to the individual standalone scene file layout
		next_scene_path = profile.scene_file_path
		
	if next_scene_path.is_empty() or not FileAccess.file_exists(next_scene_path):
		push_error("SceneTransitionManager: Target scene file path layout is invalid: " + next_scene_path)
		return
		
	_is_transitioning = true
	_target_scene_path = next_scene_path
	_loading_progress_array = [0.0]
	
	EventBus.scene_transition_started.emit()
	
	if profile.category == SceneProfile.SceneCategory.GAMEPLAY_LEVEL:
		get_tree().paused = true

	# Purge old root node content layout groups instantly from engine viewport tracking pointers
	for child in scene_container.get_children():
		child.queue_free()
		
	await get_tree().process_frame

	var error = ResourceLoader.load_threaded_request(_target_scene_path, "", true)
	if error != OK:
		push_error("SceneTransitionManager: Threaded load request failed with error code: " + str(error))
		_cleanup_failed_transition()
		return
		
	set_process(true)


func _process(_delta: float) -> void:
	var status = ResourceLoader.load_threaded_get_status(_target_scene_path, _loading_progress_array)
	match status:
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			return
		ResourceLoader.THREAD_LOAD_LOADED:
			set_process(false)
			_finalize_scene_swap()
		ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			set_process(false)
			push_error("SceneTransitionManager: Asynchronous thread tracking encountered fatal error status: " + str(status))
			_cleanup_failed_transition()


## Finishes mounting elements and executes the data injection step safely before unpausing loops
func _finalize_scene_swap() -> void:
	var packed_scene = ResourceLoader.load_threaded_get(_target_scene_path) as PackedScene
	if is_instance_valid(packed_scene) and is_instance_valid(scene_container):
		var new_instance = packed_scene.instantiate()
		
		# --- DYNAMIC INJECTION CROSSING PIPELINES ---
		# If we have an active map payload cached, inject it down to the WorldManager right now!
		scene_container.add_child(new_instance)
		if _active_map_profile_payload != null and new_instance is WorldManager:
			new_instance.initialize_world_settings(_active_map_profile_payload)

	get_tree().paused = false
	await get_tree().process_frame

	_target_scene_path = ""
	_active_map_profile_payload = null # Clear reference pointers to ensure clean garbage collection cycles
	_is_transitioning = false
	EventBus.scene_transition_finished.emit()


func _cleanup_failed_transition() -> void:
	get_tree().paused = false
	_target_scene_path = ""
	_active_map_profile_payload = null
	_is_transitioning = false
	EventBus.scene_transition_finished.emit()
