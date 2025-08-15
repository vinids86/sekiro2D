extends RefCounted
class_name CombatHitResolver

var cc: CombatController = null
var has_stamina_cb: Callable
var consume_stamina_cb: Callable
var apply_effects_cb: Callable
var play_block_sfx_cb: Callable

func setup(
	controller: CombatController,
	has_stamina: Callable,
	consume_stamina: Callable,
	apply_effects: Callable,
	play_block_sfx: Callable
) -> void:
	cc = controller
	has_stamina_cb = has_stamina
	consume_stamina_cb = consume_stamina
	apply_effects_cb = apply_effects
	play_block_sfx_cb = play_block_sfx

func process_incoming_hit(attacker: Node) -> void:
	# CC do atacante (falha rápido — preferes ver o erro)
	var atk_cc_node: Node = attacker.get_node(^"CombatController")
	var atk_cc: CombatController = atk_cc_node as CombatController
	assert(atk_cc != null, "Attacker.CombatController não é CombatController")

	var atk_cfg: AttackConfig = atk_cc.get_current_attack()
	assert(atk_cfg != null, "Attacker não possui AttackConfig ativo no momento do hit")

	# 0) I-frames: PARRY_SUCCESS não recebe nada (inclui autoblock)
	if cc.combat_state == CombatTypes.CombatState.PARRY_SUCCESS:
		return

	# 1) I-frames de esquiva por tipo
	if cc.combat_state == CombatTypes.CombatState.DODGE_ACTIVE:
		if cc.is_dodge_invulnerable_to(atk_cfg.kind):
			return

	# 2) Guard broken: qualquer hit vira finisher
	if cc.combat_state == CombatTypes.CombatState.GUARD_BROKEN:
		atk_cc.resolve_finisher(atk_cc, cc)
		return

	# 3) Parry dentro da janela efetiva (com fator do ataque)
	if cc.combat_state == CombatTypes.CombatState.PARRY_ACTIVE and atk_cfg.parryable:
		var eff: float = cc.parry_window
		# se tiver fator por golpe, aplique aqui
		if cc.is_within_parry_window(eff):
			match atk_cfg.parry_behavior:
				AttackConfig.ParryBehavior.INTERRUPT_ON_PARRY:
					if atk_cfg.kind == AttackConfig.AttackKind.HEAVY:
						cc.resolve_parry_heavy_neutral(atk_cc, cc)
					else:
						cc.resolve_parry_light(atk_cc, cc)
					return
				AttackConfig.ParryBehavior.DEFLECT_ONLY:
					cc.resolve_parry_deflect_only(atk_cc, cc)
					return

				AttackConfig.ParryBehavior.UNPARRYABLE:
					# trata como hit normal/auto-block
					cc.parry.set_success(false)

	# 4) Auto-block: só para NORMAL que não bypass e se houver stamina
	var is_light: bool = (atk_cfg.kind == AttackConfig.AttackKind.NORMAL)
	var can_autoblock: bool = is_light and (not atk_cfg.bypass_auto_block)
	if can_autoblock and has_stamina_cb.call(cc.block_stamina_cost):
		play_block_sfx_cb.call()
		cc.on_blocked()
		return

	# 5) Hit real: aplica efeitos do ataque e entra em hitstun
	apply_effects_cb.call(atk_cfg)
	cc.on_hit()
