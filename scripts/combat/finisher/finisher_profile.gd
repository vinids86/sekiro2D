# FinisherProfile.gd
extends Resource
class_name FinisherProfile

## Tempo de "travinha" visual ao abrir a janela do finisher
@export var ready_lock: float = 0.15

## O golpe de finisher do ATACANTE
@export var attack: AttackConfig
