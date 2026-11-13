-- Room grid model and path search.
-- Cells are 40x40 world units, index = x + y * width (Room:GetGridIndex). One Dijkstra flood
-- from the player per replan gives the path cost to every cell, so the brain can compare many
-- candidate targets (loot, attack spots, doors) without running a search per target.

return function(B)
    local game = B.game
    local G = {}
    B.grid = G

    local GT = GridEntityType
    local COLL = GridCollisionClass
    local PV = PickupVariant

    -- Entities that block movement like a rock: slot machines, shopkeepers, lit fireplaces,
    -- turret heads. Their cells are removed from the walkable set.
    local BLOCKING = {
        [EntityType.ENTITY_SLOT] = true,
        [EntityType.ENTITY_SHOPKEEPER] = true,
        [EntityType.ENTITY_FIREPLACE] = true,
        [EntityType.ENTITY_STONEHEAD] = true,
        [EntityType.ENTITY_CONSTANT_STONE_SHOOTER] = true,
        [EntityType.ENTITY_BRIMSTONE_HEAD] = true,
        [EntityType.ENTITY_QUAKE_GRIMACE] = true,
        [EntityType.ENTITY_BOMB_GRIMACE] = true,
        [EntityType.ENTITY_GAPING_MAW] = true,
        [EntityType.ENTITY_BROKEN_GAPING_MAW] = true,
    }

    G.w, G.h, G.size = 0, 0, 0
    G.cost = {}       -- [cell] = move cost, nil = blocked
    G.rock = {}       -- [cell] = true for cells a bomb can clear
    G.fire = {}       -- [cell] = lit fireplace entity that tears can put out
    G.poop = {}       -- [cell] = true for poop, which tears break (no bomb needed)
    G.spike = {}      -- [cell] = true for spikes that hurt this player (a full heart on Hard)
    G.spikeDown = {}  -- [cell] = true for on/off spikes currently retracted (safe to cross)
    G.spikeUp = {}    -- [cell] = true for on/off spikes standing up right now
    G.spikePolarity = -1 -- this build reports State 0 while the spikes are UP (verified in game)
    G.hasOnOff = false   -- the room has retracting spikes (rebuild the grid more often)
    G.forceSpikes = false -- last resort: walk the spikes and eat the damage instead of stalling
    G.rockKind = {}   -- [cell] = GridEntityType, so loot rocks can be told from plain ones

    -- A fireplace blocks and burns on contact only while lit; once put out it is a harmless
    -- pile you can walk over. White (4), blue (2) and purple (3) fires cannot be put out here,
    -- so they are never targeted by the sweep.
    local WHITE_FIRE = 4
    local BLUE_FIRE = 2
    local PURPLE_FIRE = 3
    function G.fireLit(e)
        return (B.try(function() return e.HitPoints end) or 0) > 1
    end
    function G.fireBreakable(e)
        return e.Variant ~= WHITE_FIRE and e.Variant ~= BLUE_FIRE and e.Variant ~= PURPLE_FIRE
    end
    G.builtAt = -1
    G.roomKey = nil

    -- Rock cells that pay for a bomb. Tinted and super tinted rocks hold a trinket or an item,
    -- gold rocks pay coins, pots / mushrooms / skulls minor pickups. `bombs` is the stock the
    -- bot wants in hand before spending one here (bombs also open bedrooms and doors).
    G.LOOT_ROCK = {}
    local function lootRock(t, value, bombs)
        if t then G.LOOT_ROCK[t] = {value = value, bombs = bombs} end
    end
    lootRock(GT.GRID_ROCKT, 9, 1)      -- tinted rock
    lootRock(GT.GRID_ROCK_SS, 11, 1)   -- super tinted rock, double rewards
    lootRock(GT.GRID_ROCK_GOLD, 5, 2)  -- gold rock

    function G.cellPos(i)
        local room = game:GetRoom()
        return room:GetGridPosition(i)
    end

    function G.cellOf(x, y)
        local room = game:GetRoom()
        return room:GetGridIndex(Vector(x, y))
    end

    function G.xy(i)
        return i % G.w, i // G.w
    end

    -- Rebuild the cost map. Cheap enough (<= 448 cells) to redo every few updates, which
    -- keeps it right after rocks break, doors open or spikes retract.
    function G.build(p, ents)
        local room = game:GetRoom()
        local w = room:GetGridWidth()
        local size = room:GetGridSize()
        G.w, G.size, G.h = w, size, size // w
        local flying = B.try(function() return p.CanFly end) and true or false
        G.flying = flying
        local cost, rock, fire, poop, spike, rockKind, spikeDown, spikeUp = {}, {}, {}, {}, {}, {}, {}, {}
        local hasOnOff = false
        for i = 0, size - 1 do
            local col = room:GetGridCollision(i)
            local ge = room:GetGridEntity(i)
            local gtype = ge and B.try(function() return ge:GetType() end) or 0
            local c
            if col == COLL.COLLISION_NONE or col == COLL.COLLISION_WALL_EXCEPT_PLAYER then
                c = 1
            elseif flying and col ~= COLL.COLLISION_WALL then
                c = 1.2
            end
            if c then
                if gtype == GT.GRID_SPIKES or gtype == GT.GRID_SPIKES_ONOFF then
                    if not flying then
                        if gtype == GT.GRID_SPIKES_ONOFF and G.forceSpikes then
                            hasOnOff = true  -- crossing anyway: no cost, the hits are accepted
                        elseif gtype == GT.GRID_SPIKES_ONOFF then
                            -- Retracting spikes: State 0 is UP in this build (verified in game),
                            -- non-zero is down. G.spikePolarity flips it without code changes.
                            -- The meaning is checked at run time in G.onHit, which marks the
                            -- cell under the bot as up when the spikes rise underneath it.
                            hasOnOff = true
                            local state = B.try(function() return ge.State end)
                            if state == nil then state = 1 end
                            local up
                            if (G.spikePolarity or 1) > 0 then up = (state ~= 0) else up = (state == 0) end
                            if up then
                                c = c + 60
                                spike[i] = true
                                spikeUp[i] = true
                            else
                                spikeDown[i] = true
                            end
                            if not G.spikeSample then
                                G.spikeSample = {state = state,
                                    timeout = B.try(function() return ge.Timeout end)}
                                B.event("spike_state", G.spikeSample)
                            end
                        else
                            c = c + 60
                            spike[i] = true
                        end
                    end
                elseif gtype == GT.GRID_SPIDERWEB then
                    c = c + 3
                elseif gtype == GT.GRID_TRAPDOOR or gtype == GT.GRID_STAIRS then
                    -- Walking over a trapdoor/crawlspace ends the floor; only the exit
                    -- logic may target it, and it does so by position, not by path cost.
                    c = c + 400
                elseif gtype == GT.GRID_PRESSURE_PLATE then
                    c = c + 0.5
                end
            elseif gtype == GT.GRID_ROCK or gtype == GT.GRID_ROCKT or gtype == GT.GRID_ROCK_ALT
                or gtype == GT.GRID_ROCK_ALT2 or gtype == GT.GRID_ROCK_BOMB or gtype == GT.GRID_POOP
                or gtype == GT.GRID_ROCK_SS or gtype == GT.GRID_ROCK_SPIKED or gtype == GT.GRID_ROCK_GOLD
                or gtype == GT.GRID_TNT then
                rock[i] = true
                rockKind[i] = gtype
                if gtype == GT.GRID_POOP then poop[i] = true end
            end
            cost[i] = c
        end
        -- Blocking entities.
        local burning = {}
        for _, e in ipairs(ents or {}) do
            if BLOCKING[e.Type] then
                local lit = true
                local isFire = e.Type == EntityType.ENTITY_FIREPLACE
                if isFire then lit = G.fireLit(e) end
                if lit then
                    local i = room:GetGridIndex(e.Position)
                    if i and i >= 0 then
                        cost[i] = nil
                        if isFire then burning[#burning + 1] = i end
                        if isFire and G.fireBreakable(e) then fire[i] = e end
                    end
                end
            elseif e.Type == EntityType.ENTITY_PICKUP then
                -- Chests are solid even after they are opened: without this the bot kept
                -- pushing an opened red chest around instead of walking around it.
                local v = e.Variant
                if v == PV.PICKUP_CHEST or v == PV.PICKUP_LOCKEDCHEST or v == PV.PICKUP_REDCHEST
                    or v == PV.PICKUP_ETERNALCHEST or v == PV.PICKUP_OLDCHEST
                    or v == PV.PICKUP_MEGACHEST or v == PV.PICKUP_BIGCHEST then
                    local i = room:GetGridIndex(e.Position)
                    if i and i >= 0 then cost[i] = nil end
                end
            end
        end
        -- Keep paths a cell away from lit fires where the room allows: brushing past one
        -- diagonally or getting knocked into it costs a heart (night 2026-10-16: 12 hits).
        for _, i in ipairs(burning) do
            local x, y = i % w, i // w
            for oy = -1, 1 do
                for ox = -1, 1 do
                    local nx, ny = x + ox, y + oy
                    local j = nx + ny * w
                    if nx >= 0 and nx < w and ny >= 0 and ny < G.h and cost[j] then
                        cost[j] = cost[j] + 4
                    end
                end
            end
        end
        G.cost, G.rock, G.fire, G.poop, G.spike = cost, rock, fire, poop, spike
        G.rockKind = rockKind
        G.spikeDown = spikeDown
        G.spikeUp = spikeUp
        G.hasOnOff = hasOnOff
        G.builtAt = B.st.tick
    end

    function G.walkable(i)
        return i ~= nil and i >= 0 and i < G.size and G.cost[i] ~= nil
    end

    -- Walkable test for a world position (used by steering and the dodge simulation).
    function G.walkableAt(x, y)
        local room = game:GetRoom()
        local i = room:GetGridIndex(Vector(x, y))
        if not i or i < 0 then return false end
        local c = G.cost[i]
        return c ~= nil and c < 50
    end

    -- ------------------------------------------------------------ Dijkstra flood

    local heap = {}
    local function push(h, n, item, pri)
        n = n + 1
        h[n] = {item, pri}
        local i = n
        while i > 1 do
            local parent = i // 2
            if h[parent][2] <= h[i][2] then break end
            h[parent], h[i] = h[i], h[parent]
            i = parent
        end
        return n
    end
    local function pop(h, n)
        local top = h[1]
        h[1] = h[n]
        h[n] = nil
        n = n - 1
        local i = 1
        while true do
            local l, r, s = i * 2, i * 2 + 1, i
            if l <= n and h[l][2] < h[s][2] then s = l end
            if r <= n and h[r][2] < h[s][2] then s = r end
            if s == i then break end
            h[s], h[i] = h[i], h[s]
            i = s
        end
        return top, n
    end

    local DIRS = {
        {1, 0, 1}, {-1, 0, 1}, {0, 1, 1}, {0, -1, 1},
        {1, 1, 1.414}, {1, -1, 1.414}, {-1, 1, 1.414}, {-1, -1, 1.414},
    }

    -- A hit landed while the bot stood on a spike it believed retracted: the state meaning
    -- is inverted (or the spikes rose underneath). Flip and rebuild; a hit from an enemy is
    -- not evidence about the floor.
    function G.onHit(source)
        if source and source.Entity then return end
        local p = B.player()
        local room = game:GetRoom()
        if not p then return end
        local i = room:GetGridIndex(p.Position)
        if i and i >= 0 and G.spikeDown and G.spikeDown[i] then
            -- The spikes rose under the bot: this cell is up NOW, whatever State said before.
            -- Marking one cell (not flipping the whole meaning) keeps a correct signal intact.
            if not G.spikeUp then G.spikeUp = {} end
            G.spikeUp[i] = true
            G.spikeDown[i] = nil
            G.builtAt = -1
            B.event("spike_hit", {cell = i})
        end
    end

    -- Direction from a cell standing on live spikes toward the nearest walkable cell that is
    -- not spiked. Returns {dx, dy} or nil.
    function G.spikeStepOff(cell)
        local x, y = G.xy(cell)
        for _, d in ipairs({{1, 0}, {-1, 0}, {0, 1}, {0, -1},
            {1, 1}, {1, -1}, {-1, 1}, {-1, -1}}) do
            local nx, ny = x + d[1], y + d[2]
            if nx >= 0 and nx < G.w and ny >= 0 and ny < G.h then
                local j = nx + ny * G.w
                if G.cost[j] and not (G.spikeUp and G.spikeUp[j]) then
                    return {d[1], d[2]}
                end
            end
        end
        return nil
    end

    -- True if a cell path steps on spikes.
    function G.pathHurts(path)
        for _, c in ipairs(path or {}) do
            if G.spike[c] then return true end
        end
        return false
    end

    -- extra[cell] adds dynamic cost (enemy proximity). rocksPassable / firePassable /
    -- poopPassable let the breaker see paths through rocks (bomb), lit fireplaces and poop
    -- (shoot) at a price.
    function G.flood(startCell, extra, rocksPassable, firePassable, poopPassable)
        local w, size, cost, rock = G.w, G.size, G.cost, G.rock
        local dist, prev = {}, {}
        if not startCell or startCell < 0 or startCell >= size then
            G.dist, G.prev = dist, prev
            return dist, prev
        end
        local function stepCost(i)
            local c = cost[i]
            if c == nil and poopPassable and G.poop[i] then c = 10 end
            if c == nil and rocksPassable and rock[i] then c = 25 end
            if c == nil and firePassable and G.fire[i] then c = 12 end
            if c == nil then return nil end
            if extra and extra[i] then c = c + extra[i] end
            return c
        end
        dist[startCell] = 0
        local h, n = heap, 0
        for k in pairs(h) do h[k] = nil end
        n = push(h, n, startCell, 0)
        while n > 0 do
            local top
            top, n = pop(h, n)
            local i, d = top[1], top[2]
            if d <= (dist[i] or math.huge) then
                local x, y = i % w, i // w
                for _, dd in ipairs(DIRS) do
                    local nx, ny = x + dd[1], y + dd[2]
                    if nx >= 0 and nx < w and ny >= 0 and ny < G.h then
                        local j = nx + ny * w
                        local c = stepCost(j)
                        -- Diagonals only when both orthogonal cells are really open (no corner
                        -- cutting). Not stepCost: with rocks/fires passable the path slipped
                        -- diagonally between a rock and a fire, through neither, so the
                        -- breaker found nothing to break and the bot stayed walled in.
                        if c and dd[3] > 1 then
                            if not cost[x + dd[1] + y * w] or not cost[x + (y + dd[2]) * w] then
                                c = nil
                            end
                        end
                        if c then
                            local nd = d + c * dd[3]
                            if nd < (dist[j] or math.huge) then
                                dist[j] = nd
                                prev[j] = i
                                n = push(h, n, j, nd)
                            end
                        end
                    end
                end
            end
        end
        G.dist, G.prev, G.start = dist, prev, startCell
        return dist, prev
    end

    -- Cell path from the flood start to `goal` (inclusive), or nil.
    function G.pathTo(goal, prev)
        prev = prev or G.prev
        local dist = G.dist
        if not goal or not dist[goal] then return nil end
        local path, i, guard = {}, goal, 0
        while i and guard < 1000 do
            table.insert(path, 1, i)
            if i == G.start then break end
            i = prev[i]
            guard = guard + 1
        end
        return path
    end

    -- Nearest reachable cell to a world position (the target itself may sit on a blocked
    -- cell: pedestals next to rocks, enemies over pits).
    function G.reachableNear(x, y, radius)
        local room = game:GetRoom()
        local i = room:GetGridIndex(Vector(x, y))
        if i and i >= 0 and G.dist[i] then return i end
        if not i or i < 0 then i = room:GetClampedGridIndex(Vector(x, y)) end
        local cx, cy = G.xy(i)
        local best, bestD
        radius = radius or 2
        for dy = -radius, radius do
            for dx = -radius, radius do
                local nx, ny = cx + dx, cy + dy
                if nx >= 0 and nx < G.w and ny >= 0 and ny < G.h then
                    local j = nx + ny * G.w
                    if G.dist[j] then
                        local d = G.dist[j] + (dx * dx + dy * dy) * 3
                        if not bestD or d < bestD then best, bestD = j, d end
                    end
                end
            end
        end
        return best
    end

    -- Straight segment clear for a body of radius r (samples along the line, checks a cell
    -- under the centre and both sides).
    function G.segmentClear(ax, ay, bx, by, r)
        local dx, dy = bx - ax, by - ay
        local len = math.sqrt(dx * dx + dy * dy)
        if len < 1 then return true end
        local nx, ny = -dy / len * r, dx / len * r
        local steps = math.ceil(len / 12)
        for s = 1, steps do
            local t = s / steps
            local x, y = ax + dx * t, ay + dy * t
            if not G.walkableAt(x, y) or not G.walkableAt(x + nx, y + ny)
                or not G.walkableAt(x - nx, y - ny) then
                return false
            end
        end
        return true
    end

    -- Steering point along a cell path: the farthest of the next few cells that can be
    -- reached in a straight line, so the bot cuts across open floor instead of zig-zagging.
    function G.steer(px, py, path, finalX, finalY)
        if not path or #path == 0 then return finalX, finalY end
        local room = game:GetRoom()
        -- Never aim past a spike that is up: cut the path at the last safe cell, so the bot
        -- walks up to the live spike and waits for it to retract instead of stepping on it.
        local stop = #path
        if not G.flying and not G.forceSpikes and G.spikeUp then
            for k = 2, #path do
                if G.spikeUp[path[k]] then stop = k - 1 break end
            end
        end
        local tx, ty
        local last = math.min(stop, 6)
        for k = last, 2, -1 do
            local pos = room:GetGridPosition(path[k])
            local x, y = pos.X, pos.Y
            if k == #path and finalX then x, y = finalX, finalY end
            if G.segmentClear(px, py, x, y, 11) then
                tx, ty = x, y
                break
            end
        end
        if not tx then
            local k = math.min(2, stop)
            local pos = room:GetGridPosition(path[k])
            tx, ty = pos.X, pos.Y
            if #path == 1 and finalX then tx, ty = finalX, finalY end
        end
        return tx, ty
    end
end
