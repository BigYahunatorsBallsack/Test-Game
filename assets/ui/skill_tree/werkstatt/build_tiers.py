"""Pack the workshop's progressive sprites. Run from any directory with Pillow."""
import json
import math
import re
from pathlib import Path

from PIL import Image, ImageDraw, ImageOps

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
SOURCE = ROOT / "src/client/Interface/Workshop"
LANCZOS = Image.Resampling.LANCZOS


def cell(sheet, col, row, cols, rows):
    w, h = sheet.size
    return sheet.crop((round(w * col / cols), round(h * row / rows),
                       round(w * (col + 1) / cols), round(h * (row + 1) / rows))).convert("RGBA")


def plate(picture, rank, hallmark=None, seal=False):
    """Higher ranks gain additional teeth, a different outline and a larger illustration."""
    result = Image.new("RGBA", (240, 240))
    draw = ImageDraw.Draw(result)
    faces = ["#9b6844", "#c39860", "#c9cbd0", "#e0ac54", "#d5a04b", "#f7cd70"]
    n = max(1, min(6, rank))
    sides = [8, 10, 8, 10, 12, 12][n - 1]
    def outline(radius):
        return [(120 + radius * math.cos((idx / sides - .25) * math.tau),
                 117 + radius * math.sin((idx / sides - .25) * math.tau)) for idx in range(sides)]
    draw.polygon(outline(114), fill="#493a2c", outline="#f3cc83", width=3)
    draw.polygon(outline(107), fill=faces[n - 1], outline="#382e28", width=3)
    draw.polygon(outline(97), fill="#112c2c", outline="#56432d", width=4)
    side = (140 if seal else 150) + n * 4
    face = ImageOps.pad(picture, (side, side), method=LANCZOS, color="#102622")
    mask = Image.new("L", face.size)
    ImageDraw.Draw(mask).ellipse((0, 0, side-1, side-1), fill=255)
    face.putalpha(Image.composite(face.getchannel("A"), Image.new("L",face.size), mask))
    result.alpha_composite(face, ((240-side)//2, (221-side)//2))
    if hallmark is not None:
        stamp = ImageOps.fit(hallmark, (72, 72), method=LANCZOS)
        mask = Image.new("L", (72, 72))
        ImageDraw.Draw(mask).ellipse((2, 2, 70, 70), fill=255)
        stamp.putalpha(mask)
        result.alpha_composite(stamp, (150, 134))
    # The bars also work when the node is dimmed or the player cannot distinguish its metal colour.
    spread = (n-1)*15
    for i in range(n):
        x = 120-spread/2+i*15
        draw.polygon([(x-7,205),(x,198),(x+7,205),(x,215)], fill="#ffe8a0",outline="#46382b",width=2)
    return result


def put(atlas, tile, columns, index, art):
    atlas.alpha_composite(art.resize((tile,tile),LANCZOS),((index%columns)*tile,(index//columns)*tile))


def main():
    devices=json.loads((SOURCE/"Devices.json").read_text(encoding="utf8"))
    extra=json.loads((SOURCE/"Support.json").read_text(encoding="utf8"))
    passive=Image.open(HERE/"Gravuren_Quelle.png")
    gears=Image.open(HERE/"Ausbaustufen_Quelle.png")
    base=Image.open(HERE/"Werkstatt_Symbole.png")
    core=Image.open(ROOT/"assets/ui/Atlas_Core.png")
    offsets={key:(int(x),int(y)) for key,x,y in re.findall(r'(\w+) = \{page="Core",x=(\d+),y=(\d+)\}',(ROOT/"src/client/Interface/Catalog.luau").read_text())}
    def original(key):
        x,y=offsets[key]
        return core.crop((x,y,x+80,y+80)).convert("RGBA")
    gear=Image.new("RGBA",(1008,1008))
    shared={}
    for rank in range(6):
        for lane in range(4):
            index=rank*4+lane
            face=cell(passive,lane,rank,4,6)
            shared[index]=face
            put(gear,84,12,index,face)
    bindings={}
    for row,dev in enumerate(devices):
        key=dev["abilityId"]
        for lane in range(4):
            for rank in range(6):
                bindings[f"{dev['id']}_p{lane+1}_{rank+1}"]=["gear",rank*4+lane,rank+1]
        stages=[]
        for path in range(2):
            for rank in range(1,4):
                node=key+"_upgrade" if (path,rank)==(0,1) else f"{key}_m{path+1}_{rank}"
                stages.append((node,rank,path,0))
        for side,letter in enumerate("ab"):
            for path in range(2):
                for rank in range(1,3):
                    stages.append((f"{key}_{letter}_m{path+1}_{rank}",rank,2*side+path,side+1))
        for j,rank in enumerate((1,1,2)):
            stages.append((f"{key}_master_{j+1}",rank,2 if j==1 else 3,3))
        for j,ident in enumerate(("bridge1","bridge2","crown")):
            stages.append((dev["id"]+"_"+ident,4+j,j,3))
        for i,(node,rank,lane,ability) in enumerate(stages):
            slot=24+row*20+i
            # Central machine visibly evolves. The inset identifies the specific effect path.
            primary=cell(gears,min(rank,3)-1,row,3,6)
            stamp=shared[(ability+min(rank,2)-1)*4+lane]
            if rank>=4:
                primary=cell(base,ability,row,4,7)
            put(gear,84,12,slot,plate(primary,rank,stamp))
            bindings[node]=["gear",slot,rank]
    support=Image.new("RGBA",(1008,1008))
    families={
        "collect":["icon_node_collect_"+d["core"] for d in devices],
        "tank":["icon_node_storage_bucket","icon_node_storage_backpack","icon_node_storage_barrel","icon_node_storage_tank"],
        "sell":["icon_currency_coin","icon_node_selling_coins","icon_node_selling_scales","icon_node_selling_stall"],
        "luck":["icon_node_luck_magnifier","icon_node_luck_clover","icon_node_luck_compass","icon_node_luck_star"],
        "sandstorm":["icon_currency_wind_crystal","icon_node_luck_compass","icon_crates_event"],
    }
    raw=(ROOT/"src/shared/Data/UpgradeTree.luau").read_text(encoding="utf8")
    all_base=re.findall(r'^    \{\n(.*?)^    \},',raw,re.M|re.S)
    slot=0
    for group,family in families.items():
        base_ids=[re.search(r'id = "(\w+)"',b)[1] for b in all_base if f'branch = "{group}"' in b]
        ids=base_ids+[n["id"] for n in extra.get(group,[])]
        for i,node in enumerate(ids):
            # Existing tool-unlock portraits remain the actual equipment at that milestone.
            if node.startswith("collect_tool_"):
                index=int(node.rsplit("_",1)[1])-1
                symbol=family[index];rank=index+1
            else:
                sequence=i if i<len(base_ids) else i-len(base_ids)
                length=len(base_ids) if i<len(base_ids) else len(ids)-len(base_ids)
                rank=1+round(5*sequence/max(1,length-1))
                symbol=family[round((len(family)-1)*sequence/max(1,length-1))]
            mark=shared[(i%6)*4+(list(families).index(group)+i//6)%4]
            put(support,112,9,slot,plate(original(symbol),rank,mark,True))
            bindings[node]=["support",slot,rank]
            slot+=1
    assert len(bindings)==339 and slot==75
    gear.save(HERE/"Werkstatt_Geraetestufen.png",optimize=True)
    support.save(HERE/"Werkstatt_Ausbaustufen.png",optimize=True)
    lines=[f'  {json.dumps(key)}: {json.dumps(bindings[key])}' for key in sorted(bindings)]
    (SOURCE/"TierArt.json").write_text("{\n"+",\n".join(lines)+"\n}\n",encoding="utf8")


if __name__=="__main__":
    main()
