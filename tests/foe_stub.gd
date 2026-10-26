extends Monster
## A monster that would fight only the ones it is given, for resident_test
## (675, npc's side): residents hold their tongue near it.

var fights: Array = []


func threatens(entity: GridEntity) -> bool:
	return entity in fights
