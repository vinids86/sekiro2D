extends Node
class_name ImpactDriver

var _hurtbox: Hurtbox
var _health: Health
var _stamina: Stamina
var _cc: CombatController
var _hub: CombatEventHub
var _guard: GuardProfile

var _wired: bool = false

func setup(
		hurtbox: Hurtbox,
		health: Health,
		stamina: Stamina,
		controller: CombatController,
		hub: CombatEventHub,
		guard_profile: GuardProfile
	) -> void:
	_hurtbox = hurtbox
	_health = health
	_stamina = stamina
	_cc = controller
	_hub = hub
	_guard = guard_profile

	assert(_hurtbox != null, "Hurtbox nulo no ImpactDriver")
	assert(_health != null, "Health nulo no ImpactDriver")
	assert(_stamina != null, "Stamina nulo no ImpactDriver")
	assert(_cc != null, "CombatController nulo no ImpactDriver")
	assert(_hub != null, "CombatEventHub nulo no ImpactDriver")
	assert(_guard != null, "GuardProfile nulo no ImpactDriver")

	if _wired:
		return
	_wired = true

	# Conectar fora do callback de física
	_hurtbox.contact.connect(_on_contact, Object.CONNECT_DEFERRED)

func _on_contact(attacker: Node2D, cfg: AttackConfig, _hitbox: AttackHitbox) -> void:
	var defender: Node2D = _hurtbox.get_parent() as Node2D

	# 1) Parry?
	if _cc.is_parry_window():
		_cc.enter_parry_success()
		_hub.publish_parry_success(attacker, defender, cfg)
		return

	# 2) Guard (auto-block com defesa variável)
	var dmg_f: float = float(cfg.damage)
	var defense_power: float = float(_guard.defense_power)
	if defense_power < 0.0:
		defense_power = 0.0

	var s_cur: float = _stamina.get_current()
	if s_cur < 0.0:
		s_cur = 0.0

	# quanto *pode* ser absorvido (1:1 stamina:dano), limitado por poder e stamina atual
	var absorb_cap: float = dmg_f
	if defense_power < absorb_cap:
		absorb_cap = defense_power
	if s_cur < absorb_cap:
		absorb_cap = s_cur

	var absorbed: float = _stamina.consume(absorb_cap)
	if absorbed < 0.0:
		absorbed = 0.0

	var hp_damage_f: float = dmg_f - absorbed

	if absorbed > 0.0:
		# aplica dano restante (geralmente 0 em golpes leves)
		var hp_dmg_int: int = int(round(hp_damage_f))
		if hp_dmg_int > 0:
			_health.apply_damage(hp_dmg_int, attacker)

		# feedback de guarda + publish no hub
		_cc.enter_guard_hit()
		_hub.publish_guard_blocked(attacker, defender, cfg, int(round(absorbed)), hp_dmg_int)
		return

	# 3) Sem absorção: dano normal + HIT_REACT
	_health.apply_damage(int(dmg_f), attacker)
	_cc.enter_hit_react()
