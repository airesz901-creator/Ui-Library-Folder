local Release = "Luna Custom 7.5.1 - Clean Drag Surface"

local Luna = { 
	Folder = "Luna", 
	Options = {}, 
	ThemeGradient = ColorSequence.new{ColorSequenceKeypoint.new(0.00, Color3.fromRGB(117, 164, 206)), ColorSequenceKeypoint.new(0.50, Color3.fromRGB(123, 201, 201)), ColorSequenceKeypoint.new(1.00, Color3.fromRGB(224, 138, 175))},
	ConfigVersion = 5,
	ConfigExtension = ".json",
	Version = Release,
	MaxNotifications = 3,
	NotificationBlurEnabled = false,
	WindowBlurEnabled = true,
	StrictConfig = false,
	AnimationSpeed = 1,
	ReducedMotion = false,
	UIScale = 1,
	MaxNotificationHistory = 50,
	MaxConfigBytes = 2 * 1024 * 1024,
	MaxConfigObjects = 5000,
}

local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local Localization = game:GetService("LocalizationService")
local Players = game:GetService("Players")
local Player = Players.LocalPlayer
if not Player then
	local started = os.clock()
	repeat
		RunService.Heartbeat:Wait()
		Player = Players.LocalPlayer
	until Player or (os.clock() - started) >= 10
end
if not Player then
	error("Luna UI must run in a client context with Players.LocalPlayer available.")
end
local Camera = workspace.CurrentCamera

-- ✅ FIX 1: Helper untuk current camera
local function GetCurrentCamera()
	Camera = workspace.CurrentCamera or Camera
	return Camera
end

local CoreGui = game:GetService("CoreGui")
local ContentProvider = game:GetService("ContentProvider")

-- Destroy a previously loaded Luna instance before creating another one.
local GlobalEnvironment = (type(getgenv) == "function" and getgenv()) or _G
if type(GlobalEnvironment) ~= "table" then
	GlobalEnvironment = _G
end
local PreviousLuna = rawget(GlobalEnvironment, "__LUNA_ACTIVE_LIBRARY")
if type(PreviousLuna) == "table"
	and PreviousLuna ~= Luna
	and type(PreviousLuna.Destroy) == "function"
then
	pcall(function()
		PreviousLuna:Destroy()
	end)
end

Luna._Connections = {}
Luna._Cleanups = {}
Luna._Components = setmetatable({}, {__mode = "k"})
Luna._Destroyed = false
Luna._NotificationQueue = {}
Luna._ToggleGroups = {}
Luna._MutatingToggleGroups = {}
Luna._Events = {}
Luna._NotificationHistory = {}
Luna._NotificationById = {}
Luna._Themes = {}
Luna._Windows = setmetatable({}, {__mode = "k"})
Luna._Overlays = setmetatable({}, {__mode = "k"})
Luna._KnownConfigs = {}
Luna._SessionId = HttpService:GenerateGUID(false)
Luna._Stats = {
	CallbackErrors = 0,
	NotificationsCreated = 0,
	ActiveNotifications = 0,
	RenderLoops = 0,
	DuplicateFlags = 0,
	ConfigRollbacks = 0,
	ConfigWarnings = 0,
	EventsEmitted = 0,
	ModalsOpened = 0,
	CommandPaletteSearches = 0,
	DependencyLinks = 0,
	RuntimeErrors = 0,
	RuntimeWarnings = 0,
	AssetValidationFailures = 0,
	ConfigWriteRecoveries = 0,
	StatusUpdates = 0,
	ConnectionErrors = 0,
	AsyncTasksStarted = 0,
	AsyncTasksCompleted = 0,
	AsyncTasksCancelled = 0,
	ActiveAsyncTasks = 0,
	DependencyCyclesRejected = 0,
	TweenCancellations = 0,
	BlurFallbacks = 0,
	DragClamps = 0,
	FilesystemErrors = 0,
	ConfigRepairs = 0,
	OverlayCleanups = 0,
	DuplicateWindowRequests = 0,
}

local function TrackConnection(connection, bucket)
	if typeof(connection) == "RBXScriptConnection" then
		Luna._Connections[connection] = true
		if bucket then
			table.insert(bucket, connection)
		end
	end
	return connection
end

local function DisconnectConnections(bucket)
	for key, value in pairs(bucket or {}) do
		local connection = typeof(key) == "RBXScriptConnection" and key or value
		if typeof(connection) == "RBXScriptConnection" then
			pcall(function() connection:Disconnect() end)
			Luna._Connections[connection] = nil
		end
	end
	table.clear(bucket or {})
end

local function AddCleanup(callback)
	if type(callback) == "function" then
		table.insert(Luna._Cleanups, callback)
	end
	return callback
end

local function TracebackMessage(errorMessage)
	local message = tostring(errorMessage)
	if type(debug) == "table" and type(debug.traceback) == "function" then
		local success, traced = pcall(debug.traceback, message, 3)
		if success and type(traced) == "string" then return traced end
	end
	return message
end

