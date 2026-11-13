-- F8 menu (the "variant C" HUD sidebar) and the status line.
--   top bar   presets: pick, save, save as, rename, delete, load at startup (presets.lua)
--   left      bot on/off, what it is doing now, goal, character, behaviour toggles
--   right     priority and exclusion tiles with item sprites, item catalog with search
-- Every setting has a "?" with an explanation (hover shows it, click pins it).
-- Everything is drawn in MC_POST_RENDER in screen coordinates: boxes with our own 1 px
-- sprite (resources/gfx/isaacbot/px.anm2), text with a game font that has Cyrillic, item
-- icons from the game's own pedestal sprite with the item's sheet swapped in at runtime.
-- Mouse (own cursor) and keyboard both work; while the menu is open main.lua keeps the
-- player's keys from moving, shooting, restarting (R) or opening the map (Tab).

return function(B)
    local P = {}
    B.panel = P
    local PR = B.presets

    P.open = false
    P.items = {}   -- catalog sorted by id: {id, name, low, q, gfx, breaks}
    P.byId = {}

    -- ------------------------------------------------------------ catalog

    function P.buildCatalog()
        if #P.items > 0 then return end
        local cfg = B.try(function() return Isaac.GetItemConfig() end)
        local list = cfg and B.try(function() return cfg:GetCollectibles() end)
        if not list then return end
        for id = 1, list.Size - 1 do
            local c = B.try(function() return cfg:GetCollectible(id) end)
            local name = c and B.try(function() return c.Name end)
            if name and name ~= "" then
                local it = {id = id, name = name, low = B.lower(name),
                    q = B.try(function() return c.Quality end) or 0,
                    gfx = B.try(function() return c.GfxFileName end),
                    breaks = B.items.BOT_BREAKING[id] or false}
                P.items[#P.items + 1] = it
                P.byId[id] = it
            end
        end
    end

    -- ItemConfig can hand back a raw localization key ("#THE_SAD_ONION_NAME") when the game
    -- has no translation for it. Decode that into readable English for display only.
    local function readableKey(s)
        if type(s) ~= "string" or s:sub(1, 1) ~= "#" then return s end
        local base = s:match("^#(.+)_NAME$") or s:match("^#(.+)_DESC$")
        if not base then return s end
        base = base:gsub("_", " ")
        base = base:gsub("(%a)([%a']*)", function(a, b) return a:upper() .. b:lower() end)
        return (base:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", ""))
    end

    local function itemName(id)
        local it = P.byId[id]
        return it and readableKey(it.name) or ("#" .. id)
    end

    -- ------------------------------------------------------------ drawing

    local COL = {
        panel = {0.07, 0.06, 0.08}, panel2 = {0.14, 0.12, 0.15}, panel3 = {0.21, 0.18, 0.2},
        line = {0.3, 0.26, 0.22}, gold = {0.98, 0.82, 0.4}, text = {0.94, 0.92, 0.88},
        dim = {0.7, 0.67, 0.62}, faint = {0.5, 0.47, 0.44}, green = {0.45, 0.9, 0.5},
        red = {0.95, 0.4, 0.36}, orange = {1, 0.65, 0.3}, black = {0, 0, 0}, white = {1, 1, 1},
        sel = {0.3, 0.23, 0.12},
    }

    local W, H = 480, 270
    local font, TS, LH = nil, 1, 13     -- font, text scale, scaled line height
    local fontTried = false

    -- The game ships a CJK pixel font whose line height is 13. The menu used to be scaled
    -- down to ~9 px to fit; at that size CJK glyphs blur, so the layout is built for the
    -- native 13 px now and only shrinks if the font is bigger than that.
    -- The UI is ASCII again, so a plain Latin font is the safe pick; the CJK font stays last
    -- (it has advance widths for CJK but no real glyphs in this build, which renders boxes).
    local FONTS = {"font/terminus.fnt", "font/pftempestasevencondensed.fnt",
        "font/luaminioutlined.fnt", "font/teammeatfont10.fnt", "font/droid.fnt",
        "font/teammeatex/teammeatex10.fnt", "font/cjk/lanapixel.fnt"}
    local function loadFont()
        if fontTried then return end
        fontTried = true
        local report, pick, back = {}, nil, nil
        for _, path in ipairs(FONTS) do
            local f = B.try(function() return Font() end)
            if f then B.try(function() f:Load(path) end) end
            if f and B.try(function() return f:IsLoaded() end) then
                local lh = B.try(function() return f:GetLineHeight() end) or 0
                local cjk = B.try(function() return f:GetStringWidthUTF8("PP Bot") end) or 0
                local cyr = B.try(function() return f:GetStringWidthUTF8("Жыщ") end) or 0
                local lat = B.try(function() return f:GetStringWidthUTF8("Abc") end) or 0
                report[#report + 1] = string.format("%s lh=%s cjk=%s lat=%s", path, lh, cjk, lat)
                if not pick and cjk > 0 and lh > 0 then pick = {f = f, lh = lh, path = path} end
                if not back and cyr > 0 and lh > 0 then back = {f = f, lh = lh, path = path} end
            else
                report[#report + 1] = path .. " missing"
            end
        end
        B.log("menu fonts: " .. table.concat(report, "; "))
        if not pick then pick = back end
        if pick then
            font = pick.f
            TS = math.max(0.85, math.min(1, 13 / pick.lh))
            LH = pick.lh * TS
            B.log("menu font " .. pick.path .. " scale " .. TS)
        else
            LH = 13
            B.log("menu font: none loaded, using Isaac.RenderText")
        end
    end

    local widthCache, widthCount = {}, 0
    local function tw(s, scale)
        local w = widthCache[s]
        if not w then
            w = font and B.try(function() return font:GetStringWidthUTF8(s) end) or (#s * 6)
            if widthCount > 3000 then widthCache, widthCount = {}, 0 end
            widthCache[s] = w
            widthCount = widthCount + 1
        end
        return w * TS * (scale or 1)
    end

    local function text(s, x, y, col, a, scale)
        col = col or COL.text
        local k = TS * (scale or 1)
        if font then
            font:DrawStringScaledUTF8(s, x, y, k, k, KColor(col[1], col[2], col[3], a or 1), 0, false)
        else
            Isaac.RenderText(s, x, y, col[1], col[2], col[3], a or 1)
        end
    end

    -- Text cut to a width with "..." (cached: the catalog draws many rows per frame).
    local fitCache, fitCount = {}, 0
    local function fit(s, maxw)
        if tw(s) <= maxw then return s end
        local key = s .. "|" .. math.floor(maxw)
        local r = fitCache[key]
        if r then return r end
        r = s
        while #r > 0 and tw(r .. "...") > maxw do r = B.utf8pop(r) end
        r = r .. "..."
        if fitCount > 2000 then fitCache, fitCount = {}, 0 end
        fitCache[key] = r
        fitCount = fitCount + 1
        return r
    end

    -- Drop the first UTF-8 character (input fields scroll their text from the left).
    local function utf8drop(s)
        if s == "" then return s end
        local b = s:byte(1) or 0
        local n = 1
        if b >= 0xF0 then n = 4 elseif b >= 0xE0 then n = 3 elseif b >= 0xC0 then n = 2 end
        return s:sub(1 + n)
    end

    local px, pxTried = nil, false
    local function rect(x, y, w, h, col, a)
        if w <= 0 or h <= 0 then return end
        if not pxTried then
            pxTried = true
            local s = B.try(function() return Sprite() end)
            if s then
                B.try(function() s:Load("gfx/isaacbot/px.anm2", true) end)
                B.try(function() s:SetFrame("Idle", 0) end)
                if B.try(function() return s:IsLoaded() end) then px = s end
            end
            B.log("menu box sprite " .. (px and "ok" or "missing (restart the game once after install)"))
        end
        if not px then return end
        px.Scale = Vector(w, h)
        px.Color = Color(col[1], col[2], col[3], a or 1, 0, 0, 0)
        px:Render(Vector(x, y), Vector(0, 0), Vector(0, 0))
    end

    local function border(x, y, w, h, col, a)
        rect(x, y, w, 1, col, a)
        rect(x, y + h - 1, w, 1, col, a)
        rect(x, y, 1, h, col, a)
        rect(x + w - 1, y, 1, h, col, a)
    end

    -- Item icons: the pedestal animation with the item's sheet on layer 1. One sprite per
    -- item, created on first use; the cache is dropped when it grows past 160.
    -- Calibrated by screenshot: the item art is centred 22 sheet px above the layer origin
    -- and is about 22 px tall, so that many sheet pixels fill the icon box.
    local ICON_CY, ICON_ART = 22, 22
    local icons, iconCount = {}, 0
    local function icon(id, x, y, size, alpha)
        local s = icons[id]
        if s == nil then
            if iconCount > 160 then icons, iconCount = {}, 0 end
            s = false
            local it = P.byId[id]
            if it and it.gfx and it.gfx ~= "" then
                local spr = B.try(function() return Sprite() end)
                if spr then
                    B.try(function()
                        spr:Load("gfx/005.100_collectible.anm2", false)
                        spr:ReplaceSpritesheet(1, it.gfx)
                        spr:LoadGraphics()
                        spr:SetFrame("Idle", 0)
                    end)
                    s = spr
                end
            end
            icons[id] = s
            iconCount = iconCount + 1
        end
        if not s then
            text("?", x + size / 2 - 2, y + size / 2 - LH / 2, COL.faint)
            return
        end
        local k = size / ICON_ART
        s.Scale = Vector(k, k)
        s.Color = Color(1, 1, 1, alpha or 1, 0, 0, 0)
        s:RenderLayer(1, Vector(x + size / 2, y + size / 2 + ICON_CY * k), Vector(0, 0), Vector(0, 0))
    end

    -- ------------------------------------------------------------ input state

    local M = {x = -100, y = -100, down = false, pressed = false, released = false,
        rdown = false, rpressed = false, used = false, moved = false}
    local hoverOK = true

    local function readMouse()
        local wp = B.try(function() return Input.GetMousePosition(true) end)
        local sp = wp and B.try(function() return Isaac.WorldToScreen(wp) end)
        if sp then
            M.moved = math.abs(sp.X - M.x) + math.abs(sp.Y - M.y) > 0.5
            M.x, M.y = sp.X, sp.Y
        end
        local d = B.try(function() return Input.IsMouseBtnPressed(Mouse.MOUSE_BUTTON_LEFT) end) and true or false
        local fake = P.fakeClick
        if fake then
            -- bridge test click: hold for 2 frames at the given point, then release
            M.x, M.y = fake.x, fake.y
            if fake.n == 0 then B.log(string.format("menu test click %.1f %.1f screen %dx%d", M.x, M.y, W, H)) end
            d = fake.n < 2
            fake.n = fake.n + 1
            if fake.n > 3 then P.fakeClick = nil end
        end
        M.pressed, M.released, M.down = d and not M.down, M.down and not d, d
        local r = B.try(function() return Input.IsMouseBtnPressed(Mouse.MOUSE_BUTTON_RIGHT) end) and true or false
        M.rpressed, M.rdown = r and not M.rdown, r
        M.used = false
    end

    -- Mouse wheel is not in the vanilla API; probe it so scrolling works when it exists.
    local function wheelDelta()
        local ok, v = pcall(function() return Input.GetMouseWheel() end)
        if ok and type(v) == "number" then return v end
        return 0
    end

    local function inside(x, y, w, h)
        return M.x >= x and M.x < x + w and M.y >= y and M.y < y + h
    end

    local function hot(x, y, w, h)
        return hoverOK and inside(x, y, w, h)
    end

    local function clicked(x, y, w, h)
        if M.pressed and not M.used and hot(x, y, w, h) then
            M.used = true
            return true
        end
        return false
    end

    local function rclicked(x, y, w, h)
        return M.rpressed and hot(x, y, w, h)
    end

    local function keyDown(key)
        return B.try(function() return Input.IsButtonPressed(key, 0) end) and true or false
    end

    local held = {}
    local function edge(key)
        local now = keyDown(key)
        local was = held[key]
        held[key] = now and (was or 0) + 1 or nil
        return now and not was
    end

    -- Pressed now, or held long enough to auto-repeat (arrows, backspace). Call edge()
    -- first in the same frame for the counter to advance.
    local function repeating(key)
        local n = held[key]
        return n ~= nil and (n == 1 or (n > 24 and n % 4 == 0))
    end

    local function shift()
        return keyDown(Keyboard.KEY_LEFT_SHIFT) or keyDown(Keyboard.KEY_RIGHT_SHIFT)
    end

    -- Physical keys to characters: Latin, or the Russian ЙЦУКЕН layout (Tab switches).
    local RU = {Q = "й", W = "ц", E = "у", R = "к", T = "е", Y = "н", U = "г", I = "ш", O = "щ",
        P = "з", A = "ф", S = "ы", D = "в", F = "а", G = "п", H = "р", J = "о", K = "л", L = "д",
        Z = "я", X = "ч", C = "с", V = "м", B = "и", N = "т", M = "ь"}
    local RU_PUNCT = {[91] = "х", [93] = "ъ", [59] = "ж", [39] = "э", [44] = "б", [46] = "ю",
        [96] = "ё", [47] = ".", [45] = "-", [32] = " "}
    local EN_PUNCT = {[45] = "-", [46] = ".", [47] = "/", [39] = "'", [44] = ",", [59] = ";",
        [32] = " ", [91] = "(", [93] = ")"}

    local function upperRu(ch)
        local b1, b2 = ch:byte(1, 2)
        if b1 == 0xD0 and b2 >= 0xB0 and b2 <= 0xBF then return string.char(0xD0, b2 - 0x20) end
        if b1 == 0xD1 and b2 >= 0x80 and b2 <= 0x8F then return string.char(0xD0, b2 + 0x20) end
        if b1 == 0xD1 and b2 == 0x91 then return "Ё" end
        return ch
    end

    local V = {
        ru = false, query = "", filter = "all", cursor = 1, scroll = 0, shown = {}, sig = nil,
        dd = false, more = false, form = nil, drag = nil, sbDrag = false,
        msg = "", msgUntil = 0, msgCol = COL.green, f7armed = 0, hint = nil, hoverName = nil,
    }

    local function toast(s, col)
        V.msg, V.msgUntil, V.msgCol = s, B.st.renderTick + 150, col or COL.green
    end

    -- Characters typed this frame (letters, digits, a little punctuation).
    local function typed()
        local out = ""
        local up = shift()
        for key = 32, 96 do
            if edge(key) then
                local ch
                if key >= 65 and key <= 90 then
                    local letter = string.char(key)
                    if V.ru then
                        ch = RU[letter]
                        if up then ch = upperRu(ch) end
                    else
                        ch = up and letter or letter:lower()
                    end
                elseif key >= 48 and key <= 57 then
                    ch = string.char(key)
                else
                    ch = (V.ru and RU_PUNCT or EN_PUNCT)[key]
                    if ch and up and V.ru then ch = upperRu(ch) end
                end
                if ch then out = out .. ch end
            end
        end
        for key = 320, 329 do
            if edge(key) then out = out .. string.char(48 + key - 320) end
        end
        return out
    end

    -- ------------------------------------------------------------ labels

    local GOAL_LABEL = {auto = "Auto", mom = "Mom", heart = "Heart", isaac = "Isaac",
        satan = "Satan", bluebaby = "???", lamb = "Lamb"}
    local GOAL_ORDER = {"mom", "heart", "isaac", "satan", "bluebaby", "lamb", "auto"}

    local CHAR_EN = {[0] = "Isaac", [1] = "Magdalene", [2] = "Cain", [3] = "Judas", [4] = "???",
        [5] = "Eve", [6] = "Samson", [7] = "Azazel", [8] = "Lazarus", [9] = "Eden", [10] = "The Lost",
        [13] = "Lilith", [14] = "Keeper", [15] = "Apollyon", [16] = "The Forgotten", [18] = "Bethany",
        [19] = "Jacob & Esau"}
    local function charName(id)
        if CHAR_EN[id] then return CHAR_EN[id] end
        if id >= 21 and id <= 37 then
            local base = {[21] = 0, [22] = 1, [23] = 2, [24] = 3, [25] = 4, [26] = 5, [27] = 6,
                [28] = 7, [29] = 8, [30] = 9, [31] = 10, [32] = 13, [33] = 14, [34] = 15, [35] = 16,
                [36] = 18, [37] = 19}
            return "T. " .. (CHAR_EN[base[id]] or "?")
        end
        return B.characterName(id)
    end
    local CHAR_MODE = {same = "Same", cycle = "Cycle", random = "Random"}
    local function charLabel(c)
        if type(c) == "number" then return charName(c) end
        return CHAR_MODE[c] or tostring(c)
    end

    local MODE_EN = {fight = "Fight", boss = "Boss", loot = "Loot", exit = "Exit", door = "Path",
        explore = "Path", enter = "Enter", hold = "Wait", wait = "Wait", won = "Won", dead = "Dead",
        paused = "Paused", off = "Off", unstick = "Stuck", bedroom = "Bedroom", bomb = "Bomb",
        fire = "Fire", poop = "Poop", plate = "Plate", boot = "Boot", idle = "Idle",
        gamepause = "Game pause", roam = "Path", leave = "Exit", deal = "Deal", ["to boss"] = "To boss",
        sweep = "Clear"}

    -- Detail words the brain puts after the mode ("sweep fire", "wait 27"): translate the head.
    local DETAIL_EXACT = {["poop bomb"] = "Poop bomb"}
    local DETAIL_EN = {fire = "Fire", poop = "Poop", rock = "Rock", wait = "Wait", cell = "Cell",
        slot = "Door", tears = "Tears", brim = "Brimstone", knife = "Knife", techx = "Tech X",
        melee = "Melee", lungs = "Lungs", bomb = "Bomb", boss = "Boss"}
    local function detailText(d)
        if not d or d == "" then return "" end
        if DETAIL_EXACT[d] then return DETAIL_EXACT[d] end
        local head, rest = d:match("^(%S+)%s*(.*)$")
        local en = head and DETAIL_EN[head]
        if not en then return d end
        if rest and rest ~= "" then return en .. " " .. rest end
        return en
    end

    -- Built-in preset names are storage keys in presets.lua; translate the display only.
    local PRESET_EN = {
        ["Стандарт"] = "Standard",
        ["Спидран до Мамы"] = "Mom Speedrun",
        ["Азазель до Агнца"] = "Azazel to Lamb",
    }
    local function presetLabel(name) return PRESET_EN[name] or name end

    -- presets.lua reports bad names in Russian; show them in Chinese as well.
    local ERR_EN = {
        ["Введите название"] = "Enter a name",
        ["Пресет с таким названием уже есть"] = "Name already in use",
    }
    local function errText(s) return ERR_EN[s] or s end

    -- One short line per control, shown in the strip under the title bar on hover.
    local HINT = {
        run = "F9 also toggles the bot; not saved in presets",
        goal = "Which ending the bot goes for",
        char = "Who starts the next run; needs auto-restart",
        autoRestart = "Start a new run after death",
        onWin = "Next run right after the goal boss",
        fast = "Treasure room and shop, then straight to the boss",
        devil = "Devil deals only if 2+ hearts remain",
        useActives = "Use charged active items in boss fights",
        useBombs = "Bomb rocks in the way and the bedroom door",
        pri = "Grabbed first: drag to reorder, right-click to remove",
        exc = "Never picked up or bought",
        cat = "Search id or name; + priority, - exclude",
        preset = "Click to switch; ... to rename, delete, set startup",
    }

    local function setHint(key, x, y, w, h)
        if key and HINT[key] and hot(x, y, w, h) then V.hint = HINT[key] end
    end

    -- ------------------------------------------------------------ widgets

    local function vy(y, h) return y + math.floor((h - LH) / 2 + 0.5) end

    local function pill(label, x, y, on, enabled, w, hintKey)
        local h = LH + 1
        w = w or (tw(label) + 10)
        local hov = enabled ~= false and hot(x, y, w, h)
        if hov and hintKey then setHint(hintKey, x, y, w, h) end
        rect(x, y, w, h, on and {0.45, 0.35, 0.12} or (hov and COL.panel3 or COL.panel2), 1)
        border(x, y, w, h, (on or hov) and COL.gold or COL.line, on and 1 or 0.6)
        local tc = on and COL.white or (enabled == false and COL.faint or COL.text)
        text(label, x + math.floor((w - tw(label)) / 2), vy(y, h), tc)
        return w, (enabled ~= false) and clicked(x, y, w, h)
    end

    local function button(label, x, y, style, enabled, w)
        local h = LH + 3
        w = w or (tw(label) + 12)
        local hov = enabled ~= false and hot(x, y, w, h)
        local bg = COL.panel2
        if style == "primary" and enabled ~= false then bg = hov and {0.75, 0.6, 0.25} or {0.55, 0.43, 0.17}
        elseif style == "danger" and enabled ~= false then bg = hov and {0.7, 0.25, 0.2} or {0.46, 0.16, 0.13}
        elseif hov then bg = COL.panel3 end
        rect(x, y, w, h, bg, 1)
        border(x, y, w, h, hov and COL.gold or COL.line, 0.8)
        text(label, x + math.floor((w - tw(label)) / 2), vy(y, h), enabled == false and COL.faint or COL.text)
        return w, (enabled ~= false) and clicked(x, y, w, h)
    end

    local function switch(on, x, y)
        local w, h = 18, LH - 3
        local yy = y + 1
        rect(x, yy, w, h, on and {0.25, 0.55, 0.28} or COL.panel3, 1)
        border(x, yy, w, h, on and COL.green or COL.line, 0.9)
        local k = h - 4
        rect(on and (x + w - k - 2) or (x + 2), yy + 2, k, k, on and COL.white or COL.dim, 1)
        return w
    end

    local function title(s, x, w, y, right, rightCol)
        text(s, x, y, COL.gold)
        if right then text(right, x + w - tw(right), y, rightCol or COL.faint) end
        return y + LH + 3
    end

    -- ------------------------------------------------------------ presets

    local function switchTo(i)
        PR.select(i)
        V.dd, V.more, V.form = false, false, nil
        toast("Loaded: " .. presetLabel(PR.active().name))
    end

    local function askName(mode, initial, after)
        V.dd, V.more = false, false
        V.form = {kind = "name", mode = mode, value = initial, err = nil, after = after}
    end

    local function confirm(textLine, buttons)
        V.dd, V.more = false, false
        V.form = {kind = "confirm", text = textLine, buttons = buttons}
    end

    local function saveAs(after)
        local p = PR.active()
        askName("saveas", PR.uniqueName(p.lock and (presetLabel(p.name) .. " (copy)") or p.name), after)
    end

    local function wantSwitch(i)
        if i == PR.activeIndex() then V.dd = false return end
        if not PR.dirty() then switchTo(i) return end
        local p = PR.active()
        confirm("Preset " .. presetLabel(p.name) .. " has unsaved changes.", {
            {p.lock and "Save as new" or "Save & switch", "primary", function()
                if p.lock then saveAs(function() switchTo(i) end)
                else PR.saveActive() switchTo(i) end
            end},
            {"Don't save", nil, function() switchTo(i) end},
            {"Cancel", nil, function() V.form = nil end},
        })
    end

    local function submitName()
        local f = V.form
        local except = (f.mode == "rename") and PR.activeIndex() or nil
        local bad = PR.badName(f.value, except)
        if bad then f.err = bad return end
        local name = f.value:gsub("^%s+", ""):gsub("%s+$", "")
        V.form = nil
        if f.mode == "rename" then
            PR.rename(name)
            toast("Renamed: " .. presetLabel(name))
        else
            PR.saveAs(name)
            toast("Saved as: " .. presetLabel(name))
        end
        if f.after then f.after() end
    end

    -- Input strip under the title bar: preset name entry or a yes/no question.
    local function drawForm(y)
        local f = V.form
        local h = LH + 8
        rect(4, y, W - 8, h, COL.panel, 0.97)
        border(4, y, W - 8, h, COL.gold, 0.9)
        local cx, cy = 10, y + (h - LH) / 2
        if f.kind == "name" then
            local label = (f.mode == "rename") and "Name" or "New preset"
            text(label, cx, cy, COL.text)
            cx = cx + tw(label) + 8
            local iw, ih = 150, LH + 3
            local iy = y + (h - ih) / 2
            rect(cx, iy, iw, ih, COL.black, 0.8)
            border(cx, iy, iw, ih, COL.gold, 0.9)
            local caret = (B.st.renderTick // 20) % 2 == 0 and "_" or ""
            local shown = f.value
            while #shown > 0 and tw(shown .. "_") > iw - 8 do shown = utf8drop(shown) end
            text(shown .. caret, cx + 4, vy(iy, ih), COL.text)
            cx = cx + iw + 6
            local w, c = button("OK", cx, iy, "primary")
            if c then submitName() return h end
            cx = cx + w + 3
            w, c = button("Cancel", cx, iy)
            if c then V.form = nil return h end
            cx = cx + w + 8
            text(V.ru and "RU" or "EN", cx, cy, COL.faint)
            cx = cx + tw("RU") + 8
            if f.err then text(fit(errText(f.err), W - 10 - cx), cx, cy, COL.red) end
        else
            text(fit(f.text, W * 0.42), cx, cy, COL.text)
            cx = cx + math.min(tw(f.text), W * 0.42) + 10
            for _, b in ipairs(f.buttons) do
                local w, c = button(b[1], cx, y + (h - LH - 3) / 2, b[2])
                if c then b[3]() return h end
                cx = cx + w + 4
            end
        end
        return h
    end

    local function cfgSummary(c)
        return string.format("%s | %s | +%d -%d", GOAL_LABEL[c.goal] or tostring(c.goal),
            charLabel(c.character), #(c.pri or {}), #(c.exc or {}))
    end

    local function ddRect(layout)
        local list = PR.list()
        local rowH = LH + 14
        local maxRows = math.max(1, math.floor((H - layout.ddY - rowH - 12) / rowH))
        local n = math.min(#list, maxRows)
        return layout.ddX, layout.ddY, math.min(240, W - layout.ddX - 4), n * rowH + LH + 10, rowH, n
    end

    local function drawDropdown(layout)
        local list = PR.list()
        local x, y, w, h, rowH, n = ddRect(layout)
        rect(x, y, w, h, COL.panel, 0.98)
        border(x, y, w, h, COL.gold, 0.9)
        local active = PR.activeIndex()
        local first = math.max(1, math.min(active - n + 1, #list - n + 1))
        if active <= n then first = 1 end
        for k = 0, n - 1 do
            local i = first + k
            local p = list[i]
            local ry = y + 2 + k * rowH
            local hov = hot(x + 1, ry, w - 2, rowH)
            if i == active then rect(x + 1, ry, w - 2, rowH, COL.sel, 1)
            elseif hov then rect(x + 1, ry, w - 2, rowH, COL.panel3, 1) end
            local nameStr = presetLabel(p.name) .. (PR.isStartup(p) and " *" or "")
            text(fit(nameStr, w - 60), x + 6, ry + 2, i == active and COL.gold or COL.text)
            if p.lock then text("built-in", x + w - 8 - tw("built-in"), ry + 2, COL.faint) end
            text(fit(cfgSummary(p.cfg), w - 12), x + 6, ry + 2 + LH, COL.dim)
            if clicked(x + 1, ry, w - 2, rowH) then wantSwitch(i) end
        end
        local ay = y + 3 + n * rowH
        local hov = hot(x + 1, ay, w - 2, LH + 4)
        if hov then rect(x + 1, ay, w - 2, LH + 4, COL.panel3, 1) end
        text(fit("+ Save current settings as new preset", w - 12), x + 6, ay + 2, COL.green)
        if clicked(x + 1, ay, w - 2, LH + 4) then saveAs() end
    end

    local MORE_W = 190
    local function moreItems()
        local p = PR.active()
        return {
            {"Rename", not p.lock, function() askName("rename", p.name) end},
            {"Revert changes", PR.dirty(), function() PR.revert() V.more = false toast("Changes reverted") end},
            {(PR.isStartup(p) and "[x] " or "[ ] ") .. "Load at game start", true, function()
                PR.toggleStartup()
                toast(PR.isStartup(p) and (presetLabel(p.name) .. " will load at startup") or "No startup preset selected")
            end},
            {"Delete preset", not p.lock, function()
                confirm("DeletePreset " .. presetLabel(p.name) .. "? This cannot be undone.", {
                    {"Delete", "danger", function()
                        PR.delete()
                        V.form = nil
                        toast("Deleted: " .. presetLabel(p.name))
                    end},
                    {"Cancel", nil, function() V.form = nil end},
                })
            end, true},
        }
    end

    local function moreRect(layout)
        local n = #moreItems()
        local w = MORE_W
        local x = math.min(layout.moreX, W - w - 4)
        return x, layout.moreY, w, n * (LH + 8) + 6
    end

    local function drawMore(layout)
        local x, y, w, h = moreRect(layout)
        rect(x, y, w, h, COL.panel, 0.98)
        border(x, y, w, h, COL.gold, 0.9)
        for k, it in ipairs(moreItems()) do
            local rh = LH + 8
            local ry = y + 3 + (k - 1) * rh
            local en = it[2]
            if en and hot(x + 1, ry, w - 2, rh) then rect(x + 1, ry, w - 2, rh, COL.panel3, 1) end
            local col = not en and COL.faint or (it[4] and COL.red or COL.text)
            local label = it[1] .. ((not en and PR.active().lock and k ~= 2) and "  (built-in)" or "")
            text(fit(label, w - 12), x + 6, vy(ry, rh), col)
            if en and clicked(x + 1, ry, w - 2, rh) then
                V.more = false
                it[3]()
            end
        end
    end

    -- ------------------------------------------------------------ left panel

    local TOGGLES = {
        {"Auto-restart", "autoRestart", function() return B.S.autoRestart end,
            function() B.S.autoRestart = not B.S.autoRestart end},
        {"New run on win", "onWin", function() return B.S.onWin == "restart" end,
            function() B.S.onWin = (B.S.onWin == "restart") and "finish" or "restart" end},
        {"Fast explore", "fast", function() return B.S.explore == "fast" end,
            function() B.S.explore = (B.S.explore == "fast") and "full" or "fast" end},
        {"Devil deals", "devil", function() return B.S.devil end,
            function() B.S.devil = not B.S.devil end},
        {"Active items", "useActives", function() return B.S.useActives end,
            function() B.S.useActives = not B.S.useActives end},
        {"Bombs", "useBombs", function() return B.S.useBombs end,
            function() B.S.useBombs = not B.S.useBombs end},
    }

    local function drawLeft(x, y, w, h)
        rect(x, y, w, h, COL.panel, 0.92)
        border(x, y, w, h, COL.line, 0.7)
        local ix, iw = x + 8, w - 16
        local cy = y + 6

        -- run switch
        local on = B.st.enabled
        local rh = LH + 2
        local hov = hot(ix, cy, iw, rh)
        if hov then V.hint = HINT.run end
        rect(ix, cy, iw, rh, on and {0.12, 0.26, 0.14} or {0.26, 0.12, 0.11}, 1)
        border(ix, cy, iw, rh, on and COL.green or COL.red, hov and 1 or 0.6)
        rect(ix + 8, cy + rh / 2 - 3, 6, 6, on and COL.green or COL.red, 1)
        text(on and "Running" or "Off", ix + 20, vy(cy, rh), COL.text)
        text("F9", ix + iw - 6 - tw("F9"), vy(cy, rh), COL.faint)
        if clicked(ix, cy, iw, rh) then P.toggleBot() end
        cy = cy + rh + 6

        -- goal
        cy = title("Goal", ix, iw, cy) - 1
        local px = ix
        local rowY = cy
        for _, g in ipairs(GOAL_ORDER) do
            local label = GOAL_LABEL[g]
            local pw = tw(label) + 12
            if px + pw > ix + iw then px, rowY = ix, rowY + LH + 2 end
            local pw2, c = pill(label, px, rowY, B.S.goal == g, true, pw, "goal")
            if c then B.S.goal = g B.saveConfig() end
            px = px + pw2 + 3
        end
        cy = rowY + LH + 5

        -- character: mode pills next to the title, the picker below
        text("Character", ix, cy, COL.gold)
        local mx = ix + tw("Character") + 10
        local wsum = tw(CHAR_MODE.same) + tw(CHAR_MODE.cycle) + tw(CHAR_MODE.random) + 30 + 6
        if mx + wsum <= ix + iw then
            for _, m in ipairs({"same", "cycle", "random"}) do
                local pw, c = pill(CHAR_MODE[m], mx, cy - 1, B.S.character == m, true, tw(CHAR_MODE[m]) + 10, "char")
                if c then B.S.character = m B.saveConfig() end
                mx = mx + pw + 3
            end
        else
            -- narrow layout: one pill that cycles same -> cycle -> random
            local curMode = type(B.S.character) == "string" and B.S.character or "same"
            local order = {"same", "cycle", "random"}
            local pos = 1
            for i, m in ipairs(order) do if m == curMode then pos = i end end
            local pw, c = pill(CHAR_MODE[curMode], mx, cy - 1, type(B.S.character) == "string", true,
                math.min(ix + iw - mx, tw(CHAR_MODE[curMode]) + 10), "char")
            if c then B.S.character = order[pos % 3 + 1] B.saveConfig() end
            local _ = pw
        end
        cy = cy + LH + 2
        local isNum = type(B.S.character) == "number"
        local cur = isNum and B.S.character or (B.st.startChar or 0)
        local idx = 1
        for i, c in ipairs(B.CHARACTERS) do if c[1] == cur then idx = i break end end
        local lw, lc = pill("<", ix, cy, false, true, 22)
        local rx = ix + iw - 22
        local nw = rx - (ix + lw + 4) - 4
        local nameLabel = fit(charName(B.CHARACTERS[idx][1]), nw - 6)
        local cw, nc = pill(nameLabel, ix + lw + 4, cy, isNum, true, nw, "char")
        local rw, rc = pill(">", rx, cy, false, true, 22)
        local _ = cw + rw
        if lc then idx = (idx - 2) % #B.CHARACTERS + 1 end
        if rc then idx = idx % #B.CHARACTERS + 1 end
        if lc or rc or nc then
            B.S.character = B.CHARACTERS[idx][1]
            B.saveConfig()
        end
        cy = cy + LH + 3

        -- behaviour
        cy = title("Behavior", ix, iw, cy) - 1
        for _, t in ipairs(TOGGLES) do
            local rowH = LH + 1
            local hovRow = hot(ix, cy, iw, rowH)
            if hovRow then
                rect(ix, cy, iw, rowH, COL.panel2, 1)
                if HINT[t[2]] then V.hint = HINT[t[2]] end
            end
            local val = t[3]()
            text(fit(t[1], iw - 34), ix + 2, cy, val and COL.text or COL.dim)
            switch(val, ix + iw - 20, cy)
            if clicked(ix, cy, iw, rowH) then
                t[4]()
                B.saveConfig()
            end
            cy = cy + rowH
        end
    end

    -- ------------------------------------------------------------ right panel

    local TILE = 16

    local function tileGrid(list, w, maxRows)
        local cols = math.max(1, math.floor((w + 2) / (TILE + 2)))
        local rows = math.max(1, math.min(maxRows, math.ceil(#list / cols)))
        return cols, rows
    end

    local function tilePos(i, cols, x, y)
        local col, row = (i - 1) % cols, (i - 1) // cols
        return x + col * (TILE + 2), y + row * (TILE + 2)
    end

    -- Draw one list of tiles; returns the area height. kind = "pri" or "exc".
    local function drawTiles(kind, x, y, w, maxRows, layout)
        local list = B.S[kind]
        local cols, rows = tileGrid(list, w, maxRows)
        local h = rows * (TILE + 2)
        layout[kind] = {x = x, y = y, w = w, h = h, cols = cols}
        if #list == 0 then
            local msg = kind == "pri" and "empty - picks by quality, use + below" or "empty - use - below"
            text(fit(msg, w), x, y + (TILE - LH) / 2, COL.faint)
            return h
        end
        local capacity = cols * rows
        for i, id in ipairs(list) do
            if i > capacity then break end
            local tx, ty = tilePos(i, cols, x, y)
            if i == capacity and #list > capacity then
                rect(tx, ty, TILE, TILE, COL.panel2, 1)
                text("+" .. (#list - capacity + 1), tx + 2, ty + (TILE - LH) / 2, COL.dim)
                break
            end
            local dragging = V.drag and V.drag.kind == kind and V.drag.idx == i and V.drag.moved
            local hov = hot(tx, ty, TILE, TILE)
            rect(tx, ty, TILE, TILE, hov and COL.panel3 or COL.panel2, 1)
            border(tx, ty, TILE, TILE, kind == "pri" and COL.line or {0.5, 0.2, 0.18}, 0.9)
            if not dragging then
                icon(id, tx + 1, ty + 1, TILE - 2, kind == "exc" and 0.45 or 1)
            end
            if kind == "pri" then
                local num = tostring(i)
                rect(tx, ty, tw(num, 0.8) + 3, LH * 0.8 + 1, COL.black, 0.75)
                text(num, tx + 1.5, ty + 0.5, COL.gold, 1, 0.8)
            else
                rect(tx + 2, ty + TILE / 2 - 0.5, TILE - 4, 1, COL.red, 0.9)
            end
            if hov then
                V.hoverName = {s = "#" .. id .. " " .. itemName(id), x = tx, y = ty + TILE + 1}
                -- remove: the corner x or right click
                local xs = 7
                local xx, xy = tx + TILE - xs, ty
                rect(xx, xy, xs, xs, COL.red, 1)
                text("x", xx + 1, xy - 1.5, COL.white, 1, 0.7)
                if clicked(xx, xy, xs, xs) or rclicked(tx, ty, TILE, TILE) then
                    PR.remove(kind, id)
                    toast("Removed: " .. itemName(id), COL.dim)
                    return h
                end
                if M.pressed and not M.used then
                    M.used = true
                    V.drag = {kind = kind, idx = i, id = id, sx = M.x, sy = M.y, moved = false}
                end
            end
        end
        return h
    end

    local function tileIndexAt(area, n)
        if not area or not inside(area.x, area.y, area.w, area.h) then return nil end
        local col = math.floor((M.x - area.x) / (TILE + 2))
        local row = math.floor((M.y - area.y) / (TILE + 2))
        if col >= area.cols then col = area.cols - 1 end
        return math.min(n + 1, row * area.cols + col + 1)
    end

    local function finishDrag(layout)
        local d = V.drag
        if not d then return end
        if M.down then
            if math.abs(M.x - d.sx) + math.abs(M.y - d.sy) > 3 then d.moved = true end
            return
        end
        V.drag = nil
        if not d.moved then return end
        local toPri = tileIndexAt(layout.pri, #B.S.pri)
        local toExc = tileIndexAt(layout.exc, #B.S.exc)
        if d.kind == "pri" and toPri then
            PR.movePri(d.idx, math.min(toPri, #B.S.pri))
        elseif d.kind == "pri" and toExc then
            PR.toggleExc(d.id)
            toast("Excluded: " .. itemName(d.id), COL.red)
        elseif d.kind == "exc" and toPri then
            PR.togglePri(d.id)
            PR.movePri(#B.S.pri, toPri)
            toast("Priority: " .. itemName(d.id))
        end
    end

    local FILTERS = {{"all", "All"}, {"q4", "Q4"}, {"q3", "Q3"}, {"pri", "Priority"}, {"exc", "Excluded"}}

    local function refreshShown()
        local S = B.S
        local sig = V.query .. "|" .. V.filter .. "|" .. table.concat(S.pri, ",") .. "|" .. table.concat(S.exc, ",") .. "|" .. #P.items
        if sig == V.sig then return end
        V.sig = sig
        local q = B.lower(V.query):gsub("^%s+", ""):gsub("%s+$", ""):gsub("^#", "")
        local pool = {}
        if V.filter == "pri" then
            for _, id in ipairs(S.pri) do if P.byId[id] then pool[#pool + 1] = P.byId[id] end end
        elseif V.filter == "exc" then
            for _, id in ipairs(S.exc) do if P.byId[id] then pool[#pool + 1] = P.byId[id] end end
        else
            for _, it in ipairs(P.items) do
                if V.filter == "all" or (V.filter == "q4" and it.q == 4) or (V.filter == "q3" and it.q == 3) then
                    pool[#pool + 1] = it
                end
            end
        end
        local out = {}
        if q == "" then
            out = pool
        else
            local exact, starts, names = {}, {}, {}
            local num = q:match("^%d+$")
            for _, it in ipairs(pool) do
                local ids = tostring(it.id)
                if num and ids == q then exact[#exact + 1] = it
                elseif num and ids:sub(1, #q) == q then starts[#starts + 1] = it
                elseif it.low:find(q, 1, true) then names[#names + 1] = it end
            end
            for _, t in ipairs({exact, starts, names}) do
                for _, it in ipairs(t) do out[#out + 1] = it end
            end
        end
        V.shown = out
        V.cursor = math.max(1, math.min(V.cursor, #out))
        if q ~= V.lastQ then V.cursor, V.scroll, V.lastQ = 1, 0, q end
    end

    local function drawCatalog(x, y, w, h, layout)
        refreshShown()
        local shown = V.shown
        local bh = LH + 3
        local sw = w - 34
        rect(x, y, sw, bh, COL.black, 0.7)
        border(x, y, sw, bh, (V.form == nil) and COL.gold or COL.line, 0.8)
        local caret = (V.form == nil and (B.st.renderTick // 20) % 2 == 0) and "_" or ""
        if V.query == "" then
            text("id or name" .. caret, x + 5, vy(y, bh), COL.faint)
        else
            local s = V.query
            while #s > 0 and tw(s .. "_") > sw - 22 do s = utf8drop(s) end
            text(s .. caret, x + 5, vy(y, bh), COL.text)
            local cx = x + sw - 11
            if hot(cx, y + 2, 9, bh - 4) then rect(cx, y + 2, 9, bh - 4, COL.panel3, 1) end
            text("x", cx + 2, vy(y, bh), COL.dim)
            if clicked(cx, y + 2, 9, bh - 4) then V.query = "" end
        end
        local lc2, lc = pill(V.ru and "RU" or "EN", x + sw + 4, y, false, true, 30)
        local _ = lc2
        if lc then V.ru = not V.ru end
        y = y + bh + 3
        local fx = x
        for _, f in ipairs(FILTERS) do
            local pw, c = pill(f[2], fx, y, V.filter == f[1], true, tw(f[2]) + 9)
            if c then V.filter, V.cursor, V.scroll = f[1], 1, 0 end
            fx = fx + pw + 3
        end
        y = y + LH + 6
        local rowH = LH + 3
        local listH = h - (bh + 3) - (LH + 6)
        if listH < rowH then return end
        local rows = math.max(1, math.floor(listH / rowH))
        local listW = w - 5
        rect(x, y, listW, listH, COL.black, 0.3)
        local wheel = wheelDelta()
        if wheel ~= 0 and hot(x, y, w, listH) then
            V.scroll = V.scroll - math.floor(wheel)
        end
        if V.cursor > V.scroll + rows then V.scroll = V.cursor - rows end
        if V.cursor <= V.scroll then V.scroll = V.cursor - 1 end
        V.scroll = math.max(0, math.min(V.scroll, math.max(0, #shown - rows)))
        V.rows = rows
        local S = B.S
        local btn = LH + 1
        for r = 1, rows do
            local i = V.scroll + r
            local it = shown[i]
            if not it then break end
            local ry = y + (r - 1) * rowH
            local hov = hot(x, ry, listW, rowH)
            if i == V.cursor then rect(x, ry, listW, rowH, COL.sel, 1)
            elseif hov then rect(x, ry, listW, rowH, COL.panel2, 1) end
            local priRank = PR.indexOf(S.pri, it.id)
            local excd = PR.indexOf(S.exc, it.id)
            icon(it.id, x + 3, ry + (rowH - 14) / 2, 14, excd and 0.45 or 1)
            local idw = tw("000") + 4
            local ids = tostring(it.id)
            text(ids, x + 21 + idw - tw(ids), ry + (rowH - LH) / 2, COL.faint)
            local nx = x + 27 + idw
            local right = x + listW - 2 * (btn + 3) - 18 - 6
            local col = it.breaks and COL.faint or (excd and {0.78, 0.45, 0.4} or (priRank and COL.green or COL.text))
            local nameStr = readableKey(it.name) .. (it.breaks and "  (bot skips)" or "")
            text(fit(nameStr, right - nx - 4), nx, ry + (rowH - LH) / 2, col)
            for k = 1, 4 do
                rect(right + (k - 1) * 4, ry + rowH / 2 - 1.5, 3, 3, k <= it.q and COL.gold or COL.panel3, 1)
            end
            local bx = x + listW - 2 * (btn + 3)
            local by = ry + (rowH - btn) / 2
            local hp = hot(bx, by, btn, btn)
            rect(bx, by, btn, btn, priRank and {0.25, 0.6, 0.25} or (hp and COL.panel3 or COL.panel2), 1)
            border(bx, by, btn, btn, COL.green, hp and 1 or 0.6)
            text("+", bx + btn / 2 - tw("+") / 2, vy(by, btn), COL.text)
            if clicked(bx, by, btn, btn) then
                V.cursor = i
                local added = PR.togglePri(it.id)
                toast((added and "Priority: " or "Removed from priority: ") .. readableKey(it.name), added and COL.green or COL.dim)
            end
            local ex = bx + btn + 3
            local he = hot(ex, by, btn, btn)
            rect(ex, by, btn, btn, excd and {0.6, 0.2, 0.17} or (he and COL.panel3 or COL.panel2), 1)
            border(ex, by, btn, btn, COL.red, he and 1 or 0.6)
            text("-", ex + btn / 2 - tw("-") / 2, vy(by, btn), COL.text)
            if clicked(ex, by, btn, btn) then
                V.cursor = i
                local added = PR.toggleExc(it.id)
                toast((added and "Excluded: " or "Removed from exclusion: ") .. readableKey(it.name), added and COL.red or COL.dim)
            end
            if clicked(x, ry, listW, rowH) then V.cursor = i end
        end
        if #shown == 0 then
            text("No matches", x + 6, y + 4, COL.faint)
        end
        local sx = x + w - 4
        rect(sx, y, 3, listH, COL.panel2, 1)
        if #shown > rows then
            local th = math.max(10, listH * rows / #shown)
            local maxScroll = #shown - rows
            local ty = y + (listH - th) * V.scroll / maxScroll
            if M.pressed and not M.used and hot(sx - 3, y, 8, listH) then
                M.used = true
                V.sbDrag = true
            end
            if V.sbDrag then
                if M.down then
                    local f = (M.y - y - th / 2) / math.max(1, listH - th)
                    V.scroll = math.floor(math.max(0, math.min(1, f)) * maxScroll + 0.5)
                    V.cursor = math.max(V.scroll + 1, math.min(V.cursor, V.scroll + rows))
                else
                    V.sbDrag = false
                end
            end
            rect(sx, ty, 3, th, V.sbDrag and COL.gold or COL.line, 1)
        end
    end

    local function drawRight(x, y, w, h, layout)
        rect(x, y, w, h, COL.panel, 0.92)
        border(x, y, w, h, COL.line, 0.7)
        local ix, iw = x + 8, w - 16
        local cy = y + 6
        local half = math.floor((iw - 8) / 2)

        -- priority and exclusion share one row to leave room for the catalog
        text("Priority", ix, cy, COL.green)
        local c1 = tostring(#B.S.pri)
        text(c1, ix + half - tw(c1), cy, COL.dim)
        text("Excluded", ix + half + 8, cy, COL.red)
        local c2 = tostring(#B.S.exc)
        text(c2, ix + iw - tw(c2), cy, COL.dim)
        setHint("pri", ix, cy, half, LH)
        setHint("exc", ix + half + 8, cy, half, LH)
        cy = cy + LH + 2
        local h1 = drawTiles("pri", ix, cy, half, 1, layout)
        local h2 = drawTiles("exc", ix + half + 8, cy, half, 1, layout)
        cy = cy + math.max(h1, h2) + 5

        text("Catalog", ix, cy, COL.gold)
        local cnt = tostring(#V.shown) .. " items"
        text(cnt, ix + iw - tw(cnt), cy, COL.dim)
        setHint("cat", ix, cy, iw, LH)
        cy = cy + LH + 2
        drawCatalog(ix, cy, iw, y + h - cy - 6, layout)
    end

    -- ------------------------------------------------------------ title / footer

    local TOP = 3
    local HDR = 18

    local function drawHeader(layout)
        local st = B.st
        local x, y, w, h = 4, TOP, W - 8, HDR
        rect(x, y, w, h, COL.panel, 0.95)
        border(x, y, w, h, COL.line, 0.7)
        local cy = vy(y, h)
        local cx = x + 8
        text("PP Bot", cx, cy, COL.gold)
        cx = cx + tw("PP Bot") + 10

        -- right side: close hint, presets menu, preset name
        local closeW = tw("F8 Close")
        local moreW = 22
        local presetW = math.min(170, math.max(90, w * 0.34))
        local closeX = x + w - 8 - closeW
        text("F8 Close", closeX, cy, COL.faint)
        local moreX = closeX - 8 - moreW
        local presetX = moreX - 6 - presetW
        layout.ddX, layout.ddY = presetX, y + h + 2
        layout.moreX, layout.moreY = moreX, y + h + 2

        -- state chip
        local on = st.enabled
        local state = on and (st.paused and "Paused" or (MODE_EN[st.mode] or "Running")) or "Off"
        local det = on and not st.paused and detailText(st.detail) or ""
        local label = state
        if det ~= "" then label = label .. " | " .. det end
        local maxw = presetX - 10 - cx - 16
        if maxw > 40 then
            local chipW = math.min(maxw, tw(label) + 18)
            label = fit(label, chipW - 18)
            rect(cx, y + 1, chipW, h - 2, on and {0.1, 0.22, 0.12} or {0.24, 0.1, 0.1}, 1)
            rect(cx + 6, y + h / 2 - 2, 4, 4, on and COL.green or COL.red, 1)
            text(label, cx + 14, cy, on and COL.green or COL.red)
        end

        -- preset selector
        local p = PR.active()
        local hov = hot(presetX, y + 1, presetW, h - 2)
        rect(presetX, y + 1, presetW, h - 2, hov and COL.panel3 or COL.panel2, 1)
        border(presetX, y + 1, presetW, h - 2, (V.dd or hov) and COL.gold or COL.line, 0.9)
        local star = PR.isStartup(p) and " *" or ""
        local tagW = p.lock and (tw("built-in") + 6) or 0
        local nameX = presetX + 7
        if PR.dirty() then
            rect(presetX + 3, y + h / 2 - 2, 4, 4, COL.orange, 1)
            nameX = nameX + 6
        end
        text(fit(presetLabel(p.name) .. star, presetW - (nameX - presetX) - tagW - 12), nameX, cy, COL.gold)
        if p.lock then text("built-in", presetX + presetW - 6 - tw("built-in"), cy, COL.faint) end
        if hov then V.hint = HINT.preset end
        if clicked(presetX, y + 1, presetW, h - 2) then V.dd, V.more = not V.dd, false end

        local _, cm = button("...", moreX, y + 1, nil, true, moreW)
        if cm then V.more, V.dd = not V.more, false end
    end

    local function drawStrip()
        if V.msg ~= "" and B.st.renderTick < V.msgUntil then
            local a = math.min(1, (V.msgUntil - B.st.renderTick) / 30)
            text(fit(V.msg, W - 24), 8, TOP + HDR + 3, V.msgCol, a)
        elseif V.hint and V.hint ~= "" then
            text(fit(V.hint, W - 24), 8, TOP + HDR + 3, COL.dim, 0.9)
        end
    end

    local function drawFooter(y)
        rect(4, y, W - 8, 18, COL.panel, 0.95)
        border(4, y, W - 8, 18, COL.line, 0.7)
        local cy = vy(y, 18)
        local stage, eff = 0, 0
        if B.player() then stage, eff = B.stageInfo() end
        local s = B.S.stats
        local hint = "F8 Close | F7 Preset | F9 Bot"
        text(hint, W - 10 - tw(hint), cy, COL.faint)
        local stats = string.format("Floor %d | Run %d | Win %d | Lose %d", eff or stage,
            s.runs or 0, s.wins or 0, s.deaths or 0)
        text(fit(stats, W - 28 - tw(hint)), 10, cy, COL.dim)
    end

    -- ------------------------------------------------------------ keys

    function P.toggleBot()
        B.st.enabled = not B.st.enabled
        B.clearInput()
        B.taps = {}
        B.say(B.st.enabled and "Bot on" or "Bot off (F9 to turn on)", 180)
    end

    local function nextPreset()
        if PR.dirty() and B.st.renderTick > V.f7armed then
            V.f7armed = B.st.renderTick + 180
            toast("Unsaved changes: press F7 again to switch", COL.orange)
            B.say("Unsaved changes: press F7 again to discard", 180)
            return
        end
        V.f7armed = 0
        local p = PR.next()
        toast("Loaded: " .. presetLabel(p.name))
        B.say("Preset: " .. presetLabel(p.name), 150)
    end

    local function catalogKeys()
        local shown, n = V.shown, #V.shown
        local rows = V.rows or 5
        for _, k in ipairs({Keyboard.KEY_UP, Keyboard.KEY_DOWN, Keyboard.KEY_PAGE_UP, Keyboard.KEY_PAGE_DOWN,
            Keyboard.KEY_HOME, Keyboard.KEY_END}) do edge(k) end
        if repeating(Keyboard.KEY_UP) then V.cursor = V.cursor - 1 end
        if repeating(Keyboard.KEY_DOWN) then V.cursor = V.cursor + 1 end
        if repeating(Keyboard.KEY_PAGE_UP) then V.cursor = V.cursor - rows end
        if repeating(Keyboard.KEY_PAGE_DOWN) then V.cursor = V.cursor + rows end
        if held[Keyboard.KEY_HOME] == 1 then V.cursor = 1 end
        if held[Keyboard.KEY_END] == 1 then V.cursor = n end
        V.cursor = math.max(1, math.min(V.cursor, math.max(1, n)))
        local enter = edge(Keyboard.KEY_ENTER)
        enter = edge(Keyboard.KEY_KP_ENTER) or enter
        if enter and shown[V.cursor] then
            local it = shown[V.cursor]
            if shift() then
                local added = PR.toggleExc(it.id)
                toast((added and "Excluded: " or "Removed from exclusion: ") .. readableKey(it.name), added and COL.red or COL.dim)
            else
                local added = PR.togglePri(it.id)
                toast((added and "Priority: " or "Removed from priority: ") .. readableKey(it.name), added and COL.green or COL.dim)
            end
        end
    end

    function P.handleKeys()
        loadFont()
        if edge(Keyboard.KEY_F8) then
            P.open = not P.open
            V.dd, V.more, V.drag = false, false, nil
        end
        if edge(Keyboard.KEY_F9) then P.toggleBot() end
        if edge(Keyboard.KEY_F7) then nextPreset() end
        if not P.open then return end
        -- Esc closes the topmost thing: the form, then a popup, then the menu itself.
        if edge(Keyboard.KEY_ESCAPE) then
            if V.form then V.form = nil
            elseif V.dd then V.dd = false
            elseif V.more then V.more = false
            else P.open = false end
            return
        end
        if edge(Keyboard.KEY_TAB) then V.ru = not V.ru end
        local chars = typed()
        edge(Keyboard.KEY_BACKSPACE)
        local back = repeating(Keyboard.KEY_BACKSPACE)
        local del = edge(Keyboard.KEY_DELETE)
        local f = V.form
        if f and f.kind == "name" then
            if back then f.value = B.utf8pop(f.value) end
            if del then f.value = "" end
            if chars ~= "" and #f.value < 48 then f.value = f.value .. chars f.err = nil end
            local enter = edge(Keyboard.KEY_ENTER)
            enter = edge(Keyboard.KEY_KP_ENTER) or enter
            if enter then submitName() end
            return
        end
        if back then V.query = B.utf8pop(V.query) end
        if del then V.query = "" end
        if chars ~= "" and #V.query < 40 then V.query = V.query .. chars end
        catalogKeys()
    end

    -- main.lua asks this for every input action while the bot does not own it.
    local BLOCK = {}
    for a = 0, 11 do BLOCK[a] = true end
    for _, a in ipairs({13, 16, 17, 18, 19, 32}) do BLOCK[a] = true end  -- map, fullscreen, mute, restart, join, console
    function P.blocks(action)
        return P.open and BLOCK[action] or false
    end

    -- ------------------------------------------------------------ draw

    local function statusLine()
        local st = B.st
        local state = st.enabled and (st.paused and "Paused" or (MODE_EN[st.mode] or st.mode)) or "Off"
        -- The menu now uses the native font size; the status bar keeps its own bigger scale.
        text(fit("PP | " .. state .. " " .. detailText(st.detail) .. "   F8 Menu", (W - 70) / 1.45),
            60, H - 42, {0.8, 1, 0.8}, 1, 1.45)
        if st.message ~= "" and st.renderTick < st.messageUntil then
            text(fit(st.message, (W - 70) / 1.45), 60, H - 22, {0.7, 0.85, 1}, 1, 1.45)
        end
    end

    -- The game draws its HUD (hearts, pickups, minimap) after MC_POST_RENDER, on top of the
    -- menu, so it is hidden while the menu is open.
    local hudHidden = nil  -- unknown after a mod reload, so the first frame always sets it
    local function setHud(visible)
        if hudHidden == not visible then return end
        hudHidden = not visible
        B.try(function() B.game:GetHUD():SetVisible(visible) end)
    end

    function P.draw()
        W = B.try(function() return Isaac.GetScreenWidth() end) or 480
        H = B.try(function() return Isaac.GetScreenHeight() end) or 270
        setHud(not P.open)
        if not P.open then
            statusLine()
            return
        end
        readMouse()
        refreshShown()
        V.hint, V.hoverName = nil, nil
        local layout = {}
        -- layout positions needed for overlay hit tests come from the previous frame
        local L = P.lastLayout or {}
        local overlay = nil
        if V.dd and L.ddX then overlay = {ddRect(L)}
        elseif V.more and L.moreX then overlay = {moreRect(L)} end
        local overlayPressed = false
        hoverOK = true
        if overlay then
            if inside(overlay[1], overlay[2], overlay[3], overlay[4]) then
                hoverOK = false
                overlayPressed, M.pressed = M.pressed, false
            elseif M.pressed then
                -- a click outside closes the list and does nothing else
                V.dd, V.more, M.pressed = false, false, false
                M.used = true
            end
        end

        drawHeader(layout)
        drawStrip()
        local stripY = TOP + HDR + 2
        local bodyY
        if V.form then
            bodyY = stripY + drawForm(stripY) + 3
        else
            bodyY = stripY + LH + 4
        end
        local footerY = H - 21
        local bodyH = math.max(60, footerY - 3 - bodyY)
        local lw = math.floor(math.max(178, math.min(206, W * 0.4)))
        drawLeft(4, bodyY, lw, bodyH)
        drawRight(4 + lw + 6, bodyY, W - lw - 14, bodyH, layout)
        drawFooter(footerY)
        finishDrag(layout)
        P.lastLayout = layout

        hoverOK = true
        if overlay then M.pressed = overlayPressed end
        if V.dd and layout.ddX then drawDropdown(layout) end
        if V.more and layout.moreX then drawMore(layout) end

        -- floating bits: dragged tile, item name, cursor
        if V.drag and V.drag.moved then
            rect(M.x - TILE / 2, M.y - TILE / 2, TILE, TILE, COL.panel3, 0.9)
            icon(V.drag.id, M.x - TILE / 2 + 1, M.y - TILE / 2 + 1, TILE - 2)
        elseif V.hoverName then
            local s = V.hoverName.s
            local w = tw(s) + 10
            local hx = math.max(4, math.min(V.hoverName.x, W - w - 4))
            rect(hx, V.hoverName.y, w, LH + 4, COL.panel, 0.97)
            border(hx, V.hoverName.y, w, LH + 4, COL.line, 1)
            text(s, hx + 5, vy(V.hoverName.y, LH + 4), COL.text)
        end
        -- cursor
        rect(M.x - 3, M.y, 7, 1, COL.white, 0.9)
        rect(M.x, M.y - 3, 1, 7, COL.white, 0.9)
    end

    -- For tests through the bridge ("bot menu search <text>").
    function P.search(q)
        V.query, V.filter = q or "", "all"
    end
end