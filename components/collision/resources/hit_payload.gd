class_name HitPayload
extends Resource

enum TargetTrackingMode {
	STATIC_VECTOR,
	REALTIME_NODE
}

@export_group("Static Combat Math")
## Raw damage calculation value configured in files
@export var base_damage: float = 0.0
## Active elemental/lifecycle tags bundled with this specific strike (e.g., FIRE, DOT)
@export var damage_tags: Array[Tags.Type] = []

@export_group("Static Status Integration")
## Status effects that this hit applies to the target on impact
@export var status_effects_to_apply: Array[StatusEffect] = []

@export_group("Dynamic Strategy Core Targets")
## Injected by the spawning Ability: Points to the live Enemy Node2D locked by the hotbar strategy
@export var target_tracking_mode: TargetTrackingMode = TargetTrackingMode.STATIC_VECTOR
var tracked_target_node: Node2D = null
var tracked_target_direction: Vector2 = Vector2.RIGHT

@export_group("Trajectory Strategy Overrides")
## Injected by the spawner card: the specific physics component used to steer this projectile
@export var trajectory_movement_scene: PackedScene
@export var base_texture: Texture2D
var caster: Node2D

## The final computed damage after applying critical hits, global card buffs, 
## or character strength multipliers in RAM.
var final_damage: float = 0.0
