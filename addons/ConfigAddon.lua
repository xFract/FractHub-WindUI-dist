local ConfigAddon = {}

function ConfigAddon.Setup(context)
	local Window = context.Window
	local Tab = context.Tab
	local Notify = context.Notify
	local TrackedElements = context.TrackedElements or {}
	local DefaultConfigName = context.DefaultConfigName or "default"

	local activeConfigName = DefaultConfigName
	local autoLoadEnabled = true
	local activeConfig = nil
	local configNameInput = nil
	local configFileDropdown = nil
	local autoLoadButton = nil

	local function registerTracked(config)
		for flag, element in pairs(TrackedElements) do
			config:Register(flag, element)
		end
	end

	local function getConfigName()
		local value = configNameInput and configNameInput.Value or activeConfigName
		if type(value) ~= "string" or value == "" then
			return activeConfigName
		end

		return value
	end

	local function setCurrentConfig(config, configName)
		registerTracked(config)
		config:SetAutoLoad(autoLoadEnabled)
		config:SetAsCurrent()

		activeConfig = config
		activeConfigName = configName
	end

	local function createOrGetConfig(configName)
		if not Window.ConfigManager then
			return nil, "ConfigManager is unavailable."
		end

		local config = Window.ConfigManager:GetConfig(configName)
		if not config then
			config = Window.ConfigManager:CreateConfig(configName, autoLoadEnabled)
		end

		setCurrentConfig(config, configName)
		return config
	end

	local function refreshAutoLoadState()
		if not autoLoadButton then
			return
		end

		autoLoadButton:SetDesc(
			"Current config: "
				.. tostring(activeConfigName)
				.. " | Auto load: "
				.. (autoLoadEnabled and "enabled" or "disabled")
		)
	end

	local configFileCode = Tab:Code({
		Title = "Config File",
		Code = "-- no config files found",
	})

	local function refreshConfigFile()
		if not Window.ConfigManager then
			configFileCode:SetCode("-- ConfigManager unavailable")
			if configFileDropdown and configFileDropdown.Refresh then
				configFileDropdown:Refresh({})
			end
			return
		end

		local files = Window.ConfigManager:AllConfigs()
		if #files == 0 then
			configFileCode:SetCode("-- no config files found")
			if configFileDropdown and configFileDropdown.Refresh then
				configFileDropdown:Refresh({})
			end
			return
		end

		configFileCode:SetCode(table.concat(files, "\n"))
		if configFileDropdown and configFileDropdown.Refresh then
			configFileDropdown:Refresh(files)
		end
	end

	configNameInput = Tab:Input({
		Title = "Config Name",
		Desc = "Target config file name.",
		Placeholder = DefaultConfigName,
		Value = activeConfigName,
		InputIcon = "lucide:file-cog",
		Callback = function(value)
			if value ~= "" then
				activeConfigName = value
			end
		end,
	})

	configFileDropdown = Tab:Dropdown({
		Title = "Config File",
		Desc = "Select an existing config file.",
		Values = {},
		Value = nil,
		AllowNone = true,
		Callback = function(value)
			if type(value) == "string" and value ~= "" then
				activeConfigName = value
				if configNameInput then
					configNameInput:Set(value)
				end
				refreshAutoLoadState()
			end
		end,
	})

	autoLoadButton = Tab:Button({
		Title = "Auto Load",
		Desc = "Current config: " .. tostring(activeConfigName) .. " | Auto load: enabled",
		Callback = function()
			autoLoadEnabled = not autoLoadEnabled
			if activeConfig then
				activeConfig:SetAutoLoad(autoLoadEnabled)
			end

			refreshAutoLoadState()
			Notify(
				"Auto Load",
				"Auto load is now " .. (autoLoadEnabled and "enabled" or "disabled"),
				autoLoadEnabled and "lucide:badge-check" or "lucide:badge-x"
			)
		end,
	})

	Tab:Button({
		Title = "CreateConfig",
		Desc = "Create or select the current config.",
		Callback = function()
			local configName = getConfigName()
			local config, err = createOrGetConfig(configName)
			if not config then
				Notify("Config Error", err, "lucide:triangle-alert", 6)
				return
			end

			if context.OnBeforeSave then
				context.OnBeforeSave(config, configName)
			end

			refreshConfigFile()
			refreshAutoLoadState()
			Notify("CreateConfig", "Current config: " .. configName, "lucide:file-plus-2")
		end,
	})

	Tab:Button({
		Title = "Save Config",
		Desc = "Save the selected config file.",
		Callback = function()
			local configName = getConfigName()
			local config, err = createOrGetConfig(configName)
			if not config then
				Notify("Config Error", err, "lucide:triangle-alert", 6)
				return
			end

			if context.OnBeforeSave then
				context.OnBeforeSave(config, configName)
			end

			config:SetAutoLoad(autoLoadEnabled)
			config:Save()
			if configFileDropdown and configFileDropdown.Select then
				configFileDropdown:Select(configName)
			end
			refreshConfigFile()
			refreshAutoLoadState()
			Notify("Save Config", "Saved: " .. configName, "lucide:save")
		end,
	})

	Tab:Button({
		Title = "Load Config",
		Desc = "Load the selected config file.",
		Callback = function()
			local configName = getConfigName()
			local config, err = createOrGetConfig(configName)
			if not config then
				Notify("Config Error", err, "lucide:triangle-alert", 6)
				return
			end

			local ok, result = config:Load()
			if ok == false then
				Notify("Load Failed", tostring(result), "lucide:circle-x", 6)
				return
			end

			if context.OnAfterLoad then
				context.OnAfterLoad(config, configName, result)
			end

			if configFileDropdown and configFileDropdown.Select then
				configFileDropdown:Select(configName)
			end
			refreshConfigFile()
			refreshAutoLoadState()
			Notify("Load Config", "Loaded: " .. configName, "lucide:folder-open")
		end,
	})

	Tab:Button({
		Title = "Delete Config",
		Desc = "Delete the selected config file.",
		Callback = function()
			if not Window.ConfigManager then
				Notify("Config Error", "ConfigManager is unavailable.", "lucide:triangle-alert", 6)
				return
			end

			local configName = getConfigName()
			local ok, result = Window.ConfigManager:DeleteConfig(configName)
			if not ok then
				Notify("Delete Failed", tostring(result), "lucide:trash-2", 6)
				return
			end

			if activeConfigName == configName then
				activeConfig = nil
			end

			refreshConfigFile()
			refreshAutoLoadState()
			Notify("Delete Config", "Deleted: " .. configName, "lucide:trash-2")
		end,
	})

	refreshConfigFile()
	refreshAutoLoadState()

	return {
		GetActiveName = function()
			return activeConfigName
		end,
		GetActiveConfig = function()
			return activeConfig
		end,
		Refresh = refreshConfigFile,
	}
end

return ConfigAddon
