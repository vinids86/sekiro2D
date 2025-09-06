extends Node
class_name CombatAnimListener

# ===== Constantes =====
const ATTACK_HIT_FRAMES_DEFAULT: int = 2

var _cc: CombatController
var _animation: AnimationPlayer
var _sprite: AnimatedSprite2D

# Perfis (mantidos para futura expansão de VFX/SFX se quiser)
var _parry_profile: ParryProfile
var _dodge_profile: DodgeProfile
var _hitreact_profile: HitReactProfile
var _parried_profile: ParriedProfile
var _guard_profile: GuardProfile
var _locomotion_profile: LocomotionProfile

var _mover: MoveController

var _parry_toggle: bool = false  # alterna success A/B

func setup(
		controller: CombatController,
		animation: AnimationPlayer,
		sprite: AnimatedSprite2D,
		parry_profile: ParryProfile,
		dodge_profile: DodgeProfile,
		hitreact_profile: HitReactProfile,
		parried_profile: ParriedProfile,
		guard_profile: GuardProfile,
		locomotion_profile: LocomotionProfile,
		mover: MoveController,
) -> void:
	_cc = controller
	_animation = animation
	_sprite = sprite

	_parry_profile = parry_profile
	_dodge_profile = dodge_profile
	_hitreact_profile = hitreact_profile
	_parried_profile = parried_profile
	_guard_profile = guard_profile

	_locomotion_profile = locomotion_profile
	_mover = mover

	# ===== Reconectar sinais do CombatController (combate) =====
	if _cc != null:
		if not _cc.state_entered.is_connected(_on_state_entered):
			_cc.state_entered.connect(_on_state_entered)
		if not _cc.phase_changed.is_connected(_on_phase_changed):
			_cc.phase_changed.connect(_on_phase_changed)
		# Conecte state_exited aqui se você tiver um handler correspondente:
		# if not _cc.state_exited.is_connected(_on_state_exited):
		#     _cc.state_exited.connect(_on_state_exited)

	# ===== Conectar evento de locomoção (andar/parar) =====
	if _mover != null and not _mover.movement_changed.is_connected(_on_movement_changed):
		_mover.movement_changed.connect(_on_movement_changed)

	print("[ANIM] listener wired: controller+phases+mover OK")

func _on_movement_changed(moving: bool) -> void:
	if _cc._state != CombatController.State.IDLE:
		return

	var clip: StringName = _locomotion_profile.idle_clip
	if moving:
		clip = _locomotion_profile.walk_clip

	if not _animation.has_animation(clip):
		push_warning("[AnimListener] Locomotion clip ausente: %s" % [str(clip)])
		return

	# Evita resetar animação em todo frame/evento idêntico
	if _animation.current_animation != clip:
		_animation.play(clip)

# ===================== ROTEAMENTO POR SINAIS =====================

func _on_state_entered(state: int, cfg: AttackConfig) -> void:
	# ATTACK: deixamos o phase_changed STARTUP tocar o clipe do golpe (cfg.body_clip)
	if state == CombatController.State.ATTACK:
		return

	# FINISHER_READY: sem clipe por enquanto (janela/pose fica por conta do lock visual)
	if state == CombatController.State.FINISHER_READY:
		return

	if state == CombatController.State.PARRY:
		# Entradas de clipe por fase (ACTIVE/SUCCESS/RECOVER) serão tratadas em _on_phase_changed
		return

	if state == CombatController.State.IDLE:
		_play(&"idle")
		return

	if state == CombatController.State.DODGE:
		_play(&"dodge_down")
		return

	if state == CombatController.State.PARRIED:
		_play(&"parried_light")
		return

	if state == CombatController.State.GUARD_HIT:
		_play(&"block_hit")
		return

	if state == CombatController.State.STUNNED:
		_play(&"hitstun")
		return

	if state == CombatController.State.GUARD_BROKEN:
		_play(&"guard_broken")
		return

	if state == CombatController.State.BROKEN_FINISHER:
		_play(&"broken_finisher")
		return

func _on_phase_changed(phase: int, cfg: AttackConfig) -> void:
	var st: int = _cc.get_state()

	# ATTACK: na virada para STARTUP de cada golpe, toca o clipe do golpe
	if st == CombatController.State.ATTACK:
		if phase == CombatController.Phase.STARTUP:
			print("[ANIM] STARTUP clip=", cfg.body_clip, " current=", _animation.current_animation, " playing=", _animation.is_playing())
			if cfg == null:
				push_error("CombatAnimListener: ATTACK STARTUP com cfg nulo")
				return

			# Finisher: exige body_clip configurado; sem fallback.
			if _cc.current_kind == CombatController.AttackKind.FINISHER:
				if cfg.body_clip == StringName():
					push_error("CombatAnimListener: Finisher sem body_clip configurado")
					return
				_play(cfg.body_clip)
				return

			# Outros ataques: mantém comportamento atual (toca se vier clip)
			if cfg.body_clip != StringName():
				_play(cfg.body_clip)
				print("Depois de play [ANIM] STARTUP clip=", cfg.body_clip, " current=", _animation.current_animation, " playing=", _animation.is_playing())

		return

	# PARRY: clipes separados por fase
	if st == CombatController.State.PARRY:
		if phase == CombatController.Phase.ACTIVE:
			_play(&"parry")
			return
		if phase == CombatController.Phase.SUCCESS:
			var clip_success: StringName = &"parry_success_a"
			if _parry_toggle:
				clip_success = &"parry_success_b"
			_parry_toggle = not _parry_toggle
			_play(clip_success)
			return
		if phase == CombatController.Phase.RECOVER:
			_play(&"parry_recover")
			return

	# DODGE/REACTIONS: já tratados em state_entered; nada a fazer aqui
	return

# ===================== HELPERS =====================

func _play(clip: StringName) -> void:
	_animation.speed_scale = 1.0
	_animation.play(clip)

# ===================== NOTIFIES (se existirem no AnimationPlayer) =====================
# Mantidos apenas para compat: não usamos mais notifies para trocar fase/estado.

func phase_startup_end() -> void:
	# Intencionalmente vazio
	pass

func phase_hit_end() -> void:
	pass

func phase_recover_end() -> void:
	pass

func parried_end() -> void:
	pass

func guard_hit_end() -> void:
	pass

func hitstun_end() -> void:
	pass

func parry_window_on() -> void:
	pass

func parry_window_off() -> void:
	pass

func parry_fail_end() -> void:
	pass

func parry_success_end() -> void:
	pass
