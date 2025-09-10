extends Node
class_name BufferController

var _has_buffer: bool = false

func has_buffer() -> bool:
	return _has_buffer

func clear() -> void:
	_has_buffer = false

func capture() -> void:
	_has_buffer = true

# --- LÓGICA DE PERMISSÃO CORRIGIDA ---
# Agora ele apenas pergunta ao OBJETO de estado atual se o buffer é permitido.
# A função 'get_state()' do controller retorna um INT, por isso precisamos
# da 'get_state_instance_for()' para pegar o objeto.
func can_buffer_now(cc: CombatController) -> bool:
	print("can_buffer_now ", cc.phase)
	return cc.get_state_instance_for(cc.get_state()).allows_attack_buffer(cc)

# A função try_consume foi removida. A sua lógica será movida para o
# CombatController para centralizar a execução de ataques.
