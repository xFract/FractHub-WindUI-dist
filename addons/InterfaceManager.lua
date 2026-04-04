local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local VirtualUser = game:GetService("VirtualUser")
local TeleportService = game:GetService("TeleportService")
local Lighting = game:GetService("Lighting")
local GuiService = game:GetService("GuiService")
local MarketplaceService = game:GetService("MarketplaceService")

local InterfaceManager = {}
InterfaceManager.__index = InterfaceManager

InterfaceManager.Folder = "WindUI"
InterfaceManager.Settings = {
	Theme = "Dark",
	Acrylic = false,
	Transparency = false,
	MenuKeybind = "RightShift",
	AutoMinimize = false,
	AutoExecute = false,
	AutoExecuteGist = "https://gist.githubusercontent.com/xFract/56ca5d02d698ea6536e4d975c4cf3d1e/raw/script.lua",
	AntiAFK = false,
	PerformanceMode = false,
	FPSCap = 60,
	AutoRejoin = false,
	LowPlayerHop = false,
	StaffDetector = false,
	WebhookURL = "",
}

InterfaceManager.AFKThread = nil
InterfaceManager.IsRejoining = false
InterfaceManager.IsHopping = false
InterfaceManager.AutoExecuteSource = nil
InterfaceManager.AutoExecuteBound = false
InterfaceManager.AutoRejoinBound = false
InterfaceManager.StaffDetectorBound = false
InterfaceManager.KeybindWatcherTask = nil
InterfaceManager.OriginalLighting = nil
InterfaceManager.PerformanceRestore = {}
InterfaceManager.MinimizeButtonConfig = nil

function InterfaceManager:SetFolder(folder)
	self.Folder = folder
	self:BuildFolderTree()
end

function InterfaceManager:SetLibrary(library)
	self.Library = library
end

function InterfaceManager:SetWindow(window)
	self.Window = window
end

function InterfaceManager:SetMinimizeButtonConfig(config)
	self.MinimizeButtonConfig = config
	self:ApplyMinimizeButton()
end

function InterfaceManager:SetAutoExecuteSource(source)
	self.AutoExecuteSource = source
end

function InterfaceManager:BuildAutoExecuteSource()
	local url = self.Settings.AutoExecuteGist
	if not url or url == "" then
		self.AutoExecuteSource = nil
		return
	end

	self.AutoExecuteSource = string.format(
		"repeat task.wait() until game:IsLoaded(); loadstring(game:HttpGet(%q))()",
		url
	)
end

function InterfaceManager:SetAutoExecuteUrl(url)
	self.Settings.AutoExecuteGist = url or ""
	self:BuildAutoExecuteSource()
	self:BindTeleportAutoExecute()
end

