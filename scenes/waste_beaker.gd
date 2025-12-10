extends Node2D
class_name WasteBeaker

## =========================================================================
## waste_beaker.gd – zlewka na odpady
## -------------------------------------------------------------------------
## Odpowiada za:
## - „wylanie” zawartości probówki (czyszczenie mieszaniny + reset wizualny),
## - przyjęcie porcji cieczy z droppera w trybie TRANSFER,
## - proste podświetlanie przy hoverze i sensownej interakcji.
## =========================================================================

# -----------------------------
# Węzły sceny
# -----------------------------

@onready var area: Area2D     = $Area2D
@onready var sprite: Sprite2D = $Sprite2D


# -----------------------------
# Konfiguracja hover / interakcji
# -----------------------------

@export var hover_enabled: bool = true                  ## Czy zlewka reaguje podświetleniem.
@export var accept_radius_px: float = 80.0              ## Promień trafienia, gdy overlap nie zadziała.

var outline_material: ShaderMaterial = null             ## Lokalna kopia materiału shadera outline’u.
@export var hover_outline_strength: float = 1.0         ## Siła podświetlenia przy hoverze.

var _cursor_inside: bool = false                        ## Informuje, czy kursor jest nad Area2D.


# =========================================================================
# INICJALIZACJA
# =========================================================================

## Przygotowuje zlewkę:
## - ustawia Area2D jako pickable/monitoring,
## - wyłącza outline na starcie.
func _ready() -> void:
	if area:
		area.input_pickable = true
		area.monitoring = true
		area.monitorable = true

	if sprite and sprite.material:
		outline_material = sprite.material as ShaderMaterial

	_set_outline(false)


## Aktualizuje stan outline’u co klatkę (np. gdy probówka przejeżdża nad zlewką).
func _process(_delta: float) -> void:
	_update_outline_interaction()


# =========================================================================
# KLIK W ZLEWKĘ (DROPper)
# =========================================================================

## Obsługuje kliknięcie LPM w obszar zlewki:
## - w trybie TRANSFER wylewa zawartość droppera do zlewki (przez Lab),
## - inne tryby są ignorowane.
func _on_area_input(_vp: Node, event: InputEvent, _shape_idx: int) -> void:
	var mouse_button := event as InputEventMouseButton
	if mouse_button == null or not mouse_button.pressed or mouse_button.button_index != MOUSE_BUTTON_LEFT:
		return

	var lab := get_tree().get_first_node_in_group("lab_root")
	if lab == null:
		return

	# Zakładam, że Lab ma enum Mode i pole dropper_loaded (tak jak w lab.gd).
	if lab.mode == lab.Mode.TRANSFER and lab.dropper_loaded and lab.has_method("_dropper_drop"):
		lab._dropper_drop(self)
		get_viewport().set_input_as_handled()


# =========================================================================
# DROPZONA DLA PROBÓWEK
# =========================================================================

## Obsługuje „drop” probówki na zlewkę (probówki nie stają się dzieckiem zlewki):
## - jeżeli probówka faktycznie wylądowała nad zlewką i ma ciecz lub pellet,
##   wylewa jej zawartość (pusta probówka),
## - uruchamia animację przechylenia po stronie Probe.gd,
## - czyści chemiczny stan probówki.
func accept_probe(probe: Node, at_global_pos: Vector2) -> bool:
	if probe == null:
		return false

	if not _is_probe_over_me(probe, at_global_pos):
		return false

	var has_liquid: bool = probe.has_method("has_any_liquid") and probe.has_any_liquid()
	var has_pellet: bool = probe.has_method("_has_pellet_ready") and probe._has_pellet_ready()

	# Jeżeli probówka jest całkowicie pusta, nie reagujemy.
	if not (has_liquid or has_pellet):
		return false

	# Prosta animacja „wylania” po stronie probówki.
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

	# Probówka wraca później na swoje miejsce (tween po jej stronie), więc tu zawsze false.
	return false


## Sprawdza, czy probówka faktycznie „wpadła” nad zlewkę:
## - najpierw sprawdza overlap po Area2D,
## - jeśli to nie zadziała, używa prostego testu odległości w promieniu.
func _is_probe_over_me(probe: Node, at_global_pos: Vector2) -> bool:
	if area and area.monitoring and area.monitorable:
		var probe_area := probe.get_node_or_null("ProbeArea2D") as Area2D
		if probe_area:
			probe_area.monitorable = true
			probe_area.monitoring = true
			var overlaps: Array = area.get_overlapping_areas()
			if overlaps.has(probe_area):
				return true

	var center: Vector2 = (area.global_position if area else global_position)
	return center.distance_to(at_global_pos) <= accept_radius_px


