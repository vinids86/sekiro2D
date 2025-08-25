extends Resource
class_name CombatTypes

# Estados mínimos da FSM + dodge
enum CombatState {
	IDLE,
	STARTUP,
	ATTACKING,
	RECOVERING,
	DODGE_STARTUP,
	DODGE_ACTIVE,
	DODGE_RECOVER
}

# Direções de dodge que vamos usar agora
enum DodgeDir {
	NEUTRAL,  # 0
	DOWN      # 1
}
