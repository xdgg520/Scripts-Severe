--[[ vt1022 ]]

--!optimize 2

-- /Locals
local services, insts, utils, vars = {}, {}, {}, {}

-- /Services
services.RunService = game:GetService("RunService")
services.Workspace  = game:GetService("Workspace")
services.Players    = game:GetService("Players")

-- /Instances
insts.lp      = services.Players.LocalPlayer
insts.killers = services.Workspace.Players.Killers

-- /Config
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

-- /Vars
vars.enabled    = false
vars.lastC     = false
vars.cache      = {}
vars.snap       = {}
vars.cam        = nil

-- /Killer list + draw snapshot (Instance access is banned inside the render event)
local killers = insts.killers:GetChildren()

local function refreshDrawData()
    vars.cam = services.Workspace.CurrentCamera
    local snap = {}
    for _, killer in ipairs(insts.killers:GetChildren()) do
        local root = utils:getRoot(killer)
        if root then
            snap[#snap + 1] = {
                pos = root.Position,
                inv = killer:GetAttribute("Invincible"),
            }
        end
    end
    vars.snap = snap
end

task.spawn(function()
    while true do
        task.wait(0.1)
        killers = insts.killers:GetChildren()
        refreshDrawData()
    end
end)

-- /Utils
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
    local toMe = (myPos.Position - killerRoot.Position) * Vector3.new(1, 0, 1)
    if toMe.Magnitude < 0.1 then return true end
    if killerRoot.CFrame.LookVector:Dot(toMe.Unit) >= Range2_Angle_cos then return true end
    local vel = killerRoot.AssemblyLinearVelocity or killerRoot.Velocity
    if vel then
        local flat = Vector3.new(vel.X, 0, vel.Z)
        if flat.Magnitude >= 0.1 and flat.Unit:Dot(toMe.Unit) >= Range2_Angle_cos then return true end
    end
    return false
end

function utils:drawRange()
    local cam = vars.cam
    if not cam then return end

    for _, e in ipairs(vars.snap) do
        local isEnraged = e.inv
        local range = isEnraged and Range2 or Range
        local color = isEnraged and Color3.new(1, 0.86, 0) or Color3.new(0, 1, 0.3)
        local center = e.pos

            if ShowRange then
                local segs = 24
                local step = 6.2832 / segs
                local pts = {}
                for i = 0, segs do
                    local ang = i * step
                    local wpos = Vector3.new(
                        center.X + math.cos(ang) * range,
                        center.Y - 2.5,
                        center.Z + math.sin(ang) * range
                    )
                    local p, on = cam:WorldToScreenPoint(wpos)
                    if on then
                        pts[#pts + 1] = Vector2.new(p.X, p.Y)
                    end
                end
                if #pts > 1 then
                    DrawingImmediate.Polyline(pts, color, 0.6, 2)
                end
            end

            if ShowTarget then
                local headPos, onScreen = cam:WorldToScreenPoint(center + Vector3.new(0, 5, 0))
                if onScreen then
                    DrawingImmediate.OutlinedText(
                        Vector2.new(headPos.X, headPos.Y),
                        16,
                        Color3.new(1, 0.2, 0.2),
                        1,
                        "Target",
                        true,
                        "Tamzen"
                    )
                end
            end
    end
end

-- /Connections
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
        if Delay > 0 then
            task.delay(Delay, function()
                utils:tap(BlockKey)
            end)
        else
            utils:tap(BlockKey)
        end
    end
end)

services.RunService.Render:Connect(function()
    utils:drawRange()
end)

print("ok")
