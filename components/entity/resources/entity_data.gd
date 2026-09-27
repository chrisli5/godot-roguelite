class_name EntityData
extends Resource

@export_group("Identification & Visuals")
@export var display_name: String = "Generic Entity"
@export var sprite_texture: Texture2D

@export_group("Base Attribute Profile")
## Injects the explicit starting stats tailored for this entity profile (Health, Speed, etc.)
@export var stats_profile: StatsProfile

@export_group("Behavioral Prefabs")
## The specific structural physics component used to steer this entity
@export var movement_strategy_scene: PackedScene
