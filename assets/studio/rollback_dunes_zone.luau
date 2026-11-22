--!strict
-- Run in Edit mode to restore objects/settings and the saved terrain region.
-- Snapshot covers x/z -256..256 and y -64..96; dune volumes outside remain.
local storage=game:GetService("ServerStorage")
local lighting=game:GetService("Lighting")
local backup=storage:FindFirstChild("DuneBaronWorldBackup")
assert(backup,"No zone backup")
local terrainBefore=backup:FindFirstChild("TerrainBefore")
assert(terrainBefore and terrainBefore:IsA("TerrainRegion"),"Terrain backup missing")
local corner=backup:GetAttribute("TerrainMinCell") :: Vector3
workspace.Terrain:PasteRegion(terrainBefore,Vector3int16.new(corner.X,corner.Y,corner.Z),true)
workspace.Terrain:SetMaterialColor(Enum.Material.Sand,backup:GetAttribute("SandColor") :: Color3)
local world=workspace:FindFirstChild("DuneBaronWorld")
if world then world:Destroy() end
local atmosphere=lighting:FindFirstChild("DuneBaronAtmosphere")
if atmosphere then atmosphere:Destroy() end
for _,key in {"ClockTime","Brightness","Ambient","OutdoorAmbient","ExposureCompensation","GlobalShadows"} do
    (lighting :: any)[key]=backup:GetAttribute(key)
end
local base=workspace:FindFirstChild("Baseplate")
if base and base:IsA("BasePart") then
    base.Transparency=backup:GetAttribute("BaseplateTransparency") :: number
    base.CanCollide=backup:GetAttribute("BaseplateCanCollide") :: boolean
end
for _,name in {"DuneBaron_AssetTests","SpawnLocation"} do
    local item=backup:FindFirstChild(name)
    if item then
        if item:IsA("SpawnLocation") then item.Enabled=backup:GetAttribute("OriginalSpawnEnabled") :: boolean end
        item.Parent=workspace
    end
end
backup.Name="DuneBaronWorldBackup_Restored"
return "Objects/settings and saved terrain region restored; outside dune volumes remain"
