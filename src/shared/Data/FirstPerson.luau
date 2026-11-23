--!strict
-- Ego-Perspektive: Zahlen für Kamera, Hände mit Werkzeug und Eimer vor der Kamera (Viewmodel),
-- freie Maus und die Sicht auf große Maschinen.
-- Die Rechnung steht in Logic/FirstPerson (Lune-Tests in tests/firstperson.spec.luau), der
-- Controller Controllers/FirstPerson setzt sie nur um. Alles nur auf dem Client, der Server
-- rechnet unabhängig davon.
--
-- Viewmodel: zwei Gruppen, die an der Kamera hängen. Rechts die Hand mit dem Werkzeug, links die
-- Hand mit dem Eimer (zeigt den Tank: der Sand darin steigt mit dem Füllstand).
-- Koordinaten im Raum der Kamera: x nach rechts, y nach oben, z nach hinten (vorn ist negativ).
-- Längen in Studs, Winkel in Grad (Drehung wie CFrame.Angles), Zeiten in Sekunden.
-- Ein Teil wie in Data/ToolLooks: shape ("Block", "Cylinder", "Ball"; die Zylinderachse ist x),
-- size, offset (relativ zum Anker der Gruppe), rotation, colorHex, material. `paint = "skin"` nimmt
-- die Hautfarbe des Avatars, `paint = "sleeve"` die Ärmelfarbe aus `sleeveHex`.
-- Alle Zahlen sind Startwerte für den Studio-Test.

export type Vec = { x: number, y: number, z: number }

export type Part = {
    name: string?,
    shape: string,
    size: Vec,
    offset: Vec,
    rotation: Vec?,
    colorHex: string,
    material: string,
    paint: string?,
}

export type Item = { parts: { Part } }

export type DigStyle = {
    move: Vec, -- Ausschlag der rechten Gruppe beim Graben (Studs)
    turn: Vec, -- Drehung der rechten Gruppe beim Graben (Grad)
    period: number,
    leftFactor: number, -- so stark wippt der Eimer mit (0 = gar nicht)
    shake: number, -- Zittern in Studs (Fernsteuerung der Maschinen)
    shakeHz: number,
}

export type ToolView = {
    item: string, -- Eintrag in `viewmodel.items` für die rechte Hand
    dig: string, -- Eintrag in `digStyles`
    hideWorldTool: boolean, -- das Werkzeug-Modell vor dem eigenen Charakter ausblenden (die Hand hält es schon)
}

local SKIN = "#E0B48C"
local SLEEVE = "#C9A66B"
local WOOD = "#8B5A2B"
local METAL = "#4A5C8C"
local BUCKET = "#3D5A9E"
local SAND = "#E6C875"

