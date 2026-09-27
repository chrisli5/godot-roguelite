class_name EnemyWaveProfile
extends Resource

@export var enemy_data_pool: Array[EnemyData] = []
## Total number of individual enemies to deploy over the duration of this wave.
@export var total_spawn_count: int = 20
## Time delay in seconds between sequential monster spawns.
@export var spawn_interval: float = 1.5
## The absolute time cutoff when this wave naturally yields to the next profile segment.
@export var wave_duration: float = 30.0
