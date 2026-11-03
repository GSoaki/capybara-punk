class_name Lever
extends StaticBody3D
## Inicia a run no lobby e chama o resgate durante a run.


func get_prompt() -> String:
	match Game.phase:
		Game.Phase.LOBBY:
			return "Iniciar expedição"
		Game.Phase.RUN:
			return "Encerrar e partir"
	return "Aguarde"


@rpc("any_peer", "call_local", "reliable")
func request_use() -> void:
	if multiplayer.is_server():
		Game.pull_lever()