return {
    enabled = true,

    camera = {
        fieldOfView = 75, -- Roblox-Standard ist 70
        offset = { x = 0, y = 0, z = 0 }, -- Humanoid.CameraOffset
    },

    -- Freie Maus am PC: Die Taste schaltet den Mauszeiger an und aus. Offene Fenster, der Baum
    -- und die Karten aus `cursorGuis` geben die Maus automatisch frei.
    cursor = {
        toggleKeys = { "LeftAlt", "RightAlt" }, -- Namen aus Enum.KeyCode
        hintSeconds = 10, -- so lange steht der Hinweis nach dem Spawn unter dem Fadenkreuz
        hintText = "Alt: Maus frei",
        -- ScreenGuis mit Karten, die einen Klick verlangen: sichtbare Knöpfe darin geben die Maus frei.
        -- Nicht dabei: Fund-Karten (DuneBaronReveal), sie blockieren nie und kommen beim Graben ständig.
        cursorGuis = { "DuneBaronOfflineCard", "DuneBaronCrateReveal" },
        checkSeconds = 0.2,
    },

    crosshair = {
        size = 6, -- Pixel
        transparency = 0.25,
    },

    viewmodel = {
        -- Anker der beiden Gruppen im Raum der Kamera.
        right = { offset = { x = 1, y = -1, z = -1.5 }, rotation = { x = 0, y = 0, z = 0 } },
        left = { offset = { x = -1, y = -1.05, z = -1.6 }, rotation = { x = 0, y = 12, z = 0 } },
        sleeveHex = SLEEVE, -- Ärmel (Arbeitsjacke)
        -- Arme: gehören fest zur Gruppe, das Werkzeug kommt dazu.
        rightArm = {
            { name = "Hand", shape = "Block", size = { x = 0.32, y = 0.36, z = 0.42 }, offset = { x = 0, y = 0, z = 0 }, colorHex = SKIN, material = "SmoothPlastic", paint = "skin" },
            { name = "Forearm", shape = "Block", size = { x = 0.4, y = 0.4, z = 1.6 }, offset = { x = 0.2, y = -0.3, z = 0.85 }, rotation = { x = 18, y = -8, z = 0 }, colorHex = SLEEVE, material = "Fabric", paint = "sleeve" },
        },
        leftArm = {
            { name = "Hand", shape = "Block", size = { x = 0.32, y = 0.36, z = 0.42 }, offset = { x = 0, y = 0.62, z = 0 }, colorHex = SKIN, material = "SmoothPlastic", paint = "skin" },
            { name = "Forearm", shape = "Block", size = { x = 0.4, y = 0.4, z = 1.6 }, offset = { x = -0.15, y = 0.3, z = 0.8 }, rotation = { x = 25, y = 10, z = 0 }, colorHex = SLEEVE, material = "Fabric", paint = "sleeve" },
        },
        -- Eimer in der linken Hand. Der Sand (`fill`) steigt mit dem Tank-Füllstand.
        bucket = {
            { name = "Body", shape = "Cylinder", size = { x = 0.9, y = 1, z = 1 }, offset = { x = 0, y = 0, z = 0 }, rotation = { x = 0, y = 0, z = 90 }, colorHex = BUCKET, material = "SmoothPlastic" },
            { name = "Rim", shape = "Cylinder", size = { x = 0.08, y = 1.08, z = 1.08 }, offset = { x = 0, y = 0.45, z = 0 }, rotation = { x = 0, y = 0, z = 90 }, colorHex = BUCKET, material = "SmoothPlastic" },
            { name = "HandleBar", shape = "Block", size = { x = 1.04, y = 0.06, z = 0.06 }, offset = { x = 0, y = 0.62, z = 0 }, colorHex = METAL, material = "Metal" },
            { name = "HandleLeft", shape = "Block", size = { x = 0.06, y = 0.22, z = 0.06 }, offset = { x = -0.52, y = 0.52, z = 0 }, colorHex = METAL, material = "Metal" },
            { name = "HandleRight", shape = "Block", size = { x = 0.06, y = 0.22, z = 0.06 }, offset = { x = 0.52, y = 0.52, z = 0 }, colorHex = METAL, material = "Metal" },
        },
        fill = {
            colorHex = SAND,
            material = "Sand",
            diameter = 0.88,
            bottomY = -0.42, -- Boden im Eimer (relativ zum Anker)
            minHeight = 0.02, -- leer: dünne Schicht, damit man den Boden sieht
            maxHeight = 0.84, -- voll: bis knapp unter den Rand
        },
        items = {
            none = { parts = {} },
            -- Schaufel: Stiel schräg von der Hand nach vorn zur Bildmitte, Blatt vorn nach unten geneigt.
            shovel = {
                parts = {
                    { name = "Shaft", shape = "Block", size = { x = 0.14, y = 0.14, z = 2.4 }, offset = { x = -0.17, y = 0, z = -0.98 }, rotation = { x = 0, y = 10, z = 0 }, colorHex = WOOD, material = "Wood" },
                    { name = "Grip", shape = "Block", size = { x = 0.18, y = 0.18, z = 0.4 }, offset = { x = 0.05, y = 0, z = 0.3 }, rotation = { x = 0, y = 10, z = 0 }, colorHex = METAL, material = "Metal" },
                    { name = "Neck", shape = "Block", size = { x = 0.22, y = 0.12, z = 0.35 }, offset = { x = -0.4, y = -0.03, z = -2.29 }, rotation = { x = -20, y = 10, z = 0 }, colorHex = METAL, material = "Metal" },
                    { name = "Blade", shape = "Block", size = { x = 0.85, y = 0.06, z = 1 }, offset = { x = -0.48, y = -0.15, z = -2.71 }, rotation = { x = -25, y = 10, z = 0 }, colorHex = METAL, material = "Metal" },
                },
            },
            -- Fernsteuerung der Maschinen: kleines Kästchen mit Antenne und Knopf.
            remote = {
                parts = {
                    { name = "Box", shape = "Block", size = { x = 0.5, y = 0.22, z = 0.38 }, offset = { x = -0.1, y = 0.2, z = -0.15 }, rotation = { x = 15, y = 0, z = 0 }, colorHex = "#3A3A3A", material = "SmoothPlastic" },
                    { name = "Antenna", shape = "Block", size = { x = 0.04, y = 0.5, z = 0.04 }, offset = { x = 0.08, y = 0.5, z = -0.2 }, colorHex = "#9A9A9A", material = "Metal" },
                    { name = "Button", shape = "Ball", size = { x = 0.12, y = 0.12, z = 0.12 }, offset = { x = -0.18, y = 0.33, z = -0.2 }, colorHex = "#D23C3C", material = "Neon" },
                },
            },
        } :: { [string]: Item },
    },

    -- Was die rechte Hand je Werkzeug hält. Unbekannte Werkzeuge bekommen `defaultTool`.
    defaultTool = "mega_machine",
    tools = {
        hand = { item = "none", dig = "scoop", hideWorldTool = true },
        shovel = { item = "shovel", dig = "stab", hideWorldTool = true },
        bucket_chain = { item = "remote", dig = "lever", hideWorldTool = false },
        mini_digger = { item = "remote", dig = "lever", hideWorldTool = false },
        vacuum_robot = { item = "remote", dig = "lever", hideWorldTool = false },
        mega_machine = { item = "remote", dig = "lever", hideWorldTool = false },
    } :: { [string]: ToolView },

    digStyles = {
        -- Hand: greift nach vorn unten in den Sand und zieht zurück.
        scoop = { move = { x = -0.15, y = -0.35, z = -0.45 }, turn = { x = -40, y = 0, z = 0 }, period = 0.6, leftFactor = 0.3, shake = 0, shakeHz = 0 },
        -- Schaufel: sticht nach vorn unten.
        stab = { move = { x = 0, y = -0.2, z = -0.5 }, turn = { x = -18, y = 0, z = 0 }, period = 0.8, leftFactor = 0.3, shake = 0, shakeHz = 0 },
        -- Fernsteuerung: kleines Drücken und Zittern.
        lever = { move = { x = 0, y = -0.04, z = 0 }, turn = { x = -4, y = 0, z = 0 }, period = 1.2, leftFactor = 0.1, shake = 0.015, shakeHz = 9 },
    } :: { [string]: DigStyle },

    -- Wippen beim Laufen (beide Hände, gegenläufig).
    walk = {
        bobStuds = 0.06,
        swayStuds = 0.04, -- seitlich
        bobHz = 1.8,
        fullSpeed = 16, -- ab dieser Geschwindigkeit volles Wippen (Roblox-Standard WalkSpeed)
    },

    -- Nachziehen beim Umsehen: die Hände hängen der Drehung leicht hinterher.
    sway = {
        degreesPerRadian = 40, -- Neigung je Bogenmaß Drehung seit dem letzten Bild
        maxDegrees = 6,
        smoothing = 12, -- je Sekunde, größer = straffer
    },

    -- Eigene Maschine: Teile, die direkt vor den Augen liegen, werden für den eigenen Blick
    -- durchscheinend. Der Sicht-Gang ist ein Quader vor der Kamera (x ±halfWidth, y Augenhöhe
    -- ±halfHeight, z von nearZ bis farZ nach vorn).
    toolView = {
        lane = { halfWidth = 1.5, halfHeight = 1, nearZ = 0, farZ = 20 },
        fadeTo = 0.75,
        defaultEyeHeight = 4.5,
    },

    -- Zielen beim Graben: Das Loch entsteht dort, wohin Fadenkreuz (oder bei freier Maus der
    -- Mauszeiger) zeigt, nicht mehr fest vor dem Charakter. Der Abstand zum Charakter (waagrecht)
    -- wird begrenzt: mindestens so weit, dass das Loch den Charakter nicht erreicht
    -- (Lochradius + Charakter-Quader + `marginStuds`), höchstens Arbeitsspitze + `extraReachStuds`.
    -- Zielt man in den Himmel, gräbt das Werkzeug an seiner Arbeitsspitze in Blickrichtung.
    aim = {
        rayLengthStuds = 80, -- so weit reicht der Strahl aus der Kamera
        extraReachStuds = 6,
        marginStuds = 0.2,
    },

    -- Eigene Kosmetik am Körper (Umhang, Schärpe), die in der Ego-Perspektive den Blick stört.
    hiddenItemParts = { "Cape", "Sash" },
}
