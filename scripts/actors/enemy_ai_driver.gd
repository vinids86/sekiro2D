extends Node
class_name EnemyAIDriver

@export var debug_ai_logs: bool = true
@export_group("Debug Level", "debug_")
@export var debug_level: int = 1  # 0 = None, 1 = Basic, 2 = Verbose

var _who: String = ""
var _parry_intent: bool = false

# =============================
# Wiring
# =============================
@export var profile: EnemyAttackProfile
@export var controller: CombatController
@export var target_controller: CombatController

@export var approach_stamina_min: float = 60.0
@export var retreat_stamina_max: float = 30.0
@export var approach_until_distance: float = 48.0
@export var retreat_until_distance: float = 64.0
@export var dead_zone_distance: float = 8.0
@export var axis_accel: float = 8.0
@export var mode_cooldown: float = 0.35           # histerese temporal (segundos)

enum Mode { APPROACH, HOLD, RETREAT }

var _axis: float = 0.0
var _mode: int = Mode.HOLD
var _mode_timer: float = 0.0

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

# Cache de performance
var _physics_tick_rate: float = 1.0 / 60.0
var _default_parry_chance: float = 0.0

# =============================
# Setup
# =============================
func _ready() -> void:
	if not _validate_dependencies():
		return
		
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

	# Cache de valores para performance
	_physics_tick_rate = 1.0 / float(Engine.physics_ticks_per_second)
	if profile != null and profile.parry_chance_by_hit.size() >= 4:
		_default_parry_chance = profile.parry_chance_by_hit[0]

	if _enabled:
		_think_timer_start()
	else:
		_think_timer_stop()

# =============================
# Validação de dependências
# =============================
func _validate_dependencies() -> bool:
	var valid: bool = true
	
	if profile == null:
		push_error("EnemyAIDriver: profile não definido")
		valid = false
		
	if controller == null:
		push_error("EnemyAIDriver: controller não definido")
		valid = false
		
	if not valid:
		set_process(false)
		set_physics_process(false)
		
	return valid

# =============================
# API pública (Enemy.gd)
# =============================
func set_target_controller(cc: CombatController) -> void:
	if not is_instance_valid(cc):
		_dbg("set_target_controller: controller inválido", 2)
		return
		
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
	if not _parry_guardrails_unlocked():
		_dbg("parry-skip: reason=blocked_on_timeout", 2)
		return
	if _self_state == CombatController.State.ATTACK:
		_dbg("parry-skip: reason=self_in_attack_on_timeout", 2)
		return
	if _player_state != CombatController.State.ATTACK:
		_dbg("parry-skip: reason=opponent_not_attacking_on_timeout", 2)
		return

	# Gate opcional do controller no exato momento do timeout
	var allows: bool = true
	if controller.has_method("allows_parry_input_now"):
		allows = controller.allows_parry_input_now()
	if not allows:
		_dbg("parry-skip: reason=controller_gate_false_on_timeout", 2)
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
		_dbg("target_controller is null, cannot connect signals", 1)
		return
	if not target_controller.state_entered.is_connected(_on_player_state_entered):
		target_controller.state_entered.connect(_on_player_state_entered) # imediato
	if not target_controller.phase_changed.is_connected(_on_player_phase_changed):
		target_controller.phase_changed.connect(_on_player_phase_changed) # imediato

# =============================
# Loop de decisão
# =============================
func _on_think_timeout() -> void:
	if not _enabled:
		return

	# Bloqueios "de turno"
	if _is_input_blocked():
		_think_timer_start()
		return

	# Já em sequência normal? O próximo hit é agendado via RECOVER
	if _sequence_running:
		_think_timer_start()
		return

	# Precisa estar em alcance
	if not _target_in_range:
		_think_timer_start()
		return

	# Respeitar o "turno do oponente"
	if _should_respect_opponent_turn():
		_think_timer_start()
		return

	if _can_start_sequence_now():
		_start_normal_sequence()

	_think_timer_start()

func _is_input_blocked() -> bool:
	return (_lock_inputs_until_idle or 
			_parried_cd_active or 
			_post_chain_cd_active or 
			(_defense_bias_active and not _punish_window_open()))

