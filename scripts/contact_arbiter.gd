extends Node
class_name ContactArbiter

signal defender_impact(cfg: AttackConfig, metrics: ImpactMetrics, result: int)
signal attacker_impact(cfg: AttackConfig, feedback: int, metrics: ImpactMetrics)

enum DefenderResult { DODGED, PARRY_SUCCESS, BLOCKED, DAMAGED, FINISHER_HIT, GUARD_BROKEN_ENTERED, POISE_BREAK }
enum AttackerFeedback { WHIFFED, ATTACK_PARRIED, BLOCKED, HIT_CONFIRMED, FINISHER_CONFIRMED, GUARD_BROKEN_CONFIRMED }

var _attacker: Node2D
var _defender: Node2D
var _def_cc: CombatController
var _def_stamina: Stamina
var _def_health: Health

func setup(attacker_root: Node2D, defender_root: Node2D) -> void:
	_attacker = attacker_root
	_defender = defender_root

	# Dependências do defensor (autoridade local)
	_def_cc = _defender.get_node(^"CombatController") as CombatController
	_def_stamina = _defender.get_node(^"Stamina") as Stamina
	_def_health = _defender.get_node(^"Health") as Health

	assert(_def_cc != null, "ContactArbiter: CombatController do defensor não encontrado")
	assert(_def_stamina != null, "ContactArbiter: Stamina do defensor não encontrada")
	assert(_def_health != null, "ContactArbiter: Health do defensor não encontrada")

