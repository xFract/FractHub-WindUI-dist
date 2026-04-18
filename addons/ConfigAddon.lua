local HttpService = game:GetService("HttpService")

local ConfigAddon = {}

function ConfigAddon.Setup(context)
	context = type(context) == "table" and context or {}

	local Window = context.Window
	local Tab = context.Tab
	local Notify = type(context.Notify) == "function" and context.Notify or function(title, message)
		warn("[ConfigAddon] " .. tostring(title) .. ": " .. tostring(message))
	end
	local TrackedElements = context.TrackedElements or {}
	local DefaultConfigName = context.DefaultConfigName or "default"
	local LoadBatchSize = math.max(1, math.floor(tonumber(context.LoadBatchSize) or 12))
	local LoadYieldDelay = math.max(0, tonumber(context.LoadYieldDelay) or 0)

	local activeConfigName = type(DefaultConfigName) == "string" and DefaultConfigName or "default"
	local currentAutoloadName = nil
	local busy = false

	local configNameInput
	local configFileDropdown
	local autoloadButton
	local getConfigName

	local function notifySafe(...)
		local ok, err = pcall(Notify, ...)
		if not ok then
			warn("[ConfigAddon] Notify failed: " .. tostring(err))
		end
	end

	local function normalizeDirectoryPath(path)
		if type(path) ~= "string" or path == "" then
			return nil
		end

		if not path:match("[/\\]$") then
			path = path .. "/"
		end

		return path
	end

	local function sanitizeConfigName(value)
		if type(value) ~= "string" then
			return nil
		end

		value = value:gsub("^%s+", ""):gsub("%s+$", "")
		value = value:gsub("[<>:\"/\\|%?%*%c]", "_")
		value = value:gsub("%.+$", "")
		value = value:gsub("^%.+", "")
		value = value:gsub("%s+$", "")

		if value == "" then
			return nil
		end

		if #value > 64 then
			value = value:sub(1, 64)
		end

		return value
	end

	local function getSelectedConfigName()
		local normalized = sanitizeConfigName(getConfigName and getConfigName() or activeConfigName)
		if normalized then
			return normalized
		end

		return sanitizeConfigName(activeConfigName) or sanitizeConfigName(DefaultConfigName) or "default"
	end

	local function safeIsFile(path)
		if not path or not isfile then
			return false
		end

		local ok, result = pcall(isfile, path)
		return ok and result == true
	end

	local function safeReadFile(path)
		if not path or not readfile then
			return false, "readfile is unavailable."
		end

		local ok, result = pcall(readfile, path)
		if not ok then
			return false, tostring(result)
		end

		return true, result
	end

	local function safeWriteFile(path, content)
		if not path or not writefile then
			return false, "writefile is unavailable."
		end

		local ok, result = pcall(writefile, path, content)
		if not ok then
			return false, tostring(result)
		end

		return true
	end

	local function safeDeleteFile(path)
		if not path or not delfile then
			return false, "delfile is unavailable."
		end

		local ok, result = pcall(delfile, path)
		if not ok then
			return false, tostring(result)
		end

		return true
	end

	if not Window or not Tab then
		warn("[ConfigAddon] Setup requires both Window and Tab.")
		return {
			GetActiveName = function()
				return activeConfigName
			end,
			GetAutoloadName = function()
				return nil
			end,
			Refresh = function()
				return {}
			end,
		}
	end

	local function getManager()
		return Window and Window.ConfigManager or nil
	end

	local function getBasePath()
		local manager = getManager()
		if manager and manager.Path then
			return normalizeDirectoryPath(manager.Path)
		end
		return nil
	end

	local function ensureBasePath()
		local path = getBasePath()
		if not path then
			return nil, "Config path is unavailable."
		end

		if isfolder and makefolder then
			local folderOk, exists = pcall(isfolder, path)
			if not folderOk then
				return nil, "Failed to query config path."
			end

			if not exists then
				local createOk, createErr = pcall(makefolder, path)
				if not createOk then
					return nil, tostring(createErr)
				end
			end
		end

		return path
	end

	local function getConfigPath(configName)
		configName = sanitizeConfigName(configName)
		if not configName then
			return nil, "Config name is invalid."
		end

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

	getConfigName = function()
		local value = configNameInput and configNameInput.Value or activeConfigName
		return sanitizeConfigName(value) or sanitizeConfigName(activeConfigName) or sanitizeConfigName(DefaultConfigName) or "default"
	end

	local function readAutoload()
		local path = getAutoloadPath()
		if not path or not safeIsFile(path) then
			return nil
		end

		local ok, value = safeReadFile(path)
		if not ok or type(value) ~= "string" then
			return nil
		end

		return sanitizeConfigName(value)
	end

	local function writeAutoload(configName)
		configName = sanitizeConfigName(configName)
		if not configName then
			return false, "Config name is invalid."
		end

		local path, err = getAutoloadPath()
		if not path then
			return false, err
		end

		local ok, writeErr = safeWriteFile(path, configName)
		if not ok then
			return false, writeErr
		end

		currentAutoloadName = configName
		return true
	end

	local function clearAutoload()
		local path = getAutoloadPath()
		currentAutoloadName = nil

		if path and safeIsFile(path) then
			safeDeleteFile(path)
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

		local ok, listedFiles = pcall(listfiles, path)
		if not ok or type(listedFiles) ~= "table" then
			return {}
		end

		local files = {}
		for _, file in next, listedFiles do
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
		if payload ~= nil and payload.value ~= nil then
			return payload.value
		end

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

		local customData = {}
		if context.BuildCustomData then
			local customOk, customResult = pcall(context.BuildCustomData)
			if not customOk then
				return nil, "Failed to build custom config data."
			end

			if customResult ~= nil and type(customResult) ~= "table" then
				return nil, "Custom config data must be a table."
			end

			customData = customResult or {}
		end

		local data = {
			__version = 1,
			__elements = {},
			__custom = customData,
		}

		for flag, element in pairs(TrackedElements) do
			local parser = element and manager.Parser and manager.Parser[element.__type]
			if parser and parser.Save then
				local ok, result = pcall(parser.Save, element)
				if ok and result then
					data.__elements[flag] = result
				elseif not ok then
					warn("[ConfigAddon] Failed to save " .. tostring(flag) .. ": " .. tostring(result))
				end
			end
		end

		return data
	end

	local function saveConfig(configName, failIfExists)
		if busy then
			return false, "Config operation already in progress."
		end

		configName = sanitizeConfigName(configName)
		if not configName then
			return false, "Config name is invalid."
		end

		local filePath, err = getConfigPath(configName)
		if not filePath then
			return false, err
		end

		if failIfExists and safeIsFile(filePath) then
			return false, "Config already exists."
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
		local writeOk, writeErr = safeWriteFile(filePath, encoded)
		busy = false
		if not writeOk then
			return false, writeErr
		end

		activeConfigName = configName
		if configNameInput and configNameInput.Set then
			configNameInput:Set(configName)
		end
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

		configName = sanitizeConfigName(configName)
		if not configName then
			return false, "Config name is invalid."
		end

		local filePath, err = getConfigPath(configName)
		if not filePath then
			return false, err
		end

		if not safeIsFile(filePath) then
			return false, "Config file does not exist."
		end

		local readOk, rawData = safeReadFile(filePath)
		if not readOk then
			return false, rawData
		end

		local decodeOk, decoded = pcall(function()
			return HttpService:JSONDecode(rawData)
		end)
		if not decodeOk or type(decoded) ~= "table" then
			return false, "Failed to parse config file."
		end

		if decoded.__version == nil and decoded.__elements == nil then
			decoded = {
				__version = 0,
				__elements = decoded,
				__custom = {},
			}
		end

		if decoded.__elements ~= nil and type(decoded.__elements) ~= "table" then
			return false, "Config data is corrupted."
		end

		if decoded.__custom ~= nil and type(decoded.__custom) ~= "table" then
			decoded.__custom = {}
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
					local payload = type(entry.Payload) == "table" and entry.Payload or nil
					local parserType = payload and payload.__type
					local parser = element and parserType and manager.Parser and manager.Parser[parserType]

					if element and parser and parser.Load and payload then
						local applyOk, applyErr = pcall(parser.Load, element, payload)
						if not applyOk then
							warn("[ConfigAddon] Failed to load " .. tostring(entry.Flag) .. ": " .. tostring(applyErr))
						end
					elseif element and entry.Payload ~= nil and not payload then
						warn("[ConfigAddon] Skipped invalid payload for " .. tostring(entry.Flag))
					end

					if index % LoadBatchSize == 0 then
						task.wait(LoadYieldDelay)
					end
				end
			end)

			busy = false

			if not ok then
				notifySafe("Load Config", "Failed while applying config: " .. tostring(loadErr), "lucide:triangle-alert", 7)
				return
			end

			if context.ApplyCustomData then
				local customOk, customErr = pcall(context.ApplyCustomData, decoded.__custom or {}, configName)
				if not customOk then
					warn("[ConfigAddon] Failed to apply custom data: " .. tostring(customErr))
				end
			end

			syncTrackedCallbacks(entries)

			if context.OnAfterLoad then
				local afterLoadOk, afterLoadErr = pcall(context.OnAfterLoad, decoded.__custom or {}, configName)
				if not afterLoadOk then
					warn("[ConfigAddon] OnAfterLoad failed: " .. tostring(afterLoadErr))
				end
			end

			if not silent then
				notifySafe("Load Config", "Loaded: " .. configName, "lucide:folder-open")
			end
		end)

		return true
	end

	local function deleteConfig(configName)
		if busy then
			return false, "Config operation already in progress."
		end

		configName = sanitizeConfigName(configName)
		if not configName then
			return false, "Config name is invalid."
		end

		local filePath, err = getConfigPath(configName)
		if not filePath then
			return false, err
		end

		if not safeIsFile(filePath) then
			return false, "Config file does not exist."
		end

		local ok, deleteErr = safeDeleteFile(filePath)
		if not ok then
			return false, deleteErr
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
			local normalized = sanitizeConfigName(value)
			if normalized then
				activeConfigName = normalized
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
			local normalized = sanitizeConfigName(value)
			if normalized then
				activeConfigName = normalized
				if configNameInput then
					configNameInput:Set(normalized)
				end
				refreshAutoloadButton()
			end
		end,
	})

	autoloadButton = Tab:Button({
		Title = "Auto Load",
		Desc = "Current: none | Selected: " .. tostring(activeConfigName),
		Callback = function()
			local configName = getSelectedConfigName()
			if currentAutoloadName == configName then
				clearAutoload()
				notifySafe("Auto Load", "Cleared autoload config.", "lucide:badge-x")
				return
			end

			local ok, err = writeAutoload(configName)
			if not ok then
				notifySafe("Auto Load", tostring(err), "lucide:triangle-alert", 6)
				return
			end

			refreshAutoloadButton()
			notifySafe("Auto Load", "Autoload set to: " .. configName, "lucide:badge-check")
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
			local configName = getSelectedConfigName()
			local ok, err = saveConfig(configName, true)
			if not ok then
				notifySafe("CreateConfig", tostring(err), "lucide:triangle-alert", 6)
				return
			end

			notifySafe("CreateConfig", "Created: " .. configName, "lucide:file-plus-2")
		end,
	})

	Tab:Button({
		Title = "Save Config",
		Desc = "Overwrite the selected config.",
		Callback = function()
			local configName = getSelectedConfigName()
			local ok, err = saveConfig(configName, false)
			if not ok then
				notifySafe("Save Config", tostring(err), "lucide:triangle-alert", 6)
				return
			end

			notifySafe("Save Config", "Saved: " .. configName, "lucide:save")
		end,
	})

	Tab:Button({
		Title = "Load Config",
		Desc = "Load config with suppressed callbacks.",
		Callback = function()
			local configName = getSelectedConfigName()
			local ok, err = loadConfig(configName, false)
			if not ok then
				notifySafe("Load Config", tostring(err), "lucide:triangle-alert", 6)
			end
		end,
	})

	Tab:Button({
		Title = "Delete Config",
		Desc = "Delete the selected config.",
		Callback = function()
			local configName = getSelectedConfigName()
			local ok, err = deleteConfig(configName)
			if not ok then
				notifySafe("Delete Config", tostring(err), "lucide:triangle-alert", 6)
				return
			end

			notifySafe("Delete Config", "Deleted: " .. configName, "lucide:trash-2")
		end,
	})

	currentAutoloadName = readAutoload()
	refreshConfigFiles()

	if currentAutoloadName then
		task.defer(function()
			local ok, err = loadConfig(currentAutoloadName, true)
			if ok then
				notifySafe("Auto Load", "Loaded: " .. currentAutoloadName, "lucide:hard-drive-download", 6)
			else
				notifySafe("Auto Load", "Failed: " .. tostring(err), "lucide:triangle-alert", 7)
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
