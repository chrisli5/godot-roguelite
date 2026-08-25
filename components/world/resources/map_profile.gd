class_name MapProfile
extends Resource

@export var level_name: String = "Forgotten Catacombs"
@export var tilemap_scene_path: String = ""

@export_group("Spawn Settings")
@export var max_simultaneous_enemies: int = 200
@export var enemy_spawn_pool: Array[PackedScene] = []