function InterfaceManager:BuildFolderTree()
	if not makefolder or not isfolder then
		return
	end

	local paths = {}
	local parts = self.Folder:split("/")
	for index = 1, #parts do
		paths[#paths + 1] = table.concat(parts, "/", 1, index)
	end

	table.insert(paths, self.Folder)
	table.insert(paths, self.Folder .. "/settings")

	for _, path in ipairs(paths) do
		if not isfolder(path) then
			makefolder(path)
		end
	end
end

function InterfaceManager:SaveSettings()
	if not writefile then
		return false
	end

	self:BuildFolderTree()
	writefile(self.Folder .. "/options.json", HttpService:JSONEncode(self.Settings))
	return true
end

function InterfaceManager:LoadSettings()
	if not isfile or not readfile then
		return false
	end

	local path = self.Folder .. "/options.json"
	if not isfile(path) then
		return false
	end

	local success, decoded = pcall(function()
		return HttpService:JSONDecode(readfile(path))
	end)

	if not success or type(decoded) ~= "table" then
		return false
	end

	for key, value in pairs(decoded) do
		self.Settings[key] = value
	end

	self:BuildAutoExecuteSource()

	return true
end

function InterfaceManager:Notify(title, content, icon)
	if self.Library and self.Library.Notify then
		self.Library:Notify({
			Title = title,
			Content = content,
			Icon = icon,
			Duration = 6,
		})
	end
end

function InterfaceManager:SetPerformanceMode(enabled)
	local settings = self.Settings
	settings.PerformanceMode = enabled == true

	if settings.PerformanceMode then
		if not self.OriginalLighting then
			self.OriginalLighting = {
				GlobalShadows = Lighting.GlobalShadows,
				FogEnd = Lighting.FogEnd,
				ShadowSoftness = Lighting.ShadowSoftness,
			}
		end

		self.PerformanceRestore = {}
		task.spawn(function()
			pcall(function()
				Lighting.GlobalShadows = false
				Lighting.FogEnd = 9e9
				Lighting.ShadowSoftness = 0
			end)

			pcall(function()
				for _, obj in ipairs(workspace:GetDescendants()) do
					if obj:IsA("BasePart") then
						self.PerformanceRestore[obj] = {
							class = "BasePart",
							Material = obj.Material,
						}
						obj.Material = Enum.Material.SmoothPlastic
					elseif obj:IsA("Decal") or obj:IsA("Texture") then
						self.PerformanceRestore[obj] = {
							class = "TextureLike",
							Transparency = obj.Transparency,
						}
						obj.Transparency = 1
					elseif obj:IsA("ParticleEmitter") or obj:IsA("Trail") then
						self.PerformanceRestore[obj] = {
							class = "Fx",
							Enabled = obj.Enabled,
						}
						obj.Enabled = false
					end
				end
			end)
		end)
		return
	end

	if self.OriginalLighting then
		pcall(function()
			Lighting.GlobalShadows = self.OriginalLighting.GlobalShadows
			Lighting.FogEnd = self.OriginalLighting.FogEnd
			Lighting.ShadowSoftness = self.OriginalLighting.ShadowSoftness
		end)
	end

	pcall(function()
		for obj, data in pairs(self.PerformanceRestore) do
			if obj and obj.Parent then
				if data.class == "BasePart" then
					obj.Material = data.Material
				elseif data.class == "TextureLike" then
					obj.Transparency = data.Transparency
				elseif data.class == "Fx" then
					obj.Enabled = data.Enabled
				end
			end
		end
	end)

	self.PerformanceRestore = {}
end

function InterfaceManager:SetFPSCap(value)
	self.Settings.FPSCap = value
	if type(setfpscap) == "function" then
		setfpscap(value)
	end
end

function InterfaceManager:SetAntiAFK(enabled)
	self.Settings.AntiAFK = enabled == true

	if self.AFKThread then
		task.cancel(self.AFKThread)
		self.AFKThread = nil
	end

	if self.Settings.AntiAFK then
		self.AFKThread = task.spawn(function()
			while self.Settings.AntiAFK do
				VirtualUser:CaptureController()
				VirtualUser:ClickButton2(Vector2.new())
				task.wait(60)
			end
		end)
	end
end

function InterfaceManager:SendWebhook(title, description)
	local webhookUrl = self.Settings.WebhookURL
	if not webhookUrl or webhookUrl == "" then
		return
	end

	task.spawn(function()
		pcall(function()
			local httpRequest = (syn and syn.request) or request or http_request or (http and http.request)
			if not httpRequest then
				return
			end

			httpRequest({
				Url = webhookUrl,
				Method = "POST",
				Headers = { ["Content-Type"] = "application/json" },
				Body = HttpService:JSONEncode({
					embeds = {{
						title = title,
						description = description,
						color = 16711680,
						footer = { text = "WindUI InterfaceManager" },
						timestamp = DateTime.now():ToIsoDate(),
					}},
				}),
			})
		end)
	end)
end

function InterfaceManager:ServerHop()
	if self.IsHopping then
		return
	end
	self.IsHopping = true

	task.spawn(function()
		local lowPlayerOnly = self.Settings.LowPlayerHop == true
		local success, result = pcall(function()
			local url = string.format(
				"https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100",
				game.PlaceId
			)
			return HttpService:JSONDecode(game:HttpGet(url))
		end)

		if not success or not result or not result.data then
			pcall(function()
				TeleportService:Teleport(game.PlaceId, Players.LocalPlayer)
			end)
			self.IsHopping = false
			return
		end

		local currentJobId = game.JobId
		local targetServer = nil
		for _, server in ipairs(result.data) do
			if server.id ~= currentJobId and server.playing and server.maxPlayers then
				if not lowPlayerOnly or server.playing < (server.maxPlayers * 0.3) then
					targetServer = server
					break
				end
			end
		end

		pcall(function()
			if targetServer then
				TeleportService:TeleportToPlaceInstance(game.PlaceId, targetServer.id, Players.LocalPlayer)
			else
				TeleportService:Teleport(game.PlaceId, Players.LocalPlayer)
			end
		end)

		task.wait(5)
		self.IsHopping = false
	end)
end

function InterfaceManager:IsStaff(player)
	if not player or player == Players.LocalPlayer then
		return false
	end

	if game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId then
		return true
	end

	if game.CreatorType == Enum.CreatorType.Group then
		local rankSuccess, rank = pcall(function()
			return player:GetRankInGroup(game.CreatorId)
		end)
		if rankSuccess and rank >= 200 then
			return true
		end
	end

	local verifiedSuccess, verified = pcall(function()
		return player.HasVerifiedBadge
	end)
	if verifiedSuccess and verified then
		return true
	end

	return false
end

function InterfaceManager:BindAutoRejoin()
	if self.AutoRejoinBound then
		return
	end
	self.AutoRejoinBound = true

	local function triggerRejoin()
		if not self.Settings.AutoRejoin or self.IsRejoining then
			return
		end

		self.IsRejoining = true
		task.wait(3)
		pcall(function()
			if #game.JobId > 0 then
				TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, Players.LocalPlayer)
			else
				TeleportService:Teleport(game.PlaceId, Players.LocalPlayer)
			end
		end)
		task.wait(5)
		self.IsRejoining = false
	end

	pcall(function()
		local promptOverlay = game:GetService("CoreGui"):FindFirstChild("RobloxPromptGui")
		promptOverlay = promptOverlay and promptOverlay:FindFirstChild("promptOverlay")
		if promptOverlay then
			promptOverlay.ChildAdded:Connect(function(child)
				if child.Name == "ErrorPrompt" then
					triggerRejoin()
				end
			end)
		end
	end)

	pcall(function()
		GuiService.ErrorMessageChanged:Connect(function()
			triggerRejoin()
		end)
	end)
