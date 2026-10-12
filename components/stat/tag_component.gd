# res://components/stat/tag_component.gd
class_name TagComponent
extends Node

signal tags_changed(active_tags: Array[Tags.Type])

@export var base_tags: Array[Tags.Type] = []

## The Active Cache Pool: Read out of RAM instantly by external subsystems
var _cached_active_tags: Array[Tags.Type] = []
var _is_dirty: bool = true
var _slot_owner_index: int = 0
var _ledger: RunLedgerComponent = null


func _ready() -> void:
	_cached_active_tags = base_tags.duplicate()


## `ledger` is the owning player's RunLedger (null for ledger-less owners such as enemies).
func configure_slot_context(slot_idx: int, ledger: RunLedgerComponent = null) -> void:
	_slot_owner_index = slot_idx
	if is_instance_valid(_ledger) and _ledger != ledger:
		if _ledger.stats_invalidated.is_connected(_on_stats_invalidated):
			_ledger.stats_invalidated.disconnect(_on_stats_invalidated)
	_ledger = ledger
	if is_instance_valid(_ledger) and not _ledger.stats_invalidated.is_connected(_on_stats_invalidated):
		_ledger.stats_invalidated.connect(_on_stats_invalidated)
	# Slot/ledger changed, so anything compiled earlier is stale.
	_is_dirty = true


## THE LAZY TAXONOMY ENGINE: 
## 99.9% of the time, this returns a pre-compiled array cleanly out of RAM.
## It updates exactly ONCE the next time an engine system or driver queries it.
## The returned array is the live cache: treat it as READ-ONLY. It is safe to hold a
## reference across recompiles because _recompile_tags() always builds a NEW array.
## Callers that intend to mutate the result must duplicate() it themselves.
func get_active_tags() -> Array[Tags.Type]:
	if _is_dirty:
		_recompile_tags()
	return _cached_active_tags


func has_tag(tag_type: Tags.Type) -> bool:
	if _is_dirty:
		_recompile_tags()
	return _cached_active_tags.has(tag_type)


func _recompile_tags() -> void:
	# LAYER 1: Re-seed the baseline designer identity tags from the current weapon blueprint
	_cached_active_tags = base_tags.duplicate()
	
	# LAYER 2: Pull dynamic upgrades from the player's centralized ledger vault
	if is_instance_valid(_ledger):
		var ledger := _ledger
		
		for def in ledger.active_upgrades:
			if def.is_infusion():
				# Procedurally compile the exact key schema representing OUR slot index
				var specialized_key := "%s::slot_%d" % [def.upgrade_id, _slot_owner_index]
				
				# Query the single source of truth: Did the player allocate this element to our lane?
				var tier = ledger.purchase_registry.get(specialized_key, 0)
				
				if tier > 0:
					# Merge the infusion element tags seamlessly into our active taxonomy profile!
					for tag in def.target_tags:
						if not _cached_active_tags.has(tag):
							_cached_active_tags.append(tag)
							
	_is_dirty = false
	tags_changed.emit(_cached_active_tags)


func _on_stats_invalidated(_definition: UpgradeDefinition) -> void:
	# Instant, zero-overhead flag toggle. The physics/math engine continues running uninterrupted.
	_is_dirty = true
