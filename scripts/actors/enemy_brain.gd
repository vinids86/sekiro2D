extends Node
class_name EnemyBrain

# ---------- CONFIG GERAL ----------
@export var enemy_path: NodePath

# Parry
@export var parry_chance: float = 0.6
@export var parry_check_cooldown: float = 0.4
@export var max_check_distance: float = 140.0
@export var require_facing_match: bool = true
@export var heavy_parry_chance_factor: float = 0.5

# Regra: parry só no 2º STARTUP do atacante
@export var second_hit_window: float = 1.2        # janela p/ manter a armação entre 1º e 2º
@export var parry_timing_fudge: float = 0.06      # antecipa em relação ao startup do atacante
@export var parry_default_delay: float = 0.02     # fallback se AttackConfig ainda não estiver pronto

# Pressão após parry leve
@export var pressure_heavy_every: int = 3
@export var action_min_interval: float = 0.05

# HEAVY/FINISHER
@export var heavy_attack: AttackConfig
@export var finisher_attack: AttackConfig
@export var finisher_max_distance: float = 120.0
@export var finisher_require_facing: bool = true
@export var finisher_retry_cooldown: float = 0.25

# ---------- ESTADOS PRIVADOS ----------
var _enemy: Enemy
var _player: Node
var _ec: CombatController

var _parry_cd: float = 0.0
var _act_cd: float = 0.0
var _finisher_cd: float = 0.0

var _tried_this_startup: bool = false
var _last_player_state: CombatTypes.CombatState = CombatTypes.CombatState.IDLE

var _pressuring: bool = false
var _pressure_count: int = 0

# Armação para "2º golpe"
var _second_primed: bool = false
var _second_prime_timer: float = 0.0

func _ready() -> void:
	_enemy = get_node(enemy_path) as Enemy
	if _enemy == null:
		return

	_ec = _enemy.get_combat_controller()
	if _ec != null and not _ec.state_changed.is_connected(_on_enemy_state_changed):
		_ec.state_changed.connect(_on_enemy_state_changed)

	if heavy_attack == null:
		heavy_attack = AttackConfig.heavy_preset()
	if finisher_attack == null:
		finisher_attack = AttackConfig.finisher_preset()

func set_player(p: Node) -> void:
	_player = p

func _process(delta: float) -> void:
	if _parry_cd > 0.0:
		_parry_cd -= delta
	if _act_cd > 0.0:
		_act_cd -= delta
	if _finisher_cd > 0.0:
		_finisher_cd -= delta

	# expira a armação do 2º golpe
	if _second_primed:
		_second_prime_timer -= delta
		if _second_prime_timer <= 0.0:
			_second_primed = false
			_second_prime_timer = 0.0

	if _enemy == null or _player == null or _ec == null:
		return

	var pc: CombatController = _player.get_combat_controller()
	if pc == null:
		return

	# 1) FINISHER tem prioridade
	if _try_finisher_if_possible(pc):
		return

	# 2) Parry reativo (com regra do 2º)
	_try_parry_tick(pc)

# ---------- CALLBACK DO CONTROLLER DO INIMIGO ----------
func _on_enemy_state_changed(new_state: int, _dir: Vector2) -> void:
	if new_state == CombatTypes.CombatState.PARRY_SUCCESS:
		_pressuring = not _ec.parry.last_was_heavy
		if _pressuring:
			_pressure_count = 0
		# limpa armação após um parry bem-sucedido
		_second_primed = false
		_second_prime_timer = 0.0
	elif new_state == CombatTypes.CombatState.STUNNED:
		# NÃO limpamos a armação; parry pode ocorrer em STUNNED conforme seu design
		_pressuring = false
		_pressure_count = 0

	if new_state == CombatTypes.CombatState.IDLE and _pressuring:
		if _act_cd <= 0.0 and _ec.can_act():
			call_deferred("_do_pressure_attack")

# ---------- FINISHER ----------
func _try_finisher_if_possible(pc: CombatController) -> bool:
	if _finisher_cd > 0.0:
		return false
	if not pc.is_guard_broken():
		return false
	if not _ec.can_act():
		return false
	if finisher_attack == null:
		return false

	var enemy_pos: Vector2 = (_enemy as Node2D).global_position
	var player_pos: Vector2 = (_player as Node2D).global_position

	if enemy_pos.distance_to(player_pos) > finisher_max_distance:
		return false

	if finisher_require_facing:
		var dx: float = player_pos.x - enemy_pos.x
		var enemy_facing_right: bool = (_enemy.last_direction == "right")
		if enemy_facing_right and dx < 0.0:
			return false
		if not enemy_facing_right and dx > 0.0:
			return false

	var dir: Vector2 = (player_pos - enemy_pos).normalized()
	var started: bool = _ec.try_attack_heavy(finisher_attack, dir, false)
	if started:
		_finisher_cd = finisher_retry_cooldown
		_act_cd = action_min_interval
		if _ec.debug_logs:
			print("EnemyBrain: FINISHER iniciado")
	return started

