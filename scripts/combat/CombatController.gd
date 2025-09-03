extends Node
class_name CombatController

signal state_entered(state: int, cfg: AttackConfig)
signal state_exited(state: int, cfg: AttackConfig)
signal phase_changed(phase: int, cfg: AttackConfig)

enum State {
	IDLE,
	ATTACK,
	PARRY,
	PARRIED,
	DODGE,
	STUNNED,
	GUARD_HIT,
	GUARD_BROKEN,
	DEAD,
}

enum Phase { STARTUP, ACTIVE, SUCCESS, RECOVER }

enum AttackKind { LIGHT, HEAVY, COUNTER, FINISHER, COMBO }

# =========================
# CONSTANTES / CAMPOS
# =========================

var _state: int = State.IDLE
var phase: Phase = -1
var current_kind: AttackKind = AttackKind.LIGHT
var combo_index: int = 0
var current_cfg: AttackConfig

var attack_set: AttackSet
var _combo_seq: Array[AttackConfig] = []
var _combo_hit: int = -1

var _parry_profile: ParryProfile
var _hitreact: HitReactProfile
var _parried: ParriedProfile
var _guard: GuardProfile
var _counter: CounterProfile
var _dodge: DodgeProfile

var _last_dodge_dir: int = 0

var _phase_timer: Timer

# ===== Buffer de 1 slot (primeiro da janela vence) =====
var _buf_has: bool = false
var _buf_kind: AttackKind = AttackKind.LIGHT
var _buf_heavy_cfg: AttackConfig
var _buf_combo_seq: Array[AttackConfig] = []

var _timer_owner_state: int = -1
var _timer_owner_phase: int = -1

func initialize(
		attack_set: AttackSet,
		parry_profile: ParryProfile,
		hit_react_profile: HitReactProfile,
		parried_profile: ParriedProfile,
		guard_profile: GuardProfile,
		counter_profile: CounterProfile,
		dodge_profile: DodgeProfile
	) -> void:
	self.attack_set = attack_set
	_parry_profile = parry_profile
	_hitreact = hit_react_profile
	_parried = parried_profile
	_guard = guard_profile
	_counter = counter_profile
	_dodge = dodge_profile
	_state = State.IDLE
	phase = -1
	combo_index = 0
	current_cfg = null
	_buffer_clear()

func _ready() -> void:
	CombatStateRegistry.bind_states(State)

	_phase_timer = Timer.new()
	_phase_timer.one_shot = true
	add_child(_phase_timer)
	_phase_timer.timeout.connect(_on_phase_timer_timeout)

func update(_dt: float) -> void:
	pass

# =========================
# INPUTS
# =========================

func on_attack_pressed() -> void:
	# LIGHT
	if _state == State.IDLE:
		var first: AttackConfig = _get_attack_from_set(0)
		_start_attack(AttackKind.LIGHT, first)
		return

	if _is_attack_buffer_window_open() and not _buf_has:
		_buffer_capture_light()
		return
	# Fora de janela: ignora (sem queue fora da janela)

func on_heavy_attack_pressed(cfg: AttackConfig) -> void:
	var st: StateBase = CombatStateRegistry.get_state_for(_state)
	if st.allows_heavy_start(self):
		_start_attack(AttackKind.HEAVY, cfg)
		return

	print("[FSM] try buff heavy")
	if _is_attack_buffer_window_open() and not _buf_has:
		print("[FSM] buff heavy successfully")
		_buffer_capture_heavy(cfg)
		return

func on_combo_pressed(seq: Array[AttackConfig]) -> void:
	# COMBO
	# Start imediato se permitido agora (ex.: em IDLE)
	if allows_attack_input_now():
		_start_combo_from_seq(seq)
		return

	# Senão, tenta capturar no buffer se a janela estiver aberta (v1: StateAttack de COMBO deve retornar false)
	if _is_attack_buffer_window_open() and not _buf_has:
		_buffer_capture_combo(seq)
		return
	# Fora de janela: ignora

