extends Node
class_name CombatController

signal state_entered(state: int, cfg: StateConfig, args: StateArgs)
signal state_exited(state: int, cfg: StateConfig, args: StateArgs)
signal phase_changed(phase: int, cfg: StateConfig)

enum State {
	IDLE,
	ATTACK,
	PARRY,
	PARRIED,
	DODGE,
	STUNNED,
	GUARD_HIT,
	GUARD_BROKEN,
	FINISHER_READY,
	BROKEN_FINISHER,
	DEAD,
}

enum Phase { STARTUP, ACTIVE, SUCCESS, RECOVER }

enum AttackKind { LIGHT, HEAVY, COUNTER, FINISHER, COMBO }

# =========================
# CONSTANTES / CAMPOS
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

var _parry_profile: ParryProfile
var _hitreact: HitReactProfile
var _parried: ParriedProfile
var _guard: GuardProfile
var _counter: CounterProfile
var _dodge: DodgeProfile
var _finisher: FinisherProfile

var _phase_timer: Timer

# ===== Buffer: apenas LIGHT na janela de RECOVER com próximo golpe disponível =====
var _buf_has: bool = false

var _timer_owner_state: int = -1
var _timer_owner_phase: int = -1

@export var base_poise: float = 0.0
var _bonus_poise_pending: float = 0.0
var _attack_bonus_poise_applied: float = 0.0
var _bonus_poise_timer: Timer

var _parry_bonus_ready: bool = false
var _parry_bonus_amount: float = 0.0

func initialize(
		attack_set: AttackSet,
		parry_profile: ParryProfile,
		hit_react_profile: HitReactProfile,
		parried_profile: ParriedProfile,
		guard_profile: GuardProfile,
		counter_profile: CounterProfile,
		dodge_profile: DodgeProfile,
		finisher_profile: FinisherProfile
	) -> void:
	self.attack_set = attack_set
	_parry_profile = parry_profile
	_hitreact = hit_react_profile
	_parried = parried_profile
	_guard = guard_profile
	_counter = counter_profile
	_dodge = dodge_profile
	_finisher = finisher_profile

	_state = State.IDLE
	phase = -1
	combo_index = 0
	current_cfg = null
	_buffer_clear()

	_bonus_poise_pending = 0.0
	_attack_bonus_poise_applied = 0.0
	if _bonus_poise_timer != null:
		_bonus_poise_timer.stop()

func _ready() -> void:
	_states = CombatStateRegistry.build_states(State)

	_phase_timer = Timer.new()
	_phase_timer.one_shot = true
	add_child(_phase_timer)
	_phase_timer.timeout.connect(_on_phase_timer_timeout)

	_bonus_poise_timer = Timer.new()
	_bonus_poise_timer.one_shot = true
	add_child(_bonus_poise_timer)
	_bonus_poise_timer.timeout.connect(_on_bonus_poise_timeout)

func update(_dt: float) -> void:
	pass

func get_effective_poise() -> float:
	var action_poise_now: float = 0.0
	if current_cfg != null:
		# Usa get() para ser compatível com AttackConfig que ainda não tenham 'action_poise'
		var ap: Variant = current_cfg.get("action_poise")
		if typeof(ap) == TYPE_FLOAT or typeof(ap) == TYPE_INT:
			action_poise_now = float(ap)

	var bonus_now: float = _attack_bonus_poise_applied
	if _bonus_poise_pending > bonus_now:
		bonus_now = _bonus_poise_pending

	var total: float = base_poise + action_poise_now + bonus_now
	return total

# =========================
# INPUTS
# =========================

func on_attack_pressed() -> void:
	print("[ATK] input: state=", State.keys()[_state])

	# FINISHER READY: qualquer ataque inicia finisher
	if _state == State.FINISHER_READY:
		print("[ATK] FINISHER_READY -> start_finisher()")
		start_finisher()
		return

	# LIGHT normal (primeiro da sequência)
	if _state == State.IDLE:
		var first: AttackConfig = _get_attack_from_set(0)
		_start_attack(AttackKind.LIGHT, first)
		return

	# Buffer APENAS para LIGHT durante RECOVER de LIGHT e com próximo golpe disponível
	if _can_buffer_light_now() and not _buf_has:
		_buffer_capture_light()
		return

func on_heavy_attack_pressed(cfg: AttackConfig) -> void:
	var st: StateBase = _get_state()
	if st.allows_heavy_start(self):
		_start_attack(AttackKind.HEAVY, cfg)
		return

