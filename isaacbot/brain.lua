-- The decision loop. Every update: read the room, rebuild the grid when needed, flood path
-- costs from the player, pick one goal (fight, plate, loot, rock, door, exit), turn it into
-- a steering point, and let the dodge layer make the final move.

return function(B)
    local game = B.game
    local R = {}
    B.brain = R

    -- Loaded before this module (see MODULES in main.lua).
    local G, D, C, I, F = B.grid, B.danger, B.combat, B.items, B.floor

    R.prof = nil
    R.profAt = -1000
    R.goalKey = nil       -- what the bot is walking to (for stuck detection)
    R.goalSince = 0
    R.goalBest = math.huge
    R.wander = nil        -- {dx, dy, untilTick}
    R.bombPlan = nil
    R.fireTries = {}      -- [cell] = {n = plans made, retry = tick} for shooting out that fireplace
    R.devilDone = false
    R.lastBombTick = -1000
    R.idleClear = 0
    R.sweepTries = {}     -- [key] = failed attempts at a fireplace / poop / rock
    R.residueSince = nil  -- tick the reviving leftovers in this room were first attacked
    R.fireHp = {}         -- [key] = {hp, since}: fires that stop burning down are given up
    R.sweepTime = {}      -- [key] = tick a destructible was first shot at
    local stepAway        -- defined below; runBomb needs it to step out of its own blast

    local function stats(p)
        return {
            keeper = (function()
                local t = B.playerType(p)
                return t == PlayerType.PLAYER_KEEPER or t == PlayerType.PLAYER_KEEPER_B
            end)(),
            lost = (function()
                local t = B.playerType(p)
                return t == PlayerType.PLAYER_THELOST or t == PlayerType.PLAYER_THELOST_B
            end)(),
            hurt = ((B.try(function() return p:GetHearts() end) or 0)
                + (B.try(function() return p:GetSoulHearts() end) or 0)) <= 4,
        }
    end

    -- One-hit characters (or anything at half a heart with no soul hearts) dodge harder.
    local function dodgeWeight(p, ctx)
        if ctx.lost then return 3 end
        local hp = (B.try(function() return p:GetHearts() end) or 0)
            + (B.try(function() return p:GetSoulHearts() end) or 0)
            + (B.try(function() return p:GetBoneHearts() end) or 0) * 2
        if hp <= 2 then return 2 end
        if hp <= 4 then return 1.5 end
        return 1
    end

    -- ------------------------------------------------------------ room / floor events

    function R.onNewRoom()
        -- Do not turn around and walk straight back through the door we just used: that is the
        -- in-out-in-out loop. Forget the way back for ~2.5 s unless something really needs it.
        local back = R.lastDoor
        if back and B.st.tick - back.tick < 30 then
            local slot = (back.slot + 2) % 4
            B.blacklist("door" .. slot .. ":" .. B.st.room, 150)
            B.event("no_backtrack", {slot = slot, room = B.st.room})
        end
        R.goalKey, R.wander, R.bombPlan = nil, nil, nil
        R.idleClear, R.idleTicks = 0, 0
        G.builtAt = -1
        if C then C.target, C.targetHash = nil, nil end
        -- The held charge may or may not survive the transition: do not learn from the
        -- first release after it.
        if C then C.charge.noLearn = true end
        if C and C.forget then C.forget() end
        R.fireTries = {}
        R.sweepTries = {}
        R.fireHp = {}
        R.sweepTime = {}
        R.residueSince = nil
        R.waitCell, R.waitUntil = nil, 0
        R.lootKey, R.lootUntil = nil, 0
        G.forceSpikes = false
        R.lastPosTick = nil
        R.doorKey = nil
        R.secretPlan = nil
    end

    function R.onNewLevel()
        R.devilDone = false
        B.st.badRooms = {}
        B.st.bedHits = {}
        B.st.blacklist = {}
        F.build()
    end

    -- ------------------------------------------------------------ goal tracking

    -- Called with a key and the remaining path cost. If the cost does not improve for a
    -- while the goal is unreachable in practice: wander, then blacklist it.
    local function track(key, remaining)
        local tick = B.st.tick
        if key ~= R.goalKey then
            R.goalKey, R.goalSince, R.goalBest, R.stuckLevel = key, tick, remaining or math.huge, 0
            return false
        end
        if remaining and remaining < R.goalBest - 0.5 then
            R.goalBest = remaining
            R.goalSince = tick
            return false
        end
        local stale = tick - R.goalSince
        if stale > 75 and (R.stuckLevel or 0) == 0 then
            R.stuckLevel = 1
            local a = math.random() * math.pi * 2
            R.wander = {math.cos(a), math.sin(a), tick + 18}
            B.event("stuck", {goal = key, level = 1, x = B.st.px, y = B.st.py})
        elseif stale > 240 then
            -- An unreachable pickup is unreachable for the rest of the run: forgetting it for
            -- 15 s only makes the bot walk back to it and try again (room ping-pong).
            B.blacklist(key, (type(key) == "string" and key:sub(1, 1) == "p") and 1e9 or 900)
            B.event("stuck", {goal = key, level = 2, x = B.st.px, y = B.st.py})
            R.goalKey = nil
            return true
        end
        return false
    end

    -- ------------------------------------------------------------ movement helpers

    -- Steering target toward a world position via the flood. Returns tx, ty, remaining cost.
    -- safe: refuse a path over spikes (loot and reward plates are not worth a heart).
    local function routeTo(p, x, y, radius, safe)
        local cell = G.reachableNear(x, y, radius or 2)
        if not cell then return nil end
        local path = G.pathTo(cell)
        if not path then return nil end
        if safe and G.pathHurts(path) then return nil end
        local tx, ty = G.steer(p.Position.X, p.Position.Y, path, x, y)
        return tx, ty, G.dist[cell], cell
    end

    local function goToward(p, tx, ty)
        if not tx then return nil end
        local dx, dy = tx - p.Position.X, ty - p.Position.Y
        if dx * dx + dy * dy < 16 then return nil end
        return dx, dy
    end

    -- Hostile NPCs that C.enemies skips because they are untouchable right now: a boss in
    -- the air or underground (still lands on you), a closed Host, something spawning.
    local function hiddenThreats(ents)
        local out = {}
        for _, e in ipairs(ents) do
            if e.Type >= 10 and e.Type ~= EntityType.ENTITY_EFFECT
                and e.Type ~= EntityType.ENTITY_FIREPLACE then
                local ok = B.try(function()
                    return e:ToNPC() ~= nil and not e:IsDead()
                        and not e:HasEntityFlags(EntityFlag.FLAG_FRIENDLY)
                        and (e:IsBoss() or e.CollisionDamage > 0 or e:IsActiveEnemy(false))
                end)
                if ok then out[#out + 1] = e end
            end
        end
        return out
    end

    -- Reachable cell that keeps the most distance from every threat, minus a little for the
    -- walk. Returns a steering target.
    local function safestSpot(p, threats)
        local room = game:GetRoom()
        local best, bestScore
        for cell, cost in pairs(G.dist) do
            local pos = room:GetGridPosition(cell)
            local m = math.huge
            for _, e in ipairs(threats) do
                local d = B.dist(pos.X, pos.Y, e.Position.X + e.Velocity.X * 6,
                    e.Position.Y + e.Velocity.Y * 6)
                if d < m then m = d end
            end
            local s = math.min(m, 260) - cost * 0.15
            if not bestScore or s > bestScore then best, bestScore = pos, s end
        end
        if not best then return nil end
        return routeTo(p, best.X, best.Y, 1)
    end

    -- A far cell to walk to while a hidden enemy (a Host in its shell) refuses to open. The
    -- spot changes every ~1.5 s so the bot really crosses the room instead of hovering: a Host
    -- only pops out after Isaac has moved away, and a small step aside is not enough.
    R.waitCell, R.waitUntil = nil, 0
    local function waitSpot(p, threats)
        local room = game:GetRoom()
        if not R.waitCell or B.st.tick >= (R.waitUntil or 0) or not G.dist[R.waitCell] then
            local best, bestS
            for cell in pairs(G.dist) do
                if G.cost[cell] and G.cost[cell] < 50 then
                    local pos = room:GetGridPosition(cell)
                    local m = math.huge
                    for _, e in ipairs(threats) do
                        local d = B.dist(pos.X, pos.Y, e.Position.X, e.Position.Y)
                        if d < m then m = d end
                    end
                    -- far from the threat, and far from where the bot stands now
                    local s = -math.min(m, 400)
                        + B.dist(pos.X, pos.Y, p.Position.X, p.Position.Y) * 0.25
                    if not bestS or s > bestS then best, bestS = cell, s end
                end
            end
            R.waitCell, R.waitUntil = best, B.st.tick + 45
        end
        local cell = R.waitCell
        if not cell then return nil end
        local pos = room:GetGridPosition(cell)
        return routeTo(p, pos.X, pos.Y, 1)
    end

    -- ------------------------------------------------------------ breaking through

    -- When a wanted point cannot be reached, look for a path through lit fireplaces and
    -- poop (shot out, always possible) and rocks (bomb, if we have one and noRocks is not
    -- set), and plan to clear the first obstacle on it.
    local function planBomb(p, x, y, noRocks)
        local canBomb = not noRocks and B.S.useBombs
            and (B.try(function() return p:GetNumBombs() end) or 0) >= 1
            and B.st.tick - R.lastBombTick >= 150
        local room = game:GetRoom()
        local start = room:GetGridIndex(p.Position)
        local dist, prev = G.dist, G.prev
        local d2, p2 = G.flood(start, nil, canBomb, true, true)
        local goal = G.reachableNear(x, y, 2)
        local path = goal and G.pathTo(goal, p2)
        G.dist, G.prev = dist, prev
        if not path then return nil end
        for k, cell in ipairs(path) do
            if G.fire[cell] then
                -- Two tries per fireplace, then a 20 s break before two more: tries also
                -- run out on plans the loot goal replaced, and a bot knocked into a pocket
                -- behind the fire has no other way out (night 2026-10-16, Basement I).
                local t = R.fireTries[cell] or {n = 0, retry = 0}
                if t.n >= 2 then
                    if B.st.tick < t.retry then return nil end
                    t.n = 0
                end
                t.n = t.n + 1
                if t.n >= 2 then t.retry = B.st.tick + 600 end
                R.fireTries[cell] = t
                return {fire = cell, e = G.fire[cell]}
            elseif G.poop[cell] then
                return {poop = cell}
            elseif G.rock[cell] then
                local before = path[k - 1]
                if before and canBomb then
                    return {rock = cell, stand = before}
                end
                return nil
            end
        end
        return nil
    end

    -- Shoot out a fireplace in the way: stand at weapon range on its row or column, fire.
    local function runFire(p, plan)
        local e = plan.e
        if not G.fire[plan.fire] or not e or not e:Exists() or not G.fireLit(e) then
            B.event("fire_out", {cell = plan.fire})
            R.bombPlan = nil
            return nil
        end
        local prof = R.prof or C.profile(p)
        B.st.mode, B.st.detail = "fire", "cell " .. plan.fire
        C.fire(p, prof, e)
        local sx, sy = C.attackSpot(p, e, prof)
        if sx then
            -- In position: stand still (0, 0 keeps the loot/door goals from taking over).
            if B.dist(p.Position.X, p.Position.Y, sx, sy) < 10 then return 0, 0 end
            local tx, ty = routeTo(p, sx, sy, 1)
            if tx then return goToward(p, tx, ty) end
        end
        return 0, 0
    end

    -- Shoot out poop in the way. Tears fly straight, so stand on the poop's row or column
    -- with open floor between (a reachable cell in range), then fire at it until the grid
    -- rebuild no longer sees it.
    local function poopSpot(p, cell, prof)
        local room = game:GetRoom()
        local gx, gy = G.xy(cell)
        local reach = math.max(2, math.min(7, math.floor(prof.range / 40)))
        local best, bestS
        for _, dir in ipairs({{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) do
            for k = 1, reach do
                local nx, ny = gx + dir[1] * k, gy + dir[2] * k
                if nx < 0 or nx >= G.w or ny < 0 or ny >= G.h then break end
                local j = nx + ny * G.w
                if not G.cost[j] then break end  -- a rock or pit stops the shot
                local d = G.dist[j]
                if d and G.cost[j] < 50 then
                    -- Right next to it is fine for melee, a little cramped for tears.
                    local s = d
                    if k == 1 and prof.kind ~= "melee" then s = s + 6 end
                    if not bestS or s < bestS then best, bestS = j, s end
                end
            end
        end
        if not best then return nil end
        local pos = room:GetGridPosition(best)
        return pos.X, pos.Y
    end

    local function runPoop(p, plan)
        if not G.poop[plan.poop] then
            B.event("poop_out", {cell = plan.poop})
            R.bombPlan = nil
            return nil
        end
        local prof = R.prof or C.profile(p)
        B.st.mode, B.st.detail = "poop", "cell " .. plan.poop
        local pos = game:GetRoom():GetGridPosition(plan.poop)
        local sx, sy = poopSpot(p, plan.poop, prof)
        if not sx then R.bombPlan = nil return nil end
        if B.dist(p.Position.X, p.Position.Y, sx, sy) < 10 then
            C.fire(p, prof, {Position = pos, Velocity = Vector(0, 0), Size = 14})
            return 0, 0
        end
        local tx, ty = routeTo(p, sx, sy, 0)
        if not tx then R.bombPlan = nil return nil end
        return goToward(p, tx, ty)
    end

    local function runBomb(p)
        local plan = R.bombPlan
        if not plan then return nil end
        if B.st.tick > (plan.expire or 0) then
            R.bombPlan = nil
            return nil
        end
        if plan.retreat then
            -- A bomb is down: walk out of the blast before going for the loot it uncovers.
            local tx, ty = stepAway(p, plan.x, plan.y)
            if tx then return goToward(p, tx, ty) end
            R.bombPlan = nil
            return nil
        end
        if plan.fire then return runFire(p, plan) end
        if plan.poop then return runPoop(p, plan) end
        local room = game:GetRoom()
        if not G.rock[plan.rock] then
            R.bombPlan = nil
            return nil
        end
        local sp = room:GetGridPosition(plan.stand)
        local d = B.dist(p.Position.X, p.Position.Y, sp.X, sp.Y)
        if d < 22 then
            B.tap(ButtonAction.ACTION_BOMB, 2)
            R.lastBombTick = B.st.tick
            B.event("bomb_rock", {cell = plan.rock})
            R.bombPlan = {retreat = true, x = sp.X, y = sp.Y, expire = B.st.tick + 70}
            return nil
        end
        B.st.mode, B.st.detail = "bomb", "rock " .. plan.rock
        local tx, ty = routeTo(p, sp.X, sp.Y, 1)
        if not tx then R.bombPlan = nil return nil end
        return goToward(p, tx, ty)
    end

    -- ------------------------------------------------------------ clean-room sweep

    -- Nearest reachable cell next to a blocked cell, where a bomb has to be dropped from.
    local function standNear(cell)
        local x, y = G.xy(cell)
        local best, bestD
        for _, dir in ipairs({{1, 0}, {-1, 0}, {0, 1}, {0, -1},
            {1, 1}, {1, -1}, {-1, 1}, {-1, -1}}) do
            local nx, ny = x + dir[1], y + dir[2]
            if nx >= 0 and nx < G.w and ny >= 0 and ny < G.h then
                local j = nx + ny * G.w
                if G.cost[j] and G.dist[j] and (not bestD or G.dist[j] < bestD) then
                    best, bestD = j, G.dist[j]
                end
            end
        end
        return best
    end

    -- Give up on a destructible that cannot be reached or shot, so the room can still be left.
    local function sweepFail(key)
        R.sweepTries[key] = (R.sweepTries[key] or 0) + 1
        if R.sweepTries[key] >= 3 then B.blacklist("sweep:" .. key, 1200) end
    end

    -- Shoot a lit fireplace from weapon range: tears put it out and it drops a pickup. Blue and
    -- white fires never go out, so a fire that stops losing HP is dropped instead of farmed.
    local function sweepFireplace(p, e, key)
        local hp = B.try(function() return e.HitPoints end) or 0
        local rec = R.fireHp[key]
        if not rec or rec.hp ~= hp then
            R.fireHp[key] = {hp = hp, since = B.st.tick}
        elseif B.st.tick - rec.since > 180 then
            B.blacklist("sweep:" .. key, 1800)
            B.event("fire_stuck", {hp = hp})
            return 0, 0
        end
        local prof = R.prof or C.profile(p)
        B.st.mode, B.st.detail = "sweep", "fire"
        -- Only fires with a clear line: a fire behind a rock or wedged in a corner can never be
        -- hit, so it is dropped instead of being shot at from wherever the bot happens to be.
        local cell = game:GetRoom():GetGridIndex(e.Position)
        local sx, sy
        if cell and cell >= 0 then sx, sy = poopSpot(p, cell, prof) end
        if not sx then
            B.blacklist("sweep:" .. key, 1800)
            B.event("fire_blocked", {cell = cell or -1})
            return 0, 0
        end
        C.fire(p, prof, e)
        if B.dist(p.Position.X, p.Position.Y, sx, sy) < 10 then return 0, 0 end
        local tx, ty = routeTo(p, sx, sy, 1)
        if not tx then
            B.blacklist("sweep:" .. key, 1800)
            return 0, 0
        end
        return goToward(p, tx, ty)
    end

    -- Shoot out poop: free, and it sometimes drops a pickup. A cell that survives 3 s of fire
    -- (red poop and friends) is blasted with a bomb while bombs are spare.
    local function sweepPoop(p, cell, key)
        local t0 = R.sweepTime[key]
        if not t0 then
            R.sweepTime[key] = B.st.tick
        elseif B.st.tick - t0 > 90 then
            local bombs = B.try(function() return p:GetNumBombs() end) or 0
            local stand = standNear(cell)
            if B.S.useBombs and bombs >= 2 and stand and not R.bombPlan then
                B.st.mode, B.st.detail = "sweep", "poop bomb"
                B.event("sweep_poop_bomb", {cell = cell})
                R.bombPlan = {rock = cell, stand = stand, expire = B.st.tick + 300}
                return runBomb(p) or 0, 0
            end
            B.blacklist("sweep:" .. key, 1800)
            return 0, 0
        end
        local prof = R.prof or C.profile(p)
        B.st.mode, B.st.detail = "sweep", "poop"
        local pos = game:GetRoom():GetGridPosition(cell)
        local sx, sy = poopSpot(p, cell, prof)
        if not sx then sweepFail(key) return 0, 0 end
        C.fire(p, prof, {Position = pos, Velocity = Vector(0, 0), Size = 14})
        if B.dist(p.Position.X, p.Position.Y, sx, sy) < 10 then return 0, 0 end
        local tx, ty = routeTo(p, sx, sy, 1)
        if not tx then return 0, 0 end
        return goToward(p, tx, ty)
    end

    -- Everything worth opening once the room is safe: lit fireplaces and poop (free), then a
    -- bomb on a rock that holds loot. Runs after the loot goal, so drops are collected next.
    local function sweepGoal(p)
        local room = game:GetRoom()
        if R.bombPlan then return nil end  -- the loot or door goal already has one pending
        local best, bestD, kind, key, cell
        local fires = B.try(function()
            return Isaac.FindByType(EntityType.ENTITY_FIREPLACE, -1, -1, false, false) end) or {}
        for _, e in ipairs(fires) do
            local k = "fire" .. B.hash(e)
            -- Only fires the player can walk up to: one across a pit burns on (and its drop
            -- lands where nothing can be picked up).
            local fc = room:GetGridIndex(e.Position)
            local reach = fc and fc >= 0 and standNear(fc)
            if reach and G.fireLit(e) and G.fireBreakable(e)
                and not B.isBlacklisted("sweep:" .. k) then
                local d = B.dist(p.Position.X, p.Position.Y, e.Position.X, e.Position.Y)
                if not bestD or d < bestD then best, bestD, kind, key = e, d, "fire", k end
            end
        end
        for c in pairs(G.poop) do
            local k = "poop" .. c
            if not B.isBlacklisted("sweep:" .. k) and standNear(c) then
                local pos = room:GetGridPosition(c)
                local d = B.dist(p.Position.X, p.Position.Y, pos.X, pos.Y)
                if not bestD or d < bestD then best, bestD, kind, key, cell = nil, d, "poop", k, c end
            end
        end
        if kind == "fire" then return sweepFireplace(p, best, key) end
        if kind == "poop" then return sweepPoop(p, cell, key) end

        -- A rock that pays for the bomb. Keep a spare unless the prize is a real item.
        local bombs = B.try(function() return p:GetNumBombs() end) or 0
        if not B.S.useBombs or bombs < 1 then return nil end
        if B.st.tick - R.lastBombTick < 90 then return nil end
        local rock, rockS
        for c, t in pairs(G.rockKind) do
            local info = G.LOOT_ROCK[t]
            local tries = R.sweepTries["rock" .. c] or 0
            if info and bombs >= info.bombs and tries < 2
                and not B.isBlacklisted("sweep:rock" .. c) then
                local stand = standNear(c)
                if stand then
                    local s = (G.dist[stand] or 99) + (12 - info.value) * 8
                    if not rockS or s < rockS then rock, rockS = {cell = c, stand = stand}, s end
                end
            end
        end
        if not rock then return nil end
        R.sweepTries["rock" .. rock.cell] = (R.sweepTries["rock" .. rock.cell] or 0) + 1
        B.st.mode, B.st.detail = "sweep", "rock"
        B.event("sweep_rock", {cell = rock.cell, type = G.rockKind[rock.cell]})
        R.bombPlan = {rock = rock.cell, stand = rock.stand, expire = B.st.tick + 300}
        local dx, dy = runBomb(p)
        if R.bombPlan then return dx or 0, dy or 0 end
        sweepFail("rock" .. rock.cell)
        return 0, 0
    end

    -- ------------------------------------------------------------ cards

    -- Cards have known effects, so the bot can use the good ones itself. Pills are left alone:
    -- their effect is hidden until tested and a bad one can end the run.
    local CARD_KIND = {}
    do
        local function add(name, kind)
            local id = B.try(function() return Card[name] end)
            if id then CARD_KIND[id] = kind end
        end
        add("TAROT_WORLD", "map")        -- reveals the floor (secret rooms included)
        add("TAROT_MOON", "secret")      -- teleports into the secret room
        add("TAROT_STAR", "treasure")    -- teleports into the treasure room
        add("TAROT_SUN", "heal")         -- full heal + damage + map
        add("TAROT_HIEROPHANT", "heal")
        add("TAROT_LOVERS", "heal")
        add("TAROT_EMPRESS", "combat")    -- damage + speed for the room: use it in a fight
        add("TAROT_MAGICIAN", "combat")
        add("TAROT_STRENGTH", "combat")
        add("TAROT_JUDGEMENT", "spawn")  -- beggar
        add("TAROT_WHEEL_OF_FORTUNE", "spawn")
        add("TAROT_DEATH", "combat")
        add("TAROT_CHARIOT", "combat")
        add("TAROT_HIGH_PRIESTESS", "combat")
    end
    R.cardBad = {}
    local HEAL_CARD = {}
    do
        for _, n in ipairs({"TAROT_SUN", "TAROT_HIEROPHANT", "TAROT_LOVERS"}) do
            local id = B.try(function() return Card[n] end)
            if id then HEAL_CARD[id] = true end
        end
    end

    local function unvisitedRoom(kind)
        for _, r in ipairs(F.rooms) do
            if r.type == kind then
                local d = F.desc(r)
                if d and (d.VisitedCount or 0) == 0 then return true end
            end
        end
        return false
    end

    local function floorHasSecret()
        return unvisitedRoom(RoomType.ROOM_SECRET)
            or unvisitedRoom(RoomType.ROOM_SUPERSECRET)
            or unvisitedRoom(RoomType.ROOM_ULTRASECRET)
    end

    local function cardGoal(p, ctx, foes)
        if B.st.tick < (R.cardUntil or 0) then return nil end
        local id = B.try(function() return p:GetCard(0) end) or 0
        if id == 0 then R.cardId, R.cardTries = nil, 0 return nil end
        if R.cardBad[id] then return nil end
        local kind = CARD_KIND[id]
        if not kind then return nil end
        if R.cardId ~= id then R.cardId, R.cardTries = id, 0 end
        local hp = (B.try(function() return p:GetHearts() end) or 0)
            + (B.try(function() return p:GetSoulHearts() end) or 0)
        local boss = false
        for _, e in ipairs(foes) do if e:IsBoss() then boss = true break end end
        local why
        if kind == "heal" and (hp <= 6 or boss) then why = boss and "boss" or "low hp"
        elseif kind == "map" and floorHasSecret() then why = "map"
        elseif kind == "secret" and floorHasSecret() then why = "secret"
        elseif kind == "treasure" and unvisitedRoom(RoomType.ROOM_TREASURE) then why = "treasure"
        elseif kind == "spawn" and #foes == 0 then why = "spawn"
        elseif kind == "combat" and (boss or #foes >= 2) then why = "combat" end
        if not why then return nil end
        R.cardTries = (R.cardTries or 0) + 1
        if R.cardTries > 3 then R.cardBad[id] = true return nil end
        B.tap(ButtonAction.ACTION_PILLCARD, 2)
        R.cardUntil = B.st.tick + 40
        B.event("card_use", {id = id, why = why, tries = R.cardTries})
        return why
    end

    -- ------------------------------------------------------------ card swap

    -- Only one card is carried at a time. If a clearly better one is on the floor, drop the
    -- held card first (the pickup cannot be taken while the slot is full) and skip the dropped
    -- card for a few seconds so the bot does not just pick it up again.
    local function cardSwapGoal(p)
        local held = B.try(function() return p:GetCard(0) end) or 0
        if held == 0 then return nil end
        local heldRank = (I.CARD_RANK or {})[held] or 99
        local list = B.try(function()
            return Isaac.FindByType(EntityType.ENTITY_PICKUP, -1, -1, false, false) end) or {}
        local best, bestD
        for _, e in ipairs(list) do
            if e.Variant == PickupVariant.PICKUP_TAROTCARD then
                local r = (I.CARD_RANK or {})[e.SubType] or 99
                if r < heldRank then
                    local d = B.dist(p.Position.X, p.Position.Y, e.Position.X, e.Position.Y)
                    if not bestD or d < bestD then best, bestD = e, d end
                end
            end
        end
        if not best then return nil end
        if bestD < 45 then
            if B.st.tick - (R.lastDrop or -1000) > 30 then
                B.tap(ButtonAction.ACTION_DROP, 2)
                R.lastDrop = B.st.tick
                I.skipCard = {id = held, expire = B.st.tick + 240}
                B.event("card_swap", {from = held, to = best.SubType})
            end
            return 0, 0
        end
        local tx, ty = routeTo(p, best.Position.X, best.Position.Y, 0)
        if tx then return goToward(p, tx, ty) end
        return nil
    end

    -- ------------------------------------------------------------ secret rooms

    -- A secret room is entered by bombing the wall it shares with a normal room. The level data
    -- lists secret rooms before they are found, so the bot can pick the middle of that edge,
    -- bomb it, step back from the blast and then walk into the opening.
    local function secretGoal(p)
        local room = game:GetRoom()
        local plan = R.secretPlan
        if plan then
            if plan.phase == "go" then
                local sp = room:GetGridPosition(plan.stand)
                local d = B.dist(p.Position.X, p.Position.Y, sp.X, sp.Y)
                if d < 22 then
                    B.tap(ButtonAction.ACTION_BOMB, 2)
                    R.lastBombTick = B.st.tick
                    plan.phase, plan.t = "wait", B.st.tick + 60
                    B.event("secret_bomb", {wall = plan.wall})
                    return 0, 0
                end
                local tx, ty = routeTo(p, sp.X, sp.Y, 0)
                if tx then return goToward(p, tx, ty) end
                R.secretPlan = nil
                return nil
            elseif plan.phase == "wait" then
                if B.st.tick < plan.t then
                    local tx, ty = stepAway(p, plan.bx, plan.by)
                    if tx then return goToward(p, tx, ty) end
                    return 0, 0
                end
                plan.phase, plan.t = "enter", B.st.tick + 150
                return 0, 0
            end
            local pos = room:GetGridPosition(plan.wall)
            local tx, ty = routeTo(p, pos.X, pos.Y, 0)
            if tx then return goToward(p, tx, ty) end
            if B.st.tick > plan.t then
                R.secretBad = plan.li
                R.secretPlan = nil
                B.event("secret_fail", {room = plan.li})
            end
            return 0, 0
        end
        if not B.S.useBombs then return nil end
        if (B.try(function() return p:GetNumBombs() end) or 0) < 1 then return nil end
        if not room:IsClear() then return nil end
        local here = F.roomOfIndex(B.st.room)
        if not here then return nil end
        local w = room:GetGridWidth()
        local h = room:GetGridSize() // w
        for _, r in ipairs(F.rooms) do
            local t = r.type
            if (t == RoomType.ROOM_SECRET or t == RoomType.ROOM_SUPERSECRET
                or t == RoomType.ROOM_ULTRASECRET) and r.li ~= R.secretBad then
                local desc = F.desc(r)
                if desc and (desc.VisitedCount or 0) == 0 then
                    local dx, dy
                    for _, a in ipairs(here.cells) do
                        local ax, ay = a % 13, a // 13
                        for _, b in ipairs(r.cells) do
                            local bx, by = b % 13, b // 13
                            local ox, oy = bx - ax, by - ay
                            if math.abs(ox) + math.abs(oy) == 1 then dx, dy = ox, oy break end
                        end
                        if dx then break end
                    end
                    if dx then
                        local wx, wy
                        if dx == 1 then wx, wy = w - 1, h // 2
                        elseif dx == -1 then wx, wy = 0, h // 2
                        elseif dy == 1 then wx, wy = w // 2, h - 1
                        else wx, wy = w // 2, 0 end
                        local sx, sy = wx - dx, wy - dy
                        local wall = wx + wy * w
                        local stand = sx + sy * w
                        if G.cost[wall] == nil and G.cost[stand] and G.dist[stand] then
                            local sp = room:GetGridPosition(stand)
                            R.secretPlan = {li = r.li, wall = wall, stand = stand,
                                phase = "go", t = B.st.tick + 600, bx = sp.X, by = sp.Y}
                            B.event("secret_found", {room = r.gi, wall = wall})
                            return 0, 0
                        end
                    end
                end
            end
        end
        return nil
    end

    -- ------------------------------------------------------------ combat goal

    local function fight(p, foes, ctx)
        local now = B.st.tick
        if not R.prof or now - R.profAt > 30 then
            R.prof = C.profile(p)
            R.profAt = now
        end
        local prof = R.prof
        local target = C.pickTarget(p, foes)
        if not target then return nil end
        local boss = false
        for _, e in ipairs(foes) do if e:IsBoss() then boss = true break end end
        B.st.mode = boss and "boss" or "fight"
        B.st.detail = prof.kind .. " " .. tostring(target.Type) .. "." .. tostring(target.Variant)

        C.observe(target)
        local pref = C.needFlank(target, prof) and C.flankPref(target) or nil
        local basePref = prof.pref
        if C.BOSS_FAR[target.Type] or C.threatOf(target) >= 5 then
            prof.pref = math.min(prof.range, basePref + 50)
        end
        local sx, sy = C.attackSpot(p, target, prof, pref)
        prof.pref = basePref
        local tx, ty
        if not sx then
            tx, ty = routeTo(p, target.Position.X, target.Position.Y, 3)
            if not tx then
                -- Walled off by poop or a fire: shoot the first one on the way instead of
                -- standing still (bombs stay for loot and doors).
                if R.bombPlan and not (R.bombPlan.poop or R.bombPlan.fire) then R.bombPlan = nil end
                if not R.bombPlan then
                    local plan = planBomb(p, target.Position.X, target.Position.Y, true)
                    if plan then
                        plan.expire = now + 300
                        R.bombPlan = plan
                    end
                end
                if R.bombPlan then
                    local dx, dy = runBomb(p)
                    if R.bombPlan then return dx, dy end
                end
            end
        end

        C.fire(p, prof, target)
        C.maybeUseActive(p, foes, boss)
        C.maybeBomb(p, target, boss, ctx.lost)

        if sx then
            local d = B.dist(p.Position.X, p.Position.Y, sx, sy)
            if d < 10 then return nil end  -- in position: hold still, dodge layer still runs
            tx, ty = routeTo(p, sx, sy, 1)
            return goToward(p, tx, ty)
        end
        -- No firing spot (enemy behind rocks or over a pit): close the distance.
        return goToward(p, tx, ty)
    end

    -- ------------------------------------------------------------ non-combat goals

    -- Unpressed pressure plates (reward plates, plate-locked rooms).
    local function plateGoal(p)
        local room = game:GetRoom()
        for i = 0, room:GetGridSize() - 1 do
            local ge = room:GetGridEntity(i)
            if ge and B.try(function() return ge:GetType() end) == GridEntityType.GRID_PRESSURE_PLATE then
                local state = B.try(function() return ge.State end) or 0
                local key = "plate" .. i
                if state == 0 and not B.isBlacklisted(key) then
                    local pos = room:GetGridPosition(i)
                    local tx, ty, remaining = routeTo(p, pos.X, pos.Y, 0, true)
                    if not tx and G.hasOnOff then
                        -- The plate is behind retracting spikes: plan through them. G.steer stops
                        -- at a live spike, so the bot walks up and steps on when it retracts.
                        tx, ty, remaining = routeTo(p, pos.X, pos.Y, 0, false)
                    end
                    if not tx then
                        -- Walled off by a fireplace, poop or rock: clear it. If nothing
                        -- breakable is in the way the plate is unreachable this room, so give
                        -- up on it instead of retrying every few seconds.
                        local plan = planBomb(p, pos.X, pos.Y)
                        if plan then
                            plan.expire = B.st.tick + 300
                            R.bombPlan = plan
                            B.st.mode, B.st.detail = "plate", tostring(i)
                            local dx, dy = runBomb(p)
                            if dx then return dx, dy end
                            return nil
                        end
                        B.blacklist(key, 1e9)
                        B.event("plate_blocked", {cell = i})
                    end
                    if tx then
                        B.st.mode, B.st.detail = "plate", tostring(i)
                        if track(key, remaining) then return nil end
                        local dx, dy = pos.X - p.Position.X, pos.Y - p.Position.Y
                        -- Close to the plate the dodge layer treats the neighbouring fires as a
                        -- reason to back off; the plate itself is walkable, so ignore it here.
                        B.st.plateNear = (dx * dx + dy * dy) < 3600
                        if dx * dx + dy * dy < 400 then return dx, dy end
                        return goToward(p, tx, ty)
                    end
                end
            end
        end
        return nil
    end

    -- Route to a pickup. Its own cell must be reachable: with a radius the route could end on
    -- a diagonal neighbour, and a chest wedged between two rocks corner to corner had the bot
    -- pushing into the gap for good. A pickup lying on the edge of a blocked cell still counts
    -- from a side neighbour close enough to touch it.
    local function lootRoute(p, e, noSafe)
        local room = game:GetRoom()
        local x, y = e.Position.X, e.Position.Y
        local cell = room:GetGridIndex(e.Position)
        if not cell or cell < 0 then return nil end
        if G.dist[cell] then return routeTo(p, x, y, 0, not noSafe) end
        if G.cost[cell] then return nil end  -- open floor, but walled off from us
        local cx, cy = G.xy(cell)
        for _, dir in ipairs({{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) do
            local nx, ny = cx + dir[1], cy + dir[2]
            if nx >= 0 and nx < G.w and ny >= 0 and ny < G.h then
                local j = nx + ny * G.w
                local pos = room:GetGridPosition(j)
                if G.dist[j] and B.dist(pos.X, pos.Y, x, y) < 30 then
                    return routeTo(p, pos.X, pos.Y, 0, not noSafe)
                end
            end
        end
        return nil
    end

    local function lootGoal(p, ctx)
        local list = I.scan(p, ctx)
        local bombs = B.try(function() return p:GetNumBombs() end) or 0
        local best, bestS, bestTx, bestTy, bestRem
        for _, entry in ipairs(list) do
            local e = entry.e
            local tx, ty, remaining = lootRoute(p, e, entry.beggar)
            if tx then
                local s = entry.value * 30 / (10 + remaining)
                -- Stick with the pickup already being walked to: otherwise two equal cards
                -- on the floor make the bot pace between them.
                if R.lootKey == entry.key and B.st.tick < (R.lootUntil or 0) then s = s + 6 end
                if not bestS or s > bestS then
                    best, bestS, bestTx, bestTy, bestRem = entry, s, tx, ty, remaining
                end
            elseif not R.bombPlan and entry.value > 0 then
                -- Walled in: put out a fireplace or poop in the way, or bomb rocks if it is
                -- worth a bomb (chests too while a spare bomb stays). No bombs: skip it.
                local plan = planBomb(p, e.Position.X, e.Position.Y)
                if plan and (plan.fire or plan.poop or entry.value >= 7
                    or (entry.value >= 4 and bombs >= 2)) then
                    plan.expire = B.st.tick + 300
                    R.bombPlan = plan
                end
            end
        end
        if not best then return nil end
        R.lootKey, R.lootUntil = best.key, B.st.tick + 60
        local e = best.e
        -- Count coins fed to a beggar so it is not fed forever if the game keeps it around.
        if best.beggar then
            local d = B.dist(p.Position.X, p.Position.Y, e.Position.X, e.Position.Y)
            if d < 26 and B.st.tick - (B.st.beggarTick or 0) > 20 then
                B.st.beggar = B.st.beggar or {}
                B.st.beggar[best.key] = (B.st.beggar[best.key] or 0) + 1
                B.st.beggarTick = B.st.tick
                B.event("beggar_pay", {paid = B.st.beggar[best.key]})
            end
        end
        B.st.mode = "loot"
        B.st.detail = tostring(e.Variant) .. "." .. tostring(e.SubType)
        if track(best.key, bestRem) then return nil end
        local dx, dy = e.Position.X - p.Position.X, e.Position.Y - p.Position.Y
        if dx * dx + dy * dy < 900 and G.segmentClear(p.Position.X, p.Position.Y,
            e.Position.X, e.Position.Y, 8) then
            return dx, dy
        end
        return goToward(p, bestTx, bestTy)
    end

    -- A reachable cell 110-200 units from a point (out of a bomb's reach, off a trapdoor).
    function stepAway(p, x, y)
        local room = game:GetRoom()
        local best, bestD
        for cell, d in pairs(G.dist) do
            local pos = room:GetGridPosition(cell)
            local r = B.dist(pos.X, pos.Y, x, y)
            if r >= 110 and r <= 200 and G.cost[cell] and G.cost[cell] < 50
                and (not bestD or d < bestD) then
                best, bestD = pos, d
            end
        end
        if not best then return nil end
        return routeTo(p, best.X, best.Y, 0)
    end

    -- Bedroom door: bomb it from the cell in front, back off while the bomb is down, again
    -- for the second explosion. Out of bombs, or still shut after four: skip the room.
    local function bedroomDoor(p, d, key, inX, inY)
        local li = d.room.li
        B.st.bedHits = B.st.bedHits or {}  -- state saved before this field existed
        local hits = B.st.bedHits[li] or 0
        if hits >= 4 or not F.canOpenBedroom(p, d.room) then
            B.st.badRooms[li] = B.st.tick + 1e9
            B.event("bedroom_skip", {room = d.room.gi, hits = hits,
                bombs = B.try(function() return p:GetNumBombs() end) or 0})
            return nil
        end
        B.st.mode, B.st.detail = "bedroom", "bombs " .. hits .. "/2"
        local since = B.st.tick - R.lastBombTick
        if since < 100 then
            R.goalKey = nil  -- waiting out the bomb is not being stuck
            local tx, ty = stepAway(p, inX, inY)
            if tx then return goToward(p, tx, ty) end
            return nil
        end
        local dist = B.dist(p.Position.X, p.Position.Y, inX, inY)
        if dist < 22 then
            if since < 120 then R.goalKey = nil return 0, 0 end
            B.tap(ButtonAction.ACTION_BOMB, 2)
            R.lastBombTick = B.st.tick
            B.st.bedHits[li] = hits + 1
            B.event("bomb_door", {room = d.room.gi, slot = d.slot, n = hits + 1})
            return 0, 0
        end
        local tx, ty, remaining = routeTo(p, inX, inY, 0)
        if not tx then
            B.blacklist(key, 900)
            return nil
        end
        if track(key, remaining) then return nil end
        return goToward(p, tx, ty)
    end

    -- Walk through a door: path to the door cell, then push outward.
    local function doorGoal(p, d, label)
        local room = game:GetRoom()
        local pos = d.pos
        local slot = d.slot % 4
        local ox, oy = 0, 0
        if slot == 0 then ox = -1 elseif slot == 1 then oy = -1 elseif slot == 2 then ox = 1 else oy = 1 end
        local key = "door" .. d.slot .. ":" .. B.st.room
        B.st.mode, B.st.detail = label, "slot " .. d.slot
        -- Heal up before a boss room while it is still free to do so.
        if d.room and d.room.type == RoomType.ROOM_BOSS and B.st.tick >= (R.cardUntil or 0) then
            local hp = (B.try(function() return p:GetHearts() end) or 0)
                + (B.try(function() return p:GetSoulHearts() end) or 0)
            local held = B.try(function() return p:GetCard(0) end) or 0
            if hp <= 6 and HEAL_CARD[held] then
                B.tap(ButtonAction.ACTION_PILLCARD, 2)
                R.cardUntil = B.st.tick + 40
                B.event("boss_prep", {card = held, hp = hp})
                return 0, 0
            end
        end
        -- A locked door with no key is not a door: walking into it just pushes the wall.
        if d.locked and not d.open then
            local keys = B.try(function() return p:GetNumKeys() end) or 0
            local golden = B.try(function() return p:HasGoldenKey() end)
            if keys < 1 and not golden and not F.isBedroom(d.room) then
                B.blacklist(key, 1200)
                return nil
            end
        end
        local inX, inY = pos.X - ox * 40, pos.Y - oy * 40
        if d.locked and F.isBedroom(d.room) then return bedroomDoor(p, d, key, inX, inY) end
        -- Poop or a rock on the cell in front of the door: the route (radius 1) ends next to
        -- it and the bot pushed into it until the stuck timer gave up, then came back.
        -- Shoot or bomb it out first.
        local inner = room:GetGridIndex(Vector(inX, inY))
        if inner and inner >= 0 and (G.poop[inner] or G.rock[inner]) then
            if not R.bombPlan then
                local plan = G.poop[inner] and {poop = inner} or planBomb(p, inX, inY)
                if plan then
                    plan.expire = B.st.tick + 300
                    R.bombPlan = plan
                    B.event("door_blocked", {slot = d.slot, cell = inner, poop = G.poop[inner] or false})
                end
            end
            if R.bombPlan then
                local dx, dy = runBomb(p)
                if dx then return dx, dy end
            end
            if not R.bombPlan then B.blacklist(key, 900) end
            return nil
        end
        local dist = B.dist(p.Position.X, p.Position.Y, inX, inY)
        if dist < 34 then
            -- A door that does not open after two seconds cannot be entered (locked without a
            -- key, boarded, or not a real door): stop pushing and forget it for a while.
            if R.doorKey ~= key then R.doorKey, R.doorTick = key, B.st.tick end
            if B.st.tick - (R.doorTick or B.st.tick) > 60 then
                -- Not enterable: never come back to this door or this room this floor.
                B.blacklist(key, 1e9)
                if d.room then B.st.badRooms[d.room.li] = B.st.tick + 1e9 end
                B.event("door_closed", {slot = d.slot, room = B.st.room,
                    target = d.room and d.room.gi or -1, locked = d.locked or false})
                R.doorKey = nil
                return nil
            end
        else
            R.doorKey = nil
        end
        if dist < 34 then
            if track(key, 0) then
                -- A locked door that stayed shut (bedroom, key-proof doors): forget the
                -- room behind it for this floor.
                if d.locked and d.room then B.st.badRooms[d.room.li] = B.st.tick + 1e9 end
                return nil
            end
            -- Line up with the door, then walk into it.
            local lx, ly = (pos.X - p.Position.X), (pos.Y - p.Position.Y)
            if ox ~= 0 then ly = ly * 2 else lx = lx * 2 end
            -- Remember which door was used; the next room blacklists the way back for a moment.
            R.lastDoor = {room = B.st.room, slot = d.slot, tick = B.st.tick}
            return lx + ox * 60, ly + oy * 60
        end
        local tx, ty, remaining = routeTo(p, inX, inY, 1)
        if not tx then
            if not R.bombPlan then
                local plan = planBomb(p, inX, inY)
                if plan then plan.expire = B.st.tick + 300 R.bombPlan = plan end
            end
            if not R.bombPlan then B.blacklist(key, 900) end
            return nil
        end
        if track(key, remaining) then return nil end
        return goToward(p, tx, ty)
    end

    local function exitGoal(p, x)
        local key = "exit:" .. x.kind
        B.st.mode, B.st.detail = "exit", x.kind
        if x.closed then
            -- Step away so it opens: the nearest reachable cell 110-200 units from it.
            B.st.detail = "trapdoor closed"
            local tx, ty = stepAway(p, x.pos.X, x.pos.Y)
            if not tx then return nil end
            return goToward(p, tx, ty)
        end
        local tx, ty, remaining
        -- Trapdoor cells carry a large path cost on purpose; route next to it, then step in.
        tx, ty, remaining = routeTo(p, x.pos.X, x.pos.Y, 1)
        local dx, dy = x.pos.X - p.Position.X, x.pos.Y - p.Position.Y
        if dx * dx + dy * dy < 60 * 60 or not tx then return dx, dy end
        if track(key, remaining) then return dx, dy end
        return goToward(p, tx, ty)
    end

    -- ------------------------------------------------------------ win / run end

    local function goalReached(effStage)
        local goalStage = B.GOAL_STAGE[B.S.goal] or 11
        if effStage < goalStage then return false end
        if B.S.goal == "auto" then return false end  -- auto ends on the chest
        local stageType = B.try(function() return game:GetLevel():GetStageType() end) or 0
        -- Stage 10/11 come in two versions; the goal names the version.
        if effStage == 10 or effStage == 11 then
            local wotl = stageType == StageType.STAGETYPE_WOTL
            if (B.S.goal == "isaac" or B.S.goal == "bluebaby") and not wotl then return false end
            if (B.S.goal == "satan" or B.S.goal == "lamb") and wotl then return false end
        end
        return true
    end

    function R.declareWin(how)
        if B.st.won then return end
        B.st.won = true
        local stage, eff = B.stageInfo()
        local p = B.player()
        B.S.stats.wins = (B.S.stats.wins or 0) + 1
        if B.st.mission then
            B.missionDone(B.st.mission)
            B.st.mission = nil
        end
        B.saveConfig()
        B.event("win", {how = how, stage = stage, eff = eff, char = p and B.playerType(p) or -1,
            goal = B.S.goal, diff = game.Difficulty, cheat = B.st.cheat or false, minutes = math.floor((B.st.tick - B.st.runStartTick) / 1800 * 10) / 10})
        B.say("WIN (" .. how .. ")", 600)
        if B.S.onWin == "restart" and B.S.autoRestart then
            B.st.restartAt = B.st.renderTick + 120
        end
    end

    -- ------------------------------------------------------------ floor routing

    local function routeFloor(p, roomType, effStage)
        local level = game:GetLevel()
        local roomIdx = level:GetCurrentRoomIndex()
        local here = F.roomOfIndex(roomIdx)

        -- Secret rooms and crawl spaces have no doors: leave through the bombed hole in the
        -- wall, or step onto the ladder at the centre.
        if #F.doors() == 0 then
            local hole = F.hole()
            if hole then return exitGoal(p, {kind = "hole", pos = hole}) end
            return exitGoal(p, {kind = "hole", pos = game:GetRoom():GetCenterPos()})
        end

        -- Off-map rooms (devil/angel, I AM ERROR, ...): leave through the first door.
        if roomIdx < 0 then
            R.devilDone = true
            local d = F.anyExitDoor()
            if d then return doorGoal(p, d, "leave") end
            local exits = F.exits()
            if #exits > 0 then return exitGoal(p, exits[1]) end
            return nil
        end

        local goalRoom, why = F.chooseGoalRoom(p, here)
        local inBoss = roomType == RoomType.ROOM_BOSS

        -- Boss room cleared and nothing left worth exploring: devil deal, then the exit.
        if inBoss and (goalRoom == nil or goalRoom == here) then
            if goalReached(effStage) and F.allBossesClear() then R.declareWin("goal boss") end
            local exits = F.exits()
            local atGoal = goalReached(effStage) or B.S.goal == "auto"
            if B.st.won and B.S.onWin == "restart" then
                B.st.mode = "won"
                return nil
            end
            if B.S.devil and not R.devilDone and not B.st.won then
                local dd = F.devilDoor()
                if dd and dd.open then return doorGoal(p, dd, "deal") end
            end
            local x, ending = F.pickExit(p, exits, effStage)
            if x and ending then
                -- Taking the chest ends the run with the real ending screen.
                if B.S.goal ~= "auto" and not atGoal then x = nil end
            end
            if B.st.won and not (x and ending) then
                -- Goal met but no ending here (Mom leaves a trapdoor): the run is done for
                -- the bot; start the next one if allowed.
                B.st.mode = "won"
                if B.S.autoRestart and not B.st.restartAt then
                    B.st.restartAt = B.st.renderTick + 180
                end
                return nil
            end
            if x then
                if ending then B.st.pendingEnding = true end
                return exitGoal(p, x)
            end
            B.st.mode, B.st.detail = "wait", "exit"
            return nil
        end

        if not goalRoom then
            -- No graph target (map not built yet or everything unreachable): any exit here.
            local exits = F.exits()
            if #exits > 0 then return exitGoal(p, exits[1]) end
            local d = F.anyExitDoor()
            if d then return doorGoal(p, d, "door") end
            return nil
        end
        if goalRoom == here then
            -- Arrived but the room still matters (should be visited now): pick again next tick.
            return nil
        end
        local d = F.doorToward(p, goalRoom)
        if not d then
            -- No usable door leads there right now: skip it for a while (it is retried, so
            -- a temporarily blacklisted door does not lose the boss for the whole floor)
            -- and take any reasonable door meanwhile.
            B.st.badRooms[goalRoom.li] = B.st.tick + 1200
            B.event("unreachable", {room = goalRoom.gi, type = goalRoom.type, from = roomIdx})
            local any = F.anyExitDoor()
            if any then return doorGoal(p, any, "roam") end
            return nil
        end
        return doorGoal(p, d, why == "boss" and "to boss" or "explore")
    end

    -- ------------------------------------------------------------ main update

    function R.update()
        B.clearInput()
        local st = B.st
        st.tick = st.tick + 1
        if not st.enabled or st.paused then st.mode = st.enabled and "paused" or "off" return end
        -- Frames the bot sits out (pause during a door transition, room entry) must not drop
        -- a held charge: the release fires it and the next press cuts the beam short.
        local function holdCharge()
            if C.charge.holding > 0 then B.shoot(C.charge.dir) end
        end
        if B.try(function() return game:IsPaused() end) then st.mode = "gamepause" holdCharge() return end

        local p = B.player()
        if not p or p:IsDead() then st.mode = "dead" return end
        st.px, st.py = math.floor(p.Position.X), math.floor(p.Position.Y)
        local room = game:GetRoom()
        if room:GetFrameCount() < 2 then st.mode = "enter" holdCharge() return end

        local level = game:GetLevel()
        st.room = level:GetCurrentRoomIndex()  -- also right after a luamod reload
        if not F.builtFor then F.build() end

        local ents = B.try(function() return Isaac.GetRoomEntities() end) or {}
        D.collect(ents, p)
        -- Retracting spikes change every few frames: rebuild faster so the step gate is current.
        if G.builtAt < 0 or st.tick - G.builtAt >= (G.hasOnOff and 4 or 15) then G.build(p, ents) end

        -- Movement speed from the stat (1.0 speed ~ 4.9 units per update at full stick).
        st.speed = math.max(2.5, (B.try(function() return p.MoveSpeed end) or 1) * 4.9)

        local foes = C.enemies(ents)
        -- Path costs: stay out of enemy contact range when routing past them.
        local extra
        if #foes > 0 then
            extra = {}
            for _, e in ipairs(foes) do
                local c = room:GetGridIndex(e.Position)
                if c and c >= 0 then
                    local cx, cy = G.xy(c)
                    for oy = -1, 1 do
                        for ox = -1, 1 do
                            local nx, ny = cx + ox, cy + oy
                            if nx >= 0 and nx < G.w and ny >= 0 and ny < G.h then
                                local j = nx + ny * G.w
                                extra[j] = (extra[j] or 0) + ((ox == 0 and oy == 0) and 12 or 5)
                            end
                        end
                    end
                end
            end
        end
        G.flood(room:GetGridIndex(p.Position), extra)

        local ctx = stats(p)
        local stage, effStage = B.stageInfo()
        local desc = B.try(function() return level:GetCurrentRoomDesc() end)
        local roomType = desc and desc.Data and desc.Data.Type or RoomType.ROOM_DEFAULT

        -- Progress clock: a spike room that does not move for ~3 s gets the brute-force
        -- crossing (walk the spikes, take the hits) instead of stalling until the run dies.
        if not R.lastPosTick or B.dist(p.Position.X, p.Position.Y, R.lastPosX or 0, R.lastPosY or 0) > 8 then
            R.lastPosX, R.lastPosY, R.lastPosTick = p.Position.X, p.Position.Y, st.tick
        end
        if G.hasOnOff and not G.forceSpikes and room:IsClear()
            and st.tick - (R.lastPosTick or 0) > 180 then
            G.forceSpikes = true
            G.builtAt = -1
            B.event("spike_force", {tick = st.tick})
        end

        local dx, dy
        -- Every branch below names its own mode; one that finds nothing to do leaves "idle"
        -- (before, the last mode stayed on screen, e.g. "off" after F9, and hid the stall).
        st.mode, st.detail = "idle", ""
        -- Standing on live spikes: step off onto the nearest retracted cell instead of taking
        -- hit after hit while the wave passes.
        local stepped
        if not G.flying and G.spikeUp then
            local here = room:GetGridIndex(p.Position)
            if here and here >= 0 and G.spikeUp[here] then
                stepped = B.try(function() return G.spikeStepOff(here) end)
            end
        end
        local cardWhy = cardGoal(p, ctx, foes)
        if cardWhy then
            dx, dy = 0, 0
            st.mode, st.detail = "card", cardWhy
        elseif stepped then
            dx, dy = stepped[1], stepped[2]
            st.mode = "unstick"
        elseif R.wander and st.tick < R.wander[3] then
            dx, dy = R.wander[1], R.wander[2]
            st.mode = "unstick"
            if #foes > 0 then C.fire(p, R.prof or C.profile(p), C.pickTarget(p, foes) or foes[1]) end
        elseif #foes > 0 then
            dx, dy = fight(p, foes, ctx)
        else
            local clear = room:IsClear()
            -- The game sometimes keeps a room "uncleared" with nothing targetable left (a
            -- stuck spawner, a fire that cannot be put out, a bugged room flag). After a few
            -- seconds of sweeping, behave as if it were clear so the bot moves on instead of
            -- standing in the middle firing in four directions forever.
            if not clear and #foes == 0 and R.idleClear > 90 and #hiddenThreats(ents) == 0 then
                clear = true
                st.mode, st.detail = "idle", ""
            end
            if R.bombPlan then dx, dy = runBomb(p) end
            if not dx then dx, dy = plateGoal(p) end
            if not dx then dx, dy = cardSwapGoal(p) end
            if not dx then dx, dy = lootGoal(p, ctx) end
            if not dx and clear then dx, dy = sweepGoal(p) end
            if not dx and clear then dx, dy = secretGoal(p) end
            if not dx and not clear then
                -- Enemies hidden or invulnerable (jumping, burrowed, spawning). If any are on
                -- screen, keep away from them and aim at the nearest; otherwise hold the centre
                -- and sweep fire so the room can finish.
                st.mode = "hold"
                R.idleClear = R.idleClear + 1
                local threats = hiddenThreats(ents)
                -- Reviving leftovers (Globin goo) stop counting as enemies but come back unless
                -- they are finished off. Give up on one that cannot be hurt.
                local goo = C.residue(ents)
                if #goo > 0 then
                    R.residueSince = R.residueSince or st.tick
                    if st.tick - R.residueSince < 300 then
                        for _, e in ipairs(goo) do threats[#threats + 1] = e end
                    end
                else
                    R.residueSince = nil
                end
                local airborne = {}
                for _, e in ipairs(threats) do
                    if e:IsBoss() then airborne[#airborne + 1] = e end
                end
                local prof = R.prof or C.profile(p)
                if #airborne > 0 then
                    -- Keep away from where it lands; fire (or charge) at it meanwhile.
                    local tx, ty = safestSpot(p, airborne)
                    C.fire(p, prof, C.pickTarget(p, airborne) or airborne[1])
                    dx, dy = goToward(p, tx, ty)
                    st.detail = "evade"
                elseif #threats > 0 then
                    -- Shut for now (a Host in its shell, a spawner): shooting an invulnerable
                    -- body only keeps it closed, so keep the distance and wait until it opens.
                    local hurtable = {}
                    for _, e in ipairs(threats) do
                        if B.try(function() return e:IsVulnerableEnemy() end) then
                            hurtable[#hurtable + 1] = e
                        end
                    end
                    if #hurtable > 0 then
                        dx, dy = fight(p, hurtable, ctx)
                    else
                        local tx2, ty2 = waitSpot(p, threats)
                        dx, dy = goToward(p, tx2, ty2)
                        st.detail = "wait " .. tostring(threats[1].Type)
                    end
                else
                    st.detail = ""
                    -- Nothing visible and the room still claims to be uncleared: after 20 s of
                    -- standing around, try the floor routing anyway instead of waiting forever.
                    if R.idleClear > 600 then
                        dx, dy = routeFloor(p, roomType, effStage)
                        if dx then st.mode = "roam" end
                    end
                    if not dx then
                        local c = room:GetCenterPos()
                        local tx, ty = routeTo(p, c.X, c.Y, 2)
                        dx, dy = goToward(p, tx, ty)
                        C.sweep(p, prof)
                    end
                end
                st.mode = "hold"
            elseif not dx then
                dx, dy = routeFloor(p, roomType, effStage)
            end
            -- Nothing to do in a clear room for 10 s: a goal choice that keeps naming this
            -- room (or no reachable target) must not freeze the run; take any door.
            if not dx and clear and st.mode == "idle" then
                R.idleTicks = (R.idleTicks or 0) + 1
                if R.idleTicks == 300 then
                    local here = F.roomOfIndex(game:GetLevel():GetCurrentRoomIndex())
                    local goal, why = F.chooseGoalRoom(p, here)
                    B.event("idle", {room = st.room, goal = goal and goal.gi or -1, why = why or "",
                        here = here and here.gi or -1})
                end
                if R.idleTicks >= 300 then
                    local d = F.anyExitDoor()
                    if d then dx, dy = doorGoal(p, d, "roam") end
                end
            else
                R.idleTicks = 0
            end
            -- Carry a full charge into the next fight instead of wasting it on nothing.
            C.keepCharge(p, R.prof or C.profile(p))
        end

        -- Final move through the dodge layer, except for the last step onto a pressure
        -- plate: the fire statics around it would otherwise veto that step forever.
        local weight = dodgeWeight(p, ctx)
        local mx, my, risk
        if st.mode == "plate" then
            -- Plate rooms: walk the path straight. The path already avoids fire cells; the
            -- dodge layer's static-fire radius was what kept vetoing the approach.
            mx, my, risk = dx, dy, 0
        else
            mx, my, risk = D.choose(p, dx, dy, weight)
        end
        if mx and (mx ~= 0 or my ~= 0) then
            -- Do not grind against a wall: a step into a solid cell is dropped unless this is a
            -- door/exit walk (those push through the opening on purpose) or the bot is standing
            -- somewhere it should not be and needs to escape.
            local nx, ny = p.Position.X + mx * 14, p.Position.Y + my * 14
            local free = B.grid.walkableAt(nx, ny) or not B.grid.walkableAt(p.Position.X, p.Position.Y)
            if free or st.mode == "door" or st.mode == "exit" or st.mode == "plate"
                or st.mode == "loot" then
                B.move(mx, my)
            end
        end
        if B.replay then B.replay.record(p, ents, dx, dy, mx, my, risk, weight) end
    end
end
