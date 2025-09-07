extends Node
class_name CombatController

signal state_entered(state: int, cfg: StateConfig, args: StateArgs)
signal state_exited(state: int, cfg: StateConfig, args: StateArgs)
signal phase_changed(phase: int, cfg: StateConfig)

enum State {
	IDLE, ATTACK, PARRY, PARRIED, DODGE, STUNNED, GUARD_HIT,
	GUARD_BROKEN, FINISHER_READY, BROKEN_FINISHER, DEAD,
}
enum Phase { STARTUP, ACTIVE, SUCCESS, RECOVER }
enum AttackKind { LIGHT, HEAVY, COUNTER, FINISHER, COMBO }

# =========================
# DEPENDÊNCIAS
# =========================
@export var poise_controller: PoiseController
@export var buffer_controller: BufferController

# =========================
# ESTADO E CONFIGURAÇÃO
# =========================
var _states: Dictionary = {}
var _state: int = State.IDLE
var phase: int = -1
var current_kind: AttackKind = AttackKind.LIGHT
var combo_index: int = 0
var current_cfg: AttackConfig

var attack_set: AttackSet
var _combo_seq: Array[AttackConfig] = []
var _combo_hit: int = -1

# Perfis de configuração
var _parry_profile: ParryProfile
var _hitreact: HitReactProfile
var _parried: ParriedProfile
var _guard: GuardProfile
var _counter: CounterProfile
var _dodge: DodgeProfile
var _finisher: FinisherProfile

# Timers
var _phase_timer: Timer
var _timer_owner_state: int = -1
var _timer_owner_phase: int = -1


func initialize(
		attack_set: AttackSet, parry_profile: ParryProfile, hit_react_profile: HitReactProfile,
		parried_profile: ParriedProfile, guard_profile: GuardProfile, counter_profile: CounterProfile,
		dodge_profile: DodgeProfile, finisher_profile: FinisherProfile, base_poise: float
	) -> void:
	print("parry_profile", parry_profile, _parry_profile)
	self.attack_set = attack_set
	_parry_profile = parry_profile; _hitreact = hit_react_profile; _parried = parried_profile
	_guard = guard_profile; _counter = counter_profile; _dodge = dodge_profile; _finisher = finisher_profile

	if poise_controller: poise_controller.initialize(base_poise)
	if buffer_controller: buffer_controller.clear()

	_state = State.IDLE; phase = -1; combo_index = 0; current_cfg = null

func _ready() -> void:
	print("--- CombatController _ready() INICIOU ---")
	print("Poise Controller na _ready: ", poise_controller)
	print("Buffer Controller na _ready: ", buffer_controller)
	
	assert(poise_controller != null, "PoiseController não está atribuído no CombatController.")
	assert(buffer_controller != null, "BufferController não está atribuído no CombatController.")
	
	_states = CombatStateRegistry.build_states(State)

	_phase_timer = Timer.new(); _phase_timer.one_shot = true
	add_child(_phase_timer); _phase_timer.timeout.connect(_on_phase_timer_timeout)


# =========================
# INPUTS
# =========================
func on_attack_pressed() -> void:
	if _state == State.FINISHER_READY:
		start_finisher()
		return

	if _state == State.IDLE:
		var first: AttackConfig = _get_attack_from_set(0)
		_start_attack(AttackKind.LIGHT, first)
		return

	if buffer_controller.can_buffer_now(self):
		buffer_controller.capture()
		return

func on_heavy_attack_pressed(cfg: AttackConfig) -> void:
	if _get_state().allows_heavy_start(self):
		_start_attack(AttackKind.HEAVY, cfg)

func on_combo_pressed(seq: Array[AttackConfig]) -> void:
	if _state == State.FINISHER_READY: return
	if allows_attack_input_now(): _start_combo_from_seq(seq)

func on_parry_pressed() -> void:
	if not allows_parry_input_now(): return
	buffer_controller.clear()
	_change_state(State.PARRY, null)
	_change_phase(Phase.ACTIVE, null)
	_safe_start_timer(_parry_profile.window)

func on_dodge_pressed(stamina: Stamina, dir: int) -> void:
	if not allows_dodge_input_now(): return
	var cost: float = maxf(0.0, _dodge.stamina_cost)
	if cost > 0.0 and not stamina.try_consume(cost): return

	buffer_controller.clear()
	_change_state(State.DODGE, null, DodgeArgs.new(dir))
	_change_phase(Phase.STARTUP, null)
	_safe_start_timer(_dodge.startup)

