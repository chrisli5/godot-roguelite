class_name RuntimeLevelFactory
extends RefCounted

static func generate_procedural_level_profile(
	act_config: ActConfiguration, 
	room_index: int, 
	node_id: String
) -> SceneProfile:
	
	if act_config.room_tilemap_pool.is_empty():
		push_error("LevelFactory: Act configuration room pool is empty.")
		return null

	# --- Step 1: Create the MapProfile dynamically in RAM ---
	var dynamic_map = MapProfile.new()
	dynamic_map.level_name = act_config.act_name + " - Room " + str(room_index)
	
	# Randomly pick a tile layout template from the act's predefined assets pool
	var chosen_tile_index = randi() % act_config.room_tilemap_pool.size()
	dynamic_map.tilemap_scene_path = act_config.room_tilemap_pool[chosen_tile_index]
	
	# Scale difficulty math (e.g., allow more simultaneous enemies deep into the run)
	dynamic_map.max_simultaneous_enemies = act_config.base_max_enemies + (room_index * 10)
	
	# Pass the shared monster references along smoothly
	dynamic_map.enemy_spawn_pool = act_config.regional_enemy_pool

	# --- Step 2: Wrap it inside a transient SceneProfile ---
	var dynamic_scene_profile = SceneProfile.new()
	dynamic_scene_profile.scene_id = node_id # Matches your Slay the Spire room coordinate ID
	dynamic_scene_profile.category = SceneProfile.SceneCategory.GAMEPLAY_LEVEL
	dynamic_scene_profile.map_profile = dynamic_map
	
	return dynamic_scene_profile
