extends Area2D
class_name AttackHitbox

@onready var shape: CollisionShape2D = $CollisionShape2D

# --- wiring ---
var _cc: CombatController = null
var _attacker: Node2D = null
var _wired: bool = false

# --- cfg atual / overrides ---
var _cfg: AttackConfig = null
var _effective_cfg: AttackConfig = null
var _runtime_damage_mul: float = 1.0

# --- posição base local (para aplicar offset por golpe) ---
var _base_local_pos: Vector2 = Vector2.ZERO

func _ready() -> void:
	# Estado inicial desligado
	monitoring = false
	if shape != null:
		shape.disabled = true
	visible = false
	_base_local_pos = position

func _exit_tree() -> void:
	# Desconecta com segurança (assinaturas novas)
	if _cc != null:
		if _cc.phase_changed.is_connected(_on_phase_changed):
			_cc.phase_changed.disconnect(_on_phase_changed)
		if _cc.state_exited.is_connected(_on_state_exited):
			_cc.state_exited.disconnect(_on_state_exited)

# -----------------------------------------------------------------------------
# Setup: conecta direto no CombatController
# -----------------------------------------------------------------------------
func setup(controller: CombatController, attacker: Node2D) -> void:
	_cc = controller
	_attacker = attacker

	assert(_cc != null, "AttackHitbox.setup: CombatController nulo")
	assert(_attacker != null, "AttackHitbox.setup: attacker nulo")
	assert(shape != null, "AttackHitbox.setup: CollisionShape2D ausente")

	if _wired:
		return
	_wired = true

	# Assinaturas novas:
	# - phase_changed(phase: int, cfg: StateConfig)
	# - state_exited(state: int, cfg: StateConfig, args: StateArgs)
	_cc.phase_changed.connect(_on_phase_changed)
	_cc.state_exited.connect(_on_state_exited)

# -----------------------------------------------------------------------------
# Liga/Desliga
# -----------------------------------------------------------------------------
func enable(cfg: AttackConfig, attacker: Node2D) -> void:
	assert(cfg != null, "AttackHitbox.enable: cfg nulo")
	assert(attacker != null, "AttackHitbox.enable: attacker nulo")

	_cfg = cfg
	_attacker = attacker

	# Aplica offset local do golpe (o flip é herdado do pai Facing)
	position = _base_local_pos + cfg.hitbox_offset

	# Prepara cfg efetivo se houver modificador de dano
	if _runtime_damage_mul != 1.0:
		_effective_cfg = cfg.duplicate(true)
		_effective_cfg.damage = maxf(0.0, cfg.damage * _runtime_damage_mul)
	else:
		_effective_cfg = null

	monitoring = true
	if shape != null:
		shape.disabled = false
	visible = true

func disable() -> void:
	monitoring = false
	if shape != null:
		shape.disabled = true
	visible = false

	# Reset de posição local para a base (remove o offset do último golpe)
	position = _base_local_pos

	_cfg = null
	_effective_cfg = null
	# mantém _attacker (opcional), mas pode limpar se preferir:
	# _attacker = null

	# reseta modificadores runtime para a próxima ativação
	_runtime_damage_mul = 1.0

# -----------------------------------------------------------------------------
# Callbacks da FSM (assinaturas novas)
# -----------------------------------------------------------------------------
func _on_phase_changed(phase: int, cfg: StateConfig) -> void:
	if _cc == null:
		return

	var st: int = _cc.get_state()

	# Liga/desliga apenas durante ATTACK
	if st == CombatController.State.ATTACK:
		if phase == CombatController.Phase.ACTIVE:
			# Proteção: só liga se vier AttackConfig válido
			var ac: AttackConfig = cfg as AttackConfig
			if ac == null:
				push_warning("[AttackHitbox] ACTIVE com cfg que não é AttackConfig (ignorado).")
				return
			enable(ac, _attacker)
		elif phase == CombatController.Phase.RECOVER:
			disable()
	elif st == CombatController.State.STUNNED:
		# Qualquer interrupção dura deve desligar
		disable()

func _on_state_exited(state: int, _cfg_sc: StateConfig, _args: StateArgs) -> void:
	# Garantia: ao sair de ATTACK, desliga imediatamente
	if state == CombatController.State.ATTACK:
		disable()

# -----------------------------------------------------------------------------
# Utilidades / acesso
# -----------------------------------------------------------------------------
func set_runtime_damage_multiplier(m: float) -> void:
	if m < 0.0:
		m = 0.0
	_runtime_damage_mul = m

func get_runtime_damage_multiplier() -> float:
	return _runtime_damage_mul

func get_current_config() -> AttackConfig:
	if _effective_cfg != null:
		return _effective_cfg
	return _cfg

func get_attacker() -> Node2D:
	return _attacker
