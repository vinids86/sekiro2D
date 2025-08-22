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

	# 1) Parry primeiro
	if _cc.is_parry_window():
		_cc.enter_parry_success()
		_hub.publish_parry_success(attacker, defender, cfg)
		return

	# 2) Guarda (auto-block com cap absoluto por golpe)
	var dmg: float = float(cfg.damage)
	if dmg <= 0.0:
		return

	# Cap absoluto do perfil de guarda (1:1 com stamina)
	var cap_from_guard: float = maxf(0.0, _guard.defense_absorb_cap)
	var stamina_avail: float = _stamina.current

	# Quanto PODE absorver nesse golpe
	var to_absorb: float = dmg
	if cap_from_guard < to_absorb:
		to_absorb = cap_from_guard
	if stamina_avail < to_absorb:
		to_absorb = stamina_avail

	var absorbed: float = 0.0
	if to_absorb > 0.0:
		absorbed = _stamina.consume(to_absorb) # retorna 0..to_absorb

	var hp_damage: float = dmg - absorbed
	if hp_damage < 0.0:
		hp_damage = 0.0

	if absorbed > 0.0:
		# Dano residual na vida (se sobrar)
		if hp_damage > 0.0:
			_health.damage(hp_damage)

		# Feedback de block + evento
		_cc.enter_guard_hit()
		# Se seu Hub espera ints, ajuste aqui para roundi(...)
		_hub.publish_guard_blocked(attacker, defender, cfg, absorbed, hp_damage)
		return

	# 3) Sem absorção: dano normal + HIT_REACT
	_health.damage(dmg)
	_cc.enter_hit_react()
