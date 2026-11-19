class_name DuelWorld
extends TrialWorld

## D/01 "FOLD" — a 1v1 duel arena. Every layout box is placed together with its
## 180° twin around the origin, so both players face identical geometry.
## Three routes connect the spawns: an open mid with a jumpable table, a tight
## counter-strafe corridor with a crouch-only duct, and a ramped high walkway
## with a jump gap. The practice range in TrialWorld is left untouched.
##
## Integration contract for the logic side:
##   SPAWNS / SPAWN_YAW below replace main.gd's SPAWN when this map is active.
##   Slot 0 hosts at +Z looking -Z (yaw 0); slot 1 joins at -Z looking +Z (yaw PI).

const MAP_ID := "D01"
const MAP_NAME := "FOLD"
const SPAWNS := [Vector3(0, 0.02, 14.5), Vector3(0, 0.02, -14.5)]
const SPAWN_YAW := [0.0, PI]
## Interior play space: x ±12.7, z ±16.7, wall height 4.5.
const BOUNDS := AABB(Vector3(-13.3, -0.5, -17.3), Vector3(26.6, 5.0, 34.6))


func _ready() -> void:
	_palette()
	_materials["floor"].uv1_scale = Vector3(13.3, 17.3, 1)
	_lighting()
	_perimeter()
	_lanes()
	_mid()
	_corridor()
	_walkway()
	_spawn_zone()
	_skyline()
	_build_batches()


## Add a box and its rotational twin. Boxes centred on the origin are added once.
func _sym(center: Vector3, size: Vector3, finish: String, solid: bool = false) -> void:
	_box(center, size, finish, solid)
	var twin := Vector3(-center.x, center.y, -center.z)
	if twin.distance_squared_to(center) > 0.0001:
		_box(twin, size, finish, solid)


func _sym_sign(caption: String, center: Vector3, pixel: float, tint: Color, rotation_y: float = 0.0) -> void:
	_sign(caption, center, pixel, tint, rotation_y)
	var twin := Vector3(-center.x, center.y, -center.z)
	if twin.distance_squared_to(center) > 0.0001:
		_sign(caption, twin, pixel, tint, rotation_y + PI)


## A walkable ramp rising toward -Z. center_top is the midpoint of the walking
## surface; the slab hangs thickness below it. The twin rises toward +Z.
func _ramp(center_top: Vector3, width: float, run: float, rise: float, finish: String) -> void:
	var angle := atan2(rise, run)
	var length := sqrt(run * run + rise * rise)
	var thickness := 0.3
	var size := Vector3(width, thickness, length)
	var basis := Basis(Vector3.RIGHT, angle)
	var center := center_top - (basis * Vector3.UP) * thickness * 0.5
	var transforms: Array = _boxes[finish]
	transforms.append(Transform3D(basis.scaled(size), center))
	_ramp_body(center, basis, size)
	var twin_center := Vector3(-center.x, center.y, -center.z)
	var twin_basis := Basis(Vector3.RIGHT, -angle)
	transforms.append(Transform3D(twin_basis.scaled(size), twin_center))
	_ramp_body(twin_center, twin_basis, size)


