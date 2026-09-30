class_name CombatPayload
extends Resource


@export_group("Static Combat Math")
## Active elemental/lifecycle tags bundled with this specific strike (e.g., FIRE, DOT)
@export var final_damage: float = 0.0
@export var damage_tags: Array[Tags.Type] = []

@export_group("Static Status Integration")
## Status effects that this hit applies to the target on impact
@export var status_effects_to_apply: Array[StatusEffect] = []

@export_group("Dynamic Strategy Core Targets")
## Injected by the spawning Ability: Points to the live Enemy Node2D locked by the hotbar strategy
@export var caster_instance_id: int = 0
@export var stats_container_id: int = 0

@export_group("Trajectory Strategy Overrides")
## Injected by the spawner card: the specific physics component used to steer this projectile
@export var trajectory_movement_scene: PackedScene
@export var base_texture: Texture2D
