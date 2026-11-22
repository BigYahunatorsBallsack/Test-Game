"""Build the catalog's revised low-poly find meshes as Studio-ready GLB files."""

import json
import math
import struct
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
ASSETS = HERE.parents[1]
UP = np.array((0.0, 1.0, 0.0))
X = np.array((1.0, 0.0, 0.0))
Z = np.array((0.0, 0.0, 1.0))
CLAY = "#a95231"
CLAY_LIGHT = "#cc764b"
GOLD = "#ce9b4a"
SANDSTONE = "#d8ad78"
STONE_LIGHT = "#e7c79b"
TEAL = "#268c8b"


def vec(value):
    return np.asarray(value, dtype=float)


def unit(value):
    return value / np.linalg.norm(value)


def rgb(color):
    return np.array([int(color[i:i+2], 16) for i in (1, 3, 5)]) / 255


def angles(sides, phase=0):
    return np.linspace(phase, phase+2*math.pi, sides, endpoint=False)


class Mesh:
    def __init__(self):
        self.triangles = []
        self.colors = []

    def polygon(self, points, color):
        for i in range(1, len(points)-1):
            self.triangles.append((points[0], points[i], points[i+1]))
            self.colors.append(rgb(color))

    def loft(self, rows, colors, *, caps=True):
        if isinstance(colors, str):
            colors = [colors]*(len(rows)-1)
        assert len(colors)==len(rows)-1
        for a, b, color in zip(rows, rows[1:], colors):
            for i in range(len(a)):
                j = (i+1) % len(a)
                self.polygon((a[i], b[i], b[j], a[j]), color)
        if caps:
            self.polygon(tuple(rows[0]), colors[0])
            self.polygon(tuple(reversed(rows[-1])), colors[-1])

    def data(self):
        triangles = np.asarray(self.triangles, dtype=float)
        colors = np.asarray(self.colors)
        normals = np.cross(triangles[:, 1]-triangles[:, 0], triangles[:, 2]-triangles[:, 0])
        area = np.linalg.norm(normals, axis=1)
        valid = area>1e-8
        triangles, colors = triangles[valid], colors[valid]
        normals = normals[valid]/area[valid, None]
        points = triangles.reshape(-1, 3)
        lo, hi = points.min(axis=0), points.max(axis=0)
        anchor = (lo+hi)/2
        anchor[1] = lo[1]
        triangles = (triangles-anchor)*(2.0/max(hi-lo))
        assert 0 < len(triangles) <= 1600
        return triangles, normals, colors


def oval(mesh, profiles, colors, *, sides=12, origin=(0, 0, 0), axis=UP, phase=0):
    """Loft circular profiles. A profile is height, X radius, and Z radius."""
    lateral = X if abs(np.dot(axis, X))<.95 else UP
    u = unit(lateral-axis*np.dot(lateral, axis))
    v = np.cross(u, axis)
    angular = angles(sides, phase)
    rows = []
    for y, rx, rz in profiles:
        rows.append(vec(origin)+axis*y+np.cos(angular)[:, None]*u*rx+np.sin(angular)[:, None]*v*rz)
    mesh.loft(rows, colors)


def lathe(mesh, profiles, colors, **kwargs):
    oval(mesh, [(y, r, r) for y, r in profiles], colors, **kwargs)


def polygon_loft(mesh, points, levels, colors, *, center=(0, 0, 0), yaw=0, roll=0, pitch=0):
    # X/Z outline in angular order, with the Y coordinates given by levels.
    outline=vec(points)
    following=np.roll(outline,-1,axis=0)
    if np.sum(outline[:,0]*following[:,1]-outline[:,1]*following[:,0])<0:
        outline=outline[::-1]
    c, s = math.cos(yaw), math.sin(yaw)
    m = np.array(((c, 0, -s), (0, 1, 0), (s, 0, c)))
    c, s = math.cos(roll), math.sin(roll)
    m = np.array(((c, -s, 0), (s, c, 0), (0, 0, 1)))@m
    c, s = math.cos(pitch), math.sin(pitch)
    m = np.array(((1, 0, 0), (0, c, -s), (0, s, c)))@m
    rows = [np.array([(x*scale, y, z*scale) for x,z in outline])@m.T+vec(center)
            for y,scale in levels]
    mesh.loft(rows, colors)


