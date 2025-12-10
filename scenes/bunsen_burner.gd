extends Node2D
class_name BunsenBurner

## =========================================================================
## bunsen_burner.gd – palnik Bunsena
## -------------------------------------------------------------------------
## Odpowiada za:
## - przełączanie płomienia między stanami OFF / YELLOW / BLUE,
## - reagowanie na kliknięcia w kurek (ValveArea2D),
## - reagowanie na wejście i wyjście kursora z płomienia (FlameArea2D),
## - sterowanie shaderem płomienia (flame_mode, test_color, height_scale),
## - prostą logikę próby płomieniowej na podstawie jonów w próbce.
## =========================================================================

# -----------------------------
# WĘZŁY SCENY
# -----------------------------

@onready var valve_area: Area2D     = $ValveArea2D
@onready var valve_sprite: Sprite2D = $ValveArea2D/Valve

@onready var flame_area: Area2D     = $FlameArea2D
@onready var flame_sprite: Sprite2D = $FlameArea2D/Flame


# -----------------------------
# STAN PALNIKA
# -----------------------------

enum FlameState { OFF, YELLOW, BLUE }

var flame_state: FlameState = FlameState.OFF

var _flame_material: ShaderMaterial = null

@export var test_duration_sec: float = 2.0
var _test_timer: Timer = null


# -----------------------------
# SYGNAŁY
# -----------------------------

signal flame_state_changed(burner: BunsenBurner, state: int)
signal flame_entered(burner: BunsenBurner)
signal flame_test_finished(burner: BunsenBurner)
signal flame_exited(burner: BunsenBurner)


# =========================================================================
# START
# =========================================================================

## Inicjalizuje palnik: ładuje materiał shadera, tworzy timer i gasi płomień.
func _ready() -> void:
	_flame_material = flame_sprite.material as ShaderMaterial

	_test_timer = Timer.new()
	_test_timer.one_shot = true
	add_child(_test_timer)
	_test_timer.timeout.connect(_on_test_timeout)

	_set_flame_state(FlameState.OFF)


# =========================================================================
# OBSŁUGA KURKA (ValveArea2D)
# =========================================================================

## Sprawdza, czy Lab jest w trybie IDLE (tylko wtedy można ruszać kurek).
func _lab_is_idle() -> bool:
	var lab := get_tree().get_first_node_in_group("lab_root")
	if lab == null:
		return true
	return lab.mode == lab.Mode.IDLE


## Obsługuje kliknięcia w kurek gazu (LPM – cykle, PPM – gaszenie).
func _on_valve_area_input_event(_viewport: Viewport, event: InputEvent, _shape_idx: int) -> void:
	if not _lab_is_idle():
		return

	var mouse_event := event as InputEventMouseButton
	if mouse_event == null or not mouse_event.pressed:
		return

	if mouse_event.button_index == MOUSE_BUTTON_LEFT:
		_cycle_flame_state()
		get_viewport().set_input_as_handled()
	elif mouse_event.button_index == MOUSE_BUTTON_RIGHT:
		if flame_state != FlameState.OFF:
			_set_flame_state(FlameState.OFF)
			get_viewport().set_input_as_handled()


## Przełącza stan płomienia: OFF → YELLOW → BLUE → OFF.
func _cycle_flame_state() -> void:
	match flame_state:
		FlameState.OFF:
			_set_flame_state(FlameState.YELLOW)
		FlameState.YELLOW:
			_set_flame_state(FlameState.BLUE)
		FlameState.BLUE:
			_set_flame_state(FlameState.OFF)


## Ustawia stan płomienia i aktualizuje widoczność oraz tryb shadera.
func _set_flame_state(new_state: FlameState) -> void:
	flame_state = new_state

	match flame_state:
		FlameState.OFF:
			flame_sprite.visible = false
			_clear_flame_test_color()
		FlameState.YELLOW:
			flame_sprite.visible = true
			_update_flame_shader_mode(0)
			_clear_flame_test_color()
		FlameState.BLUE:
			flame_sprite.visible = true
			_update_flame_shader_mode(1)

	flame_state_changed.emit(self, int(flame_state))


