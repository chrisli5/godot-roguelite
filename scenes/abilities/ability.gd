class_name Ability
extends Node

enum ExecutionType { MANUAL, AUTOMATIC }

@export var execution_mode: ExecutionType = ExecutionType.MANUAL
@export var base_cooldown: float = 1.0

@export var stats_container: StatsContainer
@export var tag_component: TagComponent

@onready var cooldown_timer: Timer = $CooldownTimer


func _ready() -> void:
	cooldown_timer.wait_time = base_cooldown
	cooldown_timer.timeout.connect(_on_cooldown_timeout)
	
	if execution_mode == ExecutionType.AUTOMATIC:
		cooldown_timer.start()

# The universal pipeline entry point
func try_execute() -> void:
	if not cooldown_timer.is_stopped():
		return # Ability is on cooldown
		
	_execute_ability_behavior()
	
	# Recalculate cooldown dynamically using your StatsContainer (Frost Infusion)
	var reduced_cooldown = stats_container.get_stat_value(Stat.Type.COOLDOWN)
	cooldown_timer.start(reduced_cooldown)

func _execute_ability_behavior() -> void:
	# Virtual method overridden by specific ability instances
	# e.g., Spawning projectiles or hitboxes
	pass

func _on_cooldown_timeout() -> void:
	if execution_mode == ExecutionType.AUTOMATIC:
		try_execute() # Auto-loop triggers instantly when off cooldown
