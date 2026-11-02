--[[
    J.A.R.V.I.S. AUDIO INTERFACE
    Iron Man style HUD music player for Roblox

    SETUP: put this in a LocalScript inside StarterPlayer > StarterPlayerScripts

    HOTKEYS
      M / orb    collapse / expand the HUD (animated)
      P          play / pause
      N / B      next / previous track
      Up / Down  volume
      T          cycle suit theme
      F          open FILES import panel
      C          open CREDITS
      K / L / Y / J  KEYS, PLAYERS, LAB and FUN tabs
      (every key can be rebound in the KEYS tab; Backspace = None)
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

local function applyAccent(c, prune)
	accent = c
	if prune then
		local live = {}
		for _, a in ipairs(accented) do
			if a[1]:IsDescendantOf(game) then
				a[1][a[2]] = accent
				table.insert(live, a)
			end
		end
		accented = live
	else
		for _, a in ipairs(accented) do
			a[1][a[2]] = accent
		end
	end
end

local function setTheme(i)
	themeIndex = i
	applyAccent(THEMES[i][2], true)
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
local cleanupFns = {} -- functions run on EXIT
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

local notifLog = {}
local onLogged
local function logLine(text)
	table.insert(notifLog, os.date("%H:%M:%S") .. "  " .. text)
	if #notifLog > 40 then
		table.remove(notifLog, 1)
	end
	if onLogged then
		onLogged()
	end
end

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
	logLine(text)
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
local clock = label(header, "00:00:00", UDim2.new(1, -190, 0, 0), UDim2.fromOffset(96, 34), 14, Enum.TextXAlignment.Right)
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
	else
		logLine(text)
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
	for _, f in ipairs(cleanupFns) do
		pcall(f)
	end
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

local showPage -- "files" | "keys" | "players" | "lab" | "credits"

local BIND_LIST = {
	{ "toggle", "Collapse / expand HUD", Enum.KeyCode.M },
	{ "play", "Play / pause", Enum.KeyCode.P },
	{ "next", "Next track", Enum.KeyCode.N },
	{ "prev", "Previous track", Enum.KeyCode.B },
	{ "volup", "Volume up", Enum.KeyCode.Up },
	{ "voldown", "Volume down", Enum.KeyCode.Down },
	{ "theme", "Cycle suit theme", Enum.KeyCode.T },
	{ "files", "Open FILES tab", Enum.KeyCode.F },
	{ "keys", "Open KEYS tab", Enum.KeyCode.K },
	{ "players", "Open PLAYERS tab", Enum.KeyCode.L },
	{ "lab", "Open LAB tab", Enum.KeyCode.Y },
	{ "fun", "Open FUN tab", Enum.KeyCode.J },
	{ "credits", "Open CREDITS tab", Enum.KeyCode.C },
	{ "exit", "Exit / unload script", Enum.KeyCode.Delete },
}
local BIND_LABEL, binds = {}, {}
for _, b in ipairs(BIND_LIST) do
	BIND_LABEL[b[1]] = b[2]
	binds[b[1]] = b[3]
end
local rebindTarget = nil
local captureKey, refreshKeys

do
	local overlay = new("Frame", {
		Position = UDim2.fromOffset(10, 38),
		Size = UDim2.new(1, -20, 1, -46),
		BackgroundColor3 = Color3.fromRGB(4, 12, 20),
		BackgroundTransparency = 0.02,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 5,
	}, main)
	acc(new("UIStroke", { Thickness = 1, Transparency = 0.5 }, overlay), "Color")

	local pageFiles = new("Frame", { Position = UDim2.fromOffset(0, 34), Size = UDim2.new(1, 0, 1, -34), BackgroundTransparency = 1, Visible = false }, overlay)
	local pageCredits = new("Frame", { Position = UDim2.fromOffset(0, 34), Size = UDim2.new(1, 0, 1, -34), BackgroundTransparency = 1, Visible = false }, overlay)
	local openPage = nil

	local L = Enum.TextXAlignment.Left
	local C = Enum.TextXAlignment.Center
	local ON = Color3.fromRGB(30, 80, 110)
	local onOpen = {}
	local labApi = {} -- lets the FUN tab reuse LAB toys

	do
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

		onOpen.files = function()
			scanPath(currentDir)
		end
	end

	do
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
		line("ARC REACTOR  |  VISUALIZER  |  FILE BROWSER  |  KEYBINDS  |  PLAYER SCANNER  |  LAB + RADAR  |  FUN ZONE  |  NOTIFICATION CORE  |  SUIT THEMES", 174, 12, C, false, 34)
		line("HOTKEYS", 214, 11, C, true)
		line("Open the KEYS tab to view or rebind every shortcut.", 228, 12, C, false, 34)
		line("powered by 100% fictional arc reactor technology.", 280, 11, C, true)
	end

	------------------------------------------------------------
	-- KEYS / PLAYERS / LAB PAGES
	------------------------------------------------------------
	local PAGE_POS, PAGE_SIZE = UDim2.fromOffset(0, 34), UDim2.new(1, 0, 1, -34)
	local pageKeys = new("Frame", { Position = PAGE_POS, Size = PAGE_SIZE, BackgroundTransparency = 1, Visible = false }, overlay)
	local pagePlayers = new("Frame", { Position = PAGE_POS, Size = PAGE_SIZE, BackgroundTransparency = 1, Visible = false }, overlay)
	local pageLab = new("Frame", { Position = PAGE_POS, Size = PAGE_SIZE, BackgroundTransparency = 1, Visible = false }, overlay)
	local pageFun = new("Frame", { Position = PAGE_POS, Size = PAGE_SIZE, BackgroundTransparency = 1, Visible = false }, overlay)
	local function charParts(p)
		local char = p and p.Character
		if not char then
			return nil, nil
		end
		return char:FindFirstChildOfClass("Humanoid"), char:FindFirstChild("HumanoidRootPart")
	end

	do
		------------------------------------------------------------
		-- KEYBINDS PAGE
		------------------------------------------------------------
		label(pageKeys, "// KEYBINDS", UDim2.fromOffset(12, 8), UDim2.fromOffset(300, 20), 16)
		label(pageKeys, "Click a key, then press the new one. ESC cancels. BACKSPACE = None.", UDim2.fromOffset(12, 30), UDim2.fromOffset(476, 16), 12).TextTransparency = 0.25

		local keyList = new("ScrollingFrame", {
			Position = UDim2.fromOffset(12, 54),
			Size = UDim2.fromOffset(476, 232),
			BackgroundColor3 = DARK,
			BackgroundTransparency = 0.5,
			BorderSizePixel = 0,
			ScrollBarThickness = 3,
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
		}, pageKeys)
		acc(new("UIStroke", { Thickness = 1, Transparency = 0.6 }, keyList), "Color")
		new("UIListLayout", { Padding = UDim.new(0, 2) }, keyList)

		local keyButtons = {}
		for i, b in ipairs(BIND_LIST) do
			local row = new("Frame", { Size = UDim2.new(1, -6, 0, 26), BackgroundTransparency = 1, LayoutOrder = i }, keyList)
			label(row, b[2], UDim2.fromOffset(8, 0), UDim2.new(1, -160, 1, 0), 13)
			local kb = button(row, "", UDim2.new(1, -140, 0, 2), UDim2.fromOffset(132, 22), function()
				rebindTarget = b[1]
				refreshKeys()
				notify("Press a key for: " .. b[2], "info", 2)
			end)
			kb.TextSize = 12
			keyButtons[b[1]] = kb
		end

		function refreshKeys()
			for id, kb in pairs(keyButtons) do
				if rebindTarget == id then
					kb.Text = "[ PRESS KEY ]"
					kb.BackgroundColor3 = Color3.fromRGB(90, 70, 10)
				else
					kb.Text = (binds[id] == Enum.KeyCode.Unknown) and "NONE" or binds[id].Name
					kb.BackgroundColor3 = DARK
				end
			end
		end
		onOpen.keys = refreshKeys

		function captureKey(k)
			local id = rebindTarget
			if not id then
				return
			end
			if k == Enum.KeyCode.Escape then
				rebindTarget = nil
				refreshKeys()
				notify("Rebind cancelled.", "warn", 1.5)
				return
			end
			if k == Enum.KeyCode.Backspace then
				binds[id] = Enum.KeyCode.Unknown
				rebindTarget = nil
				refreshKeys()
				notify(BIND_LABEL[id] .. " unbound (None).", "warn", 2)
				return
			end
			if k == Enum.KeyCode.Unknown then
				return
			end
			for other, key in pairs(binds) do
				if other ~= id and key == k then
					binds[other] = binds[id] -- swap so nothing ends up unbound
					break
				end
			end
			binds[id] = k
			rebindTarget = nil
			refreshKeys()
			notify(BIND_LABEL[id] .. " -> " .. k.Name, "ok", 2)
		end

		button(pageKeys, "RESET DEFAULTS", UDim2.fromOffset(12, 294), UDim2.fromOffset(150, 28), function()
			for _, b in ipairs(BIND_LIST) do
				binds[b[1]] = b[3]
			end
			rebindTarget = nil
			refreshKeys()
			notify("Keybinds restored to defaults.", "ok", 2)
		end)
		refreshKeys()
	end

	do
		------------------------------------------------------------
		-- PLAYERS PAGE
		------------------------------------------------------------
		local selected = nil
		local filterText = ""

		local searchBox = new("TextBox", {
			Position = UDim2.fromOffset(10, 8),
			Size = UDim2.fromOffset(170, 24),
			BackgroundColor3 = DARK,
			BackgroundTransparency = 0.3,
			BorderSizePixel = 0,
			Font = Enum.Font.Code,
			TextSize = 12,
			Text = "",
			PlaceholderText = "search players",
			PlaceholderColor3 = Color3.fromRGB(110, 140, 155),
			ClearTextOnFocus = false,
			TextXAlignment = L,
		}, pagePlayers)
		new("UIPadding", { PaddingLeft = UDim.new(0, 8) }, searchBox)
		acc(searchBox, "TextColor3")
		acc(new("UIStroke", { Thickness = 1, Transparency = 0.5 }, searchBox), "Color")

		local plist = new("ScrollingFrame", {
			Position = UDim2.fromOffset(10, 38),
			Size = UDim2.fromOffset(170, 286),
			BackgroundColor3 = DARK,
			BackgroundTransparency = 0.5,
			BorderSizePixel = 0,
			ScrollBarThickness = 3,
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
		}, pagePlayers)
		acc(new("UIStroke", { Thickness = 1, Transparency = 0.6 }, plist), "Color")
		new("UIListLayout", { Padding = UDim.new(0, 2) }, plist)

		local avatar = new("ImageLabel", {
			Position = UDim2.fromOffset(192, 8),
			Size = UDim2.fromOffset(96, 96),
			BackgroundColor3 = DARK,
			BackgroundTransparency = 0.3,
			BorderSizePixel = 0,
		}, pagePlayers)
		acc(new("UIStroke", { Thickness = 1.5, Transparency = 0.3 }, avatar), "Color")

		local pName = label(pagePlayers, "SELECT A PLAYER", UDim2.fromOffset(296, 8), UDim2.fromOffset(194, 24), 17)
		local pUser = label(pagePlayers, "", UDim2.fromOffset(296, 32), UDim2.fromOffset(194, 16), 12)
		pUser.TextTransparency = 0.35
		local hpBack = new("Frame", {
			Position = UDim2.fromOffset(296, 58),
			Size = UDim2.fromOffset(194, 8),
			BackgroundColor3 = Color3.fromRGB(20, 40, 55),
			BorderSizePixel = 0,
		}, pagePlayers)
		local hpFill = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.fromRGB(90, 255, 150), BorderSizePixel = 0 }, hpBack)
		local hpText = label(pagePlayers, "", UDim2.fromOffset(296, 70), UDim2.fromOffset(194, 16), 12)

		local ROW_KEYS = { "USER ID", "ACCOUNT AGE", "MEMBERSHIP", "TEAM", "WALKSPEED", "JUMP", "POSITION", "DISTANCE", "STATS" }
		local rowVals = {}
		for i, k in ipairs(ROW_KEYS) do
			local y = 116 + (i - 1) * 19
			label(pagePlayers, k, UDim2.fromOffset(192, y), UDim2.fromOffset(100, 18), 12).TextTransparency = 0.4
			rowVals[k] = label(pagePlayers, "--", UDim2.fromOffset(296, y), UDim2.fromOffset(194, 18), 12)
		end

		local function updateDetails()
			local p = selected
			if not p or not p.Parent then
				pName.Text = p and "PLAYER LEFT" or "SELECT A PLAYER"
				pUser.Text = ""
				hpText.Text = ""
				hpFill.Size = UDim2.fromScale(0, 1)
				for _, k in ipairs(ROW_KEYS) do
					rowVals[k].Text = "--"
				end
				return
			end
			pName.Text = p.DisplayName .. (p == player and " (you)" or "")
			pUser.Text = "@" .. p.Name
			rowVals["USER ID"].Text = tostring(p.UserId)
			rowVals["ACCOUNT AGE"].Text = p.AccountAge .. " days"
			rowVals["MEMBERSHIP"].Text = p.MembershipType.Name
			rowVals["TEAM"].Text = p.Team and p.Team.Name or "None"

			local hum, root = charParts(p)
			if hum then
				local frac = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
				hpFill.Size = UDim2.fromScale(frac, 1)
				hpFill.BackgroundColor3 = Color3.fromRGB(255, 70, 70):Lerp(Color3.fromRGB(90, 255, 150), frac)
				hpText.Text = string.format("HP  %d / %d", math.floor(hum.Health), math.floor(hum.MaxHealth))
				rowVals["WALKSPEED"].Text = string.format("%.1f", hum.WalkSpeed)
				rowVals["JUMP"].Text = hum.UseJumpPower and string.format("power %.1f", hum.JumpPower) or string.format("height %.1f", hum.JumpHeight)
			else
				hpFill.Size = UDim2.fromScale(0, 1)
				hpText.Text = "no character"
				rowVals["WALKSPEED"].Text = "--"
				rowVals["JUMP"].Text = "--"
			end

			if root then
				local pos = root.Position
				rowVals["POSITION"].Text = string.format("%d, %d, %d", pos.X, pos.Y, pos.Z)
				local _, myRoot = charParts(player)
				if p == player then
					rowVals["DISTANCE"].Text = "-- (you)"
				elseif myRoot then
					rowVals["DISTANCE"].Text = string.format("%.0f studs", (pos - myRoot.Position).Magnitude)
				else
					rowVals["DISTANCE"].Text = "--"
				end
			else
				rowVals["POSITION"].Text = "--"
				rowVals["DISTANCE"].Text = "--"
			end

			local ls = p:FindFirstChild("leaderstats")
			if ls then
				local parts = {}
				for _, v in ipairs(ls:GetChildren()) do
					if #parts < 3 and v:IsA("ValueBase") then
						table.insert(parts, v.Name .. ": " .. tostring(v.Value))
					end
				end
				rowVals["STATS"].Text = #parts > 0 and table.concat(parts, ", ") or "none"
			else
				rowVals["STATS"].Text = "none"
			end
		end

		local avatarToken = 0
		local function loadAvatar(p)
			avatarToken += 1
			local my = avatarToken
			avatar.Image = ""
			task.spawn(function()
				local ok, content = pcall(function()
					return Players:GetUserThumbnailAsync(p.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
				end)
				if ok and alive and my == avatarToken then
					avatar.Image = content
				end
			end)
		end

		local refreshList
		local function pick(p)
			selected = p
			refreshList()
			loadAvatar(p)
			updateDetails()
		end

		function refreshList()
			for _, c in ipairs(plist:GetChildren()) do
				if c:IsA("TextButton") then
					c:Destroy()
				end
			end
			local all = Players:GetPlayers()
			table.sort(all, function(a, b)
				return a.DisplayName:lower() < b.DisplayName:lower()
			end)
			local f = filterText:lower()
			for i, p in ipairs(all) do
				if f == "" or p.DisplayName:lower():find(f, 1, true) or p.Name:lower():find(f, 1, true) then
					local b = new("TextButton", {
						Size = UDim2.new(1, -6, 0, 24),
						LayoutOrder = i,
						BackgroundColor3 = Color3.fromRGB(25, 70, 95),
						BackgroundTransparency = (p == selected) and 0.3 or 0.85,
						BorderSizePixel = 0,
						Text = "  " .. p.DisplayName .. (p == player and " *" or ""),
						Font = Enum.Font.Code,
						TextSize = 13,
						TextXAlignment = L,
						TextTruncate = Enum.TextTruncate.AtEnd,
						AutoButtonColor = false,
					}, plist)
					acc(b, "TextColor3")
					b.MouseButton1Click:Connect(function()
						pick(p)
					end)
				end
			end
		end

		searchBox:GetPropertyChangedSignal("Text"):Connect(function()
			filterText = searchBox.Text
			refreshList()
		end)
		track(Players.PlayerAdded:Connect(function()
			if pagePlayers.Visible then
				refreshList()
			end
		end))
		track(Players.PlayerRemoving:Connect(function()
			task.defer(function()
				if alive and pagePlayers.Visible then
					refreshList()
				end
			end)
		end))

		onOpen.players = function()
			if not selected then
				pick(player)
			else
				refreshList()
				updateDetails()
			end
		end

		-- spectate (local camera only) + clipboard helpers
		local spectating = nil
		local specBtn
		local function stopSpec()
			if not spectating then
				return
			end
			spectating = nil
			local cam = workspace.CurrentCamera
			local hum = charParts(player)
			if cam and hum then
				cam.CameraSubject = hum
			end
			if specBtn then
				specBtn.Text = "SPECTATE"
			end
		end
		table.insert(cleanupFns, stopSpec)

		specBtn = button(pagePlayers, "SPECTATE", UDim2.fromOffset(192, 296), UDim2.fromOffset(98, 28), function()
			if spectating then
				stopSpec()
				notify("Camera restored.", "ok", 2)
				return
			end
			local p = selected
			if not p or p == player then
				notify("Pick another player first.", "warn", 2)
				return
			end
			local hum = charParts(p)
			local cam = workspace.CurrentCamera
			if not (hum and cam) then
				notify("That player has no character to follow.", "warn", 2)
				return
			end
			cam.CameraSubject = hum
			spectating = p
			specBtn.Text = "STOP SPEC"
			notify("Spectating " .. p.DisplayName, "ok", 2)
		end)
		specBtn.TextSize = 12

		local setclip = env.setclipboard or env.toclipboard
		local function copy(text, what)
			if setclip and selected then
				pcall(setclip, text)
				notify("Copied " .. what .. ".", "ok", 2)
			else
				notify("Clipboard isn't available here.", "warn", 2)
			end
		end
		button(pagePlayers, "COPY ID", UDim2.fromOffset(296, 296), UDim2.fromOffset(94, 28), function()
			if selected then
				copy(tostring(selected.UserId), "user ID")
			end
		end).TextSize = 12
		button(pagePlayers, "COPY NAME", UDim2.fromOffset(396, 296), UDim2.fromOffset(94, 28), function()
			if selected then
				copy(selected.Name, "username")
			end
		end).TextSize = 12

		local tPlayers = 0
		track(RunService.Heartbeat:Connect(function(dt)
			if spectating then
				local hum = charParts(spectating)
				local c = workspace.CurrentCamera
				if not spectating.Parent or not hum or not c or c.CameraSubject ~= hum then
					stopSpec()
				end
			end
			if not (overlay.Visible and main.Visible and pagePlayers.Visible) then
				return
			end
			tPlayers += dt
			if tPlayers >= 0.25 then
				tPlayers = 0
				updateDetails()
			end
		end))
	end

	do
		------------------------------------------------------------
		-- LAB PAGE (radar, camera / lighting toys, server info, log)
		------------------------------------------------------------
		local Lighting = game:GetService("Lighting")
		local RADAR_SIZE, RADAR_RANGE = 150, 120
		local sessionStart = os.clock()

		label(pageLab, "// LAB", UDim2.fromOffset(12, 8), UDim2.fromOffset(200, 20), 16)

		local radar = new("Frame", {
			Position = UDim2.fromOffset(14, 34),
			Size = UDim2.fromOffset(RADAR_SIZE, RADAR_SIZE),
			BackgroundColor3 = Color3.fromRGB(4, 20, 30),
			BackgroundTransparency = 0.2,
			BorderSizePixel = 0,
		}, pageLab)
		new("UICorner", { CornerRadius = UDim.new(1, 0) }, radar)
		acc(new("UIStroke", { Thickness = 2, Transparency = 0.2 }, radar), "Color")
		for _, f in ipairs({ 0.33, 0.66 }) do
			local r = new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(RADAR_SIZE * f, RADAR_SIZE * f),
				BackgroundTransparency = 1,
			}, radar)
			new("UICorner", { CornerRadius = UDim.new(1, 0) }, r)
			acc(new("UIStroke", { Thickness = 1, Transparency = 0.75 }, r), "Color")
		end
		local hLine = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, 0, 0, 1), BackgroundTransparency = 0.75, BorderSizePixel = 0 }, radar)
		local vLine = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0, 1, 1, 0), BackgroundTransparency = 0.75, BorderSizePixel = 0 }, radar)
		acc(hLine, "BackgroundColor3")
		acc(vLine, "BackgroundColor3")
		local sweep = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, radar)
		local sweepLine = new("Frame", { Position = UDim2.new(0.5, -1, 0, 0), Size = UDim2.new(0, 2, 0.5, 0), BackgroundTransparency = 0.35, BorderSizePixel = 0 }, sweep)
		acc(sweepLine, "BackgroundColor3")
		local me = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(7, 7),
			BackgroundColor3 = Color3.fromRGB(240, 255, 255),
			BorderSizePixel = 0,
		}, radar)
		new("UICorner", { CornerRadius = UDim.new(1, 0) }, me)

		local dots = {}
		for i = 1, 24 do
			local d = new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Size = UDim2.fromOffset(6, 6),
				BackgroundColor3 = Color3.fromRGB(255, 160, 60),
				BorderSizePixel = 0,
				Visible = false,
			}, radar)
			new("UICorner", { CornerRadius = UDim.new(1, 0) }, d)
			dots[i] = d
		end
		local contactsL = label(pageLab, "CONTACTS: 0", UDim2.fromOffset(14, 188), UDim2.fromOffset(160, 14), 12)

		local function updateRadar(dt)
			sweep.Rotation = (os.clock() * 110) % 360
			local cam = workspace.CurrentCamera
			local _, myRoot = charParts(player)
			local n, inRange = 0, 0
			if cam and myRoot then
				for _, p in ipairs(Players:GetPlayers()) do
					if p ~= player and n < #dots then
						local _, r = charParts(p)
						if r then
							n += 1
							local rel = cam.CFrame:VectorToObjectSpace(r.Position - myRoot.Position)
							local x, y = rel.X, rel.Z
							local dist = math.sqrt(x * x + y * y)
							local k = dist > 0 and (math.min(dist, RADAR_RANGE) / RADAR_RANGE) * (RADAR_SIZE / 2 - 6) / dist or 0
							local d = dots[n]
							d.Position = UDim2.fromOffset(RADAR_SIZE / 2 + x * k, RADAR_SIZE / 2 + y * k)
							d.BackgroundTransparency = dist > RADAR_RANGE and 0.65 or 0
							d.Visible = true
							if dist <= RADAR_RANGE then
								inRange += 1
							end
						end
					end
				end
			end
			for i = n + 1, #dots do
				dots[i].Visible = false
			end
			contactsL.Text = string.format("CONTACTS: %d  (%d st)", inRange, RADAR_RANGE)
		end

		-- camera / lighting toys
		local cam0 = workspace.CurrentCamera
		local origFov = cam0 and cam0.FieldOfView or 70
		local origClock = Lighting.ClockTime
		local fovChanged, clockChanged = false, false
		local cinema, tintOn = false, false
		local bars, tint = {}, nil
		local cinemaBtn, tintBtn

		label(pageLab, "FIELD OF VIEW", UDim2.fromOffset(180, 34), UDim2.fromOffset(160, 16), 12)
		local fovVal = label(pageLab, string.format("%d", origFov), UDim2.fromOffset(380, 34), UDim2.fromOffset(100, 16), 12, Enum.TextXAlignment.Right)
		local fovSlider = slider(pageLab, UDim2.fromOffset(180, 56), UDim2.fromOffset(300, 4), math.clamp((origFov - 30) / 90, 0, 1), function(a)
			local c = workspace.CurrentCamera
			if c then
				fovChanged = true
				c.FieldOfView = 30 + a * 90
				fovVal.Text = string.format("%d", 30 + a * 90)
			end
		end)

		label(pageLab, "TIME OF DAY (local)", UDim2.fromOffset(180, 70), UDim2.fromOffset(160, 16), 12)
		local function clockText(h)
			return string.format("%02d:%02d", math.floor(h) % 24, math.floor((h % 1) * 60))
		end
		local timeVal = label(pageLab, clockText(origClock), UDim2.fromOffset(380, 70), UDim2.fromOffset(100, 16), 12, Enum.TextXAlignment.Right)
		local timeSlider = slider(pageLab, UDim2.fromOffset(180, 92), UDim2.fromOffset(300, 4), origClock / 24, function(a)
			clockChanged = true
			Lighting.ClockTime = a * 24
			timeVal.Text = clockText(a * 24)
		end)

		local function setCinema(on)
			cinema = on
			if not bars.top then
				for _, which in ipairs({ "top", "bot" }) do
					local isBot = (which == "bot")
					bars[which] = new("Frame", {
						BackgroundColor3 = Color3.new(0, 0, 0),
						BorderSizePixel = 0,
						AnchorPoint = Vector2.new(0, isBot and 1 or 0),
						Position = UDim2.fromScale(0, isBot and 1 or 0),
						Size = UDim2.new(1, 0, 0, 0),
						ZIndex = 0,
					}, gui)
				end
			end
			for _, f in pairs(bars) do
				TweenService:Create(f, TweenInfo.new(0.6, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
					Size = UDim2.new(1, 0, on and 0.12 or 0, 0),
				}):Play()
			end
			if cinemaBtn then
				cinemaBtn.BackgroundColor3 = on and ON or DARK
			end
		end

		local function setTint(on)
			tintOn = on
			if on and not tint then
				tint = Instance.new("ColorCorrectionEffect")
				tint.Name = "JarvisTint"
				tint.Parent = Lighting
			end
			if tint then
				tint.TintColor = Color3.new(1, 1, 1):Lerp(accent, 0.2)
				tint.Saturation = 0.12
				tint.Contrast = 0.06
				tint.Enabled = on
			end
			if tintBtn then
				tintBtn.BackgroundColor3 = on and ON or DARK
			end
		end

		local function resetLab()
			setCinema(false)
			setTint(false)
			local c = workspace.CurrentCamera
			if c and fovChanged then
				c.FieldOfView = origFov
			end
			if clockChanged then
				Lighting.ClockTime = origClock
			end
			fovChanged, clockChanged = false, false
			fovSlider.force(math.clamp((origFov - 30) / 90, 0, 1))
			timeSlider.force(origClock / 24)
			fovVal.Text = string.format("%d", origFov)
			timeVal.Text = clockText(origClock)
		end
		table.insert(cleanupFns, function()
			local c = workspace.CurrentCamera
			if c and fovChanged then
				c.FieldOfView = origFov
			end
			if clockChanged then
				Lighting.ClockTime = origClock
			end
			if tint then
				tint:Destroy()
			end
			for _, f in pairs(bars) do
				f:Destroy()
			end
		end)

		cinemaBtn = button(pageLab, "CINEMA", UDim2.fromOffset(180, 108), UDim2.fromOffset(96, 24), function()
			setCinema(not cinema)
		end)
		tintBtn = button(pageLab, "SUIT TINT", UDim2.fromOffset(282, 108), UDim2.fromOffset(96, 24), function()
			setTint(not tintOn)
		end)
		local resetBtn = button(pageLab, "RESET ALL", UDim2.fromOffset(384, 108), UDim2.fromOffset(96, 24), resetLab)
		cinemaBtn.TextSize, tintBtn.TextSize, resetBtn.TextSize = 12, 12, 12
		labApi.setCinema = setCinema
		labApi.setTint = setTint

		-- server info
		local SERVER_KEYS = { "PLACE ID", "JOB ID", "PLAYERS", "SERVER TIME", "SESSION" }
		local serverVals = {}
		for i, k in ipairs(SERVER_KEYS) do
			local y = 140 + (i - 1) * 17
			label(pageLab, k, UDim2.fromOffset(180, y), UDim2.fromOffset(92, 16), 12).TextTransparency = 0.4
			serverVals[k] = label(pageLab, "--", UDim2.fromOffset(274, y), UDim2.fromOffset(210, 16), 12)
		end
		local function fmtLong(t)
			t = math.floor(t)
			return string.format("%d:%02d:%02d", t // 3600, (t % 3600) // 60, t % 60)
		end
		local function updateServer()
			serverVals["PLACE ID"].Text = tostring(game.PlaceId)
			serverVals["JOB ID"].Text = game.JobId ~= "" and (game.JobId:sub(1, 12) .. "...") or "studio / none"
			serverVals["PLAYERS"].Text = #Players:GetPlayers() .. " / " .. Players.MaxPlayers
			serverVals["SERVER TIME"].Text = fmtLong(workspace.DistributedGameTime)
			serverVals["SESSION"].Text = fmtLong(os.clock() - sessionStart)
		end

		-- system log (mirrors every JARVIS message)
		label(pageLab, "// SYSTEM LOG", UDim2.fromOffset(14, 230), UDim2.fromOffset(200, 16), 11).TextTransparency = 0.4
		local logBox = new("ScrollingFrame", {
			Position = UDim2.fromOffset(14, 248),
			Size = UDim2.fromOffset(472, 76),
			BackgroundColor3 = Color3.fromRGB(2, 8, 12),
			BackgroundTransparency = 0.2,
			BorderSizePixel = 0,
			ScrollBarThickness = 3,
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
		}, pageLab)
		acc(new("UIStroke", { Thickness = 1, Transparency = 0.6 }, logBox), "Color")
		new("UIListLayout", {}, logBox)
		local function renderLog()
			for _, c in ipairs(logBox:GetChildren()) do
				if c:IsA("TextLabel") then
					c:Destroy()
				end
			end
			for i = math.max(1, #notifLog - 14), #notifLog do
				local l = label(logBox, notifLog[i], UDim2.new(), UDim2.new(1, -8, 0, 14), 11)
				l.LayoutOrder = i
			end
			task.defer(function()
				logBox.CanvasPosition = Vector2.new(0, logBox.AbsoluteCanvasSize.Y)
			end)
		end
		onLogged = function()
			if alive and overlay.Visible and pageLab.Visible then
				renderLog()
			end
		end
		onOpen.lab = function()
			updateServer()
			renderLog()
		end

		local tServer = 0
		track(RunService.Heartbeat:Connect(function(dt)
			if not (overlay.Visible and main.Visible and pageLab.Visible) then
				return
			end
			updateRadar(dt)
			tServer += dt
			if tServer >= 1 then
				tServer = 0
				updateServer()
			end
		end))
	end

	do
		------------------------------------------------------------
		-- FUN PAGE
		------------------------------------------------------------
		label(pageFun, "// FUN ZONE", UDim2.fromOffset(12, 8), UDim2.fromOffset(200, 20), 16)

		-- PARTY MODE: rainbow HUD that speeds up with the music
		local party = false
		local partyHue = 0
		local partyBtn
		local function setParty(on)
			party = on
			partyBtn.Text = on and "PARTY MODE: ON" or "PARTY MODE: OFF"
			partyBtn.BackgroundColor3 = on and ON or DARK
			if not on then
				applyAccent(THEMES[themeIndex][2], true)
			end
			notify(on and "Party mode engaged. Let's make some noise, sir." or "Party mode disengaged.", on and "ok" or "info", 2.5)
		end
		partyBtn = button(pageFun, "PARTY MODE: OFF", UDim2.fromOffset(14, 34), UDim2.fromOffset(226, 28), function()
			setParty(not party)
		end)
		partyBtn.TextSize = 13
		table.insert(cleanupFns, function()
			party = false
		end)
		local partyAcc, partyTick = 0, 0
		track(RunService.Heartbeat:Connect(function(dt)
			if not party then
				return
			end
			local norm = sound.IsPlaying and math.clamp(sound.PlaybackLoudness / 450, 0, 1) or 0
			partyHue = (partyHue + dt * (0.06 + norm * 0.5)) % 1
			partyAcc += dt
			if partyAcc < 0.05 then
				return
			end
			partyAcc = 0
			partyTick += 1
			applyAccent(Color3.fromHSV(partyHue, 0.75, 1), partyTick % 40 == 0)
		end))

		-- SUIT-UP SEQUENCE
		local suiting = false
		button(pageFun, "SUIT-UP SEQUENCE", UDim2.fromOffset(14, 68), UDim2.fromOffset(226, 28), function()
			if suiting then
				return
			end
			suiting = true
			task.spawn(function()
				labApi.setCinema(true)
				labApi.setTint(true)
				setTheme(2)
				themeBtn.Text = "SUIT: " .. THEMES[2][1]
				local steps = {
					"Helmet locked.",
					"Gauntlets online.",
					"Repulsors charged.",
					"Arc reactor at 100%.",
					"Suit ready. Shall we, sir?",
				}
				for i, t in ipairs(steps) do
					if not alive then
						return
					end
					notify(t, i == #steps and "ok" or "info", 1.6)
					task.wait(0.9)
				end
				task.wait(1.5)
				if alive then
					labApi.setCinema(false)
					labApi.setTint(false)
				end
				suiting = false
			end)
		end).TextSize = 13

		-- ASK J.A.R.V.I.S.
		local ANSWERS = {
			"Absolutely, sir.",
			"I wouldn't bet the suit on it.",
			"The odds are in your favor.",
			"Calculations say no, sir.",
			"Ask again after a coffee.",
			"Yes. Though I advise caution.",
			"I'd call that highly unlikely.",
			"Without a doubt.",
			"My sensors are inconclusive.",
			"I have seen worse ideas. Not many.",
			"Affirmative. Brace for impact.",
			"Outlook uncertain. Reactor stable.",
			"Negative. Might I suggest a nap?",
			"Of course. I've already started.",
		}
		label(pageFun, "ASK J.A.R.V.I.S.", UDim2.fromOffset(14, 106), UDim2.fromOffset(226, 14), 12).TextTransparency = 0.3
		local askBox = new("TextBox", {
			Position = UDim2.fromOffset(14, 124),
			Size = UDim2.fromOffset(168, 26),
			BackgroundColor3 = DARK,
			BackgroundTransparency = 0.3,
			BorderSizePixel = 0,
			Font = Enum.Font.Code,
			TextSize = 12,
			Text = "",
			PlaceholderText = "ask a yes/no question",
			PlaceholderColor3 = Color3.fromRGB(110, 140, 155),
			ClearTextOnFocus = false,
			TextXAlignment = L,
		}, pageFun)
		new("UIPadding", { PaddingLeft = UDim.new(0, 8) }, askBox)
		acc(askBox, "TextColor3")
		acc(new("UIStroke", { Thickness = 1, Transparency = 0.5 }, askBox), "Color")
		local answerL = label(pageFun, "", UDim2.fromOffset(14, 156), UDim2.fromOffset(226, 56), 12)
		answerL.TextWrapped = true
		answerL.TextTruncate = Enum.TextTruncate.None
		answerL.TextYAlignment = Enum.TextYAlignment.Top
		local askToken = 0
		local function ask()
			if askBox.Text:gsub("%s", "") == "" then
				notify("You have to ask something first, sir.", "warn", 2)
				return
			end
			askToken += 1
			local my = askToken
			local ans = ANSWERS[math.random(#ANSWERS)]
			task.spawn(function()
				for i = 1, #ans do
					if my ~= askToken or not alive then
						return
					end
					answerL.Text = "> " .. ans:sub(1, i) .. "_"
					task.wait(0.02)
				end
				answerL.Text = "> " .. ans
			end)
		end
		askBox.FocusLost:Connect(function(enter)
			if enter then
				ask()
			end
		end)
		button(pageFun, "ASK", UDim2.fromOffset(188, 124), UDim2.fromOffset(52, 26), ask).TextSize = 12

		-- COIN + D20
		local rollL = label(pageFun, "", UDim2.fromOffset(14, 268), UDim2.fromOffset(226, 16), 13)
		button(pageFun, "FLIP COIN", UDim2.fromOffset(14, 232), UDim2.fromOffset(106, 28), function()
			rollL.Text = "Coin: " .. (math.random(2) == 1 and "HEADS" or "TAILS")
		end).TextSize = 12
		button(pageFun, "ROLL D20", UDim2.fromOffset(134, 232), UDim2.fromOffset(106, 28), function()
			local n = math.random(20)
			if n == 20 then
				rollL.Text = "D20: 20  (critical hit!)"
				notify("Natural 20. The universe approves, sir.", "ok", 2.5)
			elseif n == 1 then
				rollL.Text = "D20: 1  (ouch)"
				notify("A natural 1. Ouch.", "warn", 2.5)
			else
				rollL.Text = "D20: " .. n
			end
		end).TextSize = 12

		-- REPULSOR RANGE: 20-second target practice
		local AREA_W, AREA_H = 232, 190
		label(pageFun, "REPULSOR RANGE", UDim2.fromOffset(256, 34), UDim2.fromOffset(232, 16), 12).TextTransparency = 0.3
		local statL = label(pageFun, "SCORE 0   TIME 20.0   BEST 0", UDim2.fromOffset(256, 52), UDim2.fromOffset(232, 16), 12)
		local playArea = new("Frame", {
			Position = UDim2.fromOffset(256, 72),
			Size = UDim2.fromOffset(AREA_W, AREA_H),
			BackgroundColor3 = Color3.fromRGB(2, 8, 12),
			BackgroundTransparency = 0.2,
			BorderSizePixel = 0,
			ClipsDescendants = true,
		}, pageFun)
		acc(new("UIStroke", { Thickness = 1.5, Transparency = 0.3 }, playArea), "Color")
		local hint = label(playArea, "press START", UDim2.new(), UDim2.fromScale(1, 1), 13, Enum.TextXAlignment.Center)
		hint.TextTransparency = 0.4

		local target = new("TextButton", {
			Text = "",
			AutoButtonColor = false,
			Size = UDim2.fromOffset(38, 38),
			BackgroundColor3 = Color3.fromRGB(235, 252, 255),
			BorderSizePixel = 0,
			Visible = false,
		}, playArea)
		new("UICorner", { CornerRadius = UDim.new(1, 0) }, target)
		acc(new("UIStroke", { Thickness = 4 }, target), "Color")

		local playing, score, best, timeLeft, gameToken = false, 0, 0, 20, 0
		local function updateStats()
			statL.Text = string.format("SCORE %d   TIME %.1f   BEST %d", score, math.max(timeLeft, 0), best)
		end
		local function moveTarget()
			local sz = math.max(20, 38 - score)
			target.Size = UDim2.fromOffset(sz, sz)
			target.Position = UDim2.fromOffset(math.random(0, AREA_W - sz), math.random(0, AREA_H - sz))
		end
		target.MouseButton1Click:Connect(function()
			if playing then
				score += 1
				updateStats()
				moveTarget()
			end
		end)

		local startBtn
		startBtn = button(pageFun, "START", UDim2.fromOffset(256, 268), UDim2.fromOffset(232, 28), function()
			if playing then
				return
			end
			gameToken += 1
			local my = gameToken
			playing, score, timeLeft = true, 0, 20
			hint.Visible = false
			target.Visible = true
			moveTarget()
			updateStats()
			startBtn.Text = "GO GO GO"
			task.spawn(function()
				while timeLeft > 0 and my == gameToken and alive do
					task.wait(0.1)
					timeLeft -= 0.1
					updateStats()
				end
				if my ~= gameToken or not alive then
					return
				end
				playing = false
				target.Visible = false
				hint.Visible = true
				hint.Text = "final score: " .. score
				startBtn.Text = "START"
				if score > best then
					best = score
					updateStats()
					notify("New record: " .. score .. " hits. Impressive, sir.", "ok", 3)
				else
					notify("Range closed. Score: " .. score .. ".", "info", 2.5)
				end
			end)
		end)
		startBtn.TextSize = 13
	end

	------------------------------------------------------------
	-- PAGE SWITCHING + HEADER BUTTONS
	------------------------------------------------------------
	local pages = { files = pageFiles, keys = pageKeys, players = pagePlayers, lab = pageLab, fun = pageFun, credits = pageCredits }
	local tabButtons = {}
	local lastPage = "files"

	local function cancelRebind()
		if rebindTarget then
			rebindTarget = nil
			refreshKeys()
		end
	end

	function showPage(name, force)
		if name == nil or (openPage == name and not force) then
			overlay.Visible = false
			openPage = nil
			cancelRebind()
			return
		end
		if name ~= "keys" then
			cancelRebind()
		end
		openPage = name
		lastPage = name
		overlay.Visible = true
		for n, f in pairs(pages) do
			f.Visible = (n == name)
		end
		for n, tb in pairs(tabButtons) do
			tb.BackgroundColor3 = (n == name) and ON or DARK
		end
		if onOpen[name] then
			onOpen[name]()
		end
	end

	local TABS = {
		{ "files", "FILES" },
		{ "keys", "KEYS" },
		{ "players", "PLAYERS" },
		{ "lab", "LAB" },
		{ "fun", "FUN" },
		{ "credits", "CREDITS" },
	}
	for i, t in ipairs(TABS) do
		local tb = button(overlay, t[2], UDim2.fromOffset(8 + (i - 1) * 72, 6), UDim2.fromOffset(68, 24), function()
			showPage(t[1], true)
		end)
		tb.TextSize = 12
		tabButtons[t[1]] = tb
	end
	local closeTab = button(overlay, "X", UDim2.new(1, -40, 0, 6), UDim2.fromOffset(32, 24), function()
		showPage(nil)
	end)
	closeTab.TextSize = 12
	local tabSep = new("Frame", {
		Position = UDim2.fromOffset(8, 33),
		Size = UDim2.new(1, -16, 0, 1),
		BackgroundTransparency = 0.6,
		BorderSizePixel = 0,
	}, overlay)
	acc(tabSep, "BackgroundColor3")

	local menuBtn = button(header, "MENU", UDim2.fromOffset(204, 6), UDim2.fromOffset(60, 22), function()
		showPage(lastPage)
	end)
	menuBtn.TextSize = 12
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
-- HUD TOGGLE ORB (collapse / expand with animation)
----------------------------------------------------------------
local ORB_POS = UDim2.new(1, -46, 1, -46)
local uiOpen, uiBusy, booted = true, false, false
local homePos = main.Position
local pop = new("UIScale", { Scale = 1 }, main)

local orb = new("TextButton", {
	Name = "Orb",
	Text = "",
	AutoButtonColor = false,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = ORB_POS,
	Size = UDim2.fromOffset(60, 60),
	BackgroundColor3 = Color3.fromRGB(4, 12, 20),
	BackgroundTransparency = 0.15,
	BorderSizePixel = 0,
	Visible = false,
}, gui)
new("UICorner", { CornerRadius = UDim.new(1, 0) }, orb)
acc(new("UIStroke", { Thickness = 2, Transparency = 0.2 }, orb), "Color")
local orbScale = new("UIScale", { Scale = 0 }, orb)

local orbRing = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, orb)
for i = 1, 12 do
	local a = math.rad(i * 30)
	local t = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(2, 6),
		Position = UDim2.new(0.5, 24 * math.sin(a), 0.5, -24 * math.cos(a)),
		Rotation = i * 30,
		BorderSizePixel = 0,
	}, orbRing)
	acc(t, "BackgroundColor3")
end

local orbMid = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(32, 32),
	BackgroundTransparency = 1,
}, orb)
new("UICorner", { CornerRadius = UDim.new(1, 0) }, orbMid)
acc(new("UIStroke", { Thickness = 1.5, Transparency = 0.3 }, orbMid), "Color")