# =========================
# TIMER TICK
# =========================
func _on_phase_timer_timeout() -> void:
	if _state != _timer_owner_state or phase != _timer_owner_phase:
		return
	
	_get_state().on_timeout(self)

# =========================
# Consultas
# =========================
func get_state() -> int: return _state
func get_state_instance_for(state_id: int) -> StateBase: return _states[state_id]
func get_effective_poise() -> float: 
	var action_poise: float = 0.0
	if current_cfg != null:
		action_poise = current_cfg.action_poise
	return poise_controller.get_effective_poise(action_poise)

func is_stunned() -> bool: return _state == State.STUNNED
func is_parry_window() -> bool: return _state == State.PARRY and phase == Phase.ACTIVE
func is_dodge_active() -> bool: return _state == State.DODGE and phase == Phase.ACTIVE
func is_autoblock_enabled_now() -> bool: return _get_state().autoblock_enabled(self)
func allows_attack_input_now() -> bool: return _get_state().allows_attack_input(self)
func allows_parry_input_now() -> bool: return _get_state().allows_parry_input(self)
func allows_dodge_input_now() -> bool: return _get_state().allows_dodge_input(self)
func allows_movement_now() -> bool: return _get_state().allows_movement(self)
func is_guard_broken_active() -> bool: return _state == State.GUARD_BROKEN
func get_guard_absorb_cap() -> float:
	assert(_guard != null, "CombatController.get_guard_absorb_cap: GuardProfile nulo")
	var cap: float = _guard.defense_absorb_cap
	return cap

func get_finisher_cfg() -> AttackConfig:
	assert(_finisher != null, "CombatController.get_finisher_cfg: FinisherProfile nulo")
	# Nota: Alterei de _guard.finisher para _finisher.attack, que parece mais correto
	# com base na sua função start_finisher(). Ajuste se necessário.
	return _finisher.attack
func is_combo_offense_active() -> bool: return _state == State.ATTACK and (phase == Phase.STARTUP or phase == Phase.ACTIVE)

func is_combo_last_attack() -> bool:
	# Para COMBO (sequência interna)
	if current_kind == AttackKind.COMBO:
		return _combo_hit >= _combo_seq.size() - 1

	# Para a sequência LIGHT do AttackSet
	assert(attack_set != null, "is_combo_last_attack: attack_set é null.")
	assert(attack_set.attacks.size() > 0, "is_combo_last_attack: attack_set.attacks vazio.")
	assert(combo_index >= 0 and combo_index < attack_set.attacks.size(), "is_combo_last_attack: combo_index fora do intervalo.")
	return combo_index >= attack_set.attacks.size() - 1

# =========================
# State Entry Points / Event Handlers
# =========================
func enter_parry_success() -> void:
	if _state != State.PARRY: return
	_stop_phase_timer()
	_change_phase(Phase.SUCCESS, null)
	_safe_start_timer(_parry_profile.success)
	poise_controller.arm_parry_bonus(_parry_profile)

func enter_parried() -> void:
	buffer_controller.clear()
	_change_state(State.PARRIED, null); _change_phase(Phase.STARTUP, null)
	_safe_start_timer(_parried.lock)

func enter_guard_hit() -> void:
	buffer_controller.clear()
	_change_state(State.GUARD_HIT, null); _change_phase(Phase.STARTUP, null)
	_safe_start_timer(_guard.block_recover)

func enter_guard_broken() -> void:
	buffer_controller.clear()
	poise_controller.on_guard_broken() # Reset poise bonus on guard break
	_change_state(State.GUARD_BROKEN, null); _change_phase(Phase.STARTUP, null)
	_safe_start_timer(_guard.broken_finisher_lock)

func enter_hit_react() -> void:
	buffer_controller.clear()
	_change_state(State.STUNNED, null); _change_phase(Phase.STARTUP, null)
	_safe_start_timer(_hitreact.stun)

func enter_finisher_ready() -> void:
	_stop_phase_timer(); buffer_controller.clear()
	_combo_seq.clear(); _combo_hit = -1
	combo_index = 0; current_cfg = null; current_kind = AttackKind.LIGHT

	_change_state(State.FINISHER_READY, null)
	_change_phase(Phase.STARTUP, null)
	_safe_start_timer(_finisher.ready_lock)

func enter_broken_after_finisher() -> void:
	buffer_controller.clear()
	_change_state(State.BROKEN_FINISHER, null); _change_phase(Phase.STARTUP, null)
	_safe_start_timer(_guard.broken_finisher_lock)

func start_finisher() -> void:
	_start_attack(AttackKind.FINISHER, _finisher.attack)

