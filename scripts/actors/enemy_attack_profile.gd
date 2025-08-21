extends Resource
class_name EnemyAttackProfile

@export var start_delay: float = 0.75   	# tempo até a 1ª tentativa
@export var period: float = 1.00        	# intervalo-alvo entre tentativas
@export var jitter: float = 0.10        	# variação ±jitter por tentativa
@export var press_only_in_idle: bool = true # true = treino limpo (não enfileira)