local orbCore = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(14, 14),
	BackgroundColor3 = Color3.fromRGB(235, 252, 255),
	BorderSizePixel = 0,
}, orb)
new("UICorner", { CornerRadius = UDim.new(1, 0) }, orbCore)
acc(new("UIStroke", { Thickness = 3, Transparency = 0.15 }, orbCore), "Color")

local orbTip = new("TextLabel", {
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(0, -10, 0.5, 0),
	Size = UDim2.fromOffset(90, 20),
	BackgroundTransparency = 1,
	Text = "HUD  [M]",
	Font = Enum.Font.Code,
	TextSize = 13,
	TextXAlignment = Enum.TextXAlignment.Right,
	TextTransparency = 1,
}, orb)
acc(orbTip, "TextColor3")

local boost = 0

local function ripple()
	local r = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = ORB_POS,
		Size = UDim2.fromOffset(60, 60),
		BackgroundTransparency = 1,
	}, gui)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, r)
	local st = new("UIStroke", { Thickness = 3, Color = accent, Transparency = 0.1 }, r)
	TweenService:Create(r, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = UDim2.fromOffset(260, 260),
	}):Play()
	TweenService:Create(st, TweenInfo.new(0.7), { Transparency = 1, Thickness = 0.5 }):Play()
	task.delay(0.8, function()
		r:Destroy()
	end)
