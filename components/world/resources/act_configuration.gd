class_name ActConfiguration
extends Resource

@export var act_name: String = "Act 1: Forgotten Catacombs"

@export_group("Layout Themes")
## Pool of tilemap scenes that fit this act's aesthetic (e.g., room_hallway.tscn, room_arena.tscn)
@export var room_tilemap_pool: Array[String] = []

@export_group("Spawn Parameters")
@export var base_max_enemies: int = 150
## All possible enemies that can spawn in this entire act
@export var regional_enemy_pool: Array[PackedScene] = []
