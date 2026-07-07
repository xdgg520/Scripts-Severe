--!optimize 2

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local lp = Players.LocalPlayer
local gui = lp.PlayerGui.Main.Game

local ABS_POS = 0xf8   -- GuiBase2D.AbsolutePosition
local ABS_SIZE = 0x100 -- GuiBase2D.AbsoluteSize

local PRE_HIT_WINDOW = 210
local POST_HIT_WINDOW = 75
local X_WINDOW_MUL = 0.55

local TAP_HOLD_TIME = 0.025
local TAP_GAP_TIME = 0.003
local TAP_EXPIRE_TIME = 0.12

local BODY_WIDTH_MAX = 95
local BODY_MIN_HEIGHT = 35
local HOLD_RELEASE_PAD = 80

local enabled = false
local side = "left"
local lastF1 = false
local lastF2 = false

local keys = {
    [1] = 0x41, -- A
    [2] = 0x53, -- S
    [3] = 0x57, -- W
    [4] = 0x44, -- D
}

local keyDown = {}
local usedHeads = {}
local activeHolds = {}
local tapState = {}

for i = 1, 4 do
    keyDown[i] = false
    tapState[i] = {
        queue = {},
        phase = "idle",
        untilTime = 0,
    }
end

local function notify(msg)
    pcall(function()
        send_notification(msg, "info")
    end)
end

local function held(key)
    for _, k in getpressedkeys() do
        if k == key then return true end
    end
    return false
end

local function gx(o) return memory.readf32(o, ABS_POS) end
local function gy(o) return memory.readf32(o, ABS_POS + 4) end
local function gsx(o) return memory.readf32(o, ABS_SIZE) end
local function gsy(o) return memory.readf32(o, ABS_SIZE + 4) end

local function setKey(lane, down)
    if keyDown[lane] == down then return end
    keyDown[lane] = down
    if down then keypress(keys[lane]) else keyrelease(keys[lane]) end
end

local function isOurHead(cx)
    local ourMin, theirMin = math.huge, math.huge
    local ourStart, theirStart = side == "left" and 0 or 4, side == "left" and 4 or 0
    for i = ourStart, ourStart + 3 do
        local s = gui:FindFirstChild("Strum"..i)
        if s then
            local d = math.abs(cx - (gx(s) + gsx(s) / 2))
            if d < ourMin then ourMin = d end
        end
    end
    for i = theirStart, theirStart + 3 do
        local s = gui:FindFirstChild("Strum"..i)
        if s then
            local d = math.abs(cx - (gx(s) + gsx(s) / 2))
            if d < theirMin then theirMin = d end
        end
    end
    return ourMin <= theirMin
end

local function getStrums()
    if side == "left" then
        return { gui.Strum0, gui.Strum1, gui.Strum2, gui.Strum3 }
    end
    return { gui.Strum4, gui.Strum5, gui.Strum6, gui.Strum7 }
end

local function isVisible(obj)
    local ok, v = pcall(function() return obj.Visible end)
    return not ok or v ~= false
end

local function isObj(obj)
    if obj.ClassName ~= "ImageLabel" then return false end
    if obj.Parent ~= gui then return false end
    if obj.Name:find("Strum") or obj.Name:find("LaneBG") then return false end
    if not isVisible(obj) then return false end
    local ok, t = pcall(function() return obj.ImageTransparency end)
    if ok and t and t > 0.5 then return false end
    local w, h = gsx(obj), gsy(obj)
    return w > 8 and h > 8 and w <= 650 and h <= 2400
end

local function isHead(obj)
    local w, h = gsx(obj), gsy(obj)
    if w < 130 or h < 130 then return false end
    if w > 260 or h > 260 then return false end
    return true
end

local function isBody(obj)
    local w, h = gsx(obj), gsy(obj)
    return w <= BODY_WIDTH_MAX and h >= BODY_MIN_HEIGHT
end