func on_combo_pressed(seq: Array[AttackConfig]) -> void:
	if _state == State.FINISHER_READY:
		return

	# COMBO inicia apenas se permitido agora; sem buffer
	if allows_attack_input_now():
		_start_combo_from_seq(seq)
		return
	# Fora de janela: ignora

func on_parry_pressed() -> void:
	if not allows_parry_input_now():
		return

	_buffer_clear()
	_change_state(State.PARRY, null)
	_change_phase(Phase.ACTIVE, null)

	_safe_start_timer(_parry_profile.window)

	var owner_state_name: String = State.keys()[_timer_owner_state]
	var owner_phase_name: String = Phase.keys()[_timer_owner_phase]

func on_dodge_pressed(stamina: Stamina, dir: int) -> void:
	assert(stamina != null, "CombatController.on_dodge_pressed: parâmetro 'stamina' é null.")
	if not allows_dodge_input_now():
		return

	var cost: float = maxf(0.0, _dodge.stamina_cost)
	if cost > 0.0:
		var ok: bool = stamina.try_consume(cost)
		if not ok:
			return

	_buffer_clear()
	_change_state(State.DODGE, null, DodgeArgs.new(dir))
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
	if _state == State.FINISHER_READY:
		_tick_finisher_ready()
		return
	if _state == State.BROKEN_FINISHER:
		_tick_broken_finisher()
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

		# Consumo do buffer para LIGHT (encadeamento)
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
		# ===== SAÍDA DO LOCK DE PARRY: arma a janela agora =====
		if _parry_bonus_ready:
			var duration: float = 0.0
			var d: Variant = _parry_profile.get("bonus_poise_duration")
			if typeof(d) == TYPE_FLOAT or typeof(d) == TYPE_INT:
				duration = float(d)

			if duration > 0.0 and _parry_bonus_amount > 0.0:
				_bonus_poise_pending = _parry_bonus_amount
				_parry_bonus_amount = 0.0
				_parry_bonus_ready = false

				if _bonus_poise_timer != null:
					_bonus_poise_timer.stop()
					_bonus_poise_timer.start(duration)

				print("[POISE] janela armada ao sair do SUCCESS -> pending=", _bonus_poise_pending, " dur=", duration)
			else:
				_parry_bonus_ready = false
				_parry_bonus_amount = 0.0
				print("[POISE] janela NÃO armada (duration/amount inválidos)")

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

func _tick_finisher_ready() -> void:
	if phase == Phase.STARTUP:
		_change_phase(Phase.ACTIVE, null)
		# Sem rearmar timer: aguarda input do jogador para iniciar o finisher
		return
	if phase == Phase.ACTIVE:
		# Continua aguardando input do jogador
		return

# =========================
# Consultas
# =========================

func get_state_instance_for(state_id: int) -> StateBase:
	assert(_states.has(state_id), "CombatController.get_state_instance_for: id de estado inválido: %s" % [str(state_id)])
	return _states[state_id]

func is_stunned() -> bool:
	return _state == State.STUNNED

func is_parry_window() -> bool:
	var active: bool = (_state == State.PARRY and phase == Phase.ACTIVE)
	return active

func is_dodge_active() -> bool:
	return _state == State.DODGE and phase == Phase.ACTIVE

func is_autoblock_enabled_now() -> bool:
	return _get_state().autoblock_enabled(self)

func allows_attack_input_now() -> bool:
	return _get_state().allows_attack_input(self)

func allows_parry_input_now() -> bool:
	return _get_state().allows_parry_input(self)

func allows_dodge_input_now() -> bool:
	return _get_state().allows_dodge_input(self)

func allows_movement_now() -> bool:
	return _get_state().allows_movement(self)

func _is_attack_buffer_window_open() -> bool:
	return _get_state().is_attack_buffer_window_open(self)

# ===== enter_parry_success: mantém seu fluxo e acrescenta o bônus =====
func enter_parry_success() -> void:
	if _state != State.PARRY:
		return

	_stop_phase_timer()
	_change_phase(Phase.SUCCESS, null)
	_safe_start_timer(_parry_profile.success)

	# ===== Sinaliza bônus de poise PÓS-parry (sem iniciar timer ainda) =====
	var amount: float = 0.0
	var duration: float = 0.0

	var a: Variant = _parry_profile.get("bonus_poise_amount")
	if typeof(a) == TYPE_FLOAT or typeof(a) == TYPE_INT:
		amount = float(a)

	var d: Variant = _parry_profile.get("bonus_poise_duration")
	if typeof(d) == TYPE_FLOAT or typeof(d) == TYPE_INT:
		duration = float(d)

	if amount > 0.0 and duration > 0.0:
		_parry_bonus_ready = true
		_parry_bonus_amount = amount
		print("[POISE] parry success -> ready amount=", _parry_bonus_amount, " (timer só arma ao sair do SUCCESS)")
	else:
		_parry_bonus_ready = false
		_parry_bonus_amount = 0.0
		print("[POISE] parry success -> sem bonus (amount/duration inválidos no ParryProfile)")