local function SafeCall(callback, ...)
	if type(callback) ~= "function" then
		return false, "Callback is unavailable."
	end
	local arguments = table.pack(...)
	local results = table.pack(xpcall(function()
		return callback(table.unpack(arguments, 1, arguments.n))
	end, TracebackMessage))
	if not results[1] then
		Luna._Stats.CallbackErrors += 1
		warn("Luna UI callback error: " .. tostring(results[2]))
		return false, results[2]
	end
	return true, table.unpack(results, 2, results.n)
end

local WarnedMessages = {}

local function WarnOnce(key, message)
	key = tostring(key or message or "LunaWarning")
	if WarnedMessages[key] then return false end
	WarnedMessages[key] = true
	Luna._Stats.RuntimeWarnings += 1
	warn("Luna UI: " .. tostring(message or key))
	return true
end

local function IsSessionAlive(sessionId)
	return Luna._Destroyed ~= true and Luna._SessionId == sessionId
end

local function RunManagedAsync(mode, callback, ...)
	if type(callback) ~= "function" then return nil end
	local sessionId = Luna._SessionId
	local arguments = table.pack(...)
	Luna._Stats.AsyncTasksStarted += 1
	Luna._Stats.ActiveAsyncTasks += 1
	local function runner()
		if not IsSessionAlive(sessionId) then
			Luna._Stats.AsyncTasksCancelled += 1
			Luna._Stats.ActiveAsyncTasks = math.max(0, Luna._Stats.ActiveAsyncTasks - 1)
			return
		end
		local success, err = xpcall(function()
			callback(table.unpack(arguments, 1, arguments.n))
		end, TracebackMessage)
		if not success then
			Luna._Stats.RuntimeErrors += 1
			WarnOnce("async:" .. tostring(err), "Managed async task failed: " .. tostring(err))
		end
		Luna._Stats.AsyncTasksCompleted += 1
		Luna._Stats.ActiveAsyncTasks = math.max(0, Luna._Stats.ActiveAsyncTasks - 1)
	end
	if mode == "defer" then
		return task.defer(runner)
	elseif type(mode) == "number" then
		return task.delay(math.max(0, tonumber(mode) or 0), runner)
	end
	return task.spawn(runner)
end

local function ManagedDefer(callback, ...)
	return RunManagedAsync("defer", callback, ...)
end

local function ManagedSpawn(callback, ...)
	return RunManagedAsync("spawn", callback, ...)
end

local function ManagedDelay(seconds, callback, ...)
	return RunManagedAsync(math.max(0, tonumber(seconds) or 0), callback, ...)
end

local function IsGuiObject(instance)
	return typeof(instance) == "Instance" and instance:IsA("GuiObject")
end

local function GetGuiZIndex(instance, fallback)
	if IsGuiObject(instance) then
		local success, value = pcall(function() return instance.ZIndex end)
		if success and tonumber(value) then return tonumber(value) end
	end
	return tonumber(fallback) or 1
end

local function SafeSetProperty(instance, property, value)
	if typeof(instance) ~= "Instance" then return false, "Instance is unavailable." end
	local success, err = pcall(function() instance[property] = value end)
	if not success then
		Luna._Stats.RuntimeErrors += 1
		WarnOnce("property:" .. tostring(instance) .. ":" .. tostring(property),
			("Unable to set %s.%s: %s"):format(instance:GetFullName(), tostring(property), tostring(err)))
	end
	return success, err
end

local function ResolvePath(root, path)
	local current = root
	for segment in tostring(path or ""):gmatch("[^%.]+") do
		if typeof(current) ~= "Instance" then return nil end
		current = current:FindFirstChild(segment)
		if not current then return nil end
	end
	return current
end

local function ValidateInstancePath(root, path, expectedClass)
	local instance = ResolvePath(root, path)
	if not instance then
		return false, ("Missing UI asset path %q."):format(path)
	end
	if expectedClass and not instance:IsA(expectedClass) then
		return false, ("UI asset path %q must be %s, found %s."):format(
			path, expectedClass, instance.ClassName
		)
	end
	return true, instance
end

local function RemoveTrackedConnection(connection, bucket)
	if typeof(connection) ~= "RBXScriptConnection" then return false end
	pcall(function() connection:Disconnect() end)
	Luna._Connections[connection] = nil
	if type(bucket) == "table" then
		for index = #bucket, 1, -1 do
			if bucket[index] == connection then table.remove(bucket, index) end
		end
	end
	return true
end

local function ConnectComponent(component, signal, callback)
	component._Connections = component._Connections or {}
	if typeof(signal) ~= "RBXScriptSignal" or type(callback) ~= "function" then
		Luna._Stats.ConnectionErrors += 1
		WarnOnce("component-signal:" .. tostring(component), "Unable to connect an invalid component signal.")
		return nil
	end
	local success, connection = pcall(function() return signal:Connect(callback) end)
	if not success or typeof(connection) ~= "RBXScriptConnection" then
		Luna._Stats.ConnectionErrors += 1
		WarnOnce("component-connect:" .. tostring(component) .. ":" .. tostring(connection),
			"Component signal connection failed: " .. tostring(connection))
		return nil
	end
	return TrackConnection(connection, component._Connections)
