extends Node
class_name FxDriver

# Liga/desliga VFX de “linhas de velocidade” durante ATTACK/ACTIVE.
# Não altera lógica de combate, apenas reage aos sinais do CombatController.

@export var controller: CombatController
@export var speed_lines: GPUParticles2D
@export var emission_offset: float = 18.0   # deslocamento do emissor "para trás" do personagem conforme facing
@export var debug_logs: bool = true

var _facing: int = 1

func _ready() -> void:
	assert(controller != null, "FxDriver.controller não atribuído")
	assert(speed_lines != null, "FxDriver.speed_lines (GPUParticles2D) não atribuído")

	speed_lines.emitting = false
	_apply_facing()

	controller.state_entered.connect(_on_state_entered)
	controller.state_exited.connect(_on_state_exited)
	controller.phase_changed.connect(_on_phase_changed)

	_update_emission() # ajusta estado inicial

func set_facing(facing: int) -> void:
	var f: int = 1
	if facing < 0:
		f = -1
	if f != _facing:
		_facing = f
		_apply_facing()
		if debug_logs:
			print("[FxDriver] facing set to ", str(_facing))

func _apply_facing() -> void:
	if speed_lines == null:
		return

	# Espelha o emissor no eixo X para inverter a direção das linhas.
	# Direção base do material deve ser para a ESQUERDA (-X). Com escala -1, vai para a direita.
	if _facing >= 0:
		speed_lines.scale = Vector2(1.0, 1.0)
	else:
		speed_lines.scale = Vector2(-1.0, 1.0)

	# Posiciona o emissor "atrás" do personagem
	var px: float = -emission_offset
	if _facing < 0:
		px = emission_offset
	speed_lines.position = Vector2(px, speed_lines.position.y)

func _on_state_entered(state: int, _cfg: AttackConfig) -> void:
	if debug_logs:
		var sname: String = CombatController.State.keys()[state]
		print("[FxDriver] state_entered: ", sname)
	_update_emission()

func _on_state_exited(state: int, _cfg: AttackConfig) -> void:
	if debug_logs:
		var sname: String = CombatController.State.keys()[state]
		print("[FxDriver] state_exited: ", sname)
	_disable_all()

func _on_phase_changed(phase: int, _cfg: AttackConfig) -> void:
	if debug_logs:
		var pname: String = CombatController.Phase.keys()[phase]
		print("[FxDriver] phase_changed: ", pname)
	_update_emission()

func _update_emission() -> void:
	if controller == null or speed_lines == null:
		return

	var is_attack: bool = controller.get_state() == CombatController.State.ATTACK
	var is_active: bool = controller.phase == CombatController.Phase.ACTIVE
	var should_emit: bool = false

	if is_attack and is_active:
		should_emit = true

	if should_emit and not speed_lines.emitting:
		speed_lines.emitting = true
		if debug_logs:
			print("[FxDriver] ATTACK+ACTIVE -> emit ON")
	elif (not should_emit) and speed_lines.emitting:
		speed_lines.emitting = false
		if debug_logs:
			print("[FxDriver] emit OFF")

func _disable_all() -> void:
	if speed_lines != null and speed_lines.emitting:
		speed_lines.emitting = false