func _should_respect_opponent_turn() -> bool:
	if profile != null and profile.respect_opponent_turn:
		var player_is_attacking: bool = _player_state == CombatController.State.ATTACK
		var player_in_recover: bool = _player_phase == CombatController.Phase.RECOVER
		return player_is_attacking and not player_in_recover
	return false

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
		return controller.allows_attack_input_now()
	return _self_state == CombatController.State.IDLE

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
	if not _enabled:
		return
	if not _sequence_running:
		return
	if _sequence_kind != SeqKind.NORMAL:
		return
	_press_attack_input() # próximo passo

func _schedule_next_normal_hit(cfg: AttackConfig) -> void:
	# Chamado no RECOVER para agendar o próximo input
	if not _sequence_running or _sequence_kind != SeqKind.NORMAL:
		return
	if profile == null or cfg == null:
		return
	if _awaiting_chain_end:
		return

	var safety: float = maxf(_physics_tick_rate * 2.0, 0.03)
	var max_delay: float = maxf(cfg.recovery - safety, 0.0)
	var delay: float = minf(profile.inter_hit_delay, max_delay)

	_sequence_timer.stop()
	if delay <= 0.0:
		_press_attack_input()
		return

	_sequence_timer.start(delay)

# =============================
# Parry (chance unificada)
# =============================
func _on_player_phase_changed(phase: int, cfg: StateConfig) -> void:
	_player_phase = phase
	var ac: AttackConfig = cfg as AttackConfig
	if ac != null:
		_last_player_recovery = ac.recovery

	if not _enabled:
		return

	# Mantém reações em STARTUP/ACTIVE como antes (sem gates extras)
	if phase == CombatController.Phase.STARTUP:
		_handle_parry_startup_phase(ac)  # passa AttackConfig (pode ser null; a função já valida)
		return

	if phase == CombatController.Phase.ACTIVE:
		_handle_parry_active_phase()
		return

func _handle_parry_startup_phase(cfg: AttackConfig) -> void:
	# Só consideramos parry se o player realmente está ATACANDO
	if _player_state != CombatController.State.ATTACK:
		_dbg("parry-skip: reason=opponent_not_attacking state=" + CombatController.State.keys()[_player_state], 2)
		_parry_intent = false
		return

	# Bloqueios/ordem de prioridade
	if not _can_initiate_parry():
		_parry_intent = false
		return

	# Chance unificada por pressão
	var chance: float = _current_parry_chance()
	var roll: float = _rng.randf()

	_dbg("parry-decision: phase_startup pressure=" + str(_pressure_streak)
		+ " chance=" + str(chance) + " roll=" + str(roll)
		+ " self=" + CombatController.State.keys()[_self_state] + "/" + CombatController.Phase.keys()[_self_phase]
		+ " player=" + CombatController.State.keys()[_player_state] + "/" + CombatController.Phase.keys()[_player_phase], 2)

	if roll >= chance:
		_dbg("parry-skip: reason=roll_failed", 2)
		_parry_intent = false
		return

	# Gate opcional do controller
	if controller.has_method("allows_parry_input_now"):
		if not controller.allows_parry_input_now():
			_dbg("parry-skip: reason=controller_gate_false", 2)
			_parry_intent = false
			return

	# Decidimos parryar este hit
	_parry_intent = true
	_schedule_parry_react(cfg, "phase_startup")

func _handle_parry_active_phase() -> void:
	# Só se já tínhamos decidido parryar este golpe
	if not _parry_intent:
		return
	# Se já estamos em PARRY, tudo certo
	if _self_state == CombatController.State.PARRY:
		return
	# Respeita os guard-rails (cooldowns/locks)
	if not _parry_guardrails_unlocked():
		_dbg("parry-skip: reason=guardrails_block_on_active", 2)
		return
	# Cancela qualquer agendamento e aperta agora
	_parry_react_timer.stop()
	_parry_scheduled = false
	_dbg("parry-fallback: phase_active_safety -> pressing now", 2)
	_press_parry_input("phase_active_safety")

func _can_initiate_parry() -> bool:
	if _parried_cd_active:
		_dbg("parry-skip: reason=parried_cd_active", 2)
		return false
	if _sequence_running:
		_dbg("parry-skip: reason=sequence_running", 2)
		return false
	if _self_state == CombatController.State.PARRY:
		_dbg("parry-skip: reason=self_in_parry_state", 2)
		return false
	if _self_state == CombatController.State.ATTACK:
		_dbg("parry-skip: reason=self_in_attack", 2)
		return false
	if _lock_inputs_until_idle:
		_dbg("parry-skip: reason=lock_inputs_until_idle", 2)
		return false
	return true

