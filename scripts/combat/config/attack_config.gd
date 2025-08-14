@tool
extends Resource
class_name AttackConfig

# ------------------------------------------------------------------------------------
# Movimento durante o ataque
# ------------------------------------------------------------------------------------
@export var step_distance_px: float = 0.0      # quanto avança nesse golpe (em pixels)
@export var step_time_in_active: float = 0.0   # quando aplicar (segundos após iniciar o ACTIVE)
@export var can_move_during_active: bool = false
@export var move_influence: float = 0.0  # 0..1 (quão “arrasta” o personagem no ataque)

# ------------------------------------------------------------------------------------
# Tempo (s)
# ------------------------------------------------------------------------------------
@export var startup: float = 0.2
@export var active_duration: float = 0.1
@export var recovery_hard: float = 0.15    # janela sem ação (travado)
@export var recovery_soft: float = 0.15    # janela com cancel (ex.: para próximo ataque)
@export var stamina_cost: float = 2.0

func total_time() -> float:
	return startup + active_duration + recovery_hard + recovery_soft

# ------------------------------------------------------------------------------------
# Hitbox (uma ou mais janelas dentro do ativo)
# Ex.: [[0.00, 0.08], [0.10, 0.12]]  -> dois hits dentro do ACTIVE
# ------------------------------------------------------------------------------------
@export var active_windows: Array[Vector2] = [Vector2(0.0, 0.1)]

# ------------------------------------------------------------------------------------
# Cancel rules
# ------------------------------------------------------------------------------------
@export var can_cancel_to_parry_on_startup: bool = true
@export var can_cancel_to_parry_on_active: bool = false
@export var can_chain_next_attack_on_soft_recovery: bool = true

# ------------------------------------------------------------------------------------
# Parry / Poise / Dano
# ------------------------------------------------------------------------------------
@export var parryable: bool = true                    # ataques "especiais" seriam false
@export var super_armor_startup: float = 0.0          # segundos de super armor dentro do startup
@export var poise_damage: float = 10.0                # mantém seu uso atual

# NOVO: dano base explícito do golpe (vida). Se você já tem outra fonte, use este como referência única.
@export var damage: float = 10.0

# NOVO: pressão adicional de stamina (ajuda a levar GUARD_BROKEN quando somado ao dano/stamina normal)
@export var stamina_damage_extra: float = 0.0

# NOVO: fator multiplicador da janela de parry para este golpe (ex.: HEAVY = 0.6)
@export var parry_window_factor: float = 1.0

# NOVO: se true, ignora a defesa automática (auto-block). Use true em HEAVY.
@export var bypass_auto_block: bool = false

# ------------------------------------------------------------------------------------
# Identidade / Tags
# ------------------------------------------------------------------------------------
enum AttackKind { NORMAL, HEAVY, GRAB, SPECIAL }
@export var kind: AttackKind = AttackKind.NORMAL

# NOVO: se true, ao finalizar este golpe o combo é encerrado (reset de combo_index).
# Use true em HEAVY para cumprir a regra que combinamos.
@export var ends_combo: bool = false

# ------------------------------------------------------------------------------------
# Animações / Áudio
# ------------------------------------------------------------------------------------
@export var startup_animation: StringName = &"startup_1"
@export var attack_animation: StringName = &"attack_1"
@export var recovery_animation: StringName = &"recover_1"

# Áudio como recurso, não path
@export var attack_sound: AudioStream

# ------------------------------------------------------------------------------------
# Helpers de criação
# ------------------------------------------------------------------------------------
static func new_simple(
	_startup: float, _active: float, _rec_hard: float, _rec_soft: float, _stamina: float,
	_startup_anim := &"", _attack_anim := &"", _recovery_anim := &"",
	_sound: AudioStream = null,
	_step_px: float = 0.0, _step_t: float = 0.0
) -> AttackConfig:
	var c := AttackConfig.new()
	c.startup = _startup
	c.active_duration = _active
	c.recovery_hard = _rec_hard
	c.recovery_soft = _rec_soft
	c.stamina_cost = _stamina
	c.startup_animation = _startup_anim
	c.attack_animation = _attack_anim
	c.recovery_animation = _recovery_anim
	c.attack_sound = _sound
	c.step_distance_px = _step_px
	c.step_time_in_active = _step_t
	return c

static func default_sequence() -> Array[AttackConfig]:
	return [
		AttackConfig.new_simple(0.4, 0.1, 0.25, 0.05, 2.0,
			&"startup_1", &"attack_1", &"recover_1",
			preload("res://audio/attack_1.wav"),
			20.0, 0.02),
		AttackConfig.new_simple(0.28, 0.1, 0.24, 0.06, 3.0,
			&"startup_2", &"attack_2", &"recover_2",
			preload("res://audio/attack_2.wav"),
			24.0, 0.02),
		AttackConfig.new_simple(0.26, 0.12, 0.26, 0.08, 3.0,
			&"startup_3", &"attack_3", &"recover_3",
			preload("res://audio/attack_3.wav"),
			26.0, 0.03),
	]

# Preset útil para criar um HEAVY rapidamente no editor/código
static func heavy_preset() -> AttackConfig:
	var c := AttackConfig.new_simple(
		0.80,  # startup maior (telegrafia)
		0.20,  # active levemente maior
		0.60,  # recovery_hard
		0.10,  # recovery_soft (você pode reduzir se quiser deixar mais “pesado”)
		30.0   # stamina_cost
	)
	c.kind = AttackKind.HEAVY
	c.damage = 40.0
	c.stamina_damage_extra = 50.0
	c.parry_window_factor = 0.6
	c.bypass_auto_block = true
	c.ends_combo = true
	c.startup_animation = &"heavy_startup"
	c.attack_animation = &"heavy_attack"
	c.recovery_animation = &"heavy_recover"
	c.attack_sound = preload("res://audio/heavy_attack.wav")
	c.step_distance_px = 12.0
	c.step_time_in_active = 0.02
	return c
