"""Author and export the Canyon scenery meshes at their in-game scale."""

import json
import math
from pathlib import Path
import sys

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parents[2] / "models" / "fundkorrekturen"))
from build_fundkorrekturen import Mesh, UP, block, lathe, polygon_loft, tube, unit, write_glb


TIMBER = "#996744"
OLD_WOOD = "#704B39"
BARE_EDGE = "#C08C5F"
OCHRE = "#B79563"
DARK_IRON = "#485655"


def fossil_plate(mesh):
    base = np.array((-.92, 2.51, -.18))
    across = np.array((1., 0., 0.))
    back = unit(np.array((0., .83, .55)))
    front = -np.cross(across, back)
    outline = [(-1.51, .24), (-1.24, -.03), (.14, -.04), (.95, .09),
               (1.43, .46), (1.34, 1.23), (.54, 1.69), (-.80, 1.80), (-1.42, 1.26)]

    def pos(x, y, d):
        return base + across*x + back*y + front*d

    rows = []
    for d, scale in ((-.23, .95), (-.12, 1), (.12, 1), (.20, .87)):
        rows.append([pos(x*scale, .85+(y-.85)*scale, d) for x, y in outline])
    mesh.loft(rows, ["#BB996F", "#E1CDAB", "#A28259"])
    face = [pos(x*.83, .85+(y-.85)*.83, .205) for x, y in outline]
    mesh.polygon(tuple(reversed(face)), "#A88561")

    # A raised ammonite impression with chamber ridges inside an irregular plaster jacket.
    spiral = []
    for t in np.linspace(0, math.tau*1.41, 33):
        radius = .045+.074*t
        spiral.append(pos(-.10+radius*math.cos(t), .83+radius*math.sin(t), .233))
    tube(mesh, spiral, np.linspace(.035,.128,len(spiral)), "#E8CC9B", sides=6, normal=front)
    for i in range(12, 32, 2):
        azimuth = i * math.tau*1.41/32
        edge = across*math.cos(azimuth)+back*math.sin(azimuth)
        p = spiral[i]
        tube(mesh, (p-front*.036, p+edge*.108-front*.01), .031, "#B59765", normal=front, sides=5)


def fossil_workbench(mesh):
    for x in (-2.72, 2.72):
        for z in (-.99, .99):
            block(mesh, (x, 1.10, z), (.48, 2.20, .55), OLD_WOOD, rim=TIMBER)
            block(mesh, (x, .11, z), (.73, .22, .72), "#6A5143", bevel=.037)
        block(mesh, (x, .84, 0), (.33, .29, 2.46), TIMBER)
    for z in (-.98, .98):
        block(mesh, (0, 1.80, z), (6.84, .25, .26), OLD_WOOD, rim=TIMBER)
    for i, z in enumerate((-1.02, 0, 1.02)):
        plank_colors = [TIMBER, "#A67750", "#8B5C42"]
        block(mesh, (0, 2.27, z), (7.14-.07*i, .43, .995), plank_colors[i], bevel=.052, rim=BARE_EDGE)
    for x in (-2.90, 2.90):
        for z in (-1.29, 1.29):
            block(mesh, (x, 2.49, z), (.15, .043, .15), DARK_IRON, bevel=.015)
    for x in (-1.90, .14):
        block(mesh, (x, 2.90, .53), (.33, 1.32, .44), OLD_WOOD, pitch=.48)
    fossil_plate(mesh)

    block(mesh, (2.08, 2.54, -.35), (1.92, .16, 1.62), "#426D65", yaw=.08, rim="#6B9390")
    for sign in (-1, 1):
        block(mesh, (2.08+sign*.91, 2.65, -.35), (.14, .26, 1.61), "#3C6058", yaw=.08)
        block(mesh, (2.08, 2.65, -.35+sign*.74), (1.89, .26, .13), "#3C6058", yaw=.08)
    for x, z, angle in ((1.54, -.56, .28), (2.52, -.08, -.34), (2.27, -.66, .52)):
        polygon_loft(mesh, ((.21,-.19),(.30,.03),(.05,.21),(-.27,.14),(-.28,-.15)),
                     [(0,.9),(.11,1),(.29,.64)], [OCHRE,"#DBC39A"],
                     center=(x,2.60,z), yaw=angle)
    block(mesh, (-2.58, 2.52, -.91), (1.01, .10, 1.12), "#528471", rim="#689B86")
    block(mesh, (-2.58, 2.15, -1.53), (1.01, .73, .084), "#44725F", pitch=.075)
    for y in (1.92, 2.07):
        block(mesh, (-2.58, y, -1.58), (.92, .052, .027), "#9AA77B")

    brush_axis = unit(np.array((-.87,.04,-.48)))
    brush = (-1.31, 2.64, -1.09)
    lathe(mesh, [(-.68,.083),(-.56,.106),(.13,.092),(.22,.122)], "#845534",
          sides=8, origin=brush, axis=brush_axis)
    lathe(mesh, [(.18,.116),(.42,.156),(.49,.158)], "#657471",
          sides=8, origin=brush, axis=brush_axis)
    lathe(mesh, [(.48,.154),(.62,.15),(.77,.096)], ["#CAAD76","#B69461"],
          sides=8, origin=brush, axis=brush_axis)
    block(mesh, (.78, 2.57, -1.14), (1.18, .16, .16), "#5B6867", yaw=.19)
    block(mesh, (.25, 2.57, -1.23), (.26, .18, .21), "#8A5739", yaw=.19)


