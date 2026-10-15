class_name RunState
extends Resource

## Everything about the player that must outlive a single room. Room scenes are freed on
## every transition, so this lives outside the scene tree (see RunSession).
## Plain data only: it can be written to disk later with ResourceSaver for save/load.

@export var has_player_snapshot: bool = false

@export_group("Ledger")
@export var purchase_registry: Dictionary[String, int] = {}
@export var active_upgrades: Array[UpgradeDefinition] = []

@export_group("Progression")
@export var level: int = 1
@export var current_xp: float = 0.0
@export var total_accumulated_xp: float = 0.0

@export_group("Vitals")
@export var current_health: float = 0.0

@export_group("Pending Drafts")
## Level-up draft levels not yet resolved (the one on screen first, then the queue).
## Written through by UpgradeManager, because the manager is freed with the room.
@export var pending_draft_levels: Array[int] = []

@export_group("Loadout")
## Hotbar slot -> the AbilityData currently mounted there (the evolved data after an evolution).
@export var loadout: Dictionary[int, AbilityData] = {}
## Hotbar slot -> runtime-only ability state (see Ability.export_runtime_state).
@export var ability_states: Dictionary[int, Dictionary] = {}
