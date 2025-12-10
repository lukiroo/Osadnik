extends Camera2D

# Szybkość ruchu kamery (piksele na sekundę)
@export var move_speed: float = 600.0

# Krok zmiany zoomu przy scrollu
@export var zoom_step: float = 0.1

# Minimalny i maksymalny zoom
@export var zoom_min: float = 1
@export var zoom_max: float = 3

# Jak szybko kamera „dochodzi” do docelowego zoomu
@export var zoom_lerp_speed: float = 10

# Docelowy zoom (jedna liczba, bo kamera używa tego samego zoomu w X i Y)
var _target_zoom: float = 1.0


func _ready() -> void:
	# Na starcie ustawia docelowy zoom na aktualny
	_target_zoom = zoom.x


func _process(delta: float) -> void:
	# Obsługuje ruch kamery klawiaturą
	var dir := Vector2.ZERO

	if Input.is_action_pressed("right"):
		dir.x += 1.0
	if Input.is_action_pressed("left"):
		dir.x -= 1.0
	if Input.is_action_pressed("down"):
		dir.y += 1.0
	if Input.is_action_pressed("up"):
		dir.y -= 1.0

	if dir != Vector2.ZERO:
		dir = dir.normalized()
		position += dir * move_speed * delta

	# Płynnie dochodzi do docelowego zoomu
	var current_zoom: float = zoom.x
	current_zoom = lerp(current_zoom, _target_zoom, zoom_lerp_speed * delta)
	zoom = Vector2.ONE * current_zoom


func _input(event: InputEvent) -> void:
	# Obsługuje scroll myszy do zmiany zoomu
	if event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton

		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_target_zoom += zoom_step
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_target_zoom -= zoom_step

		# Pilnuje zakresu zoomu
		_target_zoom = clamp(_target_zoom, zoom_min, zoom_max)
