extends Control
## Menu principal exibido fora de sessão. Permite criar ou entrar numa sala usando
## Epic Online Services (código da sala P2P sem precisar de IP) ou via LAN/ENet local.

@onready var name_edit: LineEdit = %NameEdit
@onready var address_label: Label = %AddressLabel
@onready var address_edit: LineEdit = %AddressEdit
@onready var use_lan: CheckBox = %UseLan
@onready var eos_status_label: Label = %EosStatus
@onready var status: Label = %Status

var _busy := false


func _ready() -> void:
	name_edit.text = Settings.player_name
	%DisableEnemies.button_pressed = Game.enemies_disabled
	%DisableEnemies.toggled.connect(func(on: bool) -> void: Game.set_enemies_disabled(on))
	Game.enemies_disabled_changed.connect(func(on: bool) -> void: %DisableEnemies.set_pressed_no_signal(on))
	use_lan.toggled.connect(_on_mode_toggled)
	%HostButton.pressed.connect(_on_host)
	%JoinButton.pressed.connect(_on_join)
	multiplayer.connection_failed.connect(func() -> void:
		_busy = false
		_refresh_ui()
	)
	Net.eos_status_changed.connect(_on_eos_status_changed)
	_on_eos_status_changed(Net.eos_ready, Net.eos_status)
	_refresh_mode_fields()


func show_status(text: String) -> void:
	_busy = false
	status.text = text
	_refresh_ui()


func _on_eos_status_changed(ready: bool, text: String) -> void:
	eos_status_label.text = text
	if ready:
		eos_status_label.modulate = Color("76b041")
		if use_lan.button_pressed and not _busy:
			use_lan.set_pressed_no_signal(false)
			_refresh_mode_fields()
	elif Net.eos_connecting:
		eos_status_label.modulate = Color("f2c14e")
	else:
		eos_status_label.modulate = Color(0.7, 0.75, 0.82)
		if not use_lan.button_pressed:
			use_lan.set_pressed_no_signal(true)
			_refresh_mode_fields()
	_refresh_ui()


func _on_mode_toggled(_lan_enabled: bool) -> void:
	_refresh_mode_fields()
	_refresh_ui()


func _refresh_mode_fields() -> void:
	if use_lan.button_pressed:
		address_label.text = "Endereço do host (LAN / IP)"
		address_edit.placeholder_text = "127.0.0.1"
		address_edit.text = Settings.last_address
		%HostButton.text = "Hospedar (LAN)"
		%JoinButton.text = "Entrar (IP)"
	else:
		address_label.text = "Código da sala (para entrar)"
		address_edit.placeholder_text = "Ex: A4K9P2"
		address_edit.text = Settings.last_room_code
		%HostButton.text = "Criar Sala"
		%JoinButton.text = "Entrar com Código"


func _refresh_ui() -> void:
	var can_act := not _busy and (use_lan.button_pressed or Net.eos_ready)
	%HostButton.disabled = not can_act
	%JoinButton.disabled = not can_act


func _on_host() -> void:
	_store()
	if use_lan.button_pressed:
		if Net.host() != OK:
			show_status("Falha ao abrir a porta %d." % Net.DEFAULT_PORT)
		return

	_busy = true
	status.text = "Criando sala na Epic Games..."
	_refresh_ui()
	var code := await Net.host_eos_async()
	_busy = false
	if code.is_empty():
		show_status("Não foi possível criar a sala online.")
	else:
		DisplayServer.clipboard_set(code)
		status.text = "Sala criada: %s (copiado!)" % code
		_refresh_ui()


func _on_join() -> void:
	_store()
	if use_lan.button_pressed:
		if Net.join(Settings.last_address) != OK:
			show_status("Endereço inválido.")
			return
		_busy = true
		status.text = "Conectando via LAN..."
		_refresh_ui()
		return

	var code := Settings.last_room_code.strip_edges().to_upper()
	if code.is_empty():
		show_status("Digite o código da sala para entrar.")
		return

	_busy = true
	status.text = "Buscando sala %s..." % code
	_refresh_ui()
	var err := await Net.join_eos_by_code_async(code)
	if err == ERR_DOES_NOT_EXIST:
		show_status("Sala '%s' não encontrada." % code)
	elif err != OK:
		show_status("Falha ao entrar na sala '%s'." % code)
	else:
		status.text = "Conectando ao host da sala %s..." % code


func _store() -> void:
	Settings.player_name = name_edit.text.strip_edges()
	if use_lan.button_pressed:
		Settings.last_address = address_edit.text.strip_edges()
	else:
		Settings.last_room_code = address_edit.text.strip_edges().to_upper()
	Settings.save()
