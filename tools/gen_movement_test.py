#!/usr/bin/env python3
"""Generates scenes/tests/movement_test.tscn (course geometry by numbers).

Kept in the repo so the course can be changed and regenerated instead of
hand-editing dozens of sub-resources. Run from the project root.
"""
import math

T = 0.01  # ramp slab thickness

def ramp(name, x, width, z0, height, deg, mat):
    """Slab whose top surface rises from (z0, y=0) toward -Z to `height`."""
    a = math.radians(deg)
    run = height / math.tan(a)
    ext = 0.02  # extra length buried under the floor
    length = math.hypot(run, height) + ext
    # top surface midpoint of the visible+buried part
    top_len_mid = (math.hypot(run, height) - ext) / 2
    dz, dy = -math.cos(a), math.sin(a)
    mz = z0 + dz * top_len_mid
    my = dy * top_len_mid
    n = (0.0, math.cos(a), math.sin(a))  # top normal of Rx(a)
    cy = my - n[1] * T / 2
    cz = mz - n[2] * T / 2
    c, s = math.cos(a), math.sin(a)
    basis = f"1, 0, 0, 0, {c:.6f}, {-s:.6f}, 0, {s:.6f}, {c:.6f}"
    return (name, (width, T, length), (x, cy, cz), mat, basis), z0 - run

boxes = []
def box(name, size, center, mat, basis="1, 0, 0, 0, 1, 0, 0, 0, 1"):
    boxes.append((name, size, center, mat, basis))

# Floor: two coplanar tiles meeting at z = 0 (the seam).
box("FloorNorth", (2, 0.02, 1), (0, -0.01, 0.5), "floor")
box("FloorSouth", (2, 0.02, 1), (0, -0.01, -0.5), "floor2")
# Walls: side wall face at x = 0.58, back wall face at z = -0.9.
box("SideWall", (0.04, 0.1, 1.84), (0.6, 0.05, 0), "wall")
box("BackWall", (2, 0.1, 0.04), (0, 0.05, -0.92), "wall")
# Allowed 25° ramp to a 4 cm platform whose far side is a drop edge.
r, ztop = ramp("RampAllowed25", -0.5, 0.2, 0.8, 0.04, 25, "ramp")
box(*r)
box("Platform", (0.3, 0.04, 0.3), (-0.5, 0.02, ztop - 0.15), "ramp")
# Forbidden 50° ramp to a 5 cm block.
r, ztop2 = ramp("RampForbidden50", -0.8, 0.15, 0.8, 0.05, 50, "steep")
box(*r)
box("SteepBlock", (0.15, 0.05, 0.2), (-0.8, 0.025, ztop2 - 0.1), "steep")
# Cabinet on legs, underside 10 cm.
box("CabinetBody", (0.4, 0.3, 0.3), (-0.5, 0.25, -0.5), "wood")
for nm, (lx, lz) in {"FL": (-0.68, -0.37), "FR": (-0.32, -0.37), "BL": (-0.68, -0.63), "BR": (-0.32, -0.63)}.items():
    box(f"CabinetLeg{nm}", (0.02, 0.1, 0.02), (lx, 0.05, lz), "wood")
# Narrow passage: 5 cm wide, 3 cm high, 30 cm long, along Z at x = 0.3.
box("PassageWallL", (0.02, 0.04, 0.3), (0.265, 0.02, -0.35), "wall")
box("PassageWallR", (0.02, 0.04, 0.3), (0.335, 0.02, -0.35), "wall")
box("PassageLid", (0.09, 0.01, 0.3), (0.3, 0.035, -0.35), "wood")

stripes = [(f"Mark{i:02d}", (0.04 if i % 5 else 0.07, 0.0004, 0.004), (0, 0.0002, 0.8 - 0.1 * i)) for i in range(11)]

def yaw_tf(deg, p):
    a = math.radians(deg); c = round(math.cos(a), 6) + 0.0; s = round(math.sin(a), 6) + 0.0
    return f"Transform3D({c}, 0, {s}, 0, 1, 0, {-s}, 0, {c}, {p[0]}, {p[1]}, {p[2]})"

positions = [
    ("Depart", (0, 0, 0.8), 0),
    ("Mur", (0.555, 0, 0.6), 0),
    ("Coin", (0.45, 0, -0.75), -45),
    ("Pente", (-0.5, 0, 0.9), 0),
    ("PenteRaide", (-0.8, 0, 0.9), 0),
    ("Joint", (0, 0, 0.1), 0),
    ("SousMeuble", (-0.5, 0, -0.15), 0),
    ("Passage", (0.3, 0, -0.05), 0),
    ("Bord", (-0.5, 0.04, 0.6), 0),
]
mats = {
    "floor": "Color(0.74, 0.72, 0.66, 1)", "floor2": "Color(0.68, 0.7, 0.72, 1)",
    "wall": "Color(0.6, 0.62, 0.66, 1)", "wood": "Color(0.55, 0.4, 0.27, 1)",
    "ramp": "Color(0.5, 0.62, 0.5, 1)", "steep": "Color(0.7, 0.45, 0.4, 1)",
    "mark": "Color(0.95, 0.85, 0.2, 1)",
}
ext = [
    ("PackedScene", "res://scenes/player/player.tscn", "1_player"),
    ("PackedScene", "res://scenes/camera/camera_rig.tscn", "2_rig"),
    ("Script", "res://scripts/player/player_input.gd", "3_input"),
    ("Script", "res://scripts/game/pause_controller.gd", "4_pause"),
    ("Script", "res://scripts/ui/movement_debug_panel.gd", "5_panel"),
]
subs = ['[sub_resource type="Environment" id="Environment_env"]\nbackground_mode = 1\nbackground_color = Color(0.1, 0.1, 0.12, 1)\nambient_light_source = 2\nambient_light_color = Color(0.62, 0.62, 0.66, 1)\nambient_light_energy = 1.0\n']
for k, c in mats.items():
    subs.append(f'[sub_resource type="StandardMaterial3D" id="Mat_{k}"]\nalbedo_color = {c}\nroughness = 0.75\n')
