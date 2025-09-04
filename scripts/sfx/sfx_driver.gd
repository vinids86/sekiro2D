extends Node
class_name SfxDriver

var _cc: CombatController
var _bank: SfxBank

var _p_swing: AudioStreamPlayer2D
var _p_impact: AudioStreamPlayer2D
var _p_parry_startup: AudioStreamPlayer2D
var _p_parry_success: AudioStreamPlayer2D
var _p_dodge: AudioStreamPlayer2D
var _p_heavy_startup: AudioStreamPlayer2D
var _p_combo_parry_enter: AudioStreamPlayer2D

func setup(
	controller: CombatController,
	bank: SfxBank,
	swing: AudioStreamPlayer2D,
	impact: AudioStreamPlayer2D,
	parry_startup: AudioStreamPlayer2D,
	parry_success: AudioStreamPlayer2D,
	dodge: AudioStreamPlayer2D,
	heavy_startup: AudioStreamPlayer2D,
	combo_parry_enter: AudioStreamPlayer2D
) -> void:
	_cc = controller
	_bank = bank

	_p_swing = swing
	_p_impact = impact
	_p_parry_startup = parry_startup
	_p_parry_success = parry_success
	_p_dodge = dodge
	_p_heavy_startup = heavy_startup
	_p_combo_parry_enter = combo_parry_enter

	assert(_cc != null, "SfxDriver: controller nulo")
	assert(_bank != null, "SfxDriver: SfxBank nulo")

	# Nova integração: ouvir mudanças de fase e entradas de estado
	_cc.phase_changed.connect(_on_phase_changed)
	_cc.state_entered.connect(_on_state_entered)

func _on_state_entered(state: int, _cfg: AttackConfig) -> void:
	if state == CombatController.State.PARRY and _p_parry_startup != null and _bank.parry_startup != null:
		_p_parry_startup.stream = _bank.parry_startup
		_p_parry_startup.play()
	elif state == CombatController.State.DODGE and _p_dodge != null and _bank.dodge != null:
		_p_dodge.stream = _bank.dodge
		_p_dodge.play()
	elif state == CombatController.State.GUARD_HIT and _p_impact != null and _bank.guard_block != null:
		_p_impact.stream = _bank.guard_block
		_p_impact.play()
	elif state == CombatController.State.STUNNED and _p_impact != null and _bank.hit_impact != null:
		_p_impact.stream = _bank.hit_impact
		_p_impact.play()

func _on_phase_changed(phase: int, cfg: AttackConfig) -> void:
	var st: int = _cc.get_state()
	if st == CombatController.State.ATTACK:
		if phase == CombatController.Phase.STARTUP and _p_heavy_startup != null:
			# tocar startup pesado se for o caso (se quiser diferenciar, use outros sinais)
			# por ora usamos um único som opcional
			if _bank.heavy_startup != null:
				_p_heavy_startup.stream = _bank.heavy_startup
				#_p_heavy_startup.play()
		elif phase == CombatController.Phase.ACTIVE and _p_swing != null and cfg.sfx_swing != null:
			_p_swing.stream = cfg.sfx_swing
			_p_swing.play()
	elif st == CombatController.State.PARRY:
		# Toca o som de sucesso ao receber a troca de phase para SUCCESS
		if phase == CombatController.Phase.SUCCESS and _p_parry_success != null and _bank.parry_success != null:
			_p_parry_success.stream = _bank.parry_success
			_p_parry_success.play()
