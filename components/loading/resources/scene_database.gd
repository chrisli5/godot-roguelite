class_name SceneDatabase
extends Resource

@export var scenes: Array[SceneProfile] = []

## Cached dictionary lookup mapping keys to profiles for O(1) performance
var _lookup_cache: Dictionary = {}

func initialize_database() -> void:
	_lookup_cache.clear()
	for profile in scenes:
		if is_instance_valid(profile) and not profile.scene_id.is_empty():
			_lookup_cache[profile.scene_id] = profile


func get_profile(scene_id: String) -> SceneProfile:
	if _lookup_cache.is_empty():
		initialize_database()
	return _lookup_cache.get(scene_id, null)
