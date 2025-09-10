# EnemyAIDriver.gd
extends Node
class_name EnemyAIDriver

# --- DEPENDÊNCIAS ---
@export var profile: EnemyAIProfile
@export var controller: CombatController

# --- ESTADO INTERNO DA IA ---
var target_controller: CombatController
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _sensed_data := {
	"target_state": CombatController.State.IDLE, "target_phase": CombatController.Phase.STARTUP, "target_cfg": null,
	"self_state": CombatController.State.IDLE
}
var _idle_patience_timer: Timer
var _pressure_reset_timer: Timer
var _post_parry_cooldown_timer: Timer
var _combo_pressure_count: int = 0
var _post_parry_cooldown_active: bool = false
var _last_hit_was_parried: bool = false

# =========================
# SETUP E PROCESSAMENTO
# =========================
func _ready() -> void:
	_rng.randomize()
	_idle_patience_timer = Timer.new()
	_idle_patience_timer.one_shot = true
	add_child(_idle_patience_timer)
	_idle_patience_timer.timeout.connect(_on_idle_patience_timeout)
	_pressure_reset_timer = Timer.new()
	_pressure_reset_timer.one_shot = true
	add_child(_pressure_reset_timer)
	_pressure_reset_timer.timeout.connect(_reset_pressure_count)
	_post_parry_cooldown_timer = Timer.new()
	_post_parry_cooldown_timer.one_shot = true
	add_child(_post_parry_cooldown_timer)
	_post_parry_cooldown_timer.timeout.connect(func(): _post_parry_cooldown_active = false)

	if controller:
		controller.connect("state_entered", _on_self_state_entered)
		controller.connect("phase_changed", _on_self_phase_changed)

func _process(_delta: float) -> void:
	_sense()

func _sense() -> void:
	_sensed_data.self_state = controller.get_state()
	if not is_instance_valid(target_controller):
		_sensed_data.target_state = CombatController.State.IDLE
		return
	_sensed_data.target_state = target_controller.get_state()
	_sensed_data.target_phase = target_controller.phase
	_sensed_data.target_cfg = target_controller.current_cfg

# =========================
# CÉREBRO TÁTICO (Reage a Sinais e Chamadas)
# =========================
func _on_impact_imminent(_attack_cfg: AttackConfig) -> void:
	if not profile: return
	if _rng.randf() < _get_current_parry_chance():
		controller.on_parry_pressed()

# --- REAÇÕES A EVENTOS DO PRÓPRIO INIMIGO ---
func _on_self_state_entered(state: int, _cfg: StateConfig, _args: StateArgs):
	if state == CombatController.State.PARRIED:
		_post_parry_cooldown_active = true
		_post_parry_cooldown_timer.start(profile.post_parry_cooldown)
		_reset_pressure_count()
	elif state == CombatController.State.ATTACK:
		_reset_pressure_count()

func _on_self_phase_changed(phase: int, _cfg: StateConfig):
	if phase == CombatController.Phase.RECOVER and controller.get_state() == CombatController.State.ATTACK:
		if not _last_hit_was_parried:
			controller.on_attack_pressed()
		_last_hit_was_parried = false

func _on_self_defender_impact(_cfg: AttackConfig, _metrics: ImpactMetrics, result: int):
	if result == ContactArbiter.DefenderResult.BLOCKED or result == ContactArbiter.DefenderResult.DAMAGED:
		_combo_pressure_count += 1
		_pressure_reset_timer.start(profile.pressure_reset_time)
	elif result == ContactArbiter.DefenderResult.PARRY_SUCCESS:
		_reset_pressure_count()
		# --- MUDANÇA PRINCIPAL AQUI ---
		# Não chamamos o ataque diretamente para evitar a "corrida".
		# Em vez disso, agendamos a chamada para o próximo frame.
		call_deferred("_execute_parry_counter_attack")

# --- NOVA FUNÇÃO "TRAMPOLIM" ---
func _execute_parry_counter_attack():
	# Esta função é chamada no próximo frame, garantindo que o CombatController
	# já atualizou sua fase para SUCCESS.
	controller.on_attack_pressed()


func _on_self_attacker_impact(feedback: int, _metrics: ImpactMetrics):
	if feedback == ContactArbiter.AttackerFeedback.ATTACK_PARRIED:
		_last_hit_was_parried = true

# --- REAÇÕES A EVENTOS DO JOGADOR ---
func _on_player_state_entered(state: int, _cfg: StateConfig, _args: StateArgs):
	if state == CombatController.State.GUARD_BROKEN:
		if controller.get_state() == CombatController.State.IDLE:
			controller.start_finisher()
	elif state == CombatController.State.IDLE:
		_idle_patience_timer.start(profile.idle_patience_time)
	else:
		_idle_patience_timer.stop()

func _on_player_phase_changed(phase: int, cfg: StateConfig, _args: StateArgs):
	if phase == CombatController.Phase.RECOVER:
		var attack_cfg := cfg as AttackConfig
		if attack_cfg and attack_cfg.recovery >= profile.punish_recover_threshold:
			if controller.get_state() == CombatController.State.IDLE and not _post_parry_cooldown_active:
				controller.on_attack_pressed()

# --- FUNÇÕES INTERNAS ---
func _on_idle_patience_timeout():
	print("ATTACK: ", controller.get_state() == CombatController.State.IDLE, _post_parry_cooldown_active)
	if controller.get_state() == CombatController.State.IDLE and not _post_parry_cooldown_active:
		if _rng.randf() < profile.idle_attack_chance:
			controller.on_attack_pressed()

func _get_current_parry_chance() -> float:
	var chance_index = min(_combo_pressure_count, profile.parry_chance_per_hit.size() - 1)
	return profile.parry_chance_per_hit[chance_index]

func _reset_pressure_count():
	_combo_pressure_count = 0
	_pressure_reset_timer.stop()

# =========================
# API PÚBLICA
# =========================
func set_target_controller(cc: CombatController):
	if target_controller == cc: return
	if is_instance_valid(target_controller):
		if target_controller.is_connected("state_entered", _on_player_state_entered):
			target_controller.state_entered.disconnect(_on_player_state_entered)
		if target_controller.is_connected("phase_changed", _on_player_phase_changed):
			target_controller.phase_changed.disconnect(_on_player_phase_changed)
	
	target_controller = cc

	if is_instance_valid(target_controller):
		target_controller.state_entered.connect(_on_player_state_entered)
		target_controller.phase_changed.connect(_on_player_phase_changed)