func on_parry_pressed() -> void:
	print("[FSM] on_parry_pressed")
	if not allows_parry_input_now():
		print("[FSM] on_parry_pressed not allowed")
		return

	_buffer_clear()
	_change_state(State.PARRY, null)
	_change_phase(Phase.ACTIVE, null)

	_safe_start_timer(_parry_profile.window)

	var owner_state_name: String = State.keys()[_timer_owner_state]
	var owner_phase_name: String = Phase.keys()[_timer_owner_phase]

func on_dodge_pressed(dir: int) -> void:
	if not allows_dodge_input_now():
		return
	_last_dodge_dir = dir

	_buffer_clear()
	_change_state(State.DODGE, null)
	_change_phase(Phase.STARTUP, null)
	_safe_start_timer(_dodge.startup)

# =========================
# TIMER TICK
# =========================
func _on_phase_timer_timeout() -> void:
	# Blindagem: ignora timeouts atrasados de outro estado/fase
	if _state != _timer_owner_state or phase != _timer_owner_phase:
		return

	if _state == State.ATTACK:
		_tick_attack()
		return
	if _state == State.PARRY:
		_tick_parry()
		return
	if _state == State.DODGE:
		_tick_dodge()
		return
	if _state == State.STUNNED:
		_tick_stunned()
		return
	if _state == State.GUARD_HIT:
		_tick_guard_hit()
		return
	if _state == State.PARRIED:
		_tick_parried()
		return
	if _state == State.GUARD_BROKEN:
		_tick_guard_broken()
		return
	# DEAD/IDLE/etc.: sem ação do timer

# =========================
# TICKS por Estado
# =========================

func _tick_attack() -> void:
	if current_cfg == null:
		_exit_to_idle()
		return

	if phase == Phase.STARTUP:
		_change_phase(Phase.ACTIVE, current_cfg)
		var hit_time: float = _phase_duration_from_cfg(current_cfg, Phase.ACTIVE)
		_safe_start_timer(hit_time)
		return

	if phase == Phase.ACTIVE:
		_change_phase(Phase.RECOVER, current_cfg)
		_safe_start_timer(current_cfg.recovery)
		return

	if phase == Phase.RECOVER:
		# COMBO ininterruptível (AttackKind.COMBO)
		if current_kind == AttackKind.COMBO:
			var next_idx_combo: int = _combo_hit + 1
			if next_idx_combo < _combo_seq.size():
				_combo_hit = next_idx_combo
				current_cfg = _combo_seq[_combo_hit]
				_change_phase(Phase.STARTUP, current_cfg)
				_safe_start_timer(current_cfg.startup)
				return
			_exit_to_idle()
			return

		# Consumo do buffer no primeiro instante possível dentro de ATTACK (encadeamento)
		if _buffer_consume_in_attack_recover():
			return

		# Sem buffer: cair para IDLE
		_exit_to_idle()
		return

func _tick_parry() -> void:
	# Sem STARTUP: entramos direto em ACTIVE
	if phase == Phase.ACTIVE:
		_change_phase(Phase.RECOVER, null)
		_safe_start_timer(_parry_profile.recover)
		return

	if phase == Phase.SUCCESS:
		_exit_to_idle()
		return

	if phase == Phase.RECOVER:
		_exit_to_idle()
		return

func _tick_dodge() -> void:
	if phase == Phase.STARTUP:
		_change_phase(Phase.ACTIVE, null)
		_safe_start_timer(_dodge.active)
		return

	if phase == Phase.ACTIVE:
		_change_phase(Phase.RECOVER, null)
		_safe_start_timer(_dodge.recover)
		return

	if phase == Phase.RECOVER:
		_exit_to_idle()
		return

func _tick_stunned() -> void:
	_exit_to_idle()

func _tick_guard_hit() -> void:
	_exit_to_idle()

func _tick_parried() -> void:
	_exit_to_idle()

func _tick_guard_broken() -> void:
	_exit_to_idle()

# =========================
# Consultas
# =========================

func is_stunned() -> bool:
	return _state == State.STUNNED

