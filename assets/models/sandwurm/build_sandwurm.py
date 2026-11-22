"""Build a skinned, vertex-colored glTF of the Dune Baron sandworm."""

import json
import math
import struct
from pathlib import Path

import numpy as np

LENGTH = 34.0
SIDES = 44
FANGS = 17
SPINE = [0.0, 4.65, 9.8, 15.25, 20.8, 26.05, 30.55, LENGTH]
FRAMES = [
    # Seconds, vertical offset, spine curl, lateral sweep, tooth hinge rotation.
    (0.00, -44.0, 0, 0, 20),
    (0.05, -44.0, 0, 0, 20),
    (0.44, -42.0, 1, 0, 20),
    (0.70, -22.0, 4, -2, 12),
    (1.02, 1.6, 7, -3, -20),
    (1.29, 2.3, 5, 0, -26),
    (1.48, 1.6, -5, 2, -22),
    (1.64, -1.0, -18, 5, 24),
    (1.77, -2.0, -21, 5, 27),
    (2.03, -5.0, -10, 2, 19),
    (2.26, -15.0, -3, -1, 14),
    (2.70, -44.0, 0, 0, 20),
]


def rotate(axis, degrees):
    theta = math.radians(degrees) / 2
    return np.array([*(math.sin(theta) * np.asarray(axis)), math.cos(theta)])


def multiply(a, b):
    return np.array([*(a[3] * b[:3] + b[3] * a[:3] + np.cross(a[:3], b[:3])),
                     a[3] * b[3] - np.dot(a[:3], b[:3])])


def rotation(q):
    x, y, z, w = q
    return np.array([
        [1 - 2*(y*y + z*z), 2*(x*y - z*w), 2*(x*z + y*w)],
        [2*(x*y + z*w), 1 - 2*(x*x + z*z), 2*(y*z - x*w)],
        [2*(x*z - y*w), 2*(y*z + x*w), 1 - 2*(x*x + y*y)],
    ])


X, Y, Z = np.eye(3)
IDENTITY = np.array([0.0, 0.0, 0.0, 1.0])
LIFT = np.array([0.0, -3.3, 0.0])
samples = np.linspace(0, LENGTH, 681)


def pitch(s):
    u = s / LENGTH
    return 11 * np.sin(math.pi * u) - 66 * u ** 1.8


directions = np.radians(pitch((samples[:-1] + samples[1:]) / 2))
step = samples[1] - samples[0]
centers = np.vstack((np.zeros(3), np.cumsum(
    np.column_stack((np.zeros(len(directions)), np.cos(directions), np.sin(directions))) * step,
    axis=0,
))) + LIFT


def center_at(s):
    return np.array([np.interp(s, samples, centers[:, dim]) for dim in range(3)])


nodes = []
globals_ = []
rest_q = []


def joint(name, pos, q, parent=None):
    w = np.eye(4)
    w[:3, :3] = rotation(q)
    w[:3, 3] = pos
    local = w if parent is None else np.linalg.solve(globals_[parent], w)
    if parent is not None:
        nodes[parent].setdefault("children", []).append(len(nodes))
    # Our local rotations are simple relative bind transforms. Use the matrix
    # for the translation and quaternion multiplication for the rotation.
    if parent is not None:
        inverse_parent = rest_q[parent].copy()
        inverse_parent[:3] *= -1
        delta = multiply(inverse_parent, q)
    else:
        delta = q
    nodes.append({"name": name, "translation": local[:3, 3].tolist(), "rotation": delta.tolist()})
    globals_.append(w)
    rest_q.append(q)
    return len(nodes) - 1


root = joint("GroundRoot", np.zeros(3), IDENTITY)
lift = joint("Lift", LIFT, IDENTITY, root)
spine = []
for i, s in enumerate(SPINE):
    spine.append(joint("Head" if i == len(SPINE) - 1 else f"Spine{i + 1}",
                       center_at(s), rotate(X, pitch(s)), spine[-1] if spine else lift))
