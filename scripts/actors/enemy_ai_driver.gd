extends Node
class_name EnemyAIDriver

@export var debug_ai_logs: bool = true

var _who: String = ""
var _parry_intent: bool = false

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
var _parry_react_timer: Timer

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

var _parry_scheduled: bool = false

# =============================
# Setup
# =============================
func _ready() -> void:
	assert(profile != null, "EnemyAIDriver: profile não definido")
	assert(controller != null, "EnemyAIDriver: controller não definido")
	_rng.randomize()

	# Identidade para logs
	var p: Node = get_parent()
	if p != null:
		_who = p.name
	else:
		_who = "Enemy"

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
	
	_parry_react_timer = Timer.new()
	_parry_react_timer.process_callback = Timer.TIMER_PROCESS_PHYSICS
	_parry_react_timer.one_shot = true
	add_child(_parry_react_timer)
	_parry_react_timer.timeout.connect(_on_parry_react_timeout)

func _on_parry_react_timeout() -> void:
	# Este timeout é o momento de apertar o parry que foi agendado
	if not _parry_scheduled:
		return
	_parry_scheduled = false

	# Portas de segurança
	if not _enabled:
		return
	if _parried_cd_active or _sequence_running or _lock_inputs_until_idle:
		_dbg("parry-skip: reason=blocked_on_timeout")
		return
	if _self_state == CombatController.State.ATTACK:
		_dbg("parry-skip: reason=self_in_attack_on_timeout")
		return
	if _player_state != CombatController.State.ATTACK:
		_dbg("parry-skip: reason=opponent_not_attacking_on_timeout")
		return

	# Gate opcional do controller no exato momento do timeout
	var allows: bool = true
	if controller.has_method("allows_parry_input_now"):
		allows = controller.allows_parry_input_now()
	if not allows:
		_dbg("parry-skip: reason=controller_gate_false_on_timeout")
		return

	_press_parry_input("react_timeout")

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

	_lock_inputs_until_idle = false
	_sequence_running = false
	_sequence_kind = SeqKind.NONE

	_parried_cd_active = false
	_post_chain_cd_active = false
	_defense_bias_active = false

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
	if not target_controller.state_entered.is_connected(_on_player_state_entered):
		target_controller.state_entered.connect(_on_player_state_entered) # imediato
	if not target_controller.phase_changed.is_connected(_on_player_phase_changed):
		target_controller.phase_changed.connect(_on_player_phase_changed) # imediato

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
# Parry (chance unificada)
# =============================
func _on_player_phase_changed(phase: int, cfg: AttackConfig) -> void:
	_player_phase = phase
	if cfg != null:
		_last_player_recovery = cfg.recovery

	if not _enabled:
		return

	# --- STARTUP: decide se vai tentar parry e agenda a reação cronometrada
	if phase == CombatController.Phase.STARTUP:
		# Só consideramos parry se o player realmente está ATACANDO
		if _player_state != CombatController.State.ATTACK:
			_dbg("parry-skip: reason=opponent_not_attacking state=" + CombatController.State.keys()[_player_state])
			_parry_intent = false
			return

		# Bloqueios/ordem de prioridade
		if _parried_cd_active:
			_dbg("parry-skip: reason=parried_cd_active")
			_parry_intent = false
			return
		if _sequence_running:
			_dbg("parry-skip: reason=sequence_running")
			_parry_intent = false
			return
		if _self_state == CombatController.State.PARRY:
			_dbg("parry-skip: reason=self_in_parry_state")
			_parry_intent = false
			return
		if _self_state == CombatController.State.ATTACK:
			_dbg("parry-skip: reason=self_in_attack")
			_parry_intent = false
			return
		if _lock_inputs_until_idle:
			_dbg("parry-skip: reason=lock_inputs_until_idle")
			_parry_intent = false
			return

		# Chance unificada por pressão
		var idx: int = _pressure_to_index(_pressure_streak)
		var chance: float = 0.0
		if profile != null and profile.parry_chance_by_hit.size() >= 4:
			chance = clamp(profile.parry_chance_by_hit[idx], 0.0, 1.0)
		var roll: float = _rng.randf()

		_dbg("parry-decision: phase_startup pressure=" + str(_pressure_streak)
			+ " idx=" + str(idx)
			+ " chance=" + str(chance) + " roll=" + str(roll)
			+ " self=" + CombatController.State.keys()[_self_state] + "/" + CombatController.Phase.keys()[_self_phase]
			+ " player=" + CombatController.State.keys()[_player_state] + "/" + CombatController.Phase.keys()[_player_phase])

		if roll >= chance:
			_dbg("parry-skip: reason=roll_failed")
			_parry_intent = false
			return

		# Gate opcional do controller
		if controller.has_method("allows_parry_input_now"):
			if not controller.allows_parry_input_now():
				_dbg("parry-skip: reason=controller_gate_false")
				_parry_intent = false
				return

		# Decidimos parryar este hit
		_parry_intent = true
		_schedule_parry_react(cfg, "phase_startup")
		return

	# --- ACTIVE: fallback de segurança (garante 100% quando chance=1.0)
	if phase == CombatController.Phase.ACTIVE:
		# Só se já tínhamos decidido parryar este golpe
		if _parry_intent == false:
			return
		# Se já estamos em PARRY, tudo certo
		if _self_state == CombatController.State.PARRY:
			return
		# Respeita os guard-rails (cooldowns/locks)
		if not _parry_guardrails_unlocked():
			_dbg("parry-skip: reason=guardrails_block_on_active")
			return
		# Cancela qualquer agendamento e aperta agora
		_parry_react_timer.stop()
		_parry_scheduled = false
		_dbg("parry-fallback: phase_active_safety -> pressing now")
		_press_parry_input("phase_active_safety")
		return