func is_parry_window() -> bool:
	var active: bool = (_state == State.PARRY and phase == Phase.ACTIVE)
	return active

func is_dodge_active() -> bool:
	return _state == State.DODGE and phase == Phase.ACTIVE

func get_last_dodge_dir() -> int:
	return _last_dodge_dir

func is_autoblock_enabled_now() -> bool:
	var st: StateBase = CombatStateRegistry.get_state_for(_state)
	return st.autoblock_enabled(self)

func allows_attack_input_now() -> bool:
	var st: StateBase = CombatStateRegistry.get_state_for(_state)
	return st.allows_attack_input(self)

func allows_parry_input_now() -> bool:
	var st: StateBase = CombatStateRegistry.get_state_for(_state)
	return st.allows_parry_input(self)

func allows_dodge_input_now() -> bool:
	var st: StateBase = CombatStateRegistry.get_state_for(_state)
	return st.allows_dodge_input(self)

func is_interruptible_now() -> bool:
	var st: StateBase = CombatStateRegistry.get_state_for(_state)
	return st.is_interruptible(self)

# ======= Entradas de reação (armam timer) =======

func enter_parry_success() -> void:
	if _state != State.PARRY:
		return
	_stop_phase_timer()
	_change_phase(Phase.SUCCESS, null)
	_safe_start_timer(_parry_profile.success)

func enter_guard_hit() -> void:
	_buffer_clear()
	_change_state(State.GUARD_HIT, null)
	_change_phase(Phase.STARTUP, null)
	_safe_start_timer(_guard.block_recover)

func enter_guard_broken() -> void:
	_buffer_clear()
	_change_state(State.GUARD_BROKEN, null)
	_change_phase(Phase.STARTUP, null)
	_safe_start_timer(_guard.broken_lock)

func enter_hit_react() -> void:
	_buffer_clear()
	_change_state(State.STUNNED, null)
	_change_phase(Phase.STARTUP, null)
	_safe_start_timer(_hitreact.stun)

func enter_broken_after_finisher() -> void:
	enter_guard_broken()

func start_finisher() -> void:
	if _guard != null and _guard.finisher != null:
		_start_attack(AttackKind.FINISHER, _guard.finisher)

# =========================
# HELPERS
# =========================
func _phase_duration_from_cfg(cfg: AttackConfig, p: Phase) -> float:
	var dur: float = 0.0
	match p:
		Phase.STARTUP:
			dur = cfg.startup
		Phase.ACTIVE:
			dur = cfg.hit
		Phase.RECOVER:
			dur = cfg.recovery
		_:
			dur = 0.0
	if dur < 0.0:
		dur = 0.0
	return dur

func _schedule_phase_timeout(seconds: float) -> void:
	_timer_owner_state = _state
	_timer_owner_phase = phase

	if seconds <= 0.0:
		_on_phase_timer_timeout()
		return

	_phase_timer.stop()
	_phase_timer.start(seconds)

func _safe_start_timer(duration: float) -> void:
	if _phase_timer == null:
		return
	_phase_timer.stop()
	var d: float = maxf(duration, 0.0)

	# Registra dono do timer (estado/fase vigentes no momento do armamento)
	_timer_owner_state = _state
	_timer_owner_phase = phase

	_phase_timer.wait_time = d
	_phase_timer.start()

func _stop_phase_timer() -> void:
	if _phase_timer != null:
		_phase_timer.stop()

func _get_attack_from_set(index: int) -> AttackConfig:
	if attack_set == null:
		return null
	return attack_set.get_attack(index)

func _start_attack(kind: AttackKind, cfg: AttackConfig) -> void:
	if cfg == null:
		return
	current_kind = kind
	current_cfg = cfg

	if attack_set != null:
		var idx: int = attack_set.attacks.find(cfg)
		if idx >= 0:
			combo_index = idx
		else:
			combo_index = 0
	else:
		combo_index = 0

	_change_state(State.ATTACK, current_cfg)
	_change_phase(Phase.STARTUP, current_cfg)
	_safe_start_timer(current_cfg.startup)