head = spine[-1]
head_world = globals_[head]

positions, colors, joints, weights, faces = [], [], [], [], []


def vertex(pos, color, indices, influences):
    idx = len(positions)
    positions.append(pos)
    # glTF vertex colors are linear.
    colors.append([((c / 255 + .055) / 1.055) ** 2.4 for c in color])
    joints.append([*indices, *([0] * (4 - len(indices)))])
    weights.append([*influences, *([0.0] * (4 - len(indices)))])
    return idx


def combine(row, next_row):
    for i in range(len(row)):
        j = (i + 1) % len(row)
        faces.append((row[i], next_row[i], row[j]))
        faces.append((row[j], next_row[i], next_row[j]))


def smooth(t):
    return t * t * (3 - 2 * t)


def skin(s):
    # Smooth, overlapping influence around each joint avoids hard corners.
    upper = min(int(np.searchsorted(SPINE, s, side="right")), len(SPINE) - 1)
    lower = max(0, upper - 1)
    blend = smooth(float(np.clip((s - SPINE[lower]) / (SPINE[upper] - SPINE[lower]), 0, 1)))
    return (spine[lower], spine[upper]), (1 - blend, blend)


body_low = np.array([144, 78, 44])
body_high = np.array([193, 113, 60])
rim_color = np.array([204, 111, 53])
bark = np.array([113, 58, 38])
deep = np.array([32, 18, 16])
rows = []
for s in np.linspace(0, LENGTH, 137):
    center = center_at(s)
    basis = rotation(rotate(X, pitch(s)))
    near_head = smooth(float(np.clip((s - 30) / 4, 0, 1)))
    row = []
    for j in range(SIDES):
        a = math.tau * j / SIDES
        wave = math.tau * (s / 4.55 + 0.035 * math.sin(a * 2 + s * 0.29) + 0.043 * math.cos(a))
        groove = (0.5 + 0.5 * math.cos(wave)) ** 5
        asymmetry = (0.085 * math.sin(a * 3 + s * 0.25) + 0.05 * math.cos(a * 5 - s * 0.57)) * (1 - near_head)
        tube = 7.82 - 1.22 * (s / LENGTH) - 0.31 * groove + asymmetry
        radius = (1 - near_head) * tube + near_head * 7.26
        color = body_low + (body_high - body_low) * (0.46 + 0.27 * math.cos(a - 1.4) - 0.33 * groove)
        marks = 3.8 * math.sin(13 * a + 4.2 * s) * math.sin(7 * a - s * 3.1)
        color = (color + marks) * (1 - near_head) + (rim_color * 0.88 + marks) * near_head
        coord = center + basis @ np.array([radius * math.cos(a), 0, radius * math.sin(a) * .965])
        ids, influence = skin(s)
        row.append(vertex(coord, color, ids, influence))
    if rows:
        combine(rows[-1], row)
    rows.append(row)
tail = vertex(center_at(0), body_low, [spine[0]], [1.0])
for j in range(SIDES):
    faces.append((tail, rows[0][j], rows[0][(j+1) % SIDES]))

