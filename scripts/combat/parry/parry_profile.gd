extends Resource
class_name ParryProfile

@export var window: float = 0.20     # duração da janela ativa do parry
@export var recover: float = 0.60    # tempo de recover após falha
@export var success: float = 1.00    # lock após parry bem-sucedido
