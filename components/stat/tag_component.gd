class_name TagComponent
extends Node

signal tags_changed(active_tags: Array[Tags.Type])

@export var base_tags: Array[Tags.Type] = []

var _active_tags: Array[Tags.Type] = []


func _ready() -> void:
	_active_tags = base_tags.duplicate()


func add_tag(new_tag: Tags.Type) -> void:
	if not _active_tags.has(new_tag):
		_active_tags.append(new_tag)
		tags_changed.emit(_active_tags)


func remove_tag(target_tag: Tags.Type) -> void:
	if _active_tags.has(target_tag):
		_active_tags.erase(target_tag)
		tags_changed.emit(_active_tags)


func has_tag(tag_type: Tags.Type) -> bool:
	return _active_tags.has(tag_type)


func has_any_tags(tags_to_check: Array[Tags.Type]) -> bool:
	for tag in tags_to_check:
		if _active_tags.has(tag):
			return true
	return false


func has_all_tags(tags_to_check: Array[Tags.Type]) -> bool:
	for tag in tags_to_check:
		if not _active_tags.has(tag):
			return false
	return true


func get_active_tags() -> Array[Tags.Type]:
	return _active_tags.duplicate() # Return duplicate to prevent external data mutation
