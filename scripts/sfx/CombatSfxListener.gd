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

	# conecta sinais do controller (assinaturas novas)
	if not _cc.is_connected("state_entered", Callable(self, "_on_state_entered")):
		_cc.state_entered.connect(_on_state_entered)
	if not _cc.is_connected("phase_changed", Callable(self, "_on_phase_changed")):
		_cc.phase_changed.connect(_on_phase_changed)

# ===================== ROTEAMENTO POR SINAIS =====================

func _on_state_entered(state: int, cfg: StateConfig, args: StateArgs) -> void:
	# ATTACK: sons por fase vêm de _on_phase_changed
	if state == CombatController.State.ATTACK:
		return

	# Parry: fases tratadas em _on_phase_changed
	if state == CombatController.State.PARRY:
		return

	# Estados sistêmicos (defensor/ofensivo)
	if state == CombatController.State.DODGE:
		# Direcional via DodgeArgs, com fallback genérico do DodgeProfile
		var da: DodgeArgs = args as DodgeArgs
		if da != null:
			_play_dodge_directional(da)
		else:
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

	# FINISHER_READY / BROKEN_FINISHER:
	# Mantido silencioso aqui; mapeamos sons específicos no futuro se desejar.
	if state == CombatController.State.BROKEN_FINISHER:
		_play_effect(_get_stream(_hitreact_profile, "broken_finisher_effect_stream"))
		_play_voice(_get_stream(_hitreact_profile, "broken_finisher_voice_stream"))
		return

	# Demais estados: silencioso
	return

func _on_phase_changed(phase: int, cfg: StateConfig) -> void:
	var st: int = _cc.get_state()

	# Sons do ATAQUE (streams diretos do AttackConfig)
	if st == CombatController.State.ATTACK:
		var ac: AttackConfig = cfg as AttackConfig
		if ac == null:
			# Sem AttackConfig válido: nada a tocar
			return
		if phase == CombatController.Phase.STARTUP:
			print("Tocando: ", ac.sfx_swing_stream.resource_path, ac.body_clip)
			_play_effect(ac.sfx_startup_stream)
			_play_voice(ac.voice_startup_stream)
			return
		if phase == CombatController.Phase.ACTIVE:
			_play_effect(ac.sfx_swing_stream)
			_play_voice(ac.voice_swing_stream)
			return
		if phase == CombatController.Phase.RECOVER:
			_play_effect(ac.sfx_recover_stream)
			_play_voice(ac.voice_recover_stream)
			return
		return

	# PARRY (streams por fase no ParryProfile)
	if st == CombatController.State.PARRY:
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

func _play_dodge_directional(da: DodgeArgs) -> void:
	# Suporta campos opcionais no DodgeProfile:
	# effect_stream / voice_stream (genéricos)
	# effect_up_stream, effect_down_stream, effect_left_stream, effect_right_stream, effect_neutral_stream
	# voice_up_stream,  voice_down_stream,  voice_left_stream,  voice_right_stream,  voice_neutral_stream
	var eff_field: String = "effect_stream"
	var voi_field: String = "voice_stream"

	if da.dir == CombatTypes.DodgeDir.UP:
		eff_field = "effect_up_stream"
		voi_field = "voice_up_stream"
	elif da.dir == CombatTypes.DodgeDir.DOWN:
		eff_field = "effect_down_stream"
		voi_field = "voice_down_stream"
	elif da.dir == CombatTypes.DodgeDir.LEFT:
		eff_field = "effect_left_stream"
		voi_field = "voice_left_stream"
	elif da.dir == CombatTypes.DodgeDir.RIGHT:
		eff_field = "effect_right_stream"
		voi_field = "voice_right_stream"
	elif da.dir == CombatTypes.DodgeDir.NEUTRAL:
		eff_field = "effect_neutral_stream"
		voi_field = "voice_neutral_stream"

	var eff: AudioStream = _get_stream(_dodge_profile, eff_field)
	var voi: AudioStream = _get_stream(_dodge_profile, voi_field)

	# Fallbacks para os campos genéricos se os direcionais não existirem
	if eff == null:
		eff = _get_stream(_dodge_profile, "effect_stream")
	if voi == null:
		voi = _get_stream(_dodge_profile, "voice_stream")

	_play_effect(eff)
	_play_voice(voi)

func _get_stream(profile: Resource, field: String) -> AudioStream:
	if profile == null:
		return null
	if not profile.has_method("get"):
		return null
	var val: Variant = profile.get(field)
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