func _parry_guardrails_unlocked() -> bool:
	if _parried_cd_active:
		return false
	if _sequence_running:
		return false
	if _lock_inputs_until_idle:
		return false
	if _self_state == CombatController.State.ATTACK:
		return false
	return true

func _current_parry_chance() -> float:
	var idx: int = _pressure_streak
	if idx < 0:
		idx = 0
	if idx > 3:
		idx = 3

	if profile == null:
		return 0.0
	if profile.parry_chance_by_hit.size() < 4:
		return 0.0

	var chance: float = profile.parry_chance_by_hit[idx]
	if chance < 0.0:
		chance = 0.0
	if chance > 1.0:
		chance = 1.0
	return chance

func _pressure_to_index(pressure: int) -> int:
	if pressure <= 1:
		return 0
	if pressure == 2:
		return 1
	if pressure == 3:
		return 2
	return 3

# =============================
# Handlers (SELF)
# =============================
func _cancel_scheduled_parry() -> void:
	_parry_react_timer.stop()
	_parry_scheduled = false

func _on_self_state_entered(state: int, cfg: AttackConfig) -> void:
	var prev_state: int = _self_state
	_self_state = state
	if state == CombatController.State.PARRY:
		_cancel_scheduled_parry()

	# Se acabamos de SAIR de PARRIED, inicia o cooldown pós-parry agora
	if prev_state == CombatController.State.PARRIED and state != CombatController.State.PARRIED:
		if _pending_post_parried_cd:
			_begin_parried_cd()
			_pending_post_parried_cd = false

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
		_pending_post_parried_cd = true
	elif state == CombatController.State.GUARD_HIT:
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
	if state != CombatController.State.ATTACK:
		_cancel_scheduled_parry()
	if state == CombatController.State.PARRIED:
		_pressure_streak = 0
		_try_start_immediate_punish("parry_success") # se você usa

func _try_start_immediate_punish(reason: String) -> void:
	if _enabled == false: return
	if _target_in_range == false: return
	if _lock_inputs_until_idle: return
	if _sequence_running: return
	if _post_chain_cd_active: return
	# Importante: cooldown pós-parryado NÃO bloqueia parry, mas bloqueia ataques;
	# aqui vamos atacar, então respeite o cooldown:
	if _parried_cd_active: return

	# Honrar o "respeita turno" (só barra se o player está atacando e ainda não está em RECOVER)
	if profile != null and profile.respect_opponent_turn:
		var player_is_attacking := _player_state == CombatController.State.ATTACK
		var player_in_recover  := _player_phase == CombatController.Phase.RECOVER
		if player_is_attacking and not player_in_recover:
			return

	if _can_start_sequence_now():
		_start_normal_sequence()

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