func _parry_guardrails_unlocked() -> bool:
	return not (_parried_cd_active or 
				_sequence_running or 
				_lock_inputs_until_idle or 
				_self_state == CombatController.State.ATTACK)

func _current_parry_chance() -> float:
	if profile == null or profile.parry_chance_by_hit.size() < 4:
		return _default_parry_chance

	var idx: int = _pressure_to_index(_pressure_streak)
	var chance: float = profile.parry_chance_by_hit[idx]
	return clampf(chance, 0.0, 1.0)

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

func _on_self_state_entered(state: int, cfg: StateConfig, args: StateArgs) -> void:
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
	if _sequence_running and _sequence_kind == SeqKind.NORMAL:
		var is_attack_state: bool = state == CombatController.State.ATTACK
		var is_idle_state: bool = state == CombatController.State.IDLE
		if not is_attack_state and not is_idle_state:
			_cancel_normal_sequence("state_changed")

	# Pressão + ajustes de "turno"
	_handle_pressure_states(state, prev_state)

	# Liberar lock ao voltar ao IDLE
	if _lock_inputs_until_idle and state == CombatController.State.IDLE:
		if _awaiting_chain_end:
			_awaiting_chain_end = false
			_begin_post_chain_cd()
		_lock_inputs_until_idle = false

	# Morreu: desliga IA
	if state == CombatController.State.DEAD:
		set_enabled(false)

func _handle_pressure_states(state: int, prev_state: int) -> void:
	match state:
		CombatController.State.PARRIED:
			_increment_pressure()
			_pending_post_parried_cd = true
		CombatController.State.GUARD_HIT:
			_increment_pressure()
			_begin_defense_bias()
		CombatController.State.GUARD_BROKEN:
			_increment_pressure()
			_begin_defense_bias()
		CombatController.State.STUNNED:
			_increment_pressure()
			_begin_defense_bias()

func _on_self_phase_changed(phase: int, cfg: StateConfig) -> void:
	_self_phase = phase
	if phase == CombatController.Phase.RECOVER:
		var ac: AttackConfig = cfg as AttackConfig
		_schedule_next_normal_hit(ac)

# =============================
# Handlers (PLAYER)
# =============================
func _on_player_state_entered(state: int, cfg: StateConfig, args: StateArgs) -> void:
	_player_state = state
	if state != CombatController.State.ATTACK:
		_cancel_scheduled_parry()
	if state == CombatController.State.PARRIED:
		_pressure_streak = 0
		_try_start_immediate_punish("parry_success")

func _try_start_immediate_punish(reason: String) -> void:
	if not _enabled or not _target_in_range:
		return
	if _lock_inputs_until_idle or _sequence_running or _post_chain_cd_active or _parried_cd_active:
		return

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

	# --- NOVO: rechecagem de turno antes de enviar input (vale para o 1º hit e para os agendados) ---
	if profile != null and profile.respect_opponent_turn:
		var player_is_attacking: bool = _player_state == CombatController.State.ATTACK
		var player_in_recover: bool = _player_phase == CombatController.Phase.RECOVER
		if player_is_attacking and not player_in_recover:
			# Se estamos no meio de uma sequência, reagenda um retry curto em vez de forçar input agora
			if _sequence_running and _sequence_kind == SeqKind.NORMAL:
				var retry: float = maxf(_physics_tick_rate * 2.0, 0.05)  # ~3 frames
				_sequence_timer.stop()
				_sequence_timer.start(retry)
			return
	# --- FIM DO NOVO GATE ---

	# Contabiliza passo da sequência normal
	if _sequence_kind == SeqKind.NORMAL:
		_normal_step_count += 1
		if profile != null and profile.normal_chain_length_hint > 0:
			if _normal_step_count >= profile.normal_chain_length_hint:
				_sequence_running = false
				_sequence_timer.stop()
				_awaiting_chain_end = true
				_lock_inputs_until_idle = true

	# Tenta diferentes métodos de input
	var input_pressed: bool = false
	if controller.has_method("on_attack_pressed"):
		controller.on_attack_pressed()
		input_pressed = true
	elif controller.has_method("try_attack"):
		controller.try_attack()
		input_pressed = true
	elif controller.has_method("press_attack"):
		controller.press_attack()
		input_pressed = true
		
	if input_pressed:
		_dbg("Attack input pressed (step: " + str(_normal_step_count) + ")", 2)

