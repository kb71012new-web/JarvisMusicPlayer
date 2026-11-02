local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local VirtualUser = game:GetService("VirtualUser")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer

-- ===== Config =====
local NODE_NAME     = "Node"                  -- name of the Groups/Models to visit
local DELAY         = 1.5                     -- default seconds to wait at each node
local HEIGHT        = 3                       -- default studs above the node to land
local TOGGLE_KEY    = Enum.KeyCode.RightShift -- show/hide the GUI
local LOOK_KEY      = Enum.KeyCode.Y          -- default Auto Look keybind (rebind in the GUI)
local LOOK_MAX_DIST = 500                     -- only look at players closer than this
local LOOK_SPEED    = 0.5                     -- 1 = instant lock, lower = smoother
local TP_KEY        = Enum.KeyCode.T          -- default "TP Forward" keybind (rebind in the GUI)
local TP_STUDS      = 10                      -- default studs for the Movement teleports
-- ==================

local delayTime = DELAY
local heightStuds = HEIGHT
local lookKey = LOOK_KEY
local lookMaxDist = LOOK_MAX_DIST
local lookSpeed = LOOK_SPEED
local tpKey = TP_KEY
local tpStuds = TP_STUDS
local prediction = false -- lead the target (for delayed / projectile weapons)
local leadTime = 0.15    -- seconds ahead to aim (covers ping + weapon delay)
local projSpeed = 0      -- projectile speed in studs/sec (0 = ignore travel time)

----------------------------------------------------------------
-- Retro Roblox palette
----------------------------------------------------------------
local C = {
    Base   = Color3.fromRGB(99, 95, 98),     -- baseplate grey
    Stud   = Color3.fromRGB(126, 122, 125),  -- stud tiles
    Blue   = Color3.fromRGB(13, 105, 172),   -- bright blue
    Green  = Color3.fromRGB(40, 127, 71),    -- dark green
    Red    = Color3.fromRGB(196, 40, 28),    -- bright red
    Yellow = Color3.fromRGB(245, 205, 48),   -- new yeller
    Grey   = Color3.fromRGB(163, 162, 165),  -- medium stone grey
    Black  = Color3.fromRGB(0, 0, 0),
    White  = Color3.fromRGB(255, 255, 255),
}

local FULL_W, FULL_H, MINI_H = 669, 384, 40

----------------------------------------------------------------
-- Base GUI
----------------------------------------------------------------
local Gui = Instance.new("ScreenGui")
local Ui = Instance.new("Frame")

Gui.Parent = player:WaitForChild("PlayerGui")
Gui.Name = "Gui"
Gui.ResetOnSpawn = false
Gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling -- scripts get "Global" by default, which hid the title bar contents

Ui.Parent = Gui
Ui.Name = "Ui"
Ui.Draggable = true
Ui.AnchorPoint = Vector2.new(0.5, 0.5)
Ui.Size = UDim2.new(0, FULL_W, 0, FULL_H)
Ui.Position = UDim2.new(0.5, 0, 0.5, 0)
Ui.BackgroundColor3 = C.Base
Ui.BackgroundTransparency = 0
Ui.BorderSizePixel = 0
Ui.ClipsDescendants = true
Ui.Selectable = true
Ui.Visible = true
Ui.Active = true

local UIStroke = Instance.new("UIStroke")
UIStroke.Parent = Ui
UIStroke.Color = C.Black
UIStroke.Thickness = 3
UIStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

----------------------------------------------------------------
-- Stud background (grid of raised tiles, like a baseplate)
----------------------------------------------------------------
local Studs = Instance.new("Frame")
Studs.Parent = Ui
Studs.Name = "Studs"
Studs.BackgroundTransparency = 1
Studs.Size = UDim2.new(0, FULL_W, 0, FULL_H) -- fixed so minimizing doesn't reflow
Studs.ZIndex = 1

local StudGrid = Instance.new("UIGridLayout")
StudGrid.Parent = Studs
StudGrid.CellSize = UDim2.new(0, 20, 0, 20)
StudGrid.CellPadding = UDim2.new(0, 4, 0, 4)
StudGrid.SortOrder = Enum.SortOrder.LayoutOrder
StudGrid.HorizontalAlignment = Enum.HorizontalAlignment.Center
StudGrid.VerticalAlignment = Enum.VerticalAlignment.Center

for i = 1, 27 * 16 do
    local s = Instance.new("Frame")
    s.BackgroundColor3 = C.Stud
    s.BorderSizePixel = 0
    s.LayoutOrder = i
    local sc = Instance.new("UICorner")
    sc.CornerRadius = UDim.new(0, 6)
    sc.Parent = s
    s.Parent = Studs
end

----------------------------------------------------------------
-- Style helpers
----------------------------------------------------------------
local function outline(inst, thickness)
    local stroke = Instance.new("UIStroke")
    stroke.Color = C.Black
    stroke.Thickness = thickness or 2
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Parent = inst
end

-- Classic bevel: light strip on top, dark strip on the bottom
local function bevel(inst, h)
    h = h or 3
    local top = Instance.new("Frame")
    top.Name = "BevelTop"
    top.BackgroundColor3 = C.White
    top.BackgroundTransparency = 0.55
    top.BorderSizePixel = 0
    top.Size = UDim2.new(1, 0, 0, h)
    top.Position = UDim2.new(0, 0, 0, 0)
    top.Parent = inst

    local bottom = Instance.new("Frame")
    bottom.Name = "BevelBottom"
    bottom.BackgroundColor3 = C.Black
    bottom.BackgroundTransparency = 0.6
    bottom.BorderSizePixel = 0
    bottom.Size = UDim2.new(1, 0, 0, h)
    bottom.Position = UDim2.new(0, 0, 1, -h)
    bottom.Parent = inst
end

-- Title bar
local TitleBar = Instance.new("Frame")
TitleBar.Parent = Ui
TitleBar.Name = "TitleBar"
TitleBar.Size = UDim2.new(1, 0, 0, MINI_H)
TitleBar.BackgroundColor3 = C.Blue
TitleBar.BorderSizePixel = 0
TitleBar.ZIndex = 2
outline(TitleBar, 2)
bevel(TitleBar, 3)

