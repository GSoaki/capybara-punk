extends Control
## Menu de pausa em sessão (tecla Esc). Exibe e copia o código da sala, ajusta sensibilidade
## do mouse, captura de microfone, modo Push-to-Talk, ativação de inimigos e saída da partida.


func _ready() -> void:
	%Sensitivity.value = Settings.mouse_sensitivity * 1000.0
	%Mic.button_pressed = Settings.voice_enabled
	%PushToTalk.button_pressed = Settings.voice_push_to_talk
	%DisableEnemies.button_pressed = Game.enemies_disabled
	%Sensitivity.value_changed.connect(func(v: float) -> void: Settings.mouse_sensitivity = v / 1000.0)
	%Mic.toggled.connect(_on_mic_toggled)
	%PushToTalk.toggled.connect(func(on: bool) -> void: Settings.voice_push_to_talk = on)
	%DisableEnemies.toggled.connect(func(on: bool) -> void: Game.set_enemies_disabled(on))
	Game.enemies_disabled_changed.connect(func(on: bool) -> void: %DisableEnemies.set_pressed_no_signal(on))
	%CopyCode.pressed.connect(_on_copy_code)
	%Resume.pressed.connect(_on_resume)
	%Leave.pressed.connect(_on_leave)
	Net.room_code_changed.connect(func(_code: String) -> void: _refresh_room_code())
	visibility_changed.connect(_on_visibility_changed)
	_refresh_room_code()


func _on_visibility_changed() -> void:
	if visible:
		_refresh_room_code()
	else:
		Settings.save()


func _refresh_room_code() -> void:
	var code := Net.room_code
	%RoomCodeLabel.text = "Código da Sala: %s" % (code if not code.is_empty() else "---")
	%CopyCode.disabled = code.is_empty()
	%CopyCode.text = "Copiar Código"


func _on_copy_code() -> void:
	if Net.room_code.is_empty():
		return
	DisplayServer.clipboard_set(Net.room_code)
	%CopyCode.text = "Copiado!"


func _on_mic_toggled(on: bool) -> void:
	Settings.voice_enabled = on
	if on:
		Voice.start()
	else:
		Voice.stop()


func _on_resume() -> void:
	hide()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_leave() -> void:
	Net.leave()