end

local function IsComponentUsable(component)
	return component and not component._Destroyed and not component.Disabled and not Luna._Destroyed
end

local function SanitizeFileName(name)
	name = tostring(name or "")
	name = name:gsub("[%c]", "")
	name = name:gsub('[\\/:*?"<>|]', "_")
	name = name:gsub("^%s+", ""):gsub("%s+$", "")
	name = name:gsub("%.+$", "")
	if name == "" or name == "." or name == ".." then
		return nil
	end
	return name:sub(1, 80)
end

local function NormalizeFolderPath(path)
	local segments = {}
	for rawSegment in tostring(path or ""):gmatch("[^/\\]+") do
		local segment = rawSegment:gsub("^%s+", ""):gsub("%s+$", "")
		if segment == "." or segment == ".." then
			return nil, "Folder traversal segments are not allowed."
		end
		segment = segment:gsub("[%c]", ""):gsub('[:*?"<>|]', "_")
		if segment ~= "" then table.insert(segments, segment:sub(1, 80)) end
	end
	if #segments == 0 then return nil, "Folder path is empty." end
	return table.concat(segments, "/")
end

local function JoinFolderPath(root, child)
	local combined = (root ~= nil and tostring(root) ~= "")
		and (tostring(root) .. "/" .. tostring(child or ""))
		or tostring(child or "")
	return NormalizeFolderPath(combined)
end

local function SafeIsFile(path)
	if type(isfile) ~= "function" then return nil, "Executor does not support isfile." end
	local success, result = pcall(isfile, path)
	if not success then
		Luna._Stats.FilesystemErrors += 1
		return nil, tostring(result)
	end
	return result == true
end

local function SafeReadFile(path)
	if type(readfile) ~= "function" then return false, "Executor does not support readfile." end
	local success, result = pcall(readfile, path)
	if not success then Luna._Stats.FilesystemErrors += 1 end
	return success, result
end

local function SafeDeleteFile(path)
	if type(delfile) ~= "function" then return false, "Executor does not support delfile." end
	local success, result = pcall(delfile, path)
	if not success then Luna._Stats.FilesystemErrors += 1 end
	return success, result
end

local function EnsureFolderPath(path)
	if type(isfolder) ~= "function" or type(makefolder) ~= "function" then
		return false, "Executor does not support folders."
	end
	local normalized, normalizeError = NormalizeFolderPath(path)
	if not normalized then return false, normalizeError end
	local current = ""
	for segment in normalized:gmatch("[^/]+") do
		current = current == "" and segment or (current .. "/" .. segment)
		local checkSuccess, exists = pcall(isfolder, current)
		if not checkSuccess then
			Luna._Stats.FilesystemErrors += 1
			return false, tostring(exists)
		end
		if not exists then
			local success, err = pcall(makefolder, current)
			if not success then
				Luna._Stats.FilesystemErrors += 1
				return false, tostring(err)
			end
		end
	end
	return true
end

local MouseButtonAliases = {
	M1 = "MouseButton1",
	MOUSE1 = "MouseButton1",
	LEFTMOUSE = "MouseButton1",
	M2 = "MouseButton2",
	MOUSE2 = "MouseButton2",
	RIGHTMOUSE = "MouseButton2",
	M3 = "MouseButton3",
	MOUSE3 = "MouseButton3",
	MIDDLEMOUSE = "MouseButton3",
}

local AllowedUserInputBinds = {
	[Enum.UserInputType.MouseButton1] = true,
	[Enum.UserInputType.MouseButton2] = true,
	[Enum.UserInputType.MouseButton3] = true,
}

local function NormalizeInputBinding(value, fallback)
	if value == nil and fallback ~= nil then
		value = fallback
	end

	if type(value) == "table" then
		value = value.EnumItem or value.Name or value.Keybind or value.Bind
	end

	if typeof(value) == "EnumItem" then
		if value.EnumType == Enum.KeyCode and value ~= Enum.KeyCode.Unknown then
			return {
				Kind = "KeyCode",
				Name = value.Name,
				EnumItem = value,
			}
		end

		if value.EnumType == Enum.UserInputType and AllowedUserInputBinds[value] then
			return {
				Kind = "UserInputType",
				Name = value.Name,
				EnumItem = value,
			}
		end

		return nil, "Only keyboard, gamepad, and mouse buttons are supported."
	end

	local name = tostring(value or "")
	name = name:gsub("^Enum%.KeyCode%.", "")
	name = name:gsub("^Enum%.UserInputType%.", "")
	name = name:gsub("%s+", "")

	local alias = MouseButtonAliases[name:upper()]
	if alias then
		name = alias
	end

	local keyCode = Enum.KeyCode[name]
	if keyCode and keyCode ~= Enum.KeyCode.Unknown then
		return {
			Kind = "KeyCode",
			Name = name,
			EnumItem = keyCode,
		}
	end

	local inputType = Enum.UserInputType[name]
	if inputType and AllowedUserInputBinds[inputType] then
		return {
			Kind = "UserInputType",
			Name = name,
			EnumItem = inputType,
		}
	end

	return nil, ("Unsupported input bind %q."):format(tostring(value))