# One continuous surface, from the neck over the rounded lip and into the throat.
# Sample a curved meridian instead of stacking separately modeled rings.
profile = np.array([
    [0.0, 7.26], [0.72, 7.57], [1.55, 8.14], [2.45, 8.67],
    [3.35, 8.73], [4.20, 8.37], [4.69, 7.69], [4.73, 7.09],
    [4.46, 6.49], [3.88, 6.17], [3.02, 6.06], [1.62, 5.89],
    [-0.2, 5.42], [-1.91, 4.62], [-3.20, 3.38], [-4.10, 1.83], [-4.43, 0.42],
])
for k in range(len(profile) - 1):
    p0, p1 = profile[max(0, k - 1)], profile[k]
    p2, p3 = profile[k + 1], profile[min(k + 2, len(profile) - 1)]
    for t in (1/3, 2/3, 1):
        offset, r = 0.5 * ((2*p1) + (-p0+p2)*t + (2*p0-5*p1+4*p2-p3)*t*t + (-p0+3*p1-3*p2+p3)*t**3)
        progress = (k + t) / (len(profile) - 1)
        color = ((1 - smooth(progress / .49)) * (rim_color * .88) + smooth(progress / .49) * rim_color
                 if progress <= .49 else np.array([np.interp(progress, [.49, .62, .76, 1], [a, b, c, d])
                                                  for a, b, c, d in zip(rim_color, bark, deep, deep)]))
        row = []
        for j in range(SIDES):
            a = math.tau * j / SIDES
            n = math.sin(math.pi * progress)
            axial = offset + n * (0.18 * math.sin(2 * a) + 0.09 * math.cos(5 * a)) * min(1, r / 2)
            radius = r + n * (0.065 * math.sin(3 * a) + 0.035 * math.cos(9 * a))
            xyz = head_world @ [radius * math.cos(a), axial, radius * math.sin(a) * .965, 1]
            row.append(vertex(xyz[:3], color + 2.6 * n * math.sin(a * 11 + progress * 39), [head], [1]))
        combine(rows[-1], row)
        rows.append(row)
throat = vertex((head_world @ [0, -4.46, 0, 1])[:3], deep, [head], [1])
for j in range(SIDES):
    faces.append((rows[-1][j], throat, rows[-1][(j + 1) % SIDES]))

fangs = []
for i in range(FANGS):
    a = math.tau * i / FANGS + .045 * math.sin(i * 1.9)
    pos = (head_world @ [6.47 * math.cos(a), 3.69 + .18 * math.sin(2 * a), 6.20 * math.sin(a), 1])[:3]
    q = multiply(rest_q[head], rotate(Y, -math.degrees(a)))
    fang = joint(f"Fang{i + 1}", pos, q, head)
    fangs.append(fang)
    length = 2.17 + .68 * math.sin(i * 1.86) ** 2
    width = .5 + .14 * math.cos(i * 1.2) ** 2
    basis = globals_[fang]
    previous = None
    for u in (0, .17, .46, .73, .94):
        color = np.array([163, 104, 62]) * (1 - smooth(min(1, u * 3))) + np.array([239, 211, 160]) * smooth(min(1, u * 3))
        row = []
        for j in range(7):
            t = math.tau * j / 7
            local = [-length * u, .32 * math.sin(math.pi * u) - .39 * u*u + width * (1 - u) * math.cos(t),
                     .21 * u*u + width * (1 - u) * math.sin(t), 1]
            row.append(vertex((basis @ local)[:3], color, [fang], [1]))
        if previous:
            combine(previous, row)
        else:
            base = vertex(pos, color, [fang], [1])
            for j in range(7):
                faces.append((base, row[j], row[(j+1) % 7]))
        previous = row
    tip = vertex((basis @ [-length, -.39, .21, 1])[:3], [243, 217, 172], [fang], [1])
    for j in range(7):
        faces.append((previous[j], tip, previous[(j+1) % 7]))

xyz = np.asarray(positions)
tri = np.asarray(faces)
assert len(tri) <= 20_000 and len(xyz) < 65_536
cross = np.cross(xyz[tri[:, 1]] - xyz[tri[:, 0]], xyz[tri[:, 2]] - xyz[tri[:, 0]])
normals = np.zeros(xyz.shape)
for corner in range(3):
    np.add.at(normals, tri[:, corner], cross)
normals /= np.maximum(np.linalg.norm(normals, axis=1, keepdims=True), 1e-10)

payload = bytearray()
views, accessors = [], []


