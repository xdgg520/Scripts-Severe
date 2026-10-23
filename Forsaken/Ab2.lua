--!optimize 2

local services, insts, utils, vars = {}, {}, {}, {}

services.RunService = game:GetService("RunService")
services.Workspace  = game:GetService("Workspace")
services.Players    = game:GetService("Players")

insts.lp      = services.Players.LocalPlayer
insts.killers = services.Workspace.Players.Killers

_G.AutoBlock = type(_G.AutoBlock) == "table" and _G.AutoBlock or {}
local cfg = _G.AutoBlock
local ToggleKey = cfg.ToggleKey or "C"
local BlockKey  = cfg.BlockKey  or 0x51
local Range     = cfg.Range     or 14
local Range2    = cfg.Range2    or 24
local Delay     = cfg.Delay     or 0
local ShowRange = cfg.ShowRange or false
local ShowTarget = cfg.ShowTarget ~= false
local Range2_Angle_cos = math.cos(math.rad(70))

vars.enabled    = false
vars.lastC      = false
vars.cache      = {}
vars.snap       = {}
vars.cam        = nil
vars.tapPending = false
vars.lastTap    = 0

local killers = insts.killers:GetChildren()

local function refreshDrawData()
    vars.cam = services.Workspace.CurrentCamera
    local myChar = insts.lp.Character
    local myRoot = myChar and utils:getRoot(myChar)
    local myPos = myRoot and myRoot.Position
    local snap = {}
    for _, killer in ipairs(insts.killers:GetChildren()) do
        local root = utils:getRoot(killer)
        if root then
            local pos = root.Position
            local dist = 0
            if myPos then
                local dx, dy, dz = pos.X - myPos.X, pos.Y - myPos.Y, pos.Z - myPos.Z
                dist = math.sqrt(dx * dx + dy * dy + dz * dz)
            end
            snap[#snap + 1] = {
                pos = pos,
                inv = killer:GetAttribute("Invincible"),
                dist = dist,
            }
        end
    end
    vars.snap = snap
end

task.spawn(function()
    local printed = false
    while true do
        task.wait(0.1)
        local ok, err = pcall(function()
            killers = insts.killers:GetChildren()
            refreshDrawData()
        end)
        if not ok and not printed then
            printed = true
            print("dbg refresh err: " .. tostring(err))
        end
    end
end)

