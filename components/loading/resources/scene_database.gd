class_name SceneDatabase
extends Resource

@export var static_profiles_list: Array[SceneProfile] = []

# Live tracking registry combining disk files and procedural entries
var _runtime_registry: Dictionary = {}


func initialize_database() -> void:
	_runtime_registry.clear()
	# Load static menu layouts (Main Menu, Credits, Options) first
	for profile in static_profiles_list:
		if is_instance_valid(profile) and not profile.scene_id.is_empty():
			_runtime_registry[profile.scene_id] = profile


## Allows your procedural map controllers to push dynamic levels into the stream safely
func register_procedural_profile(procedural_profile: SceneProfile) -> void:
	if is_instance_valid(procedural_profile) and not procedural_profile.scene_id.is_empty():
		_runtime_registry[procedural_profile.scene_id] = procedural_profile


func get_profile(target_scene_id: String) -> SceneProfile:
	return _runtime_registry.get(target_scene_id, null)
