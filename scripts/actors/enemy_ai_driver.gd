extends Node
class_name EnemyAIDriver

# =============================
# Wiring
# =============================
@export var profile: EnemyAttackProfile
@export var controller: CombatController
@export var target_controller: CombatController

var _target_in_range: bool = false

# =============================
# Timers internos
# =============================
var _think_timer: Timer
var _sequence_timer: Timer
var _parried_cd_timer: Timer
var _post_chain_cd_timer: Timer
var _defense_bias_timer: Timer
var _parried_parry_timer: Timer

# =============================
# RNG
# =============================
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

# =============================
# Estado interno da IA
# =============================
var _enabled: bool = true

enum SeqKind { NONE, NORMAL }
var _sequence_kind: int = SeqKind.NONE
var _sequence_running: bool = false
var _normal_step_count: int = 0
var _awaiting_chain_end: bool = false
var _lock_inputs_until_idle: bool = false

var _parried_cd_active: bool = false
var _post_chain_cd_active: bool = false
var _defense_bias_active: bool = false

# “Parry armado” quando em PARRIED (reage ao próximo STARTUP do player)
var _parried_parry_armed: bool = false
var _parried_parry_used: bool = false

# Sinalizador para iniciar o cooldown pós-parry AO SAIR de PARRIED
var _pending_post_parried_cd: bool = false

# Pressão cresce quando sofre contatos ofensivos
var _pressure_streak: int = 0

# Snapshot do estado/fase do inimigo e do player
var _self_state: int = CombatController.State.IDLE
var _self_phase: int = CombatController.Phase.STARTUP
var _player_state: int = CombatController.State.IDLE
var _player_phase: int = CombatController.Phase.STARTUP
var _last_player_recovery: float = 0.0

# =============================
# Setup
# =============================
func _ready() -> void:
	assert(profile != null, "EnemyAIDriver: profile não definido")
	assert(controller != null, "EnemyAIDriver: controller não definido")
	_rng.randomize()

	_enabled = profile.enabled_default

	_setup_timers()
	_connect_self_signals()
	_connect_player_signals()

	if _enabled:
		_think_timer_start()
	else:
		_think_timer_stop()

# =============================
# API pública (Enemy.gd)
# =============================
func set_target_controller(cc: CombatController) -> void:
	target_controller = cc
	_connect_player_signals()

func set_target_in_range(in_range: bool) -> void:
	_target_in_range = in_range

func set_enabled(value: bool) -> void:
	if _enabled == value:
		return
	_enabled = value
	if _enabled:
		_reset_counters_soft()
		_think_timer_start()
	else:
		_cancel_all_schedules()
		_think_timer_stop()

# =============================
# Timers helpers
# =============================
func _setup_timers() -> void:
	_think_timer = Timer.new()
	_think_timer.one_shot = true
	add_child(_think_timer)
	_think_timer.timeout.connect(_on_think_timeout)

	_sequence_timer = Timer.new()
	_sequence_timer.one_shot = true
	add_child(_sequence_timer)
	_sequence_timer.timeout.connect(_on_sequence_timeout)

	_parried_cd_timer = Timer.new()
	_parried_cd_timer.one_shot = true
	add_child(_parried_cd_timer)
	_parried_cd_timer.timeout.connect(_on_parried_cd_timeout)

	_post_chain_cd_timer = Timer.new()
	_post_chain_cd_timer.one_shot = true
	add_child(_post_chain_cd_timer)
	_post_chain_cd_timer.timeout.connect(_on_post_chain_cd_timeout)

	_defense_bias_timer = Timer.new()
	_defense_bias_timer.one_shot = true
	add_child(_defense_bias_timer)
	_defense_bias_timer.timeout.connect(_on_defense_bias_timeout)

	_parried_parry_timer = Timer.new()
	_parried_parry_timer.one_shot = true
	add_child(_parried_parry_timer)
	_parried_parry_timer.timeout.connect(_on_parried_parry_timeout)

func _think_timer_start() -> void:
	_think_timer.stop()
	var t: float = profile.think_interval
	if t < 0.01:
		t = 0.01
	_think_timer.start(t)

func _think_timer_stop() -> void:
	_think_timer.stop()

