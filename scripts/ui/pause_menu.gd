extends Control


func _ready() -> void:
	%Sensitivity.value = Settings.mouse_sensitivity * 1000.0
	%Mic.button_pressed = Settings.voice_enabled
	%PushToTalk.button_pressed = Settings.voice_push_to_talk
	%Sensitivity.value_changed.connect(func(v: float) -> void: Settings.mouse_sensitivity = v / 1000.0)
	%Mic.toggled.connect(_on_mic_toggled)
	%PushToTalk.toggled.connect(func(on: bool) -> void: Settings.voice_push_to_talk = on)
	%Resume.pressed.connect(_on_resume)
	%Leave.pressed.connect(_on_leave)
	visibility_changed.connect(_on_visibility_changed)


func _on_visibility_changed() -> void:
	if not visible:
		Settings.save()


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
