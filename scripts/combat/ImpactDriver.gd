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

	# Injeta callables de custo da esquiva no Controller (Controller valida ANTES de trocar de estado)
	_cc.bind_dodge_cost_handlers(_can_pay_dodge, _consume_dodge)

	if _wired:
		return
	_wired = true

	# Conectar fora do callback de física
	_hurtbox.contact.connect(_on_contact, Object.CONNECT_DEFERRED)


# --------- Callables para custo da esquiva (usados pelo Controller) ----------
func _can_pay_dodge(cost: float) -> bool:
	if cost <= 0.0:
		return true
	return _stamina.current >= cost

func _consume_dodge(cost: float) -> void:
	if cost <= 0.0:
		return
	_stamina.consume(cost)


# ---------------------------- RESOLUÇÃO DE IMPACTO ----------------------------
func _on_contact(attacker: Node2D, cfg: AttackConfig, _hitbox: AttackHitbox) -> void:
	var defender: Node2D = _hurtbox.get_parent() as Node2D

	# 0) DODGE ativo com direção correta → ignora hit
	if _cc.is_dodge_active():
		var req: int = int(cfg.required_dodge_dir)  # 0 = NEUTRAL, 1 = DOWN (hoje usamos DOWN para heavy_up)
		var dir: int = _cc.get_last_dodge_dir()
		var ok_dir: bool = false
		if req == 0:
			ok_dir = true
		else:
			if dir == req:
				ok_dir = true
		if ok_dir:
			# Se quiser publicar um evento de dodge-success, dá pra adicionar no hub aqui.
			return

	# 1) FINISHER: prioridade máxima, dano direto no HP + pós-finisher + reset de stamina (imparryável)
	if cfg.is_finisher:
		var fin_dmg: float = float(cfg.damage)
		if fin_dmg > 0.0:
			_health.damage(fin_dmg)

		_cc.enter_broken_after_finisher()

		# Reset de stamina dos dois
		_stamina.set_current(_stamina.maximum)
		if attacker != null and attacker.has_node(^"Stamina"):
			var atk_stamina: Stamina = attacker.get_node(^"Stamina") as Stamina
			if atk_stamina != null:
				atk_stamina.set_current(atk_stamina.maximum)

		_hub.publish_finisher_hit(attacker, defender, cfg, fin_dmg)
		return

	# 2) Parry window (cobre PARRY_STARTUP e COMBO_PARRY) — mas NÃO vale contra heavy
	if _cc.is_parry_window():
		var atk_cc: CombatController = null
		if attacker != null and attacker.has_node(^"CombatController"):
			atk_cc = attacker.get_node(^"CombatController") as CombatController
		var attacker_state: int = -1
		if atk_cc != null:
			attacker_state = atk_cc.get_state()
		var is_heavy_attack: bool = (attacker_state == CombatController.State.HEAVY_STARTUP) \
			or (attacker_state == CombatController.State.HEAVY_HIT)

		if not is_heavy_attack:
			_cc.enter_parry_success()
			_hub.publish_parry_success(attacker, defender, cfg)
			return
		# Heavy não-parryável: cai para o fluxo normal de dano

	# 3) Fluxo normal: absorção condicionada pela política de autoblock do estado; overflow vira HP
	var dmg: float = float(cfg.damage)
	if dmg <= 0.0:
		return

	var absorbed: float = 0.0
	var hp_damage: float = 0.0

	var autoblock_now: bool = _cc.is_autoblock_enabled_now()
	if autoblock_now:
		var cap_from_guard: float = maxf(0.0, _guard.defense_absorb_cap)
		var stamina_avail: float = _stamina.current

		var to_absorb: float = dmg
		if cap_from_guard < to_absorb:
			to_absorb = cap_from_guard
		if stamina_avail < to_absorb:
			to_absorb = stamina_avail

		if to_absorb > 0.0:
			absorbed = _stamina.consume(to_absorb)
	else:
		absorbed = 0.0

	hp_damage = dmg - absorbed
	if hp_damage < 0.0:
		hp_damage = 0.0
	if hp_damage > 0.0:
		_health.damage(hp_damage)

	if absorbed > 0.0:
		_cc.enter_guard_hit()
		_hub.publish_guard_blocked(attacker, defender, cfg, absorbed, hp_damage)

	# 4) Zerou stamina? → GUARD_BROKEN + FINISHER do atacante + publishes
	if _stamina.is_empty():
		_cc.enter_guard_broken()
		_hub.publish_guard_broken(attacker, defender)

		if attacker != null and attacker.has_node(^"CombatController"):
			var atk_cc2: CombatController = attacker.get_node(^"CombatController") as CombatController
			if atk_cc2 != null and _guard.finisher != null:
				atk_cc2.start_finisher()
				_hub.publish_finisher_started(attacker, defender, _guard.finisher)
		return

	# 5) Sem absorção e com dano → reação normal
	if absorbed <= 0.0 and hp_damage > 0.0:
		_cc.enter_hit_react()
