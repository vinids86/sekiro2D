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

var _state: int = State.IDLE
var phase: Phase = Phase.STARTUP
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
	phase = Phase.STARTUP
	combo_index = 0
	current_cfg = null

func _ready() -> void:
	CombatStateRegistry.bind_states(State)
	

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

	# Mantém cfg nulo até o 1º phase_startup_end() (evita cfg “fantasma”)
	current_cfg = null
	combo_index = 0

	_change_state(State.ATTACK, current_cfg)
	phase = Phase.STARTUP
	print("STARTUP")
	emit_signal("phase_changed", phase, current_cfg)

func on_parry_pressed() -> void:
	print("parry -> on_parry_pressed")
	if not allows_parry_input_now():
		print("parry -> not allows_parry_input_now")
		return

	# Rearme manual: se já estou em PARRY/SUCCESS, recomeço o fluxo do parry
	if _state == State.PARRY and phase == Phase.SUCCESS:
		print("parry -> phase_changed STARTUP")
		phase = Phase.STARTUP
		emit_signal("phase_changed", phase, null)
		return

	# Fluxo normal de entrada no parry
	print("parry -> Fluxo normal de entrada no parry")
	_change_state(State.PARRY, null)
	phase = Phase.STARTUP
	emit_signal("phase_changed", phase, null)

func on_dodge_pressed(dir: int) -> void:
	if not allows_dodge_input_now():
		return
	_last_dodge_dir = dir
	_change_state(State.DODGE, null)
	phase = Phase.STARTUP
	emit_signal("phase_changed", phase, null)

# =========================
# NOTIFIES (AnimationPlayer → Listener → Controller)
# =========================
func on_phase_startup_end() -> void:
	if _state == State.ATTACK and current_kind == AttackKind.COMBO:
		_combo_hit += 1
		var total: int = _combo_seq.size()

		var cfg_for_hit: AttackConfig = _combo_seq[_combo_hit]

		current_cfg = cfg_for_hit
		combo_index = _combo_hit

	phase = CombatController.Phase.ACTIVE
	emit_signal("phase_changed", phase, current_cfg)

func on_phase_hit_end() -> void:
	phase = CombatController.Phase.RECOVER
	emit_signal("phase_changed", phase, current_cfg)

func on_phase_recover_end() -> void:
	if _state == State.ATTACK:
		# Combo especial (timeline-driven) sempre encerra aqui
		if current_kind == AttackKind.COMBO:
			_exit_to_idle()
			return

		# Encadeamento manual (combo normal via AttackSet)
		if _wants_chain and attack_set != null:
			var next_idx: int = attack_set.next_index(combo_index)
			if next_idx >= 0:
				combo_index = next_idx
				var next_cfg: AttackConfig = attack_set.get_attack(combo_index)
				if next_cfg != null:
					current_cfg = next_cfg
					# Mantemos o kind atual (normalmente LIGHT)
					phase = Phase.STARTUP
					emit_signal("phase_changed", phase, current_cfg)
					_wants_chain = false
					return
			# sem próximo → cai para idle
		_exit_to_idle()
	elif _state == State.PARRY or _state == State.DODGE:
		_exit_to_idle()

func enter_parried() -> void:
	_change_state(State.PARRIED, null)
	phase = Phase.STARTUP
	emit_signal("phase_changed", phase, null)

func on_parried_end() -> void:
	print("Provavelmente não")
	_exit_to_idle()

# ======= Consultas/compat =======

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

# ======= Entradas de reação =======

func enter_parry_success() -> void:
	if _state != State.PARRY:
		return
	# Sucesso de parry é uma phase própria (evento).
	phase = Phase.SUCCESS
	emit_signal("phase_changed", phase, null)

func enter_guard_hit() -> void:
	_change_state(State.GUARD_HIT, null)

func enter_guard_broken() -> void:
	_change_state(State.GUARD_BROKEN, null)

func enter_hit_react() -> void:
	_change_state(State.STUNNED, null)

func enter_broken_after_finisher() -> void:
	_change_state(State.GUARD_BROKEN, null)

func on_guard_hit_end() -> void:
	if _state == State.GUARD_HIT:
		_exit_to_idle()

func on_hitstun_end() -> void:
	if _state == State.STUNNED:
		_exit_to_idle()

func start_finisher() -> void:
	if _guard != null and _guard.finisher != null:
		_start_attack(AttackKind.FINISHER, _guard.finisher)
		
func on_parry_window_on() -> void:
	if _state != State.PARRY:
		return
	phase = Phase.ACTIVE
	emit_signal("phase_changed", phase, null)