end

local function flicker()
	for _, v in ipairs({ 0.55, 0, 0.4, 0, 0.2, 0 }) do
		if not (alive and uiOpen) then
			return
		end
		main.GroupTransparency = v
		task.wait(0.035)
	end
end

local function setUI(open)
	if uiBusy or not booted or open == uiOpen then
		return
	end
	uiBusy = true
	uiOpen = open
	boost = 700
	ripple()

	if open then
		main.Position = ORB_POS
		pop.Scale = 0.05
		main.GroupTransparency = 1
		main.Visible = true
		TweenService:Create(main, TweenInfo.new(0.6, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
			Position = homePos,
		}):Play()
		TweenService:Create(pop, TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Scale = 1,
		}):Play()
		TweenService:Create(main, TweenInfo.new(0.3, Enum.EasingStyle.Quad), { GroupTransparency = 0 }):Play()
		task.delay(0.6, function()
			flicker()
			uiBusy = false
		end)
	else
		homePos = main.Position
		TweenService:Create(main, TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.In), {
			Position = ORB_POS,
		}):Play()
		TweenService:Create(pop, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
			Scale = 0.05,
		}):Play()
		TweenService:Create(main, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			GroupTransparency = 1,
		}):Play()
		notify("HUD minimized. Press M or tap the orb to restore.", "info", 2.5)
		task.delay(0.47, function()
			main.Visible = false
			pop.Scale = 1
			uiBusy = false
		end)
	end
