extends Node
class_name EnemyBrain

@export var enemy_path: NodePath          # referencie o Enemy (CharacterBody2D)
@export var parry_chance := 0.6
@export var parry_check_cooldown := 0.4
@export var max_check_distance := 140.0
@export var require_facing_match := true  # só tenta parry se player estiver de frente

# Ajuste de chance contra HEAVY: 0.5 => metade da chance
@export var heavy_parry_chance_factor := 0.5

var _enemy: Node
var _player: Node
var _cooldown := 0.0

# controle para não tentar múltiplas vezes no mesmo STARTUP
var _tried_this_startup := false
var _last_player_state := -1

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

	# detectar transição do player para STARTUP para resetar a flag
	if pc.combat_state != _last_player_state:
		_last_player_state = pc.combat_state
		_tried_this_startup = false

	# só reage a STARTUP do player
	if pc.combat_state != CombatController.CombatState.STARTUP:
		return

	# já tentei neste STARTUP? então não repete
	if _tried_this_startup:
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

	# pegar o ataque atual do player para cronometrar e ajustar chance
	var p_attack: AttackConfig = pc.get_current_attack()
	if p_attack == null:
		return

	var chance := parry_chance
	if p_attack.kind == AttackConfig.AttackKind.HEAVY:
		chance *= heavy_parry_chance_factor

	# tente parry um pouco ANTES do fim do startup do player
	# buffer de segurança: 0.06s (ajuste fino depois)
	var delay: Variant = max(0.0, p_attack.startup - 0.06)

	# agendar tentativa única para este STARTUP
	_tried_this_startup = true
	_cooldown = parry_check_cooldown
	call_deferred("_try_parry_with_delay", delay, chance)

func _try_parry_with_delay(delay: float, chance: float) -> void:
	# Espera 'delay' mantendo a simplicidade
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout

	# Revalida condições mínimas (player ainda no mesmo ciclo de ataque?)
	if not _enemy or not _player:
		return
	var ec: CombatController = _enemy.get_combat_controller()
	var pc: CombatController = _player.get_combat_controller()
	if not ec or not pc:
		return
	if pc.combat_state != CombatController.CombatState.STARTUP and pc.combat_state != CombatController.CombatState.ATTACKING:
		return

	# Distância e facing ainda válidos?
	var enemy_pos: Vector2 = (_enemy as Node2D).global_position
	var player_pos: Vector2 = (_player as Node2D).global_position
	if enemy_pos.distance_to(player_pos) > max_check_distance:
		return
	if require_facing_match:
		var enemy_on_right: bool = (enemy_pos.x - player_pos.x) > 0.0
		var player_attacking_right: bool = (pc.current_attack_direction.x >= 0.0)
		if enemy_on_right != player_attacking_right:
			return

	# Decide e tenta
	if randf() < chance:
		var dir: Vector2 = (player_pos - enemy_pos).normalized()
		ec.try_parry(true, dir)
