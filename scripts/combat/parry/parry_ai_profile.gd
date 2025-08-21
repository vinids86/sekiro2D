extends Resource
class_name ParryAIProfile

@export var base_chance: float = 0.70      # probabilidade de tentar no windup
@export var press_lead: float = 0.10       # quanto ANTES do HIT apertar (s)
@export var reaction_mean: float = 0.00    # atraso extra (s) pra “humanizar”
@export var reaction_jitter: float = 0.02  # variação ± (s)
@export var min_distance: float = 160.0    # só tenta se atacante estiver dentro (px); 0 = ignora
@export var debug_ai: bool = false
