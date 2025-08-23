extends Node
class_name EnemyAIDriver

@export var profile: EnemyAttackProfile
@export var debug_ai: bool = false

# --------- COMBO CONFIG ---------
@export var combo_enabled: bool = true
@export_range(0.0, 1.0, 0.01) var combo_chance: float = 0.25
@export var combo_cooldown: float = 2.0
@export var special_sequence_primary: Array[AttackConfig]

var _controller: CombatController
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _timer: Timer
var _combo_cd: Timer
var _wired: bool = false

func setup(controller: CombatController, attack_profile: EnemyAttackProfile) -> void:
	_controller = controller
	profile = attack_profile
	_wire()

func _ready() -> void:
	# suporte a configurar via exports no editor
	if _timer == null:
		_timer = Timer.new()
		_timer.one_shot = true
		add_child(_timer)
		_timer.timeout.connect(_on_timeout)

	if _combo_cd == null:
		_combo_cd = Timer.new()
		_combo_cd.one_shot = true
		add_child(_combo_cd)
		# não precisa conectar sinal; usamos apenas is_stopped()

	if _controller != null and profile != null and not _wired:
		_wire()

func _wire() -> void:
	assert(_controller != null, "EnemyAIDriver: CombatController nulo")
	assert(profile != null, "EnemyAIDriver: EnemyAttackProfile nulo")
	_wired = true
	_rng.randomize()
	var first: float = maxf(profile.start_delay, 0.0)
	first = clampf(first, 0.0, 60.0)
	_start_timer(first)
	if debug_ai:
		print("[AI] armed: start_delay=", str(first),
			" period=", str(profile.period), " jitter=±", str(profile.jitter),
			" press_only_in_idle=", str(profile.press_only_in_idle),
			" combo_enabled=", str(combo_enabled),
			" combo_chance=", str(combo_chance),
			" combo_cooldown=", str(combo_cooldown))

func _on_timeout() -> void:
	if not is_instance_valid(_controller):
		return

	var st: int = _controller.get_state()
	var can_press: bool = true
	if profile.press_only_in_idle:
		can_press = (st == CombatController.State.IDLE)

	# Decide combo
	var can_try_combo: bool = combo_enabled
	if can_try_combo:
		if special_sequence_primary == null:
			can_try_combo = false
		elif special_sequence_primary.size() == 0:
			can_try_combo = false
		elif not _combo_cd.is_stopped():
			can_try_combo = false
		# controller só inicia combo em IDLE
		if can_try_combo and st != CombatController.State.IDLE:
			can_try_combo = false
		# Gate: bloqueia se o oponente está em combo ofensivo e NÃO é o último hit
		if can_try_combo and _opponent_combo_blocks_combo_parry():
			if debug_ai:
				print("[AI] combo bloqueado: oponente em combo ofensivo (não é último hit)")
			can_try_combo = false

	var did_action: bool = false

	if can_try_combo:
		var roll: float = _rng.randf()
		if roll < combo_chance:
			_controller.start_combo_with_parry_prep(special_sequence_primary)
			_combo_cd.start(maxf(combo_cooldown, 0.0))
			did_action = true
			if debug_ai:
				print("[AI] combo START | roll=", str(roll), " < ", str(combo_chance))

	if not did_action:
		if can_press:
			_controller.on_attack_pressed()
			did_action = true
			if debug_ai:
				print("[AI] attack pressed | state=", _state_name(st))
		else:
			if debug_ai:
				print("[AI] skipped (state=", _state_name(st), ")")

	var next_delay: float = _next_period()
	_start_timer(next_delay)

func _opponent_combo_offense_active() -> bool:
	# Busca o FacingDriver do inimigo (pai deste nó deve ser o root do Enemy)
	var enemy_root: Node = get_parent()
	assert(enemy_root != null, "EnemyAIDriver: root do Enemy inválido")

	assert(enemy_root.has_node(^"Facing"), "EnemyAIDriver: nó ^\"Facing\" não encontrado no Enemy")
	var facing_node: Node = enemy_root.get_node(^"Facing")
	assert(facing_node != null, "EnemyAIDriver: nó ^\"Facing\" inválido")

	var facing_driver: FacingDriver = facing_node as FacingDriver
	assert(facing_driver != null, "EnemyAIDriver: FacingDriver ausente em ^\"Facing\"")

	var opp: Node2D = facing_driver.opponent
	if opp == null or not is_instance_valid(opp):
		# Sem oponente válido → não bloqueia
		return false

	if not opp.has_node(^"CombatController"):
		return false
	var opp_cc: CombatController = opp.get_node(^"CombatController") as CombatController
	if opp_cc == null:
		return false

	var s: int = opp_cc.get_state()
	var in_offense: bool = (
		s == CombatController.State.COMBO_PARRY
		or s == CombatController.State.COMBO_PREP
		or s == CombatController.State.COMBO_STARTUP
		or s == CombatController.State.COMBO_HIT
	)
	return in_offense

func _opponent_combo_blocks_combo_parry() -> bool:
	var enemy_root: Node = get_parent()
	assert(enemy_root != null, "EnemyAIDriver: root do Enemy inválido")
	assert(enemy_root.has_node(^"Facing"), "EnemyAIDriver: nó ^\"Facing\" não encontrado no Enemy")

	var facing_node: Node = enemy_root.get_node(^"Facing")
	assert(facing_node != null, "EnemyAIDriver: nó ^\"Facing\" inválido")

	var facing_driver: FacingDriver = facing_node as FacingDriver
	assert(facing_driver != null, "EnemyAIDriver: FacingDriver ausente em ^\"Facing\"")

	var opp: Node2D = facing_driver.opponent
	if opp == null or not is_instance_valid(opp):
		return false

	if not opp.has_node(^"CombatController"):
		return false
	var opp_cc: CombatController = opp.get_node(^"CombatController") as CombatController
	if opp_cc == null:
		return false

	var offense: bool = opp_cc.is_combo_offense_active()
	var last_hit: bool = opp_cc.is_combo_last_attack()
	return offense and not last_hit

func _next_period() -> float:
	var base: float = maxf(profile.period, 0.0)
	var jitter: float = maxf(profile.jitter, 0.0)
	var delta: float = 0.0
	if jitter > 0.0:
		delta = _rng.randf_range(-jitter, jitter)
	var v: float = base + delta
	if v < 0.05:
		v = 0.05
	if v > 60.0:
		v = 60.0
	return v

func _start_timer(seconds: float) -> void:
	if seconds <= 0.0:
		seconds = 0.001  # próximo frame
	_timer.start(seconds)

# utilitário de debug
func _state_name(s: int) -> String:
	match s:
		CombatController.State.IDLE: return "IDLE"
		CombatController.State.STARTUP: return "STARTUP"
		CombatController.State.HIT: return "HIT"
		CombatController.State.RECOVER: return "RECOVER"
		CombatController.State.STUN: return "STUN"
		CombatController.State.PARRY_STARTUP: return "PARRY_STARTUP"
		CombatController.State.PARRY_SUCCESS: return "PARRY_SUCCESS"
		CombatController.State.PARRY_RECOVER: return "PARRY_RECOVER"
		CombatController.State.HIT_REACT: return "HIT_REACT"
		CombatController.State.COMBO_PARRY: return "COMBO_PARRY"
		CombatController.State.COMBO_PREP: return "COMBO_PREP"
		CombatController.State.COMBO_STARTUP: return "COMBO_STARTUP"
		CombatController.State.COMBO_HIT: return "COMBO_HIT"
		CombatController.State.COMBO_RECOVER: return "COMBO_RECOVER"
		_: return "UNKNOWN"
