extends Node
class_name EnemyBrain

@export var enemy_path: NodePath          # referencie o Enemy (CharacterBody2D)
@export var parry_chance := 0.3
@export var parry_check_cooldown := 0.4
@export var max_check_distance := 140.0
@export var require_facing_match := true  # só tenta parry se player estiver de frente

var _enemy: Node
var _player: Node
var _cooldown := 0.0

func _ready() -> void:
	_enemy = get_node(enemy_path)
	# Player será setado via enemy.gd chamando set_player() em runtime.

func set_player(p: Node) -> void:
	_player = p

func _process(delta: float) -> void:
	if _cooldown > 0.0:
		_cooldown -= delta
		return
	if not _enemy or not _player:
		return

	var ec: CombatController = _enemy.get_combat_controller()
	var pc: CombatController = _player.get_combat_controller()
	if not ec or not pc:
		return

	# só reage a STARTUP do player
	if pc.combat_state != CombatController.CombatState.STARTUP:
		return

	# pos dos atores (faça cast para Node2D para tipar corretamente)
	var enemy_pos: Vector2 = (_enemy as Node2D).global_position
	var player_pos: Vector2 = (_player as Node2D).global_position

	# distância
	if enemy_pos.distance_to(player_pos) > max_check_distance:
		return

	# (opcional) garantir que o player está atacando "na direção" do inimigo
	if require_facing_match:
		var enemy_on_right: bool = (enemy_pos.x - player_pos.x) > 0.0
		var player_attacking_right: bool = (pc.current_attack_direction.x >= 0.0)
		if enemy_on_right != player_attacking_right:
			return

	if randf() < parry_chance:
		var dir: Vector2 = (player_pos - enemy_pos).normalized()
		ec.try_parry(true, dir)
	_cooldown = parry_check_cooldown
