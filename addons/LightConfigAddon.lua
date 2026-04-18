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
	local currentAutoloadName = nil
	local configNameInput
	local configDropdown
	local autoloadButton

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

	local cachedBasePath = nil
	local folderVerified = false

	local function getBasePath()
		if cachedBasePath then
			return cachedBasePath
		end

		local manager = getManager()
		local path = manager and manager.Path
		if type(path) ~= "string" or path == "" then
			return nil
		end

		path = path:gsub("\\", "/")
		if not path:match("/$") then
			path = path .. "/"
		end

		cachedBasePath = path
		return path
	end

	local function ensureFolder(path)
		if folderVerified then
			return true
		end

		if not path then
			return false, "Config path is unavailable."
		end

		if not (isfolder and makefolder) then
			folderVerified = true
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

		folderVerified = true
		return true
	end

	-- Read-only path resolution: skips ensureFolder (folder must already exist for reads)
	local function getConfigPathRead(name)
		name = sanitizeName(name)
		if not name then
			return nil, "Config name is invalid."
		end

		local basePath = getBasePath()
		if not basePath then
			return nil, "Config path is unavailable."
		end

		return basePath .. name .. ".json"
	end

	-- Write path resolution: ensures folder exists before returning
	local function getConfigPath(name)
		local path, err = getConfigPathRead(name)
		if not path then
			return nil, err
		end

		local ok, folderErr = ensureFolder(getBasePath())
		if not ok then
			return nil, folderErr
		end

		return path
	end

	local function getAutoloadPath()
		local basePath = getBasePath()
		if not basePath then
			return nil, "Config path is unavailable."
		end

		local ok, err = ensureFolder(basePath)
		if not ok then
			return nil, err
		end

		return basePath .. "autoload.txt"
	end

	-- Lightweight parser: skips Tween animations during restore, Callbacks still fire for state sync
	local LightParser = {
		Toggle = {
			Save = function(el)
				return { __type = "Toggle", value = el.Value }
			end,
			Load = function(el, data)
				if el and el.Set then
					el:Set(data.value, nil, true) -- isCallback=nil(→true), isAnim=true (instant position, no Tween)
				end
			end,
		},
		Dropdown = {
			Save = function(el)
				return { __type = "Dropdown", value = el.Value }
			end,
			Load = function(el, data)
				if el and el.Select then
					el:Select(data.value) -- triggers Refresh + Callback for state sync
				end
			end,
		},
		Input = {
			Save = function(el)
				return { __type = "Input", value = el.Value }
			end,
			Load = function(el, data)
				if el and el.Set then
					el:Set(data.value)
				end
			end,
		},
		Slider = {
			Save = function(el)
				return { __type = "Slider", value = el.Value and el.Value.Default or nil }
			end,
			Load = function(el, data)
				if el and el.Set and data.value then
					el:Set(tonumber(data.value))
				end
			end,
		},
		Keybind = {
			Save = function(el)
				return { __type = "Keybind", value = el.Value }
			end,
			Load = function(el, data)
				if el and el.Set then
					el:Set(data.value)
				end
			end,
		},
		Colorpicker = {
			Save = function(el)
				return {
					__type = "Colorpicker",
					value = el.Default and el.Default:ToHex() or "FFFFFF",
					transparency = el.Transparency or nil,
				}
			end,
			Load = function(el, data)
				if el and el.Update and data.value then
					el:Update(Color3.fromHex(data.value), data.transparency or nil)
				end
			end,
		},
	}

	local function getParser(element)
		if not element or not element.__type then
			return nil
		end

		-- Use lightweight parser first, fall back to ConfigManager parser
		if LightParser[element.__type] then
			return LightParser[element.__type]
		end

		local manager = getManager()
		if not manager or not manager.Parser then
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

	-- Lightweight UI update: only updates button desc without re-listing files
	local function updateConfigUI()
		if autoloadButton and autoloadButton.SetDesc then
			autoloadButton:SetDesc(
				"Current: " .. tostring(currentAutoloadName or "none") .. " | Selected: " .. tostring(getSelectedName())
			)
		end
	end

	local function refreshList(selectName)
		local names = listConfigs()
		if configDropdown and configDropdown.Refresh then
			configDropdown:Refresh(names)
		end

		if selectName and configDropdown and configDropdown.Select then
			configDropdown:Select(selectName)
		end

		updateConfigUI()

		return names
	end

	local function readAutoload()
		local path = getAutoloadPath()
		if not path or not isfile or not isfile(path) then
			return nil
		end

		local ok, content = pcall(readfile, path)
		if not ok or type(content) ~= "string" then
			return nil
		end

		return sanitizeName(content)
	end

	local function writeAutoload(name)
		local path, err = getAutoloadPath()
		if not path then
			return false, err
		end

		name = sanitizeName(name)
		if not name then
			return false, "Config name is invalid."
		end

		local ok, writeErr = pcall(writefile, path, name)
		if not ok then
			return false, tostring(writeErr)
		end

		currentAutoloadName = name
		refreshList(activeConfigName)
		return true
	end

	local function clearAutoload()
		local path = getAutoloadPath()
		currentAutoloadName = nil

		if path and isfile and isfile(path) and delfile then
			pcall(delfile, path)
		end

		refreshList(activeConfigName)
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

	local LOAD_BATCH_LIGHT = 3 -- lightweight elements (Toggle, Input, Slider, Keybind) per frame
	local LOAD_BATCH_HEAVY = 1 -- heavy elements (Dropdown, Colorpicker) per frame

	local HEAVY_TYPES = { Dropdown = true, Colorpicker = true }

	local function loadConfig(name)
		local path, err = getConfigPathRead(name)
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

		-- Separate lightweight and heavy elements for optimal batching
		local lightEntries = {}
		local heavyEntries = {}
		for flag, savedState in pairs(decoded) do
			local element = TrackedElements[flag]
			local parser = getParser(element)
			if element and parser and parser.Load and type(savedState) == "table" then
				local entry = { element, parser, savedState, flag }
				if HEAVY_TYPES[element.__type] then
					heavyEntries[#heavyEntries + 1] = entry
				else
					lightEntries[#lightEntries + 1] = entry
				end
			end
		end

		-- Frame-distributed restore: process light elements first, then heavy ones
		local totalEntries = #lightEntries + #heavyEntries
		if totalEntries > 0 then
			task.spawn(function()
				-- Phase 1: lightweight elements (Toggle, Input, Slider, Keybind)
				for i = 1, #lightEntries, LOAD_BATCH_LIGHT do
					for j = i, math.min(i + LOAD_BATCH_LIGHT - 1, #lightEntries) do
						local e = lightEntries[j]
						local ok, loadErr = pcall(e[2].Load, e[1], e[3])
						if not ok then
							warn("[LightConfigAddon] Failed to load " .. tostring(e[4]) .. ": " .. tostring(loadErr))
						end
					end
					if i + LOAD_BATCH_LIGHT - 1 < #lightEntries or #heavyEntries > 0 then
						task.wait() -- yield to next frame
					end
				end

				-- Phase 2: heavy elements (Dropdown, Colorpicker) — 1 per frame
				for i = 1, #heavyEntries do
					local e = heavyEntries[i]
					local ok, loadErr = pcall(e[2].Load, e[1], e[3])
					if not ok then
						warn("[LightConfigAddon] Failed to load " .. tostring(e[4]) .. ": " .. tostring(loadErr))
					end
					if i < #heavyEntries then
						task.wait() -- yield to next frame
					end
				end
			end)
		end

		activeConfigName = sanitizeName(name) or activeConfigName
		if configNameInput and configNameInput.Set then
			configNameInput:Set(activeConfigName)
		end
		-- Lightweight UI update only (skip full file re-listing)
		updateConfigUI()
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

	autoloadButton = Tab:Button({
		Title = "Auto Load",
		Desc = "Current: none | Selected: " .. tostring(activeConfigName),
		Callback = function()
			local selectedName = getSelectedName()
			if currentAutoloadName == selectedName then
				clearAutoload()
				notifySafe("Auto Load", "Cleared autoload config.", "lucide:badge-x")
				return
			end

			local ok, err = writeAutoload(selectedName)
			if not ok then
				notifySafe("Auto Load", tostring(err), "lucide:triangle-alert", 6)
				return
			end

			notifySafe("Auto Load", "Autoload set to: " .. selectedName, "lucide:badge-check")
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

	currentAutoloadName = readAutoload()
	refreshList()

	if currentAutoloadName then
		task.delay(0.5, function()
			local ok, err = loadConfig(currentAutoloadName)
			if not ok then
				notifySafe("Auto Load", tostring(err), "lucide:triangle-alert", 7)
				return
			end

			notifySafe("Auto Load", "Loaded: " .. currentAutoloadName, "lucide:hard-drive-download", 6)
		end)
	end

	return {
		Refresh = refreshList,
		Save = saveConfig,
		Load = loadConfig,
		Delete = deleteConfig,
		SetAutoload = writeAutoload,
		ClearAutoload = clearAutoload,
		GetAutoloadName = function()
			return currentAutoloadName
		end,
		GetActiveName = function()
			return activeConfigName
		end,
	}
end

return LightConfigAddon