func _press_parry_input(reason: String = "unspecified") -> void:
	var allows := true
	if controller.has_method("allows_parry_input_now"):
		allows = controller.allows_parry_input_now()
	_dbg("press_parry_input(reason="+reason+") allows="+str(allows)
		+" self="+CombatController.State.keys()[_self_state]+"/"+CombatController.Phase.keys()[_self_phase]
		+" player="+CombatController.State.keys()[_player_state]+"/"+CombatController.Phase.keys()[_player_phase])
	if not allows:
		return

	if controller.has_method("on_parry_pressed"):
		controller.on_parry_pressed()
		call_deferred("_dbg_after_press_snapshot", reason)
		return
	if controller.has_method("try_parry"):
		controller.try_parry()
		call_deferred("_dbg_after_press_snapshot", reason)
		return
	if controller.has_method("press_parry"):
		controller.press_parry()
		call_deferred("_dbg_after_press_snapshot", reason)
		return

func _dbg_after_press_snapshot(reason: String) -> void:
	print("[AI][check] after-press(", reason, ") self=",
		CombatController.State.keys()[controller.get_state()], "/",
		CombatController.Phase.keys()[controller.phase])

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

func _schedule_parry_react(cfg: AttackConfig, reason: String) -> void:
	# === tempos do golpe do player ===
	var startup: float = 0.0
	var active: float = 0.0
	if cfg != null:
		startup = maxf(cfg.startup, 0.0)
		active  = maxf(cfg.hit, 0.0)

	# === janela do parry do inimigo ===
	var window: float = 0.0
	if controller != null and controller._parry_profile != null:
		window = maxf(controller._parry_profile.window, 0.0)

	# === física ===
	var tps: float = float(Engine.physics_ticks_per_second)
	if tps <= 0.0:
		tps = 60.0
	var dt: float  = 1.0 / tps
	var eps: float = dt * 0.5  # folga p/ ordem de callbacks no mesmo frame

	# === alvos de abertura (head & tail), como limites de segurança ===
	var hit_tail: float = startup + active                        # fim do ACTIVE
	var tail_open: float = maxf(hit_tail + eps - window, 0.0)     # janela termina logo após o tail

	var lead_cfg: float = 0.0
	if profile != null:
		lead_cfg = maxf(profile.parry_lead_time, 0.0)
	var early_guard: float = maxf(lead_cfg, dt * 1.5)             # >= ~1.5 frames antes do STARTUP
	var head_open: float = maxf(startup - early_guard, 0.0)       # evita abrir colado no STARTUP

	# === impacto esperado: posicione a janela aqui ===
	var center_ratio: float = 0.6
	if profile != null:
		center_ratio = clampf(profile.parry_impact_center, 0.0, 1.0)
	var expected_impact: float = startup + active * center_ratio  # 0..1 dentro do ACTIVE

	# janela centrada no impacto esperado (ajustando pelo lead)
	var target_open: float = expected_impact - (window * 0.5) - lead_cfg

	# clamp entre os limites seguros (não muito cedo, nem tarde demais)
	var open_time: float = clampf(target_open, head_open, tail_open)

	# jitter opcional
	var jitter: float = 0.0
	if profile != null and profile.parry_react_jitter > 0.0:
		jitter = _rng.randf_range(-profile.parry_react_jitter, profile.parry_react_jitter)
	open_time = clampf(open_time + jitter, 0.0, maxf(hit_tail, startup))

	# agenda
	_parry_react_timer.stop()
	_parry_scheduled = true
	_parry_react_timer.process_callback = Timer.TIMER_PROCESS_PHYSICS

	_dbg("parry-schedule: delay=" + str(open_time)
		+ " start=" + str(startup)
		+ " active=" + str(active)
		+ " window=" + str(window)
		+ " dt=" + str(dt)
		+ " eps=" + str(eps)
		+ " reason=" + reason)
	_dbg("parry-window: [" + str(open_time) + ", " + str(open_time + window) + "]"
		+ " head_open=" + str(head_open) + " tail_open=" + str(tail_open)
		+ " expected_impact=" + str(expected_impact)
		+ " hit_tail=" + str(hit_tail))

	if open_time <= 0.0:
		_on_parry_react_timeout()
	else:
		_parry_react_timer.start(open_time)

# =============================
# Pressão
# =============================
func _increment_pressure() -> void:
	_pressure_streak += 1

func _dbg(msg: String) -> void:
	if not debug_ai_logs:
		return
	var frame: int = Engine.get_physics_frames()
	var now_ms: int = Time.get_ticks_msec()
	print("[AI][", _who, "] f=", str(frame), " ms=", str(now_ms), " :: ", msg)
