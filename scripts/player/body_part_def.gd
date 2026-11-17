class_name BodyPartDef
extends PropDef
## Definição de um membro corporal modular (orgânico ou implante cyberpunk).
## Como herda de PropDef, qualquer membro removido existe no mundo como um Prop físico
## que pode ser carregado, vendido na zona de extração ou implantado em um jogador.

enum Slot {
	HEAD,
	TORSO,
	LEFT_ARM,
	RIGHT_ARM,
	LEFT_LEG,
	RIGHT_LEG,
}

enum Rarity { GREEN, BLUE, PURPLE, GOLD }

const ALL_SLOTS: Array[Slot] = [
	Slot.HEAD,
	Slot.TORSO,
	Slot.LEFT_ARM,
	Slot.RIGHT_ARM,
	Slot.LEFT_LEG,
	Slot.RIGHT_LEG,
]

@export var slot: Slot = Slot.LEFT_ARM
@export var is_cybernetic := false
## Força de pegada (N) somada quando instalado em um slot de braço.
## Dois braços orgânicos (175 N cada) somam os 350 N padrão.
@export var grip_force := 0.0
## Contribuição para a velocidade de movimento quando instalado em um slot de perna (0.5 por perna padrão).
@export var leg_speed_factor := 0.0
## Contribuição para o impulso de pulo quando instalado em um slot de perna (0.5 por perna padrão).
@export var leg_jump_factor := 0.0
## Se verdadeiro, remover este membro incapacita/mata o jogador imediatamente (cabeça e tronco).
@export var vital := false
## Raridade do implante; define cor e nome exibidos na interface.
@export var rarity: Rarity = Rarity.GREEN
## Velocidade de queda segura (m/s) somada por perna instalada.
@export var fall_speed_bonus := 0.0
## Tremor (m) do alvo de segurar quando correndo com itens frágeis.
@export var grip_jitter := 0.0
## Fração de dano reduzido (0 a 1).
@export var damage_reduction := 0.0
## Multiplicador da regeneração de stamina.
@export var stamina_regen_mult := 1.0
## Multiplicador da velocidade de movimento.
@export var move_speed_mult := 1.0
## Multiplicador do ruído produzido pela voz.
@export var voice_noise_mult := 1.0
## Identificador da habilidade ativa concedida pelo implante.
@export var ability_id: StringName = &""


static func rarity_color(r: Rarity) -> Color:
	match r:
		Rarity.GREEN:
			return Color("4CAF50")
		Rarity.BLUE:
			return Color("29B6F6")
		Rarity.PURPLE:
			return Color("AB47BC")
		Rarity.GOLD:
			return Color("FFB300")
	return Color.WHITE


static func rarity_name(r: Rarity) -> String:
	match r:
		Rarity.GREEN:
			return "Verde"
		Rarity.BLUE:
			return "Azul"
		Rarity.PURPLE:
			return "Roxa"
		Rarity.GOLD:
			return "Dourada"
	return "Desconhecida"


static func slot_name(p_slot: Slot) -> String:
	match p_slot:
		Slot.HEAD:
			return "Cabeça"
		Slot.TORSO:
			return "Tronco"
		Slot.LEFT_ARM:
			return "Braço Esq."
		Slot.RIGHT_ARM:
			return "Braço Dir."
		Slot.LEFT_LEG:
			return "Perna Esq."
		Slot.RIGHT_LEG:
			return "Perna Dir."
	return "Membro"


static func is_arm_slot(p_slot: Slot) -> bool:
	return p_slot == Slot.LEFT_ARM or p_slot == Slot.RIGHT_ARM


static func is_leg_slot(p_slot: Slot) -> bool:
	return p_slot == Slot.LEFT_LEG or p_slot == Slot.RIGHT_LEG


static func pair_slot(p_slot: Slot) -> int:
	match p_slot:
		Slot.LEFT_ARM:
			return Slot.RIGHT_ARM
		Slot.RIGHT_ARM:
			return Slot.LEFT_ARM
		Slot.LEFT_LEG:
			return Slot.RIGHT_LEG
		Slot.RIGHT_LEG:
			return Slot.LEFT_LEG
	return -1