func _start_combo_from_seq(seq: Array[AttackConfig]) -> void:
	current_kind = AttackKind.COMBO
	_combo_seq.clear()
	_combo_hit = -1

	if seq != null:
		for ac: AttackConfig in seq:
			if ac != null:
				_combo_seq.append(ac)

	if _combo_seq.size() <= 0:
		return

	_combo_hit = 0
	current_cfg = _combo_seq[_combo_hit]
	combo_index = 0

	_change_state(State.ATTACK, current_cfg)
	_change_phase(Phase.STARTUP, current_cfg)
	_safe_start_timer(current_cfg.startup)

func _exit_to_idle() -> void:
	_stop_phase_timer()

	var last: AttackConfig = current_cfg
	_change_state(State.IDLE, last)
	# Fase default pós-idle (marcador interno)
	phase = Phase.STARTUP

	current_cfg = null
	combo_index = 0

	_combo_seq.clear()
	_combo_hit = -1

	# Consumo tardio (fallback): se ainda há slot, iniciar agora em IDLE
	if _buf_has:
		_buffer_consume_in_idle()

func _change_state(new_state: int, cfg: AttackConfig) -> void:
	var same: bool = new_state == _state
	var reentry_allowed: bool = CombatStateRegistry.get_state_for(_state).allows_reentry(self)

	if (same and reentry_allowed) or (not same):
		_stop_phase_timer()

		var prev: int = _state

		var parent_node: Node = get_parent()
		var actor: String = "unknown"
		if parent_node != null:
			if parent_node.is_in_group("player"):
				actor = "player"
			elif parent_node.is_in_group("enemy"):
				actor = "enemy"
			else:
				actor = parent_node.name

		var prev_name: String = State.keys()[prev]
		var new_name: String = State.keys()[new_state]

		emit_signal("state_exited", prev, cfg)
		_state = new_state
		emit_signal("state_entered", _state, cfg)

		if prev == State.ATTACK and new_state != State.ATTACK:
			_combo_seq.clear()
			_combo_hit = -1

func _change_phase(new_phase: Phase, cfg: AttackConfig) -> void:
	var prev: Phase = phase
	var prev_name: String = Phase.keys()[prev]
	var new_name: String = Phase.keys()[new_phase]

	phase = new_phase
	emit_signal("phase_changed", phase, cfg)

func get_state() -> int:
	return _state

func is_combo_offense_active() -> bool:
	return _state == State.ATTACK and (phase == Phase.STARTUP or phase == Phase.ACTIVE)

func is_combo_last_attack() -> bool:
	if attack_set == null:
		return true
	return attack_set.next_index(combo_index) < 0

# --- CAPACIDADES DEFENSIVAS CONSULTADAS PELO MEDIADOR ---

func is_guard_broken_active() -> bool:
	return get_state() == State.GUARD_BROKEN

func get_guard_absorb_cap() -> float:
	assert(_guard != null, "CombatController.get_guard_absorb_cap: GuardProfile nulo")
	var cap: float = _guard.defense_absorb_cap
	return cap

func get_finisher_cfg() -> AttackConfig:
	assert(_guard != null, "CombatController.get_finisher_cfg: GuardProfile nulo")
	return _guard.finisher

# ===== Handlers de impacto (DEFENSOR) =====
func _on_defender_impact(cfg: AttackConfig, metrics: ImpactMetrics, result: int) -> void:
	if result == ContactArbiter.DefenderResult.PARRY_SUCCESS:
		enter_parry_success()
		return

	if result == ContactArbiter.DefenderResult.FINISHER_HIT:
		enter_broken_after_finisher()
		return

	if metrics.absorbed > 0.0:
		enter_guard_hit()
		return

	if metrics.hp_damage > 0.0:
		if is_interruptible_now():
			enter_hit_react()
		# Caso contrário, hyper armor/heavy/combo continuam sem trocar de estado
		return
	# Sem HP e sem absorção: não faz nada.