def block(mesh, center, size, color, *, bevel=.04, yaw=0, pitch=0, roll=0, rim=None):
    w, h, d = vec(size)/2
    e = min(bevel, w*.44, h*.44, d*.44)
    points = [(w,-d+e),(w,d-e),(w-e,d),(-w+e,d),(-w,d-e),(-w,-d+e),(-w+e,-d),(w-e,-d)]
    polygon_loft(mesh, points, [(-h,.93),(-h+e,1),(h-e,1),(h,.93)],
                 [color,color,rim or color],center=center,yaw=yaw,pitch=pitch,roll=roll)


def slab(mesh, points, height, color, *, center=(0, 0, 0), yaw=0, rim=None):
    edge = min(.045, height*.30)
    polygon_loft(mesh, points, [(0,.90),(edge,1),(height-edge,1),(height,.94)],
                 [color,color,rim or color],center=center,yaw=yaw)


def tube(mesh, points, radii, color, *, sides=7, normal=Z):
    points = vec(points)
    if isinstance(radii, (float,int)):
        radii = [radii]*len(points)
    rows = []
    theta = angles(sides)
    for i, (point, radius) in enumerate(zip(points,radii)):
        d = unit(points[min(i+1,len(points)-1)]-points[max(0,i-1)])
        side = unit(np.cross(normal,d))
        rise = np.cross(side,d)
        rows.append(point+radius*(np.cos(theta)[:,None]*side+np.sin(theta)[:,None]*rise))
    mesh.loft(rows,color)


def ring_arc(center, rx, rz, start, stop, n):
    return [(center[0]+rx*math.cos(t),center[1],center[2]+rz*math.sin(t))
            for t in np.linspace(start,stop,n)]


def gem(mesh, center, size, color, top, *, sides=6, phase=0):
    w,h,d=vec(size)/2
    oval(mesh, [(-h,w*.59,d*.59),(-h*.44,w,d),(h*.55,w*.82,d*.82),(h,w*.43,d*.41)],
         [color,color,top],sides=sides,origin=center,phase=phase)


def snail_shell(mesh):
    axis=unit(np.array((-.38,-.28,-.88)))
    origin=np.array((.25,.64,.50))
    outside=[(0,.047),(.18,.13),(.33,.17),(.53,.235),(.72,.31),(.93,.36),
             (1.14,.42),(1.31,.49),(1.43,.51),(1.52,.49)]
    lathe(mesh,outside+[(1.50,.383),(1.35,.34),(1.17,.17)],
          ["#dd9e68","#a86436","#ce925d","#ad6a3e","#d29a62","#b77543","#d29b6b",
           "#b37444","#edbe8b","#b98157","#6a442f","#513222"],
          sides=15,origin=origin,axis=axis)
    u=unit(np.cross(UP,axis))
    v=np.cross(u,axis)
    cases=np.linspace(.26,1.39,39)
    extent=np.asarray(outside)
    ridge=[]
    for i,y in enumerate(cases):
        phi=.4+i*.39
        radius=np.interp(y,extent[:,0],extent[:,1])
        ridge.append(origin+axis*y+(math.cos(phi)*u+math.sin(phi)*v)*radius)
    tube(mesh,ridge,[.018+.021*i/(len(ridge)-1) for i in range(len(ridge))],"#e5ac78",normal=axis,sides=5)


def sand_dollar(mesh):
    lathe(mesh,[(0,.75),(.055,.89),(.16,.90),(.20,.78),(.19,.65)],
          ["#b18b62","#c39866","#e8c892","#dfc28f"],sides=15,phase=math.pi/15)
    for t in angles(5,.24):
        direction=np.array((math.cos(t),math.sin(t)))
        tangent=np.array((-direction[1],direction[0]))
        petals=[.23*direction,.31*direction+.115*tangent,.48*direction+.091*tangent,
                .58*direction,.48*direction-.091*tangent,.31*direction-.115*tangent]
        polygon_loft(mesh,petals,[(.189,1),(.204,.98)],"#b08862")