func on_parry_window_off() -> void:
	if _state != State.PARRY:
		return
	# Só punimos se a janela estava ativa e não houve sucesso
	if phase == Phase.ACTIVE:
		phase = Phase.RECOVER
		emit_signal("phase_changed", phase, null)

func on_parry_fail_end() -> void:
	# Fim visual do clipe de parry quando falhou (estava em RECOVER)
	if _state == State.PARRY and phase == Phase.RECOVER:
		_exit_to_idle()

func on_parry_success_end() -> void:
	# Fim visual do clipe de sucesso (se o player não rearmou)
	if _state == State.PARRY and phase == Phase.SUCCESS:
		_exit_to_idle()

# =========================
# HELPERS
# =========================

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
	phase = Phase.STARTUP
	emit_signal("phase_changed", phase, current_cfg)

func _exit_to_idle() -> void:
	var last: AttackConfig = current_cfg
	_change_state(State.IDLE, last)
	phase = Phase.STARTUP
	current_cfg = null
	combo_index = 0
	_wants_chain = false

func _change_state(new_state: int, cfg: AttackConfig) -> void:
	var same: bool = new_state == _state
	var reentry_allowed: bool = CombatStateRegistry.get_state_for(_state).allows_reentry(self)

	if (same and reentry_allowed) or (not same):
		var prev: int = _state

		# ---------- LOG: quem (player/enemy) e transição ----------
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
		# ---------------------------------------------------------

		emit_signal("state_exited", prev, cfg)
		_state = new_state
		emit_signal("state_entered", _state, cfg)

		if prev == State.ATTACK and new_state != State.ATTACK:
			_combo_seq.clear()
			_combo_hit = -1

func get_state() -> int:
	return _state

func is_combo_offense_active() -> bool:
	# Verdadeiro se o controlador está no estado ofensivo e ainda não entrou em RECOVER
	return _state == State.ATTACK and (phase == Phase.STARTUP or phase == Phase.ACTIVE)

func is_combo_last_attack() -> bool:
	# Se não houver AttackSet, trate como último (não bloqueia)
	if attack_set == null:
		return true
	# Se não houver próximo índice, este é o último ataque do combo
	return attack_set.next_index(combo_index) < 0

# --- CAPACIDADES DEFENSIVAS CONSULTADAS PELO MEDIADOR ---

func is_guard_broken_active() -> bool:
	# Se você já tem um estado Guard Broken, cheque aqui
	return get_state() == State.GUARD_BROKEN

func get_guard_absorb_cap() -> float:
	# Se já usa GuardProfile com 'defense_absorb_cap', exponha aqui
	# Prefiro assert para não mascarar nulo
	assert(_guard != null, "CombatController.get_guard_absorb_cap: GuardProfile nulo")
	var cap: float = _guard.defense_absorb_cap
	return cap

func get_finisher_cfg() -> AttackConfig:
	# Finisher do atacante quando alvo está quebrado
	assert(_guard != null, "CombatController.get_finisher_cfg: GuardProfile nulo")
	return _guard.finisher

# ===== Handlers de impacto (DEFENSOR) =====
func _on_defender_impact(cfg: AttackConfig, metrics: ImpactMetrics, result: int) -> void:
	# Log legível
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

	# Reações do lado DEFENSOR (apenas estados do próprio controlador)
	if result == ContactArbiter.DefenderResult.PARRY_SUCCESS:
		enter_parry_success()
		return

	if result == ContactArbiter.DefenderResult.FINISHER_HIT:
		# O dano de finisher será aplicado pelo Health listener; aqui só transição
		enter_broken_after_finisher()
		return

	# BLOCKED x DAMAGED
	var only_block: bool = metrics.absorbed > 0.0 and metrics.hp_damage <= 0.0
	if only_block:
		enter_guard_hit()
	else:
		if metrics.hp_damage > 0.0:
			enter_hit_react()
		else:
			# Nenhum dano e nenhuma absorção relevante → permanece como está
			pass


# ===== Handlers de impacto (ATACANTE) =====
func _on_attacker_impact(cfg: AttackConfig, feedback: int, metrics: ImpactMetrics) -> void:
	# Log legível
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

	# Reações do lado ATACANTE (somente no próprio controlador)
	if feedback == ContactArbiter.AttackerFeedback.ATTACK_PARRIED:	
		enter_parried()
		return

	if feedback == ContactArbiter.AttackerFeedback.FINISHER_CONFIRMED:
		start_finisher()
		return

func _on_stamina_emptied() -> void:
	# Conecte este handler no sinal da sua Stamina (ex.: stamina.emptied.connect(controller._on_stamina_emptied))
	enter_guard_broken()
