class_name EnemyBrain
extends RefCounted
## Скрытое состояние ОДНОГО противника, даже если EnemyData общий.
## Только числа/веса/кулдауны. Связи участников и эффекты — контроллер.

var aggression: float = 0.0
var irritation: float = 0.0
var lust: float = 0.0
var stun_chain: int = 0
var stun_memory: float = 0.0
var stun_guard: float = 0.0
var stun_remaining: float = 0.0
var _enemy: EnemyData
var _cooldowns: Dictionary = {}


func _init(enemy: EnemyData) -> void:
	_enemy = enemy
	aggression = clampf(enemy.base_aggression, 0.0, 100.0)
	irritation = clampf(enemy.base_irritation, 0.0, 100.0)
	lust = clampf(enemy.base_lust, 0.0, 100.0)


## Возвращает true только при переходе похоти в следующий диапазон 20.
## Не перебрасываем намерение случайно на каждом кадре.
func advance(seconds: float, attractiveness: float) -> bool:
	var old_band := floori(lust / 20.0)
	lust = clampf(lust + (_enemy.passive_lust_per_second + maxf(0.0, attractiveness) * _enemy.lust_per_attractiveness) * seconds, 0.0, 100.0)
	irritation = maxf(_enemy.base_irritation, irritation - _enemy.irritation_decay_per_second * seconds)
	stun_guard = maxf(0.0, stun_guard - seconds)
	stun_remaining = maxf(0.0, stun_remaining - seconds)
	stun_memory = maxf(0.0, stun_memory - seconds)
	if stun_memory <= 0.0:
		stun_chain = 0
	for attack in _cooldowns.keys():
		_cooldowns[attack] = maxf(0.0, float(_cooldowns[attack]) - seconds)
	return floori(lust / 20.0) != old_band


func react_to_player_attack(is_kick: bool) -> void:
	aggression = clampf(aggression + _enemy.aggression_on_hit, 0.0, 100.0)
	var irritation_gain := _enemy.irritation_on_hit * (1.5 if is_kick else 1.0)
	irritation = clampf(irritation + irritation_gain, 0.0, 100.0)


func set_emotions(new_aggression: float, new_irritation: float, new_lust: float) -> void:
	aggression = clampf(new_aggression, 0.0, 100.0)
	irritation = clampf(new_irritation, 0.0, 100.0)
	lust = clampf(new_lust, 0.0, 100.0)


func get_weight(attack: EnemyAttack) -> float:
	return maxf(0.0, attack.base_weight + aggression * attack.aggression_weight + irritation * attack.irritation_weight + lust * attack.lust_weight)


func is_available(attack: EnemyAttack, player_immobilized: bool) -> bool:
	return attack != null and float(_cooldowns.get(attack, 0.0)) <= 0.0 and aggression >= attack.min_aggression and irritation >= attack.min_irritation and lust >= attack.min_lust and (not attack.requires_immobilized or player_immobilized)


func mark_used(attack: EnemyAttack) -> void:
	_cooldowns[attack] = maxf(0.0, attack.cooldown_seconds)


func choose(candidates: Array[EnemyAttack]) -> EnemyAttack:
	var total := 0.0
	for attack in candidates:
		total += get_weight(attack)
	if total <= 0.0:
		return null
	var roll := randf() * total
	for attack in candidates:
		roll -= get_weight(attack)
		if roll < 0.0:
			return attack
	return candidates.back()


func get_debug_text() -> String:
	return "AI — агр. %.0f · раздр. %.0f · похоть %.0f" % [aggression, irritation, lust]