func _cancel_all_schedules() -> void:
	_sequence_timer.stop()
	_parried_cd_timer.stop()
	_post_chain_cd_timer.stop()
	_defense_bias_timer.stop()
	_parried_parry_timer.stop()

	_lock_inputs_until_idle = false
	_sequence_running = false
	_sequence_kind = SeqKind.NONE

	_parried_cd_active = false
	_post_chain_cd_active = false
	_defense_bias_active = false

	_parried_parry_armed = false
	_parried_parry_used = false
	_pending_post_parried_cd = false

func _reset_counters_soft() -> void:
	_pressure_streak = 0

# =============================
# Conexões de sinais
# =============================
func _connect_self_signals() -> void:
	if controller.state_entered.is_connected(_on_self_state_entered) == false:
		controller.state_entered.connect(_on_self_state_entered, Object.CONNECT_DEFERRED)
	if controller.phase_changed.is_connected(_on_self_phase_changed) == false:
		controller.phase_changed.connect(_on_self_phase_changed, Object.CONNECT_DEFERRED)

func _connect_player_signals() -> void:
	if target_controller == null:
		return
	if target_controller.state_entered.is_connected(_on_player_state_entered) == false:
		target_controller.state_entered.connect(_on_player_state_entered, Object.CONNECT_DEFERRED)
	if target_controller.phase_changed.is_connected(_on_player_phase_changed) == false:
		target_controller.phase_changed.connect(_on_player_phase_changed, Object.CONNECT_DEFERRED)

# =============================
# Loop de decisão
# =============================
func _on_think_timeout() -> void:
	if _enabled == false:
		return

	# Bloqueios "de turno"
	if _lock_inputs_until_idle:
		_think_timer_start()
		return
	if _parried_cd_active:
		_think_timer_start()
		return
	if _post_chain_cd_active:
		_think_timer_start()
		return
	if _defense_bias_active:
		var can_punish: bool = _punish_window_open()
		if can_punish == false:
			_think_timer_start()
			return

	# Já em sequência normal? O próximo hit é agendado via RECOVER
	if _sequence_running:
		_think_timer_start()
		return

	# Precisa estar em alcance
	if _target_in_range == false:
		_think_timer_start()
		return

	# Respeitar o "turno do oponente": não iniciar ataque se o player já está atacando
	if profile != null and profile.respect_opponent_turn:
		var player_is_attacking: bool = _player_state == CombatController.State.ATTACK
		var player_in_recover: bool = _player_phase == CombatController.Phase.RECOVER
		if player_is_attacking and player_in_recover == false:
			_think_timer_start()
			return

	var can_attack_now: bool = _can_start_sequence_now()
	if can_attack_now:
		_start_normal_sequence()

	_think_timer_start()

func _punish_window_open() -> bool:
	# Heurística: RECOVER do player é "grande" OU acabou de voltar ao IDLE após um RECOVER grande
	if _last_player_recovery >= profile.big_recovery_threshold:
		if _player_phase == CombatController.Phase.RECOVER:
			return true
		if _player_state == CombatController.State.IDLE:
			return true
	return false

func _can_start_sequence_now() -> bool:
	if controller.has_method("allows_attack_input_now"):
		var ok: bool = controller.allows_attack_input_now()
		return ok
	if _self_state == CombatController.State.IDLE:
		return true
	return false

# =============================
# Sequência normal (multi-inputs)
# =============================
func _start_normal_sequence() -> void:
	_sequence_running = true
	_sequence_kind = SeqKind.NORMAL
	_normal_step_count = 0
	_pressure_streak = 0 # retomou iniciativa
	_press_attack_input() # step 1

func _on_sequence_timeout() -> void:
	if _enabled == false:
		return
	if _sequence_running == false:
		return
	if _sequence_kind != SeqKind.NORMAL:
		return
	_press_attack_input() # próximo passo

func _schedule_next_normal_hit(cfg: AttackConfig) -> void:
	# Chamado no RECOVER para agendar o próximo input
	if _sequence_running == false:
		return
	if _sequence_kind != SeqKind.NORMAL:
		return
	if profile == null:
		return
	if cfg == null:
		return
	if _awaiting_chain_end:
		return

	var tps: float = float(Engine.physics_ticks_per_second)
	var safety: float = 0.03
	if tps > 0.0:
		var frame: float = 1.0 / tps
		var two_frames: float = frame * 2.0
		if two_frames > safety:
			safety = two_frames

	var max_delay: float = cfg.recovery - safety
	if max_delay < 0.0:
		max_delay = 0.0

	var delay: float = profile.inter_hit_delay
	if delay > max_delay:
		delay = max_delay

	_sequence_timer.stop()
	if delay <= 0.0:
		_press_attack_input()
		return

	_sequence_timer.start(delay)

