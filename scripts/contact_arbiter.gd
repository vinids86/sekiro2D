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
	_def_cc = _defender.get_node(^"CombatController") as CombatController
	_def_stamina = _defender.get_node(^"Stamina") as Stamina
	_def_health = _defender.get_node(^"Health") as Health
	assert(_def_cc != null, "ContactArbiter: CombatController do defensor não encontrado")
	assert(_def_stamina != null, "ContactArbiter: Stamina do defensor não encontrada")
	assert(_def_health != null, "ContactArbiter: Health do defensor não encontrada")

func resolve(cfg: AttackConfig) -> void:
	assert(cfg != null, "ContactArbiter.resolve: cfg nulo")
	
	var m: ImpactMetrics = ImpactMetrics.new()
	m.absorbed = 0.0
	m.hp_damage = 0.0
	m.attack_id = 0

	# --- LÓGICA DE REAÇÃO DA IA ---
	var def_ai_driver: EnemyAIDriver = _defender.get_node_or_null("EnemyAIDriver")
	if def_ai_driver != null:
		def_ai_driver._on_impact_imminent(cfg)
	
	# --- O FLUXO NORMAL CONTINUA DAQUI ---
	var parry_active: bool = _def_cc.is_parry_window()
	var dodge_active: bool = _def_cc.is_dodge_active()
	var autoblock_now: bool = _def_cc.is_autoblock_enabled_now()
	var guard_broken_now: bool = _def_cc.is_guard_broken_active()

	# ========== 1) DODGE ==========
	if dodge_active:
		emit_signal("defender_impact", cfg, m, DefenderResult.DODGED)
		emit_signal("attacker_impact", cfg, AttackerFeedback.WHIFFED, m)
		return

	# ========== 2) PARRY (do Jogador ou da IA, agora unificado) ==========
	var parryable: bool = bool(cfg.parryable)
	if parry_active and parryable:
		emit_signal("defender_impact", cfg, m, DefenderResult.PARRY_SUCCESS)
		emit_signal("attacker_impact", cfg, AttackerFeedback.ATTACK_PARRIED, m)
		return

	# ========== 3) FINISHER ==========
	if int(cfg.kind) == int(CombatTypes.AttackKind.FINISHER):
		assert(guard_broken_now, "Arbiter: FINISHER recebido mas o defensor NAO esta em GUARD_BROKEN.")
		var fin_dmg: float = float(cfg.damage)
		m.hp_damage = max(fin_dmg, 0.0)
		_def_health.damage(m.hp_damage)
		emit_signal("defender_impact", cfg, m, DefenderResult.FINISHER_HIT)
		emit_signal("attacker_impact", cfg, AttackerFeedback.HIT_CONFIRMED, m)
		return

	# ========== 4) GOLPES NORMAIS: Autoblock (Stamina) -> HP ==========
	var dmg: float = float(cfg.damage)
	if dmg <= 0.0:
		emit_signal("defender_impact", cfg, m, DefenderResult.BLOCKED)
		emit_signal("attacker_impact", cfg, AttackerFeedback.BLOCKED, m)
		return

	# Autoblock
	var emptied_now: bool = false
	if autoblock_now:
		var cap: float = _def_cc.get_guard_absorb_cap()
		var stamina_avail: float = _def_stamina.current
		var to_absorb = min(dmg, cap, stamina_avail)
		if to_absorb > 0.0:
			m.absorbed = to_absorb
			var prev_stamina: float = _def_stamina.current
			_def_stamina.set_current(prev_stamina - m.absorbed)
			if prev_stamina > 0.0 and _def_stamina.current <= 0.0:
				emptied_now = true
	
	# HP residual
	m.hp_damage = max(dmg - m.absorbed, 0.0)
	if m.hp_damage > 0.0:
		_def_health.damage(m.hp_damage)

	# ======= POISE =======
	var should_emit_poise_break: bool = false
	var guard_broke_now: bool = emptied_now or guard_broken_now
	if _def_cc.get_state() == CombatController.State.ATTACK and not guard_broke_now:
		var def_poise: float = _def_cc.get_effective_poise()
		var pb: float = float(cfg.poise_break)
		if pb > def_poise:
			should_emit_poise_break = true

	# ===== Emissão de Sinais de Resultado =====
	var def_res: int = DefenderResult.DAMAGED
	var atk_fb: int = AttackerFeedback.HIT_CONFIRMED
	if m.absorbed > 0.0 and m.hp_damage <= 0.0:
		def_res = DefenderResult.BLOCKED
		atk_fb = AttackerFeedback.BLOCKED

	emit_signal("defender_impact", cfg, m, def_res)
	emit_signal("attacker_impact", cfg, atk_fb, m)

	if emptied_now:
		emit_signal("defender_impact", cfg, m, DefenderResult.GUARD_BROKEN_ENTERED)
		emit_signal("attacker_impact", cfg, AttackerFeedback.GUARD_BROKEN_CONFIRMED, m)

	if should_emit_poise_break:
		emit_signal("defender_impact", cfg, m, DefenderResult.POISE_BREAK)