local Title = Instance.new("TextLabel")
Title.Parent = TitleBar
Title.Name = "Title"
Title.BackgroundTransparency = 1
Title.Size = UDim2.new(0, 180, 1, 0)
Title.Position = UDim2.new(0, 14, 0, 0)
Title.Font = Enum.Font.ArialBold
Title.Text = "NODE TOOLS v4"
Title.TextColor3 = C.White
Title.TextSize = 20
Title.TextStrokeColor3 = C.Black
Title.TextStrokeTransparency = 0
Title.TextXAlignment = Enum.TextXAlignment.Left

-- Content holds all pages + the exit button (minimize hides all of it)
local Content = Instance.new("Frame")
Content.Parent = Ui
Content.Name = "Content"
Content.BackgroundTransparency = 1
Content.Position = UDim2.new(0, 0, 0, 45)
Content.Size = UDim2.new(1, 0, 1, -45)
Content.ZIndex = 2

local function makePage(name)
    local f = Instance.new("Frame")
    f.Parent = Content
    f.Name = name
    f.BackgroundTransparency = 1
    f.Size = UDim2.new(1, 0, 1, 0)
    return f
end

local PageUtility  = makePage("PageUtility")
local PageMovement = makePage("PageMovement")
local PageCombat   = makePage("PageCombat")
local PagePlayers  = makePage("PagePlayers")
PageMovement.Visible = false
PageCombat.Visible = false
PagePlayers.Visible = false

----------------------------------------------------------------
-- Widgets (all take a parent so they can live on any page)
----------------------------------------------------------------
local function paintToggle(btn, state)
    btn.BackgroundColor3 = state and C.Green or C.Grey
    btn.TextColor3 = state and C.White or C.Black
end

-- Returns the button and a setter that changes the look WITHOUT firing onChanged
local function makeToggle(parent, name, text, yPos, onChanged)
    local btn = Instance.new("TextButton")
    btn.Parent = parent
    btn.Name = name
    btn.Size = UDim2.new(0, 360, 0, 44)
    btn.Position = UDim2.new(0, 15, 0, yPos)
    btn.BorderSizePixel = 0
    btn.AutoButtonColor = false
    btn.Font = Enum.Font.ArialBold
    btn.TextSize = 18
    outline(btn, 2)
    bevel(btn, 3)

    local state = false
    local function refresh()
        btn.Text = text .. ": " .. (state and "ON" or "OFF")
        paintToggle(btn, state)
    end
    refresh()

    btn.MouseButton1Click:Connect(function()
        state = not state
        refresh()
        onChanged(state)
    end)

    return btn, function(newState)
        state = newState
        refresh()
    end
end

local function makeButton(parent, text, color, textColor)
    local b = Instance.new("TextButton")
    b.Parent = parent
    b.BackgroundColor3 = color
    b.BorderSizePixel = 0
    b.AutoButtonColor = true
    b.Font = Enum.Font.ArialBold
    b.Text = text
    b.TextColor3 = textColor or C.White
    b.TextSize = 16
    outline(b, 2)
    bevel(b, 3)
    return b
end

local function makeLabel(parent, text, x, y, w, h, size, align)
    local l = Instance.new("TextLabel")
    l.Parent = parent
    l.BackgroundTransparency = 1
    l.Position = UDim2.new(0, x, 0, y)
    l.Size = UDim2.new(0, w, 0, h)
    l.Font = Enum.Font.ArialBold
    l.Text = text
    l.TextColor3 = C.White
    l.TextSize = size or 16
    l.TextStrokeColor3 = C.Black
    l.TextStrokeTransparency = 0
    l.TextXAlignment = align or Enum.TextXAlignment.Left
    return l
end

local function makeInput(parent, y, labelText, x, labelW, boxW, getValue, setValue, minValue, maxValue)
    makeLabel(parent, labelText, x, y, labelW, 30)

    local box = Instance.new("TextBox")
    box.Parent = parent
    box.Position = UDim2.new(0, x + labelW, 0, y)
    box.Size = UDim2.new(0, boxW, 0, 30)
    box.BackgroundColor3 = C.White
    box.BorderSizePixel = 0
    box.Font = Enum.Font.Arial
    box.Text = tostring(getValue())
    box.TextColor3 = C.Black
    box.TextSize = 16
    box.ClearTextOnFocus = false
    outline(box, 2)

    box.FocusLost:Connect(function()
        local n = tonumber(box.Text)
        if n and n >= minValue and (not maxValue or n <= maxValue) then
            setValue(n)
        end
        box.Text = tostring(getValue())
    end)
end

-- Dark info panel with a multi-line label inside
local function makeInfoPanel(parent)
    local panel = Instance.new("Frame")
    panel.Parent = parent
    panel.Position = UDim2.new(0, 395, 0, 5)
    panel.Size = UDim2.new(0, 259, 0, 235)
    panel.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    panel.BorderSizePixel = 0
    outline(panel, 2)

    local label = Instance.new("TextLabel")
    label.Parent = panel
    label.BackgroundTransparency = 1
    label.Position = UDim2.new(0, 12, 0, 12)
    label.Size = UDim2.new(1, -24, 1, -24)
    label.Font = Enum.Font.ArialBold
    label.TextSize = 18
    label.TextColor3 = C.White
    label.TextWrapped = true
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextYAlignment = Enum.TextYAlignment.Top
    return label
end

-- Status label (Utility page)
local Status = makeLabel(PageUtility, "Status: Idle", 15, 300, 360, 26, 15)
local function setStatus(text)
    if Status and Status.Parent then
        Status.Text = "Status: " .. text
    end
end

----------------------------------------------------------------
-- Shared character helpers
----------------------------------------------------------------
local function getRoot()
    local char = player.Character or player.CharacterAdded:Wait()
    return char:FindFirstChild("HumanoidRootPart")
end

local function getRootNoWait()
    local char = player.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end

----------------------------------------------------------------
-- UTILITY: node helpers
----------------------------------------------------------------
local function getNodes()
    local nodes = {}
    for _, inst in ipairs(workspace:GetDescendants()) do
        if inst.Name == NODE_NAME and (inst:IsA("Model") or inst:IsA("Folder")) then
            table.insert(nodes, inst)
        end
    end
    return nodes
end

local function getNodeCFrame(node)
    if node:IsA("Model") then
        return node:GetPivot()
    end
    local part = node:FindFirstChildWhichIsA("BasePart", true)
    return part and part.CFrame or nil
