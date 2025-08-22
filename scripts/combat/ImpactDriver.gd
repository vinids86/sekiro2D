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

	# 1) Parry: ignora absorção/chip/HP; apenas sinaliza
	if _cc.is_parry_window():
		_cc.enter_parry_success()
		_hub.publish_parry_success(attacker, defender, cfg) # supondo que já existe no seu Hub
		return

	# 2) FINISHER: dano direto de HP + pós-finisher + reset de stamina (novo "round")
	if cfg.is_finisher:
		var fin_dmg: float = float(cfg.damage)
		if fin_dmg > 0.0:
			_health.damage(fin_dmg)

		_cc.enter_broken_after_finisher()

		# Reset de stamina dos dois (decisão atual: sempre 100% após finisher)
		_stamina.set_current(_stamina.maximum)
		if attacker != null and attacker.has_node(^"Stamina"):
			var atk_stamina: Stamina = attacker.get_node(^"Stamina") as Stamina
			if atk_stamina != null:
				atk_stamina.set_current(atk_stamina.maximum)

		_hub.publish_finisher_hit(attacker, defender, cfg, fin_dmg)
		return

	# 3) Golpe normal: absorção até o cap; overflow vira chip de HP
	var dmg: float = float(cfg.damage)
	if dmg <= 0.0:
		return

	var cap_from_guard: float = maxf(0.0, _guard.defense_absorb_cap)
	var stamina_avail: float = _stamina.current

	var to_absorb: float = dmg
	if cap_from_guard < to_absorb:
		to_absorb = cap_from_guard
	if stamina_avail < to_absorb:
		to_absorb = stamina_avail

	var absorbed: float = 0.0
	if to_absorb > 0.0:
		absorbed = _stamina.consume(to_absorb)

	var hp_damage: float = dmg - absorbed
	if hp_damage < 0.0:
		hp_damage = 0.0
	if hp_damage > 0.0:
		_health.damage(hp_damage)

	if absorbed > 0.0:
		_cc.enter_guard_hit()
		_hub.publish_guard_blocked(attacker, defender, cfg, absorbed, hp_damage) # já existia

	# 4) Zerou stamina? → GUARD_BROKEN + FINISHER do atacante + publishes
	if _stamina.is_empty():
		_cc.enter_guard_broken()
		_hub.publish_guard_broken(attacker, defender)

		if attacker != null and attacker.has_node(^"CombatController"):
			var atk_cc: CombatController = attacker.get_node(^"CombatController") as CombatController
			if atk_cc != null and _guard.finisher != null:
				atk_cc.start_finisher()
				_hub.publish_finisher_started(attacker, defender, _guard.finisher)
		return

	# 5) Sem absorção e sem broken → reação normal
	if absorbed <= 0.0 and hp_damage > 0.0:
		_cc.enter_hit_react()