def quartz_seam(mesh):
    # Aligned rock bands share the same vertices so the seam breaks through one continuous face.
    x = np.array((-4.34,-3.22,-1.98,-.53,.81,2.34,3.37,4.24))
    toe = np.array((-.35,-1.24,-1.79,-1.70,-1.44,-1.54,-1.19,-.36))
    crest = np.array((.61,1.96,2.76,3.42,4.10,3.83,3.33,2.73))
    seam = np.array((.18,.71,.83,1.26,1.73,2.03,2.03,2.21))
    thickness = np.array((.11,.22,.38,.26,.43,.28,.37,.11))
    back = np.array((.58,1.10,1.34,1.83,1.84,1.49,1.16,.52))
    lower_band = (seam-.11)*np.array((.56,.64,.59,.63,.61,.54,.57,.60))
    upper_edge = seam+thickness+.13
    cap = upper_edge+(crest-upper_edge)*np.array((.49,.54,.45,.58,.52,.62,.47,.54))
    levels = (np.zeros(len(x)), lower_band, seam-.11, seam, seam+thickness, upper_edge, cap, crest)
    front_rows = [
        np.column_stack((x, y, toe+y*.21+z))
        for y, z in zip(levels,(0.,-.035,-.055,-.05,-.10,.04,.075,.16))
    ]
    rear_floor = np.column_stack((x, np.zeros(len(x)), back))
    rear_crest = np.column_stack((x, crest, back-crest*.19))
    shades = (
        ("#AD7054","#A56A52","#AF755A"),
        ("#965A46","#A6694E","#9F604B"),
        ("#78554D","#845849","#7B534B"),
        ("#D8D6BD","#EDF0D9","#BECEC0"),
        ("#8F6958","#936658","#9B7160"),
        ("#A8755B","#B48362","#BA876A"),
        ("#BB8260","#AB765F","#C48D67"),
    )
    for band,(lo,hi) in enumerate(zip(front_rows,front_rows[1:])):
        for i in range(len(x)-1):
            j=i+1
            mesh.polygon((lo[i],hi[i],hi[j],lo[j]),shades[band][i%3])
    for i in range(len(x)-1):
        j=i+1
        top=front_rows[-1]
        bottom=front_rows[0]
        mesh.polygon((top[i],rear_crest[i],rear_crest[j],top[j]),("#C58F68","#D5A27A")[i%2])
        mesh.polygon((rear_floor[i],rear_floor[j],rear_crest[j],rear_crest[i]),"#9E6750")
        mesh.polygon((bottom[i],bottom[j],rear_floor[j],rear_floor[i]),"#764F43")
    for i in (0,-1):
        edge=[row[i] for row in front_rows]+[rear_crest[i],rear_floor[i]]
        mesh.polygon(tuple(edge[::-1] if i==0 else edge),"#9C6A53")

    for i, (sx, lift, length, radius, yaw) in enumerate((
        (-3.15,.12,.43,.19,.09),(-2.28,.19,.55,.21,-.31),(-1.72,.23,.78,.26,-.17),
        (-.77,.16,.57,.23,.12),(.01,.20,.81,.24,-.11),(.79,.22,.71,.25,.32),
        (1.47,.14,.53,.20,-.26),(2.32,.19,.73,.24,.14),(3.11,.18,.50,.23,.14),
    )):
        y=np.interp(sx,x,seam)+lift
        z=np.interp(sx,x,toe)+y*.21-.060
        direction=unit(np.array((yaw,.63,-.83)))
        palette = (("#A9C6BA","#D7E9D1","#EDF6DE"),("#C5D8C6","#EBF2DA","#FFF6DD"))[i%2]
        lathe(mesh, [(-.14,radius*.85),(0,radius),(length*.63,radius*.78),(length,.018)],
              palette, sides=6, origin=(sx,y,z+.10), axis=direction, phase=.21*i)
    for cx,cz,size,turn in ((-2.32,-1.87,.90,.38),(.89,-1.88,.81,-.29),(3.14,-1.11,.55,.09)):
        outline = np.array(((.48,-.41),(.56,-.02),(.24,.38),(-.40,.33),(-.52,-.20)))*size
        polygon_loft(mesh, outline, [(0, .92),(.12,1),(.26,.64)], ["#95634F","#BA8668"],
                     center=(cx,0,cz), yaw=turn)


def emit(name, shape, center, yaw, sink):
    mesh = Mesh()
    shape(mesh)
    triangles = np.asarray(mesh.triangles)
    colors = np.asarray(mesh.colors)
    raw_normals = np.cross(triangles[:,1]-triangles[:,0],triangles[:,2]-triangles[:,0])
    area = np.linalg.norm(raw_normals,axis=1)
    valid = area > 1e-8
    solids = triangles[valid]
    normals = raw_normals[valid] / area[valid,None]
    vertices = solids.reshape(-1,3)
    lo, hi = vertices.min(axis=0), vertices.max(axis=0)
    pivot = (lo+hi)*.5
    pivot[1] = lo[1]
    dims = np.round(hi-lo,3).tolist()
    count = len(solids)
    assert 0 < count < 3200 and min(dims) > 0
    number_vertices = write_glb(
        HERE/f"{name}.glb",name,solids-pivot,normals,colors[valid],
        {"ZoneId":"canyon","Usage":"Scenery"},
    )
    return {
        "id":name,"file":f"{name}.glb","sizeStuds":dims,"triangles":count,
        "vertices":number_vertices,"worldXZ":center,"yawDegrees":yaw,"embedStuds":sink,
    }


if __name__ == "__main__":
    items = [
        emit("canyon_fossil_workbench",fossil_workbench,[649,733],12,.27),
        emit("canyon_quartz_seam",quartz_seam,[895,767],-19,.40),
    ]
    (HERE/"manifest.json").write_text(json.dumps(items, indent=2)+"\n", encoding="utf-8")
    print(json.dumps(items, indent=2))