def accessor(data, dtype, component, kind, *, bounds=False, target=None):
    arr = np.asarray(data, dtype=dtype)
    offset = len(payload)
    payload.extend(arr.tobytes())
    views.append({"buffer": 0, "byteOffset": offset, "byteLength": len(payload) - offset})
    if target:
        views[-1]["target"] = target
    payload.extend(bytes(-len(payload) % 4))
    result = {"bufferView": len(views) - 1, "componentType": component, "count": len(arr), "type": kind}
    if bounds:
        result.update(min=np.atleast_1d(arr.min(axis=0)).tolist(), max=np.atleast_1d(arr.max(axis=0)).tolist())
    accessors.append(result)
    return len(accessors) - 1


mesh = {"name": "Carapace", "primitives": [{
    "attributes": {
        "POSITION": accessor(xyz, "<f4", 5126, "VEC3", bounds=True, target=34962),
        "NORMAL": accessor(normals, "<f4", 5126, "VEC3", target=34962),
        "COLOR_0": accessor(colors, "<f4", 5126, "VEC3", target=34962),
        "JOINTS_0": accessor(joints, "<u2", 5123, "VEC4", target=34962),
        "WEIGHTS_0": accessor(weights, "<f4", 5126, "VEC4", target=34962),
    },
    "indices": accessor(tri.flatten(), "<u2", 5123, "SCALAR", target=34963),
    "material": 0,
}]}
bind = accessor([np.linalg.inv(m).T.flatten() for m in globals_], "<f4", 5126, "MAT4")
skin_data = {"name": "SandwurmRig", "joints": list(range(len(nodes))), "skeleton": root, "inverseBindMatrices": bind}
nodes.append({"name": "SandwurmSkin", "mesh": 0, "skin": 0})

anim = {"name": "BreachSnapBurrow", "samplers": [], "channels": []}
times = accessor([f[0] for f in FRAMES], "<f4", 5126, "SCALAR", bounds=True)


def channel(node, path, data, kind):
    anim["channels"].append({"target": {"node": node, "path": path}, "sampler": len(anim["samplers"])})
    anim["samplers"].append({"input": times, "interpolation": "LINEAR", "output": accessor(data, "<f4", 5126, kind)})


channel(lift, "translation", [LIFT + [0, f[1], 0] for f in FRAMES], "VEC3")
for i, node in enumerate(spine):
    baseline = np.asarray(nodes[node]["rotation"])
    impact = .22 + i * .065
    channel(node, "rotation", [multiply(baseline, multiply(rotate(X, f[2] * impact), rotate(Z, f[3] * impact)))
                               for f in FRAMES], "VEC4")
for i, node in enumerate(fangs):
    baseline = np.asarray(nodes[node]["rotation"])
    channel(node, "rotation", [multiply(baseline, rotate(Z, f[4] * (.94 + .085 * math.sin(i) ** 2)))
                               for f in FRAMES], "VEC4")

asset = {
    "asset": {"version": "2.0", "generator": "Dune Baron sandworm asset builder"},
    "scene": 0, "scenes": [{"nodes": [root, len(nodes) - 1]}], "nodes": nodes,
    "meshes": [mesh], "skins": [skin_data], "animations": [anim],
    "materials": [{"name": "Sandwurm matte chitin", "pbrMetallicRoughness": {"metallicFactor": 0, "roughnessFactor": .84}}],
    "buffers": [{"byteLength": len(payload)}], "bufferViews": views, "accessors": accessors,
}
description = json.dumps(asset, separators=(",", ":")).encode()
description += b" " * (-len(description) % 4)
destination = Path(__file__).with_name("DuneBaron_Sandwurm.glb")
with destination.open("wb") as f:
    f.write(struct.pack("<4sII", b"glTF", 2, 28 + len(description) + len(payload)))
    f.write(struct.pack("<I4s", len(description), b"JSON"))
    f.write(description)
    f.write(struct.pack("<I4s", len(payload), b"BIN\0"))
    f.write(payload)
print(f"{destination.name}: {len(xyz):,} vertices, {len(tri):,} triangles, {len(globals_)} joints")