def pearl_shell(mesh):
    oval(mesh,[(0,.30,.25),(.09,.57,.47),(.18,.78,.61),(.28,.81,.63),
               (.32,.71,.54),(.23,.57,.42),(.18,.40,.30)],
         ["#473e3f","#5a4a45","#69564d","#95785f","#d0ab7d","#e0be90"],phase=.1,
         origin=(0,0,-.20))
    opening=unit(np.array((0,-.18,-1.0)))
    oval(mesh,[(0,.35,.27),(.085,.60,.45),(.20,.77,.55),(.29,.76,.54),
               (.32,.67,.47),(.23,.56,.37),(.19,.41,.25)],
         ["#4c4241","#5d4e46","#66554b","#977961","#c5a37b","#e4c598"],axis=opening,
         origin=(0,.73,.52),phase=.10)
    lathe(mesh,[(-.23,.083),(-.17,.121),(.17,.121),(.23,.083)],
          "#7d6556",sides=8,axis=X,origin=(0,.248,.383))
    lathe(mesh,[(0,.070),(.069,.166),(.146,.196),(.25,.16),(.313,.07),(.329,.025)],
          ["#cbb69b","#e1ceb0","#ede0c6","#faecd2","#f8f2db"],sides=12,
          origin=(0,.223,-.29))


def painted_shard(mesh):
    slab(mesh,[(.72,-.62),(.86,-.19),(.58,.21),(.62,.57),(-.21,.79),(-.74,.43),(-.87,-.24),(-.66,-.48)],
         .23,"#a65436",rim="#bc643e",yaw=.087)
    for offset in (-.18,.22):
        points=[(-.59,.23,-.09+offset),(-.31,.23,-.09+offset),(-.24,.23,.06+offset),
                (.03,.23,.06+offset),(.095,.23,-.06+offset),(.32,.23,-.06+offset),
                (.42,.23,.06+offset),(.57,.23,.06+offset)]
        tube(mesh,points,.04,"#e1b580",normal=UP,sides=6)


def amphora_handle(mesh):
    angles_=np.linspace(-math.pi*.33,1.11*math.pi,16)
    path=np.array([(.66*math.cos(t),.67+.65*math.sin(t),.05*math.cos(t)) for t in angles_])
    tube(mesh,path,[.19+.050*math.sin(i*math.pi/(len(path)-1)) for i in range(len(path))],
         "#b96445",sides=8)
    for joint in (path[0],path[-1]):
        gem(mesh,joint,(.44,.25,.39),"#ba8d5f","#e7bf8b",sides=7,phase=.2)


def cup(mesh):
    lathe(mesh, [(0,.58),(.08,.63),(.89,.76),(.98,.81),(1.05,.81),(1.09,.74),
                 (1.04,.66),(.17,.50)], [CLAY,CLAY,CLAY_LIGHT,CLAY_LIGHT,CLAY_LIGHT,"#9b4627","#793b28"],
          sides=12,phase=math.pi/12)
    tube(mesh, [(0,.45,-.673),(-.10,.36,-.661),(-.045,.30,-.648),(-.14,.20,-.635),
                (-.125,.125,-.612)], [.019,.015,.018,.010,.004], "#753922",normal=Z)


def copper_coin(mesh):
    lathe(mesh, [(0,.74),(.035,.92),(.15,.92),(.19,.80),(.16,.70)],
          ["#81402a","#9a492f","#ce764c","#ae5739"], sides=16,phase=.09)
    for x,z in [(-.68,-.12),(.53,-.48),(.2,.70)]:
        block(mesh,(x,.185,z),(.18,.025,.12),"#d18a57",yaw=math.atan2(z,x),bevel=.01)


def coin_bundle(mesh):
    for i in range(5):
        y=i*.135
        lathe(mesh, [(0,.67),(.027,.72),(.112,.72),(.127,.65)],
              ["#965f2f","#a97838",GOLD],sides=12,
              origin=(.03*math.sin(i*2.0),y,.03*math.cos(i*1.3)),phase=.10+i*.08)
    path=[(-.56,.71,0),(-.74,.55,0),(-.77,.10,0),(-.58,-.025,0),(.58,-.025,0),
          (.76,.10,0),(.75,.55,0),(.57,.72,0),(-.56,.71,0)]
    tube(mesh,path,.085,"#e3bd7a",sides=8)
    tube(mesh,[(z,y+.025,x) for x,y,z in path],.079,"#efcf91",sides=8,normal=X)
    tube(mesh,[(-.22,.72,.02),(-.11,.82,-.13),(.08,.80,-.13),(.18,.73,.03),(.25,.73,.20)],
         .067,"#e9c185")