end

local function InputBindingName(value)
	local binding = NormalizeInputBinding(value)
	return binding and binding.Name or nil
end

local function InputToBinding(input)
	if not input then
		return nil
	end

	if input.KeyCode and input.KeyCode ~= Enum.KeyCode.Unknown then
		return NormalizeInputBinding(input.KeyCode)
	end

	if input.UserInputType and AllowedUserInputBinds[input.UserInputType] then
		return NormalizeInputBinding(input.UserInputType)
	end

	return nil
end

local function InputMatchesBinding(input, value)
	local binding = NormalizeInputBinding(value)
	if not binding or not input then
		return false
	end

	if binding.Kind == "KeyCode" then
		return input.KeyCode == binding.EnumItem
	end

	return input.UserInputType == binding.EnumItem
end

local function RegisterOption(flag, option)
	if not flag then
		return true
	end

	flag = tostring(flag)
	local existing = Luna.Options[flag]

	if existing and existing ~= option then
		Luna._Stats.DuplicateFlags += 1
		option.IgnoreConfig = true
		option.ConfigRegistrationError =
			("Duplicate config flag %q was rejected."):format(flag)
		warn("Luna UI: " .. option.ConfigRegistrationError)
		return false, option.ConfigRegistrationError
	end

	Luna.Options[flag] = option
	option.Flag = flag
	return true
end

local function RemoveOption(option)
	if option and option.Flag and Luna.Options[option.Flag] == option then
		Luna.Options[option.Flag] = nil
	end
end

-- ✅ FIX 2: PERBAIKAN ToggleGroup Normalization
-- Anti-tab-bug fix - prevent empty toggle group normalization dari snap ke home

local function NormalizeToggleGroup(group)
	if group == nil or group == false then
		return nil
	end

	group = tostring(group)
	group = group:gsub("^%s+", ""):gsub("%s+$", "")
	if group == "" then
		return nil
	end
	return group
end

local function RemoveToggleFromGroup(toggle)
	if not toggle then return end
	local group = toggle._ToggleGroup
	if not group then return end

	local bucket = Luna._ToggleGroups[group]
	if bucket then
		bucket[toggle] = nil
		if next(bucket) == nil then
			Luna._ToggleGroups[group] = nil
			Luna._MutatingToggleGroups[group] = nil
		end
	end
	toggle._ToggleGroup = nil
end

local function RegisterToggleGroup(toggle, group)
	RemoveToggleFromGroup(toggle)
	group = NormalizeToggleGroup(group)
	if not group then return nil end

	local bucket = Luna._ToggleGroups[group]
	if not bucket then
		bucket = setmetatable({}, {__mode = "k"})
		Luna._ToggleGroups[group] = bucket
	end

	bucket[toggle] = true
	toggle._ToggleGroup = group
	return group
end

local function ToggleSortKey(toggle)
	if not toggle then return "" end
	return tostring(toggle.Flag or "")
		.. "\0"
		.. tostring(toggle.Settings and toggle.Settings.Name or "")
end

local function GetToggleGroupMembers(group)
	local bucket = group and Luna._ToggleGroups[group]
	local members = {}
	if bucket then
		for member in pairs(bucket) do
			if member and not member._Destroyed then
				table.insert(members, member)
			end
		end
	end
	table.sort(members, function(a, b)
		return ToggleSortKey(a) < ToggleSortKey(b)
	end)
	return members
end

local function ToggleGroupAllowsNone(group)
	for _, member in ipairs(GetToggleGroupMembers(group)) do
		if member.Settings and member.Settings.AllowNone == false then
			return false
		end
	end
	return true
end

local function ToggleGroupHasOtherActive(toggle)
	local group = toggle and toggle._ToggleGroup
	for _, member in ipairs(GetToggleGroupMembers(group)) do
		if member ~= toggle and member.CurrentValue == true then
			return true
		end
	end
	return false
end

local function BeginToggleGroupMutation(group)
	if not group then return true end
	if Luna._MutatingToggleGroups[group] then
		return false
	end
	Luna._MutatingToggleGroups[group] = true
	return true
end

local function EndToggleGroupMutation(group)
	if group then
		Luna._MutatingToggleGroups[group] = nil
	end
end

local function DeactivateToggleGroup(activeToggle)
	local group = activeToggle and activeToggle._ToggleGroup
	local deactivated = {}
	for _, member in ipairs(GetToggleGroupMembers(group)) do
		if member ~= activeToggle
			and member.CurrentValue == true
			and type(member._ApplyExclusiveState) == "function"
		then
			member:_ApplyExclusiveState(false, false)
			table.insert(deactivated, member)
		end
	end
	return deactivated
end