func enter_parried() -> void:
	_buffer_clear()
	_change_state(State.PARRIED, null)
	_change_phase(Phase.STARTUP, null)
	_safe_start_timer(_parried.lock)

func enter_guard_hit() -> void:
	_buffer_clear()
	_change_state(State.GUARD_HIT, null)
	_change_phase(Phase.STARTUP, null)
	_safe_start_timer(_guard.block_recover)

func enter_guard_broken() -> void:
	_buffer_clear()
	_change_state(State.GUARD_BROKEN, null)
	_change_phase(Phase.STARTUP, null)
	_safe_start_timer(_guard.broken_finisher_lock)

func enter_hit_react() -> void:
	_buffer_clear()
	_change_state(State.STUNNED, null)
	_change_phase(Phase.STARTUP, null)
	_safe_start_timer(_hitreact.stun)
	
func enter_finisher_ready() -> void:
	# Parar timers do golpe atual e limpar tudo que conflita
	_stop_phase_timer()
	_buffer_clear()
	_combo_seq.clear()
	_combo_hit = -1
	combo_index = 0
	current_cfg = null
	current_kind = AttackKind.LIGHT

	# Trocar de estado, fase e armar o lock visual
	_change_state(State.FINISHER_READY, null)
	_change_phase(Phase.STARTUP, null)
	_safe_start_timer(_finisher.ready_lock)

func enter_broken_after_finisher() -> void:
	print("[FSM] Enter broken finisher for ", _guard.broken_finisher_lock)
	_buffer_clear()
	_change_state(State.BROKEN_FINISHER, null)
	_change_phase(Phase.STARTUP, null)

	assert(_guard != null, "enter_broken_after_finisher: GuardProfile nulo")
	assert(_guard.broken_finisher_lock > 0.0, "GuardProfile.broken_finisher_lock deve ser > 0.0")

	_safe_start_timer(_guard.broken_finisher_lock)

func _tick_broken_finisher() -> void:
	print("[DEF] _tick_broken_finisher -> exit to IDLE")

	_exit_to_idle()

func start_finisher() -> void:
	print("[ATK] start_finisher cfg=", _finisher != null and _finisher.attack, " kind=FINISHER")
	_start_attack(AttackKind.FINISHER, _finisher.attack)

# =========================
# HELPERS
# =========================
func _get_state() -> StateBase:
	assert(_states.has(_state), "CombatController: estado '%s' não foi construído." % [str(_state)])
	return _states[_state]

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

# ===== _start_attack: consumir bônus se estiver ativo =====
func _start_attack(kind: AttackKind, cfg: AttackConfig) -> void:
	print("[ATK] _start_attack kind=", kind, " cfg=", cfg)
	if cfg == null:
		return

	current_kind = kind
	current_cfg = cfg

	# Latch do bônus de poise se houver pending dentro da janela
	if _bonus_poise_timer != null and _bonus_poise_timer.time_left > 0.0 and _bonus_poise_pending > 0.0:
		if _bonus_poise_pending > _attack_bonus_poise_applied:
			_attack_bonus_poise_applied = _bonus_poise_pending
		# Consome o pending para garantir que vale APENAS para o próximo ataque
		_bonus_poise_pending = 0.0
		print("[POISE] latch -> applied=", _attack_bonus_poise_applied)

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

func _try_start_dodge(stamina: Stamina) -> bool:
	assert(stamina != null, "CombatController._try_start_dodge_with_stamina: parâmetro 'stamina' é null.")

	# Janela de permissão vem do estado atual (StateAttack.allows_dodge_input).
	var allowed: bool = allows_dodge_input_now()
	if not allowed:
		return false

	var cost: float = maxf(0.0, _dodge.stamina_cost)
	if cost > 0.0:
		var ok: bool = stamina.try_consume(cost)
		if not ok:
			return false

	_buffer_clear()
	_change_state(State.DODGE, null)
	_change_phase(Phase.STARTUP, null)
	_safe_start_timer(_dodge.startup)
	return true

