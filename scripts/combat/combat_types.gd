extends Resource
class_name CombatTypes

enum AttackKind { LIGHT, HEAVY, COUNTER, FINISHER, COMBO }

# Estados globais finais e enxutos
enum CombatState {
	IDLE,
	ATTACK,
	PARRY,
	PARRIED,
	DODGE,
	STUNNED,
	GUARD_BROKEN,
	DEAD
}

enum DodgeDir {
	NEUTRAL,
	UP,
	DOWN,
	LEFT,
	RIGHT,
}