end

local function toggleUI()
	setUI(not uiOpen)
end

local function revealOrb()
	orb.Visible = true
	TweenService:Create(orbScale, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	ripple()
end

orb.MouseButton1Click:Connect(toggleUI)
orb.MouseEnter:Connect(function()
	TweenService:Create(orbScale, TweenInfo.new(0.15), { Scale = 1.15 }):Play()
	TweenService:Create(orbTip, TweenInfo.new(0.15), { TextTransparency = 0 }):Play()
end)
orb.MouseLeave:Connect(function()
	TweenService:Create(orbScale, TweenInfo.new(0.15), { Scale = 1 }):Play()
	TweenService:Create(orbTip, TweenInfo.new(0.15), { TextTransparency = 1 }):Play()
end)

track(RunService.RenderStepped:Connect(function(dt)
	if not orb.Visible then
		return
	end
	local norm = sound.IsPlaying and math.clamp(sound.PlaybackLoudness / 450, 0, 1) or 0
	boost = math.max(0, boost - dt * 900)
	orbRing.Rotation += dt * (40 + norm * 120 + boost)
	local sz = 14 + norm * 10 + math.sin(os.clock() * 3)
	orbCore.Size = UDim2.fromOffset(sz, sz)
end))

-- minimize button in the header
do
	local mb = button(header, "-", UDim2.new(1, -50, 0, 17), UDim2.fromOffset(34, 22), toggleUI)
	mb.AnchorPoint = Vector2.new(1, 0.5)
	mb.TextSize = 18
end

----------------------------------------------------------------
-- HOTKEYS
----------------------------------------------------------------
local actions = {}
actions.toggle = toggleUI
actions.play = togglePlay
actions.next = function()
	nextTrack(1)
end
actions.prev = function()
	nextTrack(-1)
end
actions.volup = function()
	nudgeVolume(0.05)
end
actions.voldown = function()
	nudgeVolume(-0.05)
end
actions.theme = function()
	local n = themeIndex % #THEMES + 1
	setTheme(n)
	themeBtn.Text = "SUIT: " .. THEMES[n][1]
	notify("Suit configuration: " .. THEMES[n][1], "info", 2)
end
local function openTab(name)
	setUI(true)
	showPage(name)
end
for _, name in ipairs({ "files", "keys", "players", "lab", "fun", "credits" }) do
	actions[name] = function()
		openTab(name)
	end
end
actions.exit = unload

track(UserInputService.InputBegan:Connect(function(input, processed)
	if input.UserInputType ~= Enum.UserInputType.Keyboard then
		return
	end
	if rebindTarget then
		captureKey(input.KeyCode)
		return
	end
	if processed then
		return
	end
	for id, key in pairs(binds) do
		if key ~= Enum.KeyCode.Unknown and key == input.KeyCode then
			local fn = actions[id]
			if fn then
				fn()
			end
			break
		end
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
	booted = true
	revealOrb()
	task.wait(0.5)
	boot:Destroy()
	if not alive then
		return
	end
	say("all systems online. add an audio ID or import a file to begin, sir.", "ok")
end)
