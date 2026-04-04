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

	Tab:Paragraph({
		Title = "Config File",
		Desc = "Manage one config file with a simple set of actions.",
	})

	local configFileCode = Tab:Code({
		Title = "Config File",
		Code = "-- no config selected",
	})

	local function refreshConfigFile()
		if not Window.ConfigManager then
			configFileCode:SetCode("-- ConfigManager unavailable")
			return
		end

		local files = Window.ConfigManager:AllConfigs()
		if #files == 0 then
			configFileCode:SetCode("-- no config files found")
			return
		end

		configFileCode:SetCode(table.concat(files, "\n"))
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

	local autoLoadToggle = Tab:Toggle({
		Title = "Auto Load",
		Desc = "Enable autoload for the selected config.",
		Value = autoLoadEnabled,
		Callback = function(value)
			autoLoadEnabled = value
			if activeConfig then
				activeConfig:SetAutoLoad(value)
			end
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
			refreshConfigFile()
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

			refreshConfigFile()
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
			Notify("Delete Config", "Deleted: " .. configName, "lucide:trash-2")
		end,
	})

	refreshConfigFile()
	autoLoadToggle:Set(autoLoadEnabled)

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
