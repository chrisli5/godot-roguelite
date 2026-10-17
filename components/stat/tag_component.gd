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
## Reference counts for temporary tags (e.g. from status effects), so overlapping sources
## cannot strip each other's tags.
var _temporary_tag_counts: Dictionary[Tags.Type, int] = {}


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


## Replaces the permanent identity tags (layer 1). Infusion and temporary tags are untouched.
func set_base_tags(tags: Array[Tags.Type]) -> void:
	base_tags = tags.duplicate()
	_is_dirty = true


## Grants a tag until every matching remove_temporary_tag() call has been made.
func add_temporary_tag(tag_type: Tags.Type) -> void:
	_temporary_tag_counts[tag_type] = _temporary_tag_counts.get(tag_type, 0) + 1
	_is_dirty = true


## Releases one reference to a temporary tag. The tag disappears when the last reference is released.
func remove_temporary_tag(tag_type: Tags.Type) -> void:
	var remaining: int = _temporary_tag_counts.get(tag_type, 0) - 1
	if remaining > 0:
		_temporary_tag_counts[tag_type] = remaining
	else:
		_temporary_tag_counts.erase(tag_type)
	_is_dirty = true


func _recompile_tags() -> void:
	# LAYER 1: Re-seed the baseline designer identity tags from the current weapon blueprint
	_cached_active_tags = base_tags.duplicate()
	
	# LAYER 2: Pull dynamic upgrades from the player's centralized ledger vault
	if is_instance_valid(_ledger):
		var ledger := _ledger
		
		for def in ledger.active_upgrades:
			if def.is_infusion():
				# Procedurally compile the exact key schema representing OUR slot index
				var specialized_key := PurchaseKey.make(def.upgrade_id, _slot_owner_index)
				
				# Query the single source of truth: Did the player allocate this element to our lane?
				var tier = ledger.purchase_registry.get(specialized_key, 0)
				
				if tier > 0:
					# Merge the infusion element tags seamlessly into our active taxonomy profile!
					for tag in def.target_tags:
						if not _cached_active_tags.has(tag):
							_cached_active_tags.append(tag)
							
	# LAYER 3: Temporary tags (status effects) with at least one live reference
	for temp_tag in _temporary_tag_counts:
		if not _cached_active_tags.has(temp_tag):
			_cached_active_tags.append(temp_tag)

	_is_dirty = false
	tags_changed.emit(_cached_active_tags)


func _on_stats_invalidated(_definition: UpgradeDefinition) -> void:
	# Instant, zero-overhead flag toggle. The physics/math engine continues running uninterrupted.
	_is_dirty = true