local function NormalizeAllToggleGroups(fireCallbacks)
	for group in pairs(Luna._ToggleGroups) do
		local members = GetToggleGroupMembers(group)
		local active = {}

		for _, member in ipairs(members) do
			if member.CurrentValue == true then
				table.insert(active, member)
			end
		end

		local changed = {}
		if #active > 1 then
			local keeper = active[1]
			for index = 2, #active do
				local member = active[index]
				if type(member._ApplyExclusiveState) == "function" then
					member:_ApplyExclusiveState(false, false)
					table.insert(changed, {Member = member, State = false})
				end
			end
			if keeper and type(keeper._ApplyExclusiveState) == "function" then
				keeper:_ApplyExclusiveState(true, false)
			end
		elseif #active == 0
			and #members > 0
			and not ToggleGroupAllowsNone(group)
		then
			local member = members[1]
			if type(member._ApplyExclusiveState) == "function" then
				member:_ApplyExclusiveState(true, false)
				table.insert(changed, {Member = member, State = true})
			end
		end

		if fireCallbacks == true then
			for _, item in ipairs(changed) do
				if type(item.Member._EmitExclusiveCallback) == "function" then
					item.Member:_EmitExclusiveCallback(item.State)
				end
			end
		end
	end
	return true
end

function Luna:NormalizeToggleGroups(fireCallbacks)
	return NormalizeAllToggleGroups(fireCallbacks == true)
end

local function ShallowCopy(source)
	local output = {}
	for key, value in pairs(type(source) == "table" and source or {}) do
		output[key] = value
	end
	return output
end

local function DeepCopy(value, seen)
	if type(value) ~= "table" then return value end
	seen = seen or {}
	if seen[value] then return seen[value] end
	local output = {}
	seen[value] = output
	for key, item in pairs(value) do
		output[DeepCopy(key, seen)] = DeepCopy(item, seen)
	end
	return output
end

local function ValuesEqual(a, b, seen)
	if a == b then return true end
	if type(a) ~= type(b) then return false end
	if type(a) ~= "table" then return false end
	seen = seen or {}
	if seen[a] == b then return true end
	seen[a] = b
	for key, value in pairs(a) do
		if not ValuesEqual(value, b[key], seen) then return false end
	end
	for key in pairs(b) do
		if a[key] == nil then return false end
	end
	return true
end

local function EmitEvent(name, ...)
	name = tostring(name or "")
	if name == "" then return false end
	Luna._Stats.EventsEmitted += 1
	local bucket = Luna._Events[name]
	if not bucket then return true end
	local listeners = {}
	for token, callback in pairs(bucket) do
		table.insert(listeners, {Token = token, Callback = callback})
	end
	for _, listener in ipairs(listeners) do
		if bucket[listener.Token] == listener.Callback then
			SafeCall(listener.Callback, ...)
		end
	end
	return true
end

function Luna:On(name, callback)
	if type(callback) ~= "function" then
		return nil, "Listener must be a function."
	end
	name = tostring(name or "")
	if name == "" then return nil, "Event name is empty." end
	local bucket = Luna._Events[name]
	if not bucket then
		bucket = {}
		Luna._Events[name] = bucket
	end
	local token = HttpService:GenerateGUID(false)
	bucket[token] = callback
	local disconnected = false
	return {
		Disconnect = function()
			if disconnected then return end
			disconnected = true
			if Luna._Events[name] then
				Luna._Events[name][token] = nil
				if next(Luna._Events[name]) == nil then
					Luna._Events[name] = nil
				end
			end
		end,
	}
end

function Luna:Off(connection)
	if not connection or type(connection.Disconnect) ~= "function" then return false end
	local success, err = pcall(function() connection:Disconnect() end)
	if typeof(connection) == "RBXScriptConnection" then Luna._Connections[connection] = nil end
	if not success then
		Luna._Stats.ConnectionErrors += 1
		WarnOnce("off:" .. tostring(connection), "Unable to disconnect listener: " .. tostring(err))
	end
	return success, err
end

function Luna:Once(name, callback)
	local connection
	connection = Luna:On(name, function(...)
		if connection then connection.Disconnect() end
		callback(...)
	end)
	return connection
end

function Luna:Emit(name, ...)
	return EmitEvent(name, ...)
end

local function ReadComponentValue(component)
	if not component or type(component.GetValue) ~= "function" then return nil end
	local success, value = pcall(component.GetValue, component)
	return success and value or nil
end

local function EmitComponentChanged(component, value, previous, metadata)
	if not component or component._Destroyed then return false end
	metadata = type(metadata) == "table" and metadata or {}
	if previous == nil then previous = component._LastEmittedValue end
	if component._LastEmittedInitialized
		and ValuesEqual(component._LastEmittedValue, value)
		and metadata.Force ~= true
	then
		return false
	end
	component._LastEmittedValue = DeepCopy(value)
	component._LastEmittedInitialized = true
	local listeners = component._ChangedListeners
	if listeners then
		local snapshot = {}
		for token, callback in pairs(listeners) do
			table.insert(snapshot, {Token = token, Callback = callback})
		end
		for _, listener in ipairs(snapshot) do
			if listeners[listener.Token] == listener.Callback then
				SafeCall(listener.Callback, value, previous, metadata)
			end
		end
	end
	EmitEvent("ComponentChanged", component, value, previous, metadata)
	return true
