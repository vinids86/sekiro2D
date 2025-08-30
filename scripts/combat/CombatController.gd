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
# CONSTANTES
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
var _wants_chain: bool = false

var _phase_timer: Timer

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
	if _state == State.IDLE:
		var first: AttackConfig = _get_attack_from_set(0)
		_start_attack(AttackKind.LIGHT, first)
	elif _state == State.ATTACK:
		_wants_chain = true

func on_heavy_attack_pressed(cfg: AttackConfig) -> void:
	if not CombatStateRegistry.get_state_for(_state).allows_heavy_start(self):
		return
	_start_attack(AttackKind.HEAVY, cfg)

func on_combo_pressed(seq: Array[AttackConfig]) -> void:
	if not allows_attack_input_now():
		return

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

func on_parry_pressed() -> void:
	if not allows_parry_input_now():
		return

	# Entra em PARRY já em ACTIVE (sem STARTUP)
	_change_state(State.PARRY, null)
	_change_phase(Phase.ACTIVE, null)
	_safe_start_timer(_parry_profile.window)

func on_dodge_pressed(dir: int) -> void:
	if not allows_dodge_input_now():
		return
	_last_dodge_dir = dir

	_change_state(State.DODGE, null)
	_change_phase(Phase.STARTUP, null)
	_safe_start_timer(_dodge.startup)

# =========================
# NOTIFIES (AnimationPlayer → Controller) — ignorados
# =========================
func on_phase_startup_end() -> void:
	print("[WARN] on_phase_startup_end() ignorado: FSM usa timer interno.")

func on_phase_hit_end() -> void:
	print("[WARN] on_phase_hit_end() ignorado: FSM usa timer interno.")

func on_phase_recover_end() -> void:
	print("[WARN] on_phase_recover_end() ignorado: FSM usa timer interno.")

func on_parry_window_on() -> void:
	print("[WARN] on_parry_window_on() ignorado: FSM usa timer interno.")

func on_parry_window_off() -> void:
	print("[WARN] on_parry_window_off() ignorado: FSM usa timer interno.")

func on_parry_fail_end() -> void:
	print("[WARN] on_parry_fail_end() ignorado: FSM usa timer interno.")

func on_parry_success_end() -> void:
	print("[WARN] on_parry_success_end() ignorado: FSM usa timer interno.")

func on_parried_end() -> void:
	print("[WARN] on_parried_end() ignorado: FSM usa timer interno.")

func on_guard_hit_end() -> void:
	print("[WARN] on_guard_hit_end() ignorado: FSM usa timer interno.")

func on_hitstun_end() -> void:
	print("[WARN] on_hitstun_end() ignorado: FSM usa timer interno.")

# =========================
# TIMER TICK
# =========================
func _on_phase_timer_timeout() -> void:
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
		# HIT configurado em segundos no AttackConfig.hit
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

		# Encadeamento manual via AttackSet (combo "normal")
		if _wants_chain and attack_set != null:
			var next_idx: int = attack_set.next_index(combo_index)
			if next_idx >= 0:
				combo_index = next_idx
				var next_cfg: AttackConfig = attack_set.get_attack(combo_index)
				if next_cfg != null:
					current_cfg = next_cfg
					_change_phase(Phase.STARTUP, current_cfg)
					_wants_chain = false
					_safe_start_timer(current_cfg.startup)
					return
		_exit_to_idle()

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
	return _state == State.PARRY and phase == Phase.ACTIVE

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

# ======= Entradas de reação (armam timer) =======

func enter_parry_success() -> void:
	if _state != State.PARRY:
		return
	_stop_phase_timer()
	_change_phase(Phase.SUCCESS, null)
	_safe_start_timer(_parry_profile.success)

func enter_guard_hit() -> void:
	_change_state(State.GUARD_HIT, null)
	_change_phase(Phase.STARTUP, null)
	_safe_start_timer(_guard.block_recover)

func enter_guard_broken() -> void:
	_change_state(State.GUARD_BROKEN, null)
	_change_phase(Phase.STARTUP, null)
	_safe_start_timer(_guard.broken_lock)

func enter_hit_react() -> void:
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

func _exit_to_idle() -> void:
	_stop_phase_timer()

	var last: AttackConfig = current_cfg
	_change_state(State.IDLE, last)
	# Fase default pós-idle (marcador interno)
	phase = Phase.STARTUP

	current_cfg = null
	combo_index = 0
	_wants_chain = false

	_combo_seq.clear()
	_combo_hit = -1

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
		print("[CombatController] ", actor, " state: ", prev_name, " -> ", new_name)

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
	print("[CombatController] phase: ", prev_name, " -> ", new_name)

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
	var who: String = "unknown"
	var parent_node: Node = get_parent()
	if parent_node != null:
		if parent_node.is_in_group("player"):
			who = "player"
		elif parent_node.is_in_group("enemy"):
			who = "enemy"
		else:
			who = parent_node.name

	var res_name: String = ContactArbiter.DefenderResult.keys()[result]
	print("[Impact:DEF] ", who, " result=", res_name, " absorbed=", str(metrics.absorbed), " hp=", str(metrics.hp_damage))

	if result == ContactArbiter.DefenderResult.PARRY_SUCCESS:
		enter_parry_success()
		return

	if result == ContactArbiter.DefenderResult.FINISHER_HIT:
		enter_broken_after_finisher()
		return

	var only_block: bool = metrics.absorbed > 0.0 and metrics.hp_damage <= 0.0
	if only_block:
		enter_guard_hit()
	else:
		if metrics.hp_damage > 0.0:
			enter_hit_react()
		else:
			pass

# ===== Handlers de impacto (ATACANTE) =====
func _on_attacker_impact(cfg: AttackConfig, feedback: int, metrics: ImpactMetrics) -> void:
	var who: String = "unknown"
	var parent_node: Node = get_parent()
	if parent_node != null:
		if parent_node.is_in_group("player"):
			who = "player"
		elif parent_node.is_in_group("enemy"):
			who = "enemy"
		else:
			who = parent_node.name

	var fb_name: String = ContactArbiter.AttackerFeedback.keys()[feedback]
	print("[Impact:ATK] ", who, " feedback=", fb_name, " absorbed=", str(metrics.absorbed), " hp=", str(metrics.hp_damage))

	if feedback == ContactArbiter.AttackerFeedback.ATTACK_PARRIED:
		_change_state(State.PARRIED, null)
		_change_phase(Phase.STARTUP, null)
		_safe_start_timer(_parried.lock)
		return

	if feedback == ContactArbiter.AttackerFeedback.FINISHER_CONFIRMED:
		start_finisher()
		return

func _on_stamina_emptied() -> void:
	enter_guard_broken()
