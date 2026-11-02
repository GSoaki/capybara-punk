class_name ItemDef
extends Resource
## Dados de um item encontrado no chão. Crie um .tres e adicione a item_table da cena main.

enum Kind { NONE, REVOLVER, BATON, GRENADE, AMMO }

@export var kind := Kind.AMMO
@export var display_name := "Item"
@export var size := Vector3(0.2, 0.2, 0.2)
@export var color := Color.WHITE
@export var mass := 1.0
## Revólver: balas no tambor. Munição: balas na caixa. Demais itens ignoram.
@export var amount := 1
## Quanto o item quica depois de arremessado, de 0 a 1.
@export var bounce := 0.2
## Peso relativo no sorteio.
@export var spawn_weight := 1.0
