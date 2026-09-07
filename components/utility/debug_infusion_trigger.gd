class_name DebugInfusionTrigger
extends Node

@export var upgrade_manager: UpgradeManager

func _unhandled_input(event: InputEvent) -> void:
	# Trigger the test draft event whenever the player presses the "I" key on their keyboard
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_I:
			if is_instance_valid(upgrade_manager) and upgrade_manager.has_method("trigger_infusion_draft_event"):
				print("[DEBUG TRIGGER] 'I' key pressed. Dispatching standalone elemental infusion draft event...")
				upgrade_manager.trigger_infusion_draft_event()
			else:
				push_warning("[DEBUG TRIGGER] Could not locate an active UpgradeManager node in the scene tree loop.")