def awl(mesh):
    direction=unit(np.array((.79,.17,.40)))
    lathe(mesh,[(-.86,.014),(-.65,.075),(-.15,.13),(.02,.15)],
          ["#a47347","#c49461","#94613b"],sides=8,axis=direction)
    lathe(mesh,[(0,.15),(.09,.20),(.37,.21),(.44,.19),(.67,.235),(.77,.18)],
          ["#694839","#704838","#513727","#c49761","#e2b27a"],sides=8,axis=direction)


def leaf_imprint(mesh):
    slab(mesh,[(.77,-.55),(.88,.33),(.55,.76),(-.20,.85),(-.77,.57),(-.85,-.31),(-.57,-.71),(.25,-.75)],
         .24,"#b67a55",rim="#dd9e6f",yaw=.14)
    tube(mesh,[(-.38,.245,.51),(-.19,.245,.23),(0,.245,-.03),(.17,.245,-.30),(.32,.245,-.55)],
         [.023,.025,.022,.016,.006],"#875237",normal=UP)
    forward=np.array((.57,-.82))
    across=np.array((.82,.57))
    for i in range(4):
        center=np.array((-.23,.29)) + forward*(.23*i)
        span=.36-.05*i
        for hand in (-1,1):
            blade=[
                center, center+.049*forward+hand*.58*span*across,
                center+.19*forward+hand*span*across,
                center+.18*forward+hand*.46*span*across,
            ]
            polygon_loft(mesh,blade,[(.237,.99),(.253,1)],"#965b39")


def pot_base(mesh):
    theta=angles(14,.12)
    crest=np.array([.84,.80,.57,.55,.70,.87,.75,.49,.51,.64,.78,.64,.52,.64])
    def row(radius, height):
        return np.column_stack((radius*np.cos(theta),np.broadcast_to(height,theta.shape),radius*np.sin(theta)))
    mesh.loft([row(.47,0),row(.64,.16),row(.76,.30),row(.78,.36),row(.76,.41),
               row(.71,crest),row(.61,crest-.025),row(.64,.36),row(.47,.12)],
              [CLAY,CLAY_LIGHT,"#ebbe81","#e4ae71",CLAY_LIGHT,"#e09a6b","#8f422b","#773925"])


def needle(mesh):
    # Offset eye in a flat carved bone blank. The body and eye meet at the shoulders.
    outer=[(.36,-.59),(.41,-.28),(.27,-.08),(-.27,-.08),(-.41,-.28),(-.36,-.59),(-.25,-.74),(.25,-.74)]
    inner=[(.15,-.53),(.18,-.34),(.10,-.23),(-.10,-.23),(-.18,-.34),(-.15,-.53),(-.095,-.60),(.095,-.60)]
    for i in range(len(outer)):
        j=(i+1)%len(outer)
        poly=[outer[i],outer[j],inner[j],inner[i]]
        # The eye quadrants have a continuous rectangular hole.
        polygon_loft(mesh,[(x*.72,z) for x,z in poly],[(0,1),(.13,1)],"#d5a875")
    polygon_loft(mesh,[(.195,-.115),(.108,.29),(0,1.06),(-.108,.29),(-.195,-.115)],[(0,.94),(.12,1),(.15,.92)],
                 ["#b78755","#dfbc88"])


def trough(mesh):
    block(mesh,(0,.095,0),(.99,.19,1.9),"#b66244",bevel=.055,rim="#cf8a67")
    for x in (-.40,.40):
        block(mesh,(x,.30,0),(.24,.41,1.9),"#b95d42",bevel=.072,rim="#d99a71")
    block(mesh,(0,.182,.34),(.61,.025,.64),"#af6446",bevel=.009)


def mosaic_tile(mesh):
    slab(mesh,[(.76,-.76),(.85,.64),(.55,.82),(-.67,.76),(-.84,.53),(-.79,-.61),(-.60,-.81)],.19,
         "#a88560",rim="#c6a477")
    slab(mesh,[(.63,-.64),(.72,.55),(.47,.68),(-.59,.63),(-.69,.45),(-.66,-.47),(-.46,-.67)],.09,
         "#247776",center=(0,.158,0),rim="#369d9d")
    for x,z in [(-.61,-.50),(.52,.55)]:
        block(mesh,(x,.229,z),(.19,.056,.18),"#d2a879",bevel=.017,yaw=.24)


