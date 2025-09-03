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

	# --- Raízes envolvidas no contato ---
	var attacker_root: Node2D = atk_hb.get_attacker()
	var defender_root: Node2D = get_parent() as Node2D
	assert(attacker_root != null and defender_root != null, "Hurtbox: attacker/defender inválidos")

	# --- Config do ataque atual ---
	var cfg: AttackConfig = atk_hb.get_current_config()
	assert(cfg != null, "Hurtbox: AttackConfig ausente na AttackHitbox")

	# --- Registry único (no Main/autoload) ---
	var reg: ContactArbiterRegistry = _find_registry()
	assert(reg != null, "Hurtbox: ContactArbiterRegistry não encontrado (adicione no Main e marque grupo contact_registry)")

	# --- Arbiter direcional A→B para este par ---
	var arb: ContactArbiter = reg.get_for(attacker_root, defender_root)

	# ===== Conectar ouvintes UMA vez por par =====

	# 1) DEFENSOR: componentes de atributos primeiro (Health, Stamina)
	if defender_root.has_node(^"Health"):
		var def_health: Node = defender_root.get_node(^"Health")
		var cb_def_health: Callable = Callable(def_health, "_on_defender_impact")
		if not arb.defender_impact.is_connected(cb_def_health):
			arb.defender_impact.connect(cb_def_health)
	else:
		push_warning("Hurtbox: nó 'Health' não encontrado em %s" % [defender_root.name])

	if defender_root.has_node(^"Stamina"):
		var def_stamina: Node = defender_root.get_node(^"Stamina")
		var cb_def_stamina: Callable = Callable(def_stamina, "_on_defender_impact")
		if not arb.defender_impact.is_connected(cb_def_stamina):
			arb.defender_impact.connect(cb_def_stamina)

		# (Opcional já existente) stamina do DEFENSOR avisa quebra/zerou → controller reage
		# Mantido conforme sua implementação anterior.
	else:
		push_warning("Hurtbox: nó 'Stamina' não encontrado em %s" % [defender_root.name])

	# 2) Controllers (DEFENSOR e ATACANTE) por último (estado decide após HP/SP aplicados)
	var def_cc: CombatController = defender_root.get_node(^"CombatController") as CombatController
	var atk_cc: CombatController = attacker_root.get_node(^"CombatController") as CombatController
	assert(def_cc != null and atk_cc != null, "Hurtbox: CombatController ausente em attacker/defender")

	# Defender recebe defender_impact
	var cb_def_cc: Callable = Callable(def_cc, "_on_defender_impact")
	if not arb.defender_impact.is_connected(cb_def_cc):
		arb.defender_impact.connect(cb_def_cc)

	# Attacker recebe attacker_impact
	var cb_atk_cc: Callable = Callable(atk_cc, "_on_attacker_impact")
	if not arb.attacker_impact.is_connected(cb_atk_cc):
		arb.attacker_impact.connect(cb_atk_cc)

	# (Opcional já existente) Conexão de evento da Stamina → Controller (ex.: emptied → GUARD_BROKEN)
	if defender_root.has_node(^"Stamina"):
		var stamina_node: Node = defender_root.get_node(^"Stamina")
		var cb_empty: Callable = Callable(def_cc, "_on_stamina_emptied")
		if not stamina_node.is_connected("emptied", cb_empty):
			stamina_node.connect("emptied", cb_empty)

	# ===== Agora sim, resolver o impacto =====
	arb.resolve(cfg)

func _find_registry() -> ContactArbiterRegistry:
	var n: Node = get_tree().get_first_node_in_group("contact_registry")
	if n == null:
		return null
	return n as ContactArbiterRegistry
