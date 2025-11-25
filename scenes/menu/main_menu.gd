extends Control

## =========================================================================
## main_menu.gd – ekran startowy
## -------------------------------------------------------------------------
## Odpowiada za:
## - wyświetlanie głównego menu gry (start, ustawienia, wyjście),
## - zmianę podświetleń i etykiet probówek,
## - synchronizację checkboxów z autoloadem Settings.
## =========================================================================

# Główna kolumna z przyciskami.
@onready var menu_buttons: VBoxContainer = $ButtonsMargin/ButtonContainer
# Panel z ustawieniami.
@onready var settings_panel: Panel = $SettingsPanel

# Checkboxy w panelu ustawień.
@onready var highlight_checkbox: CheckBox = $SettingsPanel/VBox/HBoxHighlights/CheckBox
@onready var labels_checkbox:   CheckBox = $SettingsPanel/VBox/HBoxTubeLabels/CheckBox


## Inicjalizuje ekran menu, ustawia początkową widoczność paneli i stan checkboxów.
func _ready() -> void:
	menu_buttons.visible = true
	settings_panel.visible = false

	# Odczytuje aktualne ustawienia z autoloada Settings.
	highlight_checkbox.button_pressed = Settings.highlights_enabled
	labels_checkbox.button_pressed    = Settings.show_tube_labels

	# Reaguje na zmiany Settings (np. po powrocie z innej sceny).
	if not Settings.changed.is_connected(_on_settings_changed):
		Settings.changed.connect(_on_settings_changed)


# ====================== CALLBACK Z SETTINGS =======================

## Aktualizuje stan checkboxów po zmianie ustawień w autoloadzie Settings.
func _on_settings_changed() -> void:
	highlight_checkbox.button_pressed = Settings.highlights_enabled
	labels_checkbox.button_pressed    = Settings.show_tube_labels


# ====================== CHECKBOXY W OPCJACH ======================

## Zapisuje w Settings, czy podświetlenia probówek są włączone.
func _on_highlight_toggled(is_on: bool) -> void:
	Settings.set_highlight_enabled(is_on)


## Zapisuje w Settings stan etykiet probówek i odświeża etykiety w otwartym labie.
func _on_labels_toggled(is_on: bool) -> void:
	Settings.set_show_tube_labels(is_on)
	_refresh_labels_in_loaded_lab()


## Resetuje progres leveli (gwiazdki, zaliczenia) w autoloadzie Settings.
func _on_reset_progress_pressed() -> void:
	Settings.reset_progress()


# ======================= PRZYCISKI W MENU ========================

## Przełącza scenę na ekran wyboru poziomu kationów.
func _on_cations_button_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/menu/level_select_cations.tscn")


## Przełącza scenę na ekran wyboru poziomu anionów.
func _on_anions_button_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/menu/level_select_anions.tscn")


## Uruchamia laboratorium w trybie sandbox.
func _on_sandbox_button_pressed() -> void:
	var cfg: Dictionary = {
		"mode": "SANDBOX",
		"branch": "SANDBOX",
		"group_id": -1,
		"starter_count": 0,
		"mix_difficulty": 0,
		"sandbox": true,
	}
	Settings.set_next_level_config(cfg)
	get_tree().change_scene_to_file("res://scenes/lab.tscn")


## Pokazuje panel ustawień zamiast głównego menu.
func _on_settings_button_pressed() -> void:
	menu_buttons.visible = false
	settings_panel.visible = true


## Wraca z panelu ustawień do głównego menu.
func _on_back_button_pressed() -> void:
	menu_buttons.visible = true
	settings_panel.visible = false


## Kończy działanie gry.
func _on_exit_button_pressed() -> void:
	get_tree().quit()


# ======================== POMOCNICZE =============================

## Odświeża etykiety probówek w załadowanej scenie labu (jeśli jest aktywna).
func _refresh_labels_in_loaded_lab() -> void:
	var lab_root := get_tree().get_first_node_in_group("lab_root")
	if lab_root == null:
		return

	var level_manager := lab_root.get_node_or_null("LevelManager")
	if level_manager and level_manager.has_method("relabel_now"):
		level_manager.relabel_now()
