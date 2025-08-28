extends Resource
class_name ImpactMetrics

@export var absorbed: float = 0.0    # quanto a Stamina do defensor deve consumir
@export var hp_damage: float = 0.0   # quanto o Health do defensor deve sofrer
@export var attack_id: int = 0       # opcional (dedupe/telemetria)