def pyrite(mesh):
    block(mesh,(-.38,.34,-.18),(.72,.68,.72),"#aa762e",rim="#d4a046",yaw=-.06,bevel=.028)
    block(mesh,(.38,.34,-.18),(.72,.68,.72),"#bf8c36",rim="#e3b353",yaw=.06,bevel=.028)
    block(mesh,(.02,1.03,.02),(.76,.74,.76),"#c39140",rim="#e8bc65",yaw=.04,bevel=.037)


def wedge(mesh):
    # Sloping side view, extruded across the grain of a split wooden wedge.
    points=[(.37,-.70),(.36,.46),(.14,.87),(-.22,.75),(-.38,.64),(-.38,-.70)]
    bottom=[(x,.02,z) for x,z in points]
    top=[(x,.11+(.84-z)*.24,z) for x,z in points]
    mesh.loft([bottom,top],["#99603d"])
    tube(mesh,[(-.23,.447,-.56),(-.19,.395,-.34),(-.21,.294,.08),(-.14,.219,.39)],
         [.020,.017,.018,.008],"#704636",normal=UP)
    tube(mesh,[(.22,.450,-.57),(.17,.369,-.23),(.17,.303,.06),(.13,.217,.39)],
         [.011,.014,.012,.006],"#bb8153",normal=UP)
    mesh.triangles=[[(-x,y,-z) for x,y,z in face] for face in mesh.triangles]


def rib(mesh):
    path=[(x,y,z) for x,y,z in [(-.72,.01,-.17),(-.62,.24,-.1),(-.51,.43,0),(-.30,.59,.11),
         (-.06,.68,.20),(.23,.70,.27),(.45,.67,.31),(.62,.58,.34),(.75,.47,.37)]]
    tube(mesh,path,[.07,.105,.131,.147,.153,.157,.138,.113,.077],"#d8b280",sides=8)
    gem(mesh,(-.70,.075,-.18),(.21,.18,.22),"#c69d6f","#e3c497",sides=6)


def pigment_bowl(mesh):
    lathe(mesh, [(0,.46),(.08,.55),(.33,.78),(.40,.78),(.43,.70),(.36,.61),(.12,.43)],
          ["#94442c","#ac5033","#ba633c","#d38454","#a75433","#773923"],sides=12)
    gem(mesh,(-.27,.45,.03),(.52,.49,.47),"#9e382c","#cb5339",sides=5,phase=.2)
    gem(mesh,(.18,.39,.19),(.56,.40,.42),"#a53e2e","#cf5f47",sides=5,phase=.6)
    gem(mesh,(.16,.36,-.25),(.46,.28,.39),"#882c23","#bd472f",sides=6)


def climbing_hook(mesh):
    path=ring_arc((0,.14,-.30),.32,.30,-math.pi*.18,math.pi*1.76,13)
    tube(mesh,path,.102,"#554e49",sides=7,normal=UP)
    polygon_loft(mesh,[(.14,-.23),(.11,.38),(-.085,.90),(-.20,.53),(-.18,-.22)],[(0,.92),(.24,1),(.28,.93)],
                 ["#524d47","#756860"])


def gypsum_rose(mesh):
    outline=[(.51,-.10),(.43,.15),(.04,.27),(-.34,.21),(-.43,-.03),(-.15,-.23),(.32,-.25)]
    levels=[(-.079,.85),(-.035,1),(.052,1),(.087,.88)]
    for i,t in enumerate(angles(8,.34)):
        x,z=.40*math.cos(t),.40*math.sin(t)
        polygon_loft(mesh,outline,levels,["#bda384","#cdb89a","#ead7bb"],
                     center=(x,.18+.065*(i%3),z),yaw=t,pitch=-.35+.32*(i%3),roll=(-1)**i*.61)
    for i,t in enumerate(angles(5,.12)):
        inner=[(.73*x,.74*z) for x,z in outline]
        polygon_loft(mesh,inner,levels,["#bfaa8b","#dbc8a8","#efdbc2"],
                     center=(.17*math.cos(t),.52+.05*(i%2),.18*math.sin(t)),yaw=t,pitch=.34,roll=(-1)**i*.83)


