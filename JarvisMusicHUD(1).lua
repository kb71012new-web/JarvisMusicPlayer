--[[
    J.A.R.V.I.S. AUDIO INTERFACE
    Iron Man style HUD music player for Roblox

    SETUP: put this in a LocalScript inside StarterPlayer > StarterPlayerScripts

    HOTKEYS
      M          show / hide HUD
      P          play / pause
      N / B      next / previous track
      Up / Down  volume
      T          cycle suit theme
      F          open FILES import panel
      C          open CREDITS
      Delete     EXIT (or click the red X) - fully unloads the script

    ADDING MUSIC (type into the box and press ADD or Enter)
      1234567890        -> Roblox audio asset ID
      rbxassetid://123  -> same thing
      file:song.mp3     -> local file from your executor's workspace folder
                           (only works where getcustomasset exists)
      FILES panel       -> browse workspace folders / paste a file path and SCAN
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer

-- optional local-file support (only exists in some environments)
local env = getfenv()
local getAsset = env.getcustomasset or env.getsynasset
local isFile = env.isfile

----------------------------------------------------------------
-- CONFIG
----------------------------------------------------------------
local THEMES = {
	{ "MARK III", Color3.fromRGB(0, 200, 255) },
	{ "MARK VII", Color3.fromRGB(255, 70, 60) },
	{ "HULKBUSTER", Color3.fromRGB(255, 190, 40) },
	{ "WAR MACHINE", Color3.fromRGB(110, 255, 160) },
	{ "STEALTH", Color3.fromRGB(190, 120, 255) },
}
local themeIndex = 1
local accent = THEMES[1][2]

-- Put your own uploaded audio IDs here: { name, id }
local STARTING_TRACKS = {
	-- { "My Song", 1234567890 },
}

----------------------------------------------------------------
-- HELPERS
----------------------------------------------------------------
local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do
		o[k] = v
	end
	o.Parent = parent
	return o
end

local accented = {}
local function acc(obj, prop)
	table.insert(accented, { obj, prop })
	obj[prop] = accent
	return obj
end

local function setTheme(i)
	themeIndex = i
	accent = THEMES[i][2]
	for _, a in ipairs(accented) do
		if a[1].Parent then
			a[1][a[2]] = accent
		end
	end
end

local function fmt(t)
	t = math.max(0, math.floor(t or 0))
	return string.format("%d:%02d", t // 60, t % 60)
end

local DARK = Color3.fromRGB(10, 30, 45)

-- everything we connect gets tracked so EXIT can fully unload the script
local alive = true
local conns = {}
local function track(c)
	table.insert(conns, c)
	return c
end
local unload -- defined once the sound exists

----------------------------------------------------------------
-- GUI ROOT
----------------------------------------------------------------
local old = player.PlayerGui:FindFirstChild("JarvisHUD")
if old then
	old:Destroy()
end

local gui = new("ScreenGui", {
	Name = "JarvisHUD",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, player.PlayerGui)

local main = new("CanvasGroup", {
	Name = "Main",
	Size = UDim2.fromOffset(520, 410),
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	BackgroundColor3 = Color3.fromRGB(4, 12, 20),
	BackgroundTransparency = 0.12,
	BorderSizePixel = 0,
	GroupTransparency = 1,
}, gui)
acc(new("UIStroke", { Thickness = 1.5, Transparency = 0.15 }, main), "Color")
new("UICorner", { CornerRadius = UDim.new(0, 4) }, main)

-- corner brackets
local function bracket(fx, fy)
	local ax, ay = fx and 1 or 0, fy and 1 or 0
	local h = new("Frame", {
		Size = UDim2.fromOffset(22, 3),
		AnchorPoint = Vector2.new(ax, ay),
		Position = UDim2.new(ax, 0, ay, 0),
		BorderSizePixel = 0,
	}, main)
	local v = new("Frame", {
		Size = UDim2.fromOffset(3, 22),
		AnchorPoint = Vector2.new(ax, ay),
		Position = UDim2.new(ax, 0, ay, 0),
		BorderSizePixel = 0,
	}, main)
	acc(h, "BackgroundColor3")
	acc(v, "BackgroundColor3")
end
bracket(false, false)
bracket(true, false)
bracket(false, true)
bracket(true, true)

-- animated scan line
local scan = new("Frame", {
	Size = UDim2.new(1, 0, 0, 2),
	BackgroundTransparency = 0.85,
	BorderSizePixel = 0,
	ZIndex = 10,
}, main)
acc(scan, "BackgroundColor3")
scan.Position = UDim2.fromScale(0, 0)
TweenService:Create(scan, TweenInfo.new(3.5, Enum.EasingStyle.Linear, Enum.EasingDirection.In, -1), {
	Position = UDim2.fromScale(0, 1),
}):Play()

local function label(parent, text, pos, size, textSize, align)
	local l = new("TextLabel", {
		BackgroundTransparency = 1,
		Text = text,
		Position = pos,
		Size = size,
		Font = Enum.Font.Code,
		TextSize = textSize,
		TextXAlignment = align or Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, parent)
	acc(l, "TextColor3")
	return l
end

local function button(parent, text, pos, size, cb)
	local b = new("TextButton", {
		Text = text,
		Position = pos,
		Size = size,
		BackgroundColor3 = DARK,
		BackgroundTransparency = 0.3,
		Font = Enum.Font.Code,
		TextSize = 14,
		AutoButtonColor = false,
		BorderSizePixel = 0,
	}, parent)
	acc(b, "TextColor3")
	acc(new("UIStroke", { Thickness = 1, Transparency = 0.5 }, b), "Color")
	b.MouseEnter:Connect(function()
		TweenService:Create(b, TweenInfo.new(0.12), { BackgroundTransparency = 0 }):Play()
	end)
	b.MouseLeave:Connect(function()
		TweenService:Create(b, TweenInfo.new(0.12), { BackgroundTransparency = 0.3 }):Play()
	end)
	b.MouseButton1Click:Connect(cb)
	return b
end

local function slider(parent, pos, size, init, cb)
	local bg = new("Frame", {
		Position = pos,
		Size = size,
		BackgroundColor3 = Color3.fromRGB(20, 40, 55),
		BorderSizePixel = 0,
	}, parent)
	local fill = new("Frame", { Size = UDim2.fromScale(init, 1), BorderSizePixel = 0 }, bg)
	acc(fill, "BackgroundColor3")
	local hit = new("TextButton", {
		Text = "",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, 14),
		Position = UDim2.fromOffset(0, -7),
	}, bg)
	local dragging = false
	local function setFromX(x)
		local a = math.clamp((x - bg.AbsolutePosition.X) / bg.AbsoluteSize.X, 0, 1)
		fill.Size = UDim2.fromScale(a, 1)
		cb(a)
	end
	hit.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			setFromX(i.Position.X)
		end
	end)
	track(UserInputService.InputChanged:Connect(function(i)
		if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
			setFromX(i.Position.X)
		end
	end))
	track(UserInputService.InputEnded:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end))
	return {
		set = function(a)
			if not dragging then
				fill.Size = UDim2.fromScale(math.clamp(a, 0, 1), 1)
			end
		end,
		force = function(a)
			fill.Size = UDim2.fromScale(math.clamp(a, 0, 1), 1)
		end,
	}
end

----------------------------------------------------------------
-- JARVIS NOTIFICATIONS (top of screen)
----------------------------------------------------------------
local notifHolder = new("Frame", {
	Name = "Notifs",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 12),
	Size = UDim2.fromOffset(360, 400),
	BackgroundTransparency = 1,
}, gui)
new("UIListLayout", {
	Padding = UDim.new(0, 6),
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	SortOrder = Enum.SortOrder.LayoutOrder,
}, notifHolder)

local toasts, toastOrder = {}, 0
local KIND_COLORS = {
	ok = Color3.fromRGB(90, 255, 150),
	warn = Color3.fromRGB(255, 200, 70),
	err = Color3.fromRGB(255, 90, 90),
}

local function notify(text, kind, duration)
	if not alive then
		return
	end
	duration = duration or 3.5
	local col = KIND_COLORS[kind] or accent
	text = text:sub(1, 1):upper() .. text:sub(2)
	toastOrder += 1

	local slot = new("Frame", {
		Size = UDim2.fromOffset(340, 46),
		BackgroundTransparency = 1,
		LayoutOrder = toastOrder,
	}, notifHolder)
	local card = new("CanvasGroup", {
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromOffset(0, -30),
		GroupTransparency = 1,
		BackgroundColor3 = Color3.fromRGB(4, 12, 20),
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
	}, slot)
	new("UIStroke", { Color = col, Thickness = 1.2, Transparency = 0.2 }, card)
	new("UICorner", { CornerRadius = UDim.new(0, 4) }, card)
	new("Frame", { Size = UDim2.new(0, 3, 1, 0), BackgroundColor3 = col, BorderSizePixel = 0 }, card)
	new("TextLabel", {
		BackgroundTransparency = 1,
		Text = "J.A.R.V.I.S.",
		Position = UDim2.fromOffset(12, 4),
		Size = UDim2.new(1, -18, 0, 12),
		Font = Enum.Font.Code,
		TextSize = 10,
		TextColor3 = col,
		TextTransparency = 0.15,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, card)
	new("TextLabel", {
		BackgroundTransparency = 1,
		Text = text,
		Position = UDim2.fromOffset(12, 16),
		Size = UDim2.new(1, -18, 0, 26),
		Font = Enum.Font.Code,
		TextSize = 13,
		TextColor3 = Color3.fromRGB(225, 245, 255),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
	}, card)
	local timer = new("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 2),
		BackgroundColor3 = col,
		BackgroundTransparency = 0.4,
		BorderSizePixel = 0,
	}, card)

	table.insert(toasts, slot)
	while #toasts > 4 do
		table.remove(toasts, 1):Destroy()
	end

	TweenService:Create(card, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.fromOffset(0, 0),
		GroupTransparency = 0,
	}):Play()
	TweenService:Create(timer, TweenInfo.new(duration, Enum.EasingStyle.Linear), {
		Size = UDim2.new(0, 0, 0, 2),
	}):Play()

	task.delay(duration, function()
		if not slot.Parent then
			return
		end
		TweenService:Create(card, TweenInfo.new(0.3), {
			Position = UDim2.fromOffset(0, -30),
			GroupTransparency = 1,
		}):Play()
		task.wait(0.3)
		local idx = table.find(toasts, slot)
		if idx then
			table.remove(toasts, idx)
		end
		slot:Destroy()
	end)