end

function InterfaceManager:BindStaffDetector()
	if self.StaffDetectorBound then
		return
	end
	self.StaffDetectorBound = true

	local function checkPlayer(player)
		if not self.Settings.StaffDetector or not self:IsStaff(player) then
			return
		end

		local gameName = "Unknown"
		pcall(function()
			gameName = MarketplaceService:GetProductInfo(game.PlaceId).Name
		end)

		self:SendWebhook(
			"Staff Detected",
			string.format(
				"**Player:** %s\n**UserId:** %d\n**Game:** %s (PlaceId: %d)\n**Action:** Auto Hop",
				player.Name,
				player.UserId,
				gameName,
				game.PlaceId
			)
		)

		task.wait(1)
		self:ServerHop()
	end

	Players.PlayerAdded:Connect(checkPlayer)
	task.spawn(function()
		for _, player in ipairs(Players:GetPlayers()) do
			checkPlayer(player)
		end
	end)
end

function InterfaceManager:BindTeleportAutoExecute()
	if self.AutoExecuteBound or not self.AutoExecuteSource or not Players.LocalPlayer then
		return
	end
	self.AutoExecuteBound = true

	local queued = false
	Players.LocalPlayer.OnTeleport:Connect(function()
		if queued or not self.Settings.AutoExecute then
			return
		end

		local queueTeleport = (syn and syn.queue_on_teleport) or queue_on_teleport or (fluxus and fluxus.queue_on_teleport)
		if queueTeleport then
			queueTeleport(self.AutoExecuteSource)
			queued = true
		end
	end)
end