end

local function teleportToNode(node)
    local cf = getNodeCFrame(node)
    local root = getRoot()
    if cf and root then
        root.CFrame = cf + Vector3.new(0, heightStuds, 0)
        return true
    end
    return false
end

----------------------------------------------------------------
-- UTILITY: auto-interact
----------------------------------------------------------------
local function promptPosition(prompt)
    local p = prompt.Parent
    if p:IsA("BasePart") then
        return p.Position
    elseif p:IsA("Attachment") then
        return p.WorldPosition
    elseif p:IsA("Model") then
        return p:GetPivot().Position
    end
    return nil
end

-- Nearest enabled prompt to the node's center (inside the node first,
-- then anything in the workspace within 30 studs of the node)
local function findNearestPrompt(node)
    local cf = getNodeCFrame(node)
    local center = cf and cf.Position
    if not center then
        local root = getRoot()
        center = root and root.Position
    end
    if not center then return nil end

    local best, bestDist
    local function consider(inst)
        if inst:IsA("ProximityPrompt") and inst.Enabled then
            local pos = promptPosition(inst)
            if pos then
                local d = (pos - center).Magnitude
                if not bestDist or d < bestDist then
                    best, bestDist = inst, d
                end
            end
        end
    end

    for _, inst in ipairs(node:GetDescendants()) do
        consider(inst)
    end

    if not best then
        for _, inst in ipairs(workspace:GetDescendants()) do
            consider(inst)
        end
        if bestDist and bestDist > 30 then
            best = nil
        end
    end

    return best
end

local function findClickDetector(node)
    for _, inst in ipairs(node:GetDescendants()) do
        if inst:IsA("ClickDetector") then
            return inst
        end
    end
    return nil
end

local function pressPrompt(prompt)
    if typeof(fireproximityprompt) == "function" then
        if pcall(fireproximityprompt, prompt) then
            return true
        end
    end
    -- fallback: hold the prompt manually
    return pcall(function()
        prompt:InputHoldBegin()
        task.wait(math.max(prompt.HoldDuration, 0) + 0.05)
        prompt:InputHoldEnd()
    end)
end

-- Returns a short result string for the status line, or nil if nothing was found
local function interactWithNode(node)
    local prompt = findNearestPrompt(node)
    if prompt then
        -- stand right next to the prompt so it is definitely in range
        local pos = promptPosition(prompt)
        local root = getRoot()
        if pos and root and (root.Position - pos).Magnitude > 8 then
            root.CFrame = CFrame.new(pos + Vector3.new(0, 3, 0))
            task.wait(0.15)
        end

        -- temporarily make it easy to trigger, then restore
        local oldHold = prompt.HoldDuration
        local oldDist = prompt.MaxActivationDistance
        local oldLos = prompt.RequiresLineOfSight
        pcall(function()
            prompt.HoldDuration = 0
            prompt.MaxActivationDistance = math.max(oldDist, 20)
            prompt.RequiresLineOfSight = false
        end)

        pressPrompt(prompt)
        task.wait(0.1)

        pcall(function()
            prompt.HoldDuration = oldHold
            prompt.MaxActivationDistance = oldDist
            prompt.RequiresLineOfSight = oldLos
        end)
        return "fired prompt"
    end

    local cd = findClickDetector(node)
    if cd and typeof(fireclickdetector) == "function" then
        pcall(fireclickdetector, cd)
        return "clicked"
    end

    return nil
end

----------------------------------------------------------------
-- UTILITY: node feature state
----------------------------------------------------------------
local teleporting = false
local autoInteract = false
local skipVisited = false
local runId = 0
local visited = {}
local setTeleportToggle -- assigned once the button exists

local function teleportLoop()
    runId += 1
    local myId = runId
    visited = {}

    local function active()
        return teleporting and runId == myId
    end

    while active() do
        local nodes = getNodes()
        local total = #nodes

        if total == 0 then
            setStatus("No nodes found")
            task.wait(1)
        else
            local didAny = false
            for i, node in ipairs(nodes) do
                if not active() then break end
                if node.Parent and not (skipVisited and visited[node]) then
                    if teleportToNode(node) then
                        visited[node] = true
                        didAny = true
                        setStatus(("Node %d/%d"):format(i, total))

                        if autoInteract then
                            task.wait(0.15) -- let the teleport register first
                            local result = interactWithNode(node)
                            setStatus(("Node %d/%d - %s"):format(i, total, result or "no prompt found"))
                        end

                        task.wait(delayTime)
                    end
                end
            end

            if active() and skipVisited and not didAny then
                setStatus("Done - all nodes visited")
                teleporting = false
                setTeleportToggle(false)
                break
            end
        end

        task.wait(0.3)
    end
end

-- Instant prompts
local originalHold = setmetatable({}, { __mode = "k" })
local promptConn

local function patchPrompt(inst)
    if inst:IsA("ProximityPrompt") then
        if originalHold[inst] == nil then
            originalHold[inst] = inst.HoldDuration
        end
        inst.HoldDuration = 0
    end
end

local function setInstantPrompts(on)
    if on then
        for _, inst in ipairs(workspace:GetDescendants()) do
            patchPrompt(inst)
        end
        promptConn = workspace.DescendantAdded:Connect(patchPrompt)
    else
        if promptConn then
            promptConn:Disconnect()
            promptConn = nil
        end
        for prompt, original in pairs(originalHold) do
            if prompt and prompt.Parent then
                prompt.HoldDuration = original
            end
        end
    end
end

-- Anti-AFK
local afkConn
local function setAntiAfk(on)
    if on then
        if not afkConn then
            afkConn = player.Idled:Connect(function()
                VirtualUser:CaptureController()
                VirtualUser:ClickButton2(Vector2.new())
            end)
        end
    elseif afkConn then
        afkConn:Disconnect()
        afkConn = nil
    end
end

----------------------------------------------------------------
-- MOVEMENT: teleport by studs, save/return position
----------------------------------------------------------------
local savedCFrame
local MoveInfo -- assigned when the Movement page is built

local function flatLook(root)
    local look = root.CFrame.LookVector
    local flat = Vector3.new(look.X, 0, look.Z)
    if flat.Magnitude < 0.01 then
        return Vector3.new(0, 0, -1)
    end
    return flat.Unit
end