func get_state() -> int:
	return _state

# ===== _exit_to_idle: limpar bônus aplicado do ataque =====
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

	_attack_bonus_poise_applied = 0.0

	if _buf_has:
		_buffer_clear()

func _change_state(new_state: int, cfg: StateConfig, args: StateArgs = null) -> void:
	print("[FSM] change state: ", new_state)

	var same: bool = new_state == _state
	var reentry_allowed: bool = _get_state().allows_reentry(self)

	if (same and reentry_allowed) or (not same):
		_stop_phase_timer()

		var prev: int = _state
		# on_exit do estado anterior
		_get_state().on_exit(self, cfg)
		emit_signal("state_exited", prev, cfg, null)

		_state = new_state

		# on_enter do novo estado (com payload)
		_get_state().on_enter(self, cfg, args)
		emit_signal("state_entered", _state, cfg, args)

		# Ao sair de ATTACK, limpar o bônus aplicado
		if prev == State.ATTACK and new_state != State.ATTACK:
			_attack_bonus_poise_applied = 0.0
			_combo_seq.clear()
			_combo_hit = -1

func _change_phase(new_phase: Phase, cfg: StateConfig) -> void:
	var prev: int = phase
	var prev_name: String = Phase.keys()[prev]
	var new_name: String = Phase.keys()[new_phase]

	phase = new_phase
	emit_signal("phase_changed", phase, cfg)

func is_combo_offense_active() -> bool:
	return _state == State.ATTACK and (phase == Phase.STARTUP or phase == Phase.ACTIVE)

func is_combo_last_attack() -> bool:
	# Se estivermos executando um COMBO com sequência interna (_combo_seq),
	# "último" é o último índice dessa sequência.
	if current_kind == AttackKind.COMBO:
		assert(_combo_seq.size() > 0, "is_combo_last_attack: COMBO ativo mas _combo_seq está vazio.")
		assert(_combo_hit >= 0 and _combo_hit < _combo_seq.size(), "is_combo_last_attack: _combo_hit fora do intervalo.")
		return _combo_hit >= _combo_seq.size() - 1

	# Caso contrário, considera-se a sequência do AttackSet (LIGHT encadeado, etc.)
	assert(attack_set != null, "is_combo_last_attack: attack_set é null.")
	assert(attack_set.attacks.size() > 0, "is_combo_last_attack: attack_set.attacks vazio.")
	assert(combo_index >= 0 and combo_index < attack_set.attacks.size(), "is_combo_last_attack: combo_index fora do intervalo.")
	return combo_index >= attack_set.attacks.size() - 1

# --- CAPACIDADES DEFENSIVAS CONSULTADAS PELO MEDIADOR ---

func is_guard_broken_active() -> bool:
	print("[FSM] is_guard_broken_active: ", _state == State.GUARD_BROKEN)
	print("[FSM] _state is: ", _state)
	return _state == State.GUARD_BROKEN

func get_guard_absorb_cap() -> float:
	assert(_guard != null, "CombatController.get_guard_absorb_cap: GuardProfile nulo")
	var cap: float = _guard.defense_absorb_cap
	return cap

func get_finisher_cfg() -> AttackConfig:
	assert(_guard != null, "CombatController.get_finisher_cfg: GuardProfile nulo")
	return _guard.finisher