func resolve(cfg: AttackConfig) -> void:
	assert(cfg != null, "ContactArbiter.resolve: cfg nulo")

	# ===== Cabeçalho do impacto =====
	var pf: int = Engine.get_physics_frames()
	var ms: int = Time.get_ticks_msec()

	# ----- Contexto DEFENSOR -----
	var parry_active: bool = _def_cc.is_parry_window()
	var dodge_active: bool = _def_cc.is_dodge_active()
	var autoblock_now: bool = _def_cc.is_autoblock_enabled_now()
	var guard_broken_now: bool = _def_cc.is_guard_broken_active()
	var stamina_now: float = _def_stamina.current
	var cap_ctx: float = 0.0
	if _def_cc != null:
		cap_ctx = _def_cc.get_guard_absorb_cap()

	print("[ARB@", pf, ":", ms, "] start kind=", int(cfg.kind),
		" dmg=", float(cfg.damage),
		" parryable=", bool(cfg.parryable),
	)
	print("[ARB@", pf, "] ctx parry=", parry_active,
		" dodge=", dodge_active,
		" autoblock_now=", autoblock_now,
		" guard_broken_now=", guard_broken_now,
		" stamina=", stamina_now,
		" cap=", cap_ctx)

	# ----- Métricas -----
	var m: ImpactMetrics = ImpactMetrics.new()
	m.absorbed = 0.0
	m.hp_damage = 0.0
	m.attack_id = 0

	# ========== 1) DODGE ==========
	if dodge_active:
		emit_signal("defender_impact", cfg, m, DefenderResult.DODGED)
		emit_signal("attacker_impact", cfg, AttackerFeedback.WHIFFED, m)
		return

	# ========== 2) PARRY ==========
	var parryable: bool = bool(cfg.parryable)
	if parry_active and parryable:
		print("[ARB@", pf, "] branch=PARRY parryable=true -> emit DEF=PARRY_SUCCESS ATK=ATTACK_PARRIED")
		emit_signal("defender_impact", cfg, m, DefenderResult.PARRY_SUCCESS)
		emit_signal("attacker_impact", cfg, AttackerFeedback.ATTACK_PARRIED, m)
		return

	# ========== 3) FINISHER ==========
	if int(cfg.kind) == int(CombatTypes.AttackKind.FINISHER):
		print("[ARB@", pf, "] branch=FINISHER guard_broken_now=", guard_broken_now, " (ASSERT esperado=true)")
		assert(guard_broken_now, "Arbiter: FINISHER recebido mas o defensor NAO esta em GUARD_BROKEN. Ver fluxo do atacante.")

		var fin_dmg: float = float(cfg.damage)
		if fin_dmg < 0.0:
			fin_dmg = 0.0
		m.hp_damage = fin_dmg
		print("[ARB@", pf, "] finisher dmg=", fin_dmg, " -> aplicar HP e emitir FINISHER_HIT/HIT_CONFIRMED")

		_def_health.damage(m.hp_damage)

		print("[ARB@", pf, "] emit DEF=FINISHER_HIT  ATK=HIT_CONFIRMED")
		emit_signal("defender_impact", cfg, m, DefenderResult.FINISHER_HIT)
		emit_signal("attacker_impact", cfg, AttackerFeedback.HIT_CONFIRMED, m)
		return

	# ========== 4) GOLPES NORMAIS: Autoblock (Stamina) -> HP ==========
	var dmg: float = float(cfg.damage)
	print("[ARB@", pf, "] branch=NORMAL base_dmg=", dmg)

	if dmg <= 0.0:
		print("[ARB@", pf, "] dmg<=0 -> emit DEF=BLOCKED ATK=BLOCKED (sem possibilidade de guard_broken)")
		emit_signal("defender_impact", cfg, m, DefenderResult.BLOCKED)
		emit_signal("attacker_impact", cfg, AttackerFeedback.BLOCKED, m)
		return

	# Autoblock
	var cap: float = 0.0
	var stamina_avail: float = _def_stamina.current
	var to_absorb: float = 0.0

	if autoblock_now:
		cap = _def_cc.get_guard_absorb_cap()
		if cap < 0.0:
			cap = 0.0

		to_absorb = dmg
		if cap < to_absorb:
			to_absorb = cap
		if stamina_avail < to_absorb:
			to_absorb = stamina_avail

		if to_absorb > 0.0:
			m.absorbed = to_absorb

	print("[ARB@", pf, "] autoblock auto=", autoblock_now,
		" cap=", cap,
		" sta_avail=", stamina_avail,
		" to_absorb=", to_absorb,
		" absorbed=", m.absorbed)

	# Aplica Stamina (silencioso) e detecta transição >0 -> 0
	var emptied_now: bool = false
	if m.absorbed > 0.0:
		var prev: float = _def_stamina.current
		var next: float = prev - m.absorbed
		if next < 0.0:
			next = 0.0
		_def_stamina.set_current(next)
		if prev > 0.0 and next <= 0.0:
			emptied_now = true
		print("[ARB@", pf, "] stamina prev=", prev, " next=", next, " emptied_now=", emptied_now)
	else:
		print("[ARB@", pf, "] stamina unchanged (absorbed=0.0) -> emptied_now=false")

	print("[ARB@", pf, "] stamina_now=", _def_stamina.current)

	# HP residual
	var hp_left: float = dmg - m.absorbed
	if hp_left < 0.0:
		hp_left = 0.0
	m.hp_damage = hp_left
	print("[ARB@", pf, "] hp_left=", hp_left, " -> m.hp_damage=", m.hp_damage)

	# Aplicar HP
	if m.hp_damage > 0.0:
		_def_health.damage(m.hp_damage)

	# ======= POISE: calcular ANTES dos sinais base, mas emitir depois =======
	var should_emit_poise_break: bool = false
	var def_is_attacking: bool = _def_cc.get_state() == CombatController.State.ATTACK
	# Se quebrou a guarda agora ou já estava quebrado, poise não se aplica.
	var guard_broke_now: bool = emptied_now or guard_broken_now

	if def_is_attacking and not guard_broke_now:
		var def_poise: float = _def_cc.get_effective_poise()
		var pb: float = float(cfg.poise_break)
		if pb > def_poise:
			should_emit_poise_break = true
		print("[ARB@", pf, "] poise_check: def_is_attacking=", def_is_attacking, " def_poise=", def_poise, " pb=", pb, " -> break?", should_emit_poise_break)
	else:
		print("[ARB@", pf, "] poise_check: skipped (attacking=", def_is_attacking, ", guard_broke_now=", guard_broke_now, ")")

	# ===== Resultado base (para feedback/UI) =====
	var def_res: int = DefenderResult.DAMAGED
	var atk_fb: int = AttackerFeedback.HIT_CONFIRMED
	var only_block: bool = m.absorbed > 0.0 and m.hp_damage <= 0.0
	if only_block:
		def_res = DefenderResult.BLOCKED
		atk_fb = AttackerFeedback.BLOCKED

	print("[ARB@", pf, "] emit base -> DEF=", def_res, " ATK=", atk_fb, " only_block=", only_block)
	emit_signal("defender_impact", cfg, m, def_res)
	emit_signal("attacker_impact", cfg, atk_fb, m)

	# ===== Guard Broken no mesmo hit =====
	print("[ARB@", pf, "] check guard_broken: emptied_now=", emptied_now, " guard_broken_pre=", guard_broken_now)
	if emptied_now:
		print("[ARB@", pf, "] emit guard_broken -> DEF=GUARD_BROKEN_ENTERED ATK=GUARD_BROKEN_CONFIRMED")
		emit_signal("defender_impact", cfg, m, DefenderResult.GUARD_BROKEN_ENTERED)
		emit_signal("attacker_impact", cfg, AttackerFeedback.GUARD_BROKEN_CONFIRMED, m)

	# ===== Emissão do POISE_BREAK (se aplicável) =====
	if should_emit_poise_break:
		print("[ARB@", pf, "] emit POISE_BREAK")
		emit_signal("defender_impact", cfg, m, DefenderResult.POISE_BREAK)
