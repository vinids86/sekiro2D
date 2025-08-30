extends Node
class_name ContactArbiter

signal defender_impact(cfg: AttackConfig, metrics: ImpactMetrics, result: int)
signal attacker_impact(cfg: AttackConfig, feedback: int, metrics: ImpactMetrics)

enum DefenderResult { DODGED, PARRY_SUCCESS, BLOCKED, DAMAGED, FINISHER_HIT }
enum AttackerFeedback { WHIFFED, ATTACK_PARRIED, BLOCKED, HIT_CONFIRMED, FINISHER_CONFIRMED }

var _attacker: Node2D
var _defender: Node2D
var _def_cc: CombatController
var _def_stamina: Stamina

func setup(attacker_root: Node2D, defender_root: Node2D) -> void:
	_attacker = attacker_root
	_defender = defender_root

	# Dependências do defensor (autoridade local)
	_def_cc = _defender.get_node(^"CombatController") as CombatController
	_def_stamina = _defender.get_node(^"Stamina") as Stamina

	assert(_def_cc != null, "ContactArbiter: CombatController do defensor não encontrado")
	assert(_def_stamina != null, "ContactArbiter: Stamina do defensor não encontrada")

func resolve(cfg: AttackConfig) -> void:
	assert(cfg != null, "ContactArbiter.resolve: cfg nulo")

	# ----- Capacidades / estado atual do DEFENSOR -----
	var parry_active: bool = _def_cc.is_parry_window()  # ou is_parry_active() se você já tiver
	var dodge_active: bool = _def_cc.is_dodge_active()
	var autoblock_now: bool = _def_cc.is_autoblock_enabled_now()
	var guard_broken_now: bool = _def_cc.is_guard_broken_active()

	# ----- Métricas de saída (o aplicador é quem consome/causa dano) -----
	var m: ImpactMetrics = ImpactMetrics.new()
	m.absorbed = 0.0
	m.hp_damage = 0.0
	m.attack_id = 0  # opcional para dedupe/telemetria

	# ========== 1) DODGE ==========
	if dodge_active:
		var req: int = int(cfg.required_dodge_dir)  # 0 = NEUTRAL (qualquer), >0 = direção específica
		var last: int = _def_cc.get_last_dodge_dir()
		var ok_dir: bool = false
		if req == 0:
			ok_dir = true
		else:
			if last == req:
				ok_dir = true
		if ok_dir:
			emit_signal("defender_impact", cfg, m, DefenderResult.DODGED)
			emit_signal("attacker_impact", cfg, AttackerFeedback.WHIFFED, m)
			return

	# ========== 2) PROMOÇÃO PARA FINISHER (defensor já está guard broken) ==========
	# TODO dano vem do ataque não do defensor
	if guard_broken_now:
		var finisher_cfg: AttackConfig = _def_cc.get_finisher_cfg()
		var fin_dmg: float = 0.0
		if finisher_cfg != null:
			fin_dmg = float(finisher_cfg.damage)
		m.absorbed = 0.0
		m.hp_damage = fin_dmg

		emit_signal("defender_impact", cfg, m, DefenderResult.FINISHER_HIT)
		emit_signal("attacker_impact", cfg, AttackerFeedback.FINISHER_CONFIRMED, m)
		return

	# ========== 3) PARRY ==========
	var parryable: bool = bool(cfg.parryable)
	print("parry_active: ", parry_active)
	print("parryable: ", parryable)
	if parry_active and parryable:
		emit_signal("defender_impact", cfg, m, DefenderResult.PARRY_SUCCESS)
		if cfg.kind != CombatTypes.AttackKind.COMBO:
			emit_signal("attacker_impact", cfg, AttackerFeedback.ATTACK_PARRIED, m)
		return

	# ========== 4) BLOQUEIO AUTOMÁTICO / DANO NORMAL ==========
	var dmg: float = float(cfg.damage)
	if dmg <= 0.0:
		# Sem dano configurado: reporta como bloqueado (neutro)
		emit_signal("defender_impact", cfg, m, DefenderResult.BLOCKED)
		emit_signal("attacker_impact", cfg, AttackerFeedback.BLOCKED, m)
		return

	if autoblock_now:
		var cap: float = _def_cc.get_guard_absorb_cap()
		if cap < 0.0:
			cap = 0.0

		var stamina_avail: float = _def_stamina.current
		var to_absorb: float = dmg
		if cap < to_absorb:
			to_absorb = cap
		if stamina_avail < to_absorb:
			to_absorb = stamina_avail

		if to_absorb > 0.0:
			m.absorbed = to_absorb

	# Dano restante em HP (Stamina é quem decide quebrou/zerou via evento próprio)
	var hp_left: float = dmg - m.absorbed
	if hp_left < 0.0:
		hp_left = 0.0
	m.hp_damage = hp_left

	var def_res: int = DefenderResult.DAMAGED
	var atk_fb: int = AttackerFeedback.HIT_CONFIRMED
	var only_block: bool = m.absorbed > 0.0 and m.hp_damage <= 0.0
	if only_block:
		def_res = DefenderResult.BLOCKED
		atk_fb = AttackerFeedback.BLOCKED

	emit_signal("defender_impact", cfg, m, def_res)
	emit_signal("attacker_impact", cfg, atk_fb, m)
