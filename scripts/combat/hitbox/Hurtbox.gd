extends Area2D
class_name Hurtbox

func _ready() -> void:
	if not self.area_entered.is_connected(_on_area_entered):
		self.area_entered.connect(_on_area_entered)

func _on_area_entered(area: Area2D) -> void:
	if area == null:
		return
	if not (area is AttackHitbox):
		return

	var atk_hb: AttackHitbox = area as AttackHitbox
	if not atk_hb.monitoring:
		return

	var attacker_root: Node2D = atk_hb.get_attacker()
	var defender_root: Node2D = get_parent() as Node2D
	assert(attacker_root != null and defender_root != null, "Hurtbox: attacker/defender inválidos")

	var cfg: AttackConfig = atk_hb.get_current_config()
	assert(cfg != null, "Hurtbox: AttackConfig ausente na AttackHitbox")

	var reg: ContactArbiterRegistry = _find_registry()
	assert(reg != null, "Hurtbox: ContactArbiterRegistry não encontrado (adicione no Main e marque grupo contact_registry)")

	var arb: ContactArbiter = reg.get_for(attacker_root, defender_root)

	# ===== Conecte UMA vez por par =====
	var def_cc: CombatController = defender_root.get_node(^"CombatController") as CombatController
	var atk_cc: CombatController = attacker_root.get_node(^"CombatController") as CombatController
	assert(def_cc != null and atk_cc != null, "Hurtbox: CombatController ausente em attacker/defender")

	# Defender recebe defender_impact
	var def_callable: Callable = Callable(def_cc, "_on_defender_impact")
	if not arb.defender_impact.is_connected(def_callable):
		arb.defender_impact.connect(def_callable)

	# Attacker recebe attacker_impact
	var atk_callable: Callable = Callable(atk_cc, "_on_attacker_impact")
	if not arb.attacker_impact.is_connected(atk_callable):
		arb.attacker_impact.connect(atk_callable)

	# (Opcional) stamina do DEFENSOR avisa quebra → controller entra GUARD_BROKEN
	if defender_root.has_node(^"Stamina"):
		var stamina: Node = defender_root.get_node(^"Stamina")
		var cb_empty: Callable = Callable(def_cc, "_on_stamina_emptied")
		if not stamina.is_connected("emptied", cb_empty):
			stamina.connect("emptied", cb_empty)

	# ===== Agora sim, resolve o impacto =====
	arb.resolve(cfg)

func _find_registry() -> ContactArbiterRegistry:
	var n: Node = get_tree().get_first_node_in_group("contact_registry")
	if n == null:
		return null
	return n as ContactArbiterRegistry
