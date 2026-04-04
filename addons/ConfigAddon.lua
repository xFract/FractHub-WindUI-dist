local ConfigAddon = {}

function ConfigAddon.Setup(context)
	local Window = context.Window
	local Tab = context.Tab
	local Notify = context.Notify
	local TrackedElements = context.TrackedElements or {}
	local DefaultConfigName = context.DefaultConfigName or "default"

	local activeConfig = nil
	local activeConfigName = DefaultConfigName
	local currentAutoloadName = nil

	local configNameInput
	local configFileDropdown
	local configFileCode
	local autoloadButton

	local function getConfigManager()
		return Window and Window.ConfigManager or nil
	end

	local function getAutoloadPath()
		local manager = getConfigManager()
		if not manager or not manager.Path then
			return nil
		end

		return manager.Path .. "autoload.txt"
	end

	local function readAutoloadName()
		local autoloadPath = getAutoloadPath()
		if not autoloadPath or not isfile or not isfile(autoloadPath) then
			return nil
		end

		local ok, value = pcall(readfile, autoloadPath)
		if not ok or type(value) ~= "string" or value == "" then
			return nil
		end

		return value
	end

	local function writeAutoloadName(configName)
		local autoloadPath = getAutoloadPath()
		if not autoloadPath or not writefile then
			return false, "writefile is unavailable"
		end

		local ok, err = pcall(writefile, autoloadPath, configName)
		if not ok then
			return false, tostring(err)
		end

		currentAutoloadName = configName
		return true
	end

	local function clearAutoloadName()
		local autoloadPath = getAutoloadPath()
		currentAutoloadName = nil

		if autoloadPath and delfile and isfile and isfile(autoloadPath) then
			pcall(delfile, autoloadPath)
		end
	end

	local function registerTracked(config)
		for flag, element in pairs(TrackedElements) do
			config:Register(flag, element)
		end
	end

	local function getInputConfigName()
		local value = configNameInput and configNameInput.Value or activeConfigName
		if type(value) ~= "string" then
			return activeConfigName
		end

		value = value:gsub("^%s+", ""):gsub("%s+$", "")
		if value == "" then
			return activeConfigName
		end

		return value
	end

	local function syncConfigName(name)
		activeConfigName = name

		if configNameInput then
			configNameInput:Set(name)
		end

		if configFileDropdown and configFileDropdown.Select then
			configFileDropdown:Select(name)
		end
	end

	local function updateAutoloadButton()
		if not autoloadButton then
			return
		end

		local current = currentAutoloadName or "none"
		local selected = activeConfigName or "none"
		local mode = currentAutoloadName == activeConfigName and "selected" or "not selected"

		autoloadButton:SetDesc("Current: " .. current .. " | Selected: " .. selected .. " | State: " .. mode)
	end

	local function refreshConfigFileList()
		local manager = getConfigManager()
		if not manager then
			if configFileCode then
				configFileCode:SetCode("-- ConfigManager unavailable")
			end
			if configFileDropdown and configFileDropdown.Refresh then
				configFileDropdown:Refresh({})
			end
			updateAutoloadButton()
			return
		end

		local files = manager:AllConfigs()
		table.sort(files)

		if configFileCode then
			configFileCode:SetCode(#files > 0 and table.concat(files, "\n") or "-- no config files found")
		end

		if configFileDropdown and configFileDropdown.Refresh then
			configFileDropdown:Refresh(files)
		end

		updateAutoloadButton()
	end

	local function createOrGetConfig(configName)
		local manager = getConfigManager()
		if not manager then
			return nil, "ConfigManager is unavailable."
		end

		local config = manager:GetConfig(configName)
		if not config then
			config = manager:CreateConfig(configName, false)
		end

		registerTracked(config)
		config:SetAutoLoad(false)
		config:SetAsCurrent()

		activeConfig = config
		activeConfigName = configName

		return config
	end

	local function createConfig(configName)
		local config, err = createOrGetConfig(configName)
		if not config then
			return nil, err
		end

		if context.OnBeforeSave then
			context.OnBeforeSave(config, configName)
		end

		local ok, result = pcall(function()
			return config:Save()
		end)
		if not ok then
			return nil, tostring(result)
		end

		syncConfigName(configName)
		refreshConfigFileList()
		return config
	end

	local function saveConfig(configName)
		local config, err = createOrGetConfig(configName)
		if not config then
			return false, err
		end

		if context.OnBeforeSave then
			context.OnBeforeSave(config, configName)
		end

		local ok, result = pcall(function()
			return config:Save()
		end)
		if not ok then
			return false, tostring(result)
		end

		syncConfigName(configName)
		refreshConfigFileList()
		return true, result
	end

	local function loadConfig(configName, silent)
		local config, err = createOrGetConfig(configName)
		if not config then
			return false, err
		end

		local ok, result = config:Load()
		if ok == false then
			return false, result
		end

		syncConfigName(configName)

		if context.OnAfterLoad then
			context.OnAfterLoad(config, configName, result)
		end

		refreshConfigFileList()

		if not silent then
			Notify("Load Config", "Loaded: " .. configName, "lucide:folder-open")
		end

		return true, result
	end

	local function deleteConfig(configName)
		local manager = getConfigManager()
		if not manager then
			return false, "ConfigManager is unavailable."
		end

		local ok, result = manager:DeleteConfig(configName)
		if not ok then
			return false, result
		end

		if currentAutoloadName == configName then
			clearAutoloadName()
		end

		if activeConfigName == configName then
			activeConfig = nil
		end

		refreshConfigFileList()
		return true
	end

	configFileCode = Tab:Code({
		Title = "Config Files",
		Code = "-- loading config files",
	})

	configNameInput = Tab:Input({
		Title = "Config Name",
		Desc = "Type a new name or edit the selected one.",
		Placeholder = DefaultConfigName,
		Value = activeConfigName,
		InputIcon = "lucide:file-cog",
		Callback = function(value)
			if type(value) == "string" and value:gsub("%s+", "") ~= "" then
				activeConfigName = value
				updateAutoloadButton()
			end
		end,
	})

	configFileDropdown = Tab:Dropdown({
		Title = "Config File",
		Desc = "Pick an existing config file.",
		Values = {},
		Value = nil,
		AllowNone = true,
		Callback = function(value)
			if type(value) == "string" and value ~= "" then
				syncConfigName(value)
				updateAutoloadButton()
			end
		end,
	})

	autoloadButton = Tab:Button({
		Title = "Auto Load",
		Desc = "Current: none | Selected: " .. tostring(activeConfigName) .. " | State: not selected",
		Callback = function()
			local configName = getInputConfigName()
			if configName == "" then
				Notify("Auto Load", "Select or enter a config name first.", "lucide:triangle-alert", 6)
				return
			end

			if currentAutoloadName == configName then
				clearAutoloadName()
				updateAutoloadButton()
				Notify("Auto Load", "Cleared autoload config.", "lucide:badge-x")
				return
			end

			local ok, err = writeAutoloadName(configName)
			if not ok then
				Notify("Auto Load", "Failed to set autoload: " .. tostring(err), "lucide:triangle-alert", 6)
				return
			end

			updateAutoloadButton()
			Notify("Auto Load", "Autoload set to: " .. configName, "lucide:badge-check")
		end,
	})

	Tab:Button({
		Title = "CreateConfig",
		Desc = "Create a new config immediately from the current UI state.",
		Callback = function()
			local configName = getInputConfigName()
			local _, err = createConfig(configName)
			if err then
				Notify("CreateConfig", tostring(err), "lucide:triangle-alert", 6)
				return
			end

			Notify("CreateConfig", "Created: " .. configName, "lucide:file-plus-2")
		end,
	})

	Tab:Button({
		Title = "Save Config",
		Desc = "Overwrite or create the selected config.",
		Callback = function()
			local configName = getInputConfigName()
			local ok, err = saveConfig(configName)
			if not ok then
				Notify("Save Config", tostring(err), "lucide:triangle-alert", 6)
				return
			end

			Notify("Save Config", "Saved: " .. configName, "lucide:save")
		end,
	})

	Tab:Button({
		Title = "Load Config",
		Desc = "Load the selected config into the current UI.",
		Callback = function()
			local configName = getInputConfigName()
			local ok, err = loadConfig(configName, false)
			if not ok then
				Notify("Load Config", tostring(err), "lucide:triangle-alert", 6)
			end
		end,
	})

	Tab:Button({
		Title = "Delete Config",
		Desc = "Delete the selected config file.",
		Callback = function()
			local configName = getInputConfigName()
			local ok, err = deleteConfig(configName)
			if not ok then
				Notify("Delete Config", tostring(err), "lucide:triangle-alert", 6)
				return
			end

			Notify("Delete Config", "Deleted: " .. configName, "lucide:trash-2")
		end,
	})

	currentAutoloadName = readAutoloadName()
	refreshConfigFileList()

	if currentAutoloadName then
		task.defer(function()
			local ok, err = loadConfig(currentAutoloadName, true)
			if ok then
				Notify("Auto Load", "Loaded: " .. currentAutoloadName, "lucide:hard-drive-download", 6)
			else
				Notify("Auto Load", "Failed to load " .. tostring(currentAutoloadName) .. ": " .. tostring(err), "lucide:triangle-alert", 7)
			end
		end)
	end

	return {
		GetActiveName = function()
			return activeConfigName
		end,
		GetActiveConfig = function()
			return activeConfig
		end,
		GetAutoloadName = function()
			return currentAutoloadName
		end,
		Refresh = refreshConfigFileList,
	}
end

return ConfigAddon