-- sign = 1 forward, -1 back (stays level, ignores where you look up/down)
local function tpForward(sign)
    local root = getRootNoWait()
    if root then
        root.CFrame = root.CFrame + flatLook(root) * (tpStuds * sign)
    end
end

-- sign = 1 up, -1 down
local function tpVertical(sign)
    local root = getRootNoWait()
    if root then
        root.CFrame = root.CFrame + Vector3.new(0, tpStuds * sign, 0)
    end
end

local function fmtVec(v)
    return ("%d, %d, %d"):format(math.floor(v.X + 0.5), math.floor(v.Y + 0.5), math.floor(v.Z + 0.5))
end

local function updateMoveInfo()
    if not MoveInfo then return end
    local root = getRootNoWait()
    local posText = root and fmtVec(root.Position) or "n/a"
    local savedText = savedCFrame and fmtVec(savedCFrame.Position) or "none"
    MoveInfo.Text = "Position:\n" .. posText
        .. "\n\nSaved position:\n" .. savedText
        .. "\n\nStuds per teleport: " .. tostring(tpStuds)
end

----------------------------------------------------------------
-- COMBAT: Auto Look (camera follows the closest player's head)
----------------------------------------------------------------
local autoLook = false
local ignoreTeam = false
local lookBound = false
local lastInfo = 0
local InfoLabel -- assigned when the Combat page is built
local setLookToggle -- assigned when the Combat page is built

local spectating -- declared here so Auto Look can see it (used by the Players page too)

-- Ignore list: lowercase usernames / display names Auto Look skips completely
local ignoredNames = {}

local function isIgnored(plr)
    return ignoredNames[plr.Name:lower()] or ignoredNames[plr.DisplayName:lower()]
end

local IgnoreLabel -- assigned when the Combat page is built
local function refreshIgnoreLabel()
    if not IgnoreLabel then return end
    local list = {}
    for name in pairs(ignoredNames) do
        table.insert(list, name)
    end
    table.sort(list)
    IgnoreLabel.Text = #list > 0 and ("Ignored: " .. table.concat(list, ", ")) or "Ignored: none"
end

local function getClosestTarget()
    local root = getRootNoWait()
    if not root then return nil end

    local bestPlr, bestHead, bestDist, bestHum
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= player and not isIgnored(plr) and not (ignoreTeam and plr.Team ~= nil and plr.Team == player.Team) then
            local c = plr.Character
            local hum = c and c:FindFirstChildOfClass("Humanoid")
            local head = c and c:FindFirstChild("Head")
            if hum and head and hum.Health > 0 then
                local d = (head.Position - root.Position).Magnitude
                if d <= lookMaxDist and (not bestDist or d < bestDist) then
                    bestPlr, bestHead, bestDist, bestHum = plr, head, d, hum
                end
            end
        end
    end
    return bestPlr, bestHead, bestDist, bestHum
end

local function updateInfo(plr, dist, hum)
    if not InfoLabel then return end
    if not autoLook then
        local hint = lookKey and ("Press " .. lookKey.Name .. " to toggle it.") or "No keybind set."
        InfoLabel.Text = "Auto Look is OFF\n\n" .. hint
    elseif plr then
        local predText = prediction and ("ON, " .. tostring(leadTime) .. "s lead") or "OFF"
        InfoLabel.Text = ("Target: %s\nDistance: %s studs\nHealth: %s\nPrediction: %s"):format(
            plr.Name, tostring(math.floor(dist)), tostring(math.floor(hum.Health)), predText)
    else
        InfoLabel.Text = "Target: none"
    end
end

local function onLookRender()
    if spectating then return end -- don't fight the spectate camera

    local cam = workspace.CurrentCamera
    if not cam then return end

    local plr, head, dist, hum = getClosestTarget()
    if head then
        local aimPos = head.Position

        -- prediction: aim where the target WILL be (velocity * time ahead)
        if prediction then
            local hrp = head.Parent and head.Parent:FindFirstChild("HumanoidRootPart")
            local vel = hrp and hrp.AssemblyLinearVelocity or head.AssemblyLinearVelocity
            local t = leadTime + ((projSpeed > 0) and (dist / projSpeed) or 0)
            aimPos = aimPos + vel * t
        end

        local desired = CFrame.lookAt(cam.CFrame.Position, aimPos)
        if lookSpeed >= 1 then
            cam.CFrame = desired
        else
            cam.CFrame = cam.CFrame:Lerp(desired, lookSpeed)
        end
    end

    local now = os.clock()
    if now - lastInfo > 0.1 then
        lastInfo = now
        updateInfo(plr, dist, hum)
    end
end

local function setAutoLook(on)
    autoLook = on
    if on and not lookBound then
        RunService:BindToRenderStep("NodeToolsAutoLook", Enum.RenderPriority.Camera.Value + 1, onLookRender)
        lookBound = true
    elseif not on and lookBound then
        RunService:UnbindFromRenderStep("NodeToolsAutoLook")
        lookBound = false
    end
    updateInfo()
end

----------------------------------------------------------------
-- Rebindable key buttons (shared by Movement and Combat)
----------------------------------------------------------------
local listeningFor = nil -- nil, "look" or "tp"
local LookKeyButton, TpKeyButton

local function paintKeyButton(btn, label, key, id)
    if listeningFor == id then
        btn.Text = "Press key (Esc cancel, Bksp none)"
        btn.BackgroundColor3 = C.Yellow
        btn.TextColor3 = C.Black
    else
        btn.Text = label .. ": " .. (key and key.Name or "None") .. "  (click to change)"
        btn.BackgroundColor3 = C.Blue
        btn.TextColor3 = C.White
    end
end

local function refreshKeyButtons()
    if LookKeyButton then paintKeyButton(LookKeyButton, "Auto Look Key", lookKey, "look") end
    if TpKeyButton then paintKeyButton(TpKeyButton, "TP Forward Key", tpKey, "tp") end
end

local function makeKeyButton(parent, y, id)
    local b = makeButton(parent, "", C.Blue)
    b.Position = UDim2.new(0, 15, 0, y)
    b.Size = UDim2.new(0, 360, 0, 44)
    b.TextSize = 18
    b.MouseButton1Click:Connect(function()
        listeningFor = id
        refreshKeyButtons()
    end)
    return b
end

----------------------------------------------------------------
-- PAGE: UTILITY (toggles, inputs, node list)
----------------------------------------------------------------
local _, tpSetter = makeToggle(PageUtility, "TeleportToggle", "Teleport to Nodes", 5, function(on)
    teleporting = on
    if on then
        task.spawn(teleportLoop)
    else
        runId += 1 -- invalidates the running loop immediately
        setStatus("Idle")
    end
end)
setTeleportToggle = tpSetter

makeToggle(PageUtility, "AutoInteractToggle", "Auto Interact", 55, function(on)
    autoInteract = on
end)

makeToggle(PageUtility, "InstantPromptToggle", "Instant Prompt", 105, setInstantPrompts)

makeToggle(PageUtility, "SkipVisitedToggle", "Skip Visited Nodes", 155, function(on)
    skipVisited = on
end)

makeToggle(PageUtility, "AntiAfkToggle", "Anti-AFK", 205, setAntiAfk)

makeInput(PageUtility, 262, "Delay (s):", 15, 90, 80,
    function() return delayTime end,
    function(n) delayTime = n end,
    0.05)

makeInput(PageUtility, 262, "Height:", 200, 75, 80,
    function() return heightStuds end,
    function(n) heightStuds = n end,
    0)

local List = Instance.new("ScrollingFrame")
List.Parent = PageUtility
List.Name = "NodeList"
List.Position = UDim2.new(0, 395, 0, 5)
List.Size = UDim2.new(0, 259, 0, 235)
List.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
List.BorderSizePixel = 0
List.ScrollBarThickness = 6
List.ScrollBarImageColor3 = C.Grey
List.CanvasSize = UDim2.new(0, 0, 0, 0)
List.AutomaticCanvasSize = Enum.AutomaticSize.Y
outline(List, 2)

local ListLayout = Instance.new("UIListLayout")
ListLayout.Parent = List
ListLayout.Padding = UDim.new(0, 4)

local ListPadding = Instance.new("UIPadding")
ListPadding.Parent = List
ListPadding.PaddingTop = UDim.new(0, 6)
ListPadding.PaddingBottom = UDim.new(0, 6)
ListPadding.PaddingLeft = UDim.new(0, 6)
ListPadding.PaddingRight = UDim.new(0, 10)

local function refreshList()
    for _, child in ipairs(List:GetChildren()) do
        if child:IsA("TextButton") then
            child:Destroy()
        end
    end

    local nodes = getNodes()
    for i, node in ipairs(nodes) do
        local btn = Instance.new("TextButton")
        btn.Parent = List
        btn.Size = UDim2.new(1, 0, 0, 28)
        btn.BackgroundColor3 = C.Blue
        btn.BorderSizePixel = 0
        btn.Font = Enum.Font.ArialBold
        btn.Text = ("%d. %s"):format(i, node.Parent and node.Parent.Name or "?")
        btn.TextColor3 = C.White
        btn.TextSize = 14
        btn.LayoutOrder = i
        outline(btn, 1)
        bevel(btn, 2)

        btn.MouseButton1Click:Connect(function()
            if node.Parent then
                teleportToNode(node)
                setStatus(("Teleported to node %d"):format(i))
            else
                setStatus("Node no longer exists")
            end
        end)
    end

    setStatus(("Found %d node(s)"):format(#nodes))
end

local Refresh = makeButton(PageUtility, "Refresh Node List", C.Blue)
Refresh.Name = "Refresh"
Refresh.Position = UDim2.new(0, 395, 0, 248)
Refresh.Size = UDim2.new(0, 259, 0, 30)
Refresh.MouseButton1Click:Connect(refreshList)

refreshList()

----------------------------------------------------------------
-- PAGE: MOVEMENT
----------------------------------------------------------------
makeInput(PageMovement, 5, "Studs:", 15, 70, 90,
    function() return tpStuds end,
    function(n)
        tpStuds = n
        updateMoveInfo()
    end,
    0.1)

makeLabel(PageMovement, "<- distance for every TP below", 200, 5, 180, 30, 13)

local function moveButton(text, x, y, color, textColor, fn)
    local b = makeButton(PageMovement, text, color, textColor)
    b.Position = UDim2.new(0, x, 0, y)
    b.Size = UDim2.new(0, 175, 0, 44)
    b.TextSize = 18
    b.MouseButton1Click:Connect(fn)
    return b
end

moveButton("TP Forward", 15, 50, C.Blue, C.White, function() tpForward(1) end)
moveButton("TP Back", 200, 50, C.Blue, C.White, function() tpForward(-1) end)
moveButton("TP Up", 15, 100, C.Blue, C.White, function() tpVertical(1) end)
moveButton("TP Down", 200, 100, C.Blue, C.White, function() tpVertical(-1) end)

TpKeyButton = makeKeyButton(PageMovement, 155, "tp")

moveButton("Save Position", 15, 205, C.Green, C.White, function()
    local root = getRootNoWait()
    if root then
        savedCFrame = root.CFrame
        updateMoveInfo()
    end
end)

moveButton("Back to Saved", 200, 205, C.Yellow, C.Black, function()
    local root = getRootNoWait()
    if root and savedCFrame then
        root.CFrame = savedCFrame
    end
end)

MoveInfo = makeInfoPanel(PageMovement)
updateMoveInfo()

-- keep the position readout fresh while the Movement page is open
local lastMove = 0
local moveConn = RunService.Heartbeat:Connect(function()
    local now = os.clock()
    if now - lastMove > 0.2 and PageMovement.Visible and Content.Visible then
        lastMove = now
        updateMoveInfo()
    end
end)

----------------------------------------------------------------
-- PAGE: COMBAT (Auto Look)
----------------------------------------------------------------
local _, lookSetter = makeToggle(PageCombat, "AutoLookToggle", "Auto Look (Closest Head)", 5, setAutoLook)
setLookToggle = lookSetter

makeToggle(PageCombat, "IgnoreTeamToggle", "Ignore Teammates", 55, function(on)
    ignoreTeam = on
end)

makeToggle(PageCombat, "PredictionToggle", "Prediction (Lead Target)", 105, function(on)
    prediction = on
end)

LookKeyButton = makeKeyButton(PageCombat, 155, "look")

makeInput(PageCombat, 208, "Max Dist:", 15, 90, 80,
    function() return lookMaxDist end,
    function(n) lookMaxDist = n end,
    1)

makeInput(PageCombat, 208, "Speed:", 200, 65, 80,
    function() return lookSpeed end,
    function(n) lookSpeed = n end,
    0.01, 1)

makeInput(PageCombat, 243, "Lead (s):", 15, 90, 80,
    function() return leadTime end,
    function(n) leadTime = n end,
    0)

makeInput(PageCombat, 243, "Proj Spd:", 200, 75, 80,
    function() return projSpeed end,
    function(n) projSpeed = n end,
    0)

makeLabel(PageCombat, "Speed 1 = instant | Lead = secs ahead | Proj Spd 0 = off", 15, 280, 360, 20, 12)

InfoLabel = makeInfoPanel(PageCombat)
updateInfo()

-- Ignore list controls (type a username, press Enter or Add / Del; type it again to remove)
local IgnoreBox = Instance.new("TextBox")
IgnoreBox.Parent = PageCombat
IgnoreBox.Position = UDim2.new(0, 395, 0, 248)
IgnoreBox.Size = UDim2.new(0, 170, 0, 30)
IgnoreBox.BackgroundColor3 = C.White
IgnoreBox.BorderSizePixel = 0
IgnoreBox.Font = Enum.Font.Arial
IgnoreBox.PlaceholderText = "username to ignore"
IgnoreBox.Text = ""
IgnoreBox.TextColor3 = C.Black
IgnoreBox.TextSize = 14
IgnoreBox.ClearTextOnFocus = false
outline(IgnoreBox, 2)

local IgnoreBtn = makeButton(PageCombat, "Add / Del", C.Green)
IgnoreBtn.Position = UDim2.new(0, 571, 0, 248)
IgnoreBtn.Size = UDim2.new(0, 83, 0, 30)
IgnoreBtn.TextSize = 13

local function toggleIgnore()
    local typed = (IgnoreBox.Text:lower():gsub("^%s+", ""):gsub("%s+$", ""))
    if typed == "" then return end

    -- resolve partial names to a real player if one matches
    local key = typed
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= player and (plr.Name:lower():sub(1, #typed) == typed or plr.DisplayName:lower():sub(1, #typed) == typed) then
            key = plr.Name:lower()
            break
        end
    end

    -- typing a name that's already ignored removes it
    if ignoredNames[key] then
        ignoredNames[key] = nil
    else
        ignoredNames[key] = true
    end
    IgnoreBox.Text = ""
    refreshIgnoreLabel()
end
IgnoreBtn.MouseButton1Click:Connect(toggleIgnore)
IgnoreBox.FocusLost:Connect(function(enterPressed)
    if enterPressed then toggleIgnore() end
end)

IgnoreLabel = makeLabel(PageCombat, "", 395, 284, 259, 40, 12)
IgnoreLabel.TextWrapped = true
IgnoreLabel.TextYAlignment = Enum.TextYAlignment.Top
refreshIgnoreLabel()

refreshKeyButtons()

----------------------------------------------------------------
-- PAGE: PLAYERS (live list with HP, details, TP, spectate)
----------------------------------------------------------------
local rows = {}
local selectedPlayer
local DetailLabel
local PlayerCount
local SpectateBtn
local specConn

local function fmtNum(n)
    if n ~= n or math.abs(n) > 1e9 then
        return "inf"
    end
    return tostring(math.floor(n + 0.5))
end

local function stopSpectate()
    spectating = nil
    if specConn then
        specConn:Disconnect()
        specConn = nil
    end
    local cam = workspace.CurrentCamera
    local char = player.Character
    local myHum = char and char:FindFirstChildOfClass("Humanoid")
    if cam and myHum then
        cam.CameraType = Enum.CameraType.Custom
        cam.CameraSubject = myHum
    end
    if SpectateBtn then
        SpectateBtn.Text = "Spectate"
    end
end

-- Re-applies the camera every frame, so respawns / the game's camera script
-- can't knock it off the target
local function startSpectate(plr)
    if specConn then specConn:Disconnect() end
    spectating = plr
    SpectateBtn.Text = "Stop Spectating"

    specConn = RunService.RenderStepped:Connect(function()
        local cam = workspace.CurrentCamera
        local c = spectating and spectating.Character
        local hum = c and c:FindFirstChildOfClass("Humanoid")
        if cam and hum then
            if cam.CameraType ~= Enum.CameraType.Custom then
                cam.CameraType = Enum.CameraType.Custom
            end
            if cam.CameraSubject ~= hum then
                cam.CameraSubject = hum
            end
        end
    end)
end

local function updateDetail()
    if not DetailLabel then return end
    local plr = selectedPlayer
    if not plr or not plr.Parent then
        DetailLabel.Text = "Click a player in the list to see details."
        return
    end

    local char = plr.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local myRoot = getRootNoWait()

    local lines = {}
    local function add(s) table.insert(lines, s) end

    if plr.DisplayName ~= plr.Name then
        add(plr.DisplayName .. " (@" .. plr.Name .. ")")
    else
        add(plr.Name)
    end

    if hum then
        local pct = (hum.MaxHealth > 0 and hum.MaxHealth < 1e9) and (" (" .. fmtNum(hum.Health / hum.MaxHealth * 100) .. "%)") or ""
        add("HP: " .. fmtNum(hum.Health) .. " / " .. fmtNum(hum.MaxHealth) .. pct)
        add("WalkSpeed: " .. fmtNum(hum.WalkSpeed))
    else
        add("HP: no character")
    end

    if hrp and myRoot then
        add("Distance: " .. fmtNum((hrp.Position - myRoot.Position).Magnitude) .. " studs")
    end

    add("Team: " .. (plr.Team and plr.Team.Name or "none"))
    add("Account age: " .. tostring(plr.AccountAge) .. " days")

    local tool = char and char:FindFirstChildOfClass("Tool")
    add("Holding: " .. (tool and tool.Name or "nothing"))

    -- leaderstats (rank / level / cash etc.), first 5 values
    local stats = plr:FindFirstChild("leaderstats")
    if stats then
        local n = 0
        for _, v in ipairs(stats:GetChildren()) do
            if v:IsA("ValueBase") and n < 5 then
                n += 1
                add(v.Name .. ": " .. tostring(v.Value))
            end
        end
    end

    DetailLabel.Text = table.concat(lines, "\n")
end

local function updatePlayersUI()
    local myRoot = getRootNoWait()
    local count = 0

    for plr, row in pairs(rows) do
        count += 1
        local char = plr.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        local hrp = char and char:FindFirstChild("HumanoidRootPart")

        if hum then
            local hp, maxHp = hum.Health, hum.MaxHealth
            local ratio
            if maxHp > 1e9 or maxHp ~= maxHp then
                ratio = 1
            elseif maxHp > 0 then
                ratio = math.clamp(hp / maxHp, 0, 1)
            else
                ratio = 0
            end
            row.fill.Size = UDim2.new(ratio, 0, 1, 0)
            row.fill.BackgroundColor3 = Color3.fromRGB(196, 40, 28):Lerp(Color3.fromRGB(75, 200, 75), ratio)
            row.hp.Text = fmtNum(hp) .. " / " .. fmtNum(maxHp)
        else
            row.fill.Size = UDim2.new(0, 0, 1, 0)
            row.hp.Text = "no character"
        end

        local dist = (myRoot and hrp) and (hrp.Position - myRoot.Position).Magnitude or nil
        row.dist.Text = dist and (fmtNum(dist) .. " studs") or "-"
        row.btn.LayoutOrder = dist and math.floor(dist) or 999999 -- closest first
        row.btn.BackgroundColor3 = (plr == selectedPlayer) and C.Blue or Color3.fromRGB(45, 45, 45)
    end

    if PlayerCount then
        PlayerCount.Text = "Players in server: " .. tostring(count + 1)
    end

    -- only stop spectating if that player left (respawns are followed automatically)
    if spectating and not spectating.Parent then
        stopSpectate()
    end

    updateDetail()
end

local PlayerList = Instance.new("ScrollingFrame")
PlayerList.Parent = PagePlayers
PlayerList.Name = "PlayerList"
PlayerList.Position = UDim2.new(0, 15, 0, 5)
PlayerList.Size = UDim2.new(0, 360, 0, 278)
PlayerList.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
PlayerList.BorderSizePixel = 0
PlayerList.ScrollBarThickness = 6
PlayerList.ScrollBarImageColor3 = C.Grey
PlayerList.CanvasSize = UDim2.new(0, 0, 0, 0)
PlayerList.AutomaticCanvasSize = Enum.AutomaticSize.Y
outline(PlayerList, 2)

local PlayerLayout = Instance.new("UIListLayout")
PlayerLayout.Parent = PlayerList
PlayerLayout.Padding = UDim.new(0, 4)
PlayerLayout.SortOrder = Enum.SortOrder.LayoutOrder

local PlayerPadding = Instance.new("UIPadding")
PlayerPadding.Parent = PlayerList
PlayerPadding.PaddingTop = UDim.new(0, 6)
PlayerPadding.PaddingBottom = UDim.new(0, 6)
PlayerPadding.PaddingLeft = UDim.new(0, 6)
PlayerPadding.PaddingRight = UDim.new(0, 10)

local function addRow(plr)
    if plr == player or rows[plr] then return end

    local btn = Instance.new("TextButton")
    btn.Parent = PlayerList
    btn.Size = UDim2.new(1, 0, 0, 44)
    btn.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
    btn.BorderSizePixel = 0
    btn.AutoButtonColor = false
    btn.Text = ""
    outline(btn, 1)

    local nameLabel = Instance.new("TextLabel")
    nameLabel.Parent = btn
    nameLabel.BackgroundTransparency = 1
    nameLabel.Position = UDim2.new(0, 6, 0, 3)
    nameLabel.Size = UDim2.new(0.6, 0, 0, 18)
    nameLabel.Font = Enum.Font.ArialBold
    nameLabel.Text = plr.DisplayName
    nameLabel.TextColor3 = C.White
    nameLabel.TextSize = 14
    nameLabel.TextXAlignment = Enum.TextXAlignment.Left

    local distLabel = Instance.new("TextLabel")
    distLabel.Parent = btn
    distLabel.BackgroundTransparency = 1
    distLabel.Position = UDim2.new(0.6, 0, 0, 3)
    distLabel.Size = UDim2.new(0.4, -6, 0, 18)
    distLabel.Font = Enum.Font.Arial
    distLabel.Text = "-"
    distLabel.TextColor3 = C.Grey
    distLabel.TextSize = 13
    distLabel.TextXAlignment = Enum.TextXAlignment.Right

    local bar = Instance.new("Frame")
    bar.Parent = btn
    bar.Position = UDim2.new(0, 6, 0, 24)
    bar.Size = UDim2.new(1, -12, 0, 14)
    bar.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
    bar.BorderSizePixel = 0
    outline(bar, 1)

    local fill = Instance.new("Frame")
    fill.Parent = bar
    fill.Size = UDim2.new(1, 0, 1, 0)
    fill.BackgroundColor3 = Color3.fromRGB(75, 200, 75)
    fill.BorderSizePixel = 0

    local hpLabel = Instance.new("TextLabel")
    hpLabel.Parent = bar
    hpLabel.BackgroundTransparency = 1
    hpLabel.Size = UDim2.new(1, 0, 1, 0)
    hpLabel.Font = Enum.Font.ArialBold
    hpLabel.Text = ""
    hpLabel.TextColor3 = C.White
    hpLabel.TextSize = 12
    hpLabel.TextStrokeColor3 = C.Black
    hpLabel.TextStrokeTransparency = 0

    btn.MouseButton1Click:Connect(function()
        selectedPlayer = plr
        updatePlayersUI()
    end)

    rows[plr] = { btn = btn, fill = fill, hp = hpLabel, dist = distLabel }
end

local function removeRow(plr)
    local row = rows[plr]
    if row then
        row.btn:Destroy()
        rows[plr] = nil
    end
    if selectedPlayer == plr then
        selectedPlayer = nil
    end
    if spectating == plr then
        stopSpectate()
    end
end

PlayerCount = makeLabel(PagePlayers, "Players in server: 1", 15, 288, 360, 22, 14)

DetailLabel = makeInfoPanel(PagePlayers)
DetailLabel.TextSize = 15

local TpPlayerBtn = makeButton(PagePlayers, "TP to Player", C.Blue)
TpPlayerBtn.Position = UDim2.new(0, 395, 0, 248)
TpPlayerBtn.Size = UDim2.new(0, 125, 0, 30)
TpPlayerBtn.MouseButton1Click:Connect(function()
    local plr = selectedPlayer
    local char = plr and plr.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local root = getRootNoWait()
    if hrp and root then
        root.CFrame = hrp.CFrame * CFrame.new(0, 0, 4)
    end
end)

SpectateBtn = makeButton(PagePlayers, "Spectate", C.Yellow, C.Black)
SpectateBtn.Position = UDim2.new(0, 529, 0, 248)
SpectateBtn.Size = UDim2.new(0, 125, 0, 30)
SpectateBtn.TextSize = 13
SpectateBtn.MouseButton1Click:Connect(function()
    if spectating then
        stopSpectate()
    elseif selectedPlayer then
        startSpectate(selectedPlayer)
    end
end)

for _, plr in ipairs(Players:GetPlayers()) do
    addRow(plr)
end
local addedConn = Players.PlayerAdded:Connect(addRow)
local removingConn = Players.PlayerRemoving:Connect(removeRow)
updatePlayersUI()

-- refresh HP / distance while the Players page is open
local lastPlayersUpdate = 0
local playersConn = RunService.Heartbeat:Connect(function()
    local now = os.clock()
    if now - lastPlayersUpdate > 0.25 and PagePlayers.Visible and Content.Visible then
        lastPlayersUpdate = now
        updatePlayersUI()
    end
end)

----------------------------------------------------------------
-- Page tabs (title bar)
----------------------------------------------------------------
local pages = { PageUtility, PageMovement, PageCombat, PagePlayers }
local tabs = {}

local function showPage(n)
    for i, page in ipairs(pages) do
        page.Visible = (i == n)
    end
    for i, tab in ipairs(tabs) do
        tab.BackgroundColor3 = (i == n) and C.White or C.Grey
    end
end

local function makeTab(text, x, n)
    local tab = Instance.new("TextButton")
    tab.Parent = TitleBar
    tab.Name = "Tab" .. n
    tab.AnchorPoint = Vector2.new(0, 0.5)
    tab.Position = UDim2.new(0, x, 0.5, 0)
    tab.Size = UDim2.new(0, 85, 0, 26)
    tab.BorderSizePixel = 0
    tab.AutoButtonColor = false
    tab.Font = Enum.Font.ArialBold
    tab.Text = text
    tab.TextColor3 = C.Black
    tab.TextSize = 15
    outline(tab, 2)
    bevel(tab, 2)
    tab.MouseButton1Click:Connect(function()
        showPage(n)
    end)
    tabs[n] = tab
end

makeTab("Utility", 200, 1)
makeTab("Movement", 290, 2)
makeTab("Combat", 380, 3)
makeTab("Players", 470, 4)
showPage(1)

----------------------------------------------------------------
-- Minimize button
----------------------------------------------------------------
local Minimize = Instance.new("TextButton")
Minimize.Parent = TitleBar
Minimize.Name = "Minimize"
Minimize.AnchorPoint = Vector2.new(1, 0.5)
Minimize.Position = UDim2.new(1, -10, 0.5, 0)
Minimize.Size = UDim2.new(0, 30, 0, 26)
Minimize.BackgroundColor3 = C.Yellow
Minimize.BorderSizePixel = 0
Minimize.Font = Enum.Font.ArialBold
Minimize.Text = "-"
Minimize.TextColor3 = C.Black
Minimize.TextSize = 22
outline(Minimize, 2)
bevel(Minimize, 2)

local minimized = false
Minimize.MouseButton1Click:Connect(function()
    minimized = not minimized
    -- keep the top edge in place (Ui is anchored at its center)
    local shift = (FULL_H - MINI_H) / 2
    if minimized then
        Content.Visible = false
        Ui.Size = UDim2.new(0, FULL_W, 0, MINI_H)
        Ui.Position = Ui.Position - UDim2.new(0, 0, 0, shift)
        Minimize.Text = "+"
    else
        Ui.Size = UDim2.new(0, FULL_W, 0, FULL_H)
        Ui.Position = Ui.Position + UDim2.new(0, 0, 0, shift)
        Content.Visible = true
        Minimize.Text = "-"
    end
end)

----------------------------------------------------------------
-- Keybinds (hide/show GUI, Auto Look, TP Forward, rebinding)
----------------------------------------------------------------
local keyConn = UserInputService.InputBegan:Connect(function(input, gameProcessed)
    -- rebinding: the next key pressed becomes the chosen key
    if listeningFor then
        if input.UserInputType == Enum.UserInputType.Keyboard then
            if input.KeyCode ~= Enum.KeyCode.Escape then
                local newKey = input.KeyCode
                if newKey == Enum.KeyCode.Backspace then
                    newKey = nil -- Backspace = unbind (no key)
                end
                if listeningFor == "look" then
                    lookKey = newKey
                else
                    tpKey = newKey
                end
            end
            listeningFor = nil
            refreshKeyButtons()
            updateInfo()
        end
        return
    end

    if gameProcessed then return end

    if input.KeyCode == TOGGLE_KEY then
        Gui.Enabled = not Gui.Enabled
    elseif input.KeyCode == lookKey then
        local newState = not autoLook
        setLookToggle(newState) -- update the button look
        setAutoLook(newState)   -- actually turn it on/off
    elseif input.KeyCode == tpKey then
        tpForward(1)
    end
end)

----------------------------------------------------------------
-- Exit button (bottom right): stops everything and destroys the GUI
----------------------------------------------------------------
local Exit = makeButton(Content, "EXIT", C.Red)
Exit.Name = "Exit"
Exit.AnchorPoint = Vector2.new(1, 1)
Exit.Size = UDim2.new(0, 90, 0, 36)
Exit.Position = UDim2.new(1, -15, 1, -15)
Exit.TextSize = 18

Exit.MouseButton1Click:Connect(function()
    teleporting = false
    runId += 1
    setInstantPrompts(false)
    setAntiAfk(false)
    setAutoLook(false)
    stopSpectate() -- also disconnects the spectate loop
    moveConn:Disconnect()
    playersConn:Disconnect()
    addedConn:Disconnect()
    removingConn:Disconnect()
    keyConn:Disconnect()
    Gui:Destroy()
end)

print("[NodeTools] v4 loaded - tabs: Utility / Movement / Combat / Players")
