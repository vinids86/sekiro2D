# res://combat/StatusEffects.gd
extends RefCounted
class_name StatusEffects

signal expired(name: String)

var _map: Dictionary = {} # name: String -> time_left: float

func apply(name: String, duration: float) -> void:
	# duração <= 0 remove o efeito (mantém semântica anterior)
	if duration <= 0.0:
		if _map.erase(name):
			# opcional: não emitir sinal aqui para não confundir "remoção manual" com expiração
			pass
	else:
		_map[name] = duration

func has(name: String) -> bool:
	return _map.has(name)

func time_left(name: String) -> float:
	if _map.has(name):
		return float(_map[name])
	return 0.0

func clear(name: String) -> void:
	_map.erase(name)

func clear_all() -> void:
	_map.clear()

func tick(delta: float) -> void:
	if _map.is_empty():
		return
	var expired_list: Array[String] = []
	for k in _map.keys():
		var key: String = k as String
		var t: float = float(_map[key]) - delta
		if t <= 0.0:
			expired_list.append(key)
		else:
			_map[key] = t
	for key in expired_list:
		_map.erase(key)
		expired.emit(key)
