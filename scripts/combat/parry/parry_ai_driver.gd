extends Node
class_name ParryAIDriver

@export var profile: ParryAIProfile

var _root: Node2D
var _cc: CombatController
var _hub: CombatEventHub
var _parry: ParryProfile

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _timer: Timer
var _armed: bool = false  # evita múltiplos timers simultâneos; rearma a cada windup válido

func setup(root: Node2D, controller: CombatController, hub: CombatEventHub, parry_profile: ParryProfile, ai_profile: ParryAIProfile) -> void:
	_root = root
	_cc = controller
	_hub = hub
	_parry = parry_profile
	profile = ai_profile

	assert(_root != null, "ParryAIDriver: root nulo")
	assert(_cc != null, "ParryAIDriver: controller nulo")
	assert(_hub != null, "ParryAIDriver: hub nulo")
	assert(_parry != null, "ParryAIDriver: ParryProfile nulo")
	assert(profile != null, "ParryAIDriver: ParryAIProfile nulo")

	if _timer == null:
		_timer = Timer.new()
		_timer.one_shot = true
		add_child(_timer)
		_timer.timeout.connect(_fire_parry, Object.CONNECT_DEFERRED)

	_rng.randomize()
	_hub.attack_windup.connect(_on_attack_windup, Object.CONNECT_DEFERRED)

func _on_attack_windup(attacker: Node2D, cfg: AttackConfig, time_to_hit: float) -> void:
	# ignora eventos do próprio lutador
	if attacker == _root:
		return

	# distância (opcional)
	if profile.min_distance > 0.0:
		var dx: float = abs(_root.global_position.x - attacker.global_position.x)
		if dx > profile.min_distance:
			return

	# chance
	var roll: float = _rng.randf()
	if roll > profile.base_chance:
		if profile.debug_ai:
			print("[AI-PARRY] roll ", str(roll), " > chance ", str(profile.base_chance), " → skip")
		return

	# cancela agendamento anterior (se houver)
	if _armed and _timer.time_left > 0.0:
		_timer.stop()
		_armed = false

	# calcular quando APERTAR:
	# Queremos abrir PARRY_STARTUP um pouco antes do HIT.
	# lead efetivo não pode exceder a janela do parry (senão abre cedo e expira).
	var lead_eff: float = profile.press_lead
	var max_lead: float = _parry.startup_time * 0.9
	if lead_eff > max_lead:
		lead_eff = max_lead
	if lead_eff < 0.0:
		lead_eff = 0.0

	# reação/jitter
	var reaction: float = profile.reaction_mean
	if profile.reaction_jitter > 0.0:
		var j: float = _rng.randf_range(-profile.reaction_jitter, profile.reaction_jitter)
		reaction += j

	# atraso total a partir de AGORA
	var delay: float = time_to_hit - lead_eff + reaction
	if delay < 0.0:
		delay = 0.0

	_timer.start(delay)
	_armed = true

	if profile.debug_ai:
		print("[AI-PARRY] schedule in ", str(snappedf(delay, 0.001)), "s | time_to_hit=", str(snappedf(time_to_hit,0.001)),
			" lead_eff=", str(snappedf(lead_eff,0.001)), " reaction=", str(snappedf(reaction,0.001)))

func _fire_parry() -> void:
	_armed = false
	_cc.on_parry_pressed()
	if profile.debug_ai:
		print("[AI-PARRY] pressed at t=", str(Time.get_ticks_msec()))
