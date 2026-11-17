class_name ImplantPool
extends Resource
## Pool de implantes por raridade. Sorteio em dois estágios: raridade (pesos) e depois item uniforme na faixa.

@export var green: Array[BodyPartDef] = []
@export var blue: Array[BodyPartDef] = []
@export var purple: Array[BodyPartDef] = []
@export var gold: Array[BodyPartDef] = []
## Chance de um spot de prop virar um implante.
@export_range(0.0, 1.0) var implant_chance := 0.08
## Pesos das raridades na ordem verde, azul, roxo, dourado.
@export var rarity_weights := PackedFloat32Array([60.0, 28.0, 9.0, 3.0])


func _tiers() -> Array:
	return [green, blue, purple, gold]


## Sorteia a raridade pelos pesos (faixas vazias ficam com peso 0) e depois um item da faixa.
func pick(rng: RandomNumberGenerator) -> BodyPartDef:
	var tiers := _tiers()
	var weights := PackedFloat32Array()
	var total := 0.0
	for i in tiers.size():
		var w := rarity_weights[i] if i < rarity_weights.size() else 0.0
		if (tiers[i] as Array).is_empty():
			w = 0.0
		weights.append(w)
		total += w
	if total <= 0.0:
		return null
	var tier: Array = tiers[rng.rand_weighted(weights)]
	return tier[rng.randi() % tier.size()] as BodyPartDef


## Sorteia somente da faixa verde (null se vazia).
func pick_green(rng: RandomNumberGenerator) -> BodyPartDef:
	if green.is_empty():
		return null
	return green[rng.randi() % green.size()]
