class_name TornadoMovementStrategy
extends MovementStrategy

@export_group("Vortex Geometry Settings")
## The rotation frequency or spinning speed around the vortex center axis.
@export var swirl_speed: float = 12.0
## How fast the cyclone's radius expands outwards over its lifetime.
@export var expansion_rate: float = 90.0

@export_group("Variance & Randomness Controls")
## Maximum pixel displacement added by chaotic wind gusts.
@export var turbulence_amplitude: float = 60.0
## Frequency multiplier of the random jitter oscillations.
@export var turbulence_frequency: float = 15.0

# Volatile local random seed registers generated on instantiation
var _angle_seed_offset: float = 0.0
var _gust_seed_offset: float = 0.0


func _ready() -> void:
	_angle_seed_offset = randf_range(0.0, TAU)
	_gust_seed_offset = randf_range(-100.0, 100.0)


func calculate_velocity(
	_current_velocity: Vector2,
	target_direction: Vector2,
	max_speed: float,
	_current_global_position: Vector2,
	time_elapsed: float,
	_target_node: Node2D = null
) -> Vector2:
	
	# LAYER 1: THE VORTEX REVOLUTION
	var active_swirl_angle := (time_elapsed * swirl_speed) + _angle_seed_offset
	var orbital_direction := Vector2.from_angle(active_swirl_angle)
	var current_cyclone_radius := time_elapsed * expansion_rate
	var rotational_offset_position := orbital_direction * current_cyclone_radius
	
	# LAYER 2: CHAOTIC TURBULENCE (RANDOM JITTER VARIANCE)
	var noise_factor_x := sin((time_elapsed * turbulence_frequency) + _gust_seed_offset)
	var noise_factor_y := cos((time_elapsed * (turbulence_frequency * 1.35)) - _gust_seed_offset)
	var random_turbulence := Vector2(noise_factor_x, noise_factor_y) * turbulence_amplitude
	
	# LAYER 3: FORWARD DRIVER CONVERSION
	var forward_base_position := target_direction * (max_speed * time_elapsed)
	var desired_target_position := forward_base_position + rotational_offset_position + random_turbulence
	
	# Convert absolute position vectors back to relative velocities safely
	var computed_velocity := desired_target_position / max_speed if time_elapsed > 0.0 else target_direction
	
	return computed_velocity.normalized() * max_speed