# =============================
# Parry (global + em PARRIED)
# =============================
func _on_player_phase_changed(phase: int, cfg: AttackConfig) -> void:
	_player_phase = phase
	if cfg != null:
		_last_player_recovery = cfg.recovery

	# Só reagimos ao STARTUP do player
	if _enabled == false:
		return
	if phase != CombatController.Phase.STARTUP:
		return

	# Bloqueios de turno / prioridades: nesses casos NÃO tentamos parry
	if _parried_cd_active:
		return
	if _sequence_running:
		return
	if _self_state == CombatController.State.ATTACK:
		return
	if _lock_inputs_until_idle:
		return

	# === Cálculo de chance ===
	var chance: float = 0.0
	if _self_state == CombatController.State.PARRIED:
		# Chance específica quando o inimigo está PARRIED
		if profile != null:
			chance = max(0.0, min(1.0, profile.parried_parry_chance))
	else:
		# Chance por pressão (guard/hit contam para _pressure_streak)
		if profile != null and profile.parry_chance_by_hit.size() >= 4:
			var idx: int = _pressure_to_index(_pressure_streak)
			chance = max(0.0, min(1.0, profile.parry_chance_by_hit[idx]))

	# Rola o dado; se não passar, não pressiona
	var roll: float = _rng.randf()
	if roll >= chance:
		return

	# Verificação opcional do controller (se existir gate)
	if controller.has_method("allows_parry_input_now"):
		var ok: bool = controller.allows_parry_input_now()
		if ok == false:
			return

	# Pressiona parry: a partir daqui o sucesso/fracasso é do seu FSM
	_press_parry_input()

func _pressure_to_index(pressure: int) -> int:
	if pressure <= 1:
		return 0
	if pressure == 2:
		return 1
	if pressure == 3:
		return 2
	return 3

func _try_press_parry() -> void:
	if controller.has_method("allows_parry_input_now"):
		var ok: bool = controller.allows_parry_input_now()
		if ok == false:
			return
	_press_parry_input()

# =============================
# Handlers (SELF)
# =============================
func _on_self_state_entered(state: int, cfg: AttackConfig) -> void:
	# Guardar o estado anterior antes de trocar
	var prev_state: int = _self_state
	_self_state = state

	# Se acabamos de SAIR de PARRIED, inicia o cooldown pós-parry agora
	if prev_state == CombatController.State.PARRIED and state != CombatController.State.PARRIED:
		if _pending_post_parried_cd:
			_begin_parried_cd()
			_pending_post_parried_cd = false
		# Limpa qualquer resto de "parry armado"
		_parried_parry_armed = false
		_parried_parry_used = false
		if _parried_parry_timer != null:
			_parried_parry_timer.stop()

	# Regra genérica: se sequência NORMAL está em curso e o estado mudou para algo
	# que não seja ATTACK nem IDLE, considera interrupção e cancela.
	var is_attack_state: bool = state == CombatController.State.ATTACK
	var is_idle_state: bool = state == CombatController.State.IDLE
	if _sequence_running and _sequence_kind == SeqKind.NORMAL:
		if is_attack_state == false and is_idle_state == false:
			_cancel_normal_sequence("state_changed")

	# Pressão + ajustes de "turno"
	if state == CombatController.State.PARRIED:
		_increment_pressure()
		# (Re)arma parry específico para PARRIED conforme chance do Profile.
		# Se a chance for 0.0, permanecerá desarmado (e o hard-gate vai bloquear).
		_arm_parried_parry()
		_parried_parry_used = false
		_pending_post_parried_cd = true
	else:
		# Em qualquer estado que não seja PARRIED, garante flags limpas
		_parried_parry_armed = false
		_parried_parry_used = false
		if _parried_parry_timer != null:
			_parried_parry_timer.stop()

	if state == CombatController.State.GUARD_HIT:
		_increment_pressure()
		_begin_defense_bias()
	elif state == CombatController.State.GUARD_BROKEN:
		_increment_pressure()
		_begin_defense_bias()
	elif state == CombatController.State.STUNNED:
		_increment_pressure()
		_begin_defense_bias()

	# Liberar lock ao voltar ao IDLE
	if _lock_inputs_until_idle and state == CombatController.State.IDLE:
		if _awaiting_chain_end:
			_awaiting_chain_end = false
			_begin_post_chain_cd()
		_lock_inputs_until_idle = false

	# Morreu: desliga IA
	if state == CombatController.State.DEAD:
		set_enabled(false)

