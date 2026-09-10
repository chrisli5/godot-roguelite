class_name ArcaneMissileOverclock
extends ArcaneMissile

func _ready() -> void:
	super()
	
	# 2. Inject structural Overclock Core state parameters safely into the live instance
	if is_instance_valid(evolution_gate_component):
		evolution_gate_component.is_permanently_overclocked = true
		
	print("[OVERCLOCK VARIANT] %s initialized with inherited base routines and open Level 15 ceilings." % display_name)
