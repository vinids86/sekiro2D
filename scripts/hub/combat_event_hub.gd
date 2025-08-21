extends Node
class_name CombatEventHub

signal parry_success(attacker: Node2D, defender: Node2D, cfg: AttackConfig)
signal guard_blocked(attacker: Node2D, defender: Node2D, cfg: AttackConfig, absorbed: int, hp_damage: int)
signal attack_windup(attacker: Node2D, cfg: AttackConfig, time_to_hit: float)

var _map_cc_to_root: Dictionary = {}  # CombatController -> Node2D (raiz do lutador)

func register_fighter(root: Node2D, cc: CombatController) -> void:
	assert(root != null, "CombatEventHub.register_fighter: root nulo")
	assert(cc != null, "CombatEventHub.register_fighter: controller nulo")
	_map_cc_to_root[cc] = root
	cc.state_entered.connect(Callable(self, "_on_state_entered").bind(cc), Object.CONNECT_DEFERRED)

func unregister_fighter(cc: CombatController) -> void:
	if _map_cc_to_root.has(cc):
		_map_cc_to_root.erase(cc)
		# desconectar se quiser (opcional): cc.state_entered.disconnect(...)

func _on_state_entered(state: int, cfg: AttackConfig, cc: CombatController) -> void:
	if state == CombatController.State.STARTUP:
		var root: Node2D = _map_cc_to_root[cc] as Node2D
		assert(cfg != null, "attack_windup sem AttackConfig")

		var time_to_hit: float = maxf(cfg.startup, 0.0)
		attack_windup.emit(root, cfg, time_to_hit)

func publish_parry_success(attacker: Node2D, defender: Node2D, cfg: AttackConfig) -> void:
	assert(attacker != null and defender != null and cfg != null)
	parry_success.emit(attacker, defender, cfg)

func publish_guard_blocked(attacker: Node2D, defender: Node2D, cfg: AttackConfig, absorbed: int, hp_damage: int) -> void:
	assert(attacker != null and defender != null and cfg != null)
	guard_blocked.emit(attacker, defender, cfg, absorbed, hp_damage)