func _ramp_body(center: Vector3, basis: Basis, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.transform = Transform3D(basis, center)
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	body.add_child(collider)
	add_child(body)


func _perimeter() -> void:
	_box(Vector3(0, -0.25, 0), Vector3(26.6, 0.5, 34.6), "floor", true)
	for x in [-13.0, 13.0]:
		_box(Vector3(x, 2.25, 0), Vector3(0.6, 4.5, 34.6), "concrete", true)
		_box(Vector3(x, 4.49, 0), Vector3(0.8, 0.2, 34.8), "charcoal")
		_box(Vector3(x * 0.977, 0.46, 0), Vector3(0.08, 0.92, 34.0), "steel")
	for z in [-17.0, 17.0]:
		_box(Vector3(0, 2.25, z), Vector3(26.6, 4.5, 0.6), "concrete", true)
		_box(Vector3(0, 4.49, z), Vector3(26.8, 0.2, 0.8), "charcoal")
		_box(Vector3(0, 0.46, z * 0.982), Vector3(25.9, 0.92, 0.08), "steel")
	for x in [-12.62, 12.62]:
		for z in range(-15, 16, 6):
			_box(Vector3(x, 2.0, z), Vector3(0.24, 4.0, 0.32), "cream")


## Lane dividers at x ±6 with a 6 m central gap, 1.6 m doorways at |z| 6.2..7.8
## and open ends beyond |z| 10.5. Doorway lintels hang at 2.4 m.
func _lanes() -> void:
	for x in [-6.0, 6.0]:
		_sym(Vector3(x, 1.5, 4.6), Vector3(0.6, 3.0, 3.2), "concrete", true)
		_sym(Vector3(x, 1.5, 9.15), Vector3(0.6, 3.0, 2.7), "concrete", true)
		_sym(Vector3(x, 3.06, 4.6), Vector3(0.72, 0.12, 3.3), "charcoal")
		_sym(Vector3(x, 3.06, 9.15), Vector3(0.72, 0.12, 2.8), "charcoal")
		_sym(Vector3(x, 2.7, 7.0), Vector3(0.66, 0.6, 1.6), "steel", true)
		_sym(Vector3(x * 0.945, 2.7, 7.0), Vector3(0.05, 0.5, 1.5), "yellow")


func _mid() -> void:
	# Central table: 0.70 m, a comfortable standing jump from any side.
	_box(Vector3(0, 0.35, 0), Vector3(4.6, 0.7, 4.6), "steel", true)
	_sym(Vector3(0, 0.66, 2.32), Vector3(4.64, 0.12, 0.06), "yellow")
	_sym(Vector3(2.32, 0.66, 0), Vector3(0.06, 0.12, 4.64), "yellow")
	# Diagonal cover on the table: crouch hides (eye 1.87 < 1.95), stand peeks.
	_sym(Vector3(1.35, 1.325, 1.35), Vector3(1.7, 1.25, 0.6), "teal", true)
	_sym(Vector3(1.35, 1.99, 1.35), Vector3(1.78, 0.08, 0.68), "charcoal")
	# Staggered screen walls break the spawn-to-spawn sightline and bend mid
	# into an S. The east gap (1.5 m) links mid to the high-line ground floor.
	_sym(Vector3(1.9, 1.1, 8.0), Vector3(4.6, 2.2, 0.5), "cream", true)
	_sym(Vector3(1.9, 2.24, 8.0), Vector3(4.7, 0.08, 0.58), "charcoal")
	_sym_sign("MID   /   01", Vector3(1.9, 1.45, 8.28), 0.008, Color("#324e52"))
	# Head-glitch crates: crouch eye 1.17 hides behind 1.2 m, stand peeks.
	_sym(Vector3(3.4, 0.6, 4.6), Vector3(1.2, 1.2, 1.2), "cream", true)
	_sym(Vector3(-3.4, 0.6, 4.6), Vector3(1.2, 1.2, 1.2), "cream", true)
	_sym(Vector3(3.4, 1.24, 4.6), Vector3(1.26, 0.08, 1.26), "charcoal")
	_sym(Vector3(-3.4, 1.24, 4.6), Vector3(1.26, 0.08, 1.26), "charcoal")
	for z in [-3.1, 3.1]:
		_box(Vector3(0, 0.012, z), Vector3(6.4, 0.024, 0.1), "chalk")
	for x in [-3.1, 3.1]:
		_box(Vector3(x, 0.012, 0), Vector3(0.1, 0.024, 6.4), "chalk")


## Tight corridor on each player's left: three staggered baffles for
## counter-strafe peeks, plus a crouch-only duct on the wall side. The doorway
## beside the duct offers a standing route into mid instead.
func _corridor() -> void:
	_sym(Vector3(-11.1, 1.1, 12.0), Vector3(3.2, 2.2, 0.8), "teal", true)
	_sym(Vector3(-7.9, 1.1, 8.5), Vector3(3.2, 2.2, 0.8), "teal", true)
	_sym(Vector3(-11.1, 1.1, 5.0), Vector3(3.2, 2.2, 0.8), "teal", true)
	_sym(Vector3(-11.1, 2.24, 12.0), Vector3(3.3, 0.08, 0.88), "charcoal")
	_sym(Vector3(-7.9, 2.24, 8.5), Vector3(3.3, 0.08, 0.88), "charcoal")
	_sym(Vector3(-11.1, 2.24, 5.0), Vector3(3.3, 0.08, 0.88), "charcoal")
	# Orange corner marks make the peek edges readable at speed.
	_sym(Vector3(-9.48, 1.1, 12.0), Vector3(0.05, 2.2, 0.82), "orange")
	_sym(Vector3(-9.52, 1.1, 8.5), Vector3(0.05, 2.2, 0.82), "orange")
	_sym(Vector3(-9.48, 1.1, 5.0), Vector3(0.05, 2.2, 0.82), "orange")
	# Duct: underside 1.50 m — crouch hull 1.37 m fits, stand hull 1.83 m does not.
	_sym(Vector3(-10.85, 1.9, 6.8), Vector3(3.7, 0.8, 1.2), "steel", true)
	_sym(Vector3(-9.15, 0.75, 6.8), Vector3(0.3, 1.5, 0.3), "steel", true)
	_sym(Vector3(-10.85, 1.505, 6.8), Vector3(2.2, 0.02, 0.26), "lamp")
	_sym(Vector3(-10.85, 2.34, 6.8), Vector3(3.78, 0.08, 1.28), "charcoal")
	_sym_sign("LOW   /   LINE", Vector3(-10.85, 1.9, 7.41), 0.006, Color("#e9e5d0"))
	for z in [14.5, 10.2, 6.8, 3.4, 1.0]:
		_sym(Vector3(-9.5, 0.012, z), Vector3(0.09, 0.024, 0.7), "chalk")


## High walkway on each player's right: a 19.3° ramp to a 1.05 m deck, a 1.8 m
## jump gap, crenellated parapet (crouch hides, stand shoots over) and an open
## drop end overlooking mid. The deck end also carries a 26 m cross-map
## sightline to the enemy spawn — intentional reward for taking the high route.
func _walkway() -> void:
	_ramp(Vector3(11.2, 0.525, 13.9), 2.6, 3.0, 1.05, "steel")
	_sym(Vector3(10.85, 0.975, 9.5), Vector3(3.7, 0.15, 5.8), "steel", true)
	_sym(Vector3(10.85, 0.975, 2.4), Vector3(3.7, 0.15, 4.8), "steel", true)
	_sym(Vector3(9.02, 0.99, 9.5), Vector3(0.05, 0.2, 5.8), "charcoal")
	_sym(Vector3(9.02, 0.99, 2.4), Vector3(0.05, 0.2, 4.8), "charcoal")
	_sym(Vector3(10.85, 1.058, 4.87), Vector3(3.66, 0.016, 0.12), "yellow")
	_sym(Vector3(10.85, 1.058, 6.53), Vector3(3.66, 0.016, 0.12), "yellow")
	_sym(Vector3(10.85, 1.058, 0.08), Vector3(3.66, 0.016, 0.12), "yellow")
	for z in [1.0, 4.2, 7.2, 11.8]:
		_sym(Vector3(9.2, 0.45, z), Vector3(0.24, 0.9, 0.24), "charcoal", true)
	# Parapet tops at 2.35 m: crouch eye on deck 2.24 m hides, stand 2.70 m peeks.
	# Shooting gaps are 1.2 m wide at z 2.0..3.2 and 8.6..9.6.
	_sym(Vector3(9.15, 1.7, 1.15), Vector3(0.3, 1.3, 1.7), "concrete", true)
	_sym(Vector3(9.15, 1.7, 3.85), Vector3(0.3, 1.3, 1.3), "concrete", true)
	_sym(Vector3(9.15, 1.7, 7.8), Vector3(0.3, 1.3, 1.6), "concrete", true)
	_sym(Vector3(9.15, 1.7, 10.6), Vector3(0.3, 1.3, 2.0), "concrete", true)
	_sign("HIGH   /   LINE", Vector3(12.66, 2.6, 9.5), 0.008, Color("#324e52"), -PI * 0.5)
	_sign("HIGH   /   LINE", Vector3(-12.66, 2.6, -9.5), 0.008, Color("#324e52"), PI * 0.5)


func _spawn_zone() -> void:
	_sym(Vector3(3.0, 0.6, 12.2), Vector3(1.4, 1.2, 1.0), "cream", true)
	_sym(Vector3(3.0, 1.24, 12.2), Vector3(1.46, 0.08, 1.06), "charcoal")
	# Team accents: A (host, +Z) orange, B (guest, -Z) mint.
	_box(Vector3(0, 0.012, 16.1), Vector3(8.0, 0.024, 0.3), "orange")
	_box(Vector3(0, 0.012, -16.1), Vector3(8.0, 0.024, 0.3), "mint")
	_box(Vector3(0, 1.0, 16.66), Vector3(8.0, 0.5, 0.06), "orange")
	_box(Vector3(0, 1.0, -16.66), Vector3(8.0, 0.5, 0.06), "mint")
	for z in [14.5, -14.5]:
		_box(Vector3(0, 0.013, z - 0.7), Vector3(1.6, 0.026, 0.08), "chalk")
		_box(Vector3(0, 0.013, z + 0.7), Vector3(1.6, 0.026, 0.08), "chalk")
		_box(Vector3(-0.7, 0.013, z), Vector3(0.08, 0.026, 1.6), "chalk")
		_box(Vector3(0.7, 0.013, z), Vector3(0.08, 0.026, 1.6), "chalk")
	_sign("A   /   SPAWN", Vector3(0, 2.7, 16.64), 0.012, Color("#324e52"), PI)
	_sign("B   /   SPAWN", Vector3(0, 2.7, -16.64), 0.012, Color("#324e52"))
	_sign("D   /   01", Vector3(0, 3.5, 16.64), 0.02, Color("#324e52"), PI)
	_sign("FOLD", Vector3(0, 3.5, -16.64), 0.02, Color("#324e52"))


func _skyline() -> void:
	_sym(Vector3(-20, 5.0, -10), Vector3(8, 10, 14), "deep")
	_sym(Vector3(19, 3.5, 8), Vector3(7, 7, 10), "steel")
	_sym(Vector3(-18, 8.0, 14), Vector3(5, 5, 8), "charcoal")
	_sym(Vector3(22, 6.5, -14), Vector3(9, 13, 12), "deep")