extends Node
class_name SfxDriver

var _cc: CombatController
var _swing: AudioStreamPlayer2D
var _wired: bool = false

func setup(controller: CombatController, swing_player: AudioStreamPlayer2D) -> void:
	_cc = controller
	_swing = swing_player

	assert(_cc != null, "CombatController nulo")
	assert(_swing != null, "AudioStreamPlayer2D nulo")

	if _wired:
		return
	_wired = true

	_cc.state_entered.connect(_on_state_entered)

func _on_state_entered(state: int, cfg: AttackConfig) -> void:
	if state == CombatController.State.HIT:
		assert(cfg != null, "AttackConfig nulo no HIT (SFX)")
		assert(cfg.sfx_swing != null, "sfx_swing não configurado no AttackConfig")
		_swing.stream = cfg.sfx_swing
		_swing.play()
