class_name ImplantAbility
extends Node
## Base das habilidades ativas/passivas de implantes. O nome do nó é o ability_id.

var player: Player
var def: BodyPartDef


func setup(p: Player, d: BodyPartDef) -> void:
	player = p
	def = d


## Ganchos virtuais; subclasses sobrescrevem o que precisarem.
func on_landed(_fall_speed: float) -> void:
	pass


func on_hit(_source: Game.HitSource, _damage: int) -> void:
	pass


func on_exhausted() -> void:
	pass


func on_action() -> void:
	pass


func on_hold_tick(_prop: Prop, _delta: float) -> void:
	pass


## Servidor: recebe o pedido enviado pelo dono via send_to_server.
func on_server_request(_payload: Dictionary) -> void:
	pass


func is_server() -> bool:
	return multiplayer.is_server()


func is_owner() -> bool:
	return player != null and player.is_local()


## Dono: envia um pedido ao servidor para esta habilidade.
func send_to_server(payload: Dictionary) -> void:
	player.request_implant_action.rpc_id(1, name, payload)
