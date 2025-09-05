extends Node2D
class_name CombatSfxListener

# ===== Dependências =====
var _cc: CombatController
var _parry_profile: ParryProfile
var _dodge_profile: DodgeProfile
var _hitreact_profile: HitReactProfile
var _parried_profile: ParriedProfile
var _guard_profile: GuardProfile

# ===== Players internos (preempção por categoria) =====
var _p_effects: AudioStreamPlayer2D
var _p_voice: AudioStreamPlayer2D

func setup(
		controller: CombatController,
		parry_profile: ParryProfile,
		dodge_profile: DodgeProfile,
		hitreact_profile: HitReactProfile,
		parried_profile: ParriedProfile,
		guard_profile: GuardProfile
	) -> void:
	_cc = controller
	_parry_profile = parry_profile
	_dodge_profile = dodge_profile
	_hitreact_profile = hitreact_profile
	_parried_profile = parried_profile
	_guard_profile = guard_profile

	assert(_cc != null, "CombatSfxListener.setup: controller nulo")

	# cria players locais (um para effects, um para voice)
	_p_effects = AudioStreamPlayer2D.new()
	_p_effects.name = "SFX_Effects"
	add_child(_p_effects)

	_p_voice = AudioStreamPlayer2D.new()
	_p_voice.name = "SFX_Voice"
	add_child(_p_voice)

	# conecta sinais do controller
	if not _cc.is_connected("state_entered", Callable(self, "_on_state_entered")):
		_cc.state_entered.connect(_on_state_entered)
	if not _cc.is_connected("phase_changed", Callable(self, "_on_phase_changed")):
		_cc.phase_changed.connect(_on_phase_changed)

# ===================== ROTEAMENTO POR SINAIS =====================

func _on_state_entered(state: int, cfg: AttackConfig) -> void:
	# Ataque: sons por fase vêm de _on_phase_changed
	if state == CombatController.State.ATTACK:
		return

	# Parry: fases tratadas em _on_phase_changed
	if state == CombatController.State.PARRY:
		return

	# Estados sistêmicos (defensor)
	if state == CombatController.State.DODGE:
		_play_effect(_get_stream(_dodge_profile, "effect_stream"))
		_play_voice(_get_stream(_dodge_profile, "voice_stream"))
		return

	if state == CombatController.State.PARRIED:
		_play_effect(_get_stream(_parried_profile, "effect_stream"))
		_play_voice(_get_stream(_parried_profile, "voice_stream"))
		return

	if state == CombatController.State.GUARD_HIT:
		_play_effect(_get_stream(_guard_profile, "block_effect_stream"))
		_play_voice(_get_stream(_guard_profile, "block_voice_stream"))
		return

	if state == CombatController.State.GUARD_BROKEN:
		_play_effect(_get_stream(_guard_profile, "broken_effect_stream"))
		_play_voice(_get_stream(_guard_profile, "broken_voice_stream"))
		return

	if state == CombatController.State.STUNNED:
		_play_effect(_get_stream(_hitreact_profile, "stun_effect_stream"))
		_play_voice(_get_stream(_hitreact_profile, "stun_voice_stream"))
		return

	if state == CombatController.State.DEAD:
		_play_effect(_get_stream(_hitreact_profile, "death_effect_stream"))
		_play_voice(_get_stream(_hitreact_profile, "death_voice_stream"))
		return

	# Finisher:
	# - FINISHER_READY (ATACANTE): vem do AttackConfig do golpe finisher
	if state == CombatController.State.FINISHER_READY:
		if cfg != null and cfg.kind == CombatTypes.AttackKind.FINISHER:
			_play_effect(cfg.sfx_startup_stream)
			_play_voice(cfg.voice_startup_stream)
		return

	# - BROKEN_FINISHER (DEFENSOR): vem do HitReactProfile
	if state == CombatController.State.BROKEN_FINISHER:
		_play_effect(_get_stream(_hitreact_profile, "broken_finisher_effect_stream"))
		_play_voice(_get_stream(_hitreact_profile, "broken_finisher_voice_stream"))
		return

	# Demais estados: silencioso
	return

func _on_phase_changed(phase: int, cfg: AttackConfig) -> void:
	var st: int = _cc.get_state()

	# Sons do ATAQUE (streams diretos do AttackConfig)
	if st == CombatController.State.ATTACK:
		if phase == CombatController.Phase.STARTUP:
			_play_effect(cfg.sfx_startup_stream)
			_play_voice(cfg.voice_startup_stream)
			return
		if phase == CombatController.Phase.ACTIVE:
			_play_effect(cfg.sfx_swing_stream)
			_play_voice(cfg.voice_swing_stream)
			return
		if phase == CombatController.Phase.RECOVER:
			_play_effect(cfg.sfx_recover_stream)
			_play_voice(cfg.voice_recover_stream)
			return
		return

	# PARRY (streams por fase no ParryProfile)
	if st == CombatController.State.PARRY:
		print("[SFX] phase: ", phase)
		if phase == CombatController.Phase.ACTIVE:
			_play_effect(_get_stream(_parry_profile, "startup_effect_stream"))
			_play_voice(_get_stream(_parry_profile, "startup_voice_stream"))
			return
		if phase == CombatController.Phase.SUCCESS:
			_play_effect(_get_stream(_parry_profile, "success_effect_stream"))
			_play_voice(_get_stream(_parry_profile, "success_voice_stream"))
			return
		if phase == CombatController.Phase.RECOVER:
			_play_effect(_get_stream(_parry_profile, "recover_effect_stream"))
			_play_voice(_get_stream(_parry_profile, "recover_voice_stream"))
			return
		return

	# Outros estados/fases: silencioso
	return

# ===================== HELPERS =====================

func _get_stream(profile: Resource, field: String) -> AudioStream:
	if profile == null:
		return null
	if not profile.has_method("get"):
		return null
	var val = profile.get(field)
	if val == null:
		return null
	if val is AudioStream:
		return val
	return null

func _play_effect(stream: AudioStream) -> void:
	if stream == null:
		return
	_p_effects.stop()
	_p_effects.stream = stream
	_p_effects.global_position = global_position
	_p_effects.play()

func _play_voice(stream: AudioStream) -> void:
	if stream == null:
		return
	_p_voice.stop()
	_p_voice.stream = stream
	_p_voice.global_position = global_position
	_p_voice.play()