function InterfaceManager:StartKeybindWatcher(keybind)
	if self.KeybindWatcherTask then
		task.cancel(self.KeybindWatcherTask)
		self.KeybindWatcherTask = nil
	end

	local lastValue = keybind and keybind.Value or self.Settings.MenuKeybind
	self.KeybindWatcherTask = task.spawn(function()
		while self.Window and not self.Window.Destroyed do
			if keybind and keybind.Value ~= lastValue then
				lastValue = keybind.Value
				self:SetMinimizeBind(lastValue)
			end
			task.wait(0.1)
		end
	end)
end

function InterfaceManager:SetMinimizeBind(key)
	self.Settings.MenuKeybind = key
	local keyCode = Enum.KeyCode[key]
	if keyCode and self.Window then
		self.Window:SetToggleKey(keyCode)
	end
	self:SaveSettings()
end

function InterfaceManager:GetMinimizeButtonConfig()
	local window = self.Window
	local configured = self.MinimizeButtonConfig or {}
	local color = configured.Color

	if color == nil then
		color = ColorSequence.new(Color3.fromHex("40c9ff"), Color3.fromHex("e81cff"))
	end

	return {
		Enabled = configured.Enabled ~= false,
		OnlyMobile = configured.OnlyMobile == true and true or false,
		OnlyIcon = configured.OnlyIcon ~= false,
		Draggable = configured.Draggable ~= false,
		Position = configured.Position or UDim2.new(1, -54, 1, -54),
		Title = configured.Title or "Open",
		Icon = configured.Icon or (window and window.Icon) or "lucide:panel-right-open",
		CornerRadius = configured.CornerRadius or UDim.new(1, 0),
		StrokeThickness = configured.StrokeThickness or 0,
		Scale = configured.Scale or 1,
		Color = color,
	}
end

function InterfaceManager:ApplyMinimizeButton()
	if not self.Window or type(self.Window.EditOpenButton) ~= "function" then
		return false
	end

	local success = pcall(function()
		self.Window:EditOpenButton(self:GetMinimizeButtonConfig())
	end)

	return success
end

function InterfaceManager:MinimizeWindow()
	if not self.Window or self.Window.Closed then
		return false
	end

	self:ApplyMinimizeButton()

	local success = pcall(function()
		self.Window:Close()
	end)

	return success
end

function InterfaceManager:ApplyLoadedSettings()
	local settings = self.Settings
	if self.Library then
		pcall(function()
			self.Library:SetTheme(settings.Theme)
		end)
		pcall(function()
			self.Library:ToggleAcrylic(settings.Acrylic)
		end)
	end

	if self.Window then
		self:ApplyMinimizeButton()
		pcall(function()
			self.Window:ToggleTransparency(settings.Transparency)
		end)
		pcall(function()
			self.Window:SetToggleKey(Enum.KeyCode[settings.MenuKeybind] or Enum.KeyCode.RightShift)
		end)
		if settings.AutoMinimize then
			task.defer(function()
				self:MinimizeWindow()
			end)
		end
	end

	if settings.AntiAFK then
		self:SetAntiAFK(true)
	end
	if settings.PerformanceMode then
		self:SetPerformanceMode(true)
	end
	if type(setfpscap) == "function" then
		self:SetFPSCap(settings.FPSCap or 60)
	end
end

