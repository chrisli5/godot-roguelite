class_name OrbitMovementStrategy
extends MovementStrategy

@export_group("Orbital Configuration Tuning")
## How fast the shard rotates around the core character tracking position (in radians per second)
@export var rotation_speed: float = 0
## The absolute distance footprint from the character origin path center in pixels
@export var orbit_radius: float = 120.0

# Running tracking register initialized contextually once per split instance
var _initial_angle_offset: float = 0.0
var _is_offset_cached: bool = false


func calculate_velocity(
	current_velocity: Vector2,
	target_direction: Vector2, # Cleanly mapped normalized vector pointing from projectile -> player
	max_speed: float, 
	acceleration: float, 
	friction: float,
	time_elapsed: float # Injected downward by parent projectile wrappers
) -> Vector2:
	
	# --- PHASE 1: LAZY CACHE SPAWN ANGLE ---
	if not _is_offset_cached:
		_is_offset_cached = true
		# Grab the initial shot trajectory heading given by the geometry driver
		var initial_heading := current_velocity.normalized() if current_velocity != Vector2.ZERO else Vector2.RIGHT
		_initial_angle_offset = initial_heading.angle()

	# --- PHASE 2: CALCULATE INDEPENDENT ORBIT TRAJECTORY ---
	# Advance our own clean angle around the player, completely independent of projectile position changes
	var active_angle := _initial_angle_offset + (rotation_speed * time_elapsed)
	
	# The tangent vector dictates the perfect circle path forward for this specific timeframe
	var tangent_orbital_vector := Vector2.from_angle(active_angle + (PI / 2.0))
	var target_velocity := tangent_orbital_vector * max_speed

	# --- PHASE 3: DISTANCE CENTERING STABILIZATION ---
	# If the projectile has a valid vector pointing back to the player,
	# we use it to apply an auto-correction force to keep it locked exactly at orbit_radius
	if target_direction != Vector2.ZERO:
		# Extract your parent projectile's frame speed to safely estimate distance gaps string-free
		var distance_traveled := time_elapsed * max_speed
		
		# If the projectile is still migrating outward, guide it smoothly toward the perimeter track
		if distance_traveled < orbit_radius:
			# Guide it outward along the current tangent angle grid
			var radial_push_vector := Vector2.from_angle(active_angle)
			target_velocity = (tangent_orbital_vector * 0.7 + radial_push_vector * 0.3).normalized() * max_speed
		else:
			# Once on track, use target_direction (pointing to player) to pull or push the shard
			# to prevent it from drifting away if the player moves dynamically
			var correction_strength := clampf((distance_traveled - orbit_radius) / orbit_radius, -0.5, 0.5)
			target_velocity = (tangent_orbital_vector + (target_direction * correction_strength)).normalized() * max_speed

	# --- PHASE 4: PARENT VELOCITY INTERPOLATION ---
	if target_velocity != Vector2.ZERO:
		return current_velocity.lerp(target_velocity, acceleration)
	else:
		return current_velocity.lerp(Vector2.ZERO, friction)
