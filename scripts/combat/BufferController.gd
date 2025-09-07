extends Node
class_name BufferController

var _has_buffer: bool = false

func has_buffer() -> bool:
	return _has_buffer

func clear() -> void:
	_has_buffer = false

func capture() -> void:
	_has_buffer = true

func can_buffer_now(cc: CombatController) -> bool:
	if cc.get_state() != CombatController.State.ATTACK: return false
	if cc.phase != CombatController.Phase.RECOVER: return false
	if cc.current_kind != CombatController.AttackKind.LIGHT: return false
	if cc.attack_set == null: return false
	
	var next_idx: int = cc.attack_set.next_index(cc.combo_index)
	return next_idx >= 0

func try_consume(cc: CombatController) -> bool:
	if not _has_buffer: return false
	clear() # Consume immediately

	if cc.attack_set == null: return false
	if cc.current_kind != CombatController.AttackKind.LIGHT: return false

	var next_idx: int = cc.attack_set.next_index(cc.combo_index)
	if next_idx < 0: return false

	cc.combo_index = next_idx
	var next_cfg: AttackConfig = cc.attack_set.get_attack(cc.combo_index)
	if next_cfg == null: return false

	cc.current_cfg = next_cfg
	cc._change_phase(CombatController.Phase.STARTUP, cc.current_cfg)
	cc._safe_start_timer(cc.current_cfg.startup)
	return true
