extends Node
class_name CombatEventHub

signal parry_success(attacker: Node2D, defender: Node2D, cfg: AttackConfig)
signal guard_blocked(attacker: Node2D, defender: Node2D, cfg: AttackConfig, absorbed: int, hp_damage: int)
signal attack_windup(attacker: Node2D, cfg: AttackConfig, time_to_hit: float)
signal guard_broken(attacker: Node2D, defender: Node2D)
signal finisher_started(attacker: Node2D, defender: Node2D, cfg: AttackConfig)
signal finisher_hit(attacker: Node2D, defender: Node2D, cfg: AttackConfig, damage: float)

# Sinais opcionais (já deixo prontos; use se quiser reagir a fases)
signal attack_active(attacker: Node2D, cfg: AttackConfig)
signal attack_recover(attacker: Node2D, cfg: AttackConfig)
signal attack_finished(attacker: Node2D)

signal parry_started(defender: Node2D)
signal parry_window_open(defender: Node2D)
signal parry_window_close(defender: Node2D)
signal parry_finished(defender: Node2D)

signal dodge_started(actor: Node2D)
signal dodge_iframes_on(actor: Node2D)
signal dodge_iframes_off(actor: Node2D)
signal dodge_finished(actor: Node2D)

var _map_cc_to_root: Dictionary = {}  # CombatController -> Node2D (raiz do lutador)

func register_fighter(root: Node2D, cc: CombatController) -> void:
	assert(root != null, "CombatEventHub.register_fighter: root nulo")
	assert(cc != null, "CombatEventHub.register_fighter: controller nulo")
	_map_cc_to_root[cc] = root

	# Conecta eventos principais do Controller
	cc.state_entered.connect(Callable(self, "_on_state_entered").bind(cc), Object.CONNECT_DEFERRED)
	cc.state_exited.connect(Callable(self, "_on_state_exited").bind(cc), Object.CONNECT_DEFERRED)
	cc.phase_changed.connect(Callable(self, "_on_phase_changed").bind(cc), Object.CONNECT_DEFERRED)

func unregister_fighter(cc: CombatController) -> void:
	if _map_cc_to_root.has(cc):
		_map_cc_to_root.erase(cc)
	# Se quiser desconectar explicitamente, faça aqui (opcional).

func _on_state_entered(state: int, cfg: AttackConfig, cc: CombatController) -> void:
	var root: Node2D = _map_cc_to_root.get(cc) as Node2D
	if root == null:
		return

	if state == CombatController.State.ATTACK:
		# Ataque normal: ainda calculamos o windup no enter
		# Combo dirigido por timeline pode entrar sem cfg (cfg == null) — nesse caso, não emitimos windup aqui.
		if cfg != null:
			var time_to_hit: float = maxf(cfg.startup, 0.0)
			attack_windup.emit(root, cfg, time_to_hit)
		# Se for combo (cfg == null), deixe a timeline mandar nas janelas;
		# o Hub continuará reagindo em _on_phase_changed (ACTIVE/RECOVER).

	elif state == CombatController.State.PARRY:
		parry_started.emit(root)

	elif state == CombatController.State.DODGE:
		dodge_started.emit(root)

func _on_state_exited(state: int, _cfg: AttackConfig, cc: CombatController) -> void:
	var root: Node2D = _map_cc_to_root.get(cc) as Node2D
	if root == null:
		return

	if state == CombatController.State.ATTACK:
		attack_finished.emit(root)
	elif state == CombatController.State.PARRY:
		parry_finished.emit(root)
	elif state == CombatController.State.DODGE:
		dodge_finished.emit(root)

# Reage às fases genéricas reportadas pelo Controller (ATTACK, PARRY, DODGE)
func _on_phase_changed(phase: int, cfg: AttackConfig, cc: CombatController) -> void:
	var root: Node2D = _map_cc_to_root.get(cc) as Node2D
	if root == null:
		return

	var st: int = cc.get_state()

	# ATTACK substitui antigos STARTUP/HIT/RECOVER
	if st == CombatController.State.ATTACK:
		if phase == CombatController.Phase.ACTIVE:
			attack_active.emit(root, cfg)
		elif phase == CombatController.Phase.RECOVER:
			attack_recover.emit(root, cfg)

	# PARRY com fases genéricas (janela ativa em ACTIVE)
	elif st == CombatController.State.PARRY:
		if phase == CombatController.Phase.ACTIVE:
			parry_window_open.emit(root)
		elif phase == CombatController.Phase.RECOVER:
			parry_window_close.emit(root)

	# DODGE (i-frames em ACTIVE)
	elif st == CombatController.State.DODGE:
		if phase == CombatController.Phase.ACTIVE:
			dodge_iframes_on.emit(root)
		elif phase == CombatController.Phase.RECOVER:
			dodge_iframes_off.emit(root)

# Publicadores existentes (mantidos)
func publish_parry_success(attacker: Node2D, defender: Node2D, cfg: AttackConfig) -> void:
	assert(attacker != null and defender != null and cfg != null)
	parry_success.emit(attacker, defender, cfg)

func publish_guard_blocked(attacker: Node2D, defender: Node2D, cfg: AttackConfig, absorbed: int, hp_damage: int) -> void:
	assert(attacker != null and defender != null and cfg != null)
	guard_blocked.emit(attacker, defender, cfg, absorbed, hp_damage)

func publish_guard_broken(attacker: Node2D, defender: Node2D) -> void:
	if attacker == null or defender == null:
		push_warning("[Hub] guard_broken com atacante/defensor nulo.")
	emit_signal("guard_broken", attacker, defender)

func publish_finisher_started(attacker: Node2D, defender: Node2D, cfg: AttackConfig) -> void:
	if attacker == null or defender == null or cfg == null:
		push_warning("[Hub] finisher_started com parâmetro nulo.")
	emit_signal("finisher_started", attacker, defender, cfg)

func publish_finisher_hit(attacker: Node2D, defender: Node2D, cfg: AttackConfig, damage: float) -> void:
	if attacker == null or defender == null or cfg == null:
		push_warning("[Hub] finisher_hit com parâmetro nulo.")
	emit_signal("finisher_hit", attacker, defender, cfg, maxf(damage, 0.0))
