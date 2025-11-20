extends Node2D
class_name WasteBeaker

## Zlewka na odpady.
## Umożliwia:
## - wylanie zawartości probówki (czyszczenie mieszaniny + reset wizualny),
## - zrzucenie porcji cieczy z droppera w trybie TRANSFER,
## - „oddanie” kropli z pipety w trybie HOLDING (tylko efekt, bez chemii w zlewce).
## Sama zlewka nie jest źródłem cieczy – wszystkie funkcje take_* zwracają null.

# --- węzły sceny ---
@onready var area: Area2D              = $Area2D
@onready var sprite: Sprite2D          = $Sprite2D
@onready var snd: AudioStreamPlayer2D  = $AudioStreamPlayer2D

# --- konfiguracja hover / interakcji ---
@export var hover_enabled: bool = true                  ## Czy zlewka w ogóle ma reagować podświetleniem.
@export var accepts_holding_pipette: bool = true        ## Czy klik w trybie HOLDING ma konsumować kroplę.
@export var accept_radius_px: float = 80.0              ## Promień trafienia, gdy overlap nie zadziała.

# --- outline (shader) ---
var outline_material: ShaderMaterial = null             ## Lokalna kopia materiału shadera.
@export var hover_outline_strength: float = 1.0         ## Siła podświetlenia przy hoverze.

var _cursor_inside: bool = false                        ## Czy kursor aktualnie leży w obszarze Area2D.

# --- audio ---
@export var play_sound_on_probe_dump: bool = true
@export var play_sound_on_dropper_pour: bool = false
@export var play_sound_on_holding_pipette: bool = false

@export var sfx_probe_dump: AudioStream
@export var sfx_dropper_pour: AudioStream
@export var sfx_holding_pipette: AudioStream


func _enter_tree() -> void:
	## Rejestracja zlewki jako „dropzony” dla probówek.
	add_to_group("probe_dropzones")


func _ready() -> void:
	## Przygotowanie Area2D i materiału dla outline’u.
	if area:
		area.input_pickable = true
		area.monitoring = true
		area.monitorable = true

	if sprite and sprite.material:
		sprite.material = sprite.material.duplicate()
	outline_material = sprite.material as ShaderMaterial
	_set_outline(false)


func _process(_dt: float) -> void:
	## Co klatkę aktualizujemy decyzję o podświetleniu (np. gdy probówka przejeżdża nad zlewką).
	_update_outline_interaction()


# -------------------------------------------------------------------
# KLIK W ZLEWKĘ (dropper / pipeta)
# -------------------------------------------------------------------
func _on_area_input(_vp: Node, event: InputEvent, _shape_idx: int) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return

	var lab := get_tree().get_first_node_in_group("lab_root")
	if lab == null:
		return

	var ModeEnum: Variant = lab.get("Mode")
	var current_mode: Variant = lab.get("mode")

	# 1) TRANSFER – dropper w ręku, wylewamy zawartość do zlewki
	if current_mode == ModeEnum.TRANSFER:
		var dropper_has_content := bool(lab.get("dropper_loaded"))
		if dropper_has_content and lab.has_method("_dropper_drop"):
			# Lab wewnętrznie woła receive_mixture(...) na tym obiekcie.
			lab._dropper_drop(self)
			get_viewport().set_input_as_handled()
		return

	# 2) HOLDING – pipeta w ręku, opcjonalnie „konsumpcja” jednej kropli (bez zapisywania chemii)
	if current_mode == ModeEnum.HOLDING and accepts_holding_pipette:
		var reagent_id := String(lab.get("active_reagent_id"))
		if reagent_id != "":
			receive_drop(reagent_id)
			get_viewport().set_input_as_handled()
		return


# -------------------------------------------------------------------
# DROPZONA DLA PROBÓWEK
# -------------------------------------------------------------------
func accept_probe(probe: Node, at_global_pos: Vector2) -> bool:
	## Zlewka nigdy nie przejmuje probówki jako dziecka – zawsze zwraca false.
	## Jedyna logika to „wylanie” zawartości, jeśli probówka faktycznie trafi w obszar zlewki.
	if probe == null:
		return false

	if not _is_probe_over_me(probe, at_global_pos):
		return false

	var has_liquid := false
	if probe.has_method("has_any_liquid"):
		has_liquid = bool(probe.has_any_liquid())

	var has_pellet := false
	if probe.has_method("_has_pellet_ready"):
		has_pellet = bool(probe._has_pellet_ready())

	# Jeżeli probówka jest całkowicie pusta, nie reagujemy.
	if not (has_liquid or has_pellet):
		return false

	# Prosta animacja przechylenia w stronę zlewki (po stronie Probe.gd).
	if probe.has_method("request_dump_anim"):
		probe.request_dump_anim()

	# 1) Zerowanie wizualnego poziomu cieczy.
	if probe.has_method("_set_fill_level"):
		probe._set_fill_level(0.0)
	else:
		if probe.has_method("set"):
			probe.set("fill_level", 0.0)
		if probe.has_method("_apply_liquid_fill_visual"):
			probe._apply_liquid_fill_visual()

	# 2) Wyczyszczenie stanu chemicznego.
	if probe.has_method("_clear_contents_completely"):
		probe._clear_contents_completely()

	# Efekt dźwiękowy dla zrzutu zawartości probówki.
	_play_sfx_probe()

	# Probówka wraca później na swoje miejsce (tween po jej stronie), więc tu zawsze false.
	return false