# =========================================================================
# „SINK” DLA DROPPERA
# =========================================================================

## Przyjmuje mieszaninę z droppera:
## - chemia nie jest zapisywana,
## - zostaje tylko efekt (opcjonalnie SFX – zakomentowany).
func receive_mixture(_mixture: Mixture, _units: float = 0.0) -> void:
	# _play_sfx_dropper()
	pass


## Zlewka nie jest źródłem cieczy – zawsze zwraca brak cieczy.
func has_any_liquid() -> bool:
	return false


## Zlewka nie udostępnia pobierania objętości – zawsze null.
func take_volume(_units: float):
	return null


## Zlewka nie udostępnia pobierania próbki – zawsze null.
func take_sample(_frac: float) -> Mixture:
	return null


## Zlewka nie udostępnia ułamkowego pobierania – zawsze null.
func take_fraction(_frac: float) -> Mixture:
	return null


# =========================================================================
# GLOBALNE HIGHLIGHTY (Settings)
# =========================================================================

## Sprawdza globalny przełącznik highlightów w autoload Settings (jeśli istnieje).
func _are_global_highlights_enabled() -> bool:
	var settings_node := get_tree().root.get_node_or_null("Settings")
	if settings_node and "highlights_enabled" in settings_node:
		return bool(settings_node.highlights_enabled)
	return true


# =========================================================================
# HOVER / OUTLINE
# =========================================================================

## Reaguje na wejście kursora nad zlewkę – ustawia flagę i odświeża outline.
func _on_mouse_entered() -> void:
	_cursor_inside = true
	_update_outline_interaction()


## Reaguje na wyjście kursora ze zlewki – resetuje outline.
func _on_mouse_exited() -> void:
	_cursor_inside = false
	_set_outline(false)


## Aktualizuje decyzję o podświetleniu zlewki:
## - uwzględnia lokalną flagę, globalne highlighty i realną możliwość interakcji.
func _update_outline_interaction() -> void:
	if not hover_enabled or not _are_global_highlights_enabled():
		_set_outline(false)
		return

	var can_by_probe := _any_probe_with_liquid_over_me()

	var can_by_dropper := false
	var lab := get_tree().get_first_node_in_group("lab_root")
	if lab:
		can_by_dropper = (lab.mode == lab.Mode.TRANSFER) and lab.dropper_loaded

	# Jeśli trzymamy LPM i nie ma realnej interakcji, gasimy outline.
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not (can_by_probe or can_by_dropper):
		_set_outline(false)
		return

	# Hover: kursor lub probówka nad zlewką + realna możliwość użycia.
	var hover_ok := _cursor_inside or can_by_probe
	_set_outline(hover_ok and (can_by_probe or can_by_dropper))


## Sprawdza, czy jakakolwiek probówka z cieczą overlapuje Area2D zlewki.
func _any_probe_with_liquid_over_me() -> bool:
	if area == null or not (area.monitoring and area.monitorable):
		return false

	for overlap in area.get_overlapping_areas():
		var overlap_area := overlap as Area2D
		if overlap_area == null:
			continue

		var probe := overlap_area.get_parent()
		if not (probe and probe.is_in_group("probes")):
			continue

		if probe.has_method("has_any_liquid") and probe.has_any_liquid():
			return true

		if probe.has_method("get"):
			var lvl: Variant = probe.get("fill_level")
			if (lvl is float or lvl is int) and float(lvl) > 0.001:
				return true

	return false


## Ustawia podświetlenie outline'u.
func _set_outline(on: bool) -> void:
	if outline_material == null:
		return
	_set_shader_param_safe(outline_material, "highlight", on)
	var strength: float = hover_outline_strength if on else 0.0
	_set_shader_param_safe(outline_material, "highlight_strength", strength)


## Ustawia parametr shadera tylko, gdy shader faktycznie posiada dany uniform.
func _set_shader_param_safe(mat: ShaderMaterial, param_name: String, value) -> void:
	if mat == null or mat.shader == null:
		return
	for uniform in mat.shader.get_shader_uniform_list():
		var uniform_dict: Dictionary = uniform
		if String(uniform_dict.get("name", "")) == param_name:
			mat.set_shader_parameter(param_name, value)
			return
