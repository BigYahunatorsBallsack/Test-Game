--!strict
-- ProductPrices-Controller (Paket 4.6, Sicherheitsprüfung 4.1 N7)
-- Holt beim Start für jedes Produkt mit ID über 0 (Data/Products, Data/GemPacks) einmal den Preis
-- und "zum Verkauf" bei Roblox (MarketplaceService, GetProductInfoAsync oder GetProductInfo). Der Shop
-- zeigt damit den Preis aus dem Creator Dashboard, den auch der Kaufdialog zeigt. Scheitert die
-- Abfrage, bleibt der Tabellenpreis (Logic/PriceView). Der Client entscheidet damit nichts: Gebucht
-- wird nur über ProcessReceipt bzw. die Besitzprüfung auf dem Server.

local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FETCH_ATTEMPTS = 3
local FETCH_RETRY_SECONDS = 2
local FETCH_GAP_SECONDS = 0.1 -- kleine Pause zwischen Produkten, damit nicht alles in einem Bild fragt

local shared = ReplicatedStorage:WaitForChild("Shared")
local function loadShared(folder: string, name: string): any
    return require(shared:WaitForChild(folder):WaitForChild(name) :: ModuleScript)
end
local Products = loadShared("Data", "Products")
local GemPacks = loadShared("Data", "GemPacks")

export type Info = { price: number?, forSale: boolean? }

local ProductPrices = {}

local infos: { [string]: Info } = {}
local listeners: { () -> () } = {}

local function key(isPass: boolean, productId: number): string
    return `{if isPass then "pass" else "product"}:{productId}`
end

-- Bekannte Antwort von Roblox oder nil.
function ProductPrices.info(isPass: boolean, productId: number): Info?
    return infos[key(isPass, productId)]
end

-- Wird nach jeder neuen Antwort aufgerufen (der Shop schreibt seine Knöpfe neu).
function ProductPrices.onChanged(callback: () -> ())
    table.insert(listeners, callback)
end

-- Ruft die neuere Async-Variante, wenn es sie gibt, sonst GetProductInfo.
local function askRoblox(productId: number, infoType: Enum.InfoType): any
    local market: any = MarketplaceService
    -- Ein fehlendes Mitglied wirft beim Lesen, darum in pcall.
    local found, method = pcall(function(): any
        return market.GetProductInfoAsync
    end)
    if found and type(method) == "function" then
        return method(market, productId, infoType)
    end
    return market:GetProductInfo(productId, infoType)
end

local function fetch(isPass: boolean, productId: number)
    local infoType = if isPass then Enum.InfoType.GamePass else Enum.InfoType.Product
    for attempt = 1, FETCH_ATTEMPTS do
        local ok, result = pcall(askRoblox, productId, infoType)
        if ok and type(result) == "table" then
            local price = result.PriceInRobux
            local forSale = result.IsForSale
            infos[key(isPass, productId)] = {
                price = if type(price) == "number" then price else nil,
                forSale = if type(forSale) == "boolean" then forSale else nil,
            }
            for _, listener in listeners do
                task.spawn(listener)
            end
            return
        end
        if attempt < FETCH_ATTEMPTS then
            task.wait(FETCH_RETRY_SECONDS)
        end
    end
    warn(`[ProductPrices] Preis für {if isPass then "Gamepass" else "Produkt"} {productId} nicht abrufbar, Tabellenpreis bleibt`)
end

function ProductPrices.Init() end

function ProductPrices.Start()
    local queue: { { isPass: boolean, productId: number } } = {}
    for _, product in Products.list do
        if product.productId > 0 and (product.kind == "gamepass" or product.kind == "developerProduct") then
            table.insert(queue, { isPass = product.kind == "gamepass", productId = product.productId })
        end
    end
    for _, pack in GemPacks.list do
        if pack.productId > 0 then
            table.insert(queue, { isPass = false, productId = pack.productId })
        end
    end
    task.spawn(function()
        for _, entry in queue do
            task.spawn(fetch, entry.isPass, entry.productId)
            task.wait(FETCH_GAP_SECONDS)
        end
    end)
end

return ProductPrices