func _is_probe_over_me(probe: Node, at_global_pos: Vector2) -> bool:
	## Sprawdzanie, czy probówka wylądowała nad zlewką:
	## najpierw overlap po Area2D, a gdy się nie uda – prosty test w promieniu.
	if area and area.monitoring and area.monitorable:
		var probe_area := probe.get_node_or_null("ProbeArea2D") as Area2D
		if probe_area:
			probe_area.monitorable = true
			probe_area.monitoring = true
			var overlaps := area.get_overlapping_areas()
			if overlaps.has(probe_area):
				return true

	var center := (area.global_position if area else global_position)
	return center.distance_to(at_global_pos) <= accept_radius_px


# -------------------------------------------------------------------
# „SINK” DLA DROPPERA I PIPETY
# -------------------------------------------------------------------
func receive_mixture(_m: Mixture, _units: float = 0.0) -> void:
	## Dropper wylewa mieszaninę do zlewki – chemia nie jest nigdzie zapisywana,
	## zostaje tylko efekt dźwiękowy (jeżeli włączony).
	_play_sfx_dropper()


func receive_drop(_reagent_id: String) -> void:
	## Jedna kropla z pipety w trybie HOLDING – również tylko SFX, bez śledzenia składu.
	_play_sfx_holding()


# Zlewka nie jest źródłem cieczy – funkcje pobierające zawsze zwracają brak danych.
func has_any_liquid() -> bool:
	return false

func take_volume(_units: float):
	return null

func take_sample(_frac: float) -> Mixture:
	return null

func take_fraction(_f: float) -> Mixture:
	return null


# -------------------------------------------------------------------
# GLOBALNE HIGHLIGHTY (Settings)
# -------------------------------------------------------------------
func _are_global_highlights_enabled() -> bool:
	## Sprawdzenie globalnego przełącznika highlightów w autoload `Settings` (jeśli istnieje).
	var settings_node := get_tree().get_root().get_node_or_null("Settings")
	if settings_node:
		if settings_node.has_method("are_highlights_enabled"):
			return bool(settings_node.are_highlights_enabled())
		elif "highlights_enabled" in settings_node:
			return bool(settings_node.highlights_enabled)
	# Brak Settings → przyjmujemy, że highlighty są włączone.
	return true


# -------------------------------------------------------------------
# HOVER / OUTLINE
# -------------------------------------------------------------------
func _on_mouse_entered() -> void:
	_cursor_inside = true
	_update_outline_interaction()


func _on_mouse_exited() -> void:
	_cursor_inside = false
	_set_outline(false)


func _update_outline_interaction() -> void:
	## Decyzja, czy zlewka powinna być aktualnie podświetlona:
	## bierzemy pod uwagę lokalną flagę, globalne ustawienia oraz faktyczną interakcję.
	if not hover_enabled:
		_set_outline(false)
		return

	if not _are_global_highlights_enabled():
		_set_outline(false)
		return

	var can_by_probe := _any_probe_with_liquid_over_me()

	var can_by_dropper := false
	var lab := get_tree().get_first_node_in_group("lab_root")
	if lab:
		var ModeEnum: Variant = lab.get("Mode")
		var current_mode: Variant = lab.get("mode")
		can_by_dropper = (current_mode == ModeEnum.TRANSFER) and bool(lab.get("dropper_loaded"))

	# Jeśli trzymamy LMB i nie ma realnej interakcji, gasimy outline.
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not (can_by_probe or can_by_dropper):
		_set_outline(false)
		return

	# Wrażenie „hoveru”: kursor lub probówka nad zlewką + realna możliwość użycia.
	var hover_ok := _cursor_inside or can_by_probe
	_set_outline(hover_ok and (can_by_probe or can_by_dropper))


func _any_probe_with_liquid_over_me() -> bool:
	## Sprawdza, czy jakakolwiek probówka z cieczą overlapuje Area2D zlewki.
	if area == null or not (area.monitoring and area.monitorable):
		return false

	for a in area.get_overlapping_areas():
		var overlap_area := a as Area2D
		if overlap_area == null:
			continue

		var probe := overlap_area.get_parent()
		if probe and probe.is_in_group("probes"):
			if probe.has_method("has_any_liquid") and probe.has_any_liquid():
				return true
			if probe.has_method("get"):
				var lvl: Variant = probe.get("fill_level")
				if (lvl is float or lvl is int) and float(lvl) > 0.001:
					return true

	return false


func _set_outline(on: bool) -> void:
	if outline_material == null:
		return
	_set_shader_param_safe(outline_material, "highlight", on)
	var strength := hover_outline_strength if on else 0.0
	_set_shader_param_safe(outline_material, "highlight_strength", strength)


func _set_shader_param_safe(m: ShaderMaterial, param_name: String, value) -> void:
	## Helper: ustawia parametr shadera tylko wtedy, gdy shader faktycznie go definiuje.
	if m == null or m.shader == null:
		return
	for u in m.shader.get_shader_uniform_list():
		var ud: Dictionary = u
		if String(ud.get("name", "")) == param_name:
			m.set_shader_parameter(param_name, value)
			return


# -------------------------------------------------------------------
# AUDIO
# -------------------------------------------------------------------
func _play_stream(stream: AudioStream) -> void:
	if snd == null or stream == null:
		return
	snd.stream = stream
	snd.play()


func _play_sfx_probe() -> void:
	if play_sound_on_probe_dump:
		_play_stream(sfx_probe_dump)


func _play_sfx_dropper() -> void:
	if play_sound_on_dropper_pour:
		_play_stream(sfx_dropper_pour)


func _play_sfx_holding() -> void:
	if play_sound_on_holding_pipette:
		_play_stream(sfx_holding_pipette)
