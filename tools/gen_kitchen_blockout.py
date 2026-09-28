#!/usr/bin/env python3
"""Writes scenes/levels/kitchen_blockout.tscn (static blockout, simple boxes).

Offline authoring helper: it only writes a static scene file. Nothing is
generated at runtime. Run from the project root after changing a number.

Axes (metres): +X east, +Z south, +Y up. The north wall face is z = 0,
the west wall face is x = 0.
"""
import math

boxes = []    # (name, size, centre, material, collide)


def box(name, size, centre, mat, collide=True):
    boxes.append((name, size, centre, mat, collide))


def span(name, x0, x1, y0, y1, z0, z1, mat, collide=True):
    box(name, (x1 - x0, y1 - y0, z1 - z0), ((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), mat, collide)


# --- Floor, walls -----------------------------------------------------------
span("Floor", -0.2, 2.1, -0.02, 0.0, -0.1, 1.5, "floor")
span("NorthWall", -0.2, 2.1, 0.0, 0.5, -0.1, 0.0, "wall")
# West wall with the refuge cavity (x -0.16..0, z 0.84..0.98, 6 cm high).
span("WestWallN", -0.2, 0.0, 0.0, 0.5, 0.0, 0.84, "wall")
span("WestWallS", -0.2, 0.0, 0.0, 0.5, 0.98, 1.5, "wall")
span("RefugeCeiling", -0.2, 0.0, 0.06, 0.5, 0.84, 0.98, "wall")
span("RefugeBack", -0.2, -0.16, 0.0, 0.06, 0.84, 0.98, "wall")
# Baseboard on the west wall, with a 6 cm opening at z 0.88..0.94.
span("BaseboardN", 0.0, 0.01, 0.0, 0.07, 0.0, 0.88, "trim")
span("BaseboardS", 0.0, 0.01, 0.0, 0.07, 0.94, 1.25, "trim")
span("BaseboardLintel", 0.0, 0.01, 0.06, 0.07, 0.88, 0.94, "trim")
span("EastWall", 2.0, 2.1, 0.0, 0.5, 0.66, 1.5, "wall")

# --- Base cabinet run along the north wall (x 0..1.5) -------------------------
span("CabinetBody", 0.0, 1.5, 0.10, 0.88, 0.0, 0.58, "cabinet")
span("Worktop", 0.0, 1.5, 0.88, 0.92, 0.0, 0.61, "worktop")
span("CabinetEndPanel", 1.48, 1.5, 0.0, 0.10, 0.0, 0.58, "cabinet")
# Recessed plinth (toe kick) at z 0.52..0.53 with three gaps:
# west 0.15..0.25, middle 0.70..0.80 (route switch), east 1.35..1.45.
for i, (x0, x1) in enumerate([(0.0, 0.15), (0.25, 0.70), (0.80, 1.35), (1.45, 1.48)]):
    span(f"Plinth{i}", x0, x1, 0.0, 0.10, 0.52, 0.53, "plinth")
for x in (0.03, 0.5, 1.0, 1.46):
    for z in (0.04, 0.48):
        span(f"Leg_{int(x*100)}_{int(z*100)}", x - 0.01, x + 0.01, 0.0, 0.10, z - 0.01, z + 0.01, "leg")
# Water pipe coming out of the wall under the sink section.
span("Pipe", 0.79, 0.81, 0.0, 0.10, 0.02, 0.04, "pipe")

# --- Fridge (east), 10 cm slot between it and the cabinet run ---------------
span("FridgeBase", 1.6, 2.0, 0.0, 0.02, 0.0, 0.66, "fridge")
span("Fridge", 1.6, 2.0, 0.02, 1.2, 0.0, 0.66, "fridge")

# --- Island base (south), recessed plinth: 5 cm covered strip -----------------
span("IslandBody", -0.2, 2.1, 0.10, 0.90, 1.25, 1.5, "cabinet")
span("IslandPlinth", -0.2, 2.1, 0.0, 0.10, 1.30, 1.31, "plinth")

# --- Covers on the open floor ----------------------------------------------
span("ChairSeat", 0.55, 0.95, 0.45, 0.48, 0.84, 1.23, "chair")
for nm, (x, z) in {"FL": (0.57, 0.86), "FR": (0.93, 0.86), "BL": (0.57, 1.21), "BR": (0.93, 1.21)}.items():
    span(f"ChairLeg{nm}", x - 0.0125, x + 0.0125, 0.0, 0.45, z - 0.0125, z + 0.0125, "chair")
span("Bin", 1.06, 1.34, 0.0, 0.40, 0.86, 1.14, "bin")

# --- Inert markers (visual only, no collision) ------------------------------
span("RefugeFloor", -0.16, 0.0, 0.0, 0.0008, 0.84, 0.98, "refuge", False)
span("RefugeExitStrip", 0.012, 0.03, 0.0, 0.0008, 0.88, 0.94, "refuge_strip", False)
span("FoodDecal", 1.51, 1.59, 0.0, 0.0008, 0.62, 0.70, "food_decal", False)
# Biscuit fragment standing on the decal: tall enough (3 cm) to be seen
# from the refuge exit at cockroach height.
span("FoodCrumb", 1.535, 1.57, 0.0, 0.03, 0.655, 0.67, "food", False)
# Landmark above the refuge, visible from the food spot: a wall socket.
span("RefugeSocket", 0.0, 0.012, 0.11, 0.19, 0.87, 0.95, "refuge_strip", False)
span("WaterDecal", 0.77, 0.83, 0.0, 0.0008, 0.06, 0.13, "water", False)

markers = [  # name, position, yaw (deg): yaw 0 faces -Z (north), -90 faces +X
    ("Refuge", (-0.04, 0.0, 0.91), -85),
    ("Nourriture", (1.55, 0.0, 0.75), 90),
    ("Eau", (0.8, 0.0, 0.2), 0),
]
reserved = [  # future resource spots (Marker3D only)
    ("FutureFood", (1.5525, 0.0, 0.6625)),
    ("FutureWater", (0.8, 0.0, 0.095)),
]

mats = {
    "floor": "Color(0.78, 0.76, 0.72, 1)", "wall": "Color(0.72, 0.72, 0.7, 1)",
    "trim": "Color(0.92, 0.91, 0.88, 1)", "cabinet": "Color(0.46, 0.52, 0.58, 1)",
    "worktop": "Color(0.3, 0.3, 0.32, 1)", "plinth": "Color(0.25, 0.28, 0.32, 1)",
    "leg": "Color(0.55, 0.55, 0.58, 1)", "pipe": "Color(0.7, 0.72, 0.75, 1)",
    "fridge": "Color(0.9, 0.92, 0.94, 1)", "chair": "Color(0.55, 0.38, 0.22, 1)",
    "bin": "Color(0.3, 0.45, 0.35, 1)", "refuge": "Color(0.35, 0.18, 0.12, 1)",
    "refuge_strip": "Color(0.85, 0.55, 0.3, 1)", "food_decal": "Color(0.95, 0.85, 0.45, 1)",
    "food": "Color(0.8, 0.6, 0.3, 1)", "water": "Color(0.35, 0.6, 0.95, 1)",
}


def yaw_tf(deg, p):
    a = math.radians(deg)
    c, s = round(math.cos(a), 6) + 0.0, round(math.sin(a), 6) + 0.0
    return f"Transform3D({c}, 0, {s}, 0, 1, 0, {-s}, 0, {c}, {p[0]}, {p[1]}, {p[2]})"


ext = [
    ("PackedScene", "res://scenes/player/player.tscn", "1_player"),
    ("PackedScene", "res://scenes/camera/camera_rig.tscn", "2_rig"),
    ("Script", "res://scripts/player/player_input.gd", "3_input"),
    ("Script", "res://scripts/game/pause_controller.gd", "4_pause"),
    ("Script", "res://scripts/ui/level_debug_panel.gd", "5_panel"),
]
subs = ['[sub_resource type="Environment" id="Environment_env"]\nbackground_mode = 1\nbackground_color = Color(0.08, 0.08, 0.1, 1)\nambient_light_source = 2\nambient_light_color = Color(0.6, 0.62, 0.68, 1)\nambient_light_energy = 0.55\n']
for k, c in mats.items():
    extra = "\nemission_enabled = true\nemission = " + c + "\nemission_energy_multiplier = 0.25" if k in ("food_decal", "water", "refuge_strip") else ""
    subs.append(f'[sub_resource type="StandardMaterial3D" id="Mat_{k}"]\nalbedo_color = {c}\nroughness = 0.8{extra}\n')
for n, s, _, m, collide in boxes:
    sz = f"Vector3({s[0]:.4f}, {s[1]:.4f}, {s[2]:.4f})"
    subs.append(f'[sub_resource type="BoxMesh" id="Mesh_{n}"]\nmaterial = SubResource("Mat_{m}")\nsize = {sz}\n')
    if collide:
        subs.append(f'[sub_resource type="BoxShape3D" id="Shape_{n}"]\nsize = {sz}\n')

out = [f"[gd_scene load_steps={len(ext) + len(subs) + 1} format=3]\n"]
out += [f'[ext_resource type="{t}" path="{p}" id="{i}"]' for t, p, i in ext]
out.append("")
out += subs
out.append('''[node name="KitchenBlockout" type="Node3D"]

[node name="WorldEnvironment" type="WorldEnvironment" parent="."]
environment = SubResource("Environment_env")

[node name="KeyLight" type="DirectionalLight3D" parent="."]
transform = Transform3D(0.894, -0.253, 0.369, 0, 0.825, 0.565, -0.447, -0.506, 0.738, 0.9, 2, 1.0)
light_energy = 1.1
shadow_enabled = true
shadow_bias = 0.02
shadow_normal_bias = 0.5
directional_shadow_max_distance = 3.0

[node name="FillLight" type="DirectionalLight3D" parent="."]
transform = Transform3D(-0.6, -0.3, 0.742, 0, 0.927, 0.375, -0.8, 0.225, -0.557, 0, 2, 0)
light_energy = 0.25

[node name="Level" type="Node3D" parent="."]
''')
for n, s, c, m, collide in boxes:
    tf = f"Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {c[0]:.4f}, {c[1]:.4f}, {c[2]:.4f})"
    if collide:
        out.append(f'''[node name="{n}" type="StaticBody3D" parent="Level"]
transform = {tf}

[node name="Mesh" type="MeshInstance3D" parent="Level/{n}"]
mesh = SubResource("Mesh_{n}")

[node name="Collision" type="CollisionShape3D" parent="Level/{n}"]
shape = SubResource("Shape_{n}")
''')
    else:
        out.append(f'''[node name="{n}" type="MeshInstance3D" parent="Level"]
transform = {tf}
mesh = SubResource("Mesh_{n}")
cast_shadow = 0
''')
out.append('[node name="Spawns" type="Node3D" parent="."]\n')
for n, p, y in markers:
    out.append(f'[node name="{n}" type="Marker3D" parent="Spawns"]\ntransform = {yaw_tf(y, p)}\ngizmo_extents = 0.03\n')
out.append('[node name="ReservedSpots" type="Node3D" parent="."]\n')
for n, p in reserved:
    out.append(f'[node name="{n}" type="Marker3D" parent="ReservedSpots"]\ntransform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {p[0]}, {p[1]}, {p[2]})\ngizmo_extents = 0.03\n')
out.append(f'''[node name="PlayerInput" type="Node" parent="."]
script = ExtResource("3_input")

[node name="PauseController" type="Node" parent="." node_paths=PackedStringArray("player_input")]
script = ExtResource("4_pause")
player_input = NodePath("../PlayerInput")
capture_mouse = true

[node name="Player" parent="." node_paths=PackedStringArray("player_input", "camera_rig") instance=ExtResource("1_player")]
transform = {yaw_tf(0, markers[0][1])}
player_input = NodePath("../PlayerInput")
camera_rig = NodePath("../CameraRig")

[node name="CameraRig" parent="." node_paths=PackedStringArray("target", "player_input") instance=ExtResource("2_rig")]
target = NodePath("../Player")
player_input = NodePath("../PlayerInput")

[node name="DebugLayer" type="CanvasLayer" parent="."]

[node name="LevelDebugPanel" type="PanelContainer" parent="DebugLayer" node_paths=PackedStringArray("player", "rig", "spawns_root", "food_spot")]
offset_left = 12.0
offset_top = 12.0
offset_right = 300.0
offset_bottom = 150.0
script = ExtResource("5_panel")
player = NodePath("../../Player")
rig = NodePath("../../CameraRig")
spawns_root = NodePath("../../Spawns")
food_spot = NodePath("../../ReservedSpots/FutureFood")

[node name="VBox" type="VBoxContainer" parent="DebugLayer/LevelDebugPanel"]

[node name="Readout" type="Label" parent="DebugLayer/LevelDebugPanel/VBox"]

[node name="Buttons" type="HBoxContainer" parent="DebugLayer/LevelDebugPanel/VBox"]
''')
open("scenes/levels/kitchen_blockout.tscn", "w").write("\n".join(out))
print(len(boxes), "boxes")