func _press_parry_input(reason: String = "unspecified") -> void:
	var allows: bool = true
	if controller.has_method("allows_parry_input_now"):
		allows = controller.allows_parry_input_now()
		
	_dbg("press_parry_input(reason="+reason+") allows="+str(allows)
		+" self="+CombatController.State.keys()[_self_state]+"/"+CombatController.Phase.keys()[_self_phase]
		+" player="+CombatController.State.keys()[_player_state]+"/"+CombatController.Phase.keys()[_player_phase], 2)
		
	if not allows:
		return

	# Tenta diferentes métodos de input
	var input_pressed: bool = false
	if controller.has_method("on_parry_pressed"):
		controller.on_parry_pressed()
		input_pressed = true
	elif controller.has_method("try_parry"):
		controller.try_parry()
		input_pressed = true
	elif controller.has_method("press_parry"):
		controller.press_parry()
		input_pressed = true
		
	if input_pressed:
		_dbg("Parry input pressed: " + reason, 2)

# =============================
# Cancelamentos e flags
# =============================
func _cancel_normal_sequence(reason: String) -> void:
	if _sequence_running and _sequence_kind == SeqKind.NORMAL:
		_sequence_timer.stop()
		_sequence_running = false
		_sequence_kind = SeqKind.NONE
		_dbg("Normal sequence canceled: " + reason, 2)

# =============================
# Timers: troca de turno / viés defensivo
# =============================
func _begin_parried_cd() -> void:
	var cd: float = maxf(profile.post_parried_cooldown, 0.0)
	_parried_cd_active = true
	_parried_cd_timer.stop()
	_parried_cd_timer.start(cd)
	_dbg("Parried cooldown started: " + str(cd) + "s", 2)

func _on_parried_cd_timeout() -> void:
	_parried_cd_active = false
	_dbg("Parried cooldown ended", 2)

func _begin_post_chain_cd() -> void:
	var cd: float = maxf(profile.post_sequence_cooldown, 0.0)
	_post_chain_cd_active = true
	_post_chain_cd_timer.stop()
	_post_chain_cd_timer.start(cd)
	_dbg("Post-chain cooldown started: " + str(cd) + "s", 2)

func _on_post_chain_cd_timeout() -> void:
	_post_chain_cd_active = false
	_dbg("Post-chain cooldown ended", 2)

func _begin_defense_bias() -> void:
	var cd: float = maxf(profile.defense_bias_time, 0.0)
	_defense_bias_active = true
	_defense_bias_timer.stop()
	_defense_bias_timer.start(cd)
	_dbg("Defense bias started: " + str(cd) + "s", 2)

func _on_defense_bias_timeout() -> void:
	_defense_bias_active = false
	_dbg("Defense bias ended", 2)

func _schedule_parry_react(cfg: AttackConfig, reason: String) -> void:
	if cfg == null:
		_dbg("Cannot schedule parry: null AttackConfig", 1)
		return

	# === tempos do golpe do player ===
	var startup: float = maxf(cfg.startup, 0.0)
	var active: float = maxf(cfg.hit, 0.0)

	# === janela do parry do inimigo ===
	var window: float = 0.0
	if controller != null and controller._parry_profile != null:
		window = maxf(controller._parry_profile.window, 0.0)

	# === física ===
	var eps: float = _physics_tick_rate * 0.5  # folga p/ ordem de callbacks no mesmo frame

	# === alvos de abertura (head & tail), como limites de segurança ===
	var hit_tail: float = startup + active                        # fim do ACTIVE
	var tail_open: float = maxf(hit_tail + eps - window, 0.0)     # janela termina logo após o tail

	var lead_cfg: float = maxf(profile.parry_lead_time, 0.0) if profile != null else 0.0
	var early_guard: float = maxf(lead_cfg, _physics_tick_rate * 1.5)  # >= ~1.5 frames antes do STARTUP
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
		+ " dt=" + str(_physics_tick_rate)
		+ " eps=" + str(eps)
		+ " reason=" + reason, 2)
	_dbg("parry-window: [" + str(open_time) + ", " + str(open_time + window) + "]"
		+ " head_open=" + str(head_open) + " tail_open=" + str(tail_open)
		+ " expected_impact=" + str(expected_impact)
		+ " hit_tail=" + str(hit_tail), 2)

	if open_time <= 0.0:
		_on_parry_react_timeout()
	else:
		_parry_react_timer.start(open_time)

