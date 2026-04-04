local HttpService = game:GetService("HttpService")

local ConfigAddon = {}

function ConfigAddon.Setup(context)
	local Window = context.Window
	local Tab = context.Tab
	local Notify = context.Notify
	local TrackedElements = context.TrackedElements or {}
	local DefaultConfigName = context.DefaultConfigName or "default"
	local LoadBatchSize = context.LoadBatchSize or 12
	local LoadYieldDelay = context.LoadYieldDelay or 0

	local activeConfigName = DefaultConfigName
	local currentAutoloadName = nil
	local busy = false

	local configNameInput
	local configFileDropdown
	local autoloadButton

	local function getManager()
		return Window and Window.ConfigManager or nil
	end

	local function getBasePath()
		local manager = getManager()
		if manager and manager.Path then
			return manager.Path
		end
		return nil
	end

	local function ensureBasePath()
		local path = getBasePath()
		if not path then
			return nil, "Config path is unavailable."
		end

		if isfolder and not isfolder(path) and makefolder then
			makefolder(path)
		end

		return path
	end

	local function getConfigPath(configName)
		local path, err = ensureBasePath()
		if not path then
			return nil, err
		end

		return path .. configName .. ".json"
	end

	local function getAutoloadPath()
		local path, err = ensureBasePath()
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

	local function readAutoload()
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

	local function writeAutoload(configName)
		local path, err = getAutoloadPath()
		if not path or not writefile then
			return false, err or "writefile is unavailable"
		end

		local ok, writeErr = pcall(writefile, path, configName)
		if not ok then
			return false, tostring(writeErr)
		end

		currentAutoloadName = configName
		return true
	end

	local function clearAutoload()
		local path = getAutoloadPath()
		currentAutoloadName = nil

		if path and delfile and isfile and isfile(path) then
			pcall(delfile, path)
		end
	end

	local function refreshAutoloadButton()
		if not autoloadButton then
			return
		end

		local current = currentAutoloadName or "none"
		local selected = getConfigName()
		autoloadButton:SetDesc("Current: " .. current .. " | Selected: " .. selected)
	end

	local function getConfigFiles()
		local path = getBasePath()
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

	local function refreshConfigFiles(selectName)
		local files = getConfigFiles()
		if configFileDropdown and configFileDropdown.Refresh then
			configFileDropdown:Refresh(files)
		end

		if selectName and configFileDropdown and configFileDropdown.Select then
			configFileDropdown:Select(selectName)
		end

		refreshAutoloadButton()
		return files
	end

	local function suppressCallbacks(callback)
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

		return ok, result
	end

	local function getElementCallbackValue(element, payload)
		if payload ~= nil and payload.Value ~= nil then
			return payload.Value
		end

		if element ~= nil and element.Value ~= nil then
			return element.Value
		end

		return nil
	end

	local function syncTrackedCallbacks(entries)
		for _, entry in ipairs(entries) do
			local element = TrackedElements[entry.Flag]
			if element and type(element.Callback) == "function" then
				local callbackValue = getElementCallbackValue(element, entry.Payload)
				local ok, err = pcall(element.Callback, callbackValue)
				if not ok then
					warn("[ConfigAddon] Failed to sync callback for " .. tostring(entry.Flag) .. ": " .. tostring(err))
				end
			end
		end
	end

	local function buildSaveData()
		local manager = getManager()
		if not manager then
			return nil, "ConfigManager is unavailable."
		end

		local data = {
			__version = 1,
			__elements = {},
			__custom = context.BuildCustomData and context.BuildCustomData() or {},
		}

		for flag, element in pairs(TrackedElements) do
			local parser = manager.Parser[element.__type]
			if parser and parser.Save then
				local ok, result = pcall(parser.Save, element)
				if ok and result then
					data.__elements[flag] = result
				end
			end
		end

		return data
	end

	local function saveConfig(configName, failIfExists)
		if busy then
			return false, "Config operation already in progress."
		end

		local filePath, err = getConfigPath(configName)
		if not filePath then
			return false, err
		end

		if failIfExists and isfile and isfile(filePath) then
			return false, "Config already exists."
		end

		if not writefile then
			return false, "writefile is unavailable."
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

		busy = true
		local writeOk, writeErr = pcall(writefile, filePath, encoded)
		busy = false
		if not writeOk then
			return false, tostring(writeErr)
		end

		activeConfigName = configName
		refreshConfigFiles(configName)
		return true
	end

	local function loadConfig(configName, silent)
		if busy then
			return false, "Config operation already in progress."
		end

		local manager = getManager()
		if not manager then
			return false, "ConfigManager is unavailable."
		end

		local filePath, err = getConfigPath(configName)
		if not filePath then
			return false, err
		end

		if not isfile or not isfile(filePath) then
			return false, "Config file does not exist."
		end

		local decodeOk, decoded = pcall(function()
			return HttpService:JSONDecode(readfile(filePath))
		end)
		if not decodeOk then
			return false, "Failed to parse config file."
		end

		local entries = {}
		for flag, payload in pairs(decoded.__elements or {}) do
			table.insert(entries, { Flag = flag, Payload = payload })
		end
		table.sort(entries, function(a, b)
			return tostring(a.Flag) < tostring(b.Flag)
		end)

		activeConfigName = configName
		refreshConfigFiles(configName)
		busy = true

		task.spawn(function()
			local ok, loadErr = suppressCallbacks(function()
				for index, entry in ipairs(entries) do
					local element = TrackedElements[entry.Flag]
					local parser = element and manager.Parser[entry.Payload.__type]

					if element and parser and parser.Load then
						local applyOk, applyErr = pcall(parser.Load, element, entry.Payload)
						if not applyOk then
							warn("[ConfigAddon] Failed to load " .. tostring(entry.Flag) .. ": " .. tostring(applyErr))
						end
					end

					if index % LoadBatchSize == 0 then
						task.wait(LoadYieldDelay)
					end
				end
			end)

			busy = false

			if not ok then
				Notify("Load Config", "Failed while applying config: " .. tostring(loadErr), "lucide:triangle-alert", 7)
				return
			end

			if context.ApplyCustomData then
				pcall(context.ApplyCustomData, decoded.__custom or {}, configName)
			end

			syncTrackedCallbacks(entries)

			if context.OnAfterLoad then
				pcall(context.OnAfterLoad, decoded.__custom or {}, configName)
			end

			if not silent then
				Notify("Load Config", "Loaded: " .. configName, "lucide:folder-open")
			end
		end)

		return true
	end

	local function deleteConfig(configName)
		if busy then
			return false, "Config operation already in progress."
		end

		local filePath, err = getConfigPath(configName)
		if not filePath then
			return false, err
		end

		if not delfile then
			return false, "delfile is unavailable."
		end

		if not isfile or not isfile(filePath) then
			return false, "Config file does not exist."
		end

		local ok, deleteErr = pcall(delfile, filePath)
		if not ok then
			return false, tostring(deleteErr)
		end

		if currentAutoloadName == configName then
			clearAutoload()
		end

		refreshConfigFiles()
		return true
	end

	configNameInput = Tab:Input({
		Title = "Config Name",
		Desc = "New or selected config name.",
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
		Desc = "Existing config files.",
		Values = {},
		Value = nil,
		AllowNone = true,
		Callback = function(value)
			if type(value) == "string" and value ~= "" then
				activeConfigName = value
				if configNameInput then
					configNameInput:Set(value)
				end
				refreshAutoloadButton()
			end
		end,
	})

	autoloadButton = Tab:Button({
		Title = "Auto Load",
		Desc = "Current: none | Selected: " .. tostring(activeConfigName),
		Callback = function()
			local configName = getConfigName()
			if currentAutoloadName == configName then
				clearAutoload()
				Notify("Auto Load", "Cleared autoload config.", "lucide:badge-x")
				return
			end

			local ok, err = writeAutoload(configName)
			if not ok then
				Notify("Auto Load", tostring(err), "lucide:triangle-alert", 6)
				return
			end

			refreshAutoloadButton()
			Notify("Auto Load", "Autoload set to: " .. configName, "lucide:badge-check")
		end,
	})

	Tab:Button({
		Title = "Refresh List",
		Desc = "Refresh config file list.",
		Callback = function()
			refreshConfigFiles()
		end,
	})

	Tab:Button({
		Title = "CreateConfig",
		Desc = "Create a new config.",
		Callback = function()
			local configName = getConfigName()
			local ok, err = saveConfig(configName, true)
			if not ok then
				Notify("CreateConfig", tostring(err), "lucide:triangle-alert", 6)
				return
			end

			Notify("CreateConfig", "Created: " .. configName, "lucide:file-plus-2")
		end,
	})

	Tab:Button({
		Title = "Save Config",
		Desc = "Overwrite the selected config.",
		Callback = function()
			local configName = getConfigName()
			local ok, err = saveConfig(configName, false)
			if not ok then
				Notify("Save Config", tostring(err), "lucide:triangle-alert", 6)
				return
			end

			Notify("Save Config", "Saved: " .. configName, "lucide:save")
		end,
	})

	Tab:Button({
		Title = "Load Config",
		Desc = "Load config with suppressed callbacks.",
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
		Desc = "Delete the selected config.",
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

	currentAutoloadName = readAutoload()
	refreshConfigFiles()

	if currentAutoloadName then
		task.defer(function()
			local ok, err = loadConfig(currentAutoloadName, true)
			if ok then
				Notify("Auto Load", "Loaded: " .. currentAutoloadName, "lucide:hard-drive-download", 6)
			else
				Notify("Auto Load", "Failed: " .. tostring(err), "lucide:triangle-alert", 7)
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
