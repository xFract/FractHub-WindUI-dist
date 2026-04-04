local HttpService = game:GetService("HttpService")

local ConfigAddon = {}

function ConfigAddon.Setup(context)
	local Window = context.Window
	local Tab = context.Tab
	local Notify = context.Notify
	local TrackedElements = context.TrackedElements or {}
	local DefaultConfigName = context.DefaultConfigName or "default"
	local BatchSize = context.LoadBatchSize or 8
	local BatchDelay = context.LoadYieldDelay or 0

	local activeConfigName = DefaultConfigName
	local currentAutoloadName = nil
	local isBusy = false

	local configNameInput
	local configFileDropdown
	local configFileCode
	local autoloadButton

	local function getManager()
		return Window and Window.ConfigManager or nil
	end

	local function getConfigPath()
		local manager = getManager()
		if manager and manager.Path then
			return manager.Path
		end

		return nil
	end

	local function ensureConfigPath()
		local path = getConfigPath()
		if not path then
			return nil, "Config path is unavailable."
		end

		if isfolder and not isfolder(path) and makefolder then
			makefolder(path)
		end

		return path
	end

	local function getConfigFilePath(configName)
		local path, err = ensureConfigPath()
		if not path then
			return nil, err
		end

		return path .. configName .. ".json"
	end

	local function getAutoloadPath()
		local path, err = ensureConfigPath()
		if not path then
			return nil, err
		end

		return path .. "autoload.txt"
	end

	local function getConfigName()
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

	local function refreshAutoloadButton()
		if not autoloadButton then
			return
		end

		local current = currentAutoloadName or "none"
		local selected = activeConfigName or "none"
		local state = currentAutoloadName == activeConfigName and "selected" or "not selected"

		autoloadButton:SetDesc("Current: " .. current .. " | Selected: " .. selected .. " | State: " .. state)
	end

	local function getConfigFiles()
		local path = getConfigPath()
		if not path or not listfiles then
			return {}
		end

		local files = {}
		for _, file in next, listfiles(path) do
			local name = file:match("([^\\/]+)%.json$")
			if name then
				table.insert(files, name)
			end
		end

		table.sort(files)
		return files
	end

	local function refreshConfigFiles()
		local files = getConfigFiles()

		if configFileCode then
			configFileCode:SetCode(#files > 0 and table.concat(files, "\n") or "-- no config files found")
		end

		if configFileDropdown and configFileDropdown.Refresh then
			configFileDropdown:Refresh(files)
		end

		refreshAutoloadButton()
		return files
	end

	local function readAutoloadName()
		local path = getAutoloadPath()
		if not path or not isfile or not isfile(path) then
			return nil
		end

		local ok, value = pcall(readfile, path)
		if not ok or type(value) ~= "string" or value == "" then
			return nil
		end

		return value
	end

	local function setAutoloadName(configName)
		local path, err = getAutoloadPath()
		if not path or not writefile then
			return false, err or "writefile is unavailable"
		end

		local ok, writeErr = pcall(writefile, path, configName)
		if not ok then
			return false, tostring(writeErr)
		end

		currentAutoloadName = configName
		refreshAutoloadButton()
		return true
	end

	local function clearAutoloadName()
		local path = getAutoloadPath()
		currentAutoloadName = nil

		if path and delfile and isfile and isfile(path) then
			pcall(delfile, path)
		end

		refreshAutoloadButton()
	end

	local function buildSaveData()
		local manager = getManager()
		if not manager then
			return nil, "ConfigManager is unavailable."
		end

		local saveData = {
			__version = 2,
			__elements = {},
			__custom = context.BuildCustomData and context.BuildCustomData() or {},
		}

		for flag, element in pairs(TrackedElements) do
			local parser = manager.Parser[element.__type]
			if parser and parser.Save then
				local ok, parsed = pcall(parser.Save, element)
				if ok and parsed then
					saveData.__elements[flag] = parsed
				end
			end
		end

		return saveData
	end

	local function withSuppressedCallbacks(callback)
		local originals = {}

		for _, element in pairs(TrackedElements) do
			if element and element.Callback ~= nil then
				originals[element] = element.Callback
				element.Callback = function() end
			end
		end

		local ok, result = pcall(callback)

		for element, original in pairs(originals) do
			element.Callback = original
		end

		if not ok then
			return false, result
		end

		return true, result
	end

	local function saveConfig(configName)
		if isBusy then
			return false, "Config operation already in progress."
		end

		local filePath, err = getConfigFilePath(configName)
		if not filePath then
			return false, err
		end
		if not writefile then
			return false, "writefile is unavailable"
		end

		local saveData, buildErr = buildSaveData()
		if not saveData then
			return false, buildErr
		end

		local ok, encoded = pcall(function()
			return HttpService:JSONEncode(saveData)
		end)
		if not ok then
			return false, tostring(encoded)
		end

		isBusy = true
		local writeOk, writeErr = pcall(writefile, filePath, encoded)
		isBusy = false
		if not writeOk then
			return false, tostring(writeErr)
		end

		syncConfigName(configName)
		refreshConfigFiles()
		return true
	end

	local function createConfig(configName)
		local filePath, err = getConfigFilePath(configName)
		if not filePath then
			return false, err
		end
		if isfile and isfile(filePath) then
			return false, "Config already exists."
		end

		return saveConfig(configName)
	end

	local function loadConfig(configName, silent)
		if isBusy then
			return false, "Config operation already in progress."
		end

		local manager = getManager()
		if not manager then
			return false, "ConfigManager is unavailable."
		end

		local filePath, err = getConfigFilePath(configName)
		if not filePath then
			return false, err
		end
		if not isfile or not isfile(filePath) then
			return false, "Config file does not exist."
		end

		local ok, decoded = pcall(function()
			return HttpService:JSONDecode(readfile(filePath))
		end)
		if not ok then
			return false, "Failed to parse config file."
		end

		local entries = {}
		for flag, data in pairs(decoded.__elements or {}) do
			table.insert(entries, { flag = flag, data = data })
		end
		table.sort(entries, function(a, b)
			return tostring(a.flag) < tostring(b.flag)
		end)

		syncConfigName(configName)
		isBusy = true

		task.spawn(function()
			local success, loadErr = withSuppressedCallbacks(function()
				for index, entry in ipairs(entries) do
					local element = TrackedElements[entry.flag]
					local parser = element and manager.Parser[entry.data.__type]

					if element and parser and parser.Load then
						local applyOk, applyErr = pcall(parser.Load, element, entry.data)
						if not applyOk then
							warn("[ConfigAddon] Failed to load flag " .. tostring(entry.flag) .. ": " .. tostring(applyErr))
						end
					end

					if index % BatchSize == 0 then
						task.wait(BatchDelay)
					end
				end
			end)

			isBusy = false

			if not success then
				Notify("Load Config", "Failed while applying config: " .. tostring(loadErr), "lucide:triangle-alert", 7)
				return
			end

			if context.ApplyCustomData then
				pcall(context.ApplyCustomData, decoded.__custom or {}, configName)
			end

			if context.OnAfterLoad then
				pcall(context.OnAfterLoad, decoded.__custom or {}, configName)
			end

			refreshConfigFiles()

			if not silent then
				Notify("Load Config", "Loaded: " .. configName, "lucide:folder-open")
			end
		end)

		return true
	end

	local function deleteConfig(configName)
		if isBusy then
			return false, "Config operation already in progress."
		end

		local filePath, err = getConfigFilePath(configName)
		if not filePath then
			return false, err
		end
		if not delfile then
			return false, "delfile is unavailable"
		end
		if not isfile or not isfile(filePath) then
			return false, "Config file does not exist."
		end

		local ok, deleteErr = pcall(delfile, filePath)
		if not ok then
			return false, tostring(deleteErr)
		end

		if currentAutoloadName == configName then
			clearAutoloadName()
		end

		refreshConfigFiles()
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
				refreshAutoloadButton()
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
				refreshAutoloadButton()
			end
		end,
	})

	autoloadButton = Tab:Button({
		Title = "Auto Load",
		Desc = "Current: none | Selected: " .. tostring(activeConfigName) .. " | State: not selected",
		Callback = function()
			local configName = getConfigName()
			if configName == "" then
				Notify("Auto Load", "Select or enter a config name first.", "lucide:triangle-alert", 6)
				return
			end

			if currentAutoloadName == configName then
				clearAutoloadName()
				Notify("Auto Load", "Cleared autoload config.", "lucide:badge-x")
				return
			end

			local ok, err = setAutoloadName(configName)
			if not ok then
				Notify("Auto Load", "Failed to set autoload: " .. tostring(err), "lucide:triangle-alert", 6)
				return
			end

			Notify("Auto Load", "Autoload set to: " .. configName, "lucide:badge-check")
		end,
	})

	Tab:Button({
		Title = "CreateConfig",
		Desc = "Create a new config from the current UI state.",
		Callback = function()
			local configName = getConfigName()
			local ok, err = createConfig(configName)
			if not ok then
				Notify("CreateConfig", tostring(err), "lucide:triangle-alert", 6)
				return
			end

			Notify("CreateConfig", "Created: " .. configName, "lucide:file-plus-2")
		end,
	})

	Tab:Button({
		Title = "Save Config",
		Desc = "Overwrite the selected config with current UI state.",
		Callback = function()
			local configName = getConfigName()
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
		Desc = "Load the selected config with batched, callback-suppressed apply.",
		Callback = function()
			local configName = getConfigName()
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
			local configName = getConfigName()
			local ok, err = deleteConfig(configName)
			if not ok then
				Notify("Delete Config", tostring(err), "lucide:triangle-alert", 6)
				return
			end

			Notify("Delete Config", "Deleted: " .. configName, "lucide:trash-2")
		end,
	})

	currentAutoloadName = readAutoloadName()
	refreshConfigFiles()

	if currentAutoloadName then
		task.defer(function()
			local ok, err = loadConfig(currentAutoloadName, true)
			if not ok then
				Notify("Auto Load", "Failed to load " .. tostring(currentAutoloadName) .. ": " .. tostring(err), "lucide:triangle-alert", 7)
			else
				Notify("Auto Load", "Loaded: " .. currentAutoloadName, "lucide:hard-drive-download", 6)
			end
		end)
	end

	return {
		GetActiveName = function()
			return activeConfigName
		end,
		GetAutoloadName = function()
			return currentAutoloadName
		end,
		Refresh = refreshConfigFiles,
	}
end

return ConfigAddon