end

----------------------------------------------------------------
-- HEADER (drag handle)
----------------------------------------------------------------
local header = new("Frame", {
	Size = UDim2.new(1, 0, 0, 34),
	BackgroundTransparency = 1,
}, main)
label(header, "J.A.R.V.I.S. // AUDIO", UDim2.fromOffset(14, 0), UDim2.fromOffset(185, 34), 15)
local clock = label(header, "00:00:00", UDim2.new(1, -150, 0, 0), UDim2.fromOffset(96, 34), 14, Enum.TextXAlignment.Right)
local divider = new("Frame", {
	Position = UDim2.fromOffset(10, 34),
	Size = UDim2.new(1, -20, 0, 1),
	BackgroundTransparency = 0.5,
	BorderSizePixel = 0,
}, main)
acc(divider, "BackgroundColor3")

do
	local dragging, startPos, startMouse
	header.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			startPos = main.Position
			startMouse = i.Position
		end
	end)
	track(UserInputService.InputChanged:Connect(function(i)
		if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
			local d = i.Position - startMouse
			main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
		end
	end))
	track(UserInputService.InputEnded:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end))
end

----------------------------------------------------------------
-- ARC REACTOR
----------------------------------------------------------------
local reactor = new("Frame", {
	Position = UDim2.fromOffset(15, 44),
	Size = UDim2.fromOffset(150, 150),
	BackgroundTransparency = 1,
}, main)

