extends Control
## Menu principal exibido fora de sessão. Lê/salva nome e endereço em Settings, permite
## alternar a opção de desativar inimigos e inicia conexões ENet como host ou cliente.

@onready var name_edit: LineEdit = %NameEdit
@onready var address_edit: LineEdit = %AddressEdit
@onready var status: Label = %Status


func _ready() -> void:
	name_edit.text = Settings.player_name
	address_edit.text = Settings.last_address
	%DisableEnemies.button_pressed = Game.enemies_disabled
	%DisableEnemies.toggled.connect(func(on: bool) -> void: Game.set_enemies_disabled(on))
	Game.enemies_disabled_changed.connect(func(on: bool) -> void: %DisableEnemies.set_pressed_no_signal(on))
	%HostButton.pressed.connect(_on_host)
	%JoinButton.pressed.connect(_on_join)
	multiplayer.connection_failed.connect(_set_buttons.bind(true))


func show_status(text: String) -> void:
	status.text = text
	_set_buttons(true)


func _on_host() -> void:
	_store()
	if Net.host() != OK:
		show_status("Falha ao abrir a porta %d." % Net.DEFAULT_PORT)


func _on_join() -> void:
	_store()
	if Net.join(Settings.last_address) != OK:
		show_status("Endereço inválido.")
		return
	status.text = "Conectando..."
	_set_buttons(false)


func _store() -> void:
	Settings.player_name = name_edit.text.strip_edges()
	Settings.last_address = address_edit.text.strip_edges()
	Settings.save()


func _set_buttons(enabled: bool) -> void:
	%HostButton.disabled = not enabled
	%JoinButton.disabled = not enabled
