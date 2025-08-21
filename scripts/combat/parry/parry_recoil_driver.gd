extends Node
class_name ParryRecoilDriver

var _root: Node2D
var _cc: CombatController
var _hub: CombatEventHub
var _profile: ParriedProfile
var _wired: bool = false

func setup(root: Node2D, controller: CombatController, hub: CombatEventHub, parried_profile: ParriedProfile) -> void:
	_root = root
	_cc = controller
	_hub = hub
	_profile = parried_profile

	assert(_root != null, "Root nulo no ParryRecoilDriver")
	assert(_cc != null, "CombatController nulo no ParryRecoilDriver")
	assert(_hub != null, "CombatEventHub nulo no ParryRecoilDriver")
	assert(_profile != null, "ParriedProfile nulo no ParryRecoilDriver")

	if _wired:
		return
	_wired = true
	# Conexão adiada: evita interações no mesmo tick do callback de física
	_hub.parry_success.connect(_on_parry_success, Object.CONNECT_DEFERRED)

func _on_parry_success(attacker: Node2D, defender: Node2D, cfg: AttackConfig) -> void:
	if attacker == _root:
		_cc.enter_parried()