# =========================
# Impact Handlers (ATACANTE E DEFENSOR)
# =========================
func _on_defender_impact(cfg: AttackConfig, metrics: ImpactMetrics, result: int) -> void:
	if result == ContactArbiter.DefenderResult.PARRY_SUCCESS:
		enter_parry_success(); return
	if result == ContactArbiter.DefenderResult.FINISHER_HIT:
		enter_broken_after_finisher(); return
	if result == ContactArbiter.DefenderResult.GUARD_BROKEN_ENTERED:
		enter_guard_broken(); return
	if result == ContactArbiter.DefenderResult.POISE_BREAK:
		enter_hit_react()
		return

	if result == ContactArbiter.DefenderResult.DODGED: return
	if _state == State.ATTACK and phase != Phase.RECOVER: return

	if metrics.absorbed > 0.0 and metrics.hp_damage <= 0.0:
		enter_guard_hit(); return
	if metrics.hp_damage > 0.0:
		enter_hit_react()

func _on_attacker_impact(cfg: AttackConfig, feedback: int, metrics: ImpactMetrics) -> void:
	print("[ATK] fb=", feedback, " name=", ContactArbiter.AttackerFeedback.keys()[feedback])

	# Parry recebido: DERRUBA apenas LIGHT; HEAVY/COMBO/FINISHER continuam
	if feedback == ContactArbiter.AttackerFeedback.ATTACK_PARRIED:
		var kind_now: int = current_kind
		if kind_now == AttackKind.LIGHT:
			enter_parried()
			return
		# HEAVY/COMBO/FINISHER: sem troca de estado aqui
		return

	# Guard broken confirmado neste hit -> entrar em FINISHER_READY
	if feedback == ContactArbiter.AttackerFeedback.GUARD_BROKEN_CONFIRMED:
		print("[ATK] enter_finisher_ready()")
		enter_finisher_ready()
		return

	# (demais feedbacks: ignorar)

# =========================
# HELPERS
# =========================
func _get_state() -> StateBase:
	assert(_states.has(_state), "CombatController: estado '%s' não foi construído." % [str(_state)])
	return _states[_state]

func _get_attack_from_set(index: int) -> AttackConfig:
	if attack_set == null: return null
	return attack_set.get_attack(index)

func _start_attack(kind: AttackKind, cfg: AttackConfig) -> void:
	if cfg == null: return
	current_kind = kind; current_cfg = cfg
	poise_controller.on_attack_started()
	
	var idx: int = -1
	if attack_set: idx = attack_set.attacks.find(cfg)
	combo_index = idx if idx >= 0 else 0

	_change_state(State.ATTACK, current_cfg)
	_change_phase(Phase.STARTUP, current_cfg)
	_safe_start_timer(current_cfg.startup)

func _start_combo_from_seq(seq: Array[AttackConfig]) -> void:
	current_kind = AttackKind.COMBO
	_combo_seq = seq.filter(func(ac): return ac != null)
	if _combo_seq.is_empty(): return
	
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
	phase = Phase.STARTUP
	current_cfg = null; combo_index = 0
	_combo_seq.clear(); _combo_hit = -1
	poise_controller.on_action_finished()
	buffer_controller.clear()

func _change_state(new_state: int, cfg: StateConfig, args: StateArgs = null) -> void:
	var same: bool = new_state == _state
	var reentry_allowed: bool = _get_state().allows_reentry(self)
	if not same or reentry_allowed:
		_stop_phase_timer()
		var prev: int = _state
		_get_state().on_exit(self, cfg)
		emit_signal("state_exited", prev, cfg, null)
		_state = new_state
		_get_state().on_enter(self, cfg, args)
		emit_signal("state_entered", _state, cfg, args)
		if prev == State.ATTACK and new_state != State.ATTACK:
			poise_controller.on_action_finished()
			_combo_seq.clear(); _combo_hit = -1

func _change_phase(new_phase: Phase, cfg: StateConfig) -> void:
	phase = new_phase
	emit_signal("phase_changed", phase, cfg)

func _safe_start_timer(duration: float) -> void:
	_phase_timer.stop()
	var d: float = maxf(duration, 0.0)
	_timer_owner_state = _state
	_timer_owner_phase = phase
	_phase_timer.wait_time = d
	_phase_timer.start()

func _stop_phase_timer() -> void:
	if _phase_timer != null: _phase_timer.stop()
	
func _phase_duration_from_cfg(cfg: AttackConfig, p: Phase) -> float:
	if not cfg: return 0.0
	match p:
		Phase.STARTUP: return cfg.startup
		Phase.ACTIVE: return cfg.hit
		Phase.RECOVER: return cfg.recovery
	return 0.0
