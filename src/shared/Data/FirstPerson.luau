--!strict
-- Ego-Perspektive: Zahlen für Kamera, sichtbare Arme, freie Maus und Werkzeug-Sicht.
-- Die Rechnung steht in Logic/FirstPerson (Lune-Tests in tests/firstperson.spec.luau), der
-- Controller Controllers/FirstPerson setzt sie nur um. Alles nur auf dem Client, der Server
-- rechnet unabhängig davon.
--
-- Winkel in Grad, Längen in Studs, Zeiten in Sekunden.
-- Armhaltung: Drehung um die Schulter im Raum des Oberkörpers.
--   x  hebt den Arm nach vorn (0 = hängt herab, 90 = zeigt waagrecht nach vorn)
--   y  dreht den Arm zur Mitte (positiv beim rechten Arm = nach links, der linke wird gespiegelt)
--   z  spreizt den Arm zur Seite (positiv = nach außen, der linke wird gespiegelt)

export type Pose = { x: number, y: number, z: number }

export type DigStyle = {
    -- Schwung beim Sammeln: Ausschlag je Achse, eine Periode in `period` Sekunden.
    swing: Pose,
    period: number,
    -- Der linke Arm schwingt um so viel einer Periode versetzt (0.5 = Gegentakt).
    leftPhase: number,
    -- Zusätzliches Zittern (Maschinen), Ausschlag in Grad und Frequenz in Hertz.
    shake: number,
    shakeHz: number,
}

export type ArmStyle = {
    right: Pose, -- Grundhaltung des rechten Arms
    left: Pose, -- Grundhaltung des linken Arms (wird gespiegelt)
    dig: string, -- Eintrag in `digStyles`
}

return {
    enabled = true,

    camera = {
        -- Sichtfeld der Kamera. Roblox-Standard ist 70.
        fieldOfView = 75,
        -- Verschiebung der Kamera gegenüber dem Kopf (Humanoid.CameraOffset, z nach vorn negativ).
        offset = { x = 0, y = 0, z = 0 },
        -- Die Schultern rücken nur für den eigenen Blick etwas hoch, nach innen und nach vorn, damit
        -- die Hände unten im Bild liegen. Andere Spieler sehen den Charakter unverändert.
        shoulderShift = { inward = 0.15, up = 0.5, forward = 0.2 },
        -- Wie stark die Arme der Blickneigung folgen (1 = voll, 0 = gar nicht).
        pitchFollow = 0.85,
        -- Grenzen der Blickneigung, die an die Arme weitergegeben wird.
        minPitch = -70,
        maxPitch = 70,
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
        checkSeconds = 0.2, -- so oft wird nachgesehen
    },

    crosshair = {
        size = 6, -- Pixel
        transparency = 0.25,
    },

    -- Bewegung der Arme beim Laufen.
    walk = {
        bobDegrees = 3, -- klein, weil die Lauf-Animation von Roblox die Arme schon schwingt -- Ausschlag des Arm-Wippens bei voller Laufgeschwindigkeit
        bobHz = 1.8,
        fullSpeed = 16, -- ab dieser Geschwindigkeit volles Wippen (Roblox-Standard WalkSpeed)
    },

    -- Glättung: so schnell erreichen die Arme die neue Haltung (je Sekunde, größer = straffer).
    smoothing = 14,

    -- Wie die Arme bei den Werkzeugen aussehen. Unbekannte Werkzeuge bekommen `defaultArms`.
    defaultArms = "machine",
    arms = {
        -- Mit den Händen schaufeln: beide Arme vorn, schwingen im Gegentakt nach unten.
        hand = { right = { x = 80, y = 14, z = 0 }, left = { x = 80, y = 14, z = 0 }, dig = "scoop" },
        -- Schaufel: rechte Hand weiter vorn, linke weiter oben am Stiel, beide stechen gemeinsam.
        shovel = { right = { x = 75, y = 18, z = 0 }, left = { x = 92, y = 30, z = 0 }, dig = "stab" },
        -- Maschinen: beide Hände an den Hebeln, nur Zittern und kleines Ruckeln.
        bucket_chain = { right = { x = 72, y = 12, z = 4 }, left = { x = 72, y = 12, z = 4 }, dig = "lever" },
        mini_digger = { right = { x = 72, y = 12, z = 4 }, left = { x = 72, y = 12, z = 4 }, dig = "lever" },
        vacuum_robot = { right = { x = 72, y = 12, z = 4 }, left = { x = 72, y = 12, z = 4 }, dig = "lever" },
        mega_machine = { right = { x = 72, y = 12, z = 4 }, left = { x = 72, y = 12, z = 4 }, dig = "lever" },
        machine = { right = { x = 72, y = 12, z = 4 }, left = { x = 72, y = 12, z = 4 }, dig = "lever" },
    } :: { [string]: ArmStyle },

    digStyles = {
        scoop = { swing = { x = -35, y = 0, z = 0 }, period = 0.6, leftPhase = 0.5, shake = 0, shakeHz = 0 },
        stab = { swing = { x = -25, y = 0, z = 0 }, period = 0.8, leftPhase = 0, shake = 0, shakeHz = 0 },
        lever = { swing = { x = -6, y = 0, z = 0 }, period = 1.2, leftPhase = 0.5, shake = 1.5, shakeHz = 9 },
    } :: { [string]: DigStyle },

    -- Eigene Maschine: Teile, die direkt vor den Augen liegen, werden für den eigenen Blick
    -- durchscheinend. Der Sicht-Gang ist ein Quader vor der Kamera (x ±halfWidth, y Augenhöhe
    -- ±halfHeight, z von nearZ bis farZ nach vorn).
    toolView = {
        lane = { halfWidth = 1.5, halfHeight = 1, nearZ = 0, farZ = 20 },
        fadeTo = 0.75, -- LocalTransparencyModifier der Teile im Sicht-Gang
        defaultEyeHeight = 4.5, -- Augenhöhe über dem Boden, falls der Charakter keine liefert
    },

    -- Eigene Kosmetik am Körper (Umhang, Schärpe), die in der Ego-Perspektive den Blick stört.
    hiddenItemParts = { "Cape", "Sash" },
}