local function ring(count, radius, tickSize, radial)
	local r = new("Frame", {
		Size = UDim2.fromOffset(150, 150),
		BackgroundTransparency = 1,
	}, reactor)
	for i = 1, count do
		local a = math.rad(i * 360 / count)
		local t = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = tickSize,
			Position = UDim2.fromOffset(75 + radius * math.sin(a), 75 - radius * math.cos(a)),
			Rotation = i * 360 / count + (radial and 0 or 0),
			BorderSizePixel = 0,
		}, r)
		acc(t, "BackgroundColor3")
	end
	return r
end

local ring1 = ring(36, 68, UDim2.fromOffset(2, 9), true)
local ring2 = ring(8, 52, UDim2.fromOffset(16, 4), false)

local ring3 = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromOffset(75, 75),
	Size = UDim2.fromOffset(78, 78),
	BackgroundTransparency = 1,
}, reactor)
new("UICorner", { CornerRadius = UDim.new(1, 0) }, ring3)
acc(new("UIStroke", { Thickness = 2, Transparency = 0.3 }, ring3), "Color")

local core = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromOffset(75, 75),
	Size = UDim2.fromOffset(40, 40),
	BackgroundColor3 = Color3.fromRGB(235, 252, 255),
	BorderSizePixel = 0,
}, reactor)
new("UICorner", { CornerRadius = UDim.new(1, 0) }, core)
local coreStroke = new("UIStroke", { Thickness = 4, Transparency = 0.1 }, core)
acc(coreStroke, "Color")

----------------------------------------------------------------
-- STATS PANEL
----------------------------------------------------------------
local statY = 200
local fpsL = label(main, "FPS   --", UDim2.fromOffset(18, statY), UDim2.fromOffset(150, 14), 13)
local pingL = label(main, "PING  --", UDim2.fromOffset(18, statY + 16), UDim2.fromOffset(150, 14), 13)
local spdL = label(main, "SPEED --", UDim2.fromOffset(18, statY + 32), UDim2.fromOffset(150, 14), 13)
local hpL = label(main, "SUIT   --", UDim2.fromOffset(18, statY + 48), UDim2.fromOffset(150, 14), 13)

local themeBtn
themeBtn = button(main, "SUIT: " .. THEMES[1][1], UDim2.fromOffset(15, 266), UDim2.fromOffset(150, 26), function()
	local n = themeIndex % #THEMES + 1
	setTheme(n)
	themeBtn.Text = "SUIT: " .. THEMES[n][1]
	notify("Suit configuration: " .. THEMES[n][1], "info", 2)
end)

----------------------------------------------------------------
-- NOW PLAYING + VISUALIZER
----------------------------------------------------------------
local RX, RW = 180, 325
local trackLbl = label(main, "NO TRACK LOADED", UDim2.fromOffset(RX, 44), UDim2.fromOffset(RW, 22), 17)
local statusLbl = label(main, "> standing by", UDim2.fromOffset(RX, 66), UDim2.fromOffset(RW, 16), 12)
statusLbl.TextTransparency = 0.2

local BAR_COUNT = 32
local barW = RW / BAR_COUNT
local barArea = new("Frame", {
	Position = UDim2.fromOffset(RX, 88),
	Size = UDim2.fromOffset(RW, 62),
	BackgroundTransparency = 1,
}, main)
local bars = {}
for i = 1, BAR_COUNT do
	local f = new("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, (i - 1) * barW, 1, 0),
		Size = UDim2.fromOffset(barW - 2, 2),
		BorderSizePixel = 0,
	}, barArea)
	acc(f, "BackgroundColor3")
	bars[i] = { f = f, h = 2 }
end

-- status typewriter
local msgToken = 0
local function say(text, kind)
	if kind then
		notify(text, kind)
	end
	msgToken += 1
	local my = msgToken
	task.spawn(function()
		for i = 1, #text do
			if my ~= msgToken then
				return
			end
			statusLbl.Text = "> " .. text:sub(1, i) .. "_"
			task.wait(0.014)
		end
		if my == msgToken then
			statusLbl.Text = "> " .. text
		end
	end)
end

----------------------------------------------------------------
-- AUDIO ENGINE
----------------------------------------------------------------
local sound = new("Sound", { Name = "JarvisSound", Volume = 0.5 }, SoundService)
local tracks = {}
local current = 0
local shuffle = false
local loop = false
local loadToken = 0