for n, s, _, m, _b in boxes:
    sz = f"Vector3({s[0]:.6f}, {s[1]:.6f}, {s[2]:.6f})"
    subs.append(f'[sub_resource type="BoxMesh" id="Mesh_{n}"]\nmaterial = SubResource("Mat_{m}")\nsize = {sz}\n')
    subs.append(f'[sub_resource type="BoxShape3D" id="Shape_{n}"]\nsize = {sz}\n')
for n, s, _ in stripes:
    subs.append(f'[sub_resource type="BoxMesh" id="Mesh_{n}"]\nmaterial = SubResource("Mat_mark")\nsize = Vector3({s[0]}, {s[1]}, {s[2]})\n')

out = [f"[gd_scene load_steps={len(ext) + len(subs) + 1} format=3]\n"]
out += [f'[ext_resource type="{t}" path="{p}" id="{i}"]' for t, p, i in ext]
out.append("")
out += subs
out.append('''[node name="MovementTest" type="Node3D"]

[node name="WorldEnvironment" type="WorldEnvironment" parent="."]
environment = SubResource("Environment_env")

[node name="KeyLight" type="DirectionalLight3D" parent="."]
transform = Transform3D(0.6, 0.524, -0.605, 0, 0.756, 0.655, 0.8, -0.393, 0.453, 0, 2, 0)
shadow_enabled = true
shadow_bias = 0.02
shadow_normal_bias = 0.5
directional_shadow_max_distance = 1.5

[node name="FillLight" type="DirectionalLight3D" parent="."]
transform = Transform3D(-0.6, -0.3, 0.742, 0, 0.927, 0.375, -0.8, 0.225, -0.557, 0, 2, 0)
light_energy = 0.35

[node name="Level" type="Node3D" parent="."]
''')
for n, s, c, m, b in boxes:
    out.append(f'''[node name="{n}" type="StaticBody3D" parent="Level"]
transform = Transform3D({b}, {c[0]:.6f}, {c[1]:.6f}, {c[2]:.6f})

[node name="Mesh" type="MeshInstance3D" parent="Level/{n}"]
mesh = SubResource("Mesh_{n}")

[node name="Collision" type="CollisionShape3D" parent="Level/{n}"]
shape = SubResource("Shape_{n}")
''')
out.append('[node name="Marks" type="Node3D" parent="Level"]\n')
for n, s, c in stripes:
    out.append(f'[node name="{n}" type="MeshInstance3D" parent="Level/Marks"]\ntransform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {c[0]}, {c[1]}, {c[2]:.3f})\nmesh = SubResource("Mesh_{n}")\ncast_shadow = 0\n')
out.append('[node name="TestPositions" type="Node3D" parent="."]\n')
for n, p, y in positions:
    out.append(f'[node name="{n}" type="Marker3D" parent="TestPositions"]\ntransform = {yaw_tf(y, p)}\ngizmo_extents = 0.02\n')
out.append('''[node name="PlayerInput" type="Node" parent="."]
script = ExtResource("3_input")

[node name="PauseController" type="Node" parent="." node_paths=PackedStringArray("player_input")]
script = ExtResource("4_pause")
player_input = NodePath("../PlayerInput")
capture_mouse = true

[node name="Player" parent="." node_paths=PackedStringArray("player_input", "camera_rig") instance=ExtResource("1_player")]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0.8)
player_input = NodePath("../PlayerInput")
camera_rig = NodePath("../CameraRig")

[node name="CameraRig" parent="." node_paths=PackedStringArray("target", "player_input") instance=ExtResource("2_rig")]
target = NodePath("../Player")
player_input = NodePath("../PlayerInput")

[node name="DebugLayer" type="CanvasLayer" parent="."]

[node name="MovementDebugPanel" type="PanelContainer" parent="DebugLayer" node_paths=PackedStringArray("player", "rig", "positions_root")]
offset_left = 12.0
offset_top = 12.0
offset_right = 330.0
offset_bottom = 200.0
script = ExtResource("5_panel")
player = NodePath("../../Player")
rig = NodePath("../../CameraRig")
positions_root = NodePath("../../TestPositions")

[node name="VBox" type="VBoxContainer" parent="DebugLayer/MovementDebugPanel"]

[node name="Readout" type="Label" parent="DebugLayer/MovementDebugPanel/VBox"]

[node name="Buttons" type="GridContainer" parent="DebugLayer/MovementDebugPanel/VBox"]
columns = 3
''')
open("scenes/tests/movement_test.tscn", "w").write("\n".join(out))
print("ramp25 top z", ztop, "ramp50 top z", ztop2)