# ===== Handlers de impacto (DEFENSOR) =====
func _on_defender_impact(cfg: AttackConfig, metrics: ImpactMetrics, result: int) -> void:
	print("[DEF] res=", result, " name=", ContactArbiter.DefenderResult.keys()[result],
	  " absorbed=", metrics.absorbed, " hp=", metrics.hp_damage,
	  " state_before=", State.keys()[_state])

	# PRIMÁRIO: sinais que sempre têm prioridade, independentemente do estado
	if result == ContactArbiter.DefenderResult.PARRY_SUCCESS:
		enter_parry_success()
		return

	if result == ContactArbiter.DefenderResult.FINISHER_HIT:
		print("[DEF] enter_broken_after_finisher lock=", _guard.broken_finisher_lock)
		enter_broken_after_finisher()
		return

	if result == ContactArbiter.DefenderResult.GUARD_BROKEN_ENTERED:
		# Perde bônus pendente se ainda não estava em ATTACK
		if _state != State.ATTACK:
			_bonus_poise_pending = 0.0
			if _bonus_poise_timer != null:
				_bonus_poise_timer.stop()
		enter_guard_broken()
		return

	if result == ContactArbiter.DefenderResult.POISE_BREAK:
		# Interrupção por poise: SEMPRE corta, independe de "interruptível"
		enter_hit_react()
		return

	# A PARTIR DAQUI: resultado base (BLOCKED/DAMAGED/DODGED) -> não deve cortar ATTACK
	# DODGED não afeta o defensor
	if result == ContactArbiter.DefenderResult.DODGED:
		return

	# Se estamos atacando, BLOCKED/DAMAGED NÃO trocam o estado (exceto se já estivéssemos em RECOVER).
	if _state == State.ATTACK and phase != Phase.RECOVER:
		return

	# Fora de ATTACK, mantém seu fluxo original:
	# BLOCO puro
	if metrics.absorbed > 0.0 and metrics.hp_damage <= 0.0:
		enter_guard_hit()
		return

	# Dano HP
	if metrics.hp_damage > 0.0:
		enter_hit_react()
		return

	# Sem efeito adicional

# ===== Handlers de impacto (ATACANTE) =====
func _on_attacker_impact(cfg: AttackConfig, feedback: int, metrics: ImpactMetrics) -> void:
	print("[ATK] fb=", feedback, " name=", ContactArbiter.AttackerFeedback.keys()[feedback])

	# Parry recebido
	if feedback == ContactArbiter.AttackerFeedback.ATTACK_PARRIED:
		# Regra: apenas LIGHT entra em PARRIED; HEAVY/COMBO seguem
		var kind_now: int = current_kind
		if kind_now == AttackKind.LIGHT:
			# Sem checar is_interruptible: parry é soberano para LIGHT
			enter_parried()
			return
		# HEAVY/COMBO/FINISHER não mudam de estado aqui
		return

	# Guard broken confirmado neste hit -> entrar em FINISHER_READY
	if feedback == ContactArbiter.AttackerFeedback.GUARD_BROKEN_CONFIRMED:
		print("[ATK] enter_finisher_ready()")
		enter_finisher_ready()
		return

	# (Demais feedbacks: ignorar aqui)

func __grant_poise_bonus(amount: float, duration: float) -> void:
	var amt: float = amount
	if amt < 0.0:
		amt = 0.0
	_bonus_poise_pending = amt

	if _bonus_poise_timer == null:
		return

	_bonus_poise_timer.stop()
	var d: float = duration
	if d < 0.0:
		d = 0.0
	_bonus_poise_timer.wait_time = d
	_bonus_poise_timer.start()

func _on_bonus_poise_timeout() -> void:
	_bonus_poise_pending = 0.0
	print("[POISE] bonus pending expirou")

# =========================
# BUFFER: helpers
# =========================

func _buffer_clear() -> void:
	_buf_has = false

func _buffer_capture_light() -> void:
	# pré-condição: _can_buffer_light_now() == true
	_buf_has = true

func _buffer_consume_in_attack_recover() -> bool:
	# Consumo durante ATTACK/RECOVER apenas para LIGHT com próximo disponível
	if not _buf_has:
		return false
	if attack_set == null:
		_buf_has = false
		return false
	if current_kind != AttackKind.LIGHT:
		# segurança: não deveria chegar aqui com buffer armado fora de LIGHT
		_buf_has = false
		return false

	var next_idx: int = attack_set.next_index(combo_index)
	if next_idx < 0:
		_buf_has = false
		return false

	combo_index = next_idx
	var next_cfg: AttackConfig = attack_set.get_attack(combo_index)
	if next_cfg == null:
		_buf_has = false
		return false

	current_cfg = next_cfg
	current_kind = AttackKind.LIGHT
	_change_phase(Phase.STARTUP, current_cfg)
	_buf_has = false
	_safe_start_timer(current_cfg.startup)
	return true

# =========================
# Regras auxiliares (buffer só para LIGHT)
# =========================
func _can_buffer_light_now() -> bool:
	# Deve estar em ATTACK/RECOVER de um golpe LIGHT
	if _state != State.ATTACK:
		return false
	if phase != Phase.RECOVER:
		return false
	if current_kind != AttackKind.LIGHT:
		return false
	if attack_set == null:
		return false
	# Só permite se houver PRÓXIMO golpe na sequência normal
	var next_idx: int = attack_set.next_index(combo_index)
	if next_idx < 0:
		return false
	print("BUFFER ")
	return true