local refreshPlaylist -- forward declaration

local function playIndex(i)
	local t = tracks[i]
	if not t then
		return
	end
	current = i
	loadToken += 1
	local my = loadToken
	sound:Stop()
	sound.SoundId = t.src
	sound.TimePosition = 0
	sound.Looped = loop
	trackLbl.Text = string.upper(t.name)
	say("loading audio stream...")
	sound:Play()
	refreshPlaylist()
	task.delay(15, function()
		if my == loadToken and not sound.IsLoaded and sound.TimeLength == 0 then
			say("audio failed to load. asset may be private or invalid, sir.", "err")
		end
	end)
	task.spawn(function()
		local ok = pcall(function()
			if not sound.IsLoaded then
				sound.Loaded:Wait()
			end
		end)
		if ok and my == loadToken then
			say("now playing. enjoy, sir.")
			notify("Now playing: " .. t.name, "info")
		end
	end)
end

local function nextTrack(dir)
	if #tracks == 0 then
		return
	end
	local n
	if shuffle and #tracks > 1 then
		repeat
			n = math.random(1, #tracks)
		until n ~= current
	else
		n = ((current - 1 + dir) % #tracks) + 1
	end
	playIndex(n)
end

local function togglePlay()
	if #tracks == 0 then
		say("playlist is empty. add an audio ID or open FILES, sir.", "warn")
		return
	end
	if current == 0 then
		playIndex(1)
	elseif sound.IsPlaying then
		sound:Pause()
		say("paused.")
	else
		sound:Resume()
		say("resuming playback.")
	end
end

sound.Ended:Connect(function()
	if not loop then
		nextTrack(1)
	end
end)

local function baseName(p)
	return p:match("[^/\\]+$") or p
end

local function addTrack(raw, quiet)
	raw = (raw or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if raw == "" then
		return false
	end

	local lower = raw:lower()
	if lower:find("youtube") or lower:find("youtu.be") or lower:find("http") then
		say("roblox can't stream URLs. convert to mp3, upload it, use the ID.", "warn")
		return false
	end

	local fileName = raw:match("^[Ff][Ii][Ll][Ee]:(.+)$")
	if not fileName and isFile then
		-- a bare path to an existing file also works
		local okf, exists = pcall(isFile, raw)
		if okf and exists then
			fileName = raw
		end
	end

	if not fileName then
		local ext = raw:lower():match("%.(%w+)$")
		if ext == "mp3" or ext == "ogg" or ext == "wav" or ext == "flac" or ext == "m4a" or ext == "opus" then
			fileName = raw
		end
	end

	if fileName then
		fileName = fileName:gsub("^%s+", "")
		if not (getAsset and isFile) then
			say("local files aren't supported in this environment.", "err")
			return false
		end
		local okf, exists = pcall(isFile, fileName)
		if not (okf and exists) then
			say("file not found in workspace: " .. fileName .. " (check the folder and exact name)", "err")
			return false
		end
		local ok, asset = pcall(getAsset, fileName)
		if not ok then
			say("couldn't load that file.", "err")
			return false
		end
		table.insert(tracks, { name = (baseName(fileName):gsub("%.%w+$", "")), src = asset })
	else
		local id = raw:match("(%d+)")
		if not id then
			say("that doesn't look like an audio ID or file.", "warn")
			return false
		end
		table.insert(tracks, { name = "Track " .. id, src = "rbxassetid://" .. id })
	end

	refreshPlaylist()
	if not quiet then
		say("added to playlist (" .. #tracks .. " tracks).", "ok")
		if current == 0 then
			playIndex(#tracks)
		end
	end
	return true
end

----------------------------------------------------------------
-- EXIT / UNLOAD
----------------------------------------------------------------
function unload()
	if not alive then
		return
	end
	alive = false
	msgToken += 1
	loadToken += 1
	pcall(function()
		sound:Stop()
	end)
	for _, c in ipairs(conns) do
		pcall(function()
			c:Disconnect()
		end)
	end
	table.clear(conns)
	pcall(function()
		TweenService:Create(main, TweenInfo.new(0.25), { GroupTransparency = 1 }):Play()
	end)
	task.delay(0.3, function()
		pcall(function()
			sound:Destroy()
		end)
		pcall(function()
			gui:Destroy()
		end)
	end)
end

do
	local exit = new("TextButton", {
		Text = "X",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0, 17),
		Size = UDim2.fromOffset(34, 22),
		BackgroundColor3 = Color3.fromRGB(70, 15, 15),
		BackgroundTransparency = 0.3,
		Font = Enum.Font.Code,
		TextSize = 14,
		TextColor3 = Color3.fromRGB(255, 90, 90),
		AutoButtonColor = false,
		BorderSizePixel = 0,
	}, header)
	new("UIStroke", { Thickness = 1, Color = Color3.fromRGB(255, 90, 90), Transparency = 0.4 }, exit)
	exit.MouseEnter:Connect(function()
		TweenService:Create(exit, TweenInfo.new(0.12), { BackgroundTransparency = 0 }):Play()
	end)
	exit.MouseLeave:Connect(function()
		TweenService:Create(exit, TweenInfo.new(0.12), { BackgroundTransparency = 0.3 }):Play()
	end)
	exit.MouseButton1Click:Connect(unload)
end

local showPage -- "files" | "credits"

do
	local overlay = new("Frame", {
		Position = UDim2.fromOffset(10, 40),
		Size = UDim2.new(1, -20, 1, -50),
		BackgroundColor3 = Color3.fromRGB(4, 12, 20),
		BackgroundTransparency = 0.02,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 5,
	}, main)
	acc(new("UIStroke", { Thickness = 1, Transparency = 0.5 }, overlay), "Color")

	local pageFiles = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false }, overlay)
	local pageCredits = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false }, overlay)
	local openPage = nil

	local L = Enum.TextXAlignment.Left
	local C = Enum.TextXAlignment.Center

	------------------------------------------------------------
	-- FILES PAGE
	------------------------------------------------------------
	local listfiles = env.listfiles
	local isfolder = env.isfolder
	local canBrowse = (listfiles ~= nil) and (getAsset ~= nil)
	local AUDIO = { mp3 = true, ogg = true, wav = true, flac = true, m4a = true, opus = true }
	local currentDir = ""
	local listed = {}

	label(pageFiles, "// FILE IMPORT", UDim2.fromOffset(12, 8), UDim2.fromOffset(300, 20), 16)
	local info = label(pageFiles, "", UDim2.fromOffset(12, 30), UDim2.fromOffset(476, 30), 12)
	info.TextWrapped = true
	info.TextTruncate = Enum.TextTruncate.None
	info.TextYAlignment = Enum.TextYAlignment.Top
	info.TextTransparency = 0.2
	if canBrowse then
		info.Text = "Workspace browser online. Open a folder, click an audio file to import it, or paste a full file path and press SCAN."
	else
		info.Text = "File browser unavailable here. Roblox has no native file picker, so local files need an environment with listfiles + getcustomasset. In Studio, upload audio and use its ID."
	end

	local dirBox = new("TextBox", {
		Position = UDim2.fromOffset(12, 64),
		Size = UDim2.fromOffset(330, 26),
		BackgroundColor3 = DARK,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		Font = Enum.Font.Code,
		TextSize = 13,
		Text = "",
		PlaceholderText = "folder or file path (blank = workspace root)",
		PlaceholderColor3 = Color3.fromRGB(110, 140, 155),
		ClearTextOnFocus = false,
		TextXAlignment = L,
	}, pageFiles)
	new("UIPadding", { PaddingLeft = UDim.new(0, 8) }, dirBox)
	acc(dirBox, "TextColor3")
	acc(new("UIStroke", { Thickness = 1, Transparency = 0.5 }, dirBox), "Color")

	local fileList = new("ScrollingFrame", {
		Position = UDim2.fromOffset(12, 98),
		Size = UDim2.fromOffset(476, 190),
		BackgroundColor3 = DARK,
		BackgroundTransparency = 0.5,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
	}, pageFiles)
	acc(new("UIStroke", { Thickness = 1, Transparency = 0.6 }, fileList), "Color")
	new("UIListLayout", { Padding = UDim.new(0, 2) }, fileList)

	local countL = label(pageFiles, "", UDim2.fromOffset(122, 296), UDim2.fromOffset(250, 28), 12)
	countL.TextTransparency = 0.3

	local function addRow(text, cb, dim)
		local row = new("Frame", {
			Size = UDim2.new(1, -6, 0, 24),
			BackgroundColor3 = Color3.fromRGB(25, 70, 95),
			BackgroundTransparency = 0.8,
			BorderSizePixel = 0,
		}, fileList)
		local b = new("TextButton", {
			Text = "  " .. text,
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Font = Enum.Font.Code,
			TextSize = 13,
			TextXAlignment = L,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}, row)
		acc(b, "TextColor3")
		if dim then
			b.TextTransparency = 0.4
		end
		if cb then
			b.MouseButton1Click:Connect(function()
				cb()
			end)
		end
	end

	local scanPath
	function scanPath(path)
		path = (path or ""):gsub("^%s+", ""):gsub("%s+$", "")
		for _, c in ipairs(fileList:GetChildren()) do
			if c:IsA("Frame") then
				c:Destroy()
			end
		end
		listed = {}
		countL.Text = ""

		if not canBrowse then
			addRow("// no file access in this environment", nil, true)
			return
		end

		-- a path that points at one file = import it directly
		if path ~= "" and isFile then
			local okf, exists = pcall(isFile, path)
			if okf and exists then
				addTrack("file:" .. path)
				scanPath(currentDir)
				return
			end
		end

		local ok, entries = pcall(listfiles, path)
		if (not ok or type(entries) ~= "table") and path == "" then
			ok, entries = pcall(listfiles, ".")
		end
		if not ok or type(entries) ~= "table" then
			addRow("// cannot open: " .. (path == "" and "(root)" or path), nil, true)
			notify("Couldn't open that location.", "err")
			return
		end

		currentDir = path
		dirBox.Text = path

		local dirs, files = {}, {}
		for _, p in ipairs(entries) do
			local name = baseName(p)
			local okd, isd = pcall(isfolder or function()
				return false
			end, p)
			if okd and isd then
				table.insert(dirs, { name = name, path = p })
			else
				local ext = name:lower():match("%.(%w+)$")
				if ext and AUDIO[ext] then
					table.insert(files, { name = name, path = p })
				end
			end
		end
		local function byName(a, b)
			return a.name:lower() < b.name:lower()
		end
		table.sort(dirs, byName)
		table.sort(files, byName)
		listed = files

		if currentDir ~= "" then
			local up = currentDir:match("^(.*)[/\\][^/\\]+$") or ""
			addRow(".. (up one level)", function()
				scanPath(up)
			end)
		end
		for _, d in ipairs(dirs) do
			addRow("[+] " .. d.name, function()
				scanPath(d.path)
			end)
		end
		for _, f in ipairs(files) do
			addRow("> " .. f.name, function()
				if addTrack("file:" .. f.path) then
					notify("Imported: " .. f.name, "ok", 2.5)
				end
			end)
		end
		if #dirs == 0 and #files == 0 then
			addRow("// nothing here (looking for mp3 / ogg / wav / flac)", nil, true)
		end
		countL.Text = #files .. " audio file(s) in this folder"
	end

	dirBox.FocusLost:Connect(function(enter)
		if enter then
			scanPath(dirBox.Text)
		end
	end)
	button(pageFiles, "SCAN", UDim2.fromOffset(348, 64), UDim2.fromOffset(66, 26), function()
		scanPath(dirBox.Text)
	end)
	button(pageFiles, "ROOT", UDim2.fromOffset(420, 64), UDim2.fromOffset(68, 26), function()
		scanPath("")
	end)
	button(pageFiles, "ADD ALL", UDim2.fromOffset(12, 294), UDim2.fromOffset(100, 28), function()
		if #listed == 0 then
			notify("No audio files listed to import.", "warn")
			return
		end
		local wasEmpty = (current == 0)
		local n = 0
		for _, f in ipairs(listed) do
			if addTrack("file:" .. f.path, true) then
				n += 1
			end
		end
		if n > 0 then
			notify("Imported " .. n .. " track(s) into the playlist.", "ok")
			if wasEmpty then
				playIndex(#tracks - n + 1)
			end
		end
	end)
	label(pageFiles, "tip: files live in your executor's workspace folder", UDim2.fromOffset(12, 330), UDim2.fromOffset(380, 16), 11).TextTransparency = 0.45

	------------------------------------------------------------
	-- CREDITS PAGE
	------------------------------------------------------------
	local function line(text, y, size, align, dim, h)
		local l = label(pageCredits, text, UDim2.fromOffset(20, y), UDim2.new(1, -40, 0, h or (size + 6)), size, align or C)
		l.TextWrapped = true
		l.TextTruncate = Enum.TextTruncate.None
		l.TextYAlignment = Enum.TextYAlignment.Top
		if dim then
			l.TextTransparency = 0.45
		end
		return l
	end

	line("J.A.R.V.I.S. AUDIO INTERFACE", 14, 19)
	line("v2.0  //  MARK III SYSTEMS", 40, 12, C, true)
	local div = new("Frame", {
		Position = UDim2.fromOffset(60, 62),
		Size = UDim2.new(1, -120, 0, 1),
		BackgroundTransparency = 0.5,
		BorderSizePixel = 0,
	}, pageCredits)
	acc(div, "BackgroundColor3")

	line("CREATED BY", 72, 11, C, true)
	line("Claude  -  AI assistant by Anthropic", 86, 16)
	line("REQUESTED BY", 116, 11, C, true)
	line(player.DisplayName .. "  (@" .. player.Name .. ")", 130, 16)
	line("MODULES", 160, 11, C, true)
	line("ARC REACTOR  |  VISUALIZER  |  FILE BROWSER  |  NOTIFICATION CORE  |  SUIT THEMES", 174, 12, C, false, 34)
	line("HOTKEYS", 214, 11, C, true)
	line("M hide  |  P play  |  N / B next / prev  |  Up / Down volume  |  T theme  |  F files  |  C credits  |  Delete exit", 228, 12, C, false, 34)
	line("powered by 100% fictional arc reactor technology.", 280, 11, C, true)

	------------------------------------------------------------
	-- PAGE SWITCHING + HEADER BUTTONS
	------------------------------------------------------------
	function showPage(name)
		if openPage == name or name == nil then
			overlay.Visible = false
			openPage = nil
			return
		end
		openPage = name
		overlay.Visible = true
		pageFiles.Visible = (name == "files")
		pageCredits.Visible = (name == "credits")
		if name == "files" then
			scanPath(currentDir)
		end
	end

	button(pageCredits, "CLOSE", UDim2.fromOffset(200, 318), UDim2.fromOffset(100, 28), function()
		showPage(nil)
	end)
	button(pageFiles, "CLOSE", UDim2.fromOffset(388, 294), UDim2.fromOffset(100, 28), function()
		showPage(nil)
	end)

	local fb = button(header, "FILES", UDim2.fromOffset(204, 6), UDim2.fromOffset(52, 22), function()
		showPage("files")
	end)
	local cb = button(header, "CREDITS", UDim2.fromOffset(262, 6), UDim2.fromOffset(66, 22), function()
		showPage("credits")
	end)
	fb.TextSize = 12
	cb.TextSize = 12
end

----------------------------------------------------------------
-- PROGRESS + CONTROLS
----------------------------------------------------------------
local progress = slider(main, UDim2.fromOffset(RX, 160), UDim2.fromOffset(RW, 4), 0, function(a)
	if sound.TimeLength > 0 then
		sound.TimePosition = a * sound.TimeLength
	end
end)
local timeL = label(main, "0:00", UDim2.fromOffset(RX, 168), UDim2.fromOffset(100, 14), 12)
local timeR = label(main, "0:00", UDim2.fromOffset(RX + RW - 100, 168), UDim2.fromOffset(100, 14), 12, Enum.TextXAlignment.Right)

button(main, "<<", UDim2.fromOffset(RX, 190), UDim2.fromOffset(50, 30), function()
	nextTrack(-1)
end)
local playBtn = button(main, "PLAY", UDim2.fromOffset(RX + 55, 190), UDim2.fromOffset(70, 30), togglePlay)
button(main, ">>", UDim2.fromOffset(RX + 130, 190), UDim2.fromOffset(50, 30), function()
	nextTrack(1)
end)
local loopBtn
loopBtn = button(main, "LOOP", UDim2.fromOffset(RX + 185, 190), UDim2.fromOffset(70, 30), function()
	loop = not loop
	sound.Looped = loop
	notify(loop and "Loop engaged." or "Loop disengaged.", "info", 2)
	loopBtn.BackgroundTransparency = loop and 0 or 0.3
	loopBtn.BackgroundColor3 = loop and Color3.fromRGB(30, 80, 110) or DARK
end)
local shufBtn
shufBtn = button(main, "SHUF", UDim2.fromOffset(RX + 260, 190), UDim2.fromOffset(65, 30), function()
	shuffle = not shuffle
	notify(shuffle and "Shuffle engaged." or "Shuffle disengaged.", "info", 2)
	shufBtn.BackgroundColor3 = shuffle and Color3.fromRGB(30, 80, 110) or DARK
end)

label(main, "VOL", UDim2.fromOffset(RX, 230), UDim2.fromOffset(30, 14), 12)
local volPct = label(main, "50%", UDim2.fromOffset(RX + RW - 40, 230), UDim2.fromOffset(40, 14), 12, Enum.TextXAlignment.Right)
local volume = slider(main, UDim2.fromOffset(RX + 34, 235), UDim2.fromOffset(RW - 80, 4), 0.5, function(a)
	sound.Volume = a
	volPct.Text = math.floor(a * 100) .. "%"
end)

local function nudgeVolume(d)
	local v = math.clamp(sound.Volume + d, 0, 1)
	sound.Volume = v
	volume.force(v)
	volPct.Text = math.floor(v * 100) .. "%"
end

----------------------------------------------------------------
-- INPUT ROW + PLAYLIST
----------------------------------------------------------------
local box = new("TextBox", {
	Position = UDim2.fromOffset(RX, 264),
	Size = UDim2.fromOffset(RW - 75, 28),
	BackgroundColor3 = DARK,
	BackgroundTransparency = 0.3,
	BorderSizePixel = 0,
	Font = Enum.Font.Code,
	TextSize = 13,
	Text = "",
	PlaceholderText = "audio ID  or  file:song.mp3",
	PlaceholderColor3 = Color3.fromRGB(110, 140, 155),
	ClearTextOnFocus = false,
	TextXAlignment = Enum.TextXAlignment.Left,
}, main)
new("UIPadding", { PaddingLeft = UDim.new(0, 8) }, box)
acc(box, "TextColor3")
acc(new("UIStroke", { Thickness = 1, Transparency = 0.5 }, box), "Color")

local function submit()
	addTrack(box.Text)
	box.Text = ""
end
box.FocusLost:Connect(function(enter)
	if enter then
		submit()
	end
end)
button(main, "ADD", UDim2.fromOffset(RX + RW - 68, 264), UDim2.fromOffset(68, 28), submit)

local list = new("ScrollingFrame", {
	Position = UDim2.fromOffset(15, 304),
	Size = UDim2.new(1, -30, 0, 94),
	BackgroundColor3 = DARK,
	BackgroundTransparency = 0.5,
	BorderSizePixel = 0,
	ScrollBarThickness = 3,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, main)
acc(new("UIStroke", { Thickness = 1, Transparency = 0.6 }, list), "Color")
new("UIListLayout", { Padding = UDim.new(0, 2) }, list)

function refreshPlaylist()
	for _, c in ipairs(list:GetChildren()) do
		if c:IsA("Frame") then
			c:Destroy()
		end
	end
	if #tracks == 0 then
		local empty = new("Frame", { Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1 }, list)
		local l = label(empty, "  // playlist empty", UDim2.new(), UDim2.fromScale(1, 1), 12)
		l.TextTransparency = 0.4
		return
	end
	for i, t in ipairs(tracks) do
		local row = new("Frame", {
			Size = UDim2.new(1, -6, 0, 22),
			BackgroundColor3 = Color3.fromRGB(25, 70, 95),
			BackgroundTransparency = (i == current) and 0.4 or 1,
			BorderSizePixel = 0,
			LayoutOrder = i,
		}, list)
		local b = new("TextButton", {
			Text = (i == current and "> " or "  ") .. i .. ". " .. t.name,
			Size = UDim2.new(1, -24, 1, 0),
			BackgroundTransparency = 1,
			Font = Enum.Font.Code,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}, row)
		acc(b, "TextColor3")
		b.MouseButton1Click:Connect(function()
			playIndex(i)
		end)
		local x = new("TextButton", {
			Text = "x",
			Position = UDim2.new(1, -22, 0, 0),
			Size = UDim2.fromOffset(22, 22),
			BackgroundTransparency = 1,
			Font = Enum.Font.Code,
			TextSize = 14,
			TextColor3 = Color3.fromRGB(255, 90, 90),
		}, row)
		x.MouseButton1Click:Connect(function()
			table.remove(tracks, i)
			if i == current then
				sound:Stop()
				current = 0
				trackLbl.Text = "NO TRACK LOADED"
			elseif i < current then
				current -= 1
			end
			refreshPlaylist()
		end)
	end
end

for _, t in ipairs(STARTING_TRACKS) do
	table.insert(tracks, { name = t[1], src = "rbxassetid://" .. t[2] })
end
refreshPlaylist()

----------------------------------------------------------------
-- HOTKEYS
----------------------------------------------------------------
track(UserInputService.InputBegan:Connect(function(input, processed)
	if processed or input.UserInputType ~= Enum.UserInputType.Keyboard then
		return
	end
	local k = input.KeyCode
	if k == Enum.KeyCode.M then
		main.Visible = not main.Visible
	elseif k == Enum.KeyCode.P then
		togglePlay()
	elseif k == Enum.KeyCode.N then
		nextTrack(1)
	elseif k == Enum.KeyCode.B then
		nextTrack(-1)
	elseif k == Enum.KeyCode.Up then
		nudgeVolume(0.05)
	elseif k == Enum.KeyCode.Down then
		nudgeVolume(-0.05)
	elseif k == Enum.KeyCode.T then
		local n = themeIndex % #THEMES + 1
		setTheme(n)
		themeBtn.Text = "SUIT: " .. THEMES[n][1]
	notify("Suit configuration: " .. THEMES[n][1], "info", 2)
	elseif k == Enum.KeyCode.F then
		showPage("files")
	elseif k == Enum.KeyCode.C then
		showPage("credits")
	elseif k == Enum.KeyCode.Delete then
		unload()
	end
end))

----------------------------------------------------------------
-- ANIMATION / UPDATE LOOP
----------------------------------------------------------------
local t0 = os.clock()
local fpsAcc, fpsN, statTimer = 0, 0, 0

track(RunService.RenderStepped:Connect(function(dt)
	local t = os.clock() - t0
	local playing = sound.IsPlaying
	local norm = playing and math.clamp(sound.PlaybackLoudness / 450, 0, 1) or 0

	-- reactor
	ring1.Rotation += dt * (18 + norm * 90)
	ring2.Rotation -= dt * (30 + norm * 160)
	local s = 38 + norm * 16 + math.sin(t * 3) * 1.5
	core.Size = UDim2.fromOffset(s, s)
	coreStroke.Thickness = 3 + norm * 5

	-- visualizer (loudness-driven; Roblox exposes no FFT)
	for i, b in ipairs(bars) do
		local wave = 0.45 + 0.55 * math.abs(math.sin(t * 4 + i * 0.55) * math.cos(t * 2.3 + i * 0.31))
		local target
		if playing then
			target = 2 + norm * wave * 58
		else
			target = 2 + (math.sin(t * 1.5 + i * 0.4) * 0.5 + 0.5) * 4
		end
		b.h += (target - b.h) * math.min(dt * 14, 1)
		b.f.Size = UDim2.fromOffset(barW - 2, b.h)
	end

	-- progress / time
	if sound.TimeLength > 0 then
		progress.set(sound.TimePosition / sound.TimeLength)
		timeL.Text = fmt(sound.TimePosition)
		timeR.Text = fmt(sound.TimeLength)
	else
		progress.set(0)
		timeL.Text, timeR.Text = "0:00", "0:00"
	end
	playBtn.Text = playing and "PAUSE" or "PLAY"

	-- slow stats
	fpsAcc += dt
	fpsN += 1
	statTimer += dt
	if statTimer >= 0.3 then
		statTimer = 0
		local fps = math.floor(fpsN / fpsAcc + 0.5)
		fpsAcc, fpsN = 0, 0
		fpsL.Text = "FPS   " .. fps
		local ping = math.floor(player:GetNetworkPing() * 1000)
		pingL.Text = "PING  " .. ping .. " ms"
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if root then
			spdL.Text = string.format("SPEED %.0f st/s", root.AssemblyLinearVelocity.Magnitude)
		end
		if hum then
			hpL.Text = string.format("SUIT   %d%%", math.floor(hum.Health / math.max(hum.MaxHealth, 1) * 100))
		end
		clock.Text = os.date("%H:%M:%S")
	end
end))

----------------------------------------------------------------
-- BOOT SEQUENCE
----------------------------------------------------------------
task.spawn(function()
	local boot = new("TextLabel", {
		Size = UDim2.fromOffset(500, 120),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundTransparency = 1,
		Font = Enum.Font.Code,
		TextSize = 18,
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
	}, gui)
	acc(boot, "TextColor3")

	local lines = {
		"INITIALIZING J.A.R.V.I.S. ...",
		"LOADING AUDIO CORE ............ OK",
		"CALIBRATING ARC REACTOR ....... OK",
		"WELCOME BACK, " .. string.upper(player.DisplayName) .. ".",
	}
	local shown = ""
	for _, line in ipairs(lines) do
		for i = 1, #line do
			if not alive then
				boot:Destroy()
				return
			end
			boot.Text = shown .. line:sub(1, i) .. "_"
			task.wait(0.012)
		end
		shown ..= line .. "\n"
		boot.Text = shown
		task.wait(0.18)
	end
	task.wait(0.3)
	if not alive then
		boot:Destroy()
		return
	end
	TweenService:Create(boot, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
	TweenService:Create(main, TweenInfo.new(0.6), { GroupTransparency = 0 }):Play()
	task.wait(0.5)
	boot:Destroy()
	if not alive then
		return
	end
	say("all systems online. add an audio ID or import a file to begin, sir.", "ok")
end)