task.spawn(function()
    task.wait(2.5)
    if #vars.snap == 0 then
        local list = insts.killers:GetChildren()
        print("dbg snap=0 killers=" .. #list .. " cam=" .. tostring(vars.cam ~= nil))
        local k = list[1]
        if k then
            local names = {}
            for _, c in ipairs(k:GetChildren()) do names[#names + 1] = c.Name end
            print("dbg killer=" .. k.Name .. " class=" .. k.ClassName .. " children=" .. table.concat(names, ","))
        end
    end
end)

function utils:getRoot(model)
    if not model then return nil end
    return model:FindFirstChild("HumanoidRootPart")
        or model:FindFirstChild("RootPart")
        or model:FindFirstChild("Torso")
        or model:FindFirstChild("UpperTorso")
end

function utils:myRoot()
    local char = insts.lp.Character
    return char and self:getRoot(char)
end

function utils:distSq(a, b)
    return (a.X - b.X) ^ 2 + (a.Z - b.Z) ^ 2
end

function utils:getAttr(model, name)
    local value = model and model:GetAttribute(name)
    if type(value) == "number" then return value end
    if type(value) == "string" then
        local num = tonumber(value:match("%d+%.?%d*"))
        if num then return num end
    end
    return 0
end

function utils:tap(key)
    keypress(key)
    keyrelease(key)
end

function utils:islookme(killerRoot)
    local myPos = self:myRoot()
    if not myPos or not killerRoot then return false end

    local my = myPos.Position
    local kp = killerRoot.Position
    local dx, dz = my.X - kp.X, my.Z - kp.Z
    local m = math.sqrt(dx * dx + dz * dz)
    if m < 0.1 then return true end
    local nx, nz = dx / m, dz / m

    local look = killerRoot.CFrame.LookVector
    if look.X * nx + look.Z * nz >= Range2_Angle_cos then return true end

    local vel = killerRoot.AssemblyLinearVelocity or killerRoot.Velocity
    if vel then
        local vx, vz = vel.X, vel.Z
        local vm = math.sqrt(vx * vx + vz * vz)
        if vm >= 0.1 and (vx / vm) * nx + (vz / vm) * nz >= Range2_Angle_cos then
            return true
        end
    end

    return false
end

function utils:drawRange()
    local cam = vars.cam
    if not cam then return end

    local drawn = 0
    for _, e in ipairs(vars.snap) do
        if drawn >= 3 then break end
        if e.dist <= 60 then
            drawn = drawn + 1

            local isEnraged = e.inv
            local range = isEnraged and Range2 or Range
            local color = isEnraged and Color3.new(1, 0.86, 0) or Color3.new(0, 1, 0.3)
            local center = e.pos

            if ShowRange then
                    local segs = 18
                    local step = 6.28318 / segs
                    local pts = {}
                    local ok = true
                    for i = 0, segs do
                        local ang = i * step
                        local wpos = Vector3.new(
                            center.X + math.cos(ang) * range,
                            center.Y - 3,
                            center.Z + math.sin(ang) * range
                        )
                        local p, on = cam:WorldToScreenPoint(wpos)
                        if not on or p.X ~= p.X or p.Y ~= p.Y
                            or math.abs(p.X) > 20000 or math.abs(p.Y) > 20000 then
                            ok = false
                            break
                        end
                        pts[#pts + 1] = Vector2.new(p.X, p.Y)
                    end
                    if ok then
                        for i = 1, #pts - 1 do
                            DrawingImmediate.Line(pts[i], pts[i + 1], color, 1, 1)
                        end
                    end
            end

            if ShowTarget and vars.enabled then
                local headPos, onScreen = cam:WorldToScreenPoint(center + Vector3.new(0, 5, 0))
                if onScreen
                    and headPos.X == headPos.X and headPos.Y == headPos.Y
                    and math.abs(headPos.X) < 20000 and math.abs(headPos.Y) < 20000 then
                    DrawingImmediate.OutlinedText(
                        Vector2.new(headPos.X, headPos.Y),
                        18,
                        Color3.new(1, 0.2, 0.2),
                        1,
                        "Target",
                        true,
                        "Interum"
                    )
                end
            end
        end
    end
end

services.RunService.PostModel:Connect(function()

    killers = insts.killers:GetChildren()

    local cDown = false
    for _, key in getpressedkeys() do if key == ToggleKey then cDown = true; break end end

    if cDown and not vars.lastC then
        vars.enabled = not vars.enabled
        if not vars.enabled then vars.cache = {} end
    end
    vars.lastC = cDown
    if not vars.enabled then return end

    if #killers == 0 then return end

    local blocked = false
    local myPos = utils:myRoot()

    for _, killer in ipairs(killers) do
        local root = utils:getRoot(killer)
        if not root then break end

        local lastUsed = utils:getAttr(killer, "AbilityLastUsed")
        local cached   = vars.cache[killer]
        vars.cache[killer] = lastUsed

        if cached ~= nil and lastUsed ~= cached then
            local abilitiesUsed = utils:getAttr(killer, "AbilitiesUsed")
            local abilitiesCached = vars.cache[killer.Name .. "_ab"]
            vars.cache[killer.Name .. "_ab"] = abilitiesUsed

            if abilitiesCached == nil or abilitiesUsed == abilitiesCached then
                local range = killer:GetAttribute("Invincible") == 1 and Range2 or Range

                if myPos and utils:distSq(myPos.Position, root.Position) <= range * range then
                    if killer:GetAttribute("Invincible") == 1 then
                        if utils:islookme(root) then
                            blocked = true
                            break
                        end
                    else
                        blocked = true
                        break
                    end
                end
            end
        end
    end

    if blocked then
        local now = tick()
        if Delay > 0 then
            if not vars.tapPending then
                vars.tapPending = true
                task.delay(Delay, function()
                    vars.tapPending = false
                    if tick() - vars.lastTap >= 0.05 then
                        vars.lastTap = tick()
                        utils:tap(BlockKey)
                    end
                end)
            end
        else
            if now - vars.lastTap >= 0.05 then
                vars.lastTap = now
                utils:tap(BlockKey)
            end
        end
    end
end)

services.RunService.Render:Connect(function()
    utils:drawRange()
end)

print("ok")