# ===== Handlers de impacto (ATACANTE) =====
func _on_attacker_impact(cfg: AttackConfig, feedback: int, metrics: ImpactMetrics) -> void:
	if feedback == ContactArbiter.AttackerFeedback.ATTACK_PARRIED:
		# Volta ao comportamento original: limpar buffer e entrar em PARRIED
		# somente se o golpe atual for interrompível.
		if is_interruptible_now():
			_buffer_clear()
			_change_state(State.PARRIED, null)
			_change_phase(Phase.STARTUP, null)
			_safe_start_timer(_parried.lock)
			return
		# Não-interrompível (ex.: COMBO): não altera estado/buffer.

	if feedback == ContactArbiter.AttackerFeedback.FINISHER_CONFIRMED:
		start_finisher()
		return

func _on_stamina_emptied() -> void:
	enter_guard_broken()

# =========================
# BUFFER: helpers
# =========================

func _is_attack_buffer_window_open() -> bool:
	var st: StateBase = CombatStateRegistry.get_state_for(_state)
	return st.is_attack_buffer_window_open(self)

func _buffer_clear() -> void:
	_buf_has = false
	_buf_kind = AttackKind.LIGHT
	_buf_heavy_cfg = null
	_buf_combo_seq.clear()

func _buffer_capture_light() -> void:
	_buf_has = true
	_buf_kind = AttackKind.LIGHT
	_buf_heavy_cfg = null
	_buf_combo_seq.clear()

func _buffer_capture_heavy(cfg: AttackConfig) -> void:
	_buf_has = true
	_buf_kind = AttackKind.HEAVY
	_buf_heavy_cfg = cfg
	_buf_combo_seq.clear()

func _buffer_capture_combo(seq: Array[AttackConfig]) -> void:
	_buf_has = true
	_buf_kind = AttackKind.COMBO
	_buf_heavy_cfg = null
	_buf_combo_seq.clear()
	if seq != null:
		for ac: AttackConfig in seq:
			if ac != null:
				_buf_combo_seq.append(ac)

func _buffer_consume_in_attack_recover() -> bool:
	# Consumir na janela de encadeamento (Phase.RECOVER de ATTACK não-combo)
	if not _buf_has:
		return false

	if _buf_kind == AttackKind.LIGHT:
		if attack_set == null:
			# Sem AttackSet: consumir em IDLE
			return false
		var next_idx: int = attack_set.next_index(combo_index)
		if next_idx >= 0:
			combo_index = next_idx
			var next_cfg: AttackConfig = attack_set.get_attack(combo_index)
			if next_cfg != null:
				current_cfg = next_cfg
				current_kind = AttackKind.LIGHT
				_change_phase(Phase.STARTUP, current_cfg)
				_buf_has = false
				_safe_start_timer(current_cfg.startup)
				return true
		# Sem próximo LIGHT: deixa para IDLE
		return false

	if _buf_kind == AttackKind.HEAVY:
		if _buf_heavy_cfg != null:
			_start_attack(AttackKind.HEAVY, _buf_heavy_cfg)
			_buf_has = false
			return true
		return false

	if _buf_kind == AttackKind.COMBO:
		if _buf_combo_seq.size() > 0:
			_start_combo_from_seq(_buf_combo_seq.duplicate())
			_buf_has = false
			return true
		return false

	return false

func _buffer_consume_in_idle() -> void:
	if not _buf_has:
		return

	if _buf_kind == AttackKind.LIGHT:
		var first: AttackConfig = _get_attack_from_set(0)
		_start_attack(AttackKind.LIGHT, first)
		_buf_has = false
		return

	if _buf_kind == AttackKind.HEAVY:
		if _buf_heavy_cfg != null:
			_start_attack(AttackKind.HEAVY, _buf_heavy_cfg)
			_buf_has = false
			return

	if _buf_kind == AttackKind.COMBO:
		if _buf_combo_seq.size() > 0:
			_start_combo_from_seq(_buf_combo_seq.duplicate())
			_buf_has = false
			return