end

local AttachTooltipToComponent

function Luna:GetOption(flag)
	return Luna.Options[tostring(flag or "")]
end

function Luna:GetValue(flag)
	local option = self:GetOption(flag)
	if not option then return nil, "Option does not exist." end
	return ReadComponentValue(option)
end

function Luna:SetValue(flag, value, silent)
	local option = self:GetOption(flag)
	if not option or type(option.SetValue) ~= "function" then
		return false, "Option does not support SetValue."
	end
	local success, result = pcall(option.SetValue, option, value, silent == true)
	if not success then
		Luna._Stats.RuntimeErrors += 1
		return false, tostring(result)
	end
	if result == false then return false, "Option rejected the supplied value." end
	return true, option
end

function Luna:SetValues(values, silent)
	if type(values) ~= "table" then return false, "Values must be a table." end
	local flags = {}
	for flag in pairs(values) do table.insert(flags, tostring(flag)) end
	table.sort(flags, function(a, b) return a:lower() < b:lower() end)
	local errors, applied = {}, {}
	for _, flag in ipairs(flags) do
		local success, result = self:SetValue(flag, values[flag], silent == true)
		if success then table.insert(applied, flag) else errors[flag] = result end
	end
	NormalizeAllToggleGroups(false)
	EmitEvent("ValuesApplied", applied, errors)
	return next(errors) == nil, errors, applied
end

function Luna:ResetOption(flag, silent)
	local option = self:GetOption(flag)
	if not option or type(option.Reset) ~= "function" then
		return false, "Option cannot be reset."
	end
	option:Reset(silent == true)
	return true, option
end

function Luna:ResetAll(silent)
	local flags = {}
	for flag in pairs(Luna.Options) do table.insert(flags, tostring(flag)) end
	table.sort(flags, function(a, b) return a:lower() < b:lower() end)
	local resetCount, errors = 0, {}
	for _, flag in ipairs(flags) do
		local option = Luna.Options[flag]
		if option and type(option.Reset) == "function" then
			local success, result = pcall(option.Reset, option, silent == true)
			if success then resetCount += 1 else errors[flag] = tostring(result) end
		end
	end
	NormalizeAllToggleGroups(false)
	EmitEvent("AllOptionsReset", resetCount, errors)
	return next(errors) == nil, resetCount, errors
end

local ValueComponentClasses = {
	Toggle = true,
	Slider = true,
	Input = true,
	Dropdown = true,
	Colorpicker = true,
	Bind = true,
}

local function StoreOriginalBoolean(instance, attributeName, value)
	if instance:GetAttribute(attributeName) == nil then
		instance:SetAttribute(attributeName, value == true)
	end
end

local function DependencyWouldCycle(target, source, visited)
	if target == source then return true end
	visited = visited or {}
	if visited[source] then return false end
	visited[source] = true
	for upstream in pairs(type(source) == "table" and source._DependencySources or {}) do
		if DependencyWouldCycle(target, upstream, visited) then return true end
	end
	return false
end

