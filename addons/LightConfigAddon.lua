local HttpService = game:GetService("HttpService")

local LightConfigAddon = {}

function LightConfigAddon.Setup(context)
	context = type(context) == "table" and context or {}

	local Window = context.Window
	local Tab = context.Tab
	local TrackedElements = type(context.TrackedElements) == "table" and context.TrackedElements or {}
	local DefaultConfigName = context.DefaultConfigName or "default"
	local Notify = type(context.Notify) == "function" and context.Notify or function(title, message)
		warn("[LightConfigAddon] " .. tostring(title) .. ": " .. tostring(message))
	end

	local activeConfigName = type(DefaultConfigName) == "string" and DefaultConfigName or "default"
	local configNameInput
	local configDropdown

	local function notifySafe(...)
		local ok, err = pcall(Notify, ...)
		if not ok then
			warn("[LightConfigAddon] Notify failed: " .. tostring(err))
		end
	end

	local function sanitizeName(value)
		if type(value) ~= "string" then
			return nil
		end

		value = value:gsub("^%s+", ""):gsub("%s+$", "")
		value = value:gsub("[<>:\"/\\|%?%*%c]", "_")
		value = value:gsub("^%.+", ""):gsub("%.+$", "")

		if value == "" then
			return nil
		end

		return value:sub(1, 64)
	end

	local function getSelectedName()
		local inputValue = configNameInput and configNameInput.Value or activeConfigName
		return sanitizeName(inputValue) or sanitizeName(activeConfigName) or "default"
	end

	local function getManager()
		return Window and Window.ConfigManager or nil
	end

	local function getBasePath()
		local manager = getManager()
		local path = manager and manager.Path
		if type(path) ~= "string" or path == "" then
			return nil
		end

		path = path:gsub("\\", "/")
		if not path:match("/$") then
			path = path .. "/"
		end

		return path
	end

	local function ensureFolder(path)
		if not path then
			return false, "Config path is unavailable."
		end

		if not (isfolder and makefolder) then
			return true
		end

		local normalized = path:gsub("\\", "/"):gsub("/+$", "")
		local prefix = ""
		local parts = {}

		if normalized:match("^[A-Za-z]:/") then
			prefix = normalized:sub(1, 3)
			normalized = normalized:sub(4)
		elseif normalized:sub(1, 1) == "/" then
			prefix = "/"
			normalized = normalized:sub(2)
		end

		for part in normalized:gmatch("[^/]+") do
			parts[#parts + 1] = part
		end

		local current = prefix
		for _, part in ipairs(parts) do
			if current == "" or current:sub(-1) == "/" then
				current = current .. part
			else
				current = current .. "/" .. part
			end

			if not isfolder(current) then
				makefolder(current)
			end
		end

		return true
	end

	local function getConfigPath(name)
		name = sanitizeName(name)
		if not name then
			return nil, "Config name is invalid."
		end

		local basePath = getBasePath()
		if not basePath then
			return nil, "Config path is unavailable."
		end

		local ok, err = ensureFolder(basePath)
		if not ok then
			return nil, err
		end

		return basePath .. name .. ".json"
	end

	local function getParser(element)
		local manager = getManager()
		if not manager or not manager.Parser or not element then
			return nil
		end

		return manager.Parser[element.__type]
	end

	local function listConfigs()
		local basePath = getBasePath()
		if not basePath or not listfiles then
			return {}
		end

		local ok, files = pcall(listfiles, basePath)
		if not ok or type(files) ~= "table" then
			return {}
		end

		local result = {}
		for _, file in ipairs(files) do
			local name = file:match("([^\\/]+)%.json$")
			if name then
				result[#result + 1] = name
			end
		end

		table.sort(result)
		return result
	end

	local function refreshList(selectName)
		local names = listConfigs()
		if configDropdown and configDropdown.Refresh then
			configDropdown:Refresh(names)
		end

		if selectName and configDropdown and configDropdown.Select then
			configDropdown:Select(selectName)
		end

		return names
	end

	local function saveConfig(name)
		local path, err = getConfigPath(name)
		if not path then
			return false, err
		end

		local payload = {}
		for flag, element in pairs(TrackedElements) do
			local parser = getParser(element)
			if parser and parser.Save then
				local ok, state = pcall(parser.Save, element)
				if ok and state ~= nil then
					payload[flag] = state
				end
			end
		end

		local ok, encoded = pcall(function()
			return HttpService:JSONEncode(payload)
		end)
		if not ok then
			return false, "Failed to encode config."
		end

		local writeOk, writeErr = pcall(writefile, path, encoded)
		if not writeOk then
			return false, tostring(writeErr)
		end

		activeConfigName = sanitizeName(name) or activeConfigName
		if configNameInput and configNameInput.Set then
			configNameInput:Set(activeConfigName)
		end
		refreshList(activeConfigName)
		return true
	end

	local function loadConfig(name)
		local path, err = getConfigPath(name)
		if not path then
			return false, err
		end

		if not isfile or not isfile(path) then
			return false, "Config file does not exist."
		end

		local readOk, content = pcall(readfile, path)
		if not readOk then
			return false, tostring(content)
		end

		local decodeOk, decoded = pcall(function()
			return HttpService:JSONDecode(content)
		end)
		if not decodeOk or type(decoded) ~= "table" then
			return false, "Failed to parse config file."
		end

		for flag, savedState in pairs(decoded) do
			local element = TrackedElements[flag]
			local parser = getParser(element)
			if element and parser and parser.Load and type(savedState) == "table" then
				local ok, loadErr = pcall(parser.Load, element, savedState)
				if not ok then
					warn("[LightConfigAddon] Failed to load " .. tostring(flag) .. ": " .. tostring(loadErr))
				end
			end
		end

		activeConfigName = sanitizeName(name) or activeConfigName
		if configNameInput and configNameInput.Set then
			configNameInput:Set(activeConfigName)
		end
		refreshList(activeConfigName)
		return true
	end

	local function deleteConfig(name)
		local path, err = getConfigPath(name)
		if not path then
			return false, err
		end

		if not isfile or not isfile(path) then
			return false, "Config file does not exist."
		end

		local ok, deleteErr = pcall(delfile, path)
		if not ok then
			return false, tostring(deleteErr)
		end

		refreshList()
		return true
	end

	if not Window or not Tab then
		return {
			Refresh = function()
				return {}
			end,
		}
	end

	configNameInput = Tab:Input({
		Title = "Config Name",
		Desc = "Config file name.",
		Placeholder = DefaultConfigName,
		Value = activeConfigName,
		InputIcon = "lucide:file-cog",
		Callback = function(value)
			local normalized = sanitizeName(value)
			if normalized then
				activeConfigName = normalized
			end
		end,
	})

	configDropdown = Tab:Dropdown({
		Title = "Config File",
		Desc = "Saved config files.",
		Values = {},
		Value = nil,
		AllowNone = true,
		Callback = function(value)
			local normalized = sanitizeName(value)
			if normalized then
				activeConfigName = normalized
				if configNameInput and configNameInput.Set then
					configNameInput:Set(normalized)
				end
			end
		end,
	})

	Tab:Button({
		Title = "Refresh List",
		Desc = "Reload saved configs.",
		Callback = function()
			refreshList()
		end,
	})

	Tab:Button({
		Title = "Save Config",
		Desc = "Save current tracked values.",
		Callback = function()
			local ok, err = saveConfig(getSelectedName())
			if not ok then
				notifySafe("Save Config", tostring(err), "lucide:triangle-alert", 6)
				return
			end

			notifySafe("Save Config", "Saved: " .. getSelectedName(), "lucide:save")
		end,
	})

	Tab:Button({
		Title = "Load Config",
		Desc = "Load selected config.",
		Callback = function()
			local ok, err = loadConfig(getSelectedName())
			if not ok then
				notifySafe("Load Config", tostring(err), "lucide:triangle-alert", 6)
				return
			end

			notifySafe("Load Config", "Loaded: " .. getSelectedName(), "lucide:folder-open")
		end,
	})

	Tab:Button({
		Title = "Delete Config",
		Desc = "Delete selected config.",
		Callback = function()
			local ok, err = deleteConfig(getSelectedName())
			if not ok then
				notifySafe("Delete Config", tostring(err), "lucide:triangle-alert", 6)
				return
			end

			notifySafe("Delete Config", "Deleted: " .. getSelectedName(), "lucide:trash-2")
		end,
	})

	refreshList()

	return {
		Refresh = refreshList,
		Save = saveConfig,
		Load = loadConfig,
		Delete = deleteConfig,
		GetActiveName = function()
			return activeConfigName
		end,
	}
end

return LightConfigAddon
