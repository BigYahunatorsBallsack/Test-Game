"""Export the wreck and its loading dock as two matte, vertex-coloured GLBs."""

import json
import math
from pathlib import Path
import sys

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parents[2] / "models" / "fundkorrekturen"))
from build_fundkorrekturen import Mesh, UP, X, Z, block, lathe, polygon_loft, tube, unit, write_glb


OLD_OAK = "#604D43"
OAK = "#896A53"
WORN_OAK = "#A08268"
CRUST = "#D2D1B9"
WET_SALT = "#ACB4A5"
ROPE = "#BA9C75"
IRON = "#58665F"

# Section Z, beam half-width, keel height and height at the gunwale.
SECTIONS = (
    (-14.2, .46, .71, 6.43),
    (-12.3, 2.82, .36, 5.91),
    (-9.4, 4.56, .12, 5.50),
    (-5.8, 5.49, .00, 5.24),
    (-2.0, 5.67, .00, 5.11),
    (2.1, 5.44, .09, 4.91),
    (5.9, 4.85, .26, 4.59),
    (9.3, 4.16, .46, 4.42),
    (12.2, 3.49, .74, 3.72),
)


def squared_timber(mesh, center, size, color, *, pitch=0, roll=0):
    w, h, d = (length/2 for length in size)
    polygon_loft(mesh, ((w,-d),(w,d),(-w,d),(-w,-d)), [(-h,1),(h,1)], color,
                 center=center, pitch=pitch, roll=roll)


def hull_point(index, side, fraction, inset=0):
    z, width, keel, rail = SECTIONS[index]
    breadth = width*(.22+.78*math.sin(fraction*1.52)**.70)
    y = keel+(rail-keel)*fraction
    z -= (1.25 if index==0 else .30 if index==1 else 0)*fraction
    return np.array((side*max(.053, breadth-inset), y, z))


def strake(mesh, index, side, lower, upper, outside, inside=OLD_OAK, *, lip=.20):
    """Make a thick hull panel with sealed edges, following two neighbouring sections."""
    low_a, low_b = lower if isinstance(lower, tuple) else (lower, lower)
    high_a, high_b = upper if isinstance(upper, tuple) else (upper, upper)
    stations = ((index, low_a), (index, high_a), (index+1, high_b), (index+1, low_b))
    outer = [hull_point(i, side, t) for i,t in stations]
    inner = [hull_point(i, side, t, lip) for i,t in stations]
    if side==-1:
        outer.reverse()
        inner.reverse()
    mesh.polygon(tuple(outer), outside)
    mesh.polygon(tuple(reversed(inner)), inside)
    for k in range(4):
        j=(k+1)%4
        mesh.polygon((inner[k], inner[j], outer[j], outer[k]), WORN_OAK)


