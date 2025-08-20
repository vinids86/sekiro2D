extends CharacterBody2D
class_name Player

@export var attack_set: AttackSet
@export var idle_clip: StringName = &"idle"

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var controller: CombatController = $CombatController
@onready var hitbox: AttackHitbox = $AttackHitbox

var _driver: AnimationDriver

func _ready() -> void:
	assert(sprite != null, "AnimatedSprite2D não encontrado no Player")
	assert(controller != null, "CombatController não encontrado no Player")
	assert(hitbox != null, "AttackHitbox não encontrado no Player")

	_driver = AnimationDriverSprite.new(sprite)
	controller.initialize(_driver, attack_set, idle_clip, hitbox)
	_driver.play_idle(idle_clip)
	
	hitbox.hit_hurtbox.connect(Callable(self, "_on_hit_hurtbox"))
	
func _on_hit_hurtbox(h: Area2D, cfg: AttackConfig) -> void:
	print("Acertou: ", h.name, " com ", cfg.name_id)
	# Exemplo: se a Hurtbox tiver script, podemos sinalizar dano:
	var hb: Hurtbox = h as Hurtbox
	if hb != null:
		hb.emit_signal("damaged", self, cfg)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("attack"):
		controller.on_attack_pressed()

func _process(delta: float) -> void:
	controller.update(delta)