# =========================================================================
# OBSŁUGA PŁOMIENIA (FlameArea2D)
# =========================================================================

## Sygnał wejścia kursora w płomień – Lab może wtedy sprawdzić drucik.
func _on_flame_area_mouse_entered() -> void:
	if flame_state == FlameState.OFF:
		return
	flame_entered.emit(self)


## Sygnał wyjścia kursora z płomienia – czyści efekt i zgłasza flame_exited.
func _on_flame_area_mouse_exited() -> void:
	_clear_flame_test_color()
	flame_exited.emit(self)


# =========================================================================
# PRÓBA PŁOMIENIOWA
# =========================================================================

## Ustawia kolor płomienia na podstawie jonów z próbki i odpala timer spalania.
func apply_flame_test_for_ions(ions: Dictionary) -> void:
	if flame_state != FlameState.BLUE:
		return
	if _flame_material == null:
		return
	if ions.size() == 0:
		return

	var test_color: Color = _pick_test_color_from_ions(ions)
	var has_colored_reaction := (test_color.a > 0.0)

	if has_colored_reaction:
		_flame_material.set_shader_parameter("test_color", test_color)
		_flame_material.set_shader_parameter("test_mix", 0.8)
		_flame_material.set_shader_parameter("use_test_color", true)
		_flame_material.set_shader_parameter("height_scale", 1.2)
	else:
		# brak charakterystycznej barwy – płomień zostaje niebieski,
		# ale i tak po 2 s. próbka na druciku zostanie spalona po stronie Lab.
		_clear_flame_test_color()

	if _test_timer:
		_test_timer.start(test_duration_sec)


## Wybiera kolor płomienia dla wybranych kationów (Na, K, Ba, Sr, Ca, Cu).
func _pick_test_color_from_ions(ions: Dictionary) -> Color:
	var result := Color(0, 0, 0, 0)

	for ion_name in ions.keys():
		var id := String(ion_name)

		# kolejność: słabsze barwy na górze, mocne (Na) na końcu
		match id:
			"K+":
				result = Color(0.8, 0.5, 1.0, 1.0)      # fioletowy (K)
			"Ca2+":
				result = Color(1.0, 0.55, 0.3, 1.0)     # ceglasty (Ca)
			"Sr2+":
				result = Color(1.0, 0.45, 0.2, 1.0)     # ceglasty (Sr)
			"Cu2+":
				result = Color(0.3, 1.0, 0.9, 1.0)      # niebiesko-zielony (Cu)
			"Ba2+":
				result = Color(0.6, 1.0, 0.4, 1.0)      # zielonkawy (Ba)
			"Na+":
				result = Color(1.0, 0.9, 0.4, 1.0)      # żółty (Na)
			_:
				pass

		if result.a > 0.0:
			break

	return result


## Czyści efekt barwienia w shaderze i zatrzymuje licznik testu.
func _clear_flame_test_color() -> void:
	if _flame_material:
		_flame_material.set_shader_parameter("use_test_color", false)
		_flame_material.set_shader_parameter("height_scale", 1.0)

	if _test_timer and not _test_timer.is_stopped():
		_test_timer.stop()


## Wywoływane po upływie test_duration_sec – kończy próbę płomieniową.
func _on_test_timeout() -> void:
	_clear_flame_test_color()
	flame_test_finished.emit(self)


# =========================================================================
# WIZUAL – SHADER PŁOMIENIA
# =========================================================================

## Ustawia tryb płomienia (0 – żółty, 1 – niebieski) w shaderze.
func _update_flame_shader_mode(mode_value: int) -> void:
	if _flame_material:
		_flame_material.set_shader_parameter("flame_mode", mode_value)