def salt_spiral(mesh):
    lathe(mesh,[(0,.66),(.055,.79),(.20,.79),(.25,.72)],
          ["#c3b39b","#d3c6ae","#eee2ca"],sides=13,phase=.24)
    phase=np.linspace(.20, math.pi*2.65, 33)
    path=[(.075*t*math.cos(t),.255,.075*t*math.sin(t)) for t in phase]
    tube(mesh,path,[.037+.032*i/(len(path)-1) for i in range(len(path))],"#bfb096",normal=UP,sides=6)


def planks(mesh):
    for i,x in enumerate((-.52,0,.48)):
        length=(1.73,1.98,1.69)[i]
        outline=[(.26,-length*.45),(.255,length*.38),(.14,length*.48),(-.24,length*.45),
                 (-.26,-length*.38),(-.11,-length*.51)]
        slab(mesh,outline,.20,["#985534","#a96237","#b27243"][i],center=(x,0,.08*(i-1)),yaw=.05*(1-i))
        for z in (-.49,.48):
            lathe(mesh,[(0,.06),(.028,.09),(.057,.066)],["#5f5146","#827061"],
                  sides=8,origin=(x,.19,z+.08*(i-1)))
        tube(mesh,[(x-.10,.20,-.48),(x-.12,.20,-.13),(x-.09,.20,.26),(x-.12,.20,.46)],.013,
             "#774329",normal=UP)


def freight_tag(mesh):
    outer=[(.80,-.65),(.83,.62),(.68,.80),(-.65,.79),(-.81,.63),(-.77,-.64),(-.64,-.76),(.64,-.77)]
    inner=[(.26,-.25),(.26,.25),(.21,.28),(-.22,.28),(-.27,.22),(-.26,-.23),(-.22,-.27),(.20,-.27)]
    # Use shaped quad sectors to preserve the squared hole.
    for j in range(len(outer)):
        k=(j+1)%len(outer)
        polygon_loft(mesh,[outer[j],outer[k],inner[k],inner[j]],[(0,1),(.18,1),(.22,.99)],
                     ["#a85b28","#c8823b"])
    for x,z in [(-.60,-.46),(.56,-.52),(-.54,.51),(.54,.49)]:
        block(mesh,(x,.217,z),(.15,.04,.16),"#db9e52",bevel=.013,yaw=.12)


def mother_of_pearl_box(mesh):
    block(mesh,(0,.29,0),(1.74,.58,1.30),"#8b5439",rim="#a3633d",bevel=.075)
    block(mesh,(0,.54,0),(1.79,.12,1.35),"#5f7f76",rim="#83a49b",bevel=.028)
    block(mesh,(0,.70,0),(1.79,.25,1.34),"#a36640",rim="#c58755",bevel=.065)
    block(mesh,(0,.823,0),(1.41,.07,1.00),"#57918d",rim="#69a39d",bevel=.020)
    slab(mesh,[(.60,0),(.20,.12),(0,.40),(-.20,.12),(-.60,0),(-.20,-.12),(0,-.40),(.20,-.12)],
         .045,"#d4c8a6",center=(0,.848,0),rim="#f2e9cc")
    block(mesh,(0,.53,-.68),(.27,.31,.12),"#c19454",rim="#e7bb75",bevel=.038)


def mirror_plate(mesh):
    lathe(mesh,[(0,.81),(.04,.91),(.14,.92),(.20,.85),(.20,.73),(.16,.69)],
          ["#686e72","#7d8486","#b4bcc0","#dce0e0","#a8bbc7"],sides=8,phase=math.pi/8)
    lathe(mesh,[(.155,.68),(.165,.68)],"#c0dce5",sides=8,phase=math.pi/8)
    slab(mesh,[(.28,-.57),(.49,-.45),(-.28,.57),(-.49,.45)],.038,"#deeef2",center=(0,.133,0),rim="#e4f1f4")


