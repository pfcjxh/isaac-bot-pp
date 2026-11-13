-- Deciding what to pick up, buy or open. Each pickup gets a value; the brain walks to the
-- best value per distance. Values come from ItemConfig quality plus rules for what the
-- character can actually use, what it costs, and what would break the bot.

return function(B)
    local game = B.game
    local I = {}
    B.items = I

    local PV = PickupVariant

    -- Items that break the bot's movement/aiming model or kill it.
    I.BOT_BREAKING = {}
    for _, name in ipairs({"THE_WIZ", "TINY_PLANET", "ANTI_GRAVITY", "MARKED", "EYE_OF_THE_OCCULT",
        "ISAACS_HEART", "CURSED_EYE", "MISSING_NO", "TMTRAINER", "KAMIKAZE", "PLAN_C", "DAMOCLES",
        "BAG_OF_CRAFTING", "CLICKER", "GENESIS", "MY_REFLECTION"}) do
        local id = CollectibleType["COLLECTIBLE_" .. name]
        if id then I.BOT_BREAKING[id] = true end
    end

    -- Cards worth carrying: effects the bot knows how to use (see the card logic in brain).
    -- Anything else (Tower, Suicide King, Fool, unknown cards) is left on the floor.
    I.CARD_KEEP, I.CARD_RANK = {}, {}
    local cardRank = 0
    -- Priority order: combat cards first (they are what the bot will use in a fight), then
    -- healing, then the floor-utility cards.
    for _, name in ipairs({"TAROT_DEATH", "TAROT_CHARIOT", "TAROT_HIGH_PRIESTESS",
        "TAROT_EMPRESS", "TAROT_MAGICIAN", "TAROT_STRENGTH", "TAROT_SUN", "TAROT_HIEROPHANT",
        "TAROT_LOVERS", "TAROT_WORLD", "TAROT_MOON", "TAROT_STAR",
        "TAROT_JUDGEMENT", "TAROT_WHEEL_OF_FORTUNE"}) do
        cardRank = cardRank + 1
        local id = B.try(function() return Card[name] end)
        if id then I.CARD_KEEP[id] = true I.CARD_RANK[id] = cardRank end
    end

    local QUALITY_VALUE = {[0] = 2, [1] = 4, [2] = 7, [3] = 11, [4] = 16}

    function I.config(id)
        return B.try(function() return Isaac.GetItemConfig():GetCollectible(id) end)
    end

    local function blockedByPair(id, p)
        for _, pair in ipairs(B.S.forbiddenPairs) do
            local a, b = tonumber(pair.a), tonumber(pair.b)
            if a and b then
                if b == id and B.try(function() return p:HasCollectible(a) end) then return true end
                if a == id and B.try(function() return p:HasCollectible(b) end) then return true end
            end
        end
        return false
    end

    local function find(list, id)
        for i, v in ipairs(list) do if v == id then return i end end
        return nil
    end

    -- Place in the menu's priority list (1 = most wanted) or nil.
    function I.priority(id)
        return find(B.S.pri, id)
    end

    -- Excluded and bot-breaking items are never taken, even from the priority list.
    function I.collectibleAllowed(id, p)
        if blockedByPair(id, p) then return false end
        if find(B.S.exc, id) then return false end
        if I.BOT_BREAKING[id] then return false end
        return true
    end

    -- Priority items outrank every quality value (16) and the key items (20), in list order.
    local function priorityValue(rank)
        return 40 - math.min(rank, 30) * 0.5
    end

    -- Value of a collectible for this player, or nil if it must not be taken.
    function I.collectibleValue(id, p)
        if id <= 0 or not I.collectibleAllowed(id, p) then return nil end
        local cfg = I.config(id)
        if not cfg then return nil end
        local q = B.try(function() return cfg.Quality end) or 1
        local rank = I.priority(id)
        if rank then
            local isActive = (B.try(function() return cfg.Type end) == ItemType.ITEM_ACTIVE)
            local current = isActive and B.try(function() return p:GetActiveItem(0) end) or 0
            local curRank = current > 0 and I.priority(current)
            if curRank and curRank <= rank then return nil end  -- already hold a better one
            return priorityValue(rank)
        end
        local v = QUALITY_VALUE[q] or 5
        -- The goal decides which key item matters after Mom.
        local goal = B.S.goal
        if id == CollectibleType.COLLECTIBLE_POLAROID then
            v = (goal == "satan" or goal == "lamb") and 1 or 20
        elseif id == CollectibleType.COLLECTIBLE_NEGATIVE then
            v = (goal == "satan" or goal == "lamb") and 20 or 1
        end
        local isActive = (B.try(function() return cfg.Type end) == ItemType.ITEM_ACTIVE)
        if isActive then
            local current = B.try(function() return p:GetActiveItem(0) end) or 0
            if current > 0 then
                -- Swapping drops the old active on the floor; only trade up.
                local old = I.config(current)
                local oq = old and B.try(function() return old.Quality end) or 0
                -- An active the bot never presses is worth replacing even by an equal item.
                local useless = B.combat and B.combat.NO_USE and B.combat.NO_USE[current]
                if not useless and (q <= oq or I.priority(current)) then return nil end
                v = v - 3
            end
        end
        return v
    end

    -- Health spent on a devil deal must leave a buffer; price codes from PickupPrice.
    local function canPayHearts(p, price)
        local red = (B.try(function() return p:GetMaxHearts() end) or 0) // 2
        local soul = (B.try(function() return p:GetSoulHearts() end) or 0) // 2
        local needRed, needSoul = 0, 0
        if price == PickupPrice.PRICE_ONE_HEART then needRed = 1
        elseif price == PickupPrice.PRICE_TWO_HEARTS then needRed = 2
        elseif price == PickupPrice.PRICE_THREE_SOULHEARTS then needSoul = 3
        elseif price == PickupPrice.PRICE_ONE_HEART_AND_TWO_SOULHEARTS then needRed, needSoul = 1, 2
        elseif price == PickupPrice.PRICE_SOUL then return false
        elseif price == PickupPrice.PRICE_ONE_SOUL_HEART then needSoul = 1
        elseif price == PickupPrice.PRICE_TWO_SOUL_HEARTS then needSoul = 2
        elseif price == PickupPrice.PRICE_ONE_HEART_AND_ONE_SOUL_HEART then needRed, needSoul = 1, 1
        elseif price == PickupPrice.PRICE_SPIKES then return false
        else return false end
        if red < needRed or soul < needSoul then return false end
        return (red - needRed) + (soul - needSoul) >= 2
    end

    local function heartWanted(p, sub)
        local function can(m)
            local r = B.try(function() return p[m](p) end)
            if r == nil then return true end
            return r
        end
        local HS = HeartSubType
        if sub == HS.HEART_FULL or sub == HS.HEART_HALF or sub == HS.HEART_DOUBLEPACK
            or sub == HS.HEART_SCARED then
            return can("CanPickRedHearts")
        elseif sub == HS.HEART_SOUL or sub == HS.HEART_HALF_SOUL or sub == HS.HEART_BLACK then
            return can("CanPickSoulHearts")
        elseif sub == HS.HEART_BLENDED then
            return can("CanPickRedHearts") or can("CanPickSoulHearts")
        elseif sub == HS.HEART_BONE then
            return can("CanPickBoneHearts")
        elseif sub == HS.HEART_GOLDEN then
            return can("CanPickGoldenHearts")
        elseif sub == HS.HEART_ROTTEN then
            return can("CanPickRottenHearts")
        end
        return true -- eternal and anything new
    end

    local function count(p, m)
        return B.try(function() return p[m](p) end) or 0
    end

    -- Value of any pickup entity (nil = ignore). Second result: needs a key/bomb to open.
    function I.value(e, p, ctx)
        local pickup = e:ToPickup()
        if not pickup then return nil end
        local v, sub = e.Variant, e.SubType
        local price = B.try(function() return pickup.Price end) or 0
        if B.try(function() return pickup.Touched end) and v == PV.PICKUP_COLLECTIBLE then
            return nil -- swapped-out actives and already handled pedestals
        end
        if B.try(function() return pickup.Wait end) and pickup.Wait > 0 and v ~= PV.PICKUP_COLLECTIBLE then
            -- Freshly dropped consumables bounce; still fine to walk to.
        end
        local coins = count(p, "GetNumCoins")
        local isKeeper = ctx.keeper

        -- Shop and devil prices.
        if price > 0 then
            if coins < price then return nil end
        elseif price < 0 and price ~= PickupPrice.PRICE_FREE then
            if not B.S.devil then return nil end
            if ctx.lost then
                -- The Lost pays nothing for devil deals.
            elseif not canPayHearts(p, price) then
                return nil
            end
        end

        local value
        if v == PV.PICKUP_COLLECTIBLE then
            if sub == 0 then return nil end
            value = I.collectibleValue(sub, p)
            if not value then return nil end
            local wanted = I.priority(sub) ~= nil  -- the menu's list skips the quality bar
            if price > 0 then
                -- Shop item: worth it from quality 2 up, or anything when rich.
                local q = B.try(function() return I.config(sub).Quality end) or 1
                -- Buy anything decent that is affordable; quality 0 only with money to burn.
                if q < 1 and coins < 60 and not wanted then return nil end
                value = value - price * 0.15
            elseif price < 0 and price ~= PickupPrice.PRICE_FREE and not ctx.lost then
                local q = B.try(function() return I.config(sub).Quality end) or 1
                -- A two-heart deal has to buy a top item; one heart still needs quality 3+.
                local dear = price == PickupPrice.PRICE_TWO_HEARTS
                    or price == PickupPrice.PRICE_THREE_SOULHEARTS
                    or price == PickupPrice.PRICE_ONE_HEART_AND_TWO_SOULHEARTS
                if q < (dear and 4 or 3) and not wanted then return nil end
                value = value - (dear and 7 or 4)
            end
        elseif v == PV.PICKUP_HEART then
            if isKeeper then return nil end
            if not heartWanted(p, sub) then return nil end
            value = (sub == HeartSubType.HEART_ETERNAL) and 5 or 3
            if ctx.hurt then value = value + 4 end
            -- From mid-run on a shop heart is worth a few coins even at full health.
            if price > 0 and not ctx.hurt and coins < 15 then return nil end
        elseif v == PV.PICKUP_COIN then
            if coins >= 99 then return nil end
            value = isKeeper and 4 or 2
            if price > 0 then return nil end
        elseif v == PV.PICKUP_KEY then
            if count(p, "GetNumKeys") >= 99 then return nil end
            value = 2.5
            if price > 0 and count(p, "GetNumKeys") > 1 then return nil end
        elseif v == PV.PICKUP_BOMB then
            if count(p, "GetNumBombs") >= 99 then return nil end
            value = 2.5
            if price > 0 and count(p, "GetNumBombs") > 1 then return nil end
        elseif v == PV.PICKUP_LIL_BATTERY then
            if not B.try(function() return p:NeedsCharge(0) end) then return nil end
            value = 3
            if price > 0 and coins < 15 then return nil end
        elseif v == PV.PICKUP_TAROTCARD then
            -- Carry only cards the bot will actually use, and only with the slot free.
            local skip = I.skipCard
            if skip and skip.id == sub and B.st.tick < skip.expire then return nil end
            local card = B.try(function() return p:GetCard(0) end) or 0
            if card ~= 0 or not I.CARD_KEEP[sub] then return nil end
            value = 2.0
        elseif v == PV.PICKUP_PILL then
            -- Pills are never used (the effect is hidden), so carrying one is pointless.
            return nil
        elseif v == PV.PICKUP_TRINKET then
            if (B.try(function() return p:GetTrinket(0) end) or 0) ~= 0 then return nil end
            value = 2
        elseif v == PV.PICKUP_GRAB_BAG then
            value = 2
        elseif v == PV.PICKUP_REDCHEST then
            -- Red chests can hold a devil item or a heart; open one with health to spare (they
            -- can also drop spiders or send the player to the devil room).
            if (B.try(function() return p:GetHearts() end) or 0)
                + (B.try(function() return p:GetSoulHearts() end) or 0) < 4 then return nil end
            value = 4
        elseif v == PV.PICKUP_CHEST or v == PV.PICKUP_WOODENCHEST then
            if sub == 0 then return nil end -- opened
            -- A golden chest is PICKUP_CHEST with the golden subtype: always worth a key.
            local gsub = B.try(function() return ChestSubType.CHEST_GOLDEN end)
            if gsub and sub == gsub then
                local keys = count(p, "GetNumKeys")
                local gk = B.try(function() return p:HasGoldenKey() end)
                if keys < 1 and not gk then return nil end
                value = 10
            else
                value = 3
            end
        elseif v == PV.PICKUP_LOCKEDCHEST or v == PV.PICKUP_ETERNALCHEST or v == PV.PICKUP_OLDCHEST
            or v == PV.PICKUP_MEGACHEST then
            if sub == 0 then return nil end
            local keys = count(p, "GetNumKeys")
            local golden = B.try(function() return p:HasGoldenKey() end)
            -- Keep keys for doors and golden chests: only open key chests with a surplus.
            if keys < 3 and not golden then return nil end
            value = 4
        elseif v == PV.PICKUP_BIGCHEST or v == PV.PICKUP_TROPHY then
            return nil -- run endings are chosen by the floor logic, never as loot
        else
            return nil -- spiked/mimic/red/haunted/stone chests, beds, unknown variants
        end
        return value
    end

    -- All wanted pickups with their value. Choice groups (OptionsPickupIndex) keep only the
    -- best member so the bot does not touch one and lose the better one.
    -- Slot machines, fortune tellers and shell games pay out loot for coins, so
    -- they are loot targets too. Blood donation / hell game cost hearts and the
    -- key master needs a key, so those are filtered out.
    local SLOT_MACHINE = 1
    local FORTUNE_TELLING = 3
    local SHELL_GAME = 4
    local KEY_MASTER = 6
    local SAFE_SLOTS = {
        [SLOT_MACHINE] = true,
        [FORTUNE_TELLING] = true,
        [SHELL_GAME] = true,
        [KEY_MASTER] = true,
    }

    function I.slotValue(e, p, ctx)
        local variant = e.Variant
        if not SAFE_SLOTS[variant] then return nil end

        if variant == KEY_MASTER then
            if count(p, "GetNumKeys") < 1 then return nil end
            return 2
        end

        -- Coins are worth more in the shop: only gamble what is clearly spare.
        if count(p, "GetNumCoins") < 12 then return nil end
        return 2
    end

    function I.scan(p, ctx)
        local list = B.try(function()
            return Isaac.FindByType(EntityType.ENTITY_PICKUP, -1, -1, false, false) end) or {}
        local out = {}
        local groups = {}
        for _, e in ipairs(list) do
            local key = "p" .. B.hash(e)
            if not B.isBlacklisted(key) then
                local value = I.value(e, p, ctx)
                if value then
                    local entry = {e = e, value = value, key = key}
                    local group = B.try(function() return e:ToPickup().OptionsPickupIndex end) or 0
                    if group ~= 0 and e.Variant == PV.PICKUP_COLLECTIBLE then
                        local cur = groups[group]
                        if not cur or cur.value < value then groups[group] = entry end
                    else
                        out[#out + 1] = entry
                    end
                end
            end
        end
        for _, entry in pairs(groups) do out[#out + 1] = entry end

        -- Beggars: pay coins until they hand over the item. Worth it when rich, and the small
        -- spike strip in front is accepted (the route may hurt).
        local beg = B.try(function() return EntityType.ENTITY_BEGGAR end)
        if beg then
            local begs = B.try(function()
                return Isaac.FindByType(beg, -1, -1, false, false) end) or {}
            for _, e in ipairs(begs) do
                local key = "g" .. B.hash(e)
                local paid = (B.st.beggar and B.st.beggar[key]) or 0
                if e.Variant == 0 and paid < 12 and not B.isBlacklisted(key)
                    and count(p, "GetNumCoins") >= 10 then
                    out[#out + 1] = {e = e, value = 6, key = key, beggar = true}
                end
            end
        end

        -- slot machines are not pickups: scan them separately
        local slots = B.try(function()
            return Isaac.FindByType(EntityType.ENTITY_SLOT, -1, -1, false, false) end) or {}
        for _, e in ipairs(slots) do
            local key = "s" .. B.hash(e)
            if not B.isBlacklisted(key) then
                local value = I.slotValue(e, p, ctx)
                if value then
                    out[#out + 1] = { e = e, value = value, key = key }
                end
            end
        end

        return out
    end

    -- Log what the player gained since the last check (works for every source of items).
    I.owned = {}
    function I.trackInventory(p)
        local cfg = B.try(function() return Isaac.GetItemConfig() end)
        local list = cfg and B.try(function() return cfg:GetCollectibles() end)
        local maxId = list and list.Size or 733
        for id = 1, maxId - 1 do
            local n = B.try(function() return p:GetCollectibleNum(id, true) end) or 0
            if n > (I.owned[id] or 0) then
                local c = I.config(id)
                B.event("item", {id = id, name = c and c.Name or "?", q = c and c.Quality or -1,
                    stage = game:GetLevel():GetStage()})
            end
            I.owned[id] = n
        end
    end
end
