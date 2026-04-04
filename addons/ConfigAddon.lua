local ConfigAddon = {}

function ConfigAddon.Setup(context)
	local Window = context.Window
	local configTab = context.Tab
	local notify = context.Notify
	local encode = context.Encode
	local executorName = context.ExecutorName
	local hasFileApi = context.HasFileApi
	local trackedElements = context.TrackedElements
	local defaultConfigName = context.DefaultConfigName or "default"

	local activeConfigName = defaultConfigName
	local activeConfig = nil

	local function useConfig(configName, autoload)
		if not Window.ConfigManager then
			return nil, "ConfigManager is unavailable. This executor likely does not expose file APIs."
		end

		local config = Window.ConfigManager:GetConfig(configName)
		if not config then
			config = Window.ConfigManager:CreateConfig(configName, autoload)
		else
			config:SetAutoLoad(autoload == true)
		end

		for flag, element in pairs(trackedElements) do
			config:Register(flag, element)
		end

		config:SetAsCurrent()
		activeConfig = config
		activeConfigName = configName

		return config
	end

	if Window.ConfigManager then
		useConfig(activeConfigName, true)
	end

	configTab:Paragraph({
		Title = "Persistent Configs",
		Desc = "Flags in this sample are registered to the current config. Executor runs with file APIs will save under Workspace/WindUI/"
			.. tostring(Window.Folder)
			.. "/config and autoload the selected config on the next execution.",
	})

	local configNameInput = configTab:Input({
		Title = "Config Name",
		Desc = "Choose the config file name to save or load.",
		Placeholder = defaultConfigName,
		Value = activeConfigName,
		InputIcon = "lucide:file-cog",
		Callback = function(value)
			if value ~= "" then
				activeConfigName = value
			end
		end,
	})

	local configListCode = configTab:Code({
		Title = "Available Configs",
		Code = "-- Config list will appear here.",
	})

	local autoloadCode = configTab:Code({
		Title = "Autoload Status",
		Code = "-- Autoload status will appear here.",
	})

	local function refreshConfigList()
		if not Window.ConfigManager then
			configListCode:SetCode("-- Config system is unavailable. Missing executor file APIs.")
			autoloadCode:SetCode("-- Autoload unavailable.")
			return
		end

		configListCode:SetCode("-- Saved Configs\nreturn " .. tostring(encode(Window.ConfigManager:AllConfigs())))
		autoloadCode:SetCode(table.concat({
			"-- Autoload Status",
			("active_config = %q"):format(tostring(activeConfigName)),
			("executor = %q"):format(tostring(executorName)),
			("file_api = %s"):format(tostring(hasFileApi and true or false)),
			("autoload = %s"):format(tostring(true)),
		}, "\n"))
	end

	local configActions = configTab:Section({
		Title = "Config Actions",
		Desc = "Use these buttons to exercise the config manager.",
		Box = true,
		BoxBorder = true,
		Opened = true,
	})

	configActions:Button({
		Title = "Save Config",
		Desc = "Create or overwrite the current config and keep autoload enabled.",
		Callback = function()
			local name = configNameInput.Value ~= "" and configNameInput.Value or activeConfigName
			local config, err = useConfig(name, true)
			if not config then
				notify("Config Error", err, "lucide:triangle-alert", 6)
				return
			end

			config:Set("executor", executorName)
			config:SetAutoLoad(true)
			if context.OnBeforeSave then
				context.OnBeforeSave(config, name)
			end
			config:Save()
			refreshConfigList()
			notify("Config Saved", "Saved and marked for autoload: " .. name, "lucide:save")
		end,
	})

	configActions:Button({
		Title = "Load Config",
		Desc = "Load values from the selected config file and set it as autoload target.",
		Callback = function()
			local name = configNameInput.Value ~= "" and configNameInput.Value or activeConfigName
			local config, err = useConfig(name, true)
			if not config then
				notify("Config Error", err, "lucide:triangle-alert", 6)
				return
			end

			local ok, result = config:Load()
			if ok == false then
				notify("Config Load Failed", tostring(result), "lucide:circle-x", 6)
				return
			end

			config:SetAutoLoad(true)
			if context.OnAfterLoad then
				context.OnAfterLoad(config, name, result)
			end
			refreshConfigList()
			notify("Config Loaded", "Loaded and marked for autoload: " .. name, "lucide:folder-open")
		end,
	})

	configActions:Button({
		Title = "Quick Save Default",
		Desc = "Save immediately to the default autoload config.",
		Callback = function()
			local config, err = useConfig(defaultConfigName, true)
			if not config then
				notify("Config Error", err, "lucide:triangle-alert", 6)
				return
			end

			configNameInput:Set(defaultConfigName)
			config:SetAutoLoad(true)
			config:Set("executor", executorName)
			if context.OnBeforeSave then
				context.OnBeforeSave(config, defaultConfigName)
			end
			config:Save()
			refreshConfigList()
			notify("Quick Saved", defaultConfigName .. " is ready for next executor run.", "lucide:bookmark-check")
		end,
	})

	configActions:Button({
		Title = "Delete Config",
		Desc = "Delete the selected config file.",
		Callback = function()
			if not Window.ConfigManager then
				notify("Config Error", "ConfigManager is unavailable.", "lucide:triangle-alert", 6)
				return
			end

			local name = configNameInput.Value ~= "" and configNameInput.Value or activeConfigName
			local ok, result = Window.ConfigManager:DeleteConfig(name)
			if not ok then
				notify("Delete Failed", tostring(result), "lucide:trash-2", 6)
				return
			end

			refreshConfigList()
			notify("Config Deleted", "Deleted config: " .. name, "lucide:trash-2")
		end,
	})

	configTab:Space()
	refreshConfigList()

	return {
		UseConfig = useConfig,
		Refresh = refreshConfigList,
		GetActiveName = function()
			return activeConfigName
		end,
		GetActiveConfig = function()
			return activeConfig
		end,
	}
end

return ConfigAddon
