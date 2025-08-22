extends CanvasLayer
class_name HUD

# --- Paths obrigatórios (defina no editor) ---
@export var player_path: NodePath
@export var enemy_path: NodePath

# Barras do Player
@export var player_stamina_bar_path: NodePath
@export var player_health_bar_path: NodePath

# Barras do Enemy
@export var enemy_stamina_bar_path: NodePath
@export var enemy_health_bar_path: NodePath

# --- Refs resolvidos no _ready ---
var _player: Node = null
var _enemy: Node = null

var _player_health: Node = null
var _player_stamina: Node = null
var _enemy_health: Node = null
var _enemy_stamina: Node = null

var _p_stamina_bar: TextureProgressBar = null
var _p_health_bar: TextureProgressBar = null
var _e_stamina_bar: TextureProgressBar = null
var _e_health_bar: TextureProgressBar = null

func _ready() -> void:
	# Barras
	_p_stamina_bar = _get_bar(player_stamina_bar_path)
	_p_health_bar  = _get_bar(player_health_bar_path)
	_e_stamina_bar = _get_bar(enemy_stamina_bar_path)
	_e_health_bar  = _get_bar(enemy_health_bar_path)

	# Padroniza barras para percentual [0..1]
	_set_bar_as_percentage(_p_stamina_bar)
	_set_bar_as_percentage(_p_health_bar)
	_set_bar_as_percentage(_e_stamina_bar)
	_set_bar_as_percentage(_e_health_bar)

	# Player
	if player_path != NodePath():
		_player = get_node(player_path)
	else:
		push_error("[HUD] player_path não definido.")
		return

	# Enemy (sempre 1)
	if enemy_path != NodePath():
		_enemy = get_node(enemy_path)
	else:
		push_error("[HUD] enemy_path não definido.")
		return

	# ---- CHAMADAS POSICIONAIS (sem :=) ----
	_connect_entity_stats(
		_player,
		"_player_health",
		"_player_stamina",
		Callable(self, "_on_player_health_changed"),
		Callable(self, "_on_player_stamina_changed")
	)

	_connect_entity_stats(
		_enemy,
		"_enemy_health",
		"_enemy_stamina",
		Callable(self, "_on_enemy_health_changed"),
		Callable(self, "_on_enemy_stamina_changed")
	)

	_refresh_all_bars()

func _get_bar(path: NodePath) -> TextureProgressBar:
	if path == NodePath():
		push_error("[HUD] NodePath de barra não definido.")
		return null
	var node := get_node(path)
	var bar := node as TextureProgressBar
	if bar == null:
		push_error("[HUD] Nó em '%s' não é TextureProgressBar." % [str(path)])
		return null
	return bar

func _set_bar_as_percentage(bar: TextureProgressBar) -> void:
	if bar == null:
		return
	# Trabalha sempre com 0..1
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.step = 0.0  # contínuo

func _connect_entity_stats(
	entity: Node,
	out_health_ref_name: String,
	out_stamina_ref_name: String,
	on_health: Callable,
	on_stamina: Callable
) -> void:
	if entity == null:
		push_error("[HUD] Entidade nula ao conectar stats.")
		return

	var health_node: Node = null
	var stamina_node: Node = null

	if entity.has_node(^"Health"):
		health_node = entity.get_node(^"Health")
	else:
		push_error("[HUD] '%s' não possui nó filho 'Health'." % [entity.name])

	if entity.has_node(^"Stamina"):
		stamina_node = entity.get_node(^"Stamina")
	else:
		push_error("[HUD] '%s' não possui nó filho 'Stamina'." % [entity.name])

	if health_node != null:
		if health_node.has_signal("changed"):
			var ok_h: int = health_node.connect("changed", on_health)
			if ok_h != OK:
				push_error("[HUD] Falha ao conectar 'changed' do Health de %s." % [entity.name])
		else:
			push_error("[HUD] Nó Health de %s não possui sinal 'changed'." % [entity.name])

	if stamina_node != null:
		if stamina_node.has_signal("changed"):
			var ok_s: int = stamina_node.connect("changed", on_stamina)
			if ok_s != OK:
				push_error("[HUD] Falha ao conectar 'changed' do Stamina de %s." % [entity.name])
		else:
			push_error("[HUD] Nó Stamina de %s não possui sinal 'changed'." % [entity.name])

	# Armazena as refs nos campos privados
	set(out_health_ref_name, health_node)
	set(out_stamina_ref_name, stamina_node)

func _refresh_all_bars() -> void:
	# Player
	if _player_health != null:
		var hp_curr: float = _safe_get_number(_player_health, "current")
		var hp_max: float = _safe_get_number(_player_health, "maximum")
		_on_player_health_changed(hp_curr, hp_max)

	if _player_stamina != null:
		var st_curr: float = _safe_get_number(_player_stamina, "current")
		var st_max: float = _safe_get_number(_player_stamina, "maximum")
		_on_player_stamina_changed(st_curr, st_max)

	# Enemy
	if _enemy_health != null:
		var ehp_curr: float = _safe_get_number(_enemy_health, "current")
		var ehp_max: float = _safe_get_number(_enemy_health, "maximum")
		_on_enemy_health_changed(ehp_curr, ehp_max)

	if _enemy_stamina != null:
		var est_curr: float = _safe_get_number(_enemy_stamina, "current")
		var est_max: float = _safe_get_number(_enemy_stamina, "maximum")
		_on_enemy_stamina_changed(est_curr, est_max)

func _safe_get_number(obj: Object, prop: StringName) -> float:
	if obj == null:
		push_error("[HUD] Objeto nulo ao ler propriedade '%s'." % [str(prop)])
		return 0.0
	var v: Variant = obj.get(prop)
	if v == null:
		push_error("[HUD] Propriedade '%s' ausente em %s." % [str(prop), obj])
		return 0.0
	return float(v)

# ---------------- Handlers de sinais ----------------

func _on_player_health_changed(current: float, maximum: float) -> void:
	if _p_health_bar == null:
		return
	var pct: float = 0.0
	if maximum > 0.0:
		pct = clampf(current / maximum, 0.0, 1.0)
	_p_health_bar.value = pct

func _on_player_stamina_changed(current: float, maximum: float) -> void:
	if _p_stamina_bar == null:
		return
	var pct: float = 0.0
	if maximum > 0.0:
		pct = clampf(current / maximum, 0.0, 1.0)
	_p_stamina_bar.value = pct

func _on_enemy_health_changed(current: float, maximum: float) -> void:
	if _e_health_bar == null:
		return
	var pct: float = 0.0
	if maximum > 0.0:
		pct = clampf(current / maximum, 0.0, 1.0)
	_e_health_bar.value = pct

func _on_enemy_stamina_changed(current: float, maximum: float) -> void:
	if _e_stamina_bar == null:
		return
	var pct: float = 0.0
	if maximum > 0.0:
		pct = clampf(current / maximum, 0.0, 1.0)
	_e_stamina_bar.value = pct