# ---------- PARRY (somente no 2º STARTUP) ----------
func _try_parry_tick(pc: CombatController) -> void:
	if _parry_cd > 0.0:
		return

	# detectar transição p/ STARTUP do ATACANTE
	if pc.combat_state == CombatTypes.CombatState.STARTUP:
		if pc.combat_state != _last_player_state:
			_tried_this_startup = false
		_last_player_state = pc.combat_state
	else:
		_last_player_state = pc.combat_state
		return

	if _tried_this_startup:
		return

	# alcance + facing
	var enemy_pos: Vector2 = (_enemy as Node2D).global_position
	var player_pos: Vector2 = (_player as Node2D).global_position
	if enemy_pos.distance_to(player_pos) > max_check_distance:
		return
	if require_facing_match:
		var enemy_on_right: bool = (enemy_pos.x - player_pos.x) > 0.0
		var player_attacking_right: bool = (pc.current_attack_direction.x >= 0.0)
		if enemy_on_right != player_attacking_right:
			return

	# AttackConfig pode não estar pronto no frame do STARTUP
	var p_attack: AttackConfig = pc.get_current_attack() as AttackConfig
	var delay: float = parry_default_delay
	var window: float = second_hit_window
	if p_attack != null:
		var d: float = p_attack.startup - parry_timing_fudge
		if d < 0.0:
			d = 0.0
		delay = d
		var w: float = p_attack.total_time() + 0.10
		if w > window:
			window = w

	_tried_this_startup = true

	# 1º STARTUP válido → apenas arma (sem cooldown)
	if not _second_primed:
		_second_primed = true
		_second_prime_timer = window
		if _ec.debug_logs:
			print("[EnemyBrain] Armado para parry no próximo STARTUP (2º)")
		return

	# 2º STARTUP → agenda parry (100% no 2º) e aplica cooldown agora
	_second_primed = false
	_second_prime_timer = 0.0
	_parry_cd = parry_check_cooldown
	if _ec.debug_logs:
		print("[EnemyBrain] Parry AGENDADO (2º). delay=" + str(delay))
	call_deferred("_try_parry_with_delay", delay, 1.0)

func _try_parry_with_delay(delay: float, chance: float) -> void:
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout

	if _enemy == null or _player == null or _ec == null:
		return
	var pc: CombatController = _player.get_combat_controller()
	if pc == null:
		return

	# player ainda em STARTUP/ATTACKING?
	if pc.combat_state != CombatTypes.CombatState.STARTUP and pc.combat_state != CombatTypes.CombatState.ATTACKING:
		return

	# alcance + facing revalidados
	var enemy_pos: Vector2 = (_enemy as Node2D).global_position
	var player_pos: Vector2 = (_player as Node2D).global_position
	if enemy_pos.distance_to(player_pos) > max_check_distance:
		return
	if require_facing_match:
		var enemy_on_right: bool = (enemy_pos.x - player_pos.x) > 0.0
		var player_attacking_right: bool = (pc.current_attack_direction.x >= 0.0)
		if enemy_on_right != player_attacking_right:
			return

	var do_parry: bool = false
	if chance >= 1.0:
		do_parry = true
	else:
		if randf() < chance:
			do_parry = true

	if do_parry:
		var dir: Vector2 = (player_pos - enemy_pos).normalized()
		_ec.try_parry(true, dir)

# ---------- PRESSÃO (leve/leve/HEAVY) ----------
func _do_pressure_attack() -> void:
	if not _pressuring or not _ec.can_act():
		return
	if _player == null:
		return

	var enemy_pos: Vector2 = (_enemy as Node2D).global_position
	var player_pos: Vector2 = (_player as Node2D).global_position
	var dir: Vector2 = (player_pos - enemy_pos).normalized()
	var did_start: bool = false
	var want_heavy: bool = (heavy_attack != null and _pressure_count >= pressure_heavy_every - 1)
	if want_heavy:
		did_start = _ec.try_attack_heavy(heavy_attack, dir, false)
		if did_start:
			_pressure_count = 0
	else:
		var next: AttackConfig = _ec.get_current_attack() as AttackConfig
		if next != null:
			did_start = _ec.try_attack(false, dir)
			if did_start:
				_pressure_count = min(_pressure_count + 1, pressure_heavy_every - 1)

	if not did_start:
		_pressuring = false
		_pressure_count = 0
	else:
		_act_cd = action_min_interval

func bind_controller(ec: CombatController) -> void:
	_ec = ec
	if _ec != null and not _ec.state_changed.is_connected(_on_enemy_state_changed):
		_ec.state_changed.connect(_on_enemy_state_changed)