def relief_fragment(mesh):
    slab(mesh,[(.84,-.62),(.85,.41),(.60,.77),(.05,.68),(-.65,.77),(-.85,.37),(-.74,-.52),(-.35,-.65)],
         .30,"#b08259",rim="#dcb181",yaw=-.08)
    outer=[(0,.55),(-.55,0),(0,-.55),(.55,0),(0,.55)]
    inner=[(0,.31),(-.31,0),(0,-.31),(.31,0),(0,.31)]
    for corners, radius in [(outer,.032),(inner,.027)]:
        tube(mesh,[(x,.305,z) for x,z in corners],radius,"#996e4d",normal=UP,sides=6)
    slab(mesh,[(.19,0),(0,.19),(-.19,0),(0,-.19)],.049,"#c39368",center=(0,.267,0),rim="#e0b484")


def incense_lamp(mesh):
    lathe(mesh,[(0,.49),(.08,.57),(.24,.74),(.46,.77),(.54,.70),(.49,.61),(.14,.40)],
          ["#ae7749","#bc8554","#d7a66e","#e5bc83","#b57c50","#8f5f3b"],sides=14)
    lathe(mesh,[(.34,.735),(.42,.751),(.48,.738)],"#bf7954",sides=14)
    theta=angles(14,math.pi/14)
    def row(radius,y):
        return list(zip(radius*np.cos(theta),[y]*len(theta),radius*np.sin(theta)))
    stripe_bottom,stripe_top=row(.758,.347),row(.768,.453)
    for i in range(14):
        j=(i+1)%14
        mid=(vec(stripe_top[i])+vec(stripe_top[j]))/2
        mesh.polygon([stripe_bottom[i],mid,stripe_bottom[j]],"#edc998")
    lathe(mesh,[(.55,.63),(.67,.62),(.84,.37),(.94,.21)],"#865331",sides=14)
    lower,upper,neck=row(.74,.64),row(.49,.94),row(.23,1.04)
    for i in range(14):
        j=(i+1)%14
        if i%2==0:
            mesh.polygon([lower[i],upper[i],upper[j],lower[j]],"#d3a272")
        mesh.polygon([upper[i],neck[i],neck[j],upper[j]],"#e5bd87")
    lathe(mesh,[(.53,.64),(.56,.72),(.65,.74),(.69,.67)],"#c58f5e",sides=14)
    lathe(mesh,[(1.02,.24),(1.10,.17),(1.21,.15),(1.24,.08)],"#c69562",sides=10)


def stone_bolt(mesh):
    oval(mesh,[(-.88,.33,.33),(-.79,.39,.39),(-.57,.37,.37),(-.49,.23,.23),
               (.47,.22,.23),(.55,.36,.37),(.77,.39,.39),(.86,.31,.32)],
         ["#ba925f","#c69c6b","#c69c6b","#d0a77a","#ba935e","#bd9564","#e0b68b"],
         sides=8,axis=X,phase=.34,origin=(0,.39,0))


def finger_segment(mesh):
    axis=unit(np.array((.96,.06,.18)))
    oval(mesh,[(-.87,.16,.19),(-.76,.26,.27),(-.47,.28,.28),(-.40,.22,.225),(-.34,.27,.26),
               (-.08,.31,.30),(.03,.25,.24),(.13,.32,.32),(.52,.34,.31),(.76,.28,.25)],
         ["#d4a678","#d3aa7c","#b18a61","#d4a878","#d5aa7c","#ad8359","#d6ad7e","#dab184","#e0ba8a"],
         sides=8,axis=axis,origin=(0,.31,0),phase=.2)


FIND_SHAPES={
    "duenenmeer_02":snail_shell,"duenenmeer_04":sand_dollar,"duenenmeer_05":pearl_shell,
    "duenenmeer_06":painted_shard,"duenenmeer_07":amphora_handle,
    "duenenmeer_08":cup,"duenenmeer_11":copper_coin,"duenenmeer_13":coin_bundle,"duenenmeer_18":awl,
    "oase_05":leaf_imprint,"oase_06":pot_base,"oase_11":needle,"oase_22":trough,"oase_26":mosaic_tile,
    "canyon_10":pyrite,"canyon_12":wedge,"canyon_17":rib,"canyon_23":pigment_bowl,"canyon_24":climbing_hook,
    "salzsee_04":gypsum_rose,"salzsee_10":salt_spiral,"salzsee_11":planks,"salzsee_21":freight_tag,
    "salzsee_25":mother_of_pearl_box,"salzsee_30":mirror_plate,"ruinenstadt_04":relief_fragment,
    "ruinenstadt_09":incense_lamp,"ruinenstadt_26":stone_bolt,"ruinenstadt_27":finger_segment,
}
PREVIEW_ONLY = {f"duenenmeer_{i:02d}" for i in (2,4,5,6,7)}


