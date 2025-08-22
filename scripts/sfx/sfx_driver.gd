extends Node
class_name SfxDriver

var _cc: CombatController
var _bank: SfxBank

var _p_swing: AudioStreamPlayer2D
var _p_impact: AudioStreamPlayer2D
var _p_parry_startup: AudioStreamPlayer2D
var _p_parry_success: AudioStreamPlayer2D

var _wired: bool = false

func setup(controller: CombatController, bank: SfxBank,
		swing_player: AudioStreamPlayer2D,
		impact_player: AudioStreamPlayer2D,
		parry_startup_player: AudioStreamPlayer2D,
		parry_success_player: AudioStreamPlayer2D) -> void:

	_cc = controller
	_bank = bank
	_p_swing = swing_player
	_p_impact = impact_player
	_p_parry_startup = parry_startup_player
	_p_parry_success = parry_success_player

	assert(_cc != null, "CombatController nulo no SfxDriver")
	assert(_bank != null, "SfxBank nulo no SfxDriver")
	assert(_p_swing != null and _p_impact != null and _p_parry_startup != null and _p_parry_success != null, "Players de áudio nulos")

	if _wired:
		return
	_wired = true

	_cc.state_entered.connect(_on_state_entered)

func _on_state_entered(state: int, cfg: AttackConfig) -> void:
	if state == CombatController.State.HIT:
		assert(cfg != null and cfg.sfx_swing != null, "AttackConfig.sfx_swing ausente")
		_p_swing.stream = cfg.sfx_swing
		_p_swing.play()

	elif state == CombatController.State.PARRY_STARTUP:
		assert(_bank.parry_startup != null, "SfxBank.parry_startup ausente")
		_p_parry_startup.stream = _bank.parry_startup
		_p_parry_startup.play()

	elif state == CombatController.State.PARRY_SUCCESS:
		assert(_bank.parry_success != null, "SfxBank.parry_success ausente")
		_p_parry_success.stream = _bank.parry_success
		_p_parry_success.play()

	elif state == CombatController.State.HIT_REACT:
		assert(_bank.hit_impact != null, "SfxBank.hit_impact ausente")
		_p_impact.stream = _bank.hit_impact
		_p_impact.play()

	elif state == CombatController.State.GUARD_HIT:
		assert(_bank.guard_block != null, "SfxBank.guard_block ausente")
		_p_impact.stream = _bank.guard_block
		_p_impact.play()
	
	elif state == CombatController.State.COUNTER_HIT:
		assert(cfg != null and cfg.sfx_swing != null, "AttackConfig.sfx_swing ausente")
		_p_swing.stream = cfg.sfx_swing
		_p_swing.play()
	
	elif state == CombatController.State.FINISHER_HIT:
		assert(cfg != null and cfg.sfx_swing != null, "AttackConfig.sfx_swing ausente")
		_p_swing.stream = cfg.sfx_swing
		_p_swing.play()