# =============================
# Movimento (decisão de eixo)
# =============================
func get_move_axis(
	enemy: CharacterBody2D,
	fd: FacingDriver,
	stamina_self: Stamina,
	opponent_stamina: Stamina,
	delta: float
) -> float:
	# Timer de histerese temporal
	if _mode_timer > 0.0:
		_mode_timer -= delta
		if _mode_timer < 0.0:
			_mode_timer = 0.0

	# Sem facing/oponente: relaxa para 0
	if fd == null or fd.opponent == null:
		var t0: float = clampf(axis_accel * delta, 0.0, 1.0)
		_axis = lerp(_axis, 0.0, t0)
		return _axis

	var opp: Node = fd.opponent
	var dx: float = opp.global_position.x - enemy.global_position.x
	var dist: float = absf(dx)

	var dir: float = 0.0
	if dx > 0.0:
		dir = 1.0
	elif dx < 0.0:
		dir = -1.0

	# Staminas atuais (com nulos tratados)
	var self_curr: float = 0.0
	if stamina_self != null:
		self_curr = stamina_self.current

	var has_opp_stamina: bool = opponent_stamina != null
	var opp_curr: float = -1.0
	if has_opp_stamina:
		opp_curr = opponent_stamina.current

	# --- Regras por stamina ---
	var want_approach: bool = self_curr >= approach_stamina_min

	var want_retreat: bool = false
	if self_curr <= retreat_stamina_max:
		if has_opp_stamina and self_curr < opp_curr:
			want_retreat = true

	# --- Gate por alcance: dentro do range, ficar em HOLD, exceto RETREAT ---
	var requested_mode: int = Mode.HOLD
	var immediate_override: bool = false
	if _target_in_range:
		if want_retreat:
			requested_mode = Mode.RETREAT
		else:
			requested_mode = Mode.HOLD
			immediate_override = true  # parar já, sem esperar cooldown de modo
	else:
		if want_retreat:
			requested_mode = Mode.RETREAT
		elif want_approach:
			requested_mode = Mode.APPROACH
		else:
			requested_mode = Mode.HOLD

	# Seleção do modo com/sem override imediato
	if immediate_override:
		if _mode != requested_mode:
			_mode = requested_mode
			_mode_timer = mode_cooldown
	else:
		if requested_mode != _mode and _mode_timer > 0.0:
			requested_mode = _mode
		elif requested_mode != _mode and _mode_timer <= 0.0:
			_mode = requested_mode
			_mode_timer = mode_cooldown

	# Tradução do modo para eixo alvo, com zonas
	var target_axis: float = 0.0
	if _mode == Mode.APPROACH:
		if dist > approach_until_distance:
			target_axis = dir
		elif dist <= dead_zone_distance:
			target_axis = -dir
		else:
			target_axis = 0.0
	elif _mode == Mode.RETREAT:
		if dist < retreat_until_distance:
			target_axis = -dir
		else:
			target_axis = 0.0
	else:
		target_axis = 0.0

	# Suavização do eixo
	var t: float = clampf(axis_accel * delta, 0.0, 1.0)
	_axis = lerp(_axis, target_axis, t)

	# Clamp final
	if _axis > 1.0:
		_axis = 1.0
	elif _axis < -1.0:
		_axis = -1.0

	return _axis

# =============================
# Pressão
# =============================
func _increment_pressure() -> void:
	_pressure_streak += 1
	_dbg("Pressure increased: " + str(_pressure_streak), 2)

func _dbg(msg: String, min_level: int = 1) -> void:
	if not debug_ai_logs or debug_level < min_level:
		return
	var frame: int = Engine.get_physics_frames()
	var now_ms: int = Time.get_ticks_msec()
	print("[AI][", _who, "] f=", str(frame), " ms=", str(now_ms), " :: ", msg)
