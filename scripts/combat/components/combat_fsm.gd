extends RefCounted
class_name CombatFSM

# Sinal: usa int para máxima compatibilidade nas conexões (Player/Enemy)
signal state_changed(state: int, attack_direction: Vector2)

# Estado atual espelhado do controller
var current_state: CombatTypes.CombatState = CombatTypes.CombatState.IDLE
var state_timer: float = 0.0

# Referências e callbacks do controller
var _controller: CombatController
var _debug_logs: bool = false
var _on_enter_cb: Callable
var _on_exit_cb: Callable
var _can_auto_advance_cb: Callable
var _auto_advance_cb: Callable

# Tabela ÚNICA de transições
var transitions: Dictionary = {
	CombatTypes.CombatState.IDLE:             [CombatTypes.CombatState.STARTUP, CombatTypes.CombatState.PARRY_ACTIVE, CombatTypes.CombatState.STUNNED, CombatTypes.CombatState.GUARD_BROKEN, CombatTypes.CombatState.DODGE_STARTUP],
	CombatTypes.CombatState.STARTUP:          [CombatTypes.CombatState.ATTACKING, CombatTypes.CombatState.PARRY_ACTIVE, CombatTypes.CombatState.STUNNED, CombatTypes.CombatState.RECOVERING, CombatTypes.CombatState.GUARD_BROKEN],
	CombatTypes.CombatState.ATTACKING:        [CombatTypes.CombatState.RECOVERING, CombatTypes.CombatState.STUNNED, CombatTypes.CombatState.PARRY_ACTIVE, CombatTypes.CombatState.GUARD_BROKEN],
	CombatTypes.CombatState.RECOVERING:       [CombatTypes.CombatState.IDLE, CombatTypes.CombatState.STUNNED, CombatTypes.CombatState.STARTUP, CombatTypes.CombatState.GUARD_BROKEN],
	CombatTypes.CombatState.PARRY_ACTIVE:     [CombatTypes.CombatState.PARRY_SUCCESS, CombatTypes.CombatState.IDLE, CombatTypes.CombatState.STUNNED, CombatTypes.CombatState.RECOVERING, CombatTypes.CombatState.GUARD_BROKEN],
	CombatTypes.CombatState.PARRY_SUCCESS:    [CombatTypes.CombatState.IDLE, CombatTypes.CombatState.STUNNED, CombatTypes.CombatState.GUARD_BROKEN],
	CombatTypes.CombatState.STUNNED:          [CombatTypes.CombatState.IDLE, CombatTypes.CombatState.STUNNED, CombatTypes.CombatState.PARRY_ACTIVE, CombatTypes.CombatState.GUARD_BROKEN],
	CombatTypes.CombatState.GUARD_BROKEN:     [CombatTypes.CombatState.IDLE, CombatTypes.CombatState.RECOVERING],
	CombatTypes.CombatState.DODGE_STARTUP:    [CombatTypes.CombatState.DODGE_ACTIVE],
	CombatTypes.CombatState.DODGE_ACTIVE:     [CombatTypes.CombatState.DODGE_RECOVERING],
	CombatTypes.CombatState.DODGE_RECOVERING: [CombatTypes.CombatState.IDLE],
}

# ---------- Setup ----------
func setup(
	controller: CombatController,
	debug_logs: bool,
	on_enter_cb: Callable,
	on_exit_cb: Callable,
	can_auto_advance_cb: Callable,
	auto_advance_cb: Callable
) -> void:
	_controller = controller
	_debug_logs = debug_logs
	_on_enter_cb = on_enter_cb
	_on_exit_cb = on_exit_cb
	_can_auto_advance_cb = can_auto_advance_cb
	_auto_advance_cb = auto_advance_cb

# Sincroniza estado inicial com o controller
func sync_from_controller(current: CombatTypes.CombatState) -> void:
	current_state = current

# ---------- API de transição ----------
func can_transition_from(from_state: CombatTypes.CombatState, to_state: CombatTypes.CombatState) -> bool:
	var allowed: Array = transitions.get(from_state, [])
	return allowed.has(to_state)

# (opcional, se você já usava esse nome)
func can_transition(to_state: CombatTypes.CombatState) -> bool:
	return can_transition_from(current_state, to_state)

func change_state(new_state: CombatTypes.CombatState) -> void:
	# Sair do estado atual
	if _on_exit_cb.is_valid():
		_on_exit_cb.call(current_state)

	# Entrar no novo
	current_state = new_state
	if _on_enter_cb.is_valid():
		_on_enter_cb.call(new_state)

	# Definir direção emitida no sinal:
	# Para DODGE_* emitimos ZERO; caso contrário, usamos a direção atual do ataque no controller.
	var emit_dir: Vector2 = Vector2.ZERO
	var is_dodge: bool = (
		new_state == CombatTypes.CombatState.DODGE_STARTUP
		or new_state == CombatTypes.CombatState.DODGE_ACTIVE
		or new_state == CombatTypes.CombatState.DODGE_RECOVERING
	)
	if not is_dodge and _controller != null:
		emit_dir = _controller.current_attack_direction

	state_changed.emit(int(new_state), emit_dir)

# ---------- Tick ----------
func tick(delta: float) -> void:
	if state_timer > 0.0:
		state_timer -= delta
		if state_timer <= 0.0 and _can_auto_advance_cb.is_valid() and _auto_advance_cb.is_valid():
			if _can_auto_advance_cb.call():
				_auto_advance_cb.call()