def write_glb(path, name, triangles, normals, colors, extras):
    pos=triangles.reshape(-1,3)
    norm=np.repeat(normals,3,axis=0)
    color=np.repeat(colors,3,axis=0)
    linear=np.where(color<=.04045,color/12.92,((color+.055)/1.055)**2.4)
    data=np.concatenate((pos,norm,linear),axis=1).astype("<f4")
    unique, indices=np.unique(data,axis=0,return_inverse=True)
    indices=indices.reshape(-1).astype("<u2")
    payload=bytearray()
    views, accessors=[],[]

    def attribute(values, component, kind, target, bounds=False):
        start=len(payload)
        buf=values.tobytes()
        payload.extend(buf)
        payload.extend(b"\0"*(-len(payload)%4))
        views.append({"buffer":0,"byteOffset":start,"byteLength":len(buf),"target":target})
        result={"bufferView":len(views)-1,"componentType":component,"type":kind,"count":len(values)}
        if bounds:
            result.update(min=values.min(axis=0).tolist(),max=values.max(axis=0).tolist())
        accessors.append(result)
        return len(accessors)-1

    primitive={
        "attributes":{
            "POSITION":attribute(unique[:,:3],5126,"VEC3",34962,True),
            "NORMAL":attribute(unique[:,3:6],5126,"VEC3",34962),
            "COLOR_0":attribute(unique[:,6:9],5126,"VEC3",34962),
        },
        "indices":attribute(indices,5123,"SCALAR",34963),"material":0,
    }
    gltf={
        "asset":{"version":"2.0","generator":"Dune Baron find revisions"},
        "scene":0,"scenes":[{"nodes":[0]}],"nodes":[{"name":name,"mesh":0,"extras":extras}],
        "meshes":[{"name":name,"primitives":[primitive]}],
        "materials":[{"name":"Relic material","pbrMetallicRoughness":{"metallicFactor":0,"roughnessFactor":.78}}],
        "accessors":accessors,"bufferViews":views,"buffers":[{"byteLength":len(payload)}],
    }
    description=json.dumps(gltf,separators=(",",":")).encode()
    description+=b" "*(-len(description)%4)
    with path.open("wb") as out:
        out.write(struct.pack("<4sII",b"glTF",2,28+len(description)+len(payload)))
        out.write(struct.pack("<I4s",len(description),b"JSON"))
        out.write(description)
        out.write(struct.pack("<I4s",len(payload),b"BIN\0"))
        out.write(payload)
    return len(unique)


def main():
    draft=json.loads((ASSETS/"reference/finds_draft.json").read_text(encoding="utf8"))["items"]
    by_id={row["id"]:row for row in draft}
    dest=HERE/"glb"
    dest.mkdir(exist_ok=True)
    manifest=[]
    for find_id, shape in FIND_SHAPES.items():
        source=by_id[find_id]
        mesh=Mesh()
        shape(mesh)
        triangles,normals,colors=mesh.data()
        path=dest/f"{find_id}.glb"
        extras={"FindId":find_id,"ZoneId":source["zone"],"DraftSetId":source["set_id"],"DesignReference":source["icon_path"]}
        vertices=write_glb(path,find_id,triangles,normals,colors,extras)
        manifest.append({
            "id":find_id,"name":source["name_de"],"zone":source["zone"],
            "basis":"collision_preview" if find_id in PREVIEW_ONLY else "visual_mismatch",
            "glb":path.relative_to(HERE).as_posix(),"icon":source["icon_path"],
            "model":f"ServerStorage.DuneBaronAssetLibrary.Finds.{source['zone']}.{find_id}",
            "triangles":len(triangles),"vertices":vertices,"extent":np.ptp(triangles.reshape(-1,3),axis=0).round(3).tolist(),
        })
    (HERE/"manifest.json").write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+"\n",encoding="utf8")
    print(f"{len(manifest)} meshes, {sum(row['triangles'] for row in manifest):,} triangles total")


if __name__=="__main__":
    main()
