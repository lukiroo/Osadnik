extends Control

## =========================================================================
## MainMenu.gd – ekran startowy
## -------------------------------------------------------------------------
## - Pokazuje główne przyciski (Start / Ustawienia / Wyjście).
## - Pozwala wejść w panel ustawień (podświetlenia, etykiety probówek).
## - Synchronizuje stan checkboxów z autoloadem Settings.
## - Opcjonalnie odświeża etykiety probówek „na żywo” w już otwartym Labie.
## =========================================================================

# ───────────────────────── REFERENCJE UI ─────────────────────────
@onready var menu_buttons: VBoxContainer = $ButtonsMargin/ButtonContainer
@onready var settings_panel: Panel = $SettingsPanel

@onready var highlight_checkbox: CheckBox = $SettingsPanel/VBox/HBoxHighlights/CheckBox
@onready var labels_checkbox: CheckBox    = $SettingsPanel/VBox/HBoxTubeLabels/CheckBox


# ───────────────────────── START MENU─────────────────────────────
func _ready() -> void:
	# Ekran startowy: przyciski widoczne, panel ustawień ukryty.
	menu_buttons.visible = true
	settings_panel.visible = false

	# Wczytaj stan przycisków z Settings (autoload).
	highlight_checkbox.button_pressed = Settings.highlights_enabled
	labels_checkbox.button_pressed    = Settings.show_tube_labels

	# Subskrypcja zmian Settings (raz, bez duplikacji).
	if not Settings.changed.is_connected(_on_settings_changed):
		Settings.changed.connect(_on_settings_changed)

	# Podpięcie sygnałów z checkboxów (gdyby nie były spięte w edytorze).
	if not highlight_checkbox.toggled.is_connected(_on_highlight_toggled):
		highlight_checkbox.toggled.connect(_on_highlight_toggled)
	if not labels_checkbox.toggled.is_connected(_on_labels_toggled):
		labels_checkbox.toggled.connect(_on_labels_toggled)


# ───────────────────────── CALLBACKI SETTINGS ───────────────────
## Gdy autoload Settings zmieni stan (np. z innej sceny), odświeżamy UI.
func _on_settings_changed() -> void:
	highlight_checkbox.button_pressed = Settings.highlights_enabled
	labels_checkbox.button_pressed    = Settings.show_tube_labels


# ───────────────────────── HANDLERY CHECKBOXÓW ──────────────────
## Zmiana globalnego przełącznika podświetleń.
func _on_highlight_toggled(is_on: bool) -> void:
	Settings.set_highlight_enabled(is_on)

## Zmiana widoczności numerków probówek.
func _on_labels_toggled(is_on: bool) -> void:
	Settings.set_show_tube_labels(is_on)
	# (opcjonalnie) odśwież etykiety w już otwartym labie.
	_refresh_labels_in_loaded_lab()


# ───────────────────────── HANDLERY PRZYCISKÓW ──────────────────
## Start – przejście do wyboru poziomu.
func _on_start_button_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/menu/level_select.tscn")

## Wejście do panelu ustawień.
func _on_settings_button_pressed() -> void:
	menu_buttons.visible = false
	settings_panel.visible = true

## Powrót z panelu ustawień do głównego menu.
func _on_back_button_pressed() -> void:
	menu_buttons.visible = true
	settings_panel.visible = false

## Wyjście z gry.
func _on_exit_button_pressed() -> void:
	get_tree().quit()


# ───────────────────────── POMOCNICZE ───────────────────────────
## Opcjonalne „na żywo” – prośba do LevelManagera o przestawienie etykiet.
func _refresh_labels_in_loaded_lab() -> void:
	var lab_root: Node = get_tree().get_first_node_in_group("lab_root")
	if lab_root == null:
		return

	var level_manager: Node = lab_root.get_node_or_null("LevelManager")
	if level_manager and level_manager.has_method("relabel_now"):
		level_manager.relabel_now()