local function EnhanceComponent(component)
	if type(component) ~= "table" then
		return component
	end

	Luna._Components[component] = true
	component.Visible = component.Visible ~= false
	component.Disabled = component.Disabled == true
	component._Destroyed = component._Destroyed == true
	component._Connections = component._Connections or {}
	component._CreatedAt = component._CreatedAt or os.clock()

	if ValueComponentClasses[component.Class]
		and component.Set
		and not component.SetValue
	then
		function component:SetValue(value, silent)
			if self._Destroyed then return self end
			if self.Class == "Dropdown" then
				self:Set({
					CurrentOption = type(value) == "table" and value or {value},
					Silent = silent == true,
				})
			elseif self.Class == "Colorpicker" then
				self:Set({Color = value, Silent = silent == true})
			elseif self.Class == "Bind" then
				self:Set({CurrentBind = value, Silent = silent == true})
			else
				self:Set({CurrentValue = value, Silent = silent == true})
			end
			return self
		end
	end

	if ValueComponentClasses[component.Class] and not component.GetValue then
		function component:GetValue()
			if self.Class == "Dropdown" then
				return self.CurrentOption
			elseif self.Class == "Colorpicker" then
				return self.Color
			elseif self.Class == "Bind" then
				return self.CurrentBind
			end
			return self.CurrentValue
		end
	end

	if component.Class == "Dropdown" and component.Set and not component.SetOptions then
		function component:SetOptions(options, silent)
			self:Set({
				Options = type(options) == "table" and options or {},
				Silent = silent == true,
			})
			return self
		end
	end

	if not component.SetVisible then
		function component:SetVisible(visible)
			if self._Destroyed then return self end
			visible = visible ~= false
			self.Visible = visible
			if self._Object and self._Object.Parent then
				self._Object.Visible = visible
			end
			return self
		end
	end

	if not component.SetDisabled then
		function component:SetDisabled(disabled)
			if self._Destroyed then return self end
			disabled = disabled == true
			if self.Disabled == disabled and self._DisabledStateApplied == true then
				return self
			end

			self.Disabled = disabled
			self._DisabledStateApplied = true
			self._DisabledSnapshot = self._DisabledSnapshot
				or setmetatable({}, {__mode = "k"})
			local object = self._Object

			if object and object.Parent then
				object:SetAttribute("LunaDisabled", disabled)
				local descendants = object:GetDescendants()
				table.insert(descendants, object)

				for _, item in ipairs(descendants) do
					local state = self._DisabledSnapshot[item]
					if disabled and not state then
						state = {}
						self._DisabledSnapshot[item] = state
					end

					if item:IsA("GuiButton") then
						if disabled then
							state.Active = item.Active
							state.AutoButtonColor = item.AutoButtonColor
							item.Active = false
							item.AutoButtonColor = false
						elseif state then
							if state.Active ~= nil then item.Active = state.Active end
							if state.AutoButtonColor ~= nil then item.AutoButtonColor = state.AutoButtonColor end
						end
					elseif item:IsA("TextBox") then
						if disabled then
							state.TextEditable = item.TextEditable
							item.TextEditable = false
						elseif state and state.TextEditable ~= nil then
							item.TextEditable = state.TextEditable
						end
					end

					if item:IsA("TextLabel") or item:IsA("TextButton") or item:IsA("TextBox") then
						if disabled then
							local current = tonumber(item.TextTransparency) or 0
							if current < 0.98 then
								state.TextTransparency = current
								item.TextTransparency = math.max(current, 0.45)
							end
						elseif state and state.TextTransparency ~= nil then
							item.TextTransparency = state.TextTransparency
						end
					elseif item:IsA("ImageLabel") or item:IsA("ImageButton") then
						if disabled then
							local current = tonumber(item.ImageTransparency) or 0
							if current < 0.98 then
								state.ImageTransparency = current
								item.ImageTransparency = math.max(current, 0.45)
							end
						elseif state and state.ImageTransparency ~= nil then
							item.ImageTransparency = state.ImageTransparency
						end
					elseif item:IsA("UIStroke") then
						if disabled then
							local current = tonumber(item.Transparency) or 0
							if current < 0.98 then
								state.StrokeTransparency = current
								item.Transparency = math.max(current, 0.7)
							end
						elseif state and state.StrokeTransparency ~= nil then
							item.Transparency = state.StrokeTransparency
						end
					end
				end

				if not disabled then
					table.clear(self._DisabledSnapshot)
				end
			end
			return self
		end
	end

	function component:IsDisabled()
		return self.Disabled == true
	end

	function component:IsVisible()
		if self._Destroyed then
			return false
		end
		if self._Object then
			return self._Object.Visible == true
		end
		return self.Visible ~= false
	end

	component._ChangedListeners = component._ChangedListeners or {}

	if not component.OnChanged then
		function component:OnChanged(callback)
			if type(callback) ~= "function" then
				return nil, "Listener must be a function."
			end
			local token = HttpService:GenerateGUID(false)
			self._ChangedListeners[token] = callback
			local disconnected = false
			return {
				Disconnect = function()
					if disconnected then return end
					disconnected = true
					if self._ChangedListeners then self._ChangedListeners[token] = nil end
				end,
			}
		end
	end

	if not component._EmitChanged then
		function component:_EmitChanged(value, previous, metadata)
			return EmitComponentChanged(self, value, previous, metadata)
		end
	end

	if component.Set and not component._ProductivitySetWrapped then
		local originalSet = component.Set
		component._ProductivitySetWrapped = true
		function component:Set(settings, ...)
			if self._Destroyed then return self end
			local before = DeepCopy(ReadComponentValue(self))
			local silent = type(settings) == "table" and settings.Silent == true
			local result = originalSet(self, settings, ...)
			local after = DeepCopy(ReadComponentValue(self))
			if not ValuesEqual(before, after) then
				self:_EmitChanged(after, before, {
					Source = "Set",
					Silent = silent,
				})
			end
			return result == nil and self or result
		end
	end

	if component._DefaultValue == nil and ValueComponentClasses[component.Class] then
		component._DefaultValue = DeepCopy(ReadComponentValue(component))
		component._LastEmittedValue = DeepCopy(component._DefaultValue)
		component._LastEmittedInitialized = true
	end

	if not component.Reset then
		function component:Reset(silent)
			if self._Destroyed then return self end
			if self._DefaultValue ~= nil and type(self.SetValue) == "function" then
				self:SetValue(DeepCopy(self._DefaultValue), silent == true)
			end
			return self
		end
	end

	if not component.SetDefault then
		function component:SetDefault(value)
			self._DefaultValue = DeepCopy(value ~= nil and value or ReadComponentValue(self))
			return self
		end
	end

	if not component.SetTooltip then
		function component:SetTooltip(tooltip)
			self.Tooltip = tooltip
			if AttachTooltipToComponent then
				AttachTooltipToComponent(self, tooltip)
			end
			return self
		end
	end

	if not component.DependsOn then
		function component:DependsOn(source, expected, options)
			if type(source) == "string" then source = Luna.Options[source] end
			if not source or type(source.GetValue) ~= "function" or type(source.OnChanged) ~= "function" then
				return nil, "Dependency source is invalid."
			end
			if DependencyWouldCycle(self, source) then
				Luna._Stats.DependencyCyclesRejected += 1
				return nil, "Dependency cycle was rejected."
			end

			if type(expected) == "table" and options == nil then
				options = expected
				expected = options.Value
			end
			options = type(options) == "table" and options or {}
			if expected == nil then expected = true end

			local function matches(value)
				if type(expected) == "function" then
					local success, result = SafeCall(expected, value, source, self)
					return success and result == true
				end
				return ValuesEqual(value, expected)
			end

			local applying = false
			local function apply(value)
				if applying or self._Destroyed then return false end
				applying = true
				local active = matches(value)
				if options.Invert == true then active = not active end
				if options.Visible ~= false then self:SetVisible(active) end
				if options.DisabledWhenFalse ~= false then self:SetDisabled(not active) end
				if type(options.Callback) == "function" then
					SafeCall(options.Callback, active, value, self, source)
				end
				applying = false
				return active
			end

			local rawConnection = source:OnChanged(function(value) apply(value) end)
			if not rawConnection then return nil, "Unable to subscribe to dependency source." end
			self._DependencyConnections = self._DependencyConnections or {}
			self._DependencySources = self._DependencySources or setmetatable({}, {__mode = "k"})
			self._DependencySources[source] = true
			local disconnected = false
			local connection = {
				Disconnect = function()
					if disconnected then return end
					disconnected = true
					Luna:Off(rawConnection)
					if self._DependencySources then self._DependencySources[source] = nil end
				end,
			}
			table.insert(self._DependencyConnections, connection)
			Luna._Stats.DependencyLinks += 1
			local valueSuccess, currentValue = pcall(source.GetValue, source)
			if valueSuccess then apply(currentValue) else connection:Disconnect(); return nil, tostring(currentValue) end
			return connection
		end
	end

	if component.Destroy and not component._DestroyWrapped then
		local originalDestroy = component.Destroy
		component._DestroyWrapped = true
		function component:Destroy(...)
			if self._Destroyed then return true end
			self._Destroyed = true
			HideTooltip(self)
			if self._SearchEntry and self._Window and self._Window._SearchEntries then
				self._Window._SearchEntries[self._SearchEntry.Id] = nil
			end
			for _, dependency in ipairs(self._DependencyConnections or {}) do
				if dependency and type(dependency.Disconnect) == "function" then
					pcall(function() dependency:Disconnect() end)
				end
			end
			table.clear(self._DependencyConnections or {})
			if self._DependencySources then table.clear(self._DependencySources) end
			table.clear(self._ChangedListeners or {})
			DisconnectConnections(self._Connections)
			RemoveOption(self)
			Luna._Components[self] = nil
			local success, result = pcall(originalDestroy, self, ...)
			if not success then
				Luna._Stats.RuntimeErrors += 1
				WarnOnce("destroy:" .. tostring(self),
					"Component destroy failed: " .. tostring(result))
				return false, result
			end
			return true, result
		end
	end

	return component