local function Detect()
    local strums = {}
    for i = 0, 7 do
        local s = gui:FindFirstChild("Strum" .. i)
        if s then strums[#strums + 1] = s end
    end
    if #strums == 0 then return end
    local totalH = 0
    for _, s in ipairs(strums) do totalH = totalH + gsy(s) end
    local avgH = totalH / #strums
    PRE_HIT_WINDOW = avgH * 1.2
    POST_HIT_WINDOW = avgH * 0.5
    HOLD_RELEASE_PAD = avgH * 0.4
    for _, obj in ipairs(gui:GetChildren()) do
        if isObj(obj) and isHead(obj) then
            local hw = gsx(obj)
            BODY_WIDTH_MAX = hw * 0.45
            BODY_MIN_HEIGHT = hw * 0.15
            break
        end
    end
end

local function getLanes()
    local lanes = {}
    for lane, receptor in ipairs(getStrums()) do
        local x, y, w, h = gx(receptor), gy(receptor), gsx(receptor), gsy(receptor)
        lanes[lane] = { x = x, y = y, w = w, h = h, cx = x + w / 2 }
    end
    return lanes
end

local function pickLane(cx, lanes)
    local bestLane, bestDist = nil, math.huge
    for lane, info in pairs(lanes) do
        local d = math.abs(cx - info.cx)
        if d < bestDist then bestDist = d; bestLane = lane end
    end
    if bestLane and bestDist <= lanes[bestLane].w * X_WINDOW_MUL then return bestLane end
    return nil
end

local function findBody(head, lane, lanes)
    local info = lanes[lane]
    local hx, hy, hw, hh = gx(head), gy(head), gsx(head), gsy(head)
    local hcx = hx + hw / 2
    local headBottom = hy + hh
    local best, bestDist = nil, math.huge
    for _, obj in ipairs(gui:GetChildren()) do
        if obj ~= head and isObj(obj) and isBody(obj) then
            local x, y, w, h = gx(obj), gy(obj), gsx(obj), gsy(obj)
            local cx = x + w / 2
            if math.abs(cx - hcx) <= info.w * X_WINDOW_MUL then
                local bodyTop = y; local bodyBottom = y + h
                if bodyBottom >= hy - 120 and bodyTop <= headBottom + 320 then
                    local d = math.abs(bodyTop - headBottom)
                    if d < bestDist then bestDist = d; best = obj end
                end
            end
        end
    end
    return best
end

local function resetKeys()
    for lane = 1, 4 do
        setKey(lane, false)
        activeHolds[lane] = nil
        tapState[lane].queue = {}
        tapState[lane].phase = "idle"
    end
end

local function hotkeys()
    local f1 = held("F1"); local f2 = held("F2")
    if f1 and not lastF1 then
        enabled = not enabled
        if enabled then Detect() end
        notify(enabled and "enabled" or "disabled")
        if not enabled then resetKeys(); usedHeads = {} end
    end
    if f2 and not lastF2 then
        side = side == "left" and "right" or "left"; notify(side)
    end
    lastF1 = f1; lastF2 = f2
end

local function cleanUsed()
    for obj in pairs(usedHeads) do
        if not obj or not obj.Parent or not isVisible(obj) then usedHeads[obj] = nil end
    end
end

local function doTap(lane, head)
    if usedHeads[head] then return end
    usedHeads[head] = true
    tapState[lane].queue[#tapState[lane].queue + 1] = tick()
end

local function doHold(lane, head, body)
    if activeHolds[lane] then return end
    usedHeads[head] = true
    activeHolds[lane] = { body = body }
end

local function tapTick(lane, now)
    if activeHolds[lane] then return true end
    local st = tapState[lane]; local q = st.queue
    while #q > 0 and now - q[1] > TAP_EXPIRE_TIME do table.remove(q, 1) end
    if st.phase == "idle" then
        if #q > 0 then table.remove(q, 1); st.phase = "down"; st.untilTime = now + TAP_HOLD_TIME; return true end
        return false
    end
    if st.phase == "down" then
        if now < st.untilTime then return true end
        st.phase = "gap"; st.untilTime = now + TAP_GAP_TIME; return false
    end
    if st.phase == "gap" then
        if now < st.untilTime then return false end
        st.phase = "idle"
        if #q > 0 then
            table.remove(q, 1); st.phase = "down"; st.untilTime = now + TAP_HOLD_TIME; return true
        end
        return tapTick(lane, now)
    end
    st.phase = "idle"; return false
end

local function holdTick(lane, lanes)
    local st = activeHolds[lane]
    if not st then return false end
    local body = st.body; local info = lanes[lane]
    if not body or not body.Parent or not isVisible(body) then
        activeHolds[lane] = nil; return false
    end
    local y = gy(body); local h = gsy(body)
    if h < 10 or y + h <= info.y + HOLD_RELEASE_PAD then
        activeHolds[lane] = nil; return false
    end
    return true
end

RunService.PostModel:Connect(function()
    if isrbxactive and not isrbxactive() then return end
    hotkeys()
    if not enabled then return end
    local now = tick(); local lanes = getLanes(); cleanUsed()
    local candidates = { [1] = {}, [2] = {}, [3] = {}, [4] = {} }
    for _, obj in ipairs(gui:GetChildren()) do
        if isObj(obj) and isHead(obj) and not usedHeads[obj] then
            local x, y, w = gx(obj), gy(obj), gsx(obj)
            local cx = x + w / 2
            if isOurHead(cx) then
            local lane = pickLane(cx, lanes)
            if lane then
                local info = lanes[lane]; local dy = y - info.y
                if dy <= PRE_HIT_WINDOW and dy >= -POST_HIT_WINDOW then
                    candidates[lane][#candidates[lane] + 1] = { head = obj, dist = math.abs(dy) }
                end
            end
        end
    end
    end
    for lane, list in pairs(candidates) do
        table.sort(list, function(a, b) return a.dist < b.dist end)
        for _, item in ipairs(list) do
            local body = findBody(item.head, lane, lanes)
            if body then doHold(lane, item.head, body) else doTap(lane, item.head) end
        end
    end
    for lane = 1, 4 do
        local holdDown = holdTick(lane, lanes)
        local tapDown = tapTick(lane, now)
        setKey(lane, holdDown or tapDown)
    end
end)

Detect()
notify("ok")