def wreck(mesh):
    boards = (.00, .18, .35, .50, .64, .77, .89, 1.)
    port_end = (7, 7, 7, 7, 7, 7, 6, 4)
    starboard_end = (7, 7, 7, 7, 6, 5, 3, 2)
    woods = ("#674E43", "#806251", "#92735C", "#795B4D", "#9B775D", "#7F624F", "#786358")
    salt_lower = (.407,.396,.421,.405,.395,.429,.423,.412,.398)
    salt_upper = (.424,.440,.451,.445,.440,.462,.454,.434,.414)
    for side, intact in ((-1,port_end),(1,starboard_end)):
        for i,count in enumerate(intact):
            for plank in range(count):
                tone = woods[(plank+i//3)%len(woods)]
                low, high = boards[plank],boards[plank+1]
                if plank==2 and 0<i<7:
                    bottom = salt_lower[i:i+2]
                    top = salt_upper[i:i+2]
                    strake(mesh,i,side,low,bottom,tone,lip=.22)
                    strake(mesh,i,side,bottom,top,CRUST if i%3==2 else WET_SALT,lip=.22)
                    strake(mesh,i,side,top,high,tone,lip=.22)
                else:
                    strake(mesh,i,side,low,high,tone,lip=.22)
            if count==7:
                rail = [hull_point(i,side,.987-.005*i,-.028) for i in (i,i+1)]
                tube(mesh,rail,.16,"#526A5D",sides=6,normal=UP)

    inner_keel = [hull_point(i,1,.065) for i in range(len(SECTIONS))]
    keel = [np.array((0,p[1],p[2])) for p in inner_keel]
    tube(mesh,keel,.61,OLD_OAK,sides=8,normal=UP)
    bow = [hull_point(0,1,t) for t in (0,.16,.34,.52,.70,.90,1.)]
    stem = [np.array((0,p[1],p[2]-.06)) for p in bow]
    tube(mesh,stem,[.27,.25,.24,.25,.28,.32,.28],WORN_OAK,sides=8,normal=X)
    for i in range(2,len(SECTIONS)):
        for side in (-1,1):
            rail_end = 1.015 if side==-1 else (.95,.93,.87,1.03,.86,.75,.66)[i-2]
            ribs = [hull_point(i,side,t,.28) for t in np.linspace(.075,rail_end,5)]
            ribs[0][0] = 0
            tube(mesh,ribs,[.23,.26,.237,.21,.17],OAK,sides=6,normal=Z)
            if i in (5,6,7,8):
                top=ribs[-1]+np.array((side*.07,.04,-.03))
                tube(mesh,[top,top+np.array((side*.03,.19,.012))],.143,CRUST,sides=5,normal=Z)

    for i,x in enumerate(np.linspace(-2.61,2.61,9)):
        length = 2.67 if i in (2,7) else 4.72
        z = -4.92+(4.72-length)*.45
        squared_timber(mesh,(x,1.59+.047*abs(x),z),(.61,.22,length), OAK if i%2 else WORN_OAK,
                      pitch=.027*(i%3-1),roll=.035*x)
    for z, width, y in ((-9.60,6.45,3.12),(-7.93,8.15,3.23),(1.6,8.26,3.18),(5.47,6.75,2.93)):
        squared_timber(mesh,(0,y,z),(width,.33,.49), OLD_OAK, roll=.032)
    for i,x in enumerate(np.linspace(-2.10,2.40,6)):
        block(mesh,(x,3.39,-8.76),(.69,.17,1.48-(i%3)*.13),
              OAK if i%2 else WORN_OAK,yaw=.044*(i-2))

    # The mast remains trapped in its step. The torn end is irregular and solid.
    block(mesh,(.31,1.76,-4.75),(1.67,.77,1.97),OLD_OAK,rim=OAK)
    mast_start = np.array((.32,1.80,-4.75))
    mast_axis = unit(np.array((.24,1,.26)))
    mast_up = unit(np.cross(mast_axis,Z))
    mast_cross = np.cross(mast_up,mast_axis)
    a = np.linspace(0,math.tau,10,endpoint=False)
    radial = np.cos(a)[:,None]*mast_up+np.sin(a)[:,None]*mast_cross
    jagged = np.array((.15,-.14,.36,.19,-.25,.04,-.18,.23,-.09,.22))
    rows = [mast_start+mast_axis*h+radial*r for h,r in ((0,.45),(2.9,.40),(6.13,.34))]
    rows.append(mast_start+(6.36+jagged[:,None])*mast_axis+radial*.27)
    mesh.loft(rows,[OAK,"#8A6B50","#AF8B66"])
    lathe(mesh,[(.88,.47),(1.08,.46)],IRON,axis=mast_axis,origin=mast_start,sides=10)
    lathe(mesh,[(3.07,.42),(3.25,.41)],ROPE,axis=mast_axis,origin=mast_start,sides=10)
    branch = mast_start+mast_axis*4.8
    stay_end=hull_point(2,-1,.91,.20)
    sag=(branch+stay_end)/2-UP*.47
    tube(mesh,(branch,sag,stay_end),.068,ROPE,sides=6,normal=UP)

    for i,(x,z) in enumerate(((-4.4,9.25),(3.71,10.95),(4.33,7.77),(-4.91,2.85))):
        size = (1.58,.23,2.60-(i%3)*.36)
        block(mesh,(x,.48+.065*(i%2),z),size,WORN_OAK if i%2 else OAK,
              yaw=(.28,-.45,.56,-.31)[i],roll=(i-1)*.075)
        block(mesh,(x+.14,.60+.065*(i%2),z+.29),(.34,.051,.77),CRUST,
              yaw=(.28,-.45,.56,-.31)[i])


def deck_height(z):
    return 1.62-.037*z


def dock(mesh):
    slope = math.atan(.037)
    for z, foot, above in ((-6.82,-.67,2.91),(-.63,-3.40,2.72),(5.46,-4.25,2.32)):
        for side in (-1,1):
            x = side*2.85
            y = (above+foot)*.5
            block(mesh,(x,y,z),(.64,above-foot,.68),OLD_OAK, pitch=.017*side, roll=-.025*side,
                  rim=WORN_OAK)
            block(mesh,(x,above-.27,z),(.76,.19,.76),ROPE,bevel=.045)
            if z>=-.63:
                block(mesh,(x,.23,z),(.69,.24,.72),CRUST,bevel=.035)
    for x, length, z in ((-2.42,16.0,-.55),(2.37,13.71,-1.69)):
        block(mesh,(x,deck_height(z)-.44,z),(.43,.64,length),OLD_OAK,pitch=slope)
    for z in (-6.82,-.63,5.46):
        block(mesh,(0,deck_height(z)-.64,z),(6.25,.36,.51),OAK)
    for i in range(9):
        z = -7.73+i*1.13
        length = (5.71,5.59,5.67,5.53)[i%4] if i<8 else 4.04
        x = .025*math.sin(i*1.7) if i<8 else -.63
        top = deck_height(z)
        block(mesh,(x,top-.14,z),(length,.28,1.10),OAK if i%3 else WORN_OAK,
              bevel=.043, pitch=slope, yaw=.023*(i%3-1))
        if i%2:
            for side in (-1,1):
                block(mesh,(x+side*length*.406,top+.018,z+.29),(.108,.045,.112),IRON,bevel=.014)
    block(mesh,(1.59,deck_height(1.48)-.22,1.56),(2.06,.22,.93),WORN_OAK,yaw=.20,pitch=.12)
    block(mesh,(-1.61,.91,4.14),(2.5,.20,.63),WORN_OAK,yaw=.35,roll=.15,pitch=-.36)
    for x in (-2.45,2.50):
        block(mesh,(x,.75,2.62),(.31,.28,5.70),OAK,pitch=.47,roll=.042*x)

    # A hand-operated windlass and the remains of mooring rope on the usable section.
    base = np.array((-1.37,2.30,-3.85))
    lathe(mesh,[(-.86,.24),(-.75,.41),(-.57,.41),(-.53,.28),
                (.51,.28),(.56,.41),(.72,.41),(.82,.20)],OLD_OAK,
          axis=X,origin=base,sides=12)
    for x in (-.63,.66):
        block(mesh,base+np.array((x,-.33,0)),(.37,.70,.79),OLD_OAK,rim=OAK)
    for i in range(7):
        lathe(mesh,[(-.46+i*.132,.328),(-.366+i*.132,.328)],ROPE,
              axis=X,origin=base,sides=10)
    crank = [base+np.array(offset) for offset in ((.82,0,0),(1.01,0,0),(1.01,.57,.035),(1.19,.57,.035))]
    tube(mesh,crank,.105,IRON,sides=7,normal=Z)
    lathe(mesh,[(0,.124),(.34,.124)],WORN_OAK,axis=X,origin=crank[-1],sides=7)
    rope = [(-2.84,2.61,-6.82),(-2.66,2.42,-4.39),(-2.66,2.31,-2.05),(-2.84,2.41,-.63)]
    tube(mesh,rope,.062,ROPE,sides=5,normal=UP)


def export(name, build, placement):
    mesh = Mesh()
    build(mesh)
    triangles = np.asarray(mesh.triangles)
    cross = np.cross(triangles[:,1]-triangles[:,0],triangles[:,2]-triangles[:,0])
    area = np.linalg.norm(cross,axis=1)
    valid = area > 1e-8
    triangles = triangles[valid]
    normals = cross[valid] / area[valid,None]
    colors = np.asarray(mesh.colors)[valid]
    points = triangles.reshape((-1,3))
    low, high = points.min(axis=0),points.max(axis=0)
    assert 0 < len(triangles) <= 4100, (name,len(triangles))
    file = f"{name}.glb"
    vertex_count = write_glb(HERE/file,name,triangles,normals,colors,
                             {"ZoneId":"salt_lake","Usage":"Scenery"})
    return dict(
        id=name, file=file, triangles=len(triangles), vertices=vertex_count,
        boundsCenter=np.round((low+high)*.5,4).tolist(), sizeStuds=np.round(high-low,4).tolist(),
        **placement,
    )


if __name__ == "__main__":
    assets = [
        export("salt_lake_wreck",wreck,dict(worldXZ=[1286,790],yawDegrees=31,pitchDegrees=5,rollDegrees=-4,embedStuds=1.20)),
        export("salt_lake_dock",dock,dict(worldXZ=[1311,796],yawDegrees=18,waterline=16.2)),
    ]
    (HERE/"manifest.json").write_text(json.dumps(assets,indent=2)+"\n",encoding="utf-8")
    print(json.dumps(assets,indent=2))