function InterfaceManager:BuildInterfaceSection(tab, options)
	assert(self.Library, "Must set InterfaceManager.Library")
	assert(self.Window, "Must set InterfaceManager.Window")

	options = options or {}
	if options.MinimizeButton then
		self.MinimizeButtonConfig = options.MinimizeButton
	end
	self:ApplyMinimizeButton()
	self:LoadSettings()
	self:BindTeleportAutoExecute()
	self:BindAutoRejoin()
	self:BindStaffDetector()
	self:ApplyLoadedSettings()

	local settings = self.Settings
	local themeNames = {}
	for name, _ in pairs(self.Library:GetThemes()) do
		table.insert(themeNames, name)
	end
	table.sort(themeNames)

	local AppearanceSection = tab:Section({
		Title = options.AppearanceTitle or "Appearance",
		Desc = options.AppearanceDesc or "Interface options and saved preferences.",
		Box = true,
		BoxBorder = true,
		Opened = true,
	})

	AppearanceSection:Dropdown({
		Title = "Theme",
		Value = settings.Theme,
		Values = themeNames,
		SearchBarEnabled = true,
		Callback = function(value)
			settings.Theme = value
			self.Library:SetTheme(value)
			self:SaveSettings()
		end,
	})

	if self.Window.AcrylicPaint then
		AppearanceSection:Space()
		AppearanceSection:Toggle({
			Title = "Acrylic",
			Value = settings.Acrylic,
			Callback = function(value)
				settings.Acrylic = value
				self.Library:ToggleAcrylic(value)
				self:SaveSettings()
			end,
		})
	end

	AppearanceSection:Space()
	AppearanceSection:Toggle({
		Title = "Transparency",
		Value = settings.Transparency,
		Callback = function(value)
			settings.Transparency = value
			self.Window:ToggleTransparency(value)
			self:SaveSettings()
		end,
	})

	AppearanceSection:Space()
	local MinimizeKeybind = AppearanceSection:Keybind({
		Title = "Minimize Bind",
		Value = settings.MenuKeybind,
		Callback = function(key)
			self:SetMinimizeBind(key)
		end,
	})
	self:StartKeybindWatcher(MinimizeKeybind)

	local UtilitySection = tab:Section({
		Title = options.UtilityTitle or "Utility",
		Desc = options.UtilityDesc or "Quality of life settings.",
		Box = true,
		BoxBorder = true,
		Opened = true,
	})

	UtilitySection:Toggle({
		Title = "Auto Minimize",
		Value = settings.AutoMinimize,
		Callback = function(value)
			settings.AutoMinimize = value
			self:SaveSettings()
		end,
	})

	UtilitySection:Space()
	UtilitySection:Toggle({
		Title = "Auto Execute",
		Value = settings.AutoExecute,
		Callback = function(value)
			settings.AutoExecute = value
			self:SaveSettings()
		end,
	})

	UtilitySection:Space()
	UtilitySection:Toggle({
		Title = "Anti AFK",
		Value = settings.AntiAFK,
		Callback = function(value)
			self:SetAntiAFK(value)
			self:SaveSettings()
		end,
	})

	UtilitySection:Space()
	UtilitySection:Toggle({
		Title = "Performance Mode",
		Value = settings.PerformanceMode,
		Callback = function(value)
			self:SetPerformanceMode(value)
			self:SaveSettings()
		end,
	})

	UtilitySection:Space()
	UtilitySection:Slider({
		Title = "FPS Cap",
		Step = 1,
		Value = { Min = 15, Max = 240, Default = settings.FPSCap or 60 },
		Callback = function(value)
			self:SetFPSCap(value)
			self:SaveSettings()
		end,
	})

	local ServerSection = tab:Section({
		Title = options.ServerTitle or "Server & Safety",
		Desc = options.ServerDesc or "Reconnect, hop, and staff detection helpers.",
		Box = true,
		BoxBorder = true,
		Opened = true,
	})

	ServerSection:Toggle({
		Title = "Auto Rejoin",
		Value = settings.AutoRejoin,
		Callback = function(value)
			settings.AutoRejoin = value
			self:SaveSettings()
		end,
	})

	ServerSection:Space()
	ServerSection:Toggle({
		Title = "Low Player Hop",
		Value = settings.LowPlayerHop,
		Callback = function(value)
			settings.LowPlayerHop = value
			self:SaveSettings()
		end,
	})

	ServerSection:Space()
	ServerSection:Toggle({
		Title = "Staff Detector",
		Value = settings.StaffDetector,
		Callback = function(value)
			settings.StaffDetector = value
			self:SaveSettings()
		end,
	})

	ServerSection:Space()
	ServerSection:Button({
		Title = "Server Hop",
		Callback = function()
			self:ServerHop()
		end,
	})

	ServerSection:Space()
	ServerSection:Input({
		Title = "Discord Webhook URL",
		Placeholder = "https://discord.com/api/webhooks/...",
		Callback = function(value)
			settings.WebhookURL = value
			self:SaveSettings()
		end,
	})
end

return InterfaceManager