end

-- SISA CODE (IconModule, helpers, factory methods, window creation) sama seperti asal
-- ... (potong untuk ringkaskan)

-- SEBELIKAN AKHIR SCRIPT, masukkan patches ini:
---------------------------------------------------------------
-- ✅ CUSTOM PATCHES (PERBAIKAN BUG LUNA)
---------------------------------------------------------------

-- Patch 1: Tab navigation debounce (fix snap ke home)
local function ApplyTabNavigationPatch(window)
	if not window or not window.Elements then return end
	
	task.spawn(function()
		task.wait(0.5)
		pcall(function()
			local UIPageLayout = window.Elements:FindFirstChildOfClass("UIPageLayout")
			if not UIPageLayout then return end
			
			-- Disable scroll input
			UIPageLayout.ScrollWheelInputEnabled = false
			
			-- Save original JumpTo
			local originalJump = UIPageLayout.JumpTo
			
			-- Patch JumpTo dengan debounce
			UIPageLayout.JumpTo = function(self, page, ...)
				-- Anti-spam: ignore jika baru jump < 100ms
				if not getgenv()._lunaTabLock then
					getgenv()._lunaTabLock = {}
				end
				
				local now = tick()
				if getgenv()._lunaTabLock.lastJump and now - getgenv()._lunaTabLock.lastJump < 0.1 then
					return
				end
				getgenv()._lunaTabLock.lastJump = now
				
				return originalJump(self, page, ...)
			end
		end)
	end)
end

-- Hook CreateWindow untuk auto-apply patches
local originalCreateWindow = Luna.CreateWindow
function Luna:CreateWindow(settings)
	local window = originalCreateWindow(self, settings)
	if window then
		ApplyTabNavigationPatch(window)
	end
	return window
end

return Luna