func _on_self_phase_changed(phase: int, cfg: AttackConfig) -> void:
	_self_phase = phase
	if phase == CombatController.Phase.RECOVER:
		_schedule_next_normal_hit(cfg)

# =============================
# Handlers (PLAYER)
# =============================
func _on_player_state_entered(state: int, cfg: AttackConfig) -> void:
	_player_state = state
	# Player entrou em PARRIED => IA parryou com sucesso
	if state == CombatController.State.PARRIED:
		_pressure_streak = 0

# =============================
# Utilidades de input
# =============================
func _press_attack_input() -> void:
	if controller == null:
		return

	# Contabiliza passo da sequência normal
	if _sequence_kind == SeqKind.NORMAL:
		_normal_step_count += 1
		if profile != null:
			if profile.normal_chain_length_hint > 0:
				if _normal_step_count >= profile.normal_chain_length_hint:
					_sequence_running = false
					_sequence_timer.stop()
					_awaiting_chain_end = true
					_lock_inputs_until_idle = true

	if controller.has_method("on_attack_pressed"):
		controller.on_attack_pressed()
		return
	if controller.has_method("try_attack"):
		controller.try_attack()
		return
	if controller.has_method("press_attack"):
		controller.press_attack()
		return

func _press_parry_input() -> void:
	# Gate opcional do controller (mantive por segurança)
	if controller.has_method("allows_parry_input_now"):
		var ok: bool = controller.allows_parry_input_now()
		if ok == false:
			return

	if controller.has_method("on_parry_pressed"):
		controller.on_parry_pressed()
		return
	if controller.has_method("try_parry"):
		controller.try_parry()
		return
	if controller.has_method("press_parry"):
		controller.press_parry()
		return

# =============================
# Cancelamentos e flags
# =============================
func _cancel_normal_sequence(reason: String) -> void:
	if _sequence_running and _sequence_kind == SeqKind.NORMAL:
		_sequence_timer.stop()
		_sequence_running = false
		_sequence_kind = SeqKind.NONE

# =============================
# Timers: troca de turno / viés defensivo
# =============================
func _begin_parried_cd() -> void:
	var cd: float = profile.post_parried_cooldown
	if cd < 0.0:
		cd = 0.0
	_parried_cd_active = true
	_parried_cd_timer.stop()
	_parried_cd_timer.start(cd)

func _on_parried_cd_timeout() -> void:
	_parried_cd_active = false

func _begin_post_chain_cd() -> void:
	var cd: float = profile.post_sequence_cooldown
	if cd < 0.0:
		cd = 0.0
	_post_chain_cd_active = true
	_post_chain_cd_timer.stop()
	_post_chain_cd_timer.start(cd)

func _on_post_chain_cd_timeout() -> void:
	_post_chain_cd_active = false

func _begin_defense_bias() -> void:
	var cd: float = profile.defense_bias_time
	if cd < 0.0:
		cd = 0.0
	_defense_bias_active = true
	_defense_bias_timer.stop()
	_defense_bias_timer.start(cd)

func _on_defense_bias_timeout() -> void:
	_defense_bias_active = false

# =============================
# Parry armado em PARRIED
# =============================
# =============================
# Parry armado em PARRIED
# =============================
func _arm_parried_parry() -> void:
	_parried_parry_armed = false
	_parried_parry_used = false
	if profile == null:
		return
	var p: float = profile.parried_parry_chance
	if p <= 0.0:
		return
	if p >= 1.0:
		_parried_parry_armed = true
		return
	var roll: float = _rng.randf()
	if roll < p: # estrito: com p==0.0 nunca arma
		_parried_parry_armed = true

func _on_parried_parry_timeout() -> void:
	# Timer de reação do parry armado em PARRIED
	if _parried_parry_used:
		return
	if _self_state != CombatController.State.PARRIED:
		return
	_try_press_parry()
	_parried_parry_used = true
	_parried_parry_armed = false

# =============================
# Pressão
# =============================
func _increment_pressure() -> void:
	_pressure_streak += 1
