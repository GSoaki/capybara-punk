class_name PropDef
extends Resource
## Dados de um tipo de loot. Crie um .tres e adicione ao loot_table da cena main.

@export var display_name := "Objeto"
@export var size := Vector3(0.5, 0.5, 0.5)
@export var color := Color.WHITE
## Massa acima de ~35 kg exige duas pessoas para erguer (ver Prop.GRIP_FORCE).
@export var mass := 5.0
@export var min_value := 20
@export var max_value := 60
## Velocidade de impacto (m/s) a partir da qual o objeto perde valor.
@export var impact_threshold := 6.0
## Fração do valor original perdida por m/s acima do limite.
@export var fragility := 0.1
## Peso relativo no sorteio.
@export var spawn_weight := 1.0
