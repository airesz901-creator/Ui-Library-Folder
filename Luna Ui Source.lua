local Release = "Luna Custom 7.3.13 - Topbar Status Layout Hotfix"

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
}

local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local Localization = game:GetService("LocalizationService")
local Players = game:GetService("Players")
local Player = Players.LocalPlayer
local Camera = workspace.CurrentCamera

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
-- Final lifecycle, diagnostics, and utility layer.
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
Luna._KnownConfigs = {}
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

local function SafeCall(callback, ...)
	if type(callback) ~= "function" then
		return false, "Callback is unavailable."
	end
	local success, result = pcall(callback, ...)
	if not success then
		Luna._Stats.CallbackErrors += 1
		warn("Luna UI callback error: " .. tostring(result))
	end
	return success, result
end

local function ConnectComponent(component, signal, callback)
	component._Connections = component._Connections or {}
	return TrackConnection(signal:Connect(callback), component._Connections)
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

local function EnsureFolderPath(path)
	if type(isfolder) ~= "function" or type(makefolder) ~= "function" then
		return false, "Executor does not support folders."
	end
	local current = ""
	for segment in tostring(path):gmatch("[^/\\]+") do
		current = current == "" and segment or (current .. "/" .. segment)
		if not isfolder(current) then
			local success, err = pcall(makefolder, current)
			if not success then
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


-- Exclusive toggle groups. Any toggles sharing the same Group value behave like
-- radio buttons: enabling one automatically disables the others in that group.
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
	if connection and type(connection.Disconnect) == "function" then
		connection.Disconnect()
		return true
	end
	return false
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
	option:SetValue(value, silent == true)
	return true, option
end

function Luna:SetValues(values, silent)
	if type(values) ~= "table" then return false, "Values must be a table." end
	local errors = {}
	for flag, value in pairs(values) do
		local success, result = self:SetValue(flag, value, silent == true)
		if not success then errors[tostring(flag)] = result end
	end
	return next(errors) == nil, errors
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
	local resetCount = 0
	for _, option in pairs(Luna.Options) do
		if type(option.Reset) == "function" then
			option:Reset(silent == true)
			resetCount += 1
		end
	end
	NormalizeAllToggleGroups(false)
	EmitEvent("AllOptionsReset", resetCount)
	return true, resetCount
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

local function EnhanceComponent(component)
	if type(component) ~= "table" then
		return component
	end

	Luna._Components[component] = true
	component.Visible = component.Visible ~= false
	component.Disabled = component.Disabled == true
	component._Destroyed = component._Destroyed == true
	component._Connections = component._Connections or {}

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
			self.Disabled = disabled
			local object = self._Object

			if object then
				object:SetAttribute("LunaDisabled", disabled)
				local descendants = object:GetDescendants()
				table.insert(descendants, object)

				for _, item in ipairs(descendants) do
					if item:IsA("GuiButton") then
						StoreOriginalBoolean(item, "LunaOriginalActive", item.Active)
						StoreOriginalBoolean(item, "LunaOriginalAutoButtonColor", item.AutoButtonColor)
						if disabled then
							item.Active = false
							item.AutoButtonColor = false
						else
							item.Active = item:GetAttribute("LunaOriginalActive") == true
							item.AutoButtonColor =
								item:GetAttribute("LunaOriginalAutoButtonColor") == true
						end
					elseif item:IsA("TextBox") then
						StoreOriginalBoolean(item, "LunaOriginalTextEditable", item.TextEditable)
						item.TextEditable = disabled
							and false
							or item:GetAttribute("LunaOriginalTextEditable") == true
					end

					if item:IsA("TextLabel")
						or item:IsA("TextButton")
						or item:IsA("TextBox")
					then
						local attribute = "LunaOriginalTextTransparency"
						if disabled then
							if item:GetAttribute(attribute) == nil then
								item:SetAttribute(attribute, item.TextTransparency)
							end
							local original = item:GetAttribute(attribute) or 0
							item.TextTransparency = math.max(original, 0.45)
						else
							local original = item:GetAttribute(attribute)
							if original ~= nil then item.TextTransparency = original end
						end
					elseif item:IsA("ImageLabel") or item:IsA("ImageButton") then
						local attribute = "LunaOriginalImageTransparency"
						if disabled then
							if item:GetAttribute(attribute) == nil then
								item:SetAttribute(attribute, item.ImageTransparency)
							end
							local original = item:GetAttribute(attribute) or 0
							item.ImageTransparency = math.max(original, 0.45)
						else
							local original = item:GetAttribute(attribute)
							if original ~= nil then item.ImageTransparency = original end
						end
					elseif item:IsA("UIStroke") then
						local attribute = "LunaOriginalStrokeTransparency"
						if disabled then
							if item:GetAttribute(attribute) == nil then
								item:SetAttribute(attribute, item.Transparency)
							end
							local original = item:GetAttribute(attribute) or 0
							item.Transparency = math.max(original, 0.7)
						else
							local original = item:GetAttribute(attribute)
							if original ~= nil then item.Transparency = original end
						end
					end
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

		if type(expected) == "table" and options == nil then
			options = expected
			expected = options.Value
		end
		options = type(options) == "table" and options or {}
		if expected == nil then expected = true end

		local function matches(value)
			if type(expected) == "function" then
				local success, result = pcall(expected, value, source, self)
				return success and result == true
			end
			return ValuesEqual(value, expected)
		end

		local function apply(value)
			local active = matches(value)
			if options.Invert == true then active = not active end
			if options.Visible ~= false then self:SetVisible(active) end
			if options.DisabledWhenFalse ~= false then self:SetDisabled(not active) end
			if type(options.Callback) == "function" then
				SafeCall(options.Callback, active, value, self, source)
			end
			return active
		end

		local connection = source:OnChanged(function(value)
			apply(value)
		end)
		self._DependencyConnections = self._DependencyConnections or {}
		table.insert(self._DependencyConnections, connection)
		Luna._Stats.DependencyLinks += 1
		apply(source:GetValue())
		return connection
	end
end

	if component.Destroy and not component._DestroyWrapped then
		local originalDestroy = component.Destroy
		component._DestroyWrapped = true
		function component:Destroy(...)
			if self._Destroyed then return end
			self._Destroyed = true
			if self._SearchEntry and self._Window and self._Window._SearchEntries then
				self._Window._SearchEntries[self._SearchEntry.Id] = nil
			end
			for _, dependency in ipairs(self._DependencyConnections or {}) do
				if dependency and type(dependency.Disconnect) == "function" then pcall(dependency.Disconnect) end
			end
			table.clear(self._DependencyConnections or {})
			DisconnectConnections(self._Connections)
			Luna._Components[self] = nil
			return originalDestroy(self, ...)
		end
	end

	return component
end

function Luna:GetDiagnostics()
	local connectionCount, componentCount, optionCount, groupCount = 0, 0, 0, 0
	for connection in pairs(Luna._Connections) do
		if typeof(connection) == "RBXScriptConnection" and connection.Connected then
			connectionCount += 1
		else
			Luna._Connections[connection] = nil
		end
	end
	for component in pairs(Luna._Components) do
		if component and not component._Destroyed then componentCount += 1 end
	end
	for _ in pairs(Luna.Options) do optionCount += 1 end
	for _ in pairs(Luna._ToggleGroups) do groupCount += 1 end
	return {
		Version = Release,
		Destroyed = Luna._Destroyed,
		Connections = connectionCount,
		Components = componentCount,
		Cleanups = #Luna._Cleanups,
		Options = optionCount,
		RenderLoops = Luna._Stats.RenderLoops,
		CallbackErrors = Luna._Stats.CallbackErrors,
		NotificationsCreated = Luna._Stats.NotificationsCreated,
		ActiveNotifications = Luna._Stats.ActiveNotifications,
		DuplicateFlags = Luna._Stats.DuplicateFlags,
		ConfigRollbacks = Luna._Stats.ConfigRollbacks,
		ConfigWarnings = Luna._Stats.ConfigWarnings,
		EventsEmitted = Luna._Stats.EventsEmitted,
		ModalsOpened = Luna._Stats.ModalsOpened,
		CommandPaletteSearches = Luna._Stats.CommandPaletteSearches,
		DependencyLinks = Luna._Stats.DependencyLinks,
		NotificationHistory = #Luna._NotificationHistory,
		RegisteredThemes = (function() local count = 0 for _ in pairs(Luna._Themes) do count += 1 end return count end)(),
		ToggleGroups = groupCount,
		MaxNotifications = Luna.MaxNotifications,
		NotificationBlurEnabled = Luna.NotificationBlurEnabled,
		WindowBlurEnabled = Luna.WindowBlurEnabled,
		StrictConfig = Luna.StrictConfig,
		ConfigVersion = Luna.ConfigVersion,
	}
end

local website = "github.com/Nebula-Softworks"

-- Credits To Latte Softworks And qweery for Lucide And Material Icons Respectively.
local IconModule = {
	Lucide = nil,
	Material = {
		["perm_media"] = "http://www.roblox.com/asset/?id=6031215982";
		["sticky_note_2"] = "http://www.roblox.com/asset/?id=6031265972";
		["gavel"] = "http://www.roblox.com/asset/?id=6023565902";
		["table_view"] = "http://www.roblox.com/asset/?id=6031233835";
		["home"] = "http://www.roblox.com/asset/?id=6026568195";
		["list"] = "http://www.roblox.com/asset/?id=6026568229";
		["alarm_add"] = "http://www.roblox.com/asset/?id=6023426898";
		["speaker_notes"] = "http://www.roblox.com/asset/?id=6031266001";
		["check_circle_outline"] = "http://www.roblox.com/asset/?id=6023426909";
		["extension"] = "http://www.roblox.com/asset/?id=6023565892";
		["pending"] = "http://www.roblox.com/asset/?id=6031084745";
		["pageview"] = "http://www.roblox.com/asset/?id=6031216007";
		["group_work"] = "http://www.roblox.com/asset/?id=6023565910";
		["zoom_in"] = "http://www.roblox.com/asset/?id=6031075573";
		["aspect_ratio"] = "http://www.roblox.com/asset/?id=6022668895";
		["code"] = "http://www.roblox.com/asset/?id=6022668955";
		["3d_rotation"] = "http://www.roblox.com/asset/?id=6022668893";
		["translate"] = "http://www.roblox.com/asset/?id=6031225812";
		["star_rate"] = "http://www.roblox.com/asset/?id=6031265978";
		["system_update_alt"] = "http://www.roblox.com/asset/?id=6031251515";
		["open_with"] = "http://www.roblox.com/asset/?id=6026568265";
		["build_circle"] = "http://www.roblox.com/asset/?id=6023426952";
		["toc"] = "http://www.roblox.com/asset/?id=6031229341";
		["settings_phone"] = "http://www.roblox.com/asset/?id=6031289445";
		["open_in_full"] = "http://www.roblox.com/asset/?id=6026568245";
		["history"] = "http://www.roblox.com/asset/?id=6026568197";
		["accessibility_new"] = "http://www.roblox.com/asset/?id=6022668945";
		["hourglass_disabled"] = "http://www.roblox.com/asset/?id=6026568193";
		["line_style"] = "http://www.roblox.com/asset/?id=6026568276";
		["account_circle"] = "http://www.roblox.com/asset/?id=6022668898";
		["settings_cell"] = "http://www.roblox.com/asset/?id=6031280890";
		["search_off"] = "http://www.roblox.com/asset/?id=6031260783";
		["shop"] = "http://www.roblox.com/asset/?id=6031265983";
		["anchor"] = "http://www.roblox.com/asset/?id=6023426906";
		["language"] = "http://www.roblox.com/asset/?id=6026568213";
		["settings_brightness"] = "http://www.roblox.com/asset/?id=6031280902";
		["restore_page"] = "http://www.roblox.com/asset/?id=6031154877";
		["chrome_reader_mode"] = "http://www.roblox.com/asset/?id=6023426912";
		["sync_alt"] = "http://www.roblox.com/asset/?id=6031233840";
		["book"] = "http://www.roblox.com/asset/?id=6022860343";
		["smart_button"] = "http://www.roblox.com/asset/?id=6031265962";
		["request_page"] = "http://www.roblox.com/asset/?id=6031154873";
		["lock_clock"] = "http://www.roblox.com/asset/?id=6026568260";
		["android"] = "http://www.roblox.com/asset/?id=6022668966";
		["outgoing_mail"] = "http://www.roblox.com/asset/?id=6026568242";
		["dynamic_form"] = "http://www.roblox.com/asset/?id=6023426970";
		["track_changes"] = "http://www.roblox.com/asset/?id=6031225814";
		["source"] = "http://www.roblox.com/asset/?id=6031289451";
		["thumb_down"] = "http://www.roblox.com/asset/?id=6031229336";
		["integration_instructions"] = "http://www.roblox.com/asset/?id=6026568214";
		["opacity"] = "http://www.roblox.com/asset/?id=6026568295";
		["perm_identity"] = "http://www.roblox.com/asset/?id=6031215978";
		["view_module"] = "http://www.roblox.com/asset/?id=6031079152";
		["perm_data_setting"] = "http://www.roblox.com/asset/?id=6031215991";
		["assignment_turned_in"] = "http://www.roblox.com/asset/?id=6023426904";
		["change_history"] = "http://www.roblox.com/asset/?id=6023426914";
		["thumb_down_off_alt"] = "http://www.roblox.com/asset/?id=6031229354";
		["text_rotation_angledown"] = "http://www.roblox.com/asset/?id=6031251513";
		["bookmark"] = "http://www.roblox.com/asset/?id=6022852108";
		["view_stream"] = "http://www.roblox.com/asset/?id=6031079164";
		["remove_done"] = "http://www.roblox.com/asset/?id=6031086169";
		["markunread_mailbox"] = "http://www.roblox.com/asset/?id=6031082531";
		["store"] = "http://www.roblox.com/asset/?id=6031265968";
		["text_rotation_angleup"] = "http://www.roblox.com/asset/?id=6031229337";
		["eco"] = "http://www.roblox.com/asset/?id=6023426988";
		["find_in_page"] = "http://www.roblox.com/asset/?id=6023426986";
		["api"] = "http://www.roblox.com/asset/?id=6022668911";
		["launch"] = "http://www.roblox.com/asset/?id=6026568211";
		["text_rotation_down"] = "http://www.roblox.com/asset/?id=6031229334";
		["flip_to_back"] = "http://www.roblox.com/asset/?id=6023565896";
		["contact_page"] = "http://www.roblox.com/asset/?id=6022668881";
		["preview"] = "http://www.roblox.com/asset/?id=6031260793";
		["restore"] = "http://www.roblox.com/asset/?id=6031260800";
		["favorite_border"] = "http://www.roblox.com/asset/?id=6023565882";
		["assignment_late"] = "http://www.roblox.com/asset/?id=6022668880";
		["youtube_searched_for"] = "http://www.roblox.com/asset/?id=6031075934";
		["hourglass_full"] = "http://www.roblox.com/asset/?id=6026568190";
		["timeline"] = "http://www.roblox.com/asset/?id=6031229350";
		["turned_in"] = "http://www.roblox.com/asset/?id=6031225808";
		["info"] = "http://www.roblox.com/asset/?id=6026568227";
		["restore_from_trash"] = "http://www.roblox.com/asset/?id=6031154869";
		["arrow_circle_down"] = "http://www.roblox.com/asset/?id=6022668877";
		["flaky"] = "http://www.roblox.com/asset/?id=6031082523";
		["alarm_on"] = "http://www.roblox.com/asset/?id=6023426920";
		["swap_vertical_circle"] = "http://www.roblox.com/asset/?id=6031233839";
		["open_in_new"] = "http://www.roblox.com/asset/?id=6026568256";
		["watch_later"] = "http://www.roblox.com/asset/?id=6031075924";
		["alarm_off"] = "http://www.roblox.com/asset/?id=6023426901";
		["maximize"] = "http://www.roblox.com/asset/?id=6026568267";
		["lock_outline"] = "http://www.roblox.com/asset/?id=6031082533";
		["outbond"] = "http://www.roblox.com/asset/?id=6026568244";
		["view_carousel"] = "http://www.roblox.com/asset/?id=6031251507";
		["published_with_changes"] = "http://www.roblox.com/asset/?id=6031243328";
		["verified_user"] = "http://www.roblox.com/asset/?id=6031225819";
		["drag_indicator"] = "http://www.roblox.com/asset/?id=6023426962";
		["lightbulb_outline"] = "http://www.roblox.com/asset/?id=6026568254";
		["segment"] = "http://www.roblox.com/asset/?id=6031260773";
		["assignment"] = "http://www.roblox.com/asset/?id=6022668882";
		["work_outline"] = "http://www.roblox.com/asset/?id=6031075930";
		["line_weight"] = "http://www.roblox.com/asset/?id=6026568226";
		["dangerous"] = "http://www.roblox.com/asset/?id=6022668916";
		["assessment"] = "http://www.roblox.com/asset/?id=6022668897";
		["view_day"] = "http://www.roblox.com/asset/?id=6031079153";
		["help_center"] = "http://www.roblox.com/asset/?id=6026568192";
		["logout"] = "http://www.roblox.com/asset/?id=6031082522";
		["event"] = "http://www.roblox.com/asset/?id=6023426959";
		["get_app"] = "http://www.roblox.com/asset/?id=6023565889";
		["tab"] = "http://www.roblox.com/asset/?id=6031233851";
		["label"] = "http://www.roblox.com/asset/?id=6031082525";
		["g_translate"] = "http://www.roblox.com/asset/?id=6031082526";
		["view_week"] = "http://www.roblox.com/asset/?id=6031079154";
		["view_in_ar"] = "http://www.roblox.com/asset/?id=6031079158";
		["card_travel"] = "http://www.roblox.com/asset/?id=6023426925";
		["lock_open"] = "http://www.roblox.com/asset/?id=6026568220";
		["voice_over_off"] = "http://www.roblox.com/asset/?id=6031075927";
		["app_blocking"] = "http://www.roblox.com/asset/?id=6022668952";
		["settings_ethernet"] = "http://www.roblox.com/asset/?id=6031280883";
		["supervised_user_circle"] = "http://www.roblox.com/asset/?id=6031289449";
		["done_all"] = "http://www.roblox.com/asset/?id=6023426929";
		["lightbulb"] = "http://www.roblox.com/asset/?id=6026568247";
		["find_replace"] = "http://www.roblox.com/asset/?id=6023426979";
		["bookmarks"] = "http://www.roblox.com/asset/?id=6023426924";
		["today"] = "http://www.roblox.com/asset/?id=6031229352";
		["class"] = "http://www.roblox.com/asset/?id=6022668949";
		["supervisor_account"] = "http://www.roblox.com/asset/?id=6031251516";
		["support"] = "http://www.roblox.com/asset/?id=6031251532";
		["done_outline"] = "http://www.roblox.com/asset/?id=6023426936";
		["reorder"] = "http://www.roblox.com/asset/?id=6031154868";
		["fact_check"] = "http://www.roblox.com/asset/?id=6023426951";
		["thumb_up"] = "http://www.roblox.com/asset/?id=6031229347";
		["assignment_returned"] = "http://www.roblox.com/asset/?id=6023426899";
		["card_giftcard"] = "http://www.roblox.com/asset/?id=6023426978";
		["trending_down"] = "http://www.roblox.com/asset/?id=6031225811";
		["settings_backup_restore"] = "http://www.roblox.com/asset/?id=6031280886";
		["settings_voice"] = "http://www.roblox.com/asset/?id=6031265966";
		["dns"] = "http://www.roblox.com/asset/?id=6023426958";
		["perm_scan_wifi"] = "http://www.roblox.com/asset/?id=6031215985";
		["plagiarism"] = "http://www.roblox.com/asset/?id=6031243320";
		["commute"] = "http://www.roblox.com/asset/?id=6022668901";
		["gif"] = "http://www.roblox.com/asset/?id=6031082540";
		["work"] = "http://www.roblox.com/asset/?id=6031075939";
		["picture_in_picture_alt"] = "http://www.roblox.com/asset/?id=6031215979";
		["query_builder"] = "http://www.roblox.com/asset/?id=6031086183";
		["label_off"] = "http://www.roblox.com/asset/?id=6026568209";
		["all_out"] = "http://www.roblox.com/asset/?id=6022668876";
		["article"] = "http://www.roblox.com/asset/?id=6022668907";
		["shopping_basket"] = "http://www.roblox.com/asset/?id=6031265997";
		["mark_as_unread"] = "http://www.roblox.com/asset/?id=6026568223";
		["work_off"] = "http://www.roblox.com/asset/?id=6031075937";
		["delete_outline"] = "http://www.roblox.com/asset/?id=6022668962";
		["account_box"] = "http://www.roblox.com/asset/?id=6023426915";
		["home_filled"] = "rbxassetid://9080449299";
		["lock"] = "http://www.roblox.com/asset/?id=6026568224";
		["perm_device_information"] = "http://www.roblox.com/asset/?id=6031215996";
		["add_task"] = "http://www.roblox.com/asset/?id=6022668912";
		["text_rotate_up"] = "http://www.roblox.com/asset/?id=6031251526";
		["swipe"] = "http://www.roblox.com/asset/?id=6031233863";
		["eject"] = "http://www.roblox.com/asset/?id=6023426930";
		["mediation"] = "http://www.roblox.com/asset/?id=6026568249";
		["label_important_outline"] = "http://www.roblox.com/asset/?id=6026568199";
		["settings_remote"] = "http://www.roblox.com/asset/?id=6031289442";
		["history_toggle_off"] = "http://www.roblox.com/asset/?id=6026568196";
		["invert_colors"] = "http://www.roblox.com/asset/?id=6026568253";
		["visibility_off"] = "http://www.roblox.com/asset/?id=6031075929";
		["addchart"] = "http://www.roblox.com/asset/?id=6023426905";
		["cancel_schedule_send"] = "http://www.roblox.com/asset/?id=6022668963";
		["loyalty"] = "http://www.roblox.com/asset/?id=6026568237";
		["speaker_notes_off"] = "http://www.roblox.com/asset/?id=6031265965";
		["online_prediction"] = "http://www.roblox.com/asset/?id=6026568239";
		["remove_shopping_cart"] = "http://www.roblox.com/asset/?id=6031260778";
		["text_rotate_vertical"] = "http://www.roblox.com/asset/?id=6031251518";
		["visibility"] = "http://www.roblox.com/asset/?id=6031075931";
		["add_to_drive"] = "http://www.roblox.com/asset/?id=6022860335";
		["accessible"] = "http://www.roblox.com/asset/?id=6022668902";
		["bookmark_border"] = "http://www.roblox.com/asset/?id=6022860339";
		["tour"] = "http://www.roblox.com/asset/?id=6031229362";
		["compare_arrows"] = "http://www.roblox.com/asset/?id=6022668951";
		["view_sidebar"] = "http://www.roblox.com/asset/?id=6031079160";
		["face"] = "http://www.roblox.com/asset/?id=6023426944";
		["wysiwyg"] = "http://www.roblox.com/asset/?id=6031075938";
		["camera_enhance"] = "http://www.roblox.com/asset/?id=6023426935";
		["perm_camera_mic"] = "http://www.roblox.com/asset/?id=6031215983";
		["model_training"] = "http://www.roblox.com/asset/?id=6026568222";
		["arrow_circle_up"] = "http://www.roblox.com/asset/?id=6022668934";
		["euro_symbol"] = "http://www.roblox.com/asset/?id=6023426954";
		["pending_actions"] = "http://www.roblox.com/asset/?id=6031260777";
		["not_accessible"] = "http://www.roblox.com/asset/?id=6026568269";
		["explore_off"] = "http://www.roblox.com/asset/?id=6023426953";
		["build"] = "http://www.roblox.com/asset/?id=6023426938";
		["backup"] = "http://www.roblox.com/asset/?id=6023426911";
		["settings_input_antenna"] = "http://www.roblox.com/asset/?id=6031280891";
		["disabled_by_default"] = "http://www.roblox.com/asset/?id=6023426939";
		["upgrade"] = "http://www.roblox.com/asset/?id=6031225815";
		["contactless"] = "http://www.roblox.com/asset/?id=6022668886";
		["trending_flat"] = "http://www.roblox.com/asset/?id=6031225818";
		["schedule"] = "http://www.roblox.com/asset/?id=6031260808";
		["offline_pin"] = "http://www.roblox.com/asset/?id=6031084770";
		["date_range"] = "http://www.roblox.com/asset/?id=6022668894";
		["flight_land"] = "http://www.roblox.com/asset/?id=6023565897";
		["view_headline"] = "http://www.roblox.com/asset/?id=6031079151";
		["cached"] = "http://www.roblox.com/asset/?id=6023426921";
		["unpublished"] = "http://www.roblox.com/asset/?id=6031225817";
		["outlet"] = "http://www.roblox.com/asset/?id=6031084748";
		["favorite"] = "http://www.roblox.com/asset/?id=6023426974";
		["vertical_split"] = "http://www.roblox.com/asset/?id=6031225820";
		["report_problem"] = "http://www.roblox.com/asset/?id=6031086176";
		["fingerprint"] = "http://www.roblox.com/asset/?id=6023565895";
		["important_devices"] = "http://www.roblox.com/asset/?id=6026568202";
		["outbox"] = "http://www.roblox.com/asset/?id=6026568263";
		["all_inbox"] = "http://www.roblox.com/asset/?id=6022668909";
		["label_important"] = "http://www.roblox.com/asset/?id=6026568215";
		["print"] = "http://www.roblox.com/asset/?id=6031243324";
		["settings_bluetooth"] = "http://www.roblox.com/asset/?id=6031280905";
		["power_settings_new"] = "http://www.roblox.com/asset/?id=6031260781";
		["zoom_out"] = "http://www.roblox.com/asset/?id=6031075577";
		["stars"] = "http://www.roblox.com/asset/?id=6031265971";
		["offline_bolt"] = "http://www.roblox.com/asset/?id=6031084742";
		["feedback"] = "http://www.roblox.com/asset/?id=6023426957";
		["accessibility"] = "http://www.roblox.com/asset/?id=6022668887";
		["announcement"] = "http://www.roblox.com/asset/?id=6022668946";
		["settings_input_hdmi"] = "http://www.roblox.com/asset/?id=6031280970";
		["leaderboard"] = "http://www.roblox.com/asset/?id=6026568216";
		["view_quilt"] = "http://www.roblox.com/asset/?id=6031079155";
		["note_add"] = "http://www.roblox.com/asset/?id=6031084749";
		["theaters"] = "http://www.roblox.com/asset/?id=6031229335";
		["alarm"] = "http://www.roblox.com/asset/?id=6023426910";
		["settings_input_composite"] = "http://www.roblox.com/asset/?id=6031280896";
		["grade"] = "http://www.roblox.com/asset/?id=6026568189";
		["tab_unselected"] = "http://www.roblox.com/asset/?id=6031251505";
		["swap_vert"] = "http://www.roblox.com/asset/?id=6031233847";
		["assignment_return"] = "http://www.roblox.com/asset/?id=6023426931";
		["highlight_alt"] = "http://www.roblox.com/asset/?id=6023565913";
		["shopping_bag"] = "http://www.roblox.com/asset/?id=6031265970";
		["contact_support"] = "http://www.roblox.com/asset/?id=6022668879";
		["flip_to_front"] = "http://www.roblox.com/asset/?id=6023565894";
		["touch_app"] = "http://www.roblox.com/asset/?id=6031229361";
		["room"] = "http://www.roblox.com/asset/?id=6031154875";
		["send_and_archive"] = "http://www.roblox.com/asset/?id=6031280889";
		["view_array"] = "http://www.roblox.com/asset/?id=6031225842";
		["settings_power"] = "http://www.roblox.com/asset/?id=6031289446";
		["admin_panel_settings"] = "http://www.roblox.com/asset/?id=6022668961";
		["open_in_browser"] = "http://www.roblox.com/asset/?id=6026568266";
		["card_membership"] = "http://www.roblox.com/asset/?id=6023426942";
		["rule"] = "http://www.roblox.com/asset/?id=6031154859";
		["schedule_send"] = "http://www.roblox.com/asset/?id=6031154866";
		["calendar_today"] = "http://www.roblox.com/asset/?id=6022668917";
		["info_outline"] = "http://www.roblox.com/asset/?id=6026568210";
		["description"] = "http://www.roblox.com/asset/?id=6022668888";
		["dashboard_customize"] = "http://www.roblox.com/asset/?id=6022668899";
		["rowing"] = "http://www.roblox.com/asset/?id=6031154857";
		["swap_horizontal_circle"] = "http://www.roblox.com/asset/?id=6031233833";
		["account_balance_wallet"] = "http://www.roblox.com/asset/?id=6022668892";
		["view_agenda"] = "http://www.roblox.com/asset/?id=6031225831";
		["shop_two"] = "http://www.roblox.com/asset/?id=6031289461";
		["done"] = "http://www.roblox.com/asset/?id=6023426926";
		["circle_notifications"] = "http://www.roblox.com/asset/?id=6023426923";
		["compress"] = "http://www.roblox.com/asset/?id=6022668878";
		["calendar_view_day"] = "http://www.roblox.com/asset/?id=6023426946";
		["thumbs_up_down"] = "http://www.roblox.com/asset/?id=6031229373";
		["account_balance"] = "http://www.roblox.com/asset/?id=6022668900";
		["play_for_work"] = "http://www.roblox.com/asset/?id=6031260776";
		["pets"] = "http://www.roblox.com/asset/?id=6031260782";
		["view_column"] = "http://www.roblox.com/asset/?id=6031079172";
		["search"] = "http://www.roblox.com/asset/?id=6031154871";
		["autorenew"] = "http://www.roblox.com/asset/?id=6023565901";
		["copyright"] = "http://www.roblox.com/asset/?id=6023565898";
		["privacy_tip"] = "http://www.roblox.com/asset/?id=6031260784";
		["arrow_right_alt"] = "http://www.roblox.com/asset/?id=6022668890";
		["delete"] = "http://www.roblox.com/asset/?id=6022668885";
		["nightlight_round"] = "http://www.roblox.com/asset/?id=6031084743";
		["batch_prediction"] = "http://www.roblox.com/asset/?id=6022860334";
		["shopping_cart"] = "http://www.roblox.com/asset/?id=6031265976";
		["login"] = "http://www.roblox.com/asset/?id=6031082527";
		["settings_input_svideo"] = "http://www.roblox.com/asset/?id=6031289444";
		["payment"] = "http://www.roblox.com/asset/?id=6031084751";
		["update"] = "http://www.roblox.com/asset/?id=6031225810";
		["text_rotation_none"] = "http://www.roblox.com/asset/?id=6031229344";
		["perm_contact_calendar"] = "http://www.roblox.com/asset/?id=6031215990";
		["explore"] = "http://www.roblox.com/asset/?id=6023426941";
		["delete_forever"] = "http://www.roblox.com/asset/?id=6022668939";
		["rounded_corner"] = "http://www.roblox.com/asset/?id=6031154861";
		["book_online"] = "http://www.roblox.com/asset/?id=6022860332";
		["quickreply"] = "http://www.roblox.com/asset/?id=6031243319";
		["bug_report"] = "http://www.roblox.com/asset/?id=6022852107";
		["subtitles_off"] = "http://www.roblox.com/asset/?id=6031289466";
		["close_fullscreen"] = "http://www.roblox.com/asset/?id=6023426928";
		["horizontal_split"] = "http://www.roblox.com/asset/?id=6026568194";
		["minimize"] = "http://www.roblox.com/asset/?id=6026568240";
		["filter_list_alt"] = "http://www.roblox.com/asset/?id=6023426955";
		["add_shopping_cart"] = "http://www.roblox.com/asset/?id=6022668875";
		["next_plan"] = "http://www.roblox.com/asset/?id=6026568231";
		["view_list"] = "http://www.roblox.com/asset/?id=6031079156";
		["receipt"] = "http://www.roblox.com/asset/?id=6031086173";
		["polymer"] = "http://www.roblox.com/asset/?id=6031260785";
		["spellcheck"] = "http://www.roblox.com/asset/?id=6031289450";
		["wifi_protected_setup"] = "http://www.roblox.com/asset/?id=6031075926";
		["label_outline"] = "http://www.roblox.com/asset/?id=6026568207";
		["highlight_off"] = "http://www.roblox.com/asset/?id=6023565916";
		["turned_in_not"] = "http://www.roblox.com/asset/?id=6031225806";
		["edit_off"] = "http://www.roblox.com/asset/?id=6023426983";
		["question_answer"] = "http://www.roblox.com/asset/?id=6031086172";
		["settings_overscan"] = "http://www.roblox.com/asset/?id=6031289459";
		["trending_up"] = "http://www.roblox.com/asset/?id=6031225816";
		["verified"] = "http://www.roblox.com/asset/?id=6031225809";
		["flight_takeoff"] = "http://www.roblox.com/asset/?id=6023565891";
		["grading"] = "http://www.roblox.com/asset/?id=6026568191";
		["dashboard"] = "http://www.roblox.com/asset/?id=6022668883";
		["expand"] = "http://www.roblox.com/asset/?id=6022668891";
		["backup_table"] = "http://www.roblox.com/asset/?id=6022860338";
		["analytics"] = "http://www.roblox.com/asset/?id=6022668884";
		["picture_in_picture"] = "http://www.roblox.com/asset/?id=6031215994";
		["settings"] = "http://www.roblox.com/asset/?id=6031280882";
		["accessible_forward"] = "http://www.roblox.com/asset/?id=6022668906";
		["pan_tool"] = "http://www.roblox.com/asset/?id=6031084771";
		["https"] = "http://www.roblox.com/asset/?id=6026568200";
		["filter_alt"] = "http://www.roblox.com/asset/?id=6023426984";
		["thumb_up_off_alt"] = "http://www.roblox.com/asset/?id=6031229342";
		["record_voice_over"] = "http://www.roblox.com/asset/?id=6031243318";
		["help_outline"] = "http://www.roblox.com/asset/?id=6026568201";
		["check_circle"] = "http://www.roblox.com/asset/?id=6023426945";
		["comment_bank"] = "http://www.roblox.com/asset/?id=6023426937";
		["perm_phone_msg"] = "http://www.roblox.com/asset/?id=6031215986";
		["settings_applications"] = "http://www.roblox.com/asset/?id=6031280894";
		["exit_to_app"] = "http://www.roblox.com/asset/?id=6023426922";
		["saved_search"] = "http://www.roblox.com/asset/?id=6031154867";
		["toll"] = "http://www.roblox.com/asset/?id=6031229343";
		["not_started"] = "http://www.roblox.com/asset/?id=6026568232";
		["subject"] = "http://www.roblox.com/asset/?id=6031289452";
		["redeem"] = "http://www.roblox.com/asset/?id=6031086170";
		["input"] = "http://www.roblox.com/asset/?id=6026568225";
		["settings_input_component"] = "http://www.roblox.com/asset/?id=6031280884";
		["assignment_ind"] = "http://www.roblox.com/asset/?id=6022668935";
		["swap_horiz"] = "http://www.roblox.com/asset/?id=6031233841";
		["fullscreen"] = "http://www.roblox.com/asset/?id=6031094681";
		["cancel"] = "http://www.roblox.com/asset/?id=6031094677";
		["subdirectory_arrow_left"] = "http://www.roblox.com/asset/?id=6031104654";
		["close"] = "http://www.roblox.com/asset/?id=6031094678";
		["arrow_back_ios"] = "http://www.roblox.com/asset/?id=6031091003";
		["east"] = "http://www.roblox.com/asset/?id=6031094675";
		["unfold_more"] = "http://www.roblox.com/asset/?id=6031104644";
		["south"] = "http://www.roblox.com/asset/?id=6031104646";
		["arrow_drop_up"] = "http://www.roblox.com/asset/?id=6031090990";
		["arrow_back"] = "http://www.roblox.com/asset/?id=6031091000";
		["arrow_downward"] = "http://www.roblox.com/asset/?id=6031090991";
		["west"] = "http://www.roblox.com/asset/?id=6031104677";
		["legend_toggle"] = "http://www.roblox.com/asset/?id=6031097233";
		["fullscreen_exit"] = "http://www.roblox.com/asset/?id=6031094691";
		["last_page"] = "http://www.roblox.com/asset/?id=6031094686";
		["switch_right"] = "http://www.roblox.com/asset/?id=6031104649";
		["check"] = "http://www.roblox.com/asset/?id=6031094667";
		["home_work"] = "http://www.roblox.com/asset/?id=6031094683";
		["north_east"] = "http://www.roblox.com/asset/?id=6031097228";
		["double_arrow"] = "http://www.roblox.com/asset/?id=6031094674";
		["more_vert"] = "http://www.roblox.com/asset/?id=6031104648";
		["chevron_left"] = "http://www.roblox.com/asset/?id=6031094670";
		["more_horiz"] = "http://www.roblox.com/asset/?id=6031104650";
		["unfold_less"] = "http://www.roblox.com/asset/?id=6031104681";
		["first_page"] = "http://www.roblox.com/asset/?id=6031094682";
		["payments"] = "http://www.roblox.com/asset/?id=6031097227";
		["arrow_right"] = "http://www.roblox.com/asset/?id=6031090994";
		["offline_share"] = "http://www.roblox.com/asset/?id=6031097267";
		["south_west"] = "http://www.roblox.com/asset/?id=6031104652";
		["expand_less"] = "http://www.roblox.com/asset/?id=6031094679";
		["south_east"] = "http://www.roblox.com/asset/?id=6031104642";
		["assistant_navigation"] = "http://www.roblox.com/asset/?id=6031091006";
		["apps"] = "http://www.roblox.com/asset/?id=6031090999";
		["arrow_upward"] = "http://www.roblox.com/asset/?id=6031090997";
		["app_settings_alt"] = "http://www.roblox.com/asset/?id=6031090998";
		["subdirectory_arrow_right"] = "http://www.roblox.com/asset/?id=6031104647";
		["north_west"] = "http://www.roblox.com/asset/?id=6031104630";
		["switch_left"] = "http://www.roblox.com/asset/?id=6031104651";
		["chevron_right"] = "http://www.roblox.com/asset/?id=6031094680";
		["arrow_forward"] = "http://www.roblox.com/asset/?id=6031090995";
		["arrow_forward_ios"] = "http://www.roblox.com/asset/?id=6031091008";
		["arrow_drop_down"] = "http://www.roblox.com/asset/?id=6031091004";
		["refresh"] = "http://www.roblox.com/asset/?id=6031097226";
		["pivot_table_chart"] = "http://www.roblox.com/asset/?id=6031097234";
		["expand_more"] = "http://www.roblox.com/asset/?id=6031094687";
		["campaign"] = "http://www.roblox.com/asset/?id=6031094666";
		["arrow_left"] = "http://www.roblox.com/asset/?id=6031091002";
		["arrow_drop_down_circle"] = "http://www.roblox.com/asset/?id=6031091001";
		["menu_open"] = "http://www.roblox.com/asset/?id=6031097229";
		["waterfall_chart"] = "http://www.roblox.com/asset/?id=6031104632";
		["assistant_direction"] = "http://www.roblox.com/asset/?id=6031091005";
		["menu"] = "http://www.roblox.com/asset/?id=6031097225";
		["personal_video"] = "http://www.roblox.com/asset/?id=6034457070";
		["power_off"] = "http://www.roblox.com/asset/?id=6034457087";
		["wifi_off"] = "http://www.roblox.com/asset/?id=6034461625";
		["adb"] = "http://www.roblox.com/asset/?id=6034418515";
		["airline_seat_recline_normal"] = "http://www.roblox.com/asset/?id=6034418512";
		["sync_problem"] = "http://www.roblox.com/asset/?id=6034452653";
		["network_check"] = "http://www.roblox.com/asset/?id=6034461631";
		["event_busy"] = "http://www.roblox.com/asset/?id=6034439634";
		["airline_seat_flat"] = "http://www.roblox.com/asset/?id=6034418511";
		["disc_full"] = "http://www.roblox.com/asset/?id=6034418518";
		["sd_card"] = "http://www.roblox.com/asset/?id=6034457089";
		["time_to_leave"] = "http://www.roblox.com/asset/?id=6034452660";
		["phone_bluetooth_speaker"] = "http://www.roblox.com/asset/?id=6034457057";
		["phone_paused"] = "http://www.roblox.com/asset/?id=6034457066";
		["phone_locked"] = "http://www.roblox.com/asset/?id=6034457058";
		["more"] = "http://www.roblox.com/asset/?id=6034461627";
		["add_call"] = "http://www.roblox.com/asset/?id=6034418524";
		["account_tree"] = "http://www.roblox.com/asset/?id=6034418507";
		["do_not_disturb_on"] = "http://www.roblox.com/asset/?id=6034439649";
		["event_note"] = "http://www.roblox.com/asset/?id=6034439637";
		["sync_disabled"] = "http://www.roblox.com/asset/?id=6034452649";
		["mms"] = "http://www.roblox.com/asset/?id=6034461621";
		["airline_seat_flat_angled"] = "http://www.roblox.com/asset/?id=6034418513";
		["bluetooth_audio"] = "http://www.roblox.com/asset/?id=6034418522";
		["vibration"] = "http://www.roblox.com/asset/?id=6034452651";
		["system_update"] = "http://www.roblox.com/asset/?id=6034452663";
		["enhanced_encryption"] = "http://www.roblox.com/asset/?id=6034439652";
		["wc"] = "http://www.roblox.com/asset/?id=6034452643";
		["live_tv"] = "http://www.roblox.com/asset/?id=6034439648";
		["folder_special"] = "http://www.roblox.com/asset/?id=6034439639";
		["phone_missed"] = "http://www.roblox.com/asset/?id=6034457056";
		["airline_seat_recline_extra"] = "http://www.roblox.com/asset/?id=6034418528";
		["sms"] = "http://www.roblox.com/asset/?id=6034452645";
		["tap_and_play"] = "http://www.roblox.com/asset/?id=6034452650";
		["confirmation_number"] = "http://www.roblox.com/asset/?id=6034418519";
		["event_available"] = "http://www.roblox.com/asset/?id=6034439643";
		["sms_failed"] = "http://www.roblox.com/asset/?id=6034452676";
		["do_not_disturb_alt"] = "http://www.roblox.com/asset/?id=6034461619";
		["do_not_disturb"] = "http://www.roblox.com/asset/?id=6034439645";
		["ondemand_video"] = "http://www.roblox.com/asset/?id=6034457065";
		["no_encryption"] = "http://www.roblox.com/asset/?id=6034457059";
		["airline_seat_legroom_extra"] = "http://www.roblox.com/asset/?id=6034418508";
		["tv_off"] = "http://www.roblox.com/asset/?id=6034452646";
		["sim_card_alert"] = "http://www.roblox.com/asset/?id=6034452641";
		["airline_seat_legroom_normal"] = "http://www.roblox.com/asset/?id=6034418532";
		["wifi"] = "http://www.roblox.com/asset/?id=6034461626";
		["do_not_disturb_off"] = "http://www.roblox.com/asset/?id=6034439642";
		["imagesearch_roller"] = "http://www.roblox.com/asset/?id=6034439635";
		["power"] = "http://www.roblox.com/asset/?id=6034457105";
		["airline_seat_legroom_reduced"] = "http://www.roblox.com/asset/?id=6034418520";
		["phone_in_talk"] = "http://www.roblox.com/asset/?id=6034457067";
		["airline_seat_individual_suite"] = "http://www.roblox.com/asset/?id=6034418514";
		["priority_high"] = "http://www.roblox.com/asset/?id=6034457092";
		["phone_callback"] = "http://www.roblox.com/asset/?id=6034457104";
		["phone_forwarded"] = "http://www.roblox.com/asset/?id=6034457106";
		["sync"] = "http://www.roblox.com/asset/?id=6034452662";
		["vpn_lock"] = "http://www.roblox.com/asset/?id=6034452648";
		["support_agent"] = "http://www.roblox.com/asset/?id=6034452656";
		["network_locked"] = "http://www.roblox.com/asset/?id=6034457064";
		["directions_off"] = "http://www.roblox.com/asset/?id=6034418517";
		["drive_eta"] = "http://www.roblox.com/asset/?id=6034464371";
		["sensor_window"] = "http://www.roblox.com/asset/?id=6031067242";
		["sensor_door"] = "http://www.roblox.com/asset/?id=6031067241";
		["keyboard_return"] = "http://www.roblox.com/asset/?id=6034818370";
		["monitor"] = "http://www.roblox.com/asset/?id=6034837803";
		["device_hub"] = "http://www.roblox.com/asset/?id=6034789877";
		["keyboard"] = "http://www.roblox.com/asset/?id=6034818398";
		["keyboard_voice"] = "http://www.roblox.com/asset/?id=6034818360";
		["cast"] = "http://www.roblox.com/asset/?id=6034789876";
		["developer_board"] = "http://www.roblox.com/asset/?id=6034789883";
		["tablet"] = "http://www.roblox.com/asset/?id=6034848733";
		["keyboard_hide"] = "http://www.roblox.com/asset/?id=6034818386";
		["dock"] = "http://www.roblox.com/asset/?id=6034789888";
		["phonelink"] = "http://www.roblox.com/asset/?id=6034837801";
		["device_unknown"] = "http://www.roblox.com/asset/?id=6034789884";
		["speaker_group"] = "http://www.roblox.com/asset/?id=6034848732";
		["desktop_mac"] = "http://www.roblox.com/asset/?id=6034789898";
		["point_of_sale"] = "http://www.roblox.com/asset/?id=6034837798";
		["memory"] = "http://www.roblox.com/asset/?id=6034837807";
		["keyboard_tab"] = "http://www.roblox.com/asset/?id=6034818363";
		["router"] = "http://www.roblox.com/asset/?id=6034837806";
		["sim_card"] = "http://www.roblox.com/asset/?id=6034837800";
		["headset"] = "http://www.roblox.com/asset/?id=6034789880";
		["gamepad"] = "http://www.roblox.com/asset/?id=6034789879";
		["speaker"] = "http://www.roblox.com/asset/?id=6034848746";
		["devices_other"] = "http://www.roblox.com/asset/?id=6034789873";
		["laptop"] = "http://www.roblox.com/asset/?id=6034818367";
		["scanner"] = "http://www.roblox.com/asset/?id=6034837799";
		["tv"] = "http://www.roblox.com/asset/?id=6034848740";
		["headset_mic"] = "http://www.roblox.com/asset/?id=6034818383";
		["browser_not_supported"] = "http://www.roblox.com/asset/?id=6034789875";
		["computer"] = "http://www.roblox.com/asset/?id=6034789874";
		["connected_tv"] = "http://www.roblox.com/asset/?id=6034789870";
		["phonelink_off"] = "http://www.roblox.com/asset/?id=6034837804";
		["headset_off"] = "http://www.roblox.com/asset/?id=6034818402";
		["cast_connected"] = "http://www.roblox.com/asset/?id=6034789895";
		["watch"] = "http://www.roblox.com/asset/?id=6034848747";
		["keyboard_arrow_up"] = "http://www.roblox.com/asset/?id=6034818379";
		["keyboard_backspace"] = "http://www.roblox.com/asset/?id=6034818381";
		["laptop_chromebook"] = "http://www.roblox.com/asset/?id=6034818364";
		["phone_iphone"] = "http://www.roblox.com/asset/?id=6034837811";
		["smartphone"] = "http://www.roblox.com/asset/?id=6034848731";
		["power_input"] = "http://www.roblox.com/asset/?id=6034837794";
		["videogame_asset"] = "http://www.roblox.com/asset/?id=6034848748";
		["desktop_windows"] = "http://www.roblox.com/asset/?id=6034789893";
		["keyboard_arrow_down"] = "http://www.roblox.com/asset/?id=6034818372";
		["laptop_mac"] = "http://www.roblox.com/asset/?id=6034837808";
		["laptop_windows"] = "http://www.roblox.com/asset/?id=6034837796";
		["keyboard_arrow_right"] = "http://www.roblox.com/asset/?id=6034818365";
		["cast_for_education"] = "http://www.roblox.com/asset/?id=6034789872";
		["keyboard_capslock"] = "http://www.roblox.com/asset/?id=6034818403";
		["toys"] = "http://www.roblox.com/asset/?id=6034848752";
		["tablet_android"] = "http://www.roblox.com/asset/?id=6034848734";
		["mouse"] = "http://www.roblox.com/asset/?id=6034837797";
		["phone_android"] = "http://www.roblox.com/asset/?id=6034837793";
		["keyboard_arrow_left"] = "http://www.roblox.com/asset/?id=6034818375";
		["security"] = "http://www.roblox.com/asset/?id=6034837802";
		["dry_cleaning"] = "http://www.roblox.com/asset/?id=6034754456";
		["bakery_dining"] = "http://www.roblox.com/asset/?id=6034767610";
		["place"] = "http://www.roblox.com/asset/?id=6034503372";
		["run_circle"] = "http://www.roblox.com/asset/?id=6034503367";
		["local_post_office"] = "http://www.roblox.com/asset/?id=6034513883";
		["takeout_dining"] = "http://www.roblox.com/asset/?id=6034467808";
		["nightlife"] = "http://www.roblox.com/asset/?id=6034510003";
		["design_services"] = "http://www.roblox.com/asset/?id=6034754453";
		["celebration"] = "http://www.roblox.com/asset/?id=6034767613";
		["near_me_disabled"] = "http://www.roblox.com/asset/?id=6034509988";
		["add_location_alt"] = "http://www.roblox.com/asset/?id=6034483678";
		["directions_run"] = "http://www.roblox.com/asset/?id=6034754445";
		["local_fire_department"] = "http://www.roblox.com/asset/?id=6034684949";
		["add_road"] = "http://www.roblox.com/asset/?id=6034483677";
		["my_location"] = "http://www.roblox.com/asset/?id=6034509987";
		["dinner_dining"] = "http://www.roblox.com/asset/?id=6034754457";
		["local_airport"] = "http://www.roblox.com/asset/?id=6034687951";
		["zoom_out_map"] = "http://www.roblox.com/asset/?id=6035229856";
		["pin_drop"] = "http://www.roblox.com/asset/?id=6034470807";
		["subway"] = "http://www.roblox.com/asset/?id=6034467790";
		["electric_moped"] = "http://www.roblox.com/asset/?id=6034744027";
		["restaurant_menu"] = "http://www.roblox.com/asset/?id=6034503378";
		["local_gas_station"] = "http://www.roblox.com/asset/?id=6034684935";
		["local_cafe"] = "http://www.roblox.com/asset/?id=6034687954";
		["theater_comedy"] = "http://www.roblox.com/asset/?id=6034467796";
		["directions_bus"] = "http://www.roblox.com/asset/?id=6034754434";
		["hail"] = "http://www.roblox.com/asset/?id=6034744033";
		["satellite"] = "http://www.roblox.com/asset/?id=6034503370";
		["local_phone"] = "http://www.roblox.com/asset/?id=6034513884";
		["electric_bike"] = "http://www.roblox.com/asset/?id=6034744032";
		["local_see"] = "http://www.roblox.com/asset/?id=6034513887";
		["transit_enterexit"] = "http://www.roblox.com/asset/?id=6034467805";
		["local_convenience_store"] = "http://www.roblox.com/asset/?id=6034687956";
		["local_offer"] = "http://www.roblox.com/asset/?id=6034513891";
		["electric_car"] = "http://www.roblox.com/asset/?id=6034744029";
		["beenhere"] = "http://www.roblox.com/asset/?id=6034483675";
		["miscellaneous_services"] = "http://www.roblox.com/asset/?id=6034509993";
		["maps_ugc"] = "http://www.roblox.com/asset/?id=6034509992";
		["moped"] = "http://www.roblox.com/asset/?id=6034509999";
		["medical_services"] = "http://www.roblox.com/asset/?id=6034510001";
		["money"] = "http://www.roblox.com/asset/?id=6034509997";
		["transfer_within_a_station"] = "http://www.roblox.com/asset/?id=6034467809";
		["electrical_services"] = "http://www.roblox.com/asset/?id=6034744038";
		["museum"] = "http://www.roblox.com/asset/?id=6034510005";
		["add_location"] = "http://www.roblox.com/asset/?id=6034483672";
		["layers"] = "http://www.roblox.com/asset/?id=6034687957";
		["handyman"] = "http://www.roblox.com/asset/?id=6034744057";
		["local_pharmacy"] = "http://www.roblox.com/asset/?id=6034513903";
		["electric_rickshaw"] = "http://www.roblox.com/asset/?id=6034744043";
		["alt_route"] = "http://www.roblox.com/asset/?id=6034483670";
		["no_transfer"] = "http://www.roblox.com/asset/?id=6034503363";
		["pedal_bike"] = "http://www.roblox.com/asset/?id=6034503374";
		["directions_transit"] = "http://www.roblox.com/asset/?id=6034754436";
		["railway_alert"] = "http://www.roblox.com/asset/?id=6034470823";
		["local_police"] = "http://www.roblox.com/asset/?id=6034513895";
		["directions_car"] = "http://www.roblox.com/asset/?id=6034754441";
		["category"] = "http://www.roblox.com/asset/?id=6034767621";
		["attractions"] = "http://www.roblox.com/asset/?id=6034767620";
		["person_pin_circle"] = "http://www.roblox.com/asset/?id=6034503375";
		["cleaning_services"] = "http://www.roblox.com/asset/?id=6034767619";
		["terrain"] = "http://www.roblox.com/asset/?id=6034467794";
		["no_meals"] = "http://www.roblox.com/asset/?id=6034510024";
		["train"] = "http://www.roblox.com/asset/?id=6034467803";
		["delivery_dining"] = "http://www.roblox.com/asset/?id=6034767644";
		["pest_control"] = "http://www.roblox.com/asset/?id=6034470809";
		["directions"] = "http://www.roblox.com/asset/?id=6034754449";
		["atm"] = "http://www.roblox.com/asset/?id=6034767614";
		["rate_review"] = "http://www.roblox.com/asset/?id=6034503385";
		["local_bar"] = "http://www.roblox.com/asset/?id=6034687950";
		["local_drink"] = "http://www.roblox.com/asset/?id=6034687965";
		["directions_railway"] = "http://www.roblox.com/asset/?id=6034754433";
		["person_pin"] = "http://www.roblox.com/asset/?id=6034503364";
		["ev_station"] = "http://www.roblox.com/asset/?id=6034744037";
		["home_repair_service"] = "http://www.roblox.com/asset/?id=6034744064";
		["bus_alert"] = "http://www.roblox.com/asset/?id=6034767618";
		["agriculture"] = "http://www.roblox.com/asset/?id=6034483674";
		["volunteer_activism"] = "http://www.roblox.com/asset/?id=6034467799";
		["breakfast_dining"] = "http://www.roblox.com/asset/?id=6034483671";
		["layers_clear"] = "http://www.roblox.com/asset/?id=6034687975";
		["plumbing"] = "http://www.roblox.com/asset/?id=6034470800";
		["taxi_alert"] = "http://www.roblox.com/asset/?id=6034467792";
		["add_business"] = "http://www.roblox.com/asset/?id=6034483666";
		["badge"] = "http://www.roblox.com/asset/?id=6034767607";
		["edit_attributes"] = "http://www.roblox.com/asset/?id=6034754443";
		["directions_walk"] = "http://www.roblox.com/asset/?id=6034754448";
		["local_play"] = "http://www.roblox.com/asset/?id=6034513889";
		["bike_scooter"] = "http://www.roblox.com/asset/?id=6034483669";
		["two_wheeler"] = "http://www.roblox.com/asset/?id=6034467795";
		["local_florist"] = "http://www.roblox.com/asset/?id=6034684940";
		["local_hotel"] = "http://www.roblox.com/asset/?id=6034684939";
		["no_meals_ouline"] = "http://www.roblox.com/asset/?id=6034510025";
		["festival"] = "http://www.roblox.com/asset/?id=6034744031";
		["local_shipping"] = "http://www.roblox.com/asset/?id=6034684926";
		["directions_boat"] = "http://www.roblox.com/asset/?id=6034754442";
		["wrong_location"] = "http://www.roblox.com/asset/?id=6034467801";
		["restaurant"] = "http://www.roblox.com/asset/?id=6034503366";
		["directions_subway"] = "http://www.roblox.com/asset/?id=6034754440";
		["not_listed_location"] = "http://www.roblox.com/asset/?id=6034503380";
		["electric_scooter"] = "http://www.roblox.com/asset/?id=6034744041";
		["ramen_dining"] = "http://www.roblox.com/asset/?id=6034503377";
		["edit_road"] = "http://www.roblox.com/asset/?id=6034744035";
		["local_printshop"] = "http://www.roblox.com/asset/?id=6034513897";
		["map"] = "http://www.roblox.com/asset/?id=6034684930";
		["car_rental"] = "http://www.roblox.com/asset/?id=6034767641";
		["multiple_stop"] = "http://www.roblox.com/asset/?id=6034510026";
		["brunch_dining"] = "http://www.roblox.com/asset/?id=6034767611";
		["local_laundry_service"] = "http://www.roblox.com/asset/?id=6034684943";
		["set_meal"] = "http://www.roblox.com/asset/?id=6034503368";
		["local_car_wash"] = "http://www.roblox.com/asset/?id=6034687976";
		["pest_control_rodent"] = "http://www.roblox.com/asset/?id=6034470803";
		["local_pizza"] = "http://www.roblox.com/asset/?id=6034513885";
		["local_grocery_store"] = "http://www.roblox.com/asset/?id=6034684933";
		["traffic"] = "http://www.roblox.com/asset/?id=6034467797";
		["departure_board"] = "http://www.roblox.com/asset/?id=6034767615";
		["icecream"] = "http://www.roblox.com/asset/?id=6034687967";
		["navigation"] = "http://www.roblox.com/asset/?id=6034509984";
		["near_me"] = "http://www.roblox.com/asset/?id=6034509996";
		["fastfood"] = "http://www.roblox.com/asset/?id=6034744034";
		["local_library"] = "http://www.roblox.com/asset/?id=6034684931";
		["local_activity"] = "http://www.roblox.com/asset/?id=6034687955";
		["local_hospital"] = "http://www.roblox.com/asset/?id=6034684956";
		["menu_book"] = "http://www.roblox.com/asset/?id=6034509994";
		["directions_bike"] = "http://www.roblox.com/asset/?id=6034754459";
		["store_mall_directory"] = "http://www.roblox.com/asset/?id=6034470811";
		["trip_origin"] = "http://www.roblox.com/asset/?id=6034467804";
		["tram"] = "http://www.roblox.com/asset/?id=6034467806";
		["edit_location"] = "http://www.roblox.com/asset/?id=6034754439";
		["streetview"] = "http://www.roblox.com/asset/?id=6034470805";
		["hvac"] = "http://www.roblox.com/asset/?id=6034687960";
		["lunch_dining"] = "http://www.roblox.com/asset/?id=6034684928";
		["car_repair"] = "http://www.roblox.com/asset/?id=6034767617";
		["compass_calibration"] = "http://www.roblox.com/asset/?id=6034767623";
		["360"] = "http://www.roblox.com/asset/?id=6034767608";
		["flight"] = "http://www.roblox.com/asset/?id=6034744030";
		["local_mall"] = "http://www.roblox.com/asset/?id=6034684934";
		["hotel"] = "http://www.roblox.com/asset/?id=6034687977";
		["local_parking"] = "http://www.roblox.com/asset/?id=6034513893";
		["hardware"] = "http://www.roblox.com/asset/?id=6034744036";
		["local_dining"] = "http://www.roblox.com/asset/?id=6034687963";
		["park"] = "http://www.roblox.com/asset/?id=6034503369";
		["location_pin"] = "http://www.roblox.com/asset/?id=6034684937";
		["local_movies"] = "http://www.roblox.com/asset/?id=6034684936";
		["local_atm"] = "http://www.roblox.com/asset/?id=6034687953";
		["local_taxi"] = "http://www.roblox.com/asset/?id=6034684927";
		["brightness_low"] = "http://www.roblox.com/asset/?id=6034989542";
		["screen_lock_landscape"] = "http://www.roblox.com/asset/?id=6034996700";
		["graphic_eq"] = "http://www.roblox.com/asset/?id=6034989551";
		["screen_lock_rotation"] = "http://www.roblox.com/asset/?id=6034996710";
		["signal_cellular_4_bar"] = "http://www.roblox.com/asset/?id=6035030076";
		["airplanemode_inactive"] = "http://www.roblox.com/asset/?id=6034983848";
		["signal_wifi_0_bar"] = "http://www.roblox.com/asset/?id=6035030067";
		["battery_full"] = "http://www.roblox.com/asset/?id=6034983854";
		["gps_fixed"] = "http://www.roblox.com/asset/?id=6034989550";
		["brightness_high"] = "http://www.roblox.com/asset/?id=6034989541";
		["ad_units"] = "http://www.roblox.com/asset/?id=6034983845";
		["signal_cellular_alt"] = "http://www.roblox.com/asset/?id=6035030079";
		["bluetooth_connected"] = "http://www.roblox.com/asset/?id=6034983855";
		["wifi_tethering"] = "http://www.roblox.com/asset/?id=6035039430";
		["dvr"] = "http://www.roblox.com/asset/?id=6034989561";
		["screen_search_desktop"] = "http://www.roblox.com/asset/?id=6034996711";
		["network_wifi"] = "http://www.roblox.com/asset/?id=6034996712";
		["access_alarms"] = "http://www.roblox.com/asset/?id=6034983853";
		["nfc"] = "http://www.roblox.com/asset/?id=6034996698";
		["location_disabled"] = "http://www.roblox.com/asset/?id=6034996694";
		["signal_wifi_4_bar"] = "http://www.roblox.com/asset/?id=6035030077";
		["access_time"] = "http://www.roblox.com/asset/?id=6034983856";
		["mobile_off"] = "http://www.roblox.com/asset/?id=6034996702";
		["battery_unknown"] = "http://www.roblox.com/asset/?id=6034983842";
		["signal_cellular_null"] = "http://www.roblox.com/asset/?id=6035030075";
		["bluetooth_disabled"] = "http://www.roblox.com/asset/?id=6034989562";
		["developer_mode"] = "http://www.roblox.com/asset/?id=6034989549";
		["network_cell"] = "http://www.roblox.com/asset/?id=6034996709";
		["sd_storage"] = "http://www.roblox.com/asset/?id=6034996719";
		["signal_cellular_no_sim"] = "http://www.roblox.com/asset/?id=6035030078";
		["devices"] = "http://www.roblox.com/asset/?id=6034989540";
		["screen_rotation"] = "http://www.roblox.com/asset/?id=6034996701";
		["device_thermostat"] = "http://www.roblox.com/asset/?id=6034989544";
		["signal_wifi_off"] = "http://www.roblox.com/asset/?id=6035030074";
		["widgets"] = "http://www.roblox.com/asset/?id=6035039429";
		["bluetooth"] = "http://www.roblox.com/asset/?id=6034983880";
		["battery_charging_full"] = "http://www.roblox.com/asset/?id=6034983849";
		["mobile_friendly"] = "http://www.roblox.com/asset/?id=6034996699";
		["signal_cellular_0_bar"] = "http://www.roblox.com/asset/?id=6035030072";
		["storage"] = "http://www.roblox.com/asset/?id=6035030083";
		["send_to_mobile"] = "http://www.roblox.com/asset/?id=6034996697";
		["location_searching"] = "http://www.roblox.com/asset/?id=6034996695";
		["brightness_auto"] = "http://www.roblox.com/asset/?id=6034989545";
		["wifi_lock"] = "http://www.roblox.com/asset/?id=6035039428";
		["gps_not_fixed"] = "http://www.roblox.com/asset/?id=6034989547";
		["access_alarm"] = "http://www.roblox.com/asset/?id=6034983844";
		["battery_alert"] = "http://www.roblox.com/asset/?id=6034983843";
		["signal_cellular_off"] = "http://www.roblox.com/asset/?id=6035030084";
		["signal_cellular_connected_no_internet_4"] = "http://www.roblox.com/asset/?id=6035229858";
		["gps_off"] = "http://www.roblox.com/asset/?id=6034989548";
		["add_alarm"] = "http://www.roblox.com/asset/?id=6034983850";
		["brightness_medium"] = "http://www.roblox.com/asset/?id=6034989543";
		["usb"] = "http://www.roblox.com/asset/?id=6035030080";
		["airplanemode_active"] = "http://www.roblox.com/asset/?id=6034983864";
		["reset_tv"] = "http://www.roblox.com/asset/?id=6034996696";
		["wallpaper"] = "http://www.roblox.com/asset/?id=6035030102";
		["settings_system_daydream"] = "http://www.roblox.com/asset/?id=6035030081";
		["bluetooth_searching"] = "http://www.roblox.com/asset/?id=6034989553";
		["add_to_home_screen"] = "http://www.roblox.com/asset/?id=6034983858";
		["screen_lock_portrait"] = "http://www.roblox.com/asset/?id=6034996706";
		["data_usage"] = "http://www.roblox.com/asset/?id=6034989568";
		["_auto_delete"] = "http://www.roblox.com/asset/?id=6031071068";
		["_error"] = "http://www.roblox.com/asset/?id=6031071057";
		["_notification_important"] = "http://www.roblox.com/asset/?id=6031071056";
		["_add_alert"] = "http://www.roblox.com/asset/?id=6031071067";
		["_warning"] = "http://www.roblox.com/asset/?id=6031071053";
		["_error_outline"] = "http://www.roblox.com/asset/?id=6031071050";
		["check_box_outline_blank"] = "http://www.roblox.com/asset/?id=6031068420";
		["toggle_off"] = "http://www.roblox.com/asset/?id=6031068429";
		["indeterminate_check_box"] = "http://www.roblox.com/asset/?id=6031068445";
		["radio_button_checked"] = "http://www.roblox.com/asset/?id=6031068426";
		["toggle_on"] = "http://www.roblox.com/asset/?id=6031068430";
		["check_box"] = "http://www.roblox.com/asset/?id=6031068421";
		["radio_button_unchecked"] = "http://www.roblox.com/asset/?id=6031068433";
		["star"] = "http://www.roblox.com/asset/?id=6031068423";
		["star_border"] = "http://www.roblox.com/asset/?id=6031068425";
		["star_half"] = "http://www.roblox.com/asset/?id=6031068427";
		["star_outline"] = "http://www.roblox.com/asset/?id=6031068428";
		["multiline_chart"] = "http://www.roblox.com/asset/?id=6034941721";
		["pie_chart"] = "http://www.roblox.com/asset/?id=6034973076";
		["format_line_spacing"] = "http://www.roblox.com/asset/?id=6034910905";
		["format_align_left"] = "http://www.roblox.com/asset/?id=6034900727";
		["linear_scale"] = "http://www.roblox.com/asset/?id=6034941707";
		["insert_photo"] = "http://www.roblox.com/asset/?id=6034941703";
		["scatter_plot"] = "http://www.roblox.com/asset/?id=6034973094";
		["post_add"] = "http://www.roblox.com/asset/?id=6034973083";
		["format_textdirection_r_to_l"] = "http://www.roblox.com/asset/?id=6034925623";
		["format_size"] = "http://www.roblox.com/asset/?id=6034910908";
		["format_color_fill"] = "http://www.roblox.com/asset/?id=6034910903";
		["format_paint"] = "http://www.roblox.com/asset/?id=6034925618";
		["format_underlined"] = "http://www.roblox.com/asset/?id=6034925627";
		["format_shapes"] = "http://www.roblox.com/asset/?id=6034910909";
		["title"] = "http://www.roblox.com/asset/?id=6034934042";
		["highlight"] = "http://www.roblox.com/asset/?id=6034925617";
		["bar_chart"] = "http://www.roblox.com/asset/?id=6034898096";
		["format_indent_increase"] = "http://www.roblox.com/asset/?id=6034900724";
		["merge_type"] = "http://www.roblox.com/asset/?id=6034941705";
		["bubble_chart"] = "http://www.roblox.com/asset/?id=6034925612";
		["publish"] = "http://www.roblox.com/asset/?id=6034973085";
		["format_indent_decrease"] = "http://www.roblox.com/asset/?id=6034900733";
		["margin"] = "http://www.roblox.com/asset/?id=6034941701";
		["table_rows"] = "http://www.roblox.com/asset/?id=6034934025";
		["stacked_line_chart"] = "http://www.roblox.com/asset/?id=6034934039";
		["border_clear"] = "http://www.roblox.com/asset/?id=6034898135";
		["border_color"] = "http://www.roblox.com/asset/?id=6034898100";
		["border_inner"] = "http://www.roblox.com/asset/?id=6034898131";
		["insert_chart"] = "http://www.roblox.com/asset/?id=6034925628";
		["border_top"] = "http://www.roblox.com/asset/?id=6034900726";
		["padding"] = "http://www.roblox.com/asset/?id=6034973078";
		["border_vertical"] = "http://www.roblox.com/asset/?id=6034900725";
		["score"] = "http://www.roblox.com/asset/?id=6034934041";
		["border_right"] = "http://www.roblox.com/asset/?id=6034898120";
		["add_chart"] = "http://www.roblox.com/asset/?id=6034898093";
		["space_bar"] = "http://www.roblox.com/asset/?id=6034934037";
		["border_outer"] = "http://www.roblox.com/asset/?id=6034898104";
		["mode_comment"] = "http://www.roblox.com/asset/?id=6034941700";
		["attach_money"] = "http://www.roblox.com/asset/?id=6034898098";
		["drag_handle"] = "http://www.roblox.com/asset/?id=6034910907";
		["format_align_right"] = "http://www.roblox.com/asset/?id=6034900723";
		["pie_chart_outlined"] = "http://www.roblox.com/asset/?id=6034973077";
		["horizontal_rule"] = "http://www.roblox.com/asset/?id=6034925610";
		["border_all"] = "http://www.roblox.com/asset/?id=6034898101";
		["border_style"] = "http://www.roblox.com/asset/?id=6034898097";
		["insert_comment"] = "http://www.roblox.com/asset/?id=6034925609";
		["vertical_align_top"] = "http://www.roblox.com/asset/?id=6034973080";
		["vertical_align_center"] = "http://www.roblox.com/asset/?id=6034934051";
		["format_color_text"] = "http://www.roblox.com/asset/?id=6034910910";
		["format_quote"] = "http://www.roblox.com/asset/?id=6034925629";
		["height"] = "http://www.roblox.com/asset/?id=6034925613";
		["add_comment"] = "http://www.roblox.com/asset/?id=6034898128";
		["format_strikethrough"] = "http://www.roblox.com/asset/?id=6034910904";
		["strikethrough_s"] = "http://www.roblox.com/asset/?id=6034934030";
		["border_left"] = "http://www.roblox.com/asset/?id=6034898099";
		["format_list_bulleted"] = "http://www.roblox.com/asset/?id=6034925620";
		["format_italic"] = "http://www.roblox.com/asset/?id=6034910912";
		["format_list_numbered"] = "http://www.roblox.com/asset/?id=6034925622";
		["attach_file"] = "http://www.roblox.com/asset/?id=6034898102";
		["wrap_text"] = "http://www.roblox.com/asset/?id=6034973118";
		["insert_invitation"] = "http://www.roblox.com/asset/?id=6034973091";
		["format_list_numbered_rtl"] = "http://www.roblox.com/asset/?id=6034910906";
		["border_horizontal"] = "http://www.roblox.com/asset/?id=6034898105";
		["format_align_center"] = "http://www.roblox.com/asset/?id=6034900718";
		["format_textdirection_l_to_r"] = "http://www.roblox.com/asset/?id=6034925619";
		["show_chart"] = "http://www.roblox.com/asset/?id=6034934032";
		["insert_chart_outlined"] = "http://www.roblox.com/asset/?id=6034925606";
		["vertical_align_bottom"] = "http://www.roblox.com/asset/?id=6034934023";
		["subscript"] = "http://www.roblox.com/asset/?id=6034934059";
		["format_align_justify"] = "http://www.roblox.com/asset/?id=6034900721";
		["format_clear"] = "http://www.roblox.com/asset/?id=6034910902";
		["notes"] = "http://www.roblox.com/asset/?id=6034973084";
		["insert_drive_file"] = "http://www.roblox.com/asset/?id=6034941697";
		["functions"] = "http://www.roblox.com/asset/?id=6034925614";
		["insert_emoticon"] = "http://www.roblox.com/asset/?id=6034973079";
		["insert_link"] = "http://www.roblox.com/asset/?id=6034973074";
		["format_color_reset"] = "http://www.roblox.com/asset/?id=6034900743";
		["monetization_on"] = "http://www.roblox.com/asset/?id=6034973115";
		["short_text"] = "http://www.roblox.com/asset/?id=6034934035";
		["mode_edit"] = "http://www.roblox.com/asset/?id=6034941708";
		["superscript"] = "http://www.roblox.com/asset/?id=6034934034";
		["table_chart"] = "http://www.roblox.com/asset/?id=6034973081";
		["format_bold"] = "http://www.roblox.com/asset/?id=6034900732";
		["money_off"] = "http://www.roblox.com/asset/?id=6034973088";
		["border_bottom"] = "http://www.roblox.com/asset/?id=6034898094";
		["text_fields"] = "http://www.roblox.com/asset/?id=6034934040";
		["note"] = "http://www.roblox.com/asset/?id=6026663734";
		["shuffle"] = "http://www.roblox.com/asset/?id=6026667003";
		["library_books"] = "http://www.roblox.com/asset/?id=6026660085";
		["library_music"] = "http://www.roblox.com/asset/?id=6026660075";
		["surround_sound"] = "http://www.roblox.com/asset/?id=6026671209";
		["forward_30"] = "http://www.roblox.com/asset/?id=6026660088";
		["music_video"] = "http://www.roblox.com/asset/?id=6026663704";
		["videocam_off"] = "http://www.roblox.com/asset/?id=6026671212";
		["control_camera"] = "http://www.roblox.com/asset/?id=6026647916";
		["explicit"] = "http://www.roblox.com/asset/?id=6026647913";
		["3k_plus"] = "http://www.roblox.com/asset/?id=6026681598";
		["fiber_pin"] = "http://www.roblox.com/asset/?id=6026660064";
		["skip_previous"] = "http://www.roblox.com/asset/?id=6026667011";
		["pause_circle_filled"] = "http://www.roblox.com/asset/?id=6026663718";
		["video_settings"] = "http://www.roblox.com/asset/?id=6026671211";
		["movie"] = "http://www.roblox.com/asset/?id=6026660081";
		["add_to_queue"] = "http://www.roblox.com/asset/?id=6026647903";
		["6k"] = "http://www.roblox.com/asset/?id=6026681579";
		["web_asset"] = "http://www.roblox.com/asset/?id=6026671239";
		["play_circle_outline"] = "http://www.roblox.com/asset/?id=6026663726";
		["volume_off"] = "http://www.roblox.com/asset/?id=6026671224";
		["mic_off"] = "http://www.roblox.com/asset/?id=6026660076";
		["featured_play_list"] = "http://www.roblox.com/asset/?id=6026647932";
		["pause_circle_outline"] = "http://www.roblox.com/asset/?id=6026663701";
		["slow_motion_video"] = "http://www.roblox.com/asset/?id=6026681583";
		["7k"] = "http://www.roblox.com/asset/?id=6026681584";
		["playlist_add"] = "http://www.roblox.com/asset/?id=6026663728";
		["fiber_smart_record"] = "http://www.roblox.com/asset/?id=6026660080";
		["8k"] = "http://www.roblox.com/asset/?id=6026643014";
		["hd"] = "http://www.roblox.com/asset/?id=6026660065";
		["repeat_one_on"] = "http://www.roblox.com/asset/?id=6026666992";
		["recent_actors"] = "http://www.roblox.com/asset/?id=6026663773";
		["fiber_new"] = "http://www.roblox.com/asset/?id=6026647930";
		["fiber_dvr"] = "http://www.roblox.com/asset/?id=6026647912";
		["hearing_disabled"] = "http://www.roblox.com/asset/?id=6026660068";
		["forward_10"] = "http://www.roblox.com/asset/?id=6026660062";
		["4k_plus"] = "http://www.roblox.com/asset/?id=6026643005";
		["repeat_one"] = "http://www.roblox.com/asset/?id=6026681590";
		["equalizer"] = "http://www.roblox.com/asset/?id=6026647906";
		["stop"] = "http://www.roblox.com/asset/?id=6026681576";
		["2k"] = "http://www.roblox.com/asset/?id=6026643032";
		["playlist_add_check"] = "http://www.roblox.com/asset/?id=6026663727";
		["not_interested"] = "http://www.roblox.com/asset/?id=6026663743";
		["videocam"] = "http://www.roblox.com/asset/?id=6026671213";
		["sort_by_alpha"] = "http://www.roblox.com/asset/?id=6026667009";
		["library_add"] = "http://www.roblox.com/asset/?id=6026660063";
		["stop_circle"] = "http://www.roblox.com/asset/?id=6026681577";
		["pause"] = "http://www.roblox.com/asset/?id=6026663719";
		["new_releases"] = "http://www.roblox.com/asset/?id=6026663730";
		["album"] = "http://www.roblox.com/asset/?id=6026647905";
		["sd"] = "http://www.roblox.com/asset/?id=6026681582";
		["volume_up"] = "http://www.roblox.com/asset/?id=6026671215";
		["replay_5"] = "http://www.roblox.com/asset/?id=6026666993";
		["high_quality"] = "http://www.roblox.com/asset/?id=6026660059";
		["shuffle_on"] = "http://www.roblox.com/asset/?id=6026666996";
		["play_arrow"] = "http://www.roblox.com/asset/?id=6026663699";
		["snooze"] = "http://www.roblox.com/asset/?id=6026667006";
		["closed_caption_disabled"] = "http://www.roblox.com/asset/?id=6026647900";
		["subscriptions"] = "http://www.roblox.com/asset/?id=6026671207";
		["skip_next"] = "http://www.roblox.com/asset/?id=6026667005";
		["branding_watermark"] = "http://www.roblox.com/asset/?id=6026647911";
		["speed"] = "http://www.roblox.com/asset/?id=6026681578";
		["art_track"] = "http://www.roblox.com/asset/?id=6026647908";
		["3k"] = "http://www.roblox.com/asset/?id=6026681574";
		["4k"] = "http://www.roblox.com/asset/?id=6026643017";
		["volume_mute"] = "http://www.roblox.com/asset/?id=6026671214";
		["playlist_play"] = "http://www.roblox.com/asset/?id=6026663723";
		["remove_from_queue"] = "http://www.roblox.com/asset/?id=6026663771";
		["fast_forward"] = "http://www.roblox.com/asset/?id=6026647902";
		["play_disabled"] = "http://www.roblox.com/asset/?id=6026663702";
		["fast_rewind"] = "http://www.roblox.com/asset/?id=6026647942";
		["5k"] = "http://www.roblox.com/asset/?id=6026681575";
		["replay_10"] = "http://www.roblox.com/asset/?id=6026667007";
		["video_library"] = "http://www.roblox.com/asset/?id=6026671208";
		["loop"] = "http://www.roblox.com/asset/?id=6026660087";
		["replay_circle_filled"] = "http://www.roblox.com/asset/?id=6026667002";
		["5g"] = "http://www.roblox.com/asset/?id=6026643007";
		["library_add_check"] = "http://www.roblox.com/asset/?id=6026660083";
		["repeat"] = "http://www.roblox.com/asset/?id=6026666998";
		["queue_play_next"] = "http://www.roblox.com/asset/?id=6026663700";
		["forward_5"] = "http://www.roblox.com/asset/?id=6026660067";
		["web"] = "http://www.roblox.com/asset/?id=6026671234";
		["mic_none"] = "http://www.roblox.com/asset/?id=6026660066";
		["queue"] = "http://www.roblox.com/asset/?id=6026663724";
		["closed_caption_off"] = "http://www.roblox.com/asset/?id=6026647943";
		["hearing"] = "http://www.roblox.com/asset/?id=6026660060";
		["queue_music"] = "http://www.roblox.com/asset/?id=6026663725";
		["airplay"] = "http://www.roblox.com/asset/?id=6026647929";
		["9k"] = "http://www.roblox.com/asset/?id=6026643013";
		["video_label"] = "http://www.roblox.com/asset/?id=6026671204";
		["8k_plus"] = "http://www.roblox.com/asset/?id=6026643003";
		["play_circle_filled"] = "http://www.roblox.com/asset/?id=6026663705";
		["1k"] = "http://www.roblox.com/asset/?id=6026643002";
		["fiber_manual_record"] = "http://www.roblox.com/asset/?id=6026647909";
		["closed_caption"] = "http://www.roblox.com/asset/?id=6026647896";
		["subtitles"] = "http://www.roblox.com/asset/?id=6026671203";
		["featured_video"] = "http://www.roblox.com/asset/?id=6026647910";
		["replay_30"] = "http://www.roblox.com/asset/?id=6026667010";
		["10k"] = "http://www.roblox.com/asset/?id=6026643035";
		["5k_plus"] = "http://www.roblox.com/asset/?id=6026643028";
		["6k_plus"] = "http://www.roblox.com/asset/?id=6026643019";
		["replay"] = "http://www.roblox.com/asset/?id=6026666999";
		["repeat_on"] = "http://www.roblox.com/asset/?id=6026666994";
		["1k_plus"] = "http://www.roblox.com/asset/?id=6026681580";
		["2k_plus"] = "http://www.roblox.com/asset/?id=6026681588";
		["games"] = "http://www.roblox.com/asset/?id=6026660074";
		["volume_down"] = "http://www.roblox.com/asset/?id=6026671206";
		["mic"] = "http://www.roblox.com/asset/?id=6026660078";
		["call_to_action"] = "http://www.roblox.com/asset/?id=6026647898";
		["7k_plus"] = "http://www.roblox.com/asset/?id=6026643012";
		["av_timer"] = "http://www.roblox.com/asset/?id=6026647934";
		["9k_plus"] = "http://www.roblox.com/asset/?id=6026681585";
		["radio"] = "http://www.roblox.com/asset/?id=6026663698";
		["10mp"] = "http://www.roblox.com/asset/?id=6031328149";
		["20mp"] = "http://www.roblox.com/asset/?id=6031488940";
		["wb_twighlight"] = "http://www.roblox.com/asset/?id=6034412760";
		["movie_creation"] = "http://www.roblox.com/asset/?id=6034323681";
		["crop_portrait"] = "http://www.roblox.com/asset/?id=6031630198";
		["filter_5"] = "http://www.roblox.com/asset/?id=6031597518";
		["broken_image"] = "http://www.roblox.com/asset/?id=6031471480";
		["flip_camera_android"] = "http://www.roblox.com/asset/?id=6034333280";
		["flip_camera_ios"] = "http://www.roblox.com/asset/?id=6034333267";
		["circle"] = "http://www.roblox.com/asset/?id=6031625146";
		["photo_camera_front"] = "http://www.roblox.com/asset/?id=6031771000";
		["assistant"] = "http://www.roblox.com/asset/?id=6031360356";
		["face_retouching_natural"] = "http://www.roblox.com/asset/?id=6034333274";
		["palette"] = "http://www.roblox.com/asset/?id=6034316009";
		["nature_people"] = "http://www.roblox.com/asset/?id=6034323711";
		["14mp"] = "http://www.roblox.com/asset/?id=6031328161";
		["gradient"] = "http://www.roblox.com/asset/?id=6034333261";
		["filter_4"] = "http://www.roblox.com/asset/?id=6031597512";
		["panorama_wide_angle_select"] = "http://www.roblox.com/asset/?id=6031770990";
		["photo"] = "http://www.roblox.com/asset/?id=6031770993";
		["grid_off"] = "http://www.roblox.com/asset/?id=6034333286";
		["leak_add"] = "http://www.roblox.com/asset/?id=6034407074";
		["landscape"] = "http://www.roblox.com/asset/?id=6034407069";
		["exposure_plus_1"] = "http://www.roblox.com/asset/?id=6034328970";
		["slideshow"] = "http://www.roblox.com/asset/?id=6031754546";
		["camera_alt"] = "http://www.roblox.com/asset/?id=6031572307";
		["audiotrack"] = "http://www.roblox.com/asset/?id=6031471489";
		["filter_none"] = "http://www.roblox.com/asset/?id=6031600815";
		["blur_off"] = "http://www.roblox.com/asset/?id=6031371055";
		["crop_16_9"] = "http://www.roblox.com/asset/?id=6031630205";
		["blur_on"] = "http://www.roblox.com/asset/?id=6031371068";
		["brightness_4"] = "http://www.roblox.com/asset/?id=6031471483";
		["details"] = "http://www.roblox.com/asset/?id=6034328968";
		["panorama_horizontal"] = "http://www.roblox.com/asset/?id=6034315966";
		["camera_rear"] = "http://www.roblox.com/asset/?id=6031572316";
		["hdr_weak"] = "http://www.roblox.com/asset/?id=6034407083";
		["collections"] = "http://www.roblox.com/asset/?id=6031625145";
		["hdr_enhanced_select"] = "http://www.roblox.com/asset/?id=6034333281";
		["adjust"] = "http://www.roblox.com/asset/?id=6031339048";
		["burst_mode"] = "http://www.roblox.com/asset/?id=6031572306";
		["nature"] = "http://www.roblox.com/asset/?id=6034323695";
		["brightness_6"] = "http://www.roblox.com/asset/?id=6031572309";
		["19mp"] = "http://www.roblox.com/asset/?id=6031339054";
		["grain"] = "http://www.roblox.com/asset/?id=6034333288";
		["receipt_long"] = "http://www.roblox.com/asset/?id=6031763428";
		["photo_filter"] = "http://www.roblox.com/asset/?id=6031770992";
		["edit"] = "http://www.roblox.com/asset/?id=6034328955";
		["healing"] = "http://www.roblox.com/asset/?id=6034407071";
		["exposure_neg_1"] = "http://www.roblox.com/asset/?id=6034328957";
		["exposure"] = "http://www.roblox.com/asset/?id=6034328962";
		["wb_shade"] = "http://www.roblox.com/asset/?id=6034315974";
		["compare"] = "http://www.roblox.com/asset/?id=6031625151";
		["cases"] = "http://www.roblox.com/asset/?id=6031572324";
		["timer_3"] = "http://www.roblox.com/asset/?id=6031754540";
		["exposure_plus_2"] = "http://www.roblox.com/asset/?id=6034328961";
		["12mp"] = "http://www.roblox.com/asset/?id=6031328140";
		["22mp"] = "http://www.roblox.com/asset/?id=6031360353";
		["timer_off"] = "http://www.roblox.com/asset/?id=6031734881";
		["auto_stories"] = "http://www.roblox.com/asset/?id=6031360360";
		["rotate_left"] = "http://www.roblox.com/asset/?id=6031763427";
		["wb_iridescent"] = "http://www.roblox.com/asset/?id=6034315972";
		["shutter_speed"] = "http://www.roblox.com/asset/?id=6031763443";
		["switch_video"] = "http://www.roblox.com/asset/?id=6031754536";
		["23mp"] = "http://www.roblox.com/asset/?id=6031339045";
		["euro"] = "http://www.roblox.com/asset/?id=6034328963";
		["15mp"] = "http://www.roblox.com/asset/?id=6031328158";
		["filter_center_focus"] = "http://www.roblox.com/asset/?id=6031600817";
		["photo_library"] = "http://www.roblox.com/asset/?id=6031770998";
		["mp"] = "http://www.roblox.com/asset/?id=6034323674";
		["looks_4"] = "http://www.roblox.com/asset/?id=6034407089";
		["filter_2"] = "http://www.roblox.com/asset/?id=6031597521";
		["crop_3_2"] = "http://www.roblox.com/asset/?id=6034328956";
		["auto_fix_normal"] = "http://www.roblox.com/asset/?id=6031371074";
		["auto_fix_off"] = "http://www.roblox.com/asset/?id=6031360381";
		["wb_auto"] = "http://www.roblox.com/asset/?id=6031734875";
		["switch_camera"] = "http://www.roblox.com/asset/?id=6031754550";
		["filter_vintage"] = "http://www.roblox.com/asset/?id=6031600811";
		["photo_size_select_small"] = "http://www.roblox.com/asset/?id=6031763457";
		["blur_linear"] = "http://www.roblox.com/asset/?id=6031488930";
		["hdr_on"] = "http://www.roblox.com/asset/?id=6034333279";
		["tag_faces"] = "http://www.roblox.com/asset/?id=6031754560";
		["21mp"] = "http://www.roblox.com/asset/?id=6031339065";
		["camera"] = "http://www.roblox.com/asset/?id=6031572312";
		["image_aspect_ratio"] = "http://www.roblox.com/asset/?id=6034407073";
		["filter_b_and_w"] = "http://www.roblox.com/asset/?id=6031600824";
		["crop_landscape"] = "http://www.roblox.com/asset/?id=6031630202";
		["13mp"] = "http://www.roblox.com/asset/?id=6031328137";
		["grid_on"] = "http://www.roblox.com/asset/?id=6034333276";
		["motion_photos_pause"] = "http://www.roblox.com/asset/?id=6034323668";
		["filter_6"] = "http://www.roblox.com/asset/?id=6031597524";
		["linked_camera"] = "http://www.roblox.com/asset/?id=6034407082";
		["panorama_fish_eye"] = "http://www.roblox.com/asset/?id=6034315969";
		["panorama"] = "http://www.roblox.com/asset/?id=6034315955";
		["color_lens"] = "http://www.roblox.com/asset/?id=6031625148";
		["lens"] = "http://www.roblox.com/asset/?id=6034407081";
		["crop_din"] = "http://www.roblox.com/asset/?id=6031630208";
		["exposure_neg_2"] = "http://www.roblox.com/asset/?id=6034328973";
		["mic_external_off"] = "http://www.roblox.com/asset/?id=6034323672";
		["crop_free"] = "http://www.roblox.com/asset/?id=6031630212";
		["crop_original"] = "http://www.roblox.com/asset/?id=6031630204";
		["panorama_photosphere_select"] = "http://www.roblox.com/asset/?id=6034315975";
		["photo_size_select_actual"] = "http://www.roblox.com/asset/?id=6031771012";
		["leak_remove"] = "http://www.roblox.com/asset/?id=6034407080";
		["collections_bookmark"] = "http://www.roblox.com/asset/?id=6034328965";
		["straighten"] = "http://www.roblox.com/asset/?id=6031754545";
		["timelapse"] = "http://www.roblox.com/asset/?id=6031754541";
		["picture_as_pdf"] = "http://www.roblox.com/asset/?id=6031763425";
		["crop_rotate"] = "http://www.roblox.com/asset/?id=6031630203";
		["control_point_duplicate"] = "http://www.roblox.com/asset/?id=6034328959";
		["photo_camera_back"] = "http://www.roblox.com/asset/?id=6031771007";
		["looks_3"] = "http://www.roblox.com/asset/?id=6034407088";
		["motion_photos_off"] = "http://www.roblox.com/asset/?id=6034323670";
		["rotate_right"] = "http://www.roblox.com/asset/?id=6031763429";
		["view_compact"] = "http://www.roblox.com/asset/?id=6031734878";
		["crop_7_5"] = "http://www.roblox.com/asset/?id=6031630197";
		["style"] = "http://www.roblox.com/asset/?id=6031754538";
		["exposure_zero"] = "http://www.roblox.com/asset/?id=6034329000";
		["camera_front"] = "http://www.roblox.com/asset/?id=6031572318";
		["hdr_strong"] = "http://www.roblox.com/asset/?id=6034333272";
		["view_comfy"] = "http://www.roblox.com/asset/?id=6031734876";
		["panorama_vertical"] = "http://www.roblox.com/asset/?id=6034315963";
		["panorama_vertical_select"] = "http://www.roblox.com/asset/?id=6034315961";
		["looks_two"] = "http://www.roblox.com/asset/?id=6034412757";
		["filter_drama"] = "http://www.roblox.com/asset/?id=6031600813";
		["center_focus_strong"] = "http://www.roblox.com/asset/?id=6031625147";
		["18mp"] = "http://www.roblox.com/asset/?id=6031339064";
		["7mp"] = "http://www.roblox.com/asset/?id=6031328139";
		["wb_sunny"] = "http://www.roblox.com/asset/?id=6034412758";
		["filter_9_plus"] = "http://www.roblox.com/asset/?id=6031600812";
		["crop"] = "http://www.roblox.com/asset/?id=6034328964";
		["vignette"] = "http://www.roblox.com/asset/?id=6031734905";
		["brightness_2"] = "http://www.roblox.com/asset/?id=6031488938";
		["crop_square"] = "http://www.roblox.com/asset/?id=6031630222";
		["looks_5"] = "http://www.roblox.com/asset/?id=6034412764";
		["flip"] = "http://www.roblox.com/asset/?id=6034333275";
		["looks_one"] = "http://www.roblox.com/asset/?id=6034412761";
		["flash_off"] = "http://www.roblox.com/asset/?id=6034333270";
		["hdr_off"] = "http://www.roblox.com/asset/?id=6034333266";
		["photo_album"] = "http://www.roblox.com/asset/?id=6031770989";
		["motion_photos_paused"] = "http://www.roblox.com/asset/?id=6034323675";
		["photo_camera"] = "http://www.roblox.com/asset/?id=6031770997";
		["2mp"] = "http://www.roblox.com/asset/?id=6031328138";
		["3mp"] = "http://www.roblox.com/asset/?id=6031328136";
		["24mp"] = "http://www.roblox.com/asset/?id=6031360352";
		["filter_9"] = "http://www.roblox.com/asset/?id=6031597534";
		["6mp"] = "http://www.roblox.com/asset/?id=6031328131";
		["remove_red_eye"] = "http://www.roblox.com/asset/?id=6031763426";
		["4mp"] = "http://www.roblox.com/asset/?id=6031328152";
		["add_a_photo"] = "http://www.roblox.com/asset/?id=6031339049";
		["filter_3"] = "http://www.roblox.com/asset/?id=6031597513";
		["crop_5_4"] = "http://www.roblox.com/asset/?id=6034328960";
		["8mp"] = "http://www.roblox.com/asset/?id=6031328133";
		["camera_roll"] = "http://www.roblox.com/asset/?id=6031572314";
		["panorama_wide_angle"] = "http://www.roblox.com/asset/?id=6031770995";
		["transform"] = "http://www.roblox.com/asset/?id=6031734873";
		["flare"] = "http://www.roblox.com/asset/?id=6031600816";
		["image_search"] = "http://www.roblox.com/asset/?id=6034407084";
		["auto_awesome"] = "http://www.roblox.com/asset/?id=6031360365";
		["motion_photos_on"] = "http://www.roblox.com/asset/?id=6034323669";
		["rotate_90_degrees_ccw"] = "http://www.roblox.com/asset/?id=6031763456";
		["filter_1"] = "http://www.roblox.com/asset/?id=6031597511";
		["filter_tilt_shift"] = "http://www.roblox.com/asset/?id=6031600814";
		["image"] = "http://www.roblox.com/asset/?id=6034407078";
		["center_focus_weak"] = "http://www.roblox.com/asset/?id=6031625144";
		["blur_circular"] = "http://www.roblox.com/asset/?id=6031488945";
		["bedtime"] = "http://www.roblox.com/asset/?id=6031371054";
		["auto_fix_high"] = "http://www.roblox.com/asset/?id=6031360355";
		["monochrome_photos"] = "http://www.roblox.com/asset/?id=6034323678";
		["flash_auto"] = "http://www.roblox.com/asset/?id=6034333287";
		["5mp"] = "http://www.roblox.com/asset/?id=6031328144";
		["photo_size_select_large"] = "http://www.roblox.com/asset/?id=6031763423";
		["assistant_photo"] = "http://www.roblox.com/asset/?id=6031339052";
		["animation"] = "http://www.roblox.com/asset/?id=6031625150";
		["looks"] = "http://www.roblox.com/asset/?id=6034407096";
		["17mp"] = "http://www.roblox.com/asset/?id=6031339055";
		["panorama_horizontal_select"] = "http://www.roblox.com/asset/?id=6034315965";
		["flash_on"] = "http://www.roblox.com/asset/?id=6034333271";
		["iso"] = "http://www.roblox.com/asset/?id=6034407106";
		["music_note"] = "http://www.roblox.com/asset/?id=6034323673";
		["music_off"] = "http://www.roblox.com/asset/?id=6034323679";
		["navigate_next"] = "http://www.roblox.com/asset/?id=6034315956";
		["timer"] = "http://www.roblox.com/asset/?id=6031754564";
		["loupe"] = "http://www.roblox.com/asset/?id=6034412770";
		["navigate_before"] = "http://www.roblox.com/asset/?id=6034323696";
		["brightness_1"] = "http://www.roblox.com/asset/?id=6031471488";
		["brightness_7"] = "http://www.roblox.com/asset/?id=6031471491";
		["tonality"] = "http://www.roblox.com/asset/?id=6031734891";
		["brush"] = "http://www.roblox.com/asset/?id=6031572320";
		["colorize"] = "http://www.roblox.com/asset/?id=6031625161";
		["filter_7"] = "http://www.roblox.com/asset/?id=6031597515";
		["16mp"] = "http://www.roblox.com/asset/?id=6031328168";
		["timer_10"] = "http://www.roblox.com/asset/?id=6031734880";
		["portrait"] = "http://www.roblox.com/asset/?id=6031763434";
		["tune"] = "http://www.roblox.com/asset/?id=6031734877";
		["image_not_supported"] = "http://www.roblox.com/asset/?id=6034407076";
		["wb_cloudy"] = "http://www.roblox.com/asset/?id=6031734907";
		["auto_awesome_motion"] = "http://www.roblox.com/asset/?id=6031360370";
		["filter_8"] = "http://www.roblox.com/asset/?id=6031597532";
		["brightness_5"] = "http://www.roblox.com/asset/?id=6031471479";
		["movie_filter"] = "http://www.roblox.com/asset/?id=6034323687";
		["add_photo_alternate"] = "http://www.roblox.com/asset/?id=6031471484";
		["add_to_photos"] = "http://www.roblox.com/asset/?id=6031371075";
		["texture"] = "http://www.roblox.com/asset/?id=6031754553";
		["11mp"] = "http://www.roblox.com/asset/?id=6031328141";
		["mic_external_on"] = "http://www.roblox.com/asset/?id=6034323671";
		["looks_6"] = "http://www.roblox.com/asset/?id=6034412759";
		["dehaze"] = "http://www.roblox.com/asset/?id=6031630200";
		["control_point"] = "http://www.roblox.com/asset/?id=6031625131";
		["panorama_photosphere"] = "http://www.roblox.com/asset/?id=6034412763";
		["filter_frames"] = "http://www.roblox.com/asset/?id=6031600833";
		["auto_awesome_mosaic"] = "http://www.roblox.com/asset/?id=6031371053";
		["9mp"] = "http://www.roblox.com/asset/?id=6031328146";
		["filter"] = "http://www.roblox.com/asset/?id=6031597514";
		["brightness_3"] = "http://www.roblox.com/asset/?id=6031572317";
		["dirty_lens"] = "http://www.roblox.com/asset/?id=6034328967";
		["wb_incandescent"] = "http://www.roblox.com/asset/?id=6034316010";
		["filter_hdr"] = "http://www.roblox.com/asset/?id=6031600819";
		["textsms"] = "http://www.roblox.com/asset/?id=6035202006";
		["comment"] = "http://www.roblox.com/asset/?id=6035181871";
		["call_end"] = "http://www.roblox.com/asset/?id=6035173845";
		["qr_code_scanner"] = "http://www.roblox.com/asset/?id=6035202022";
		["phonelink_setup"] = "http://www.roblox.com/asset/?id=6035202025";
		["call_merge"] = "http://www.roblox.com/asset/?id=6035173843";
		["phonelink_erase"] = "http://www.roblox.com/asset/?id=6035202085";
		["contact_mail"] = "http://www.roblox.com/asset/?id=6035181868";
		["contact_phone"] = "http://www.roblox.com/asset/?id=6035181861";
		["screen_share"] = "http://www.roblox.com/asset/?id=6035202008";
		["present_to_all"] = "http://www.roblox.com/asset/?id=6035202020";
		["stay_primary_portrait"] = "http://www.roblox.com/asset/?id=6035202009";
		["message"] = "http://www.roblox.com/asset/?id=6035202033";
		["sentiment_satisfied_alt"] = "http://www.roblox.com/asset/?id=6035202069";
		["stay_current_portrait"] = "http://www.roblox.com/asset/?id=6035202004";
		["voicemail"] = "http://www.roblox.com/asset/?id=6035202019";
		["business"] = "http://www.roblox.com/asset/?id=6035173853";
		["mail_outline"] = "http://www.roblox.com/asset/?id=6035190844";
		["vpn_key"] = "http://www.roblox.com/asset/?id=6035202034";
		["forward_to_inbox"] = "http://www.roblox.com/asset/?id=6035190840";
		["contacts"] = "http://www.roblox.com/asset/?id=6035181864";
		["phonelink_ring"] = "http://www.roblox.com/asset/?id=6035202066";
		["domain_disabled"] = "http://www.roblox.com/asset/?id=6035181862";
		["person_add_disabled"] = "http://www.roblox.com/asset/?id=6035202007";
		["stay_primary_landscape"] = "http://www.roblox.com/asset/?id=6035202026";
		["alternate_email"] = "http://www.roblox.com/asset/?id=6035173865";
		["phone_disabled"] = "http://www.roblox.com/asset/?id=6035202028";
		["email"] = "http://www.roblox.com/asset/?id=6035181866";
		["mobile_screen_share"] = "http://www.roblox.com/asset/?id=6035202021";
		["live_help"] = "http://www.roblox.com/asset/?id=6035190836";
		["chat_bubble"] = "http://www.roblox.com/asset/?id=6035181858";
		["stop_screen_share"] = "http://www.roblox.com/asset/?id=6035202042";
		["location_on"] = "http://www.roblox.com/asset/?id=6035190846";
		["chat_bubble_outline"] = "http://www.roblox.com/asset/?id=6035181869";
		["dialer_sip"] = "http://www.roblox.com/asset/?id=6035181865";
		["no_sim"] = "http://www.roblox.com/asset/?id=6035202030";
		["list_alt"] = "http://www.roblox.com/asset/?id=6035190838";
		["call"] = "http://www.roblox.com/asset/?id=6035173859";
		["pause_presentation"] = "http://www.roblox.com/asset/?id=6035202015";
		["invert_colors_off"] = "http://www.roblox.com/asset/?id=6035190842";
		["call_missed_outgoing"] = "http://www.roblox.com/asset/?id=6035173847";
		["stay_current_landscape"] = "http://www.roblox.com/asset/?id=6035202011";
		["import_export"] = "http://www.roblox.com/asset/?id=6035202040";
		["add_ic_call"] = "http://www.roblox.com/asset/?id=6035173839";
		["dialpad"] = "http://www.roblox.com/asset/?id=6035181892";
		["nat"] = "http://www.roblox.com/asset/?id=6035202082";
		["unsubscribe"] = "http://www.roblox.com/asset/?id=6035202044";
		["mark_chat_unread"] = "http://www.roblox.com/asset/?id=6035190841";
		["portable_wifi_off"] = "http://www.roblox.com/asset/?id=6035202091";
		["location_off"] = "http://www.roblox.com/asset/?id=6035202049";
		["person_search"] = "http://www.roblox.com/asset/?id=6035202013";
		["phonelink_lock"] = "http://www.roblox.com/asset/?id=6035202064";
		["desktop_access_disabled"] = "http://www.roblox.com/asset/?id=6035181863";
		["import_contacts"] = "http://www.roblox.com/asset/?id=6035190854";
		["rss_feed"] = "http://www.roblox.com/asset/?id=6035202016";
		["chat"] = "http://www.roblox.com/asset/?id=6035173838";
		["print_disabled"] = "http://www.roblox.com/asset/?id=6035202041";
		["mark_email_read"] = "http://www.roblox.com/asset/?id=6035202038";
		["hourglass_top"] = "http://www.roblox.com/asset/?id=6035190886";
		["clear_all"] = "http://www.roblox.com/asset/?id=6035181870";
		["forum"] = "http://www.roblox.com/asset/?id=6035202002";
		["qr_code"] = "http://www.roblox.com/asset/?id=6035202012";
		["speaker_phone"] = "http://www.roblox.com/asset/?id=6035202018";
		["rtt"] = "http://www.roblox.com/asset/?id=6035202010";
		["domain_verification"] = "http://www.roblox.com/asset/?id=6035181867";
		["app_registration"] = "http://www.roblox.com/asset/?id=6035173870";
		["call_split"] = "http://www.roblox.com/asset/?id=6035173861";
		["cell_wifi"] = "http://www.roblox.com/asset/?id=6035173852";
		["phone_enabled"] = "http://www.roblox.com/asset/?id=6035202089";
		["call_made"] = "http://www.roblox.com/asset/?id=6035173858";
		["call_received"] = "http://www.roblox.com/asset/?id=6035173844";
		["phone"] = "http://www.roblox.com/asset/?id=6035202017";
		["ring_volume"] = "http://www.roblox.com/asset/?id=6035202032";
		["mark_email_unread"] = "http://www.roblox.com/asset/?id=6035202027";
		["hourglass_bottom"] = "http://www.roblox.com/asset/?id=6035202043";
		["read_more"] = "http://www.roblox.com/asset/?id=6035202014";
		["duo"] = "http://www.roblox.com/asset/?id=6035181860";
		["more_time"] = "http://www.roblox.com/asset/?id=6035202036";
		["wifi_calling"] = "http://www.roblox.com/asset/?id=6035202065";
		["swap_calls"] = "http://www.roblox.com/asset/?id=6035202037";
		["cancel_presentation"] = "http://www.roblox.com/asset/?id=6035173837";
		["call_missed"] = "http://www.roblox.com/asset/?id=6035173850";
		["mark_chat_read"] = "http://www.roblox.com/asset/?id=6035202031";
		["text_snippet"] = "http://www.roblox.com/asset/?id=6031302995";
		["snippet_folder"] = "http://www.roblox.com/asset/?id=6031302947";
		["workspaces_outline"] = "http://www.roblox.com/asset/?id=6031302952";
		["file_download"] = "http://www.roblox.com/asset/?id=6031302931";
		["request_quote"] = "http://www.roblox.com/asset/?id=6031302941";
		["approval"] = "http://www.roblox.com/asset/?id=6031302928";
		["drive_folder_upload"] = "http://www.roblox.com/asset/?id=6031302929";
		["rule_folder"] = "http://www.roblox.com/asset/?id=6031302940";
		["attach_email"] = "http://www.roblox.com/asset/?id=6031302935";
		["topic"] = "http://www.roblox.com/asset/?id=6031302976";
		["upload_file"] = "http://www.roblox.com/asset/?id=6031302959";
		["attachment"] = "http://www.roblox.com/asset/?id=6031302921";
		["file_download_done"] = "http://www.roblox.com/asset/?id=6031302926";
		["drive_file_move_outline"] = "http://www.roblox.com/asset/?id=6031302924";
		["cloud_upload"] = "http://www.roblox.com/asset/?id=6031302992";
		["cloud_circle"] = "http://www.roblox.com/asset/?id=6031302919";
		["folder_shared"] = "http://www.roblox.com/asset/?id=6031302945";
		["cloud_download"] = "http://www.roblox.com/asset/?id=6031302917";
		["file_upload"] = "http://www.roblox.com/asset/?id=6031302996";
		["workspaces_filled"] = "http://www.roblox.com/asset/?id=6031302961";
		["cloud_queue"] = "http://www.roblox.com/asset/?id=6031302916";
		["cloud"] = "http://www.roblox.com/asset/?id=6031302918";
		["folder_open"] = "http://www.roblox.com/asset/?id=6031302934";
		["grid_view"] = "http://www.roblox.com/asset/?id=6031302950";
		["cloud_off"] = "http://www.roblox.com/asset/?id=6031302993";
		["create_new_folder"] = "http://www.roblox.com/asset/?id=6031302933";
		["cloud_done"] = "http://www.roblox.com/asset/?id=6031302927";
		["folder"] = "http://www.roblox.com/asset/?id=6031302932";
		["drive_file_move"] = "http://www.roblox.com/asset/?id=6031302922";
		["drive_file_rename_outline"] = "http://www.roblox.com/asset/?id=6031302994";
		["notifications_active"] = "http://www.roblox.com/asset/?id=6034304908";
		["sentiment_neutral"] = "http://www.roblox.com/asset/?id=6034230636";
		["sick"] = "http://www.roblox.com/asset/?id=6034230642";
		["poll"] = "http://www.roblox.com/asset/?id=6034267991";
		["emoji_events"] = "http://www.roblox.com/asset/?id=6034275726";
		["groups"] = "http://www.roblox.com/asset/?id=6034281935";
		["sports_soccer"] = "http://www.roblox.com/asset/?id=6034227075";
		["person_add"] = "http://www.roblox.com/asset/?id=6034287514";
		["mood_bad"] = "http://www.roblox.com/asset/?id=6034295706";
		["person_remove_alt_1"] = "http://www.roblox.com/asset/?id=6034287515";
		["king_bed"] = "http://www.roblox.com/asset/?id=6034281948";
		["architecture"] = "http://www.roblox.com/asset/?id=6034275730";
		["deck"] = "http://www.roblox.com/asset/?id=6034295703";
		["group_add"] = "http://www.roblox.com/asset/?id=6034281909";
		["sports_basketball"] = "http://www.roblox.com/asset/?id=6034230649";
		["emoji_symbols"] = "http://www.roblox.com/asset/?id=6034281899";
		["switch_account"] = "http://www.roblox.com/asset/?id=6034227138";
		["remove_moderator"] = "http://www.roblox.com/asset/?id=6034267998";
		["coronavirus"] = "http://www.roblox.com/asset/?id=6034275724";
		["people"] = "http://www.roblox.com/asset/?id=6034287513";
		["person"] = "http://www.roblox.com/asset/?id=6034287594";
		["elderly"] = "http://www.roblox.com/asset/?id=6034295698";
		["clean_hands"] = "http://www.roblox.com/asset/?id=6034275729";
		["emoji_flags"] = "http://www.roblox.com/asset/?id=6034304898";
		["psychology"] = "http://www.roblox.com/asset/?id=6034287516";
		["person_add_alt"] = "http://www.roblox.com/asset/?id=6034267994";
		["sports_volleyball"] = "http://www.roblox.com/asset/?id=6034227139";
		["domain"] = "http://www.roblox.com/asset/?id=6034275722";
		["emoji_objects"] = "http://www.roblox.com/asset/?id=6034281900";
		["ios_share"] = "http://www.roblox.com/asset/?id=6034281941";
		["history_edu"] = "http://www.roblox.com/asset/?id=6034281934";
		["share"] = "http://www.roblox.com/asset/?id=6034230648";
		["military_tech"] = "http://www.roblox.com/asset/?id=6034295711";
		["sports_kabaddi"] = "http://www.roblox.com/asset/?id=6034227141";
		["cake"] = "http://www.roblox.com/asset/?id=6034295702";
		["engineering"] = "http://www.roblox.com/asset/?id=6034281908";
		["emoji_food_beverage"] = "http://www.roblox.com/asset/?id=6034304883";
		["notifications_none"] = "http://www.roblox.com/asset/?id=6034308947";
		["emoji_people"] = "http://www.roblox.com/asset/?id=6034281904";
		["thumb_down_alt"] = "http://www.roblox.com/asset/?id=6034227069";
		["sentiment_very_satisfied"] = "http://www.roblox.com/asset/?id=6034230650";
		["nights_stay"] = "http://www.roblox.com/asset/?id=6034304881";
		["reduce_capacity"] = "http://www.roblox.com/asset/?id=6034268013";
		["add_moderator"] = "http://www.roblox.com/asset/?id=6034295699";
		["science"] = "http://www.roblox.com/asset/?id=6034230640";
		["pages"] = "http://www.roblox.com/asset/?id=6034304892";
		["sentiment_satisfied"] = "http://www.roblox.com/asset/?id=6034230668";
		["plus_one"] = "http://www.roblox.com/asset/?id=6034268012";
		["party_mode"] = "http://www.roblox.com/asset/?id=6034287521";
		["person_remove"] = "http://www.roblox.com/asset/?id=6034267996";
		["single_bed"] = "http://www.roblox.com/asset/?id=6034230651";
		["mood"] = "http://www.roblox.com/asset/?id=6034295704";
		["public"] = "http://www.roblox.com/asset/?id=6034287522";
		["sports_rugby"] = "http://www.roblox.com/asset/?id=6034227073";
		["sports_handball"] = "http://www.roblox.com/asset/?id=6034227074";
		["person_add_alt_1"] = "http://www.roblox.com/asset/?id=6034287519";
		["people_alt"] = "http://www.roblox.com/asset/?id=6034287518";
		["notifications_off"] = "http://www.roblox.com/asset/?id=6034304894";
		["whatshot"] = "http://www.roblox.com/asset/?id=6034287525";
		["emoji_transportation"] = "http://www.roblox.com/asset/?id=6034281894";
		["outdoor_grill"] = "http://www.roblox.com/asset/?id=6034304900";
		["sentiment_very_dissatisfied"] = "http://www.roblox.com/asset/?id=6034230659";
		["masks"] = "http://www.roblox.com/asset/?id=6034295710";
		["luggage"] = "http://www.roblox.com/asset/?id=6034295708";
		["sports_motorsports"] = "http://www.roblox.com/asset/?id=6034227071";
		["sports_esports"] = "http://www.roblox.com/asset/?id=6034227061";
		["location_city"] = "http://www.roblox.com/asset/?id=6034304889";
		["sports_golf"] = "http://www.roblox.com/asset/?id=6034227060";
		["sentiment_dissatisfied"] = "http://www.roblox.com/asset/?id=6034230637";
		["no_luggage"] = "http://www.roblox.com/asset/?id=6034304891";
		["fireplace"] = "http://www.roblox.com/asset/?id=6034281910";
		["emoji_nature"] = "http://www.roblox.com/asset/?id=6034281896";
		["group"] = "http://www.roblox.com/asset/?id=6034281901";
		["thumb_up_alt"] = "http://www.roblox.com/asset/?id=6034227076";
		["sports_tennis"] = "http://www.roblox.com/asset/?id=6034227068";
		["facebook"] = "http://www.roblox.com/asset/?id=6034281898";
		["sports_mma"] = "http://www.roblox.com/asset/?id=6034227072";
		["person_outline"] = "http://www.roblox.com/asset/?id=6034268008";
		["sports_baseball"] = "http://www.roblox.com/asset/?id=6034230652";
		["sports_cricket"] = "http://www.roblox.com/asset/?id=6034230660";
		["people_outline"] = "http://www.roblox.com/asset/?id=6034287528";
		["notifications_paused"] = "http://www.roblox.com/asset/?id=6034304896";
		["emoji_emotions"] = "http://www.roblox.com/asset/?id=6034275731";
		["follow_the_signs"] = "http://www.roblox.com/asset/?id=6034281911";
		["sanitizer"] = "http://www.roblox.com/asset/?id=6034287586";
		["self_improvement"] = "http://www.roblox.com/asset/?id=6034230634";
		["notifications"] = "http://www.roblox.com/asset/?id=6034308946";
		["public_off"] = "http://www.roblox.com/asset/?id=6034287538";
		["recommend"] = "http://www.roblox.com/asset/?id=6034287524";
		["sports_football"] = "http://www.roblox.com/asset/?id=6034227067";
		["sports_hockey"] = "http://www.roblox.com/asset/?id=6034227064";
		["school"] = "http://www.roblox.com/asset/?id=6034230641";
		["connect_without_contact"] = "http://www.roblox.com/asset/?id=6034275800";
		["sports"] = "http://www.roblox.com/asset/?id=6034230647";
		["construction"] = "http://www.roblox.com/asset/?id=6034275725";
		["inventory"] = "http://www.roblox.com/asset/?id=6035056487";
		["add_box"] = "http://www.roblox.com/asset/?id=6035047375";
		["how_to_reg"] = "http://www.roblox.com/asset/?id=6035053288";
		["unarchive"] = "http://www.roblox.com/asset/?id=6035078921";
		["block_flipped"] = "http://www.roblox.com/asset/?id=6035047378";
		["file_copy"] = "http://www.roblox.com/asset/?id=6035053293";
		["bolt"] = "http://www.roblox.com/asset/?id=6035047381";
		["remove_circle_outline"] = "http://www.roblox.com/asset/?id=6035067843";
		["move_to_inbox"] = "http://www.roblox.com/asset/?id=6035067838";
		["save_alt"] = "http://www.roblox.com/asset/?id=6035067842";
		["weekend"] = "http://www.roblox.com/asset/?id=6035078894";
		["where_to_vote"] = "http://www.roblox.com/asset/?id=6035078913";
		["biotech"] = "http://www.roblox.com/asset/?id=6035047385";
		["report_off"] = "http://www.roblox.com/asset/?id=6035067830";
		["clear"] = "http://www.roblox.com/asset/?id=6035047409";
		["redo"] = "http://www.roblox.com/asset/?id=6035056483";
		["link"] = "http://www.roblox.com/asset/?id=6035056475";
		["drafts"] = "http://www.roblox.com/asset/?id=6035053297";
		["push_pin"] = "http://www.roblox.com/asset/?id=6035056481";
		["reply"] = "http://www.roblox.com/asset/?id=6035067844";
		["undo"] = "http://www.roblox.com/asset/?id=6035078896";
		["archive"] = "http://www.roblox.com/asset/?id=6035047379";
		["add"] = "http://www.roblox.com/asset/?id=6035047377";
		["insights"] = "http://www.roblox.com/asset/?id=6035067839";
		["flag"] = "http://www.roblox.com/asset/?id=6035053279";
		["save"] = "http://www.roblox.com/asset/?id=6035067857";
		["text_format"] = "http://www.roblox.com/asset/?id=6035078890";
		["content_cut"] = "http://www.roblox.com/asset/?id=6035053280";
		["ballot"] = "http://www.roblox.com/asset/?id=6035047386";
		["remove"] = "http://www.roblox.com/asset/?id=6035067836";
		["calculate"] = "http://www.roblox.com/asset/?id=6035047384";
		["report"] = "http://www.roblox.com/asset/?id=6035067826";
		["markunread"] = "http://www.roblox.com/asset/?id=6035056476";
		["delete_sweep"] = "http://www.roblox.com/asset/?id=6035053301";
		["gesture"] = "http://www.roblox.com/asset/?id=6035053287";
		["link_off"] = "http://www.roblox.com/asset/?id=6035056484";
		["forward"] = "http://www.roblox.com/asset/?id=6035053298";
		["reply_all"] = "http://www.roblox.com/asset/?id=6035067824";
		["how_to_vote"] = "http://www.roblox.com/asset/?id=6035053295";
		["square_foot"] = "http://www.roblox.com/asset/?id=6035078918";
		["outlined_flag"] = "http://www.roblox.com/asset/?id=6035056486";
		["add_circle"] = "http://www.roblox.com/asset/?id=6035047380";
		["stacked_bar_chart"] = "http://www.roblox.com/asset/?id=6035078892";
		["policy"] = "http://www.roblox.com/asset/?id=6035056512";
		["backspace"] = "http://www.roblox.com/asset/?id=6035047397";
		["sort"] = "http://www.roblox.com/asset/?id=6035078888";
		["content_paste"] = "http://www.roblox.com/asset/?id=6035053285";
		["low_priority"] = "http://www.roblox.com/asset/?id=6035056491";
		["font_download"] = "http://www.roblox.com/asset/?id=6035053275";
		["shield"] = "http://www.roblox.com/asset/?id=6035078889";
		["waves"] = "http://www.roblox.com/asset/?id=6035078898";
		["select_all"] = "http://www.roblox.com/asset/?id=6035067834";
		["dynamic_feed"] = "http://www.roblox.com/asset/?id=6035053289";
		["mail"] = "http://www.roblox.com/asset/?id=6035056477";
		["amp_stories"] = "http://www.roblox.com/asset/?id=6035047382";
		["filter_list"] = "http://www.roblox.com/asset/?id=6035053294";
		["send"] = "http://www.roblox.com/asset/?id=6035067832";
		["create"] = "http://www.roblox.com/asset/?id=6035053304";
		["stream"] = "http://www.roblox.com/asset/?id=6035078897";
		["next_week"] = "http://www.roblox.com/asset/?id=6035067835";
		["inbox"] = "http://www.roblox.com/asset/?id=6035067831";
		["add_link"] = "http://www.roblox.com/asset/?id=6035047374";
		["content_copy"] = "http://www.roblox.com/asset/?id=6035053278";
		["remove_circle"] = "http://www.roblox.com/asset/?id=6035067837";
		["add_circle_outline"] = "http://www.roblox.com/asset/?id=6035047391";
		["block"] = "http://www.roblox.com/asset/?id=6035047387";
		["tag"] = "http://www.roblox.com/asset/?id=6035078895";
		["beach_access"] = "http://www.roblox.com/asset/?id=6035107923";
		["stroller"] = "http://www.roblox.com/asset/?id=6035161535";
		["family_restroom"] = "http://www.roblox.com/asset/?id=6035121916";
		["corporate_fare"] = "http://www.roblox.com/asset/?id=6035121908";
		["no_meeting_room"] = "http://www.roblox.com/asset/?id=6035153649";
		["do_not_touch"] = "http://www.roblox.com/asset/?id=6035121915";
		["ac_unit"] = "http://www.roblox.com/asset/?id=6035107929";
		["business_center"] = "http://www.roblox.com/asset/?id=6035107933";
		["spa"] = "http://www.roblox.com/asset/?id=6035153639";
		["no_flash"] = "http://www.roblox.com/asset/?id=6035145424";
		["no_cell"] = "http://www.roblox.com/asset/?id=6035145376";
		["room_service"] = "http://www.roblox.com/asset/?id=6035153648";
		["tapas"] = "http://www.roblox.com/asset/?id=6035161533";
		["microwave"] = "http://www.roblox.com/asset/?id=6035145367";
		["meeting_room"] = "http://www.roblox.com/asset/?id=6035145361";
		["wash"] = "http://www.roblox.com/asset/?id=6035161540";
		["escalator"] = "http://www.roblox.com/asset/?id=6035121939";
		["house_siding"] = "http://www.roblox.com/asset/?id=6035145393";
		["food_bank"] = "http://www.roblox.com/asset/?id=6035121921";
		["foundation"] = "http://www.roblox.com/asset/?id=6035121918";
		["elevator"] = "http://www.roblox.com/asset/?id=6035121912";
		["room_preferences"] = "http://www.roblox.com/asset/?id=6035153642";
		["do_not_step"] = "http://www.roblox.com/asset/?id=6035121910";
		["free_breakfast"] = "http://www.roblox.com/asset/?id=6035145363";
		["house"] = "http://www.roblox.com/asset/?id=6035145364";
		["child_care"] = "http://www.roblox.com/asset/?id=6035107927";
		["night_shelter"] = "http://www.roblox.com/asset/?id=6035145378";
		["child_friendly"] = "http://www.roblox.com/asset/?id=6035121942";
		["checkroom"] = "http://www.roblox.com/asset/?id=6035107931";
		["hot_tub"] = "http://www.roblox.com/asset/?id=6035145382";
		["dry"] = "http://www.roblox.com/asset/?id=6035121909";
		["charging_station"] = "http://www.roblox.com/asset/?id=6035107925";
		["all_inclusive"] = "http://www.roblox.com/asset/?id=6035107920";
		["bento"] = "http://www.roblox.com/asset/?id=6035107924";
		["no_backpack"] = "http://www.roblox.com/asset/?id=6035145368";
		["storefront"] = "http://www.roblox.com/asset/?id=6035161534";
		["no_food"] = "http://www.roblox.com/asset/?id=6035145372";
		["backpack"] = "http://www.roblox.com/asset/?id=6035107928";
		["stairs"] = "http://www.roblox.com/asset/?id=6035153637";
		["carpenter"] = "http://www.roblox.com/asset/?id=6035107955";
		["no_stroller"] = "http://www.roblox.com/asset/?id=6035153661";
		["roofing"] = "http://www.roblox.com/asset/?id=6035153656";
		["umbrella"] = "http://www.roblox.com/asset/?id=6035161550";
		["sports_bar"] = "http://www.roblox.com/asset/?id=6035153638";
		["apartment"] = "http://www.roblox.com/asset/?id=6035107922";
		["smoke_free"] = "http://www.roblox.com/asset/?id=6035153647";
		["pool"] = "http://www.roblox.com/asset/?id=6035153655";
		["bathtub"] = "http://www.roblox.com/asset/?id=6035107939";
		["no_drinks"] = "http://www.roblox.com/asset/?id=6035145390";
		["escalator_warning"] = "http://www.roblox.com/asset/?id=6035121930";
		["wheelchair_pickup"] = "http://www.roblox.com/asset/?id=6035161536";
		["smoking_rooms"] = "http://www.roblox.com/asset/?id=6035153636";
		["rice_bowl"] = "http://www.roblox.com/asset/?id=6035153662";
		["tty"] = "http://www.roblox.com/asset/?id=6035161541";
		["no_photography"] = "http://www.roblox.com/asset/?id=6035153664";
		["casino"] = "http://www.roblox.com/asset/?id=6035107936";
		["fence"] = "http://www.roblox.com/asset/?id=6035121923";
		["grass"] = "http://www.roblox.com/asset/?id=6035145359";
		["countertops"] = "http://www.roblox.com/asset/?id=6035121914";
		["kitchen"] = "http://www.roblox.com/asset/?id=6035145362";
		["golf_course"] = "http://www.roblox.com/asset/?id=6035145423";
		["soap"] = "http://www.roblox.com/asset/?id=6035153645";
		["water_damage"] = "http://www.roblox.com/asset/?id=6035161563";
		["airport_shuttle"] = "http://www.roblox.com/asset/?id=6035107921";
		["fitness_center"] = "http://www.roblox.com/asset/?id=6035121907";
		["baby_changing_station"] = "http://www.roblox.com/asset/?id=6035107930";
		["fire_extinguisher"] = "http://www.roblox.com/asset/?id=6035121913";
		["sparkle"] = "http://www.roblox.com/asset/?id=4483362748"
	}
}

-- Other Variables
local request = (syn and syn.request) or (http and http.request) or http_request or nil
local tweeninfo = TweenInfo.new(0.3, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out)
local PresetGradients = {
	["Nightlight (Classic)"] = {Color3.fromRGB(147, 255, 239), Color3.fromRGB(201,211,233), Color3.fromRGB(255, 167, 227)},
	["Nightlight (Neo)"] = {Color3.fromRGB(117, 164, 206), Color3.fromRGB(123, 201, 201), Color3.fromRGB(224, 138, 175)},
	Starlight = {Color3.fromRGB(147, 255, 239), Color3.fromRGB(181, 206, 241), Color3.fromRGB(214, 158, 243)},
	Solar = {Color3.fromRGB(242, 157, 76), Color3.fromRGB(240, 179, 81), Color3.fromRGB(238, 201, 86)},
	Sparkle = {Color3.fromRGB(199, 130, 242), Color3.fromRGB(221, 130, 238), Color3.fromRGB(243, 129, 233)},
	Lime = {Color3.fromRGB(170, 255, 127), Color3.fromRGB(163, 220, 138), Color3.fromRGB(155, 185, 149)},
	Vine = {Color3.fromRGB(0, 191, 143), Color3.fromRGB(0, 126, 94), Color3.fromRGB(0, 61, 46)},
	Cherry = {Color3.fromRGB(148, 54, 54), Color3.fromRGB(168, 67, 70), Color3.fromRGB(188, 80, 86)},
	Daylight = {Color3.fromRGB(51, 156, 255), Color3.fromRGB(89, 171, 237), Color3.fromRGB(127, 186, 218)},
	Blossom = {Color3.fromRGB(255, 165, 243), Color3.fromRGB(213, 129, 231), Color3.fromRGB(170, 92, 218)},
}

local LucideIconsCache
local LucideAttempts = 0
local LucideLastAttempt = -math.huge
local LucideRetryDelay = 10
local LucideMaxAttempts = 3

local function LoadLucideIcons()
	if LucideIconsCache then return LucideIconsCache end
	if LucideAttempts >= LucideMaxAttempts then return nil end
	if os.clock() - LucideLastAttempt < LucideRetryDelay then return nil end

	LucideAttempts += 1
	LucideLastAttempt = os.clock()
	local success, result = pcall(function()
		local iconData = game:HttpGet("https://raw.githubusercontent.com/latte-soft/lucide-roblox/refs/heads/master/lib/Icons.luau")
		local loader = loadstring(iconData)
		return loader and loader()
	end)
	if success and type(result) == "table" and type(result["48px"]) == "table" then
		LucideIconsCache = result
	end
	return LucideIconsCache
end

function Luna:RetryLucideIcons()
	LucideAttempts = 0
	LucideLastAttempt = -math.huge
	LucideIconsCache = nil
	return LoadLucideIcons() ~= nil
end

local FALLBACK_ICON = "rbxassetid://10723434557"

local function NormalizeImageSource(source)
	local normalized = string.lower(tostring(source or "Material"))
	if normalized == "lucide" then return "Lucide" end
	if normalized == "custom" or normalized == "asset" then return "Custom" end
	if normalized == "local" or normalized == "file" or normalized == "localasset"
		or normalized == "customasset" or normalized == "getcustomasset" then
		return "Local"
	end
	return "Material"
end

local function NormalizeIconName(icon, source)
	local name = tostring(icon or "")
	name = name:match("^%s*(.-)%s*$") or name
	if source == "Lucide" then
		return string.lower(name):gsub("_", "-"):gsub("%s+", "-")
	elseif source == "Material" then
		return string.lower(name):gsub("%-", "_"):gsub("%s+", "_")
	end
	return name
end

local function GetCustomAssetFunction()
	if type(getcustomasset) == "function" then return getcustomasset end
	if type(getsynasset) == "function" then return getsynasset end
	if type(syn) == "table" and type(syn.getcustomasset) == "function" then
		return syn.getcustomasset
	end
	return nil
end

local function ResolveLocalAsset(path)
	path = tostring(path or "")
	if path == "" then return nil, "Local icon path is empty." end

	local customAsset = GetCustomAssetFunction()
	if type(customAsset) ~= "function" then
		return nil, "Executor does not support getcustomasset/getsynasset."
	end

	if type(isfile) == "function" then
		local existsSuccess, exists = pcall(isfile, path)
		if not existsSuccess or not exists then
			return nil, "Local icon file does not exist: " .. path
		end
	end

	local success, asset = pcall(customAsset, path)
	if not success or type(asset) ~= "string" or asset == "" then
		return nil, "Unable to register local icon: " .. tostring(asset)
	end
	return asset
end

local function GetIcon(icon, source)
	source = NormalizeImageSource(source)
	icon = NormalizeIconName(icon, source)

	if source == "Local" then
		local asset = ResolveLocalAsset(icon)
		return asset or FALLBACK_ICON
	elseif source == "Custom" then
		if icon == "" then return FALLBACK_ICON end
		if icon:match("^rbxassetid://") or icon:match("^rbxasset://") or icon:match("^https?://") then
			return icon
		end
		return "rbxassetid://" .. icon
	elseif source == "Lucide" then
		local icons = LoadLucideIcons()
		if not icons then return FALLBACK_ICON end
		local r = icons["48px"][icon]
		if not r or type(r[1]) ~= "number" or type(r[2]) ~= "table" or type(r[3]) ~= "table" then
			return FALLBACK_ICON
		end
		return {
			id = r[1],
			imageRectSize = Vector2.new(r[2][1], r[2][2]),
			imageRectOffset = Vector2.new(r[3][1], r[3][2]),
		}
	end

	local materialIcon = IconModule.Material[icon]
	return materialIcon or FALLBACK_ICON
end

local function PrepareIconVisual(imageObject, source)
	imageObject.Visible = true
	imageObject.ImageTransparency = 0
	-- White preserves full-colour local/custom PNGs and keeps monochrome icons visible.
	imageObject.ImageColor3 = Color3.fromRGB(255, 255, 255)
	imageObject:SetAttribute("LunaIconSource", NormalizeImageSource(source))
end

local function UseFallbackIcon(imageObject)
	if not imageObject or not imageObject.Parent then return false end
	imageObject.ImageRectSize = Vector2.zero
	imageObject.ImageRectOffset = Vector2.zero
	imageObject.Image = FALLBACK_ICON
	imageObject.Visible = true
	imageObject.ImageTransparency = 0
	imageObject.ImageColor3 = Color3.fromRGB(255, 255, 255)
	imageObject:SetAttribute("LunaIconFallback", true)
	return true
end

local function PreloadIcon(imageObject)
	task.defer(function()
		if Luna._Destroyed or not imageObject or not imageObject.Parent then return end

		local originalImage = imageObject.Image
		local preloadSuccess = pcall(function()
			ContentProvider:PreloadAsync({imageObject})
		end)

		-- Give IsLoaded one scheduler step to update after PreloadAsync.
		task.wait()
		if Luna._Destroyed or not imageObject or not imageObject.Parent then return end

		local loaded = preloadSuccess and imageObject.IsLoaded == true
		if not loaded and originalImage ~= FALLBACK_ICON then
			UseFallbackIcon(imageObject)
			pcall(function()
				ContentProvider:PreloadAsync({imageObject})
			end)
			task.wait()
			loaded = imageObject.IsLoaded == true
		end

		if imageObject and imageObject.Parent then
			imageObject:SetAttribute("LunaIconLoaded", loaded)
			imageObject:SetAttribute("LunaIconLoadFailed", not loaded)
		end
	end)
end

local function ApplyIcon(imageObject, icon, source)
	if not imageObject or not (imageObject:IsA("ImageLabel") or imageObject:IsA("ImageButton")) then
		return false, "Invalid ImageLabel/ImageButton."
	end

	source = NormalizeImageSource(source)
	local iconData = GetIcon(icon, source)
	imageObject.ImageRectSize = Vector2.zero
	imageObject.ImageRectOffset = Vector2.zero
	imageObject:SetAttribute("LunaIconName", tostring(icon or ""))
	imageObject:SetAttribute("LunaIconFallback", false)
	imageObject:SetAttribute("LunaIconLoadFailed", false)

	local usedFallback = false
	if type(iconData) == "table" then
		if not iconData.id then
			imageObject.Image = FALLBACK_ICON
			usedFallback = true
		else
			imageObject.Image = "rbxassetid://" .. tostring(iconData.id)
			imageObject.ImageRectSize = iconData.imageRectSize or Vector2.zero
			imageObject.ImageRectOffset = iconData.imageRectOffset or Vector2.zero
		end
	elseif type(iconData) == "string" and iconData ~= "" then
		imageObject.Image = iconData
		usedFallback = iconData == FALLBACK_ICON
	else
		imageObject.Image = FALLBACK_ICON
		usedFallback = true
	end

	PrepareIconVisual(imageObject, source)
	PreloadIcon(imageObject)
	return not usedFallback, usedFallback and "Fallback icon was used." or nil
end

local function ApplyLocalIcon(imageObject, path)
	if not imageObject or not (imageObject:IsA("ImageLabel") or imageObject:IsA("ImageButton")) then
		return false, "Invalid ImageLabel/ImageButton."
	end

	local asset, err = ResolveLocalAsset(path)
	if not asset then
		imageObject.ImageRectSize = Vector2.zero
		imageObject.ImageRectOffset = Vector2.zero
		imageObject.Image = FALLBACK_ICON
		PrepareIconVisual(imageObject, "Local")
		PreloadIcon(imageObject)
		return false, err
	end

	imageObject.ImageRectSize = Vector2.zero
	imageObject.ImageRectOffset = Vector2.zero
	imageObject.Image = asset
	imageObject:SetAttribute("LunaIconName", tostring(path or ""))
	PrepareIconVisual(imageObject, "Local")
	PreloadIcon(imageObject)
	return true, asset
end

function Luna:ApplyIcon(imageObject, icon, source)
	return ApplyIcon(imageObject, icon, source)
end

function Luna:ApplyLocalIcon(imageObject, path)
	return ApplyLocalIcon(imageObject, path)
end

function Luna:GetIconDebugInfo(imageObject)
	if not imageObject or not (imageObject:IsA("ImageLabel") or imageObject:IsA("ImageButton")) then
		return nil, "Invalid ImageLabel/ImageButton."
	end
	return {
		Visible = imageObject.Visible,
		ImageTransparency = imageObject.ImageTransparency,
		ImageColor3 = imageObject.ImageColor3,
		Image = imageObject.Image,
		IsLoaded = imageObject.IsLoaded,
		AbsoluteSize = imageObject.AbsoluteSize,
		ImageRectSize = imageObject.ImageRectSize,
		ImageRectOffset = imageObject.ImageRectOffset,
		Source = imageObject:GetAttribute("LunaIconSource"),
		Name = imageObject:GetAttribute("LunaIconName"),
		LoadedAttribute = imageObject:GetAttribute("LunaIconLoaded"),
		UsedFallback = imageObject:GetAttribute("LunaIconFallback"),
		LoadFailed = imageObject:GetAttribute("LunaIconLoadFailed"),
	}
end

local function RemoveTable(tablre, value)
	for i,v in pairs(tablre) do
		if tostring(v) == tostring(value) then
			table.remove(tablre, i)
		end
	end
end

local function Kwargify(defaults, passed)
	for i, v in pairs(defaults) do
		if passed[i] == nil then
			passed[i] = v
		end
	end
	return passed
end

local function PackColor(Color)
	return {R = Color.R * 255, G = Color.G * 255, B = Color.B * 255}
end    

local function UnpackColor(Color)
	return Color3.fromRGB(Color.R, Color.G, Color.B)
end

local function ScaleTweenInfo(info)
	info = info or tweeninfo
	local scale = math.max(0, tonumber(Luna.AnimationSpeed) or 1)
	if Luna.ReducedMotion then scale = 0 end
	local duration = scale == 0 and 0 or math.max(0, info.Time * scale)
	return TweenInfo.new(
		duration,
		info.EasingStyle,
		info.EasingDirection,
		info.RepeatCount,
		info.Reverses,
		info.DelayTime * scale
	)
end

local ActiveTweens = setmetatable({}, {__mode = "k"})
local function TweenGoalKey(goal)
	local keys = {}
	for key in pairs(type(goal) == "table" and goal or {}) do table.insert(keys, tostring(key)) end
	table.sort(keys)
	return table.concat(keys, "|")
end
local function tween(object, goal, callback, tweenin)
	if not object then return nil end
	local bucket = ActiveTweens[object]
	if not bucket then bucket = {}; ActiveTweens[object] = bucket end
	local goalKey = TweenGoalKey(goal)
	local previous = bucket[goalKey]
	if previous then pcall(function() previous:Cancel() end) end
	local animation = TweenService:Create(object, ScaleTweenInfo(tweenin), goal)
	bucket[goalKey] = animation
	animation.Completed:Once(function(...)
		if bucket[goalKey] == animation then bucket[goalKey] = nil end
		if next(bucket) == nil then ActiveTweens[object] = nil end
		if type(callback) == "function" then callback(...) end
	end)
	animation:Play()
	return animation
end

local function BlurModule(Frame)
	local RunService = game:GetService('RunService')
	local camera = workspace.CurrentCamera
	local MTREL = "Glass"
	local binds = {}
	local root = Instance.new('Folder', camera)
	root.Name = 'LunaBlur'

	local gTokenMH = 99999999
	local gToken = math.random(1, gTokenMH)

	local DepthOfField = Instance.new('DepthOfFieldEffect', game:GetService('Lighting'))
	DepthOfField.FarIntensity = 0
	DepthOfField.FocusDistance = 51.6
	DepthOfField.InFocusRadius = 50
	DepthOfField.NearIntensity = 6
	DepthOfField.Name = "DPT_"..gToken

	local frame = Instance.new('Frame')
	frame.Parent = Frame
	frame.Size = UDim2.new(0.95, 0, 0.95, 0)
	frame.Position = UDim2.new(0.5, 0, 0.5, 0)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.BackgroundTransparency = 1

	local GenUid; do -- Generate unique names for RenderStepped bindings
		local id = 0
		function GenUid()
			id = id + 1
			return 'neon::'..tostring(id)
		end
	end

	do
		local function IsNotNaN(x)
			return x == x
		end
		local continue = IsNotNaN(camera:ScreenPointToRay(0,0).Origin.x)
		while not continue do
			RunService.RenderStepped:Wait()
			continue = IsNotNaN(camera:ScreenPointToRay(0,0).Origin.x)
		end
	end

	local DrawQuad; do

		local acos, max, pi, sqrt = math.acos, math.max, math.pi, math.sqrt
		local sz = 0.22
		local function DrawTriangle(v1, v2, v3, p0, p1) -- I think Stravant wrote this function

			local s1 = (v1 - v2).magnitude
			local s2 = (v2 - v3).magnitude
			local s3 = (v3 - v1).magnitude
			local smax = max(s1, s2, s3)
			local A, B, C
			if s1 == smax then
				A, B, C = v1, v2, v3
			elseif s2 == smax then
				A, B, C = v2, v3, v1
			elseif s3 == smax then
				A, B, C = v3, v1, v2
			end

			local para = ( (B-A).x*(C-A).x + (B-A).y*(C-A).y + (B-A).z*(C-A).z ) / (A-B).magnitude
			local perp = sqrt((C-A).magnitude^2 - para*para)
			local dif_para = (A - B).magnitude - para

			local st = CFrame.new(B, A)
			local za = CFrame.Angles(pi/2,0,0)

			local cf0 = st

			local Top_Look = (cf0 * za).lookVector
			local Mid_Point = A + CFrame.new(A, B).lookVector * para
			local Needed_Look = CFrame.new(Mid_Point, C).lookVector
			local dot = Top_Look.x*Needed_Look.x + Top_Look.y*Needed_Look.y + Top_Look.z*Needed_Look.z

			local ac = CFrame.Angles(0, 0, acos(dot))

			cf0 = cf0 * ac
			if ((cf0 * za).lookVector - Needed_Look).magnitude > 0.01 then
				cf0 = cf0 * CFrame.Angles(0, 0, -2*acos(dot))
			end
			cf0 = cf0 * CFrame.new(0, perp/2, -(dif_para + para/2))

			local cf1 = st * ac * CFrame.Angles(0, pi, 0)
			if ((cf1 * za).lookVector - Needed_Look).magnitude > 0.01 then
				cf1 = cf1 * CFrame.Angles(0, 0, 2*acos(dot))
			end
			cf1 = cf1 * CFrame.new(0, perp/2, dif_para/2)

			if not p0 then
				p0 = Instance.new('Part')
				p0.FormFactor = 'Custom'
				p0.TopSurface = 0
				p0.BottomSurface = 0
				p0.Anchored = true
				p0.CanCollide = false
				p0.CastShadow = false
				p0.Material = MTREL
				p0.Size = Vector3.new(sz, sz, sz)
				local mesh = Instance.new('SpecialMesh', p0)
				mesh.MeshType = 2
				mesh.Name = 'WedgeMesh'
			end
			p0.WedgeMesh.Scale = Vector3.new(0, perp/sz, para/sz)
			p0.CFrame = cf0

			if not p1 then
				p1 = p0:clone()
			end
			p1.WedgeMesh.Scale = Vector3.new(0, perp/sz, dif_para/sz)
			p1.CFrame = cf1

			return p0, p1
		end

		function DrawQuad(v1, v2, v3, v4, parts)
			parts[1], parts[2] = DrawTriangle(v1, v2, v3, parts[1], parts[2])
			parts[3], parts[4] = DrawTriangle(v3, v2, v4, parts[3], parts[4])
		end
	end

	if binds[frame] then
		return binds[frame].parts
	end

	local uid = "luna::blur::" .. HttpService:GenerateGUID(false)
	local parts = {}
	local f = Instance.new('Folder', root)
	f.Name = frame.Name

	local parents = {}
	do
		local function add(child)
			if child:IsA'GuiObject' then
				parents[#parents + 1] = child
				add(child.Parent)
			end
		end
		add(frame)
	end

	local function UpdateOrientation(fetchProps)
		if not Frame.Parent or Frame.Visible == false then
			for _, pt in pairs(parts) do
				pt.Transparency = 1
			end
			return
		end

		camera = GetCurrentCamera()
		if not camera then return end
		if root.Parent ~= camera then
			root.Parent = camera
		end

		local properties = {
			Transparency = 0.98;
			BrickColor = BrickColor.new('Institutional white');
		}
		for _, pt in pairs(parts) do
			pt.Transparency = properties.Transparency
		end
		local zIndex = 1 - 0.05*frame.ZIndex

		local tl, br = frame.AbsolutePosition, frame.AbsolutePosition + frame.AbsoluteSize
		local tr, bl = Vector2.new(br.x, tl.y), Vector2.new(tl.x, br.y)
		do
			local rot = 0;
			for _, v in ipairs(parents) do
				rot = rot + v.Rotation
			end
			if rot ~= 0 and rot%180 ~= 0 then
				local mid = tl:lerp(br, 0.5)
				local s, c = math.sin(math.rad(rot)), math.cos(math.rad(rot))
				local vec = tl
				tl = Vector2.new(c*(tl.x - mid.x) - s*(tl.y - mid.y), s*(tl.x - mid.x) + c*(tl.y - mid.y)) + mid
				tr = Vector2.new(c*(tr.x - mid.x) - s*(tr.y - mid.y), s*(tr.x - mid.x) + c*(tr.y - mid.y)) + mid
				bl = Vector2.new(c*(bl.x - mid.x) - s*(bl.y - mid.y), s*(bl.x - mid.x) + c*(bl.y - mid.y)) + mid
				br = Vector2.new(c*(br.x - mid.x) - s*(br.y - mid.y), s*(br.x - mid.x) + c*(br.y - mid.y)) + mid
			end
		end
		DrawQuad(
			camera:ScreenPointToRay(tl.x, tl.y, zIndex).Origin, 
			camera:ScreenPointToRay(tr.x, tr.y, zIndex).Origin, 
			camera:ScreenPointToRay(bl.x, bl.y, zIndex).Origin, 
			camera:ScreenPointToRay(br.x, br.y, zIndex).Origin, 
			parts
		)
		if fetchProps then
			for _, pt in pairs(parts) do
				pt.Parent = f
			end
			for propName, propValue in pairs(properties) do
				for _, pt in pairs(parts) do
					pt[propName] = propValue
				end
			end
		end

	end

	UpdateOrientation(true)
	RunService:BindToRenderStep(uid, 2000, UpdateOrientation)
	Luna._Stats.RenderLoops += 1

	local cleaned = false
	local function CleanupBlur()
		if cleaned then return end
		cleaned = true
		pcall(function() RunService:UnbindFromRenderStep(uid) end)
		Luna._Stats.RenderLoops = math.max(0, Luna._Stats.RenderLoops - 1)
		pcall(function() frame:Destroy() end)
		pcall(function() f:Destroy() end)
		pcall(function() root:Destroy() end)
		pcall(function() DepthOfField:Destroy() end)
	end

	AddCleanup(CleanupBlur)
	return CleanupBlur
end

local function unpackt(array : table)

	local val = ""
	local i = 0
	for _,v in pairs(array) do
		if i < 3 then
			val = val .. v .. ", "
			i += 1
		else
			val = "Various"
			break
		end
	end

	return val
end

-- Interface Management
local assetSuccess, assetObjects = pcall(
	game.GetObjects,
	game,
	"rbxassetid://86467455075715"
)
if not assetSuccess
	or type(assetObjects) ~= "table"
	or not assetObjects[1]
then
	error("Luna UI asset could not be loaded: " .. tostring(assetObjects))
end

local LunaUI = assetObjects[1]
local requiredChildren = {"SmartWindow", "Notifications", "Drag", "MobileSupport"}
for _, childName in ipairs(requiredChildren) do
	if not LunaUI:FindFirstChild(childName) then
		pcall(function() LunaUI:Destroy() end)
		error(("Luna UI asset is missing required child %q."):format(childName))
	end
end

GlobalEnvironment.__LUNA_ACTIVE_LIBRARY = Luna

local SavedWindowVisibilityState = setmetatable({}, {__mode = "k"})
local LastHideNotificationAt = setmetatable({}, {__mode = "k"})

local function Hide(Window, bind, notif, notificationCooldown)
	if not Window then
		return false
	end

	SavedWindowVisibilityState[Window] = {
		Size = Window.Size,
		ElementsVisible = Window.Elements.Visible,
		NavigationVisible = Window.Navigation.Visible,
	}

	local now = os.clock()
	local cooldown = math.max(
		0,
		tonumber(notificationCooldown) or 1.5
	)
	local lastNotification = LastHideNotificationAt[Window] or -math.huge
	local shouldNotify = notif and (now - lastNotification >= cooldown)

	if shouldNotify then
		LastHideNotificationAt[Window] = now
		local bindName = InputBindingName(bind) or "Unassigned"
		Luna:Notification({
			Title = "Interface Hidden",
			Content = "Press the minimize keybind (" .. bindName .. ") to reopen the interface.",
			Icon = "visibility_off",
			ImageSource = "Material",
		})
	end

	-- Full hide is intentionally instant. No delayed task is left behind,
	-- so rapid minimize/restore inputs cannot finish out of order.
	Window.BackgroundTransparency = 1
	Window.Elements.BackgroundTransparency = 1
	Window.Line.BackgroundTransparency = 1
	Window.Title.Title.TextTransparency = 1
	Window.Title.subtitle.TextTransparency = 1
	Window.Logo.ImageTransparency = 1
	Window.Navigation.Line.BackgroundTransparency = 1

	for _, TopbarButton in ipairs(Window.Controls:GetChildren()) do
		if TopbarButton.ClassName == "Frame" then
			TopbarButton.BackgroundTransparency = 1
			if TopbarButton:FindFirstChild("UIStroke") then
				TopbarButton.UIStroke.Transparency = 1
			end
			if TopbarButton:FindFirstChild("ImageLabel") then
				TopbarButton.ImageLabel.ImageTransparency = 1
			end
			TopbarButton.Visible = false
		end
	end

	for _, tabbtn in ipairs(Window.Navigation.Tabs:GetChildren()) do
		if tabbtn.ClassName == "Frame" and tabbtn.Name ~= "InActive Template" then
			tabbtn.BackgroundTransparency = 1
			if tabbtn:FindFirstChild("ImageLabel") then
				tabbtn.ImageLabel.ImageTransparency = 1
			end
			if tabbtn:FindFirstChild("UIStroke") then
				tabbtn.UIStroke.Transparency = 1
			end
			local shadowHolder = tabbtn:FindFirstChild("DropShadowHolder")
			local shadow = shadowHolder and shadowHolder:FindFirstChild("DropShadow")
			if shadow then
				shadow.ImageTransparency = 1
			end
		end
	end

	Window.Size = UDim2.fromOffset(0, 0)
	local parent = Window.Parent
	local shadowHolder = parent and parent:FindFirstChild("ShadowHolder")
	if shadowHolder then
		shadowHolder.Visible = false
	end
	Window.Visible = false
	return true
end


if gethui then
	LunaUI.Parent = gethui()
elseif syn and syn.protect_gui then 
	syn.protect_gui(LunaUI)
	LunaUI.Parent = CoreGui
elseif CoreGui:FindFirstChild("RobloxGui") then
	LunaUI.Parent = CoreGui:FindFirstChild("RobloxGui")
else
	LunaUI.Parent = CoreGui
end

local interfaceParent = type(gethui) == "function" and gethui() or CoreGui
for _, Interface in ipairs(interfaceParent:GetChildren()) do
	if Interface.Name == LunaUI.Name and Interface ~= LunaUI then
		pcall(function()
			Interface.Enabled = false
			Interface:Destroy()
		end)
	end
end

LunaUI.Enabled = false
LunaUI.SmartWindow.Visible = false
LunaUI.Notifications.Template.Visible = false
LunaUI.DisplayOrder = 1000000000

local Main : Frame = LunaUI.SmartWindow
local Dragger = Main.Drag
local dragBar = LunaUI.Drag
local dragInteract = dragBar and dragBar.Interact or nil
local dragBarCosmetic = dragBar and dragBar.Drag or nil
local Elements = Main.Elements.Interactions
local LoadingFrame = Main.LoadingFrame
local Navigation = Main.Navigation
local Tabs = Navigation.Tabs
local Notifications = LunaUI.Notifications

-- Luna 7.3 productivity and component extension layer.
local ProductivityColors = {
	Card = Color3.fromRGB(32, 30, 38),
	CardHover = Color3.fromRGB(39, 37, 47),
	Border = Color3.fromRGB(64, 61, 76),
	Text = Color3.fromRGB(240, 240, 240),
	Muted = Color3.fromRGB(165, 163, 175),
	Success = Color3.fromRGB(76, 190, 125),
	Warning = Color3.fromRGB(235, 177, 74),
	Error = Color3.fromRGB(222, 92, 92),
	Info = Color3.fromRGB(104, 154, 225),
}

local function CreateCorner(parent, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, tonumber(radius) or 7)
	corner.Parent = parent
	return corner
end

local function CreateStroke(parent, transparency)
	local stroke = Instance.new("UIStroke")
	stroke.Color = ProductivityColors.Border
	stroke.Transparency = tonumber(transparency) or 0.45
	stroke.Thickness = 1
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
	return stroke
end

local function CreatePadding(parent, left, right, top, bottom)
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, tonumber(left) or 0)
	padding.PaddingRight = UDim.new(0, tonumber(right) or 0)
	padding.PaddingTop = UDim.new(0, tonumber(top) or 0)
	padding.PaddingBottom = UDim.new(0, tonumber(bottom) or 0)
	padding.Parent = parent
	return padding
end

local function CreateText(parent, text, size, bold)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Text = tostring(text or "")
	label.TextColor3 = ProductivityColors.Text
	label.TextTransparency = 0
	label.Font = Luna.CurrentFont or (bold and Enum.Font.GothamSemibold or Enum.Font.Gotham)
	label.TextSize = tonumber(size) or 14
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Parent = parent
	return label
end

local function CreateCard(parent, name, height)
	local card = Instance.new("Frame")
	card.Name = tostring(name or "Luna Component")
	card:SetAttribute("LunaProductivityCard", true)
	card.BackgroundColor3 = ProductivityColors.Card
	card.BackgroundTransparency = tonumber(Luna.ComponentTransparency) or 0.5
	card.BorderSizePixel = 0
	card.Size = UDim2.new(1, 0, 0, tonumber(height) or 58)
	card.Visible = true
	card.Parent = parent
	CreateCorner(card, 8)
	CreateStroke(card, 0.5)
	return card
end

local function FindScrollingAncestor(object)
	local current = object
	while current do
		if current:IsA("ScrollingFrame") then return current end
		current = current.Parent
	end
	return nil
end

local TooltipRoot
local TooltipTitle
local TooltipContent
local TooltipOwner
local TooltipGeneration = 0

local function EnsureTooltip()
	if TooltipRoot and TooltipRoot.Parent then return TooltipRoot end
	TooltipRoot = Instance.new("Frame")
	TooltipRoot.Name = "LunaTooltip"
	TooltipRoot.BackgroundColor3 = Color3.fromRGB(23, 22, 28)
	TooltipRoot.BackgroundTransparency = 0.05
	TooltipRoot.BorderSizePixel = 0
	TooltipRoot.Size = UDim2.fromOffset(270, 70)
	TooltipRoot.AutomaticSize = Enum.AutomaticSize.Y
	TooltipRoot.Visible = false
	TooltipRoot.ZIndex = 1200
	TooltipRoot.Parent = LunaUI
	CreateCorner(TooltipRoot, 8)
	CreateStroke(TooltipRoot, 0.25)
	CreatePadding(TooltipRoot, 12, 12, 9, 10)

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 3)
	layout.Parent = TooltipRoot

	TooltipTitle = CreateText(TooltipRoot, "Information", 14, true)
	TooltipTitle.Name = "Title"
	TooltipTitle.LayoutOrder = 1
	TooltipTitle.Size = UDim2.new(1, 0, 0, 18)
	TooltipTitle.ZIndex = 1201

	TooltipContent = CreateText(TooltipRoot, "", 12, false)
	TooltipContent.Name = "Content"
	TooltipContent.LayoutOrder = 2
	TooltipContent.Size = UDim2.new(1, 0, 0, 0)
	TooltipContent.AutomaticSize = Enum.AutomaticSize.Y
	TooltipContent.TextWrapped = true
	TooltipContent.TextTransparency = 0.22
	TooltipContent.TextYAlignment = Enum.TextYAlignment.Top
	TooltipContent.ZIndex = 1201
	return TooltipRoot
end

local function PositionTooltip(position)
	local root = EnsureTooltip()
	local camera = GetCurrentCamera()
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	local size = root.AbsoluteSize
	local x = math.clamp(position.X + 14, 8, math.max(8, viewport.X - size.X - 8))
	local y = math.clamp(position.Y + 18, 8, math.max(8, viewport.Y - size.Y - 8))
	root.Position = UDim2.fromOffset(x, y)
end

local function NormalizeTooltip(tooltip, component)
	if tooltip == nil or tooltip == false then return nil end
	if type(tooltip) == "string" then
		return {
			Title = component and component.Settings and component.Settings.Name or "Information",
			Content = tooltip,
		}
	end
	if type(tooltip) == "table" then
		return {
			Title = tooltip.Title or (component and component.Settings and component.Settings.Name) or "Information",
			Content = tooltip.Content or tooltip.Text or tooltip.Description or "",
		}
	end
	return nil
end

local function ShowTooltip(component, tooltip, position)
	local normalized = NormalizeTooltip(tooltip, component)
	if not normalized then return false end
	local root = EnsureTooltip()
	TooltipOwner = component
	TooltipTitle.Text = tostring(normalized.Title or "Information")
	TooltipContent.Text = tostring(normalized.Content or "")
	root.Visible = true
	PositionTooltip(position or UserInputService:GetMouseLocation())
	return true
end

local function HideTooltip(component)
	if component and TooltipOwner ~= component then return end
	TooltipGeneration += 1
	TooltipOwner = nil
	if TooltipRoot then TooltipRoot.Visible = false end
end

AttachTooltipToComponent = function(component, tooltip)
	if not component or component._Destroyed then return component end
	component.Tooltip = tooltip
	if component._TooltipConnectionsAttached then return component end
	local object = component._Object
	if not object or not object:IsA("GuiObject") then return component end
	component._TooltipConnectionsAttached = true
	object.Active = true

	ConnectComponent(component, object.MouseEnter, function()
		if component.Tooltip then ShowTooltip(component, component.Tooltip) end
	end)
	ConnectComponent(component, object.MouseLeave, function()
		HideTooltip(component)
	end)
	ConnectComponent(component, object.InputChanged, function(input)
		if TooltipOwner == component and input.UserInputType == Enum.UserInputType.MouseMovement then
			PositionTooltip(input.Position)
		end
	end)
	ConnectComponent(component, object.InputBegan, function(input)
		if input.UserInputType ~= Enum.UserInputType.Touch then return end
		TooltipGeneration += 1
		local generation = TooltipGeneration
		task.delay(0.55, function()
			if generation == TooltipGeneration and not component._Destroyed and component.Tooltip then
				ShowTooltip(component, component.Tooltip, input.Position)
			end
		end)
	end)
	ConnectComponent(component, object.InputEnded, function(input)
		if input.UserInputType == Enum.UserInputType.Touch then HideTooltip(component) end
	end)
	return component
end

TrackConnection(UserInputService.InputChanged:Connect(function(input)
	if TooltipRoot and TooltipRoot.Visible and input.UserInputType == Enum.UserInputType.MouseMovement then
		PositionTooltip(input.Position)
	end
end))

local function StatusColor(statusType)
	statusType = tostring(statusType or "Info"):lower()
	if statusType == "success" or statusType == "online" or statusType == "connected" then
		return ProductivityColors.Success
	elseif statusType == "warning" or statusType == "pending" then
		return ProductivityColors.Warning
	elseif statusType == "error" or statusType == "offline" or statusType == "failed" then
		return ProductivityColors.Error
	end
	return ProductivityColors.Info
end

local function FocusComponent(component)
	if not component or component._Destroyed then return false end
	if component._Tab and type(component._Tab.Activate) == "function" then
		component._Tab:Activate()
	end
	local object = component._Object
	if not object or not object.Parent then return false end
	component:SetVisible(true)
	local scrolling = FindScrollingAncestor(object)
	if scrolling then
		local relativeY = object.AbsolutePosition.Y - scrolling.AbsolutePosition.Y + scrolling.CanvasPosition.Y
		scrolling.CanvasPosition = Vector2.new(scrolling.CanvasPosition.X, math.max(0, relativeY - 42))
	end
	local stroke = object:FindFirstChildWhichIsA("UIStroke")
	if stroke then
		local originalColor = stroke.Color
		local originalTransparency = stroke.Transparency
		stroke.Color = Color3.fromRGB(190, 205, 255)
		stroke.Transparency = 0
		task.delay(0.65, function()
			if stroke and stroke.Parent then
				stroke.Color = originalColor
				stroke.Transparency = originalTransparency
			end
		end)
	end
	return true
end

local function SearchScore(entry, query)
	query = tostring(query or ""):lower()
	if query == "" then return 1 end
	local name = tostring(entry.Name or ""):lower()
	local description = tostring(entry.Description or ""):lower()
	local category = tostring(entry.Category or ""):lower()
	if name == query then return 1000 end
	if name:sub(1, #query) == query then return 700 - #name end
	local namePosition = name:find(query, 1, true)
	if namePosition then return 500 - namePosition end
	local descriptionPosition = description:find(query, 1, true)
	if descriptionPosition then return 250 - descriptionPosition end
	local categoryPosition = category:find(query, 1, true)
	if categoryPosition then return 150 - categoryPosition end
	local termsMatched = 0
	for term in query:gmatch("%S+") do
		if name:find(term, 1, true) or description:find(term, 1, true) or category:find(term, 1, true) then
			termsMatched += 1
		else
			return 0
		end
	end
	return termsMatched > 0 and (80 + termsMatched) or 0
end

local function RegisterSearchEntry(window, entry)
	if not window or type(entry) ~= "table" then return nil end
	window._SearchEntries = window._SearchEntries or {}
	entry.Id = entry.Id or HttpService:GenerateGUID(false)
	window._SearchEntries[entry.Id] = entry
	return entry
end

local function AttachProductivityComponent(component, settings, context)
	if type(component) ~= "table" then return component end
	settings = type(settings) == "table" and settings or {}
	context = type(context) == "table" and context or {}
	component._Window = context.Window
	component._Tab = context.Tab
	component._TabName = context.Tab and (context.Tab._Name or context.Tab.Name) or context.TabName
	component._Container = context.Container
	component.ProductivityType = context.Type or component.ProductivityType or component.Class
	local currentValue = ReadComponentValue(component)
	if currentValue ~= nil then
		component._DefaultValue = DeepCopy(currentValue)
		component._LastEmittedValue = DeepCopy(currentValue)
		component._LastEmittedInitialized = true
	end

	if not component.Focus then
		function component:Focus()
			return FocusComponent(self)
		end
	end

	if settings.Tooltip then component:SetTooltip(settings.Tooltip) end
	if settings.DependsOn then
		local dependency = settings.DependsOn
		if type(dependency) == "table" and dependency.Source then
			component:DependsOn(dependency.Source, dependency.Value, dependency)
		else
			component:DependsOn(dependency, true)
		end
	end

	local object = component._Object
	if object and Luna.CurrentFont then
		local descendants = object:GetDescendants()
		table.insert(descendants, object)
		for _, descendant in ipairs(descendants) do
			if descendant:IsA("TextLabel") or descendant:IsA("TextButton") or descendant:IsA("TextBox") then
				descendant.Font = Luna.CurrentFont
			end
		end
	end
	if context.Window and object then
		component._SearchEntry = RegisterSearchEntry(context.Window, {
			Name = settings.Name or settings.Title or object.Name or component.Flag or component.Class,
			Description = settings.Description or settings.Tooltip or "",
			Category = component._TabName or context.Category or "Component",
			Component = component,
			Action = function()
				component:Focus()
				if type(settings.CommandCallback) == "function" then SafeCall(settings.CommandCallback, component) end
			end,
		})
	end
	return component
end

local FactoryMethods = {
	"CreateButton",
	"CreateLabel",
	"CreateParagraph",
	"CreateSlider",
	"CreateToggle",
	"CreateBind",
	"CreateInput",
	"CreateDropdown",
	"CreateColorPicker",
}

local function WrapContainerFactory(container, methodName, context)
	local original = container[methodName]
	if type(original) ~= "function" or container["_Wrapped_" .. methodName] then return end
	container["_Wrapped_" .. methodName] = true
	container[methodName] = function(self, settings, ...)
		local supplied = type(settings) == "table" and settings or nil
		local nextSettings = supplied and ShallowCopy(supplied) or settings
		local originalCallback = supplied and supplied.Callback
		local holder = {}

		if supplied and type(originalCallback) == "function" then
			nextSettings.Callback = function(value, ...)
				local result = originalCallback(value, ...)
				local component = holder.Component
				if component then
					component:_EmitChanged(
						DeepCopy(ReadComponentValue(component) ~= nil and ReadComponentValue(component) or value),
						component._LastEmittedValue,
						{Source = "Callback", UserInput = true, Force = ReadComponentValue(component) == nil}
					)
				end
				return result
			end
		end

		local component = original(self, nextSettings, ...)
		holder.Component = component
		if type(component) == "table" then
			component.ProductivityType = component.ProductivityType or methodName:gsub("^Create", "")
			AttachProductivityComponent(component, nextSettings, context)
		end
		return component
	end
end

local function CreateProgressBar(container, settings, flag, context)
	settings = Kwargify({
		Name = "Progress",
		Description = nil,
		Range = {0, 100},
		CurrentValue = 0,
		Status = "",
		ShowPercentage = true,
		Callback = function() end,
	}, ShallowCopy(settings or {}))
	local parent = context.Parent
	local card = CreateCard(parent, tostring(settings.Name) .. " - Progress", settings.Description and 82 or 66)
	local component = {
		Class = "Slider",
		ProductivityType = "ProgressBar",
		IgnoreConfig = false,
		Settings = settings,
		CurrentValue = tonumber(settings.CurrentValue) or 0,
		_Object = card,
	}

	local title = CreateText(card, settings.Name, 14, true)
	title.Position = UDim2.fromOffset(14, 7)
	title.Size = UDim2.new(1, -95, 0, 20)
	local percent = CreateText(card, "0%", 12, true)
	percent.Position = UDim2.new(1, -72, 0, 7)
	percent.Size = UDim2.fromOffset(58, 20)
	percent.TextXAlignment = Enum.TextXAlignment.Right
	local status = CreateText(card, settings.Status or "", 11, false)
	status.Position = UDim2.fromOffset(14, 26)
	status.Size = UDim2.new(1, -28, 0, 16)
	status.TextColor3 = ProductivityColors.Muted
	status.Visible = tostring(settings.Status or "") ~= ""

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.BackgroundColor3 = Color3.fromRGB(20, 19, 24)
	track.BackgroundTransparency = 0.15
	track.BorderSizePixel = 0
	track.Position = UDim2.new(0, 14, 1, -20)
	track.Size = UDim2.new(1, -28, 0, 8)
	track.Parent = card
	CreateCorner(track, 4)
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = Color3.fromRGB(135, 178, 215)
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(0, 1)
	fill.Parent = track
	CreateCorner(fill, 4)
	local gradient = Instance.new("UIGradient")
	gradient.Color = Luna.ThemeGradient
	gradient.Parent = fill

	local function range()
		local minimum = tonumber(settings.Range and settings.Range[1]) or 0
		local maximum = tonumber(settings.Range and settings.Range[2]) or 100
		if minimum > maximum then minimum, maximum = maximum, minimum end
		return minimum, maximum
	end

	local function apply(value, silent)
		local minimum, maximum = range()
		value = math.clamp(tonumber(value) or minimum, minimum, maximum)
		local previous = component.CurrentValue
		component.CurrentValue = value
		settings.CurrentValue = value
		local alpha = maximum == minimum and 0 or (value - minimum) / (maximum - minimum)
		fill.Size = UDim2.fromScale(math.clamp(alpha, 0, 1), 1)
		percent.Text = settings.ShowPercentage == false and tostring(value) or string.format("%d%%", math.floor(alpha * 100 + 0.5))
		percent.Visible = settings.ShowPercentage ~= false
		if silent ~= true and previous ~= value then SafeCall(settings.Callback, value) end
		component:_EmitChanged(value, previous, {Source = "ProgressBar", Silent = silent == true})
		return component
	end

	function component:Set(newSettings)
		newSettings = Kwargify(settings, ShallowCopy(newSettings or {}))
		settings = newSettings
		self.Settings = settings
		title.Text = tostring(settings.Name)
		self:SetStatus(settings.Status)
		return apply(settings.CurrentValue, settings.Silent == true)
	end
	function component:SetValue(value, silent) return apply(value, silent == true) end
	function component:GetValue() return self.CurrentValue end
	function component:SetStatus(value)
		settings.Status = tostring(value or "")
		status.Text = settings.Status
		status.Visible = settings.Status ~= ""
		return self
	end
	function component:Complete(message)
		local _, maximum = range()
		if message ~= nil then self:SetStatus(message) end
		return apply(maximum, false)
	end
	function component:Destroy()
		RemoveOption(self)
		if card.Parent then card:Destroy() end
	end

	if flag then RegisterOption(flag, component) end
	component = EnhanceComponent(component)
	component._DefaultValue = tonumber(settings.CurrentValue) or 0
	AttachProductivityComponent(component, settings, context)
	ConnectComponent(component, LunaUI.ThemeRemote:GetPropertyChangedSignal("Value"), function()
		if gradient.Parent then gradient.Color = Luna.ThemeGradient end
	end)
	apply(settings.CurrentValue, true)
	return component
end

local function CreateStatusComponent(container, settings, context)
	settings = Kwargify({
		Name = "Status",
		Status = "Unknown",
		Type = "Info",
		Description = nil,
	}, ShallowCopy(settings or {}))
	local card = CreateCard(context.Parent, tostring(settings.Name) .. " - Status", settings.Description and 64 or 48)
	local component = {Class = "Status", Settings = settings, _Object = card}
	local dot = Instance.new("Frame")
	dot.Name = "Dot"
	dot.Position = UDim2.fromOffset(14, 17)
	dot.Size = UDim2.fromOffset(10, 10)
	dot.BorderSizePixel = 0
	dot.Parent = card
	CreateCorner(dot, 8)
	local title = CreateText(card, settings.Name, 14, true)
	title.Position = UDim2.fromOffset(34, 6)
	title.Size = UDim2.new(0.55, -34, 0, 22)
	local value = CreateText(card, settings.Status, 12, true)
	value.Position = UDim2.new(0.55, 0, 0, 6)
	value.Size = UDim2.new(0.45, -14, 0, 22)
	value.TextXAlignment = Enum.TextXAlignment.Right
	local description = CreateText(card, settings.Description or "", 11, false)
	description.Position = UDim2.fromOffset(34, 29)
	description.Size = UDim2.new(1, -48, 0, 17)
	description.TextColor3 = ProductivityColors.Muted
	description.Visible = settings.Description ~= nil and settings.Description ~= ""

	function component:SetStatus(statusText, statusType)
		local previous = settings.Status
		settings.Status = tostring(statusText or "")
		if statusType ~= nil then settings.Type = statusType end
		value.Text = settings.Status
		dot.BackgroundColor3 = StatusColor(settings.Type)
		self:_EmitChanged(settings.Status, previous, {Source = "Status"})
		return self
	end
	function component:GetValue() return settings.Status end
	function component:Set(newSettings)
		newSettings = Kwargify(settings, ShallowCopy(newSettings or {}))
		settings = newSettings
		self.Settings = settings
		title.Text = tostring(settings.Name)
		description.Text = tostring(settings.Description or "")
		description.Visible = settings.Description ~= nil and settings.Description ~= ""
		return self:SetStatus(settings.Status, settings.Type)
	end
	function component:Destroy() if card.Parent then card:Destroy() end end
	component = EnhanceComponent(component)
	AttachProductivityComponent(component, settings, context)
	component:SetStatus(settings.Status, settings.Type)
	return component
end

local function CreateImageCard(container, settings, context)
	settings = Kwargify({
		Title = "Image Card",
		Name = nil,
		Description = "",
		Image = "view_in_ar",
		ImageSource = "Material",
		Badge = nil,
		Callback = nil,
	}, ShallowCopy(settings or {}))
	settings.Name = settings.Name or settings.Title
	local card = CreateCard(context.Parent, tostring(settings.Name) .. " - Card", 88)
	local component = {Class = "ImageCard", Settings = settings, _Object = card}
	local image = Instance.new("ImageLabel")
	image.Name = "Image"
	image.BackgroundColor3 = Color3.fromRGB(24, 23, 29)
	image.BackgroundTransparency = 0.2
	image.BorderSizePixel = 0
	image.Position = UDim2.fromOffset(14, 14)
	image.Size = UDim2.fromOffset(60, 60)
	image.ScaleType = Enum.ScaleType.Fit
	image.Parent = card
	CreateCorner(image, 8)
	ApplyIcon(image, settings.Image, settings.ImageSource)
	local title = CreateText(card, settings.Title, 15, true)
	title.Position = UDim2.fromOffset(86, 12)
	title.Size = UDim2.new(1, -100, 0, 24)
	local description = CreateText(card, settings.Description, 12, false)
	description.Position = UDim2.fromOffset(86, 36)
	description.Size = UDim2.new(1, -100, 0, 38)
	description.TextWrapped = true
	description.TextYAlignment = Enum.TextYAlignment.Top
	description.TextColor3 = ProductivityColors.Muted
	local badge = CreateText(card, settings.Badge or "", 10, true)
	badge.BackgroundColor3 = ProductivityColors.Info
	badge.BackgroundTransparency = 0.15
	badge.Position = UDim2.new(1, -88, 0, 10)
	badge.Size = UDim2.fromOffset(74, 20)
	badge.TextXAlignment = Enum.TextXAlignment.Center
	badge.Visible = settings.Badge ~= nil and settings.Badge ~= ""
	CreateCorner(badge, 10)

	local interact = Instance.new("TextButton")
	interact.Name = "Interact"
	interact.BackgroundTransparency = 1
	interact.Text = ""
	interact.Size = UDim2.fromScale(1, 1)
	interact.ZIndex = 5
	interact.Parent = card
	if type(settings.Callback) == "function" then
		ConnectComponent(component, interact.MouseButton1Click, function()
			if IsComponentUsable(component) then SafeCall(settings.Callback, component) end
		end)
	end

	function component:SetImage(icon, source)
		settings.Image = icon
		settings.ImageSource = source or settings.ImageSource
		ApplyIcon(image, settings.Image, settings.ImageSource)
		return self
	end
	function component:SetBadge(value, badgeType)
		settings.Badge = tostring(value or "")
		badge.Text = settings.Badge
		badge.Visible = settings.Badge ~= ""
		if badgeType then badge.BackgroundColor3 = StatusColor(badgeType) end
		return self
	end
	function component:Set(newSettings)
		newSettings = Kwargify(settings, ShallowCopy(newSettings or {}))
		settings = newSettings
		self.Settings = settings
		title.Text = tostring(settings.Title or settings.Name)
		description.Text = tostring(settings.Description or "")
		self:SetImage(settings.Image, settings.ImageSource)
		self:SetBadge(settings.Badge, settings.BadgeType)
		return self
	end
	function component:Destroy() if card.Parent then card:Destroy() end end
	component = EnhanceComponent(component)
	AttachProductivityComponent(component, settings, context)
	return component
end

local function CreateSegmentedControl(container, settings, flag, context)
	settings = Kwargify({
		Name = "Segmented Control",
		Options = {"Option 1", "Option 2"},
		CurrentOption = nil,
		Callback = function() end,
	}, ShallowCopy(settings or {}))
	settings.CurrentOption = settings.CurrentOption or settings.Options[1]
	if type(settings.CurrentOption) == "table" then settings.CurrentOption = settings.CurrentOption[1] end
	local card = CreateCard(context.Parent, tostring(settings.Name) .. " - Segmented", 72)
	local component = {
		Class = "Dropdown",
		ProductivityType = "SegmentedControl",
		IgnoreConfig = false,
		Settings = settings,
		CurrentOption = {settings.CurrentOption},
		_Object = card,
	}
	local title = CreateText(card, settings.Name, 13, true)
	title.Position = UDim2.fromOffset(14, 6)
	title.Size = UDim2.new(1, -28, 0, 20)
	local holder = Instance.new("Frame")
	holder.Name = "Segments"
	holder.BackgroundColor3 = Color3.fromRGB(23, 22, 28)
	holder.BackgroundTransparency = 0.12
	holder.BorderSizePixel = 0
	holder.Position = UDim2.fromOffset(14, 32)
	holder.Size = UDim2.new(1, -28, 0, 28)
	holder.Parent = card
	CreateCorner(holder, 6)
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = holder
	local buttons = {}
	local segmentConnections = {}

	local function render()
		DisconnectConnections(segmentConnections)
		for _, child in ipairs(holder:GetChildren()) do
			if child:IsA("TextButton") then child:Destroy() end
		end
		table.clear(buttons)
		local count = math.max(1, #settings.Options)
		for index, option in ipairs(settings.Options) do
			local button = Instance.new("TextButton")
			button.Name = tostring(option)
			button.AutoButtonColor = false
			button.BackgroundColor3 = Color3.fromRGB(70, 75, 92)
			button.BackgroundTransparency = tostring(option) == tostring(component.CurrentOption[1]) and 0.15 or 1
			button.BorderSizePixel = 0
			button.Size = UDim2.new(1 / count, 0, 1, 0)
			button.Font = Enum.Font.GothamMedium
			button.Text = tostring(option)
			button.TextColor3 = ProductivityColors.Text
			button.TextSize = 11
			button.LayoutOrder = index
			button.Parent = holder
			if index == 1 or index == count then CreateCorner(button, 6) end
			buttons[tostring(option)] = button
			TrackConnection(button.MouseButton1Click:Connect(function()
				component:SetValue(option, false)
			end), segmentConnections)
		end
	end

	local function apply(value, silent)
		if type(value) == "table" then value = value[1] end
		if not table.find(settings.Options, value) then value = settings.Options[1] end
		local previous = component.CurrentOption[1]
		component.CurrentOption = {value}
		settings.CurrentOption = value
		for option, button in pairs(buttons) do
			button.BackgroundTransparency = option == tostring(value) and 0.15 or 1
		end
		if silent ~= true and previous ~= value then SafeCall(settings.Callback, value) end
		component:_EmitChanged(value, previous, {Source = "SegmentedControl", Silent = silent == true})
		return component
	end

	function component:SetValue(value, silent) return apply(value, silent == true) end
	function component:GetValue() return self.CurrentOption[1] end
	function component:Set(newSettings)
		newSettings = Kwargify(settings, ShallowCopy(newSettings or {}))
		settings = newSettings
		self.Settings = settings
		title.Text = tostring(settings.Name)
		if type(settings.Options) ~= "table" then settings.Options = {} end
		render()
		return apply(settings.CurrentOption, settings.Silent == true)
	end
	function component:SetOptions(options, silent)
		settings.Options = type(options) == "table" and options or {}
		render()
		return apply(component.CurrentOption[1], silent == true)
	end
	function component:Destroy()
		DisconnectConnections(segmentConnections)
		RemoveOption(self)
		if card.Parent then card:Destroy() end
	end

	if flag then RegisterOption(flag, component) end
	component = EnhanceComponent(component)
	component._DefaultValue = settings.CurrentOption
	AttachProductivityComponent(component, settings, context)
	render()
	apply(settings.CurrentOption, true)
	return component
end

local function CreateDataTable(container, settings, context)
	settings = Kwargify({
		Name = "Data Table",
		Columns = {"Name", "Value"},
		Rows = {},
		Height = 220,
		Searchable = true,
		Sortable = true,
		RowHeight = 28,
		OnRowSelected = nil,
	}, ShallowCopy(settings or {}))
	local height = math.max(120, tonumber(settings.Height) or 220)
	local card = CreateCard(context.Parent, tostring(settings.Name) .. " - Table", height)
	local component = {Class = "DataTable", Settings = settings, Rows = {}, _Object = card}
	local title = CreateText(card, settings.Name, 14, true)
	title.Position = UDim2.fromOffset(14, 7)
	title.Size = UDim2.new(1, -28, 0, 20)

	local search
	local topOffset = 31
	if settings.Searchable ~= false then
		search = Instance.new("TextBox")
		search.Name = "Search"
		search.BackgroundColor3 = Color3.fromRGB(23, 22, 28)
		search.BackgroundTransparency = 0.15
		search.BorderSizePixel = 0
		search.ClearTextOnFocus = false
		search.Font = Enum.Font.Gotham
		search.PlaceholderText = "Search rows..."
		search.PlaceholderColor3 = ProductivityColors.Muted
		search.Text = ""
		search.TextColor3 = ProductivityColors.Text
		search.TextSize = 12
		search.TextXAlignment = Enum.TextXAlignment.Left
		search.Position = UDim2.fromOffset(14, topOffset)
		search.Size = UDim2.new(1, -28, 0, 28)
		search.Parent = card
		CreateCorner(search, 6)
		CreatePadding(search, 9, 9, 0, 0)
		topOffset += 34
	end

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.BackgroundColor3 = Color3.fromRGB(41, 39, 49)
	header.BackgroundTransparency = 0.2
	header.BorderSizePixel = 0
	header.Position = UDim2.fromOffset(14, topOffset)
	header.Size = UDim2.new(1, -28, 0, 28)
	header.Parent = card
	CreateCorner(header, 5)
	local headerLayout = Instance.new("UIListLayout")
	headerLayout.FillDirection = Enum.FillDirection.Horizontal
	headerLayout.SortOrder = Enum.SortOrder.LayoutOrder
	headerLayout.Parent = header

	local list = Instance.new("ScrollingFrame")
	list.Name = "Rows"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.fromOffset(14, topOffset + 32)
	list.Size = UDim2.new(1, -28, 1, -(topOffset + 44))
	list.ScrollBarThickness = 4
	list.ScrollBarImageColor3 = Color3.fromRGB(95, 93, 108)
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.Parent = card
	local rowLayout = Instance.new("UIListLayout")
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowLayout.Padding = UDim.new(0, 3)
	rowLayout.Parent = list

	local filterText = ""
	local sortColumn
	local sortAscending = true
	local rowConnections = {}
	local headerConnections = {}

	local function cellValue(row, index, column)
		if type(row) ~= "table" then return index == 1 and row or "" end
		if row[index] ~= nil then return row[index] end
		if row[column] ~= nil then return row[column] end
		return ""
	end

	local function renderRows()
		DisconnectConnections(rowConnections)
		for _, child in ipairs(list:GetChildren()) do
			if child:IsA("GuiObject") then child:Destroy() end
		end
		local rows = {}
		for _, row in ipairs(component.Rows) do table.insert(rows, row) end
		if sortColumn then
			local columnName = settings.Columns[sortColumn]
			table.sort(rows, function(a, b)
				local av = cellValue(a, sortColumn, columnName)
				local bv = cellValue(b, sortColumn, columnName)
				local an, bn = tonumber(av), tonumber(bv)
				local left, right = an and bn and an or tostring(av):lower(), an and bn and bn or tostring(bv):lower()
				if sortAscending then return left < right else return left > right end
			end)
		end
		local visibleIndex = 0
		for _, row in ipairs(rows) do
			local searchable = {}
			for index, column in ipairs(settings.Columns) do
				table.insert(searchable, tostring(cellValue(row, index, column)))
			end
			if filterText == "" or table.concat(searchable, " "):lower():find(filterText, 1, true) then
				visibleIndex += 1
				local rowFrame = Instance.new("TextButton")
				rowFrame.Name = "Row " .. visibleIndex
				rowFrame.AutoButtonColor = false
				rowFrame.BackgroundColor3 = visibleIndex % 2 == 0 and Color3.fromRGB(35, 33, 41) or Color3.fromRGB(30, 29, 36)
				rowFrame.BackgroundTransparency = 0.25
				rowFrame.BorderSizePixel = 0
				rowFrame.Text = ""
				rowFrame.Size = UDim2.new(1, -2, 0, tonumber(settings.RowHeight) or 28)
				rowFrame.LayoutOrder = visibleIndex
				rowFrame.Parent = list
				CreateCorner(rowFrame, 4)
				local layout = Instance.new("UIListLayout")
				layout.FillDirection = Enum.FillDirection.Horizontal
				layout.SortOrder = Enum.SortOrder.LayoutOrder
				layout.Parent = rowFrame
				for index, column in ipairs(settings.Columns) do
					local cell = CreateText(rowFrame, cellValue(row, index, column), 11, false)
					cell.LayoutOrder = index
					cell.Size = UDim2.new(1 / math.max(1, #settings.Columns), -4, 1, 0)
					cell.TextTruncate = Enum.TextTruncate.AtEnd
					CreatePadding(cell, 8, 4, 0, 0)
				end
				TrackConnection(rowFrame.MouseButton1Click:Connect(function()
					if type(settings.OnRowSelected) == "function" then SafeCall(settings.OnRowSelected, row, component) end
					component:_EmitChanged(row, nil, {Source = "DataTable", RowSelected = true, Force = true})
				end), rowConnections)
			end
		end
	end

	local function renderHeader()
		DisconnectConnections(headerConnections)
		for _, child in ipairs(header:GetChildren()) do
			if child:IsA("GuiObject") then child:Destroy() end
		end
		for index, column in ipairs(settings.Columns) do
			local button = Instance.new("TextButton")
			button.Name = tostring(column)
			button.AutoButtonColor = false
			button.BackgroundTransparency = 1
			button.BorderSizePixel = 0
			button.Font = Enum.Font.GothamSemibold
			button.Text = tostring(column)
			button.TextColor3 = ProductivityColors.Text
			button.TextSize = 11
			button.TextXAlignment = Enum.TextXAlignment.Left
			button.Size = UDim2.new(1 / math.max(1, #settings.Columns), -4, 1, 0)
			button.LayoutOrder = index
			button.Parent = header
			CreatePadding(button, 8, 4, 0, 0)
			if settings.Sortable ~= false then
				TrackConnection(button.MouseButton1Click:Connect(function()
					if sortColumn == index then sortAscending = not sortAscending else sortColumn, sortAscending = index, true end
					renderRows()
				end), headerConnections)
			end
		end
	end

	function component:SetRows(rows)
		self.Rows = type(rows) == "table" and DeepCopy(rows) or {}
		settings.Rows = self.Rows
		renderRows()
		return self
	end
	function component:AddRow(row)
		table.insert(self.Rows, DeepCopy(row))
		renderRows()
		return self
	end
	function component:Clear()
		table.clear(self.Rows)
		renderRows()
		return self
	end
	function component:SetFilter(value)
		filterText = tostring(value or ""):lower()
		if search and search.Text ~= tostring(value or "") then search.Text = tostring(value or "") end
		renderRows()
		return self
	end
	function component:SortBy(column, ascending)
		if type(column) == "string" then column = table.find(settings.Columns, column) end
		sortColumn = tonumber(column)
		sortAscending = ascending ~= false
		renderRows()
		return self
	end
	function component:GetRows() return DeepCopy(self.Rows) end
	function component:Set(newSettings)
		newSettings = Kwargify(settings, ShallowCopy(newSettings or {}))
		settings = newSettings
		self.Settings = settings
		title.Text = tostring(settings.Name)
		renderHeader()
		return self:SetRows(settings.Rows)
	end
	function component:Destroy()
		DisconnectConnections(rowConnections)
		DisconnectConnections(headerConnections)
		if card.Parent then card:Destroy() end
	end

	component = EnhanceComponent(component)
	AttachProductivityComponent(component, settings, context)
	if search then
		ConnectComponent(component, search:GetPropertyChangedSignal("Text"), function()
			filterText = search.Text:lower()
			renderRows()
		end)
	end
	renderHeader()
	component:SetRows(settings.Rows)
	return component
end

local function EnhanceCollapsibleSection(section, settings)
	if not section or not section._Header or section._CollapsibleEnhanced then return section end
	section._CollapsibleEnhanced = true
	settings = type(settings) == "table" and settings or {}

	local header = section._Header
	local body = section._Body
	local HEADER_HEIGHT = math.max(24, tonumber(settings.HeaderHeight) or 28)

	-- A normal CreateSection remains a normal, always-visible section unless the
	-- caller explicitly requests collapse behaviour. This prevents a blank tab
	-- when older scripts pass a settings table without intending to hide content.
	local isCollapsible = settings.Collapsible == true
		or settings._LunaExplicitCollapsible == true
		or settings.DefaultExpanded ~= nil
		or settings.Collapsed ~= nil

	if settings.Tooltip then section:SetTooltip(settings.Tooltip) end

	if not isCollapsible then
		section.Collapsible = false
		section.Collapsed = false
		if body then body.Visible = true end
		header.Text = tostring(section.Name or settings.Name or "Section")
		return section
	end

	section.Collapsible = true
	if body then body.Visible = true end
	pcall(function() header.ClipsDescendants = false end)

	local expandedArrow = tostring(settings.ExpandedArrow or "▼")
	local collapsedArrow = tostring(settings.CollapsedArrow or "▶")
	if settings.UseAsciiArrow == true then
		expandedArrow, collapsedArrow = "v", ">"
	end

	local function renderHeader()
		if not header or not header.Parent then return end
		local arrowText = section.Collapsed and collapsedArrow or expandedArrow
		header.Text = arrowText .. "  " .. tostring(section.Name or settings.Name or "Section")
		header:SetAttribute("LunaCollapsed", section.Collapsed == true)
		header:SetAttribute("LunaCollapsible", true)
	end

	-- Put the arrow directly inside the title string. Unlike a child positioned
	-- at the right edge, this remains visible even when the asset header uses
	-- automatic width, clipping, or a narrow TextLabel.
	local interact = Instance.new("TextButton")
	interact.Name = "CollapseHeaderInteract"
	interact.BackgroundTransparency = 1
	interact.BorderSizePixel = 0
	interact.Text = ""
	interact.AutoButtonColor = false
	interact.Active = true
	interact.Position = UDim2.fromOffset(0, 0)
	interact.Size = UDim2.new(1, 0, 0, HEADER_HEIGHT)
	interact.ZIndex = header.ZIndex + 5
	interact.Parent = header
	interact:SetAttribute("LunaCollapseControl", true)

	section._CollapseHeaderButton = interact
	section._CollapseArrow = nil

	local baseSetCollapsed = section.SetCollapsed
	local baseSet = section.Set

	function section:SetCollapsed(collapsed)
		if self._Destroyed then return self end
		collapsed = collapsed == true
		baseSetCollapsed(self, collapsed)
		self.Collapsed = collapsed
		if body then body.Visible = not collapsed end
		renderHeader()
		EmitEvent("SectionCollapsed", self, self.Collapsed)
		return self
	end

	function section:Set(newSection)
		if self._Destroyed then return self end
		local result = baseSet(self, newSection)
		if type(newSection) == "table" then
			for key, value in pairs(newSection) do settings[key] = value end
		end
		renderHeader()
		return result == nil and self or result
	end

	function section:IsCollapsed()
		return self.Collapsed == true
	end

	function section:Expand()
		return self:SetCollapsed(false)
	end

	function section:Collapse()
		return self:SetCollapsed(true)
	end

	function section:SetCollapsible(enabled)
		self.Collapsible = enabled ~= false
		if not self.Collapsible then
			self:SetCollapsed(false)
			header.Text = tostring(self.Name or settings.Name or "Section")
			interact.Visible = false
		else
			interact.Visible = true
			renderHeader()
		end
		return self
	end

	local function toggleSection()
		if not IsComponentUsable(section) or section.Collapsible == false then return end
		section:Toggle()
	end

	ConnectComponent(section, interact.MouseButton1Click, toggleSection)
	ConnectComponent(section, interact.MouseEnter, function()
		if header and header.Parent and not section._Destroyed then
			header:SetAttribute("LunaCollapseHover", true)
		end
	end)
	ConnectComponent(section, interact.MouseLeave, function()
		if header and header.Parent and not section._Destroyed then
			header:SetAttribute("LunaCollapseHover", false)
		end
	end)

	-- Collapsible sections now open by default. A caller must explicitly set
	-- DefaultExpanded = false or Collapsed = true to start closed.
	local initiallyCollapsed = settings.Collapsed == true or settings.DefaultExpanded == false
	section:SetCollapsed(initiallyCollapsed)

	-- Some UI assets update visibility during the same frame in which they are
	-- cloned. Re-assert the expanded body once after creation so child controls
	-- cannot remain hidden because of an initialization race.
	task.defer(function()
		if not section._Destroyed and body and body.Parent and not section.Collapsed then
			body.Visible = true
			renderHeader()
		end
	end)

	if section._Window then
		section._SearchEntry = RegisterSearchEntry(section._Window, {
			Name = section.Name,
			Description = settings.Description or "Open section",
			Category = section._Tab and section._Tab._Name or "Sections",
			Component = section,
			Action = function()
				section:Expand()
				FocusComponent(section)
			end,
		})
	end
	return section
end

local function EnhanceContainerAPI(container, parent, window, tab, metadata)
	if not container or container._ProductivityContainerEnhanced then return container end
	container._ProductivityContainerEnhanced = true
	metadata = type(metadata) == "table" and metadata or {}
	container._Parent = parent
	container._Window = window
	container._Tab = tab
	local context = {
		Parent = parent,
		Window = window,
		Tab = tab,
		Container = container,
		Category = metadata.Name,
	}

	for _, methodName in ipairs(FactoryMethods) do
		WrapContainerFactory(container, methodName, context)
	end

	function container:CreateProgressBar(settings, flag)
		return CreateProgressBar(self, settings, flag, context)
	end
	function container:CreateStatus(settings)
		return CreateStatusComponent(self, settings, context)
	end
	function container:CreateImageCard(settings)
		return CreateImageCard(self, settings, context)
	end
	function container:CreateSegmentedControl(settings, flag)
		return CreateSegmentedControl(self, settings, flag, context)
	end
	function container:CreateDataTable(settings)
		return CreateDataTable(self, settings, context)
	end
	function container:CreateTable(settings)
		return self:CreateDataTable(settings)
	end
	function container:CreateListView(settings)
		settings = ShallowCopy(settings or {})
		settings.Columns = settings.Columns or {settings.ColumnName or "Item"}
		return self:CreateDataTable(settings)
	end

	if metadata.IsTab then
		function container:CreateCollapsibleSection(settings)
			settings = type(settings) == "table" and ShallowCopy(settings) or {Name = settings}
			settings.Collapsible = true
			settings._LunaExplicitCollapsible = true
			if settings.DefaultExpanded == nil and settings.Collapsed == nil then
				settings.DefaultExpanded = true
			end
			return self:CreateSection(settings)
		end
	end
	return container
end

local function CreateModalOverlay(window, data)
	data = Kwargify({
		Title = "Confirmation",
		Content = "",
		ConfirmText = "Confirm",
		CancelText = "Cancel",
		ShowCancel = true,
		Input = false,
		Placeholder = "Type here...",
		CurrentValue = "",
		CloseOnBackground = false,
		Callback = nil,
	}, ShallowCopy(data or {}))
	Luna._Stats.ModalsOpened += 1
	local handle = {Closed = false, Result = nil}
	local resolved = Instance.new("BindableEvent")
	local connections = {}

	local overlay = Instance.new("Frame")
	overlay.Name = "LunaModal"
	overlay.BackgroundColor3 = Color3.new(0, 0, 0)
	overlay.BackgroundTransparency = 0.38
	overlay.BorderSizePixel = 0
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.ZIndex = 800
	overlay.Parent = LunaUI

	local background = Instance.new("TextButton")
	background.Name = "Background"
	background.BackgroundTransparency = 1
	background.Text = ""
	background.Size = UDim2.fromScale(1, 1)
	background.ZIndex = 800
	background.Parent = overlay

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.new(0, 420, 0, data.Input and 235 or 185)
	panel.BackgroundColor3 = Color3.fromRGB(28, 27, 34)
	panel.BackgroundTransparency = 0.02
	panel.BorderSizePixel = 0
	panel.ZIndex = 802
	panel.Parent = overlay
	CreateCorner(panel, 11)
	CreateStroke(panel, 0.22)

	local title = CreateText(panel, data.Title, 18, true)
	title.Position = UDim2.fromOffset(20, 15)
	title.Size = UDim2.new(1, -40, 0, 28)
	title.ZIndex = 803
	local content = CreateText(panel, data.Content, 13, false)
	content.Position = UDim2.fromOffset(20, 48)
	content.Size = UDim2.new(1, -40, 0, data.Input and 58 or 72)
	content.TextWrapped = true
	content.TextYAlignment = Enum.TextYAlignment.Top
	content.TextColor3 = ProductivityColors.Muted
	content.ZIndex = 803

	local inputBox
	if data.Input then
		inputBox = Instance.new("TextBox")
		inputBox.Name = "Input"
		inputBox.BackgroundColor3 = Color3.fromRGB(20, 19, 25)
		inputBox.BackgroundTransparency = 0.08
		inputBox.BorderSizePixel = 0
		inputBox.ClearTextOnFocus = false
		inputBox.Font = Enum.Font.Gotham
		inputBox.PlaceholderText = tostring(data.Placeholder)
		inputBox.PlaceholderColor3 = ProductivityColors.Muted
		inputBox.Text = tostring(data.CurrentValue or "")
		inputBox.TextColor3 = ProductivityColors.Text
		inputBox.TextSize = 13
		inputBox.TextXAlignment = Enum.TextXAlignment.Left
		inputBox.Position = UDim2.fromOffset(20, 112)
		inputBox.Size = UDim2.new(1, -40, 0, 36)
		inputBox.ZIndex = 803
		inputBox.Parent = panel
		CreateCorner(inputBox, 7)
		CreateStroke(inputBox, 0.55)
		CreatePadding(inputBox, 10, 10, 0, 0)
	end

	local buttons = Instance.new("Frame")
	buttons.Name = "Buttons"
	buttons.BackgroundTransparency = 1
	buttons.Position = UDim2.new(0, 20, 1, -54)
	buttons.Size = UDim2.new(1, -40, 0, 36)
	buttons.ZIndex = 803
	buttons.Parent = panel
	local buttonLayout = Instance.new("UIListLayout")
	buttonLayout.FillDirection = Enum.FillDirection.Horizontal
	buttonLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	buttonLayout.Padding = UDim.new(0, 8)
	buttonLayout.Parent = buttons

	local function makeButton(name, text, primary)
		local button = Instance.new("TextButton")
		button.Name = name
		button.AutoButtonColor = false
		button.BackgroundColor3 = primary and Color3.fromRGB(74, 100, 136) or Color3.fromRGB(45, 43, 53)
		button.BackgroundTransparency = primary and 0.05 or 0.2
		button.BorderSizePixel = 0
		button.Font = Enum.Font.GothamSemibold
		button.Text = tostring(text)
		button.TextColor3 = ProductivityColors.Text
		button.TextSize = 12
		button.Size = UDim2.fromOffset(math.max(92, #tostring(text) * 8 + 28), 36)
		button.ZIndex = 804
		button.Parent = buttons
		CreateCorner(button, 7)
		return button
	end
	local cancel = data.ShowCancel ~= false and makeButton("Cancel", data.CancelText, false) or nil
	local confirm = makeButton("Confirm", data.ConfirmText, true)

	function handle:Close(result)
		if self.Closed then return self.Result end
		self.Closed = true
		self.Result = result
		for _, connection in ipairs(connections) do pcall(function() connection:Disconnect() end) end
		table.clear(connections)
		if overlay.Parent then overlay:Destroy() end
		if window._ActiveModal == self then window._ActiveModal = nil end
		resolved:Fire(result)
		if type(data.Callback) == "function" then SafeCall(data.Callback, result, self) end
		EmitEvent("ModalClosed", window, self, result)
		task.defer(function() resolved:Destroy() end)
		return result
	end
	function handle:Await()
		if self.Closed then return self.Result end
		return resolved.Event:Wait()
	end
	function handle:GetInput()
		return inputBox and inputBox.Text or nil
	end
	function handle:SetContent(value)
		content.Text = tostring(value or "")
		return self
	end
	function handle:SetTitle(value)
		title.Text = tostring(value or "")
		return self
	end

	table.insert(connections, confirm.MouseButton1Click:Connect(function()
		handle:Close(inputBox and inputBox.Text or true)
	end))
	if cancel then
		table.insert(connections, cancel.MouseButton1Click:Connect(function() handle:Close(false) end))
	end
	if data.CloseOnBackground then
		table.insert(connections, background.MouseButton1Click:Connect(function() handle:Close(false) end))
	end
	table.insert(connections, UserInputService.InputBegan:Connect(function(input)
		if handle.Closed then return end
		if input.KeyCode == Enum.KeyCode.Escape then handle:Close(false) end
	end))
	if inputBox then task.defer(function() if inputBox.Parent then inputBox:CaptureFocus() end end) end
	EmitEvent("ModalOpened", window, handle, data)
	return handle
end

local function EnhanceWindowProductivity(window, settings)
	if not window or window._ProductivityEnhanced then return window end
	window._ProductivityEnhanced = true
	window._Tabs = window._Tabs or {}
	window._SearchEntries = window._SearchEntries or {}
	window._Commands = window._Commands or {}
	window.CommandPaletteKeybind = Enum.KeyCode.K
	window.CommandPaletteModifier = Enum.KeyCode.LeftControl

	function window:_RegisterTab(tab)
		if not tab then return end
		self._Tabs[tostring(tab._Name or #self._Tabs + 1)] = tab
		RegisterSearchEntry(self, {
			Name = tostring(tab._Name or "Tab"),
			Description = "Open tab",
			Category = "Tabs",
			Action = function() if type(tab.Activate) == "function" then tab:Activate() end end,
		})
		EmitEvent("TabRegistered", self, tab)
	end

	function window:RegisterCommand(commandSettings)
		commandSettings = type(commandSettings) == "table" and commandSettings or {Name = commandSettings}
		local id = tostring(commandSettings.Id or HttpService:GenerateGUID(false))
		local entry = RegisterSearchEntry(self, {
			Id = id,
			Name = commandSettings.Name or id,
			Description = commandSettings.Description or "",
			Category = commandSettings.Category or "Commands",
			Action = commandSettings.Callback or commandSettings.Action or function() end,
		})
		self._Commands[id] = entry
		return entry
	end

	function window:UnregisterCommand(id)
		id = tostring(id or "")
		self._Commands[id] = nil
		self._SearchEntries[id] = nil
		return true
	end

	function window:Search(query, limit)
		Luna._Stats.CommandPaletteSearches += 1
		local results = {}
		for _, entry in pairs(self._SearchEntries) do
			local score = SearchScore(entry, query)
			if score > 0 then
				table.insert(results, {Entry = entry, Score = score})
			end
		end
		table.sort(results, function(a, b)
			if a.Score == b.Score then return tostring(a.Entry.Name) < tostring(b.Entry.Name) end
			return a.Score > b.Score
		end)
		local output = {}
		for index = 1, math.min(#results, math.max(1, tonumber(limit) or 12)) do
			table.insert(output, results[index].Entry)
		end
		EmitEvent("CommandPaletteSearched", self, query, output)
		return output
	end

	function window:OpenModal(data)
		if self._ActiveModal and not self._ActiveModal.Closed then self._ActiveModal:Close(false) end
		self._ActiveModal = CreateModalOverlay(self, data)
		return self._ActiveModal
	end
	function window:Confirm(data)
		data = ShallowCopy(data or {})
		data.Input = false
		return self:OpenModal(data)
	end
	function window:Prompt(data)
		data = ShallowCopy(data or {})
		data.Input = true
		return self:OpenModal(data)
	end

	function window:SetCommandPaletteKeybind(keybind, modifier)
		local binding, err = NormalizeInputBinding(keybind)
		if not binding or binding.Kind ~= "KeyCode" then return false, err or "KeyCode required." end
		self.CommandPaletteKeybind = binding.EnumItem
		if modifier ~= nil then
			local modifierBinding, modifierError = NormalizeInputBinding(modifier)
			if not modifierBinding or modifierBinding.Kind ~= "KeyCode" then return false, modifierError end
			self.CommandPaletteModifier = modifierBinding.EnumItem
		end
		return true
	end

	function window:OpenCommandPalette(initialQuery)
		if self._Palette and not self._Palette.Closed then
			if self._Palette.Input then self._Palette.Input:CaptureFocus() end
			return self._Palette
		end
		local palette = {Closed = false}
		local overlay = Instance.new("Frame")
		overlay.Name = "LunaCommandPalette"
		overlay.BackgroundColor3 = Color3.new(0, 0, 0)
		overlay.BackgroundTransparency = 0.42
		overlay.BorderSizePixel = 0
		overlay.Size = UDim2.fromScale(1, 1)
		overlay.ZIndex = 850
		overlay.Parent = LunaUI
		local background = Instance.new("TextButton")
		background.BackgroundTransparency = 1
		background.Text = ""
		background.Size = UDim2.fromScale(1, 1)
		background.ZIndex = 850
		background.Parent = overlay
		local panel = Instance.new("Frame")
		panel.AnchorPoint = Vector2.new(0.5, 0)
		panel.Position = UDim2.new(0.5, 0, 0, 72)
		panel.Size = UDim2.fromOffset(500, 410)
		panel.BackgroundColor3 = Color3.fromRGB(27, 26, 33)
		panel.BackgroundTransparency = 0.01
		panel.BorderSizePixel = 0
		panel.ZIndex = 852
		panel.Parent = overlay
		CreateCorner(panel, 11)
		CreateStroke(panel, 0.2)
		local input = Instance.new("TextBox")
		input.Name = "Search"
		input.BackgroundColor3 = Color3.fromRGB(20, 19, 25)
		input.BackgroundTransparency = 0.05
		input.BorderSizePixel = 0
		input.ClearTextOnFocus = false
		input.Font = Enum.Font.GothamMedium
		input.PlaceholderText = "Search components and commands..."
		input.PlaceholderColor3 = ProductivityColors.Muted
		input.Text = tostring(initialQuery or "")
		input.TextColor3 = ProductivityColors.Text
		input.TextSize = 14
		input.TextXAlignment = Enum.TextXAlignment.Left
		input.Position = UDim2.fromOffset(14, 14)
		input.Size = UDim2.new(1, -28, 0, 42)
		input.ZIndex = 853
		input.Parent = panel
		CreateCorner(input, 8)
		CreateStroke(input, 0.55)
		CreatePadding(input, 12, 12, 0, 0)
		local resultsFrame = Instance.new("ScrollingFrame")
		resultsFrame.Name = "Results"
		resultsFrame.BackgroundTransparency = 1
		resultsFrame.BorderSizePixel = 0
		resultsFrame.Position = UDim2.fromOffset(14, 66)
		resultsFrame.Size = UDim2.new(1, -28, 1, -80)
		resultsFrame.ScrollBarThickness = 4
		resultsFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
		resultsFrame.CanvasSize = UDim2.new()
		resultsFrame.ZIndex = 853
		resultsFrame.Parent = panel
		local layout = Instance.new("UIListLayout")
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Padding = UDim.new(0, 5)
		layout.Parent = resultsFrame
		local connections = {}
		local resultConnections = {}

		function palette:Close()
			if self.Closed then return end
			self.Closed = true
			for _, connection in ipairs(connections) do pcall(function() connection:Disconnect() end) end
			for _, connection in ipairs(resultConnections) do pcall(function() connection:Disconnect() end) end
			table.clear(connections)
			table.clear(resultConnections)
			if overlay.Parent then overlay:Destroy() end
			window._Palette = nil
			EmitEvent("CommandPaletteClosed", window)
		end
		function palette:Refresh()
			for _, connection in ipairs(resultConnections) do pcall(function() connection:Disconnect() end) end
			table.clear(resultConnections)
			for _, child in ipairs(resultsFrame:GetChildren()) do
				if child:IsA("GuiObject") then child:Destroy() end
			end
			local results = window:Search(input.Text, 12)
			for index, entry in ipairs(results) do
				local button = Instance.new("TextButton")
				button.Name = tostring(entry.Name)
				button.AutoButtonColor = false
				button.BackgroundColor3 = Color3.fromRGB(37, 35, 44)
				button.BackgroundTransparency = 0.2
				button.BorderSizePixel = 0
				button.Text = ""
				button.Size = UDim2.new(1, -2, 0, 48)
				button.LayoutOrder = index
				button.ZIndex = 854
				button.Parent = resultsFrame
				CreateCorner(button, 7)
				local name = CreateText(button, entry.Name, 13, true)
				name.Position = UDim2.fromOffset(12, 4)
				name.Size = UDim2.new(1, -24, 0, 21)
				name.ZIndex = 855
				local description = CreateText(button, entry.Description or entry.Category or "", 11, false)
				description.Position = UDim2.fromOffset(12, 24)
				description.Size = UDim2.new(1, -24, 0, 17)
				description.TextColor3 = ProductivityColors.Muted
				description.ZIndex = 855
				table.insert(resultConnections, button.MouseButton1Click:Connect(function()
					palette:Close()
					if type(entry.Action) == "function" then SafeCall(entry.Action, entry) end
				end))
			end
		end
		palette.Input = input
		table.insert(connections, input:GetPropertyChangedSignal("Text"):Connect(function() palette:Refresh() end))
		table.insert(connections, background.MouseButton1Click:Connect(function() palette:Close() end))
		table.insert(connections, UserInputService.InputBegan:Connect(function(key)
			if palette.Closed then return end
			if key.KeyCode == Enum.KeyCode.Escape then palette:Close() end
		end))
		self._Palette = palette
		palette:Refresh()
		task.defer(function() if input.Parent then input:CaptureFocus() end end)
		EmitEvent("CommandPaletteOpened", self, palette)
		return palette
	end

	function window:CloseCommandPalette()
		if self._Palette then self._Palette:Close() end
		return true
	end

	function window:SetUIScale(scale)
		scale = math.clamp(tonumber(scale) or 1, 0.65, 1.5)
		Luna.UIScale = scale
		local root = Main.Parent or Main
		local uiScale = root:FindFirstChild("LunaUIScale")
		if not uiScale then
			uiScale = Instance.new("UIScale")
			uiScale.Name = "LunaUIScale"
			uiScale.Parent = root
		end
		uiScale.Scale = scale
		EmitEvent("UIScaleChanged", self, scale)
		return scale
	end

	function window:SetDensity(mode)
		mode = tostring(mode or "Comfortable")
		local normalized = mode:lower()
		local padding = normalized == "compact" and 3 or normalized == "spacious" and 10 or 6
		for _, descendant in ipairs(Elements:GetDescendants()) do
			if descendant:IsA("UIListLayout") and descendant.FillDirection == Enum.FillDirection.Vertical then
				if descendant:GetAttribute("LunaOriginalPadding") == nil then
					descendant:SetAttribute("LunaOriginalPadding", descendant.Padding.Offset)
				end
				descendant.Padding = UDim.new(0, padding)
			end
		end
		self.Density = normalized == "compact" and "Compact" or normalized == "spacious" and "Spacious" or "Comfortable"
		Luna.CurrentDensity = self.Density
		EmitEvent("DensityChanged", self, self.Density)
		return self.Density
	end

	function window:ResetTab(name, silent)
		name = tostring(name or self.CurrentTab or "")
		local count = 0
		for _, option in pairs(Luna.Options) do
			if option._Window == self and tostring(option._TabName or "") == name and type(option.Reset) == "function" then
				option:Reset(silent == true)
				count += 1
			end
		end
		NormalizeAllToggleGroups(false)
		EmitEvent("TabReset", self, name, count)
		return true, count
	end

	window:SetUIScale(Luna.UIScale)
	if Luna.CurrentDensity then window:SetDensity(Luna.CurrentDensity) end
	TrackConnection(UserInputService.InputBegan:Connect(function(input, processed)
		if processed or Luna._Destroyed or UserInputService:GetFocusedTextBox() then return end
		if input.KeyCode ~= window.CommandPaletteKeybind then return end
		local modifier = window.CommandPaletteModifier
		if modifier and not UserInputService:IsKeyDown(modifier) then
			local alternate = modifier == Enum.KeyCode.LeftControl and Enum.KeyCode.RightControl or nil
			if not alternate or not UserInputService:IsKeyDown(alternate) then return end
		end
		window:OpenCommandPalette()
	end))
	return window
end


local function CountTableEntries(value)
	local count = 0
	for _ in pairs(type(value) == "table" and value or {}) do count += 1 end
	return count
end

function Luna:SetFont(font)
	if typeof(font) ~= "EnumItem" or font.EnumType ~= Enum.Font then
		return false, "Font must be an Enum.Font value."
	end
	for _, descendant in ipairs(LunaUI:GetDescendants()) do
		if descendant:IsA("TextLabel") or descendant:IsA("TextButton") or descendant:IsA("TextBox") then
			descendant.Font = font
		end
	end
	Luna.CurrentFont = font
	EmitEvent("FontChanged", font)
	return true, font
end

function Luna:SetComponentTransparency(value)
	value = math.clamp(tonumber(value) or 0.5, 0, 1)
	for _, descendant in ipairs(LunaUI:GetDescendants()) do
		if descendant:IsA("Frame") and descendant:GetAttribute("LunaProductivityCard") then
			descendant.BackgroundTransparency = value
		end
	end
	Luna.ComponentTransparency = value
	EmitEvent("ComponentTransparencyChanged", value)
	return value
end

function Luna:RegisterTheme(name, theme)
	name = tostring(name or ""):match("^%s*(.-)%s*$")
	if name == "" then return false, "Theme name is empty." end
	if type(theme) ~= "table" then return false, "Theme must be a table." end
	Luna._Themes[name] = DeepCopy(theme)
	EmitEvent("ThemeRegistered", name, Luna._Themes[name])
	return true, name
end

function Luna:RemoveTheme(name)
	name = tostring(name or "")
	if not Luna._Themes[name] then return false, "Theme does not exist." end
	Luna._Themes[name] = nil
	EmitEvent("ThemeRemoved", name)
	return true
end

function Luna:GetThemes()
	return DeepCopy(Luna._Themes)
end

function Luna:SetAnimationSpeed(value)
	Luna.AnimationSpeed = math.clamp(tonumber(value) or 1, 0, 5)
	EmitEvent("AnimationSpeedChanged", Luna.AnimationSpeed)
	return Luna.AnimationSpeed
end

function Luna:SetReducedMotion(enabled)
	Luna.ReducedMotion = enabled == true
	EmitEvent("ReducedMotionChanged", Luna.ReducedMotion)
	return Luna.ReducedMotion
end

function Luna:SetTheme(theme)
	local themeName
	if type(theme) == "string" then
		themeName = theme
		theme = Luna._Themes[theme]
		if not theme then return false, "Theme does not exist." end
	end
	theme = type(theme) == "table" and theme or {}
	local color1 = theme.Color1 or theme[1]
	local color2 = theme.Color2 or theme[2]
	local color3 = theme.Color3 or theme[3]
	if typeof(color1) ~= "Color3"
		or typeof(color2) ~= "Color3"
		or typeof(color3) ~= "Color3"
	then
		return false, "Theme requires three Color3 values."
	end
	Luna.ThemeGradient = ColorSequence.new({
		ColorSequenceKeypoint.new(0.00, color1),
		ColorSequenceKeypoint.new(0.50, color2),
		ColorSequenceKeypoint.new(1.00, color3),
	})
	if theme.AnimationSpeed ~= nil then Luna:SetAnimationSpeed(theme.AnimationSpeed) end
	if theme.ReducedMotion ~= nil then Luna:SetReducedMotion(theme.ReducedMotion) end
	if theme.Font ~= nil then Luna:SetFont(theme.Font) end
	if theme.Transparency ~= nil then Luna:SetComponentTransparency(theme.Transparency) end
	if theme.UIScale ~= nil then
		Luna.UIScale = math.clamp(tonumber(theme.UIScale) or 1, 0.65, 1.5)
		for window in pairs(Luna._Windows) do
			if type(window.SetUIScale) == "function" then window:SetUIScale(Luna.UIScale) end
		end
	end
	if theme.Density ~= nil then
		Luna.CurrentDensity = tostring(theme.Density)
		for window in pairs(Luna._Windows) do
			if type(window.SetDensity) == "function" then window:SetDensity(theme.Density) end
		end
	end
	LunaUI.ThemeRemote.Value = not LunaUI.ThemeRemote.Value
	EmitEvent("ThemeChanged", themeName, DeepCopy(theme))
	return true, themeName or "Custom"
end

Luna:RegisterTheme("Nightlight Neo", {
	Color1 = Color3.fromRGB(117, 164, 206),
	Color2 = Color3.fromRGB(123, 201, 201),
	Color3 = Color3.fromRGB(224, 138, 175),
})
Luna:RegisterTheme("Starlight", {
	Color1 = Color3.fromRGB(147, 255, 239),
	Color2 = Color3.fromRGB(181, 206, 241),
	Color3 = Color3.fromRGB(214, 158, 243),
})
Luna:RegisterTheme("Solar", {
	Color1 = Color3.fromRGB(242, 157, 76),
	Color2 = Color3.fromRGB(240, 179, 81),
	Color3 = Color3.fromRGB(238, 201, 86),
})

local LegacyKeyGate = Main:FindFirstChild("KeySystem")
if LegacyKeyGate then
	LegacyKeyGate:Destroy()
end

-- Legacy configuration code removed. JSON config v5 is defined below.

local function Draggable(Bar, Window, enableTaptic, tapticOffset)
	if not Bar or not Window then return function() end end
	if Bar:GetAttribute("LunaDraggableConnected") then return function() end end
	Bar:SetAttribute("LunaDraggableConnected", true)
	local connections = {}
	local Dragging = false
	local DragInput
	local MousePos
	local FramePos
	local inputEndedConnection

	if not Bar or not Window then
		return function() end
	end

	if dragBar and enableTaptic then
		TrackConnection(dragBar.MouseEnter:Connect(function()
			if not Dragging and dragBarCosmetic then
				TweenService:Create(dragBarCosmetic, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
					BackgroundTransparency = 0.5,
					Size = UDim2.new(0, 120, 0, 4)
				}):Play()
			end
		end), connections)

		TrackConnection(dragBar.MouseLeave:Connect(function()
			if not Dragging and dragBarCosmetic then
				TweenService:Create(dragBarCosmetic, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
					BackgroundTransparency = 0.7,
					Size = UDim2.new(0, 100, 0, 4)
				}):Play()
			end
		end), connections)
	end

	TrackConnection(Bar.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end

		Dragging = true
		MousePos = input.Position
		FramePos = Window.Position

		if enableTaptic and dragBarCosmetic then
			TweenService:Create(dragBarCosmetic, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Size = UDim2.new(0, 110, 0, 4),
				BackgroundTransparency = 0
			}):Play()
		end

		if inputEndedConnection then
			pcall(function() inputEndedConnection:Disconnect() end)
		end
		inputEndedConnection = TrackConnection(input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then
				Dragging = false
				if enableTaptic and dragBarCosmetic then
					TweenService:Create(dragBarCosmetic, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
						Size = UDim2.new(0, 100, 0, 4),
						BackgroundTransparency = 0.7
					}):Play()
				end
			end
		end), connections)
	end), connections)

	TrackConnection(Bar.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			DragInput = input
		end
	end), connections)

	TrackConnection(UserInputService.InputChanged:Connect(function(input)
		if input ~= DragInput or not Dragging or not MousePos or not FramePos then
			return
		end

		local delta = input.Position - MousePos
		local newPosition = UDim2.new(
			FramePos.X.Scale,
			FramePos.X.Offset + delta.X,
			FramePos.Y.Scale,
			FramePos.Y.Offset + delta.Y
		)
		Window.Position = newPosition

		if dragBar then
			dragBar.Position = UDim2.new(
				FramePos.X.Scale,
				FramePos.X.Offset + delta.X,
				FramePos.Y.Scale,
				FramePos.Y.Offset + delta.Y + (tonumber(tapticOffset) or 240)
			)
		end
	end), connections)

	local function cleanup()
		Dragging = false
		pcall(function() Bar:SetAttribute("LunaDraggableConnected", nil) end)
		DisconnectConnections(connections)
	end
	AddCleanup(cleanup)
	return cleanup
end

local function RemoveNotificationRecord(record)
	local index = table.find(Luna._NotificationQueue, record)
	if index then
		table.remove(Luna._NotificationQueue, index)
	end
	Luna._Stats.ActiveNotifications = #Luna._NotificationQueue
end

local function CloseNotificationRecord(record, immediate)
	if not record or record.Closed then return end
	record.Closed = true
	RemoveNotificationRecord(record)
	if record.Id and Luna._NotificationById[record.Id] == record.Handle then
		Luna._NotificationById[record.Id] = nil
	end
	if record.Handle then record.Handle.Closed = true end
	EmitEvent("NotificationClosed", record.Handle, immediate == true)

	local notification = record.Object
	if record.CleanupBlur then
		pcall(record.CleanupBlur)
		record.CleanupBlur = nil
	end
	DisconnectConnections(record.Connections)

	if not notification or not notification.Parent then return end

	if immediate then
		notification.Visible = false
		pcall(function() notification:Destroy() end)
		return
	end

	pcall(function()
		notification.Icon.Visible = false
		TweenService:Create(notification, TweenInfo.new(0.25, Enum.EasingStyle.Exponential), {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, -90, 0, 0),
		}):Play()
		TweenService:Create(notification.UIStroke, TweenInfo.new(0.2, Enum.EasingStyle.Exponential), {
			Transparency = 1,
		}):Play()
		TweenService:Create(notification.Shadow, TweenInfo.new(0.2, Enum.EasingStyle.Exponential), {
			ImageTransparency = 1,
		}):Play()
		TweenService:Create(notification.Title, TweenInfo.new(0.2, Enum.EasingStyle.Exponential), {
			TextTransparency = 1,
		}):Play()
		TweenService:Create(notification.Description, TweenInfo.new(0.2, Enum.EasingStyle.Exponential), {
			TextTransparency = 1,
		}):Play()
	end)

	task.delay(0.3, function()
		if notification and notification.Parent then
			notification.Visible = false
			pcall(function() notification:Destroy() end)
		end
	end)
end

function Luna:SetMaxNotifications(value)
	local maximum = math.max(1, math.floor(tonumber(value) or 3))
	Luna.MaxNotifications = maximum

	while #Luna._NotificationQueue > maximum do
		CloseNotificationRecord(Luna._NotificationQueue[1], true)
	end

	return maximum
end

function Luna:SetStrictConfig(enabled)
	Luna.StrictConfig = enabled == true
	return Luna.StrictConfig
end

function Luna:SetNotificationBlurEnabled(enabled)
	Luna.NotificationBlurEnabled = enabled == true
	return Luna.NotificationBlurEnabled
end

function Luna:SetWindowBlurEnabled(enabled)
	Luna.WindowBlurEnabled = enabled ~= false
	return Luna.WindowBlurEnabled
end

function Luna:ClearNotifications()
	while #Luna._NotificationQueue > 0 do
		CloseNotificationRecord(Luna._NotificationQueue[1], true)
	end
	return true
end

function Luna:GetNotificationHistory()
	return DeepCopy(Luna._NotificationHistory)
end

function Luna:ClearNotificationHistory()
	table.clear(Luna._NotificationHistory)
	EmitEvent("NotificationHistoryCleared")
	return true
end

function Luna:GetNotification(id)
	return Luna._NotificationById[tostring(id or "")]
end

function Luna:SetMaxNotificationHistory(value)
	Luna.MaxNotificationHistory = math.max(1, math.floor(tonumber(value) or 50))
	while #Luna._NotificationHistory > Luna.MaxNotificationHistory do
		table.remove(Luna._NotificationHistory, 1)
	end
	return Luna.MaxNotificationHistory
end

function Luna:UpdateNotification(id, data)
	local notification = self:GetNotification(id)
	if not notification then return false, "Notification does not exist." end
	notification:Update(data)
	return true, notification
end

function Luna:Notification(data) -- rich notification with actions, progress and update handles
	if Luna._Destroyed then return nil end
	data = Kwargify({
		Id = nil,
		GroupKey = nil,
		Title = "Missing Title",
		Content = "Missing or Unknown Content",
		Icon = "view_in_ar",
		ImageSource = "Material",
		Duration = nil,
		Persistent = false,
		PauseOnHover = true,
		SwipeToDismiss = true,
		Progress = nil,
		Actions = nil,
		Blur = Luna.NotificationBlurEnabled,
	}, ShallowCopy(data or {}))

	local notificationId = data.Id and tostring(data.Id) or nil
	local groupKey = data.GroupKey and tostring(data.GroupKey) or nil
	if notificationId and Luna._NotificationById[notificationId] then
		local existing = Luna._NotificationById[notificationId]
		existing:Update(data)
		return existing
	end
	if groupKey then
		for _, existing in pairs(Luna._NotificationById) do
			if existing and not existing.Closed and existing.GroupKey == groupKey then
				existing:Update(data)
				return existing
			end
		end
	end

	Luna._Stats.NotificationsCreated += 1
	local handle = {
		Id = notificationId,
		GroupKey = groupKey,
		Closed = false,
		Ready = false,
		Data = data,
		_Record = nil,
	}

	local historyItem = {
		Id = notificationId,
		GroupKey = groupKey,
		Title = tostring(data.Title),
		Content = tostring(data.Content),
		CreatedAt = os.time(),
		Progress = tonumber(data.Progress),
		Persistent = data.Persistent == true,
	}
	table.insert(Luna._NotificationHistory, historyItem)
	while #Luna._NotificationHistory > math.max(1, tonumber(Luna.MaxNotificationHistory) or 50) do
		table.remove(Luna._NotificationHistory, 1)
	end

	function handle:Close(immediate)
		if self.Closed then return false end
		self.Closed = true
		if self.Id and Luna._NotificationById[self.Id] == self then Luna._NotificationById[self.Id] = nil end
		if self._Record then CloseNotificationRecord(self._Record, immediate == true) end
		return true
	end

	function handle:SetTitle(value)
		self.Data.Title = tostring(value or "")
		if self._Record and self._Record.Object and self._Record.Object.Parent then
			self._Record.Object.Title.Text = self.Data.Title
		end
		return self
	end

	function handle:SetContent(value)
		self.Data.Content = tostring(value or "")
		if self._Record and self._Record.Object and self._Record.Object.Parent then
			self._Record.Object.Description.Text = self.Data.Content
		end
		return self
	end

	function handle:SetProgress(value)
		if value == nil then
			self.Data.Progress = nil
		else
			value = tonumber(value) or 0
			if value > 1 then value = value / 100 end
			self.Data.Progress = math.clamp(value, 0, 1)
		end
		local record = self._Record
		if record and record.ProgressTrack and record.ProgressTrack.Parent then
			record.ProgressTrack.Visible = self.Data.Progress ~= nil
			record.ProgressFill.Size = UDim2.fromScale(self.Data.Progress or 0, 1)
		end
		return self
	end

	function handle:Update(nextData)
		if self.Closed then return self end
		nextData = type(nextData) == "table" and nextData or {}
		for key, value in pairs(nextData) do self.Data[key] = value end
		if nextData.Title ~= nil then self:SetTitle(nextData.Title) end
		if nextData.Content ~= nil then self:SetContent(nextData.Content) end
		if nextData.Progress ~= nil then self:SetProgress(nextData.Progress) end
		local record = self._Record
		if record and record.Object and record.Object.Parent then
			if nextData.Icon ~= nil or nextData.ImageSource ~= nil then
				ApplyIcon(record.Object.Icon, self.Data.Icon, self.Data.ImageSource)
			end
		end
		EmitEvent("NotificationUpdated", self, nextData)
		return self
	end

	if notificationId then Luna._NotificationById[notificationId] = handle end
	if groupKey and not notificationId then
		local generatedId = "group:" .. groupKey
		handle.Id = generatedId
		Luna._NotificationById[generatedId] = handle
	end

	task.spawn(function()
		if Luna._Destroyed or handle.Closed then return end
		local maximum = math.max(1, math.floor(tonumber(data.MaxNotifications or Luna.MaxNotifications) or 3))
		while #Luna._NotificationQueue >= maximum do
			CloseNotificationRecord(Luna._NotificationQueue[1], true)
		end

		local newNotification = Notifications.Template:Clone()
		newNotification.Name = tostring(data.Title)
		newNotification.Parent = Notifications
		newNotification.LayoutOrder = Luna._Stats.NotificationsCreated
		newNotification.Visible = false

		local record = {
			Id = handle.Id,
			Handle = handle,
			Connections = {},
			Object = newNotification,
			Closed = false,
			CleanupBlur = data.Blur == true and BlurModule(newNotification) or nil,
		}
		handle._Record = record
		handle.Ready = true
		table.insert(Luna._NotificationQueue, record)
		Luna._Stats.ActiveNotifications = #Luna._NotificationQueue

		local function isAlive()
			return not record.Closed and not handle.Closed and not Luna._Destroyed and newNotification and newNotification.Parent ~= nil
		end

		newNotification.Title.Text = tostring(data.Title)
		newNotification.Description.Text = tostring(data.Content)
		ApplyIcon(newNotification.Icon, data.Icon, data.ImageSource)
		newNotification.BackgroundTransparency = 1
		newNotification.Title.TextTransparency = 1
		newNotification.Description.TextTransparency = 1
		newNotification.UIStroke.Transparency = 1
		newNotification.Shadow.ImageTransparency = 1
		newNotification.Icon.ImageTransparency = 1
		newNotification.Icon.BackgroundTransparency = 1
		newNotification.Active = true

		local extraHeight = 0
		local progressTrack
		local progressFill
		if data.Progress ~= nil then
			progressTrack = Instance.new("Frame")
			progressTrack.Name = "ProgressTrack"
			progressTrack.BackgroundColor3 = Color3.fromRGB(25, 24, 30)
			progressTrack.BackgroundTransparency = 0.1
			progressTrack.BorderSizePixel = 0
			progressTrack.AnchorPoint = Vector2.new(0, 1)
			progressTrack.Position = UDim2.new(0, 16, 1, -10)
			progressTrack.Size = UDim2.new(1, -32, 0, 5)
			progressTrack.ZIndex = newNotification.ZIndex + 2
			progressTrack.Parent = newNotification
			CreateCorner(progressTrack, 3)
			progressFill = Instance.new("Frame")
			progressFill.Name = "Fill"
			progressFill.BackgroundColor3 = Color3.fromRGB(130, 175, 215)
			progressFill.BorderSizePixel = 0
			progressFill.Size = UDim2.fromScale(0, 1)
			progressFill.ZIndex = progressTrack.ZIndex + 1
			progressFill.Parent = progressTrack
			CreateCorner(progressFill, 3)
			local gradient = Instance.new("UIGradient")
			gradient.Color = Luna.ThemeGradient
			gradient.Parent = progressFill
			record.ProgressTrack = progressTrack
			record.ProgressFill = progressFill
			extraHeight += 14
			handle:SetProgress(data.Progress)
		end

		local actionFrame
		if type(data.Actions) == "table" and #data.Actions > 0 then
			actionFrame = Instance.new("Frame")
			actionFrame.Name = "Actions"
			actionFrame.BackgroundTransparency = 1
			actionFrame.AnchorPoint = Vector2.new(0, 1)
			actionFrame.Position = UDim2.new(0, 16, 1, -(progressTrack and 22 or 10))
			actionFrame.Size = UDim2.new(1, -32, 0, 30)
			actionFrame.ZIndex = newNotification.ZIndex + 2
			actionFrame.Parent = newNotification
			local actionLayout = Instance.new("UIListLayout")
			actionLayout.FillDirection = Enum.FillDirection.Horizontal
			actionLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
			actionLayout.VerticalAlignment = Enum.VerticalAlignment.Center
			actionLayout.Padding = UDim.new(0, 6)
			actionLayout.Parent = actionFrame
			for index, action in ipairs(data.Actions) do
				action = type(action) == "table" and action or {Text = tostring(action)}
				local button = Instance.new("TextButton")
				button.Name = tostring(action.Id or action.Text or index)
				button.AutoButtonColor = false
				button.BackgroundColor3 = action.Primary and Color3.fromRGB(74, 100, 136) or Color3.fromRGB(45, 43, 53)
				button.BackgroundTransparency = 0.12
				button.BorderSizePixel = 0
				button.Font = Enum.Font.GothamSemibold
				button.Text = tostring(action.Text or "Action")
				button.TextColor3 = ProductivityColors.Text
				button.TextSize = 10
				button.Size = UDim2.fromOffset(math.max(64, #button.Text * 7 + 20), 28)
				button.ZIndex = actionFrame.ZIndex + 1
				button.Parent = actionFrame
				CreateCorner(button, 6)
				TrackConnection(button.MouseButton1Click:Connect(function()
					if type(action.Callback) == "function" then SafeCall(action.Callback, handle, action) end
					EmitEvent("NotificationAction", handle, action)
					if action.Close ~= false then handle:Close(false) end
				end), record.Connections)
			end
			extraHeight += 36
		end

		task.wait()
		if not isAlive() then return end
		local layout = Notifications:FindFirstChild("UIListLayout")
		local padding = layout and layout.Padding.Offset or 0
		newNotification.Size = UDim2.new(1, 0, 0, -padding)
		newNotification.Icon.Size = UDim2.new(0, 28, 0, 28)
		newNotification.Icon.Position = UDim2.new(0, 16, 0, 28)
		newNotification.Visible = true
		newNotification.Description.Size = UDim2.new(1, -65, 0, math.huge)
		local bounds = newNotification.Description.TextBounds.Y + 55 + extraHeight
		newNotification.Description.Size = UDim2.new(1, -65, 0, math.max(20, bounds - 35 - extraHeight))
		newNotification.Size = UDim2.new(1, 0, 0, -padding)

		TweenService:Create(newNotification, ScaleTweenInfo(TweenInfo.new(0.6, Enum.EasingStyle.Exponential)), {
			Size = UDim2.new(1, 0, 0, bounds),
		}):Play()
		task.wait(Luna.ReducedMotion and 0 or 0.15)
		if not isAlive() then return end
		TweenService:Create(newNotification, ScaleTweenInfo(TweenInfo.new(0.4, Enum.EasingStyle.Exponential)), {BackgroundTransparency = 0.45}):Play()
		TweenService:Create(newNotification.Title, ScaleTweenInfo(TweenInfo.new(0.3, Enum.EasingStyle.Exponential)), {TextTransparency = 0}):Play()
		TweenService:Create(newNotification.Icon, ScaleTweenInfo(TweenInfo.new(0.3, Enum.EasingStyle.Exponential)), {ImageTransparency = 0}):Play()
		TweenService:Create(newNotification.Description, ScaleTweenInfo(TweenInfo.new(0.3, Enum.EasingStyle.Exponential)), {TextTransparency = 0.35}):Play()
		TweenService:Create(newNotification.UIStroke, ScaleTweenInfo(TweenInfo.new(0.4, Enum.EasingStyle.Exponential)), {Transparency = 0.95}):Play()
		TweenService:Create(newNotification.Shadow, ScaleTweenInfo(TweenInfo.new(0.3, Enum.EasingStyle.Exponential)), {ImageTransparency = 0.82}):Play()

		local hovered = false
		TrackConnection(newNotification.MouseEnter:Connect(function() hovered = true end), record.Connections)
		TrackConnection(newNotification.MouseLeave:Connect(function() hovered = false end), record.Connections)

		if data.SwipeToDismiss ~= false then
			local touchStart
			TrackConnection(newNotification.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.Touch then touchStart = input.Position end
			end), record.Connections)
			TrackConnection(newNotification.InputEnded:Connect(function(input)
				if touchStart and input.UserInputType == Enum.UserInputType.Touch then
					if math.abs(input.Position.X - touchStart.X) >= 80 then handle:Close(false) end
					touchStart = nil
				end
			end), record.Connections)
		end

		EmitEvent("NotificationCreated", handle, data)
		if data.Persistent == true then return end
		local waitDuration = math.min(math.max((#newNotification.Description.Text * 0.1) + 2.5, 3), 10)
		local remaining = math.max(0.1, tonumber(data.Duration) or waitDuration)
		while remaining > 0 and isAlive() do
			local step = math.min(0.1, remaining)
			task.wait(step)
			if not (data.PauseOnHover ~= false and hovered) then remaining -= step end
		end
		if isAlive() then handle:Close(false) end
	end)
	return handle
end

local function Unhide(Window, currentTab)
	if not Window then
		return false
	end

	local saved = SavedWindowVisibilityState[Window]
	if saved and saved.Size then
		Window.Size = saved.Size
	end

	Window.Visible = true
	Window.Elements.Visible =
		not saved or saved.ElementsVisible ~= false
	Window.Navigation.Visible =
		not saved or saved.NavigationVisible ~= false

	local parent = Window.Parent
	local shadowHolder = parent and parent:FindFirstChild("ShadowHolder")
	if shadowHolder then
		shadowHolder.Visible = true
	end

	-- Restore every visual property synchronously. This cancels the old
	-- delayed hide behavior and keeps the final state deterministic.
	Window.BackgroundTransparency = 0.2
	Window.Elements.BackgroundTransparency = 0.08
	Window.Line.BackgroundTransparency = 0
	Window.Title.Title.TextTransparency = 0
	Window.Title.subtitle.TextTransparency = 0
	Window.Logo.ImageTransparency = 0
	Window.Navigation.Line.BackgroundTransparency = 0

	for _, TopbarButton in ipairs(Window.Controls:GetChildren()) do
		if TopbarButton.ClassName == "Frame" and TopbarButton.Name ~= "Theme" then
			TopbarButton.Visible = true
			TopbarButton.BackgroundTransparency = 0.25
			if TopbarButton:FindFirstChild("UIStroke") then
				TopbarButton.UIStroke.Transparency = 0.5
			end
			if TopbarButton:FindFirstChild("ImageLabel") then
				TopbarButton.ImageLabel.ImageTransparency = 0.25
			end
		end
	end

	for _, tabbtn in ipairs(Window.Navigation.Tabs:GetChildren()) do
		if tabbtn.ClassName == "Frame" and tabbtn.Name ~= "InActive Template" then
			local active = tabbtn.Name == currentTab
			tabbtn.BackgroundTransparency = active and 0 or 1
			if tabbtn:FindFirstChild("UIStroke") then
				tabbtn.UIStroke.Transparency = active and 0.41 or 1
			end
			if tabbtn:FindFirstChild("ImageLabel") then
				tabbtn.ImageLabel.ImageTransparency = 0
			end
			local tabShadowHolder = tabbtn:FindFirstChild("DropShadowHolder")
			local shadow = tabShadowHolder and tabShadowHolder:FindFirstChild("DropShadow")
			if shadow then
				shadow.ImageTransparency = 1
			end
		end
	end

	return true
end

local MainSize
local MinSize

local function CalculateWindowSizes()
	local currentCamera = GetCurrentCamera()
	local viewport = currentCamera and currentCamera.ViewportSize
		or Vector2.new(800, 600)

	if viewport.X > 774 and viewport.Y > 503 then
		MainSize = UDim2.fromOffset(675, 424)
		MinSize = UDim2.fromOffset(500, 42)
	else
		MainSize = UDim2.fromOffset(
			math.max(320, viewport.X - 40),
			math.max(260, viewport.Y - 70)
		)
		MinSize = UDim2.fromOffset(math.max(260, viewport.X - 160), 42)
	end
	return MainSize, MinSize
end

CalculateWindowSizes()

local function Maximise(Window)
	Window.Controls.ToggleSize.ImageLabel.Image = "rbxassetid://10137941941"
	Window.Size = MainSize
	Window.Elements.Visible = true
	Window.Navigation.Visible = true
	return true
end

local function Minimize(Window)
	Window.Controls.ToggleSize.ImageLabel.Image = "rbxassetid://11036884234"
	Window.Elements.Visible = false
	Window.Navigation.Visible = false
	Window.Size = MinSize
	return true
end


function Luna:CreateWindow(WindowSettings)

	WindowSettings = Kwargify({
		Name = "Luna UI Example Window",
		Subtitle = "",
		LogoID = "6031097225",
		LoadingEnabled = true,
		LoadingDuration = 1.2,
		LoadingTitle = "Luna Interface Suite",
		LoadingSubtitle = "by Nebula Softworks",
		BlurEnabled = Luna.WindowBlurEnabled,

		ConfigSettings = {},
		MinimizeSettings = {},
		StatusDisplay = {},
	}, WindowSettings or {})

	WindowSettings.ConfigSettings = Kwargify({
		RootFolder = nil,
		ConfigFolder = "Big Hub",
	}, WindowSettings.ConfigSettings or {})

	WindowSettings.MinimizeSettings = Kwargify({
		Enabled = true,
		Keybind = Enum.KeyCode.RightShift,
		ShowNotification = true,
		NotificationCooldown = 1.5,
	}, WindowSettings.MinimizeSettings or {})

	WindowSettings.StatusDisplay = Kwargify({
		Enabled = true,
		ShowFPS = true,
		ShowClock = true,
		ShowSeconds = false,
		ClockFormat = "24h",
		UpdateInterval = 0.5,
		Separator = "  •  ",
	}, WindowSettings.StatusDisplay or {})

	if WindowSettings.ConfigSettings.RootFolder ~= nil and WindowSettings.ConfigSettings.RootFolder ~= "" then
		Luna.Folder = tostring(WindowSettings.ConfigSettings.RootFolder) .. "/" .. tostring(WindowSettings.ConfigSettings.ConfigFolder)
	else
		Luna.Folder = tostring(WindowSettings.ConfigSettings.ConfigFolder)
	end

	local minimizeBinding, minimizeBindingError = NormalizeInputBinding(
		WindowSettings.MinimizeSettings.Keybind,
		Enum.KeyCode.RightShift
	)

	if not minimizeBinding then
		warn("Luna UI: " .. tostring(minimizeBindingError) .. " Falling back to RightShift.")
		minimizeBinding = NormalizeInputBinding(Enum.KeyCode.RightShift)
	end

	local Window = {
		Bind = minimizeBinding.EnumItem,
		MinimizeBind = minimizeBinding,
		MinimizeEnabled = WindowSettings.MinimizeSettings.Enabled ~= false,
		MinimizeShowNotification = WindowSettings.MinimizeSettings.ShowNotification ~= false,
		MinimizeNotificationCooldown = math.max(
			0,
			tonumber(WindowSettings.MinimizeSettings.NotificationCooldown) or 1.5
		),
		CurrentTab = nil,
		State = true,
		Size = false,
		Settings = nil,
		CurrentFPS = 0,
		StatusDisplaySettings = WindowSettings.StatusDisplay,
	}

	-- Extra topbar hide button. The existing square button keeps the compact/minimize action,
	-- while this minus button hides the whole interface and allows reopening with the UI bind.
	local HideControl = Main.Controls:FindFirstChild("Hide")
	if not HideControl then
		local ToggleTemplate = Main.Controls:FindFirstChild("ToggleSize")
		if ToggleTemplate then
			HideControl = ToggleTemplate:Clone()
			HideControl.Name = "Hide"
			HideControl.LayoutOrder = ToggleTemplate.LayoutOrder - 1

			-- Position fallback for assets that do not use a UIListLayout.
			local templatePosition = ToggleTemplate.Position
			local templateSize = ToggleTemplate.Size
			HideControl.Position = UDim2.new(
				templatePosition.X.Scale - templateSize.X.Scale,
				templatePosition.X.Offset - templateSize.X.Offset - 6,
				templatePosition.Y.Scale,
				templatePosition.Y.Offset
			)
			HideControl.Parent = Main.Controls

			local clickTarget = HideControl:FindFirstChild("ImageLabel")
			if clickTarget and (clickTarget:IsA("ImageButton") or clickTarget:IsA("ImageLabel")) then
				-- A text glyph is used so the minus remains visible even if an image asset fails.
				clickTarget.Image = ""
				clickTarget.ImageRectSize = Vector2.zero
				clickTarget.ImageRectOffset = Vector2.zero
				clickTarget.ImageTransparency = 1

				local glyph = Instance.new("TextLabel")
				glyph.Name = "MinusGlyph"
				glyph.BackgroundTransparency = 1
				glyph.Size = UDim2.fromScale(1, 1)
				glyph.Position = UDim2.fromScale(0, 0)
				glyph.Font = Enum.Font.GothamBold
				glyph.Text = "−"
				glyph.TextColor3 = Color3.fromRGB(195, 195, 195)
				glyph.TextSize = 20
				glyph.TextScaled = false
				glyph.TextXAlignment = Enum.TextXAlignment.Center
				glyph.TextYAlignment = Enum.TextYAlignment.Center
				glyph.Active = false
				glyph.Selectable = false
				glyph.ZIndex = clickTarget.ZIndex + 1
				glyph.Parent = clickTarget
			end
		end
	end
	Window.HideControl = HideControl

	-- Lightweight topbar FPS and local clock display. FPS is averaged over the
	-- selected update interval so the number stays readable instead of jumping
	-- every rendered frame. The clock uses the executor/device local time.
	local StatusDisplay = Main:FindFirstChild("LunaStatusDisplay")
	if StatusDisplay then
		StatusDisplay:Destroy()
	end
	StatusDisplay = Main.Title.subtitle:Clone()
	StatusDisplay.Name = "LunaStatusDisplay"
	StatusDisplay.BackgroundTransparency = 1
	StatusDisplay.AnchorPoint = Vector2.new(1, 0.5)
	StatusDisplay.Position = UDim2.fromOffset(0, 0)
	StatusDisplay.Size = UDim2.fromOffset(150, 18)
	StatusDisplay.Text = ""
	StatusDisplay.TextXAlignment = Enum.TextXAlignment.Right
	StatusDisplay.TextYAlignment = Enum.TextYAlignment.Center
	StatusDisplay.TextTruncate = Enum.TextTruncate.AtEnd
	StatusDisplay.TextWrapped = false
	StatusDisplay.TextSize = 11
	StatusDisplay.Active = false
	StatusDisplay.Selectable = false
	-- Main.Controls / Control is a Folder in the current Luna asset, so it has no ZIndex.
	-- Read the layer only from real GuiObjects and keep a safe fallback.
	local statusBaseZIndex = 1
	local statusSubtitle = Main:FindFirstChild("Title")
		and Main.Title:FindFirstChild("subtitle")
	if statusSubtitle and statusSubtitle:IsA("GuiObject") then
		statusBaseZIndex = statusSubtitle.ZIndex
	elseif Main:IsA("GuiObject") then
		statusBaseZIndex = Main.ZIndex
	end
	StatusDisplay.ZIndex = math.max(20, statusBaseZIndex + 1)
	StatusDisplay.TextTransparency = 1
	StatusDisplay.Visible = WindowSettings.StatusDisplay.Enabled ~= false
	StatusDisplay.Parent = Main
	Window.StatusDisplay = StatusDisplay

	local statusFrameCount = 0
	local statusElapsed = 0
	local statusLastClock = "--:--"
	local statusHasRoom = true

	local function GetRenderedTextRight(textObject, mainLeft)
		if not textObject or not textObject:IsA("TextLabel") then
			return 0
		end
		local relativeLeft = textObject.AbsolutePosition.X - mainLeft
		local renderedWidth = tonumber(textObject.TextBounds.X) or 0
		if renderedWidth <= 0 then
			renderedWidth = math.min(textObject.AbsoluteSize.X, 120)
		end
		return relativeLeft + math.min(renderedWidth, textObject.AbsoluteSize.X)
	end

	local function GetTopbarControlAnchor(mainLeft, mainTop, mainWidth)
		local leftEdge = math.huge
		local centerY
		for _, control in ipairs(Main.Controls:GetChildren()) do
			if control:IsA("GuiObject")
				and control.Name ~= "Theme"
				and control.AbsoluteSize.X > 0
				and control.AbsoluteSize.Y > 0
			then
				local relativeLeft = control.AbsolutePosition.X - mainLeft
				-- Ignore malformed/off-window controls, but visibility is intentionally
				-- not required because controls are hidden during the loading animation.
				if relativeLeft >= 0 and relativeLeft <= mainWidth then
					if relativeLeft < leftEdge then
						leftEdge = relativeLeft
						centerY = control.AbsolutePosition.Y - mainTop
							+ (control.AbsoluteSize.Y * 0.5)
					end
				end
			end
		end

		if leftEdge == math.huge then
			leftEdge = mainWidth - 116
		end
		if not centerY then
			local separator = Main:FindFirstChild("Line")
			if separator and separator:IsA("GuiObject") then
				centerY = math.max(16, (separator.AbsolutePosition.Y - mainTop) * 0.5)
			else
				centerY = 23
			end
		end
		return leftEdge, centerY
	end

	local function RefreshStatusLayout()
		if not StatusDisplay or not StatusDisplay.Parent then return end
		local mainWidth = math.max(0, Main.AbsoluteSize.X)
		local mainLeft = Main.AbsolutePosition.X
		local mainTop = Main.AbsolutePosition.Y
		local controlLeft, controlCenterY = GetTopbarControlAnchor(mainLeft, mainTop, mainWidth)

		-- Keep the status on the same horizontal line as the topbar controls and
		-- stop it before the left-most minimize/hide/close button.
		local rightEdge = math.clamp(controlLeft - 8, 0, math.max(0, mainWidth - 8))
		local titleRight = 72
		if Main:FindFirstChild("Title") then
			titleRight = math.max(
				titleRight,
				GetRenderedTextRight(Main.Title:FindFirstChild("Title"), mainLeft),
				GetRenderedTextRight(Main.Title:FindFirstChild("subtitle"), mainLeft)
			)
		end
		local availableWidth = rightEdge - titleRight - 12
		statusHasRoom = availableWidth >= 72
		local width = math.clamp(availableWidth, 72, 190)

		StatusDisplay.Position = UDim2.fromOffset(rightEdge, controlCenterY)
		StatusDisplay.Size = UDim2.fromOffset(width, 18)
		StatusDisplay.TextSize = mainWidth < 440 and 10 or 11
	end

	local function FormatStatusClock()
		local statusSettings = Window.StatusDisplaySettings
		local use12Hour = tostring(statusSettings.ClockFormat or "24h"):lower() == "12h"
		local showSeconds = statusSettings.ShowSeconds == true
		local format
		if use12Hour then
			format = showSeconds and "%I:%M:%S %p" or "%I:%M %p"
		else
			format = showSeconds and "%H:%M:%S" or "%H:%M"
		end
		local success, clockText = pcall(os.date, format)
		if not success or type(clockText) ~= "string" or clockText == "" then
			return "--:--"
		end
		if use12Hour then
			clockText = clockText:gsub("^0", "")
		end
		return clockText
	end

	local function RefreshStatusDisplay()
		if Luna._Destroyed or not StatusDisplay or not StatusDisplay.Parent then
			return
		end
		local statusSettings = Window.StatusDisplaySettings
		local parts = {}
		if statusSettings.ShowFPS ~= false then
			table.insert(parts, (Window.CurrentFPS > 0 and tostring(Window.CurrentFPS) or "--") .. " FPS")
		end
		if statusSettings.ShowClock ~= false then
			statusLastClock = FormatStatusClock()
			table.insert(parts, statusLastClock)
		end
		StatusDisplay.Text = table.concat(parts, tostring(statusSettings.Separator or "  •  "))
		StatusDisplay.Visible = Window.State
			and statusSettings.Enabled ~= false
			and statusHasRoom
			and #parts > 0
	end

	local function ResetStatusSample()
		statusFrameCount = 0
		statusElapsed = 0
	end

	TrackConnection(RunService.RenderStepped:Connect(function(deltaTime)
		if Luna._Destroyed then return end
		statusFrameCount += 1
		statusElapsed += math.max(0, tonumber(deltaTime) or 0)
		local interval = math.max(
			0.2,
			tonumber(Window.StatusDisplaySettings.UpdateInterval) or 0.5
		)
		if statusElapsed >= interval then
			Window.CurrentFPS = math.max(0, math.floor((statusFrameCount / math.max(statusElapsed, 0.001)) + 0.5))
			ResetStatusSample()
			RefreshStatusDisplay()
		end
	end))

	TrackConnection(Main.Title.subtitle:GetPropertyChangedSignal("TextColor3"):Connect(function()
		if StatusDisplay and StatusDisplay.Parent then
			StatusDisplay.TextColor3 = Main.Title.subtitle.TextColor3
		end
	end))
	TrackConnection(Main:GetPropertyChangedSignal("AbsoluteSize"):Connect(RefreshStatusLayout))
	TrackConnection(Main:GetPropertyChangedSignal("AbsolutePosition"):Connect(RefreshStatusLayout))
	TrackConnection(Main.Title.Title:GetPropertyChangedSignal("TextBounds"):Connect(RefreshStatusLayout))
	TrackConnection(Main.Title.subtitle:GetPropertyChangedSignal("TextBounds"):Connect(RefreshStatusLayout))

	local function TrackStatusControlLayout(control)
		if not control or not control:IsA("GuiObject") then return end
		TrackConnection(control:GetPropertyChangedSignal("AbsolutePosition"):Connect(RefreshStatusLayout))
		TrackConnection(control:GetPropertyChangedSignal("AbsoluteSize"):Connect(RefreshStatusLayout))
	end
	for _, control in ipairs(Main.Controls:GetChildren()) do
		TrackStatusControlLayout(control)
	end
	TrackConnection(Main.Controls.ChildAdded:Connect(function(control)
		TrackStatusControlLayout(control)
		task.defer(RefreshStatusLayout)
	end))
	TrackConnection(Main.Controls.ChildRemoved:Connect(function()
		task.defer(RefreshStatusLayout)
	end))

	function Window:SetStatusDisplayEnabled(enabled)
		self.StatusDisplaySettings.Enabled = enabled ~= false
		RefreshStatusDisplay()
		return self.StatusDisplaySettings.Enabled
	end

	function Window:SetFPSVisible(enabled)
		self.StatusDisplaySettings.ShowFPS = enabled ~= false
		RefreshStatusDisplay()
		return self.StatusDisplaySettings.ShowFPS
	end

	function Window:SetClockVisible(enabled)
		self.StatusDisplaySettings.ShowClock = enabled ~= false
		RefreshStatusDisplay()
		return self.StatusDisplaySettings.ShowClock
	end

	function Window:SetClockFormat(format)
		format = tostring(format or "24h"):lower()
		if format ~= "12h" and format ~= "24h" then
			return false, "Clock format must be '12h' or '24h'."
		end
		self.StatusDisplaySettings.ClockFormat = format
		RefreshStatusDisplay()
		return true, format
	end

	function Window:SetClockSecondsVisible(enabled)
		self.StatusDisplaySettings.ShowSeconds = enabled == true
		RefreshStatusDisplay()
		return self.StatusDisplaySettings.ShowSeconds
	end

	function Window:SetStatusUpdateInterval(seconds)
		seconds = tonumber(seconds)
		if not seconds then
			return false, "Update interval must be a number."
		end
		self.StatusDisplaySettings.UpdateInterval = math.max(0.2, seconds)
		ResetStatusSample()
		return true, self.StatusDisplaySettings.UpdateInterval
	end

	function Window:GetFPS()
		return self.CurrentFPS
	end

	function Window:GetClockText()
		return FormatStatusClock()
	end

	RefreshStatusLayout()
	RefreshStatusDisplay()

	Main.Title.Title.Text = WindowSettings.Name
	Main.Title.subtitle.Text = WindowSettings.Subtitle
	Main.Logo.Image = "rbxassetid://" .. WindowSettings.LogoID
	task.defer(RefreshStatusLayout)
	Main.Visible = true
	Main.BackgroundTransparency = 1
	Main.Size = MainSize
	Main.Parent.ShadowHolder.Size = Main.Size
	LoadingFrame.Frame.Frame.Title.TextTransparency = 1
	LoadingFrame.Frame.Frame.Subtitle.TextTransparency = 1
	LoadingFrame.Version.TextTransparency = 1
	LoadingFrame.Frame.ImageLabel.ImageTransparency = 1

	tween(Elements.Parent, {BackgroundTransparency = 1})
	Elements.Parent.Visible = false

	LoadingFrame.Frame.Frame.Title.Text = WindowSettings.LoadingTitle
	LoadingFrame.Frame.Frame.Subtitle.Text = WindowSettings.LoadingSubtitle
	LoadingFrame.Version.Text = LoadingFrame.Frame.Frame.Title.Text == "Luna Interface Suite" and Release or "Luna UI"

	Navigation.Player.icon.ImageLabel.Image = Players:GetUserThumbnailAsync(Players.LocalPlayer.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
	Navigation.Player.Namez.Text = Players.LocalPlayer.DisplayName
	Navigation.Player.TextLabel.Text = Players.LocalPlayer.Name

	for i,v in pairs(Main.Controls:GetChildren()) do
		v.Visible = false
	end

	TrackConnection(Main:GetPropertyChangedSignal("Position"):Connect(function()
		if Main.Parent and Main.Parent:FindFirstChild("ShadowHolder") then
			Main.Parent.ShadowHolder.Position = Main.Position
		end
	end))
	TrackConnection(Main:GetPropertyChangedSignal("Size"):Connect(function()
		if Main.Parent and Main.Parent:FindFirstChild("ShadowHolder") then
			Main.Parent.ShadowHolder.Size = Main.Size
		end
	end))

	local viewportConnection
	local function ApplyViewportSize()
		CalculateWindowSizes()
		if Main and Main.Parent then
			Main.Size = Window.Size and MinSize or MainSize
		end
	end
	local function BindViewportCamera()
		if viewportConnection then
			pcall(function() viewportConnection:Disconnect() end)
			Luna._Connections[viewportConnection] = nil
			viewportConnection = nil
		end
		Camera = workspace.CurrentCamera or Camera
		if Camera then
			viewportConnection = TrackConnection(
				Camera:GetPropertyChangedSignal("ViewportSize"):Connect(ApplyViewportSize)
			)
		end
		ApplyViewportSize()
	end
	TrackConnection(
		workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(BindViewportCamera)
	)
	BindViewportCamera()

	LoadingFrame.Visible = true

	-- pcall(function()
	-- 	if not isfolder(ConfigurationFolder) then
	-- 		makefolder(ConfigurationFolder)
	-- 	end
	-- 	if WindowSettings.ConfigSettings.RootFolder then
	-- 		if not isfolder(ConfigurationFolder .. WindowSettings.ConfigSettings.RootFolder) then
	-- 			makefolder(ConfigurationFolder .. WindowSettings.ConfigSettings.RootFolder)
	-- 			if not isfolder(ConfigurationFolder .. WindowSettings.ConfigSettings.RootFolder .. WindowSettings.ConfigSettings.ConfigFolder) then
	-- 				makefolder(ConfigurationFolder .. WindowSettings.ConfigSettings.RootFolder .. WindowSettings.ConfigSettings.ConfigFolder)
	-- 			end
	-- 		end
	-- 	else
	-- 		if not isfolder(ConfigurationFolder .. WindowSettings.ConfigSettings.ConfigFolder) then
	-- 			makefolder(ConfigurationFolder .. WindowSettings.ConfigSettings.ConfigFolder)
	-- 		end
	-- 	end

	-- 	LoadAutoLoad(WindowSettings.ConfigSettings.ConfigFolder, WindowSettings.ConfigSettings.RootFolder)
	-- end)

	LunaUI.Enabled = true

	if WindowSettings.BlurEnabled ~= false then
		BlurModule(Main)
	end

	if WindowSettings.LoadingEnabled then
		task.wait(0.3)
		TweenService:Create(LoadingFrame.Frame.Frame.Title, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {TextTransparency = 0}):Play()
		TweenService:Create(LoadingFrame.Frame.ImageLabel, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {ImageTransparency = 0}):Play()
		task.wait(0.05)
		TweenService:Create(LoadingFrame.Frame.Frame.Subtitle, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {TextTransparency = 0}):Play()
		TweenService:Create(LoadingFrame.Version, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {TextTransparency = 0}):Play()
		task.wait(0.29)
		TweenService:Create(LoadingFrame.Frame.ImageLabel, TweenInfo.new(1.7, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 2, false, 0.2), {Rotation = 450}):Play()

		task.wait(math.max(0, tonumber(WindowSettings.LoadingDuration) or 1.2))

		TweenService:Create(LoadingFrame.Frame.Frame.Title, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {TextTransparency = 1}):Play()
		TweenService:Create(LoadingFrame.Frame.ImageLabel, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {ImageTransparency = 1}):Play()
		task.wait(0.05)
		TweenService:Create(LoadingFrame.Frame.Frame.Subtitle, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {TextTransparency = 1}):Play()
		TweenService:Create(LoadingFrame.Version, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {TextTransparency = 1}):Play()
		task.wait(0.3)
		TweenService:Create(LoadingFrame, TweenInfo.new(0.5, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {BackgroundTransparency = 1}):Play()
	end

	TweenService:Create(Main, TweenInfo.new(0.5, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {BackgroundTransparency = 0.2, Size = MainSize}):Play()
	TweenService:Create(Main.Parent.ShadowHolder, TweenInfo.new(0.5, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {Size = MainSize}):Play()
	TweenService:Create(Main.Title.Title, TweenInfo.new(0.35, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {TextTransparency = 0}):Play()
	TweenService:Create(Main.Title.subtitle, TweenInfo.new(0.35, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {TextTransparency = 0}):Play()
	TweenService:Create(StatusDisplay, TweenInfo.new(0.35, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {TextTransparency = 0}):Play()
	TweenService:Create(Main.Logo, TweenInfo.new(0.35, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {ImageTransparency = 0}):Play()
	TweenService:Create(Navigation.Player.icon.ImageLabel, TweenInfo.new(0.35, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {ImageTransparency = 0}):Play()
	TweenService:Create(Navigation.Player.icon.UIStroke, TweenInfo.new(0.35, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {Transparency = 0}):Play()
	TweenService:Create(Main.Line, TweenInfo.new(0.35, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {BackgroundTransparency = 0}):Play()
	task.wait(0.4)
	LoadingFrame.Visible = false

	Draggable(Dragger, Main)
	Draggable(LunaUI.MobileSupport, LunaUI.MobileSupport)
	if dragBar then Draggable(dragInteract, Main, true, 255) end

	Elements.Template.LayoutOrder = 1000000000
	Elements.Template.Visible = false
	Navigation.Tabs["InActive Template"].LayoutOrder = 1000000000
	Navigation.Tabs["InActive Template"].Visible = false

	local FirstTab = true

	function Window:CreateHomeTab(HomeTabSettings)
		HomeTabSettings = Kwargify({
			Icon = 1,
			SupportedExecutors = {"Vega X", "Delta", "Nihon", "Xeno"},
			DiscordInvite = "noinvitelink",
			RefreshInterval = 1,
			FriendsRefreshInterval = 30,
		}, HomeTabSettings or {})

		local HomeTab = {}
		local homeConnections = {}
		local alive = true
		local HomeTabButton = Navigation.Tabs.Home
		local HomeTabPage = Elements.Home

		HomeTabButton.Visible = true
		HomeTabPage.Visible = true
		if HomeTabSettings.Icon == 2 then
			ApplyIcon(HomeTabButton.ImageLabel, "dashboard", "Material")
		end

		function HomeTab:Activate()
			if not alive or Luna._Destroyed then return end
			tween(HomeTabButton.ImageLabel, {ImageColor3 = Color3.fromRGB(255,255,255)})
			tween(HomeTabButton, {BackgroundTransparency = 0})
			tween(HomeTabButton.UIStroke, {Transparency = 0.41})
			Elements.UIPageLayout:JumpTo(HomeTabPage)
			task.wait(0.05)
			for _, other in ipairs(Navigation.Tabs:GetChildren()) do
				if other.Name ~= "InActive Template" and other.ClassName == "Frame" and other ~= HomeTabButton then
					tween(other.ImageLabel, {ImageColor3 = Color3.fromRGB(221,221,221)})
					tween(other, {BackgroundTransparency = 1})
					tween(other.UIStroke, {Transparency = 1})
				end
			end
			Window.CurrentTab = "Home"
		end

		HomeTab:Activate()
		FirstTab = false
		TrackConnection(HomeTabButton.Interact.MouseButton1Click:Connect(function()
			HomeTab:Activate()
		end), homeConnections)

		local thumbnailSuccess, thumbnail = pcall(Players.GetUserThumbnailAsync, Players, Player.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size420x420)
		if thumbnailSuccess then HomeTabPage.icon.ImageLabel.Image = thumbnail end
		HomeTabPage.player.Text.Text = "Hello, " .. Player.DisplayName
		HomeTabPage.player.user.Text = Player.Name .. " - " .. WindowSettings.Name

		local executorName = "Unknown Executor"
		if type(identifyexecutor) == "function" then
			local success, result = pcall(identifyexecutor)
			if success and result then executorName = tostring(result) end
		end
		HomeTabPage.detailsholder.dashboard.Client.Title.Text = executorName
		local executorSupported = table.find(HomeTabSettings.SupportedExecutors, executorName) ~= nil
		HomeTabPage.detailsholder.dashboard.Client.Subtitle.Text = executorSupported
			and "Your Executor Supports This Script."
			or "Your Executor Isn't Officially Supported By This Script."

		local function homeNotification(title, content, icon)
			Luna:Notification({
				Title = tostring(title),
				Content = tostring(content),
				Icon = icon or "content_copy",
				ImageSource = "Material",
				Duration = 4,
			})
		end

		local function copyHomeText(text, successTitle, successContent)
			text = tostring(text or "")
			if text == "" then
				homeNotification(
					"Nothing to copy",
					"The requested content is empty.",
					"error_outline"
				)
				return false
			end

			local clipboardFunctions = {}

			if type(setclipboard) == "function" then
				table.insert(clipboardFunctions, setclipboard)
			end

			if type(toclipboard) == "function" then
				table.insert(clipboardFunctions, toclipboard)
			end

			for _, clipboardFunction in ipairs(clipboardFunctions) do
				local success = pcall(clipboardFunction, text)

				if success then
					homeNotification(
						successTitle or "Copied",
						successContent or "Copied to clipboard.",
						"content_copy"
					)
					return true
				end
			end

			homeNotification(
				"Clipboard unavailable",
				"Your executor does not support clipboard copying.",
				"error_outline"
			)
			return false
		end

		local function normalizeDiscordInvite(value)
			local invite = tostring(value or "")
				:match("^%s*(.-)%s*$")

			if invite == ""
				or invite:lower() == "noinvitelink"
			then
				return nil, nil
			end

			local code =
				invite:match("discord%.gg/([^/%?]+)")
				or invite:match(
					"discord%.com/invite/([^/%?]+)"
				)
				or invite:match(
					"discordapp%.com/invite/([^/%?]+)"
				)
				or invite

			code = tostring(code or "")
				:match("^%s*(.-)%s*$")

			if code == "" then
				return nil, nil
			end

			return "https://discord.gg/" .. code, code
		end

		local function findGuiButton(object)
			if not object then
				return nil
			end

			if object:IsA("GuiButton") then
				return object
			end

			local directInteract =
				object:FindFirstChild("Interact")

			if directInteract
				and directInteract:IsA("GuiButton")
			then
				return directInteract
			end

			for _, descendant in ipairs(
				object:GetDescendants()
			) do
				if descendant:IsA("GuiButton") then
					return descendant
				end
			end

			return nil
		end

		local function findJoinScriptButton(root)
			if not root then
				return nil
			end

			local exactNames = {
				"JoinScript",
				"CopyJoinScript",
				"JoinServer",
				"ServerJoin",
			}

			for _, name in ipairs(exactNames) do
				local object =
					root:FindFirstChild(name, true)
				local button = findGuiButton(object)

				if button then
					return button
				end
			end

			for _, descendant in ipairs(
				root:GetDescendants()
			) do
				local text = ""

				if descendant:IsA("TextLabel")
					or descendant:IsA("TextButton")
					or descendant:IsA("TextBox")
				then
					text = tostring(descendant.Text or "")
				end

				local searchable = (
					tostring(descendant.Name)
					.. " "
					.. text
				):lower()

				local looksLikeJoin =
					searchable:find(
						"join",
						1,
						true
					) ~= nil

				local looksLikeScript =
					searchable:find(
						"script",
						1,
						true
					) ~= nil
					or searchable:find(
						"server",
						1,
						true
					) ~= nil

				if looksLikeJoin and looksLikeScript then
					local ancestor = descendant

					for _ = 1, 6 do
						if not ancestor
							or ancestor == root
						then
							break
						end

						local button =
							findGuiButton(ancestor)

						if button then
							return button
						end

						ancestor = ancestor.Parent
					end
				end
			end

			return nil
		end

		local dashboard =
			HomeTabPage.detailsholder.dashboard
		local discordCard =
			dashboard:FindFirstChild("Discord")

		if discordCard then
			local discordInteract =
				findGuiButton(discordCard)

			local baseZIndex = math.max(
				tonumber(discordCard.ZIndex) or 1,
				discordInteract
					and (tonumber(discordInteract.ZIndex) or 1)
					or 1
			)

			local oldLogo =
				discordCard:FindFirstChild(
					"AireszDiscordLogo"
				)

			if oldLogo then
				oldLogo:Destroy()
			end

			local oldHolder =
				discordCard:FindFirstChild(
					"AireszDiscordLogoHolder"
				)

			if oldHolder then
				oldHolder:Destroy()
			end

			local logoHolder = Instance.new("Frame")
			logoHolder.Name = "AireszDiscordLogoHolder"
			logoHolder.AnchorPoint = Vector2.new(1, 0.5)
			logoHolder.BackgroundColor3 =
				Color3.fromRGB(88, 101, 242)
			logoHolder.BackgroundTransparency = 0
			logoHolder.BorderSizePixel = 0
			logoHolder.Position =
				UDim2.new(1, -42, 0.5, 0)
			logoHolder.Size =
				UDim2.fromOffset(30, 30)
			logoHolder.ZIndex = baseZIndex + 2
			logoHolder.ClipsDescendants = true
			logoHolder.Parent = discordCard

			local logoCorner = Instance.new("UICorner")
			logoCorner.CornerRadius = UDim.new(0, 8)
			logoCorner.Parent = logoHolder

			-- Pure-UI fallback. This remains visible until the
			-- external Discord decal thumbnail has loaded.
			local fallbackLogo = Instance.new("Frame")
			fallbackLogo.Name = "DiscordVectorFallback"
			fallbackLogo.BackgroundTransparency = 1
			fallbackLogo.Size = UDim2.fromScale(1, 1)
			fallbackLogo.ZIndex = baseZIndex + 3
			fallbackLogo.Parent = logoHolder

			local leftEar = Instance.new("Frame")
			leftEar.AnchorPoint = Vector2.new(0, 0.5)
			leftEar.BackgroundColor3 =
				Color3.fromRGB(255, 255, 255)
			leftEar.BorderSizePixel = 0
			leftEar.Position =
				UDim2.new(0, 5, 0.5, 1)
			leftEar.Size =
				UDim2.fromOffset(6, 12)
			leftEar.ZIndex = baseZIndex + 3
			leftEar.Parent = fallbackLogo

			local leftEarCorner = Instance.new("UICorner")
			leftEarCorner.CornerRadius =
				UDim.new(1, 0)
			leftEarCorner.Parent = leftEar

			local rightEar = Instance.new("Frame")
			rightEar.AnchorPoint = Vector2.new(1, 0.5)
			rightEar.BackgroundColor3 =
				Color3.fromRGB(255, 255, 255)
			rightEar.BorderSizePixel = 0
			rightEar.Position =
				UDim2.new(1, -5, 0.5, 1)
			rightEar.Size =
				UDim2.fromOffset(6, 12)
			rightEar.ZIndex = baseZIndex + 3
			rightEar.Parent = fallbackLogo

			local rightEarCorner = Instance.new("UICorner")
			rightEarCorner.CornerRadius =
				UDim.new(1, 0)
			rightEarCorner.Parent = rightEar

			local controller = Instance.new("Frame")
			controller.AnchorPoint = Vector2.new(0.5, 0.5)
			controller.BackgroundColor3 =
				Color3.fromRGB(255, 255, 255)
			controller.BorderSizePixel = 0
			controller.Position =
				UDim2.new(0.5, 0, 0.5, 1)
			controller.Size =
				UDim2.fromOffset(19, 13)
			controller.ZIndex = baseZIndex + 4
			controller.Parent = fallbackLogo

			local controllerCorner = Instance.new("UICorner")
			controllerCorner.CornerRadius =
				UDim.new(1, 0)
			controllerCorner.Parent = controller

			local eyeLeft = Instance.new("Frame")
			eyeLeft.AnchorPoint = Vector2.new(0.5, 0.5)
			eyeLeft.BackgroundColor3 =
				Color3.fromRGB(88, 101, 242)
			eyeLeft.BorderSizePixel = 0
			eyeLeft.Position =
				UDim2.new(0.34, 0, 0.48, 0)
			eyeLeft.Size =
				UDim2.fromOffset(3, 4)
			eyeLeft.ZIndex = baseZIndex + 5
			eyeLeft.Parent = controller

			local eyeLeftCorner = Instance.new("UICorner")
			eyeLeftCorner.CornerRadius =
				UDim.new(1, 0)
			eyeLeftCorner.Parent = eyeLeft

			local eyeRight = eyeLeft:Clone()
			eyeRight.Position =
				UDim2.new(0.66, 0, 0.48, 0)
			eyeRight.Parent = controller

			local discordLogo = Instance.new("ImageLabel")
			discordLogo.Name = "AireszDiscordLogo"
			discordLogo.AnchorPoint =
				Vector2.new(0.5, 0.5)
			discordLogo.BackgroundTransparency = 1
			discordLogo.Position =
				UDim2.fromScale(0.5, 0.5)
			discordLogo.Size =
				UDim2.fromScale(0.88, 0.88)
			discordLogo.Image =
				"rbxthumb://type=Asset&id=18810599582&w=420&h=420"
			discordLogo.ImageColor3 =
				Color3.fromRGB(255, 255, 255)
			discordLogo.ImageTransparency = 0
			discordLogo.ScaleType =
				Enum.ScaleType.Fit
			discordLogo.ZIndex = baseZIndex + 6
			discordLogo.Parent = logoHolder

			task.spawn(function()
				local started = os.clock()

				while discordLogo.Parent
					and not discordLogo.IsLoaded
					and (os.clock() - started) < 3
				do
					task.wait(0.05)
				end

				if not discordLogo.Parent then
					return
				end

				if discordLogo.IsLoaded then
					fallbackLogo.Visible = false
				else
					discordLogo.Visible = false
					fallbackLogo.Visible = true
				end
			end)

			local oldArrow =
				discordCard:FindFirstChild(
					"AireszDiscordArrow"
				)

			if oldArrow then
				oldArrow:Destroy()
			end

			local discordArrow =
				Instance.new("TextLabel")
			discordArrow.Name =
				"AireszDiscordArrow"
			discordArrow.AnchorPoint =
				Vector2.new(1, 0.5)
			discordArrow.BackgroundTransparency = 1
			discordArrow.Position =
				UDim2.new(1, -10, 0.5, -1)
			discordArrow.Size =
				UDim2.fromOffset(20, 26)
			discordArrow.Font =
				Enum.Font.GothamBold
			discordArrow.Text = "›"
			discordArrow.TextColor3 =
				Color3.fromRGB(220, 224, 240)
			discordArrow.TextSize = 24
			discordArrow.TextTransparency = 0
			discordArrow.ZIndex = baseZIndex + 6
			discordArrow.Parent = discordCard

			if discordInteract then
				TrackConnection(
					discordInteract
						.MouseButton1Click
						:Connect(function()
							local inviteUrl, inviteCode =
								normalizeDiscordInvite(
									HomeTabSettings
										.DiscordInvite
								)

							if not inviteUrl then
								homeNotification(
									"Discord unavailable",
									"Discord invite is not configured.",
									"error_outline"
								)
								return
							end

							copyHomeText(
								inviteUrl,
								"Discord copied",
								"Discord invite copied to clipboard."
							)

							if type(request) == "function" then
								pcall(request, {
									Url =
										"http://127.0.0.1:6463/rpc?v=1",
									Method = "POST",
									Headers = {
										["Content-Type"] =
											"application/json",
										Origin =
											"https://discord.com",
									},
									Body =
										HttpService:JSONEncode({
											cmd =
												"INVITE_BROWSER",
											nonce =
												HttpService
													:GenerateGUID(
														false
													),
											args = {
												code =
													inviteCode,
											},
										}),
								})
							end
						end),
					homeConnections
				)
			end
		end

		local joinScriptButton =
			findJoinScriptButton(HomeTabPage)

		if joinScriptButton then
			TrackConnection(
				joinScriptButton.MouseButton1Click:Connect(
					function()
						local joinScript = string.format(
							"game:GetService(%q)"
							.. ":TeleportToPlaceInstance("
							.. "%d, %q, "
							.. "game:GetService(%q)"
							.. ".LocalPlayer)",
							"TeleportService",
							game.PlaceId,
							tostring(game.JobId),
							"Players"
						)

						copyHomeText(
							joinScript,
							"Join script copied",
							"Server join script copied to clipboard."
						)
					end
				),
				homeConnections
			)
		end

		local function setPlayerCounts()
			if not alive or not HomeTabPage.Parent then return end
			HomeTabPage.detailsholder.dashboard.Server.Players.Value.Text = #Players:GetPlayers() .. " playing"
			HomeTabPage.detailsholder.dashboard.Server.MaxPlayers.Value.Text = Players.MaxPlayers .. " players can join this server"
		end
		setPlayerCounts()
		TrackConnection(Players.PlayerAdded:Connect(setPlayerCounts), homeConnections)
		TrackConnection(Players.PlayerRemoving:Connect(function()
			task.defer(setPlayerCounts)
		end), homeConnections)

		local region = "Unknown"
		task.spawn(function()
			local success, result = pcall(Localization.GetCountryRegionForPlayerAsync, Localization, Player)
			if success and result then region = tostring(result) end
			if alive and HomeTabPage.Parent then
				HomeTabPage.detailsholder.dashboard.Server.Region.Value.Text = region
			end
		end)

		local function getPing()
			local success, value = pcall(function()
				return game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValue()
			end)
			return success and math.clamp(tonumber(value) or 0, 0, 9999) or 0
		end

		local function format(value)
			return string.format("%02i", math.floor(value))
		end

		local function convertToHMS(seconds)
			local minutes = math.floor(seconds / 60)
			local hours = math.floor(minutes / 60)
			return format(hours) .. ":" .. format(minutes % 60) .. ":" .. format(seconds % 60)
		end

		local checkingFriends = false
		local function checkFriends()
			if checkingFriends or not alive then return end
			checkingFriends = true
			task.spawn(function()
				local playersFriends = {}
				local friendsInTotal, onlineFriends, friendsInGame = 0, 0, 0
				local success = pcall(function()
					local pages = Players:GetFriendsAsync(Player.UserId)
					while true do
						for _, data in ipairs(pages:GetCurrentPage()) do
							friendsInTotal += 1
							table.insert(playersFriends, data)
						end
						if pages.IsFinished then break end
						pages:AdvanceToNextPageAsync()
					end
					for _ in ipairs(Player:GetFriendsOnline()) do onlineFriends += 1 end
					for _, data in ipairs(playersFriends) do
						if data.Username and Players:FindFirstChild(data.Username) then friendsInGame += 1 end
					end
				end)
				if success and alive and HomeTabPage.Parent then
					local dashboard = HomeTabPage.detailsholder.dashboard.Friends
					dashboard.All.Value.Text = tostring(friendsInTotal) .. " friends"
					dashboard.Offline.Value.Text = tostring(math.max(0, friendsInTotal - onlineFriends)) .. " friends"
					dashboard.Online.Value.Text = tostring(onlineFriends) .. " friends"
					dashboard.InGame.Value.Text = tostring(friendsInGame) .. " friends"
				end
				checkingFriends = false
			end)
		end

		checkFriends()
		task.spawn(function()
			local friendElapsed = tonumber(HomeTabSettings.FriendsRefreshInterval) or 30
			while alive and not Luna._Destroyed and HomeTabPage.Parent do
				HomeTabPage.detailsholder.dashboard.Server.Latency.Value.Text = tostring(math.floor(getPing())) .. "ms"
				HomeTabPage.detailsholder.dashboard.Server.Time.Value.Text = convertToHMS(time())
				friendElapsed += tonumber(HomeTabSettings.RefreshInterval) or 1
				if friendElapsed >= (tonumber(HomeTabSettings.FriendsRefreshInterval) or 30) then
					friendElapsed = 0
					checkFriends()
				end
				task.wait(math.max(0.25, tonumber(HomeTabSettings.RefreshInterval) or 1))
			end
		end)

		function HomeTab:Destroy()
			alive = false
			DisconnectConnections(homeConnections)
			HomeTabPage.Visible = false
			HomeTabButton.Visible = false
		end

		AddCleanup(function()
			alive = false
			DisconnectConnections(homeConnections)
		end)
		return HomeTab
	end

	function Window:CreateTab(TabSettings)

		local Tab = {}

		TabSettings = Kwargify({
			Name = "Tab",
			ShowTitle = true,
			Icon = "view_in_ar",
			ImageSource = "Material" 
		}, TabSettings or {})

		local TabButton = Navigation.Tabs["InActive Template"]:Clone()

		TabButton.Name = TabSettings.Name
		TabButton.TextLabel.Text = TabSettings.Name
		TabButton.Parent = Navigation.Tabs
		ApplyIcon(TabButton.ImageLabel, TabSettings.Icon, TabSettings.ImageSource)

		TabButton.Visible = true

		local TabPage = Elements.Template:Clone()
		TabPage.Name = TabSettings.Name
		TabPage.Title.Visible = TabSettings.ShowTitle
		TabPage.Title.Text = TabSettings.Name
		TabPage.Visible = true

		Tab.Page = TabPage

		if TabSettings.ShowTitle == false then
			TabPage.UIPadding.PaddingTop = UDim.new(0,10)
		end

		TabPage.LayoutOrder = #Elements:GetChildren() - 3

		for _, TemplateElement in ipairs(TabPage:GetChildren()) do
			if TemplateElement.ClassName == "Frame" or TemplateElement.ClassName == "TextLabel" and TemplateElement.Name ~= "Title" then
				TemplateElement:Destroy()
			end
		end
		TabPage.Parent = Elements

		function Tab:Activate()
			tween(TabButton.ImageLabel, {ImageColor3 = Color3.fromRGB(255,255,255)})
			tween(TabButton, {BackgroundTransparency = 0})
			tween(TabButton.UIStroke, {Transparency = 0.41})

			Elements.UIPageLayout:JumpTo(TabPage)

			task.wait(0.05)

			for _, OtherTabButton in ipairs(Navigation.Tabs:GetChildren()) do
				if OtherTabButton.Name ~= "InActive Template" and OtherTabButton.ClassName == "Frame" and OtherTabButton ~= TabButton then
					tween(OtherTabButton.ImageLabel, {ImageColor3 = Color3.fromRGB(221,221,221)})
					tween(OtherTabButton, {BackgroundTransparency = 1})
					tween(OtherTabButton.UIStroke, {Transparency = 1})
				end

			end

			Window.CurrentTab = TabSettings.Name
			EmitEvent("TabChanged", Window, TabSettings.Name, Tab)
		end

		if FirstTab then
			Tab:Activate()
		end

		task.wait(0.01)

		TrackConnection(TabButton.Interact.MouseButton1Click:Connect(function()
			Tab:Activate()
		end))

		FirstTab = false

		-- Section
		function Tab:CreateSection(name)

			local Section = {}
			local SectionSettings = type(name) == "table" and ShallowCopy(name) or {Name = name}
			name = tostring(SectionSettings.Name or "Section")

			Section.Name = name
			Section.Settings = SectionSettings
			Section.Collapsed = false

			local Sectiont = Elements.Template.Section:Clone()
			Sectiont.Text = name
			Sectiont.Visible = true
			Sectiont.Parent = TabPage
			local TabPage = Sectiont.Frame

			Sectiont.TextTransparency = 1
			tween(Sectiont, {TextTransparency = 0})

			function Section:Set(NewSection)
				if type(NewSection) == "table" then
					for key, value in pairs(NewSection) do Section.Settings[key] = value end
					NewSection = NewSection.Name or Section.Name
				end
				Section.Name = tostring(NewSection or "Section")
				Section.Settings.Name = Section.Name
				Sectiont.Text = Section.Name
				return Section
			end

			function Section:SetCollapsed(collapsed)
				Section.Collapsed = collapsed == true
				TabPage.Visible = not Section.Collapsed
				return Section
			end

			function Section:Toggle()
				return Section:SetCollapsed(not Section.Collapsed)
			end

			function Section:IsCollapsed()
				return Section.Collapsed == true
			end

			function Section:Expand()
				return Section:SetCollapsed(false)
			end

			function Section:Collapse()
				return Section:SetCollapsed(true)
			end

			function Section:Destroy()
				Sectiont:Destroy()
			end

			-- Divider
			function Section:CreateDivider()
				TabPage.Position = UDim2.new(0,0,0,28)
				local b = Elements.Template.Divider:Clone()
				b.Parent = TabPage
				b.Size = UDim2.new(1,0,0,18)
				b.Line.BackgroundTransparency = 1
				tween(b.Line, {BackgroundTransparency = 0})
			end

			-- Button
			function Section:CreateButton(ButtonSettings)
				TabPage.Position = UDim2.new(0,0,0,28)

				ButtonSettings = Kwargify({
					Name = "Button",
					Description = nil,
					Callback = function()

					end,
				}, ButtonSettings or {})

				local ButtonV = {
					Hover = false,
					Settings = ButtonSettings
				}


				local Button
				if ButtonSettings.Description == nil or ButtonSettings.Description == "" then
					Button = Elements.Template.Button:Clone()
				else
					Button = Elements.Template.ButtonDesc:Clone()
				end
				Button.Name = ButtonSettings.Name
				Button.Title.Text = ButtonSettings.Name
				if ButtonSettings.Description ~= nil and ButtonSettings.Description ~= "" then
					Button.Desc.Text = ButtonSettings.Description
				end
				Button.Visible = true
				Button.Parent = TabPage

				Button.UIStroke.Transparency = 1
				Button.Title.TextTransparency = 1
				if ButtonSettings.Description ~= nil and ButtonSettings.Description ~= "" then
					Button.Desc.TextTransparency = 1
				end

				TweenService:Create(Button, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0.5}):Play()
				TweenService:Create(Button.UIStroke, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {Transparency = 0.5}):Play()
				TweenService:Create(Button.Title, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {TextTransparency = 0}):Play()	
				if ButtonSettings.Description ~= nil and ButtonSettings.Description ~= "" then
					TweenService:Create(Button.Desc, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {TextTransparency = 0}):Play()	
				end

				ConnectComponent(ButtonV, Button.Interact.MouseButton1Click, function()
					local Success,Response = pcall(ButtonSettings.Callback)

					if not Success then
						TweenService:Create(Button, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0}):Play()
						TweenService:Create(Button, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {BackgroundColor3 = Color3.fromRGB(85, 0, 0)}):Play()
						TweenService:Create(Button.UIStroke, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {Transparency = 1}):Play()
						Button.Title.Text = "Callback Error"
						print("Luna Interface Suite | "..ButtonSettings.Name.." Callback Error " ..tostring(Response))
						task.wait(0.5)
						Button.Title.Text = ButtonSettings.Name
						TweenService:Create(Button, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0.5}):Play()
						TweenService:Create(Button, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {BackgroundColor3 = Color3.fromRGB(32, 30, 38)}):Play()
						TweenService:Create(Button.UIStroke, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {Transparency = 0.5}):Play()
					else
						tween(Button.UIStroke, {Color = Color3.fromRGB(136, 131, 163)})
						task.wait(0.2)
						if ButtonV.Hover then
							tween(Button.UIStroke, {Color = Color3.fromRGB(87, 84, 104)})
						else
							tween(Button.UIStroke, {Color = Color3.fromRGB(64,61,76)})
						end
					end
				end)

				ConnectComponent(ButtonV, Button.MouseEnter, function()
					ButtonV.Hover = true
					tween(Button.UIStroke, {Color = Color3.fromRGB(87, 84, 104)})
				end)

				ConnectComponent(ButtonV, Button.MouseLeave, function()
					ButtonV.Hover = false
					tween(Button.UIStroke, {Color = Color3.fromRGB(64,61,76)})
				end)

				function ButtonV:Set(ButtonSettings2)
					ButtonSettings2 = Kwargify({
						Name = ButtonSettings.Name,
						Description = ButtonSettings.Description,
						Callback = ButtonSettings.Callback
					}, ButtonSettings2 or {})

					ButtonSettings = ButtonSettings2
					ButtonV.Settings = ButtonSettings2

					Button.Name = ButtonSettings.Name
					Button.Title.Text = ButtonSettings.Name
					if ButtonSettings.Description ~= nil and ButtonSettings.Description ~= "" and Button.Desc ~= nil then
						Button.Desc.Text = ButtonSettings.Description
					end
				end

				function ButtonV:Destroy()
					RemoveOption(ButtonV)
					Button.Visible = false
					Button:Destroy()
				end

				ButtonV._Object = Button

				return EnhanceComponent(ButtonV)
			end

			-- Label
			function Section:CreateLabel(LabelSettings)
				TabPage.Position = UDim2.new(0,0,0,28)

				local LabelV = {}

				LabelSettings = Kwargify({
					Text = "Label",
					Style = 1
				}, LabelSettings or {}) 

				LabelV.Settings = LabelSettings

				local Label
				if LabelSettings.Style == 1 then
					Label = Elements.Template.Label:Clone()
				elseif LabelSettings.Style == 2 then
					Label = Elements.Template.Info:Clone()
				elseif LabelSettings.Style == 3 then
					Label = Elements.Template.Warn:Clone()
				end

				Label.Text.Text = LabelSettings.Text
				Label.Visible = true
				Label.Parent = TabPage

				Label.BackgroundTransparency = 1
				Label.UIStroke.Transparency = 1
				Label.Text.TextTransparency = 1

				if LabelSettings.Style ~= 1 then
					TweenService:Create(Label, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0.8}):Play()
				else
					TweenService:Create(Label, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {BackgroundTransparency = 1}):Play()
				end
				TweenService:Create(Label.UIStroke, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {Transparency = 0.5}):Play()
				TweenService:Create(Label.Text, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {TextTransparency = 0}):Play()	

				function LabelV:Set(NewLabel)
					LabelSettings.Text = NewLabel
					LabelV.Settings = LabelSettings
					Label.Text.Text = NewLabel
				end

				function LabelV:Destroy()
					RemoveOption(LabelV)
					Label.Visible = false
					Label:Destroy()
				end

				LabelV._Object = Label

				return EnhanceComponent(LabelV)
			end

			-- Paragraph
			function Section:CreateParagraph(ParagraphSettings)
				TabPage.Position = UDim2.new(0,0,0,28)

				ParagraphSettings = Kwargify({
					Title = "Paragraph",
					Text = "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Vivamus venenatis lacus sed tempus eleifend. Mauris interdum bibendum felis, in tempor augue egestas vel. Praesent tristique consectetur ex, eu pretium sem placerat non. Vestibulum a nisi sit amet augue facilisis consectetur sit amet et nunc. Integer fermentum ornare cursus. Pellentesque sed ultricies metus, ut egestas metus. Vivamus auctor erat ac sapien vulputate, nec ultricies sem tempor. Quisque leo lorem, faucibus nec pulvinar nec, congue eu velit. Duis sodales massa efficitur imperdiet ultrices. Donec eros ipsum, ornare pharetra purus aliquam, tincidunt elementum nisi. Ut mi tortor, feugiat eget nunc vitae, facilisis interdum dui. Vivamus ullamcorper nunc dui, a dapibus nisi pretium ac. Integer eleifend placerat nibh, maximus malesuada tellus. Cras in justo in ligula scelerisque suscipit vel vitae quam."
				}, ParagraphSettings or {})

				local ParagraphV = {
					Settings = ParagraphSettings
				}

				local Paragraph = Elements.Template.Paragraph:Clone()
				Paragraph.Title.Text = ParagraphSettings.Title
				Paragraph.Text.Text = ParagraphSettings.Text
				Paragraph.Visible = true
				Paragraph.Parent = TabPage

				Paragraph.BackgroundTransparency = 1
				Paragraph.UIStroke.Transparency = 1
				Paragraph.Title.TextTransparency = 1
				Paragraph.Text.TextTransparency = 1

				TweenService:Create(Paragraph, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {BackgroundTransparency = 1}):Play()
				TweenService:Create(Paragraph.UIStroke, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {Transparency = 0.5}):Play()
				TweenService:Create(Paragraph.Title, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {TextTransparency = 0}):Play()	
				TweenService:Create(Paragraph.Text, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {TextTransparency = 0}):Play()	

				function ParagraphV:Update()
					Paragraph.Text.Size = UDim2.new(Paragraph.Text.Size.X.Scale, Paragraph.Text.Size.X.Offset, 0, math.huge)
					Paragraph.Text.Size = UDim2.new(Paragraph.Text.Size.X.Scale, Paragraph.Text.Size.X.Offset, 0, Paragraph.Text.TextBounds.Y)
					tween(Paragraph, {Size = UDim2.new(Paragraph.Size.X.Scale, Paragraph.Size.X.Offset, 0, Paragraph.Text.TextBounds.Y + 40)})
				end

				function ParagraphV:Set(NewParagraphSettings)

					NewParagraphSettings = Kwargify({
						Title = ParagraphSettings.Title,
						Text = ParagraphSettings.Text
					}, NewParagraphSettings or {})

					ParagraphV.Settings = NewParagraphSettings

					Paragraph.Title.Text = NewParagraphSettings.Title
					Paragraph.Text.Text = NewParagraphSettings.Text

					ParagraphV:Update()

				end

				function ParagraphV:Destroy()
					RemoveOption(ParagraphV)
					Paragraph.Visible = false
					Paragraph:Destroy()
				end

				ParagraphV:Update()

				ParagraphV._Object = Paragraph

				return EnhanceComponent(ParagraphV)
			end

			-- Slider
			function Section:CreateSlider(SliderSettings, Flag)
				TabPage.Position = UDim2.new(0,0,0,28)
				local SliderV = {IgnoreConfig = false, Class = "Slider", Settings = SliderSettings}

				SliderSettings = Kwargify({
					Name = "Slider",
					Range = {0, 200},
					Increment = 1,
					CurrentValue = 100,
					FireOnInit = false,
					FireOnSet = true,
					CallbackInterval = 0.03,
					Callback = function(Value) end,
					OnFinished = function(Value) end,
				}, SliderSettings or {})
				SliderV.Settings = SliderSettings

				local Slider = Elements.Template.Slider:Clone()
				Slider.Name = tostring(SliderSettings.Name) .. " - Slider"
				Slider.Title.Text = tostring(SliderSettings.Name)
				Slider.Visible = true
				Slider.Parent = TabPage
				Slider.BackgroundTransparency = 1
				Slider.UIStroke.Transparency = 1
				Slider.Title.TextTransparency = 1

				TweenService:Create(Slider, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0.5}):Play()
				TweenService:Create(Slider.UIStroke, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {Transparency = 0.5}):Play()
				TweenService:Create(Slider.Title, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {TextTransparency = 0}):Play()

				local updatingText = false
				local dragging = false
				local activeInput
				local lastCallbackAt = -math.huge

				local function normalizedRange()
					local range = type(SliderSettings.Range) == "table"
						and SliderSettings.Range or {0, 100}
					local minimum = tonumber(range[1]) or 0
					local maximum = tonumber(range[2]) or 100
					if minimum > maximum then minimum, maximum = maximum, minimum end
					local increment = math.abs(tonumber(SliderSettings.Increment) or 1)
					if increment <= 0 then increment = 1 end
					return minimum, maximum, increment
				end

				local function decimalPlaces(number)
					local output = string.format("%.6f", math.abs(tonumber(number) or 0))
					output = output:gsub("0+$", ""):gsub("%.$", "")
					local decimals = output:match("%.(%d+)$")
					return decimals and #decimals or 0
				end

				local function formatNumber(value, increment)
					local decimals = math.clamp(decimalPlaces(increment), 0, 6)
					local output = string.format("%." .. decimals .. "f", value)
					if decimals > 0 then
						output = output:gsub("(%..-)0+$", "%1"):gsub("%.$", "")
					end
					return output
				end

				local function setProgress(value)
					local minimum, maximum = normalizedRange()
					local width = math.max(0, Slider.Main.AbsoluteSize.X)
					local alpha = maximum == minimum and 0
						or math.clamp((value - minimum) / (maximum - minimum), 0, 1)
					Slider.Main.Progress.Size = UDim2.new(0, math.max(5, width * alpha), 1, 0)
				end

				local function emitCallback(value, force)
					local interval = math.max(0, tonumber(SliderSettings.CallbackInterval) or 0.03)
					local now = os.clock()
					if force == true or now - lastCallbackAt >= interval then
						lastCallbackAt = now
						SafeCall(SliderSettings.Callback, value)
						return true
					end
					return false
				end

				local function setValue(value, fireCallback, forceCallback)
					local minimum, maximum, increment = normalizedRange()
					value = tonumber(value) or tonumber(SliderSettings.CurrentValue) or minimum
					value = math.clamp(value, minimum, maximum)
					value = minimum + math.floor(((value - minimum) / increment) + 0.5) * increment
					value = math.clamp(value, minimum, maximum)
					value = math.floor(value * 1000000 + 0.5) / 1000000

					local changed = tonumber(SliderSettings.CurrentValue) ~= value
					SliderSettings.CurrentValue = value
					SliderV.CurrentValue = value
					updatingText = true
					Slider.Value.Text = formatNumber(value, increment)
					Slider.Value.Size = UDim2.fromOffset(math.max(20, Slider.Value.TextBounds.X), 23)
					updatingText = false
					setProgress(value)

					if fireCallback and (changed or forceCallback == true)
						and IsComponentUsable(SliderV)
					then
						emitCallback(value, forceCallback == true)
					end
					return value
				end

				local function inputX(input)
					if input and input.UserInputType == Enum.UserInputType.Touch then
						return input.Position.X
					end
					return UserInputService:GetMouseLocation().X
				end

				local function updateFromInput(input)
					if not dragging or not IsComponentUsable(SliderV) then return end
					local width = Slider.Main.AbsoluteSize.X
					if width <= 0 then return end
					local minimum, maximum = normalizedRange()
					local alpha = math.clamp(
						(inputX(input) - Slider.Main.AbsolutePosition.X) / width,
						0,
						1
					)
					setValue(minimum + alpha * (maximum - minimum), true, false)
				end

				ConnectComponent(SliderV, Slider.MouseEnter, function()
					if not SliderV.Disabled then
						tween(Slider.UIStroke, {Color = Color3.fromRGB(87, 84, 104)})
					end
				end)
				ConnectComponent(SliderV, Slider.MouseLeave, function()
					tween(Slider.UIStroke, {Color = Color3.fromRGB(64,61,76)})
				end)
				ConnectComponent(SliderV, Slider.Interact.InputBegan, function(input)
					if not IsComponentUsable(SliderV) then return end
					if input.UserInputType == Enum.UserInputType.MouseButton1
						or input.UserInputType == Enum.UserInputType.Touch
					then
						dragging = true
						activeInput = input
						updateFromInput(input)
					end
				end)
				ConnectComponent(SliderV, UserInputService.InputChanged, function(input)
					if not dragging then return end
					if activeInput and activeInput.UserInputType == Enum.UserInputType.Touch then
						if input ~= activeInput then return end
					elseif input.UserInputType ~= Enum.UserInputType.MouseMovement then
						return
					end
					updateFromInput(input)
				end)
				ConnectComponent(SliderV, UserInputService.InputEnded, function(input)
					if input == activeInput
						or input.UserInputType == Enum.UserInputType.MouseButton1
					then
						local wasDragging = dragging
						dragging = false
						activeInput = nil
						if wasDragging and IsComponentUsable(SliderV) then
							setValue(SliderV.CurrentValue, true, true)
							SafeCall(SliderSettings.OnFinished, SliderV.CurrentValue)
						end
					end
				end)

				if Slider.Value:IsA("TextBox") then
					ConnectComponent(SliderV, Slider.Value.FocusLost, function()
						if updatingText then return end
						setValue(Slider.Value.Text, true, true)
						SafeCall(SliderSettings.OnFinished, SliderV.CurrentValue)
					end)
				end

				ConnectComponent(SliderV, LunaUI.ThemeRemote:GetPropertyChangedSignal("Value"), function()
					if Slider.Parent then
						Slider.Main.color.Color = Luna.ThemeGradient
						Slider.Main.UIStroke.color.Color = Luna.ThemeGradient
					end
				end)

				function SliderV:UpdateValue(value, silent)
					setValue(value, silent ~= true, false)
					return self
				end

				function SliderV:Set(NewSliderSettings)
					NewSliderSettings = Kwargify(SliderSettings, NewSliderSettings or {})
					SliderSettings = NewSliderSettings
					SliderV.Settings = NewSliderSettings
					Slider.Name = tostring(SliderSettings.Name) .. " - Slider"
					Slider.Title.Text = tostring(SliderSettings.Name)
					local shouldFire = NewSliderSettings.Silent ~= true
						and SliderSettings.FireOnSet ~= false
					setValue(
						SliderSettings.CurrentValue,
						shouldFire,
						NewSliderSettings.ForceCallback == true
					)
					return self
				end

				function SliderV:Destroy()
					RemoveOption(SliderV)
					if Slider.Parent then Slider:Destroy() end
				end

				if Flag then RegisterOption(Flag, SliderV) end
				SliderV._Object = Slider
				SliderV = EnhanceComponent(SliderV)
				setValue(SliderSettings.CurrentValue, false, false)
				if SliderSettings.FireOnInit and IsComponentUsable(SliderV) then
					emitCallback(SliderV.CurrentValue, true)
				end
				task.defer(function()
					if Slider.Parent then
						setProgress(tonumber(SliderSettings.CurrentValue) or 0)
					end
				end)
				return SliderV
			end
			-- Toggle
			function Section:CreateToggle(ToggleSettings, Flag)
				TabPage.Position = UDim2.new(0,0,0,28)
				local ToggleV = { IgnoreConfig = false, Class = "Toggle" }

				ToggleSettings = Kwargify({
					Name = "Toggle",
					Description = nil,
					CurrentValue = false,
					FireOnInit = false,
					FireOnSet = true,
					Group = nil,
					AllowNone = true,
					FireGroupCallbacks = true,
					Callback = function(Value) end,
				}, ToggleSettings or {})

				ToggleV.Settings = ToggleSettings

				local Toggle
				if ToggleSettings.Description ~= nil and ToggleSettings.Description ~= "" then
					Toggle = Elements.Template.ToggleDesc:Clone()
				else
					Toggle = Elements.Template.Toggle:Clone()
				end

				Toggle.Visible = true
				Toggle.Parent = TabPage
				Toggle.Name = tostring(ToggleSettings.Name) .. " - Toggle"
				Toggle.Title.Text = tostring(ToggleSettings.Name)
				if ToggleSettings.Description ~= nil and ToggleSettings.Description ~= "" then
					Toggle.Desc.Text = tostring(ToggleSettings.Description)
				end

				Toggle.UIStroke.Transparency = 1
				Toggle.Title.TextTransparency = 1
				if ToggleSettings.Description ~= nil and ToggleSettings.Description ~= "" then
					Toggle.Desc.TextTransparency = 1
				end

				TweenService:Create(Toggle, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0.5}):Play()
				if ToggleSettings.Description ~= nil and ToggleSettings.Description ~= "" then
					TweenService:Create(Toggle.Desc, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {TextTransparency = 0}):Play()
				end
				TweenService:Create(Toggle.UIStroke, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {Transparency = 0.5}):Play()
				TweenService:Create(Toggle.Title, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {TextTransparency = 0}):Play()

				local function Render(state)
					state = state == true
					if state then
						Toggle.toggle.color.Enabled = true
						tween(Toggle.toggle, {BackgroundTransparency = 0})
						Toggle.toggle.UIStroke.color.Enabled = true
						tween(Toggle.toggle.UIStroke, {Color = Color3.fromRGB(255,255,255)})
						tween(Toggle.toggle.val, {
							BackgroundColor3 = Color3.fromRGB(255,255,255),
							Position = UDim2.new(1,-23,0.5,0),
							BackgroundTransparency = 0.45,
						})
					else
						Toggle.toggle.color.Enabled = false
						Toggle.toggle.UIStroke.color.Enabled = false
						Toggle.toggle.UIStroke.Color = Color3.fromRGB(97,97,97)
						tween(Toggle.toggle, {BackgroundTransparency = 1})
						tween(Toggle.toggle.val, {
							BackgroundColor3 = Color3.fromRGB(97,97,97),
							Position = UDim2.new(0,5,0.5,0),
							BackgroundTransparency = 0,
						})
					end
				end

				local function ShowCallbackError(response)
					if not Toggle.Parent then return end
					Luna._Stats.CallbackErrors += 1
					warn("Luna UI callback error: " .. tostring(response))
					TweenService:Create(Toggle, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0}):Play()
					TweenService:Create(Toggle, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {BackgroundColor3 = Color3.fromRGB(85, 0, 0)}):Play()
					TweenService:Create(Toggle.UIStroke, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {Transparency = 1}):Play()
					Toggle.Title.Text = "Callback Error"
					task.delay(0.5, function()
						if not Toggle.Parent then return end
						Toggle.Title.Text = tostring(ToggleSettings.Name)
						TweenService:Create(Toggle, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0.5}):Play()
						TweenService:Create(Toggle, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {BackgroundColor3 = Color3.fromRGB(32, 30, 38)}):Play()
						TweenService:Create(Toggle.UIStroke, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {Transparency = 0.5}):Play()
					end)
				end

				local function EmitCallback(state)
					if not IsComponentUsable(ToggleV) then return false end
					local success, response = pcall(ToggleSettings.Callback, state)
					if not success then
						ShowCallbackError(response)
					end
					return success, response
				end

				local function SetRawState(state)
					state = state == true
					ToggleSettings.CurrentValue = state
					ToggleV.CurrentValue = state
					Render(state)
					return state
				end

				local function ApplyState(state, fireCallback, enforceGroup, fireGroupCallbacks, force)
					state = state == true
					force = force == true
					local group = ToggleV._ToggleGroup

					if group and Luna._MutatingToggleGroups[group] and not force then
						return ToggleV, false, "Toggle group is busy."
					end

					if not state
						and group
						and enforceGroup ~= false
						and not force
						and not ToggleGroupAllowsNone(group)
						and not ToggleGroupHasOtherActive(ToggleV)
					then
						return ToggleV, false, "At least one toggle in this group must remain active."
					end

					if state and group and enforceGroup ~= false then
						if not BeginToggleGroupMutation(group) then
							return ToggleV, false, "Toggle group is busy."
						end

						local deactivated = DeactivateToggleGroup(ToggleV)
						SetRawState(true)

						if fireGroupCallbacks == true then
							for _, member in ipairs(deactivated) do
								if type(member._EmitExclusiveCallback) == "function" then
									member:_EmitExclusiveCallback(false)
								end
							end
						end
						if fireCallback == true then
							EmitCallback(true)
						end
						EndToggleGroupMutation(group)
					else
						SetRawState(state)
						if fireCallback == true then
							EmitCallback(state)
						end
					end
					return ToggleV, true
				end

				function ToggleV:_ApplyExclusiveState(state, fireCallback)
					SetRawState(state)
					if fireCallback == true then
						EmitCallback(state == true)
					end
					return self
				end

				function ToggleV:_EmitExclusiveCallback(state)
					return EmitCallback(state == true)
				end

				function ToggleV:GetGroup()
					return self._ToggleGroup
				end

				function ToggleV:SetGroup(group, fireGroupCallbacks)
					ToggleSettings.Group = group
					RegisterToggleGroup(self, group)
					if self.CurrentValue == true and self._ToggleGroup then
						ApplyState(true, false, true, fireGroupCallbacks == true, true)
					end
					NormalizeAllToggleGroups(false)
					return self
				end

				ConnectComponent(ToggleV, Toggle.Interact.MouseButton1Click, function()
					if not IsComponentUsable(ToggleV) then return end
					ApplyState(
						not ToggleSettings.CurrentValue,
						true,
						true,
						ToggleSettings.FireGroupCallbacks ~= false,
						false
					)
				end)

				ConnectComponent(ToggleV, Toggle.MouseEnter, function()
					if not ToggleV.Disabled then
						tween(Toggle.UIStroke, {Color = Color3.fromRGB(87, 84, 104)})
					end
				end)

				ConnectComponent(ToggleV, Toggle.MouseLeave, function()
					tween(Toggle.UIStroke, {Color = Color3.fromRGB(64,61,76)})
				end)

				function ToggleV:UpdateState(state, force)
					return ApplyState(state, false, true, false, force == true)
				end

				function ToggleV:Set(NewToggleSettings)
					NewToggleSettings = Kwargify({
						Name = ToggleSettings.Name,
						Description = ToggleSettings.Description,
						CurrentValue = ToggleSettings.CurrentValue,
						FireOnInit = ToggleSettings.FireOnInit,
						FireOnSet = ToggleSettings.FireOnSet,
						Group = ToggleSettings.Group,
						AllowNone = ToggleSettings.AllowNone,
						FireGroupCallbacks = ToggleSettings.FireGroupCallbacks,
						Callback = ToggleSettings.Callback,
					}, NewToggleSettings or {})

					ToggleSettings = NewToggleSettings
					ToggleV.Settings = NewToggleSettings
					RegisterToggleGroup(ToggleV, ToggleSettings.Group)

					Toggle.Name = tostring(ToggleSettings.Name) .. " - Toggle"
					Toggle.Title.Text = tostring(ToggleSettings.Name)
					if Toggle.Desc ~= nil then
						Toggle.Desc.Text = tostring(ToggleSettings.Description or "")
					end

					local shouldFire = NewToggleSettings.Silent ~= true
						and ToggleSettings.FireOnSet ~= false
					return ApplyState(
						ToggleSettings.CurrentValue,
						shouldFire,
						true,
						shouldFire and ToggleSettings.FireGroupCallbacks ~= false,
						NewToggleSettings.Force == true
					)
				end

				function ToggleV:Destroy()
					RemoveToggleFromGroup(ToggleV)
					RemoveOption(ToggleV)
					if Toggle.Parent then Toggle:Destroy() end
				end

				ConnectComponent(ToggleV, LunaUI.ThemeRemote:GetPropertyChangedSignal("Value"), function()
					if Toggle.Parent then
						Toggle.toggle.color.Color = Luna.ThemeGradient
						Toggle.toggle.UIStroke.color.Color = Luna.ThemeGradient
					end
				end)

				if Flag then RegisterOption(Flag, ToggleV) end
				ToggleV._Object = Toggle
				ToggleV = EnhanceComponent(ToggleV)
				RegisterToggleGroup(ToggleV, ToggleSettings.Group)

				ApplyState(
					ToggleSettings.CurrentValue,
					ToggleSettings.CurrentValue == true and ToggleSettings.FireOnInit == true,
					true,
					false,
					true
				)
				task.defer(function()
					if not ToggleV._Destroyed then
						NormalizeAllToggleGroups(false)
					end
				end)
				return ToggleV
			end
			-- Bind
			function Section:CreateBind(BindSettings, Flag)
				TabPage.Position = UDim2.new(0,0,0,28)
				local BindV = {Class = "Bind", IgnoreConfig = false, Settings = BindSettings, Active = false}

				BindSettings = Kwargify({
					Name = "Bind",
					Description = nil,
					CurrentBind = "Q",
					HoldToInteract = false,
					FireOnInit = false,
					Callback = function(active) end,
					OnChangedCallback = function(bind) end,
				}, BindSettings or {})

				local checkingForKey = false
				local Bind
				if BindSettings.Description ~= nil and BindSettings.Description ~= "" then
					Bind = Elements.Template.BindDesc:Clone()
				else
					Bind = Elements.Template.Bind:Clone()
				end

				Bind.Visible = true
				Bind.Parent = TabPage
				Bind.Name = tostring(BindSettings.Name)
				Bind.Title.Text = tostring(BindSettings.Name)
				if Bind.Desc and BindSettings.Description then Bind.Desc.Text = tostring(BindSettings.Description) end
				Bind.BindFrame.BindBox.Text = tostring(BindSettings.CurrentBind)
				BindV.CurrentBind = tostring(BindSettings.CurrentBind)

				local function resizeBindBox()
					Bind.BindFrame.BindBox.Size = UDim2.new(0, Bind.BindFrame.BindBox.TextBounds.X + 20, 0, 42)
				end
				resizeBindBox()

				local function currentBinding()
					return NormalizeInputBinding(BindSettings.CurrentBind)
				end

				local function setBind(newBind, fireChanged)
					local binding = NormalizeInputBinding(
						newBind,
						BindSettings.CurrentBind or "Q"
					)
					if not binding then return false end
					local bindName = binding.Name
					local changed = tostring(BindSettings.CurrentBind) ~= bindName
					BindSettings.CurrentBind = bindName
					BindV.CurrentBind = bindName
					Bind.BindFrame.BindBox.Text = bindName
					resizeBindBox()
					if changed and fireChanged and IsComponentUsable(BindV) then
						SafeCall(BindSettings.OnChangedCallback, bindName)
					end
					return true
				end

				setBind(BindSettings.CurrentBind, false)

				ConnectComponent(BindV, Bind.BindFrame.BindBox.Focused, function()
					if BindV.Disabled then return end
					checkingForKey = true
					Bind.BindFrame.BindBox.Text = "..."
				end)
				ConnectComponent(BindV, Bind.BindFrame.BindBox.FocusLost, function()
					checkingForKey = false
					Bind.BindFrame.BindBox.Text = tostring(BindSettings.CurrentBind)
					resizeBindBox()
				end)
				ConnectComponent(BindV, Bind.MouseEnter, function()
					if not BindV.Disabled then tween(Bind.UIStroke, {Color = Color3.fromRGB(87,84,104)}) end
				end)
				ConnectComponent(BindV, Bind.MouseLeave, function()
					tween(Bind.UIStroke, {Color = Color3.fromRGB(64,61,76)})
				end)

				ConnectComponent(BindV, UserInputService.InputBegan, function(input, processed)
					if Luna._Destroyed or BindV._Destroyed then return end
					if checkingForKey then
						local newBinding = InputToBinding(input)
						if newBinding then
							setBind(newBinding.Name, true)
							Bind.BindFrame.BindBox:ReleaseFocus()
						end
						return
					end
					if processed or BindV.Disabled then return end
					local binding = currentBinding()
					if not binding or not InputMatchesBinding(input, binding) then return end

					if BindSettings.HoldToInteract then
						if not BindV.Active then
							BindV.Active = true
							SafeCall(BindSettings.Callback, true)
						end
					else
						BindV.Active = not BindV.Active
						SafeCall(BindSettings.Callback, BindV.Active)
					end
				end)

				ConnectComponent(BindV, UserInputService.InputEnded, function(input)
					if BindV._Destroyed or not BindSettings.HoldToInteract or not BindV.Active then return end
					local binding = currentBinding()
					if binding and InputMatchesBinding(input, binding) then
						BindV.Active = false
						SafeCall(BindSettings.Callback, false)
					end
				end)

				function BindV:Set(NewBindSettings)
					NewBindSettings = Kwargify(BindSettings, NewBindSettings or {})
					local oldBind = tostring(BindSettings.CurrentBind)
					BindSettings = NewBindSettings
					BindV.Settings = NewBindSettings
					Bind.Name = tostring(BindSettings.Name)
					Bind.Title.Text = tostring(BindSettings.Name)
					if Bind.Desc and BindSettings.Description ~= nil then Bind.Desc.Text = tostring(BindSettings.Description) end
					setBind(BindSettings.CurrentBind, NewBindSettings.Silent ~= true and oldBind ~= tostring(BindSettings.CurrentBind))
					return BindV
				end

				function BindV:Destroy()
					if BindV.Active and BindSettings.HoldToInteract then SafeCall(BindSettings.Callback, false) end
					BindV.Active = false
					RemoveOption(BindV)
					if Bind.Parent then Bind:Destroy() end
				end

				if Flag then RegisterOption(Flag, BindV) end
				BindV._Object = Bind
				BindV = EnhanceComponent(BindV)
				if BindSettings.FireOnInit then SafeCall(BindSettings.Callback, BindV.Active) end
				return BindV
			end

			function Section:CreateKeybind(BindSettings, Flag)
				return Section:CreateBind(BindSettings, Flag)
			end

			function Section:CreateInput(InputSettings, Flag)
				TabPage.Position = UDim2.new(0,0,0,28)
				local InputV = { IgnoreConfig = false, Class = "Input", Settings = InputSettings }

				InputSettings = Kwargify({
					Name = "Dynamic Input",
					Description = nil,
					CurrentValue = "",
					PlaceholderText = "Input Placeholder",
					RemoveTextAfterFocusLost = false,
					Numeric = false,
					AllowNegative = true,
					AllowDecimal = true,
					Enter = false,
					MaxCharacters = nil,
					FireOnInit = false,
					FireOnSet = true,
					Callback = function(Text) end,
				}, InputSettings or {})

				InputV.Settings = InputSettings
				local descriptionEnabled = InputSettings.Description ~= nil
					and InputSettings.Description ~= ""
				local Input = descriptionEnabled
					and Elements.Template.InputDesc:Clone()
					or Elements.Template.Input:Clone()
				local TextBox = Input.InputFrame.InputBox

				Input.Name = tostring(InputSettings.Name)
				Input.Title.Text = tostring(InputSettings.Name)
				if descriptionEnabled and Input:FindFirstChild("Desc") then
					Input.Desc.Text = tostring(InputSettings.Description)
				end
				Input.Visible = true
				Input.Parent = TabPage

				Input.BackgroundTransparency = 1
				Input.UIStroke.Transparency = 1
				Input.Title.TextTransparency = 1
				if descriptionEnabled and Input:FindFirstChild("Desc") then
					Input.Desc.TextTransparency = 1
				end
				Input.InputFrame.BackgroundTransparency = 1
				Input.InputFrame.UIStroke.Transparency = 1
				TextBox.TextTransparency = 1

				TweenService:Create(Input, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0.5}):Play()
				TweenService:Create(Input.UIStroke, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {Transparency = 0.5}):Play()
				TweenService:Create(Input.Title, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {TextTransparency = 0}):Play()
				if descriptionEnabled and Input:FindFirstChild("Desc") then
					TweenService:Create(Input.Desc, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {TextTransparency = 0}):Play()
				end
				TweenService:Create(Input.InputFrame, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0.9}):Play()
				TweenService:Create(Input.InputFrame.UIStroke, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {Transparency = 0.3}):Play()
				TweenService:Create(TextBox, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {TextTransparency = 0}):Play()

				local updatingText = false

				local function sanitizeNumeric(text)
					text = tostring(text or "")
					local negative = InputSettings.AllowNegative ~= false
						and text:sub(1, 1) == "-"
					local body = text:gsub("[^%d%.]", "")
					if InputSettings.AllowDecimal == false then
						body = body:gsub("%.", "")
					else
						local firstDot = body:find(".", 1, true)
						if firstDot then
							body = body:sub(1, firstDot)
								.. body:sub(firstDot + 1):gsub("%.", "")
						end
					end
					return (negative and "-" or "") .. body
				end

				local function sanitizeText(value)
					local text = tostring(value or "")
					if InputSettings.Numeric then
						text = sanitizeNumeric(text)
					end
					local maximum = tonumber(InputSettings.MaxCharacters)
					if maximum then
						maximum = math.max(0, math.floor(maximum))
						if #text > maximum then
							text = text:sub(1, maximum)
						end
					end
					return text
				end

				local function resizeInput()
					local width = math.clamp(TextBox.TextBounds.X + 52, 90, 320)
					Input.InputFrame.Size = UDim2.fromOffset(width, 30)
				end

				local function emitCallback(text)
					if IsComponentUsable(InputV) then
						return SafeCall(InputSettings.Callback, text)
					end
					return false
				end

				local function applyText(value, fireCallback, forceCallback)
					local text = sanitizeText(value)
					local changed = tostring(InputV.CurrentValue or "") ~= text
					InputSettings.CurrentValue = text
					InputV.CurrentValue = text
					if TextBox.Text ~= text then
						updatingText = true
						TextBox.Text = text
						updatingText = false
					end
					resizeInput()
					if fireCallback == true and (changed or forceCallback == true) then
						emitCallback(text)
					end
					return text
				end

				TextBox.PlaceholderText = tostring(InputSettings.PlaceholderText or "")
				ConnectComponent(InputV, TextBox:GetPropertyChangedSignal("Text"), function()
					if updatingText or not IsComponentUsable(InputV) then return end
					applyText(TextBox.Text, not InputSettings.Enter, false)
				end)

				ConnectComponent(InputV, TextBox.FocusLost, function(enterPressed)
					local shouldFire = InputSettings.Enter and enterPressed == true
					applyText(TextBox.Text, shouldFire, shouldFire)
					if InputSettings.RemoveTextAfterFocusLost then
						applyText("", false, false)
					end
				end)

				ConnectComponent(InputV, Input.MouseEnter, function()
					if not InputV.Disabled then
						tween(Input.UIStroke, {Color = Color3.fromRGB(87, 84, 104)})
					end
				end)
				ConnectComponent(InputV, Input.MouseLeave, function()
					tween(Input.UIStroke, {Color = Color3.fromRGB(64,61,76)})
				end)

				function InputV:UpdateValue(value, silent)
					applyText(value, silent ~= true, false)
					return self
				end

				function InputV:Set(NewInputSettings)
					NewInputSettings = Kwargify(InputSettings, NewInputSettings or {})
					InputSettings = NewInputSettings
					InputV.Settings = NewInputSettings
					Input.Name = tostring(InputSettings.Name)
					Input.Title.Text = tostring(InputSettings.Name)
					TextBox.PlaceholderText = tostring(InputSettings.PlaceholderText or "")
					if Input:FindFirstChild("Desc") then
						Input.Desc.Text = tostring(InputSettings.Description or "")
					end
					local shouldFire = NewInputSettings.Silent ~= true
						and InputSettings.FireOnSet ~= false
					applyText(
						InputSettings.CurrentValue,
						shouldFire,
						NewInputSettings.ForceCallback == true
					)
					return self
				end

				function InputV:Destroy()
					RemoveOption(InputV)
					if Input.Parent then Input:Destroy() end
				end

				if Flag then RegisterOption(Flag, InputV) end
				InputV._Object = Input
				InputV = EnhanceComponent(InputV)
				applyText(InputSettings.CurrentValue, false, false)
				if InputSettings.FireOnInit then
					emitCallback(InputV.CurrentValue)
				end
				return InputV
			end
			-- Dropdown
			function Section:CreateDropdown(DropdownSettings, Flag)
				TabPage.Position = UDim2.new(0,0,0,28)
				local DropdownV = { IgnoreConfig = false, Class = "Dropdown", Settings = DropdownSettings}
				local PlayerConnections = {}
				local OptionConnections = {}

				DropdownSettings = Kwargify({
					Name = "Dropdown",
					Description = nil,
					Options = {"Option 1", "Option 2"},
					CurrentOption = {"Option 1"},
					MultipleOptions = false,
					SpecialType = nil, -- supports "Player"
					AllowLocalPlayer = false,
					ReturnPlayerInstance = false,
					SortPlayers = true,
					AutoSelectFirst = true,
					FireOnInit = false,
					Callback = function(Options)
						-- The function that takes place when the selected option is changed
						-- The variable (Options) is a table of strings for the current selected options or a string if multioptions is false
					end,
				}, DropdownSettings or {})

				DropdownV.CurrentOption = DropdownSettings.CurrentOption

				local descriptionbool = false
				if DropdownSettings.Description ~= nil and DropdownSettings.Description ~= "" then
					descriptionbool = true
				end
				local closedsize
				local openedsize
				if descriptionbool then
					closedsize = 48
					openedsize = 170
				elseif not descriptionbool then
					closedsize = 38
					openedsize = 160
				end
				local opened = false

				local Dropdown
				if descriptionbool then Dropdown = Elements.Template.DropdownDesc:Clone() else Dropdown = Elements.Template.Dropdown:Clone() end

				Dropdown.Name = DropdownSettings.Name
				Dropdown.Title.Text = DropdownSettings.Name
				if descriptionbool then Dropdown.Desc.Text = DropdownSettings.Description end

				Dropdown.Parent = TabPage
				Dropdown.Visible = true

				local function Toggle()
					opened = not opened
					if opened then
						local optionCount = math.clamp(#DropdownSettings.Options, 1, 6)
						local dynamicOpenedSize = math.max(openedsize, closedsize + 35 + optionCount * 24)
						tween(Dropdown.icon, {Rotation = 180})
						tween(Dropdown, {Size = UDim2.new(1, -25, 0, dynamicOpenedSize)})
					else
						tween(Dropdown.icon, {Rotation = 0})
						tween(Dropdown, {Size = UDim2.new(1, -25, 0, closedsize)})
					end
				end

				local function SafeCallback(param, c2, silent)
					if silent == true then
						if c2 then c2() end
						return true
					end
					local callbackParam = param
					if DropdownSettings.SpecialType == "Player" and DropdownSettings.ReturnPlayerInstance then
						if type(param) == "string" then
							callbackParam = Players:FindFirstChild(param)
						elseif type(param) == "table" then
							callbackParam = {}
							for _, name in ipairs(param) do
								local target = Players:FindFirstChild(tostring(name))
								if target then table.insert(callbackParam, target) end
							end
						end
					end
					local Success, Response = pcall(function()
						DropdownSettings.Callback(callbackParam)
					end)
					if not Success then
						TweenService:Create(Dropdown, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0}):Play()
						TweenService:Create(Dropdown, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {BackgroundColor3 = Color3.fromRGB(85, 0, 0)}):Play()
						TweenService:Create(Dropdown.UIStroke, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {Transparency = 1}):Play()
						Dropdown.Title.Text = "Callback Error"
						print("Luna Interface Suite | "..DropdownSettings.Name.." Callback Error " ..tostring(Response))
						task.wait(0.5)
						Dropdown.Title.Text = DropdownSettings.Name
						TweenService:Create(Dropdown, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0.5}):Play()
						TweenService:Create(Dropdown, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {BackgroundColor3 = Color3.fromRGB(32, 30, 38)}):Play()
						TweenService:Create(Dropdown.UIStroke, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {Transparency = 0.5}):Play()
					end
					if Success and c2 then
						c2()
					end
				end

				-- fixed by justhey
				ConnectComponent(DropdownV, Dropdown.Selected:GetPropertyChangedSignal("Text"), function()
					local text = Dropdown.Selected.Text:lower()
					for _, Item in ipairs(Dropdown.List:GetChildren()) do
						if Item:IsA("TextLabel") and Item.Name ~= "Template" then
							Item.Visible = text == "" or string.find(Item.Name:lower(), text, 1, true) ~= nil
						end
					end
				end)


				local function Clear()
					DisconnectConnections(OptionConnections)
					for _, option in ipairs(Dropdown.List:GetChildren()) do
						if option.ClassName == "TextLabel" and option.Name ~= "Template" then
							option:Destroy()
						end
					end
				end

				local function ActivateColorSingle(name)
					for _, Option in pairs(Dropdown.List:GetChildren()) do
						if Option.ClassName == "TextLabel" and Option.Name ~= "Template" then
							tween(Option, {BackgroundTransparency = 0.98})
						end
					end

					Toggle()
					local targetOption = name and Dropdown.List:FindFirstChild(tostring(name)); if targetOption then tween(targetOption, {BackgroundTransparency = 0.95, TextColor3 = Color3.fromRGB(240,240,240)}) end
				end

				local function Refresh()
					Clear()
					for i,v in pairs(DropdownSettings.Options) do
						local Option = Dropdown.List.Template:Clone()
						local optionhover = false
						Option.Text = v
						if v == "Template" then v = "Template (Name)" end
						Option.Name = v
						TrackConnection(Option.Interact.MouseButton1Click:Connect(function()
							local bleh
							if DropdownSettings.MultipleOptions then
								if table.find(DropdownSettings.CurrentOption, v) then
									RemoveTable(DropdownSettings.CurrentOption, v)
									DropdownV.CurrentOption = DropdownSettings.CurrentOption
									if not optionhover then
										tween(Option, {TextColor3 = Color3.fromRGB(200,200,200)})
									end
									tween(Option, {BackgroundTransparency = 0.98})
								else
									table.insert(DropdownSettings.CurrentOption, v)
									DropdownV.CurrentOption = DropdownSettings.CurrentOption
									tween(Option, {TextColor3 = Color3.fromRGB(240,240,240), BackgroundTransparency = 0.95})
								end
								bleh = DropdownSettings.CurrentOption
							else
								DropdownSettings.CurrentOption = {v}
								bleh = v
								DropdownV.CurrentOption = bleh
								ActivateColorSingle(v)
							end

							SafeCallback(bleh, function()
								if DropdownSettings.MultipleOptions then
									if DropdownSettings.CurrentOption and type(DropdownSettings.CurrentOption) == "table" then
										if #DropdownSettings.CurrentOption == 1 then
											Dropdown.Selected.PlaceholderText = DropdownSettings.CurrentOption[1]
										elseif #DropdownSettings.CurrentOption == 0 then
											Dropdown.Selected.PlaceholderText = "None"
										else
											Dropdown.Selected.PlaceholderText = unpackt(DropdownSettings.CurrentOption)
										end
									else
										DropdownSettings.CurrentOption = {}
										Dropdown.Selected.PlaceholderText = "None"
									end
								end
								if not DropdownSettings.MultipleOptions then
									Dropdown.Selected.PlaceholderText = DropdownSettings.CurrentOption[1] or "None"
								end
								Dropdown.Selected.Text = ""
							end)
						end), OptionConnections)
						Option.Visible = true
						Option.Parent = Dropdown.List
						TrackConnection(Option.MouseEnter:Connect(function()
							optionhover = true
							if Option.BackgroundTransparency == 0.95 then
								return
							else
								tween(Option, {TextColor3 = Color3.fromRGB(240,240,240)})
							end
						end), OptionConnections)
						TrackConnection(Option.MouseLeave:Connect(function()
							optionhover = false
							if Option.BackgroundTransparency == 0.95 then
								return
							else
								tween(Option, {TextColor3 = Color3.fromRGB(200,200,200)})
							end
						end), OptionConnections)	
					end
				end

				local function PlayerTableRefresh()
					table.clear(DropdownSettings.Options)
					for _, player in ipairs(Players:GetPlayers()) do
						if DropdownSettings.AllowLocalPlayer or player ~= Player then
							table.insert(DropdownSettings.Options, player.Name)
						end
					end
					if DropdownSettings.SortPlayers then table.sort(DropdownSettings.Options) end

					local current = DropdownSettings.CurrentOption
					if type(current) == "string" then current = {current} end
					if type(current) ~= "table" then current = {} end
					local valid = {}
					for _, name in ipairs(current) do
						if table.find(DropdownSettings.Options, name) then table.insert(valid, name) end
					end
					if not DropdownSettings.MultipleOptions and #valid == 0 and DropdownSettings.AutoSelectFirst and DropdownSettings.Options[1] then
						valid = {DropdownSettings.Options[1]}
					end
					DropdownSettings.CurrentOption = valid
					DropdownV.CurrentOption = DropdownSettings.MultipleOptions and valid or valid[1]
				end

				ConnectComponent(DropdownV, Dropdown.Interact.MouseButton1Click, function()
					Toggle()
				end)

				ConnectComponent(DropdownV, Dropdown.MouseEnter, function()
					tween(Dropdown.UIStroke, {Color = Color3.fromRGB(87, 84, 104)})
				end)

				ConnectComponent(DropdownV, Dropdown.MouseLeave, function()
					tween(Dropdown.UIStroke, {Color = Color3.fromRGB(64,61,76)})
				end)

				if DropdownSettings.SpecialType == "Player" then
					DropdownV.IgnoreConfig = true
					PlayerTableRefresh()

					local function refreshPlayers()
						if not Dropdown.Parent then return end
						PlayerTableRefresh()
						Refresh()
						Dropdown.Selected.PlaceholderText = DropdownSettings.CurrentOption[1] or "None"
						local value = DropdownSettings.MultipleOptions and DropdownSettings.CurrentOption or DropdownSettings.CurrentOption[1]
						SafeCallback(value)
					end
					TrackConnection(Players.PlayerAdded:Connect(function() task.defer(refreshPlayers) end), PlayerConnections)
					TrackConnection(Players.PlayerRemoving:Connect(function() task.defer(refreshPlayers) end), PlayerConnections)
					TrackConnection(Dropdown.AncestryChanged:Connect(function(_, parent)
						if parent == nil then DisconnectConnections(PlayerConnections) end
					end), PlayerConnections)
				end

				Refresh()

				if DropdownSettings.CurrentOption then
					if type(DropdownSettings.CurrentOption) == "string" then
						DropdownSettings.CurrentOption = {DropdownSettings.CurrentOption}
					end
					if not DropdownSettings.MultipleOptions and type(DropdownSettings.CurrentOption) == "table" then
						DropdownSettings.CurrentOption = {DropdownSettings.CurrentOption[1]}
					end
				else
					DropdownSettings.CurrentOption = {}
				end

				local bleh, ind = nil,0
				for i,v in pairs(DropdownSettings.CurrentOption) do
					ind = ind + 1
				end
				if ind == 1 then bleh = DropdownSettings.CurrentOption[1] else bleh = DropdownSettings.CurrentOption end
				if DropdownSettings.FireOnInit then SafeCallback(bleh) end
				if type(bleh) == "string" then 
					local targetOption = bleh and Dropdown.List:FindFirstChild(tostring(bleh)); if targetOption then tween(targetOption, {TextColor3 = Color3.fromRGB(240,240,240), BackgroundTransparency = 0.95}) end
				else
					for i,v in pairs(bleh) do
						local targetOption = v and Dropdown.List:FindFirstChild(tostring(v)); if targetOption then tween(targetOption, {TextColor3 = Color3.fromRGB(240,240,240), BackgroundTransparency = 0.95}) end
					end
				end

				if DropdownSettings.MultipleOptions then
					if DropdownSettings.CurrentOption and type(DropdownSettings.CurrentOption) == "table" then
						if #DropdownSettings.CurrentOption == 1 then
							Dropdown.Selected.PlaceholderText = DropdownSettings.CurrentOption[1]
						elseif #DropdownSettings.CurrentOption == 0 then
							Dropdown.Selected.PlaceholderText = "None"
						else
							Dropdown.Selected.PlaceholderText = unpackt(DropdownSettings.CurrentOption)
						end
					else
						DropdownSettings.CurrentOption = {}
						Dropdown.Selected.PlaceholderText = "None"
					end
					for _, name in pairs(DropdownSettings.CurrentOption) do
						local targetOption = name and Dropdown.List:FindFirstChild(tostring(name)); if targetOption then tween(targetOption, {TextColor3 = Color3.fromRGB(227,227,227), BackgroundTransparency = 0.95}) end
					end
				else
					Dropdown.Selected.PlaceholderText = DropdownSettings.CurrentOption[1] or "None"
				end
				Dropdown.Selected.Text = ""

				function DropdownV:Set(NewDropdownSettings)
					NewDropdownSettings = Kwargify(DropdownSettings, NewDropdownSettings or {})

					DropdownV.Settings = NewDropdownSettings
					DropdownSettings = NewDropdownSettings

					Dropdown.Name = DropdownSettings.Name
					Dropdown.Title.Text = DropdownSettings.Name
					if DropdownSettings.Description ~= nil and DropdownSettings.Description ~= "" and Dropdown.Desc ~= nil then
						Dropdown.Desc.Text = DropdownSettings.Description
					end

					if DropdownSettings.SpecialType == "Player" then
						DropdownV.IgnoreConfig = true
						PlayerTableRefresh()
					end

					Refresh()

					if DropdownSettings.CurrentOption then
						if type(DropdownSettings.CurrentOption) == "string" then
							DropdownSettings.CurrentOption = {DropdownSettings.CurrentOption}
						end
						if not DropdownSettings.MultipleOptions and type(DropdownSettings.CurrentOption) == "table" then
							DropdownSettings.CurrentOption = {DropdownSettings.CurrentOption[1]}
						end
					else
						DropdownSettings.CurrentOption = {}
					end

					local bleh, ind = nil,0
					for i,v in pairs(DropdownSettings.CurrentOption) do
						ind = ind + 1
					end
					if ind == 1 then bleh = DropdownSettings.CurrentOption[1] else bleh = DropdownSettings.CurrentOption end
					DropdownV.CurrentOption = DropdownSettings.CurrentOption
					SafeCallback(bleh, nil, NewDropdownSettings.Silent == true)
					for _, Option in pairs(Dropdown.List:GetChildren()) do
						if Option.ClassName == "TextLabel" then
							tween(Option, {TextColor3 = Color3.fromRGB(200,200,200), BackgroundTransparency = 0.98})
						end
					end
					local targetOption = bleh and Dropdown.List:FindFirstChild(tostring(bleh)); if targetOption then tween(targetOption, {TextColor3 = Color3.fromRGB(240,240,240), BackgroundTransparency = 0.95}) end

					if DropdownSettings.MultipleOptions then
						if DropdownSettings.CurrentOption and type(DropdownSettings.CurrentOption) == "table" then
							if #DropdownSettings.CurrentOption == 1 then
								Dropdown.Selected.PlaceholderText = DropdownSettings.CurrentOption[1]
							elseif #DropdownSettings.CurrentOption == 0 then
								Dropdown.Selected.PlaceholderText = "None"
							else
								Dropdown.Selected.PlaceholderText = unpackt(DropdownSettings.CurrentOption)
							end
						else
							DropdownSettings.CurrentOption = {}
							Dropdown.Selected.PlaceholderText = "None"
						end
						for _, name in pairs(DropdownSettings.CurrentOption) do
							local targetOption = name and Dropdown.List:FindFirstChild(tostring(name)); if targetOption then tween(targetOption, {TextColor3 = Color3.fromRGB(227,227,227), BackgroundTransparency = 0.95}) end
						end
					else
						Dropdown.Selected.PlaceholderText = DropdownSettings.CurrentOption[1] or "None"
					end
					Dropdown.Selected.Text = ""

					-- Luna.Flags[DropdownSettings.Flag] = DropdownSettings
					return self
				end

				function DropdownV:Destroy()
					DisconnectConnections(PlayerConnections)
					DisconnectConnections(OptionConnections)
					RemoveOption(DropdownV)
					Dropdown.Visible = false
					Dropdown:Destroy()
				end

				if Flag then
					RegisterOption(Flag, DropdownV)
				end

				-- Luna.Flags[DropdownSettings.Flag] = DropdownSettings

				DropdownV._Object = Dropdown

				return EnhanceComponent(DropdownV)

			end

			-- Color Picker
			function Section:CreateColorPicker(ColorPickerSettings, Flag)
				TabPage.Position = UDim2.new(0,0,0,28)
				local ColorPickerV = {IgnoreClass = false, Class = "Colorpicker", Settings = ColorPickerSettings}

				ColorPickerSettings = Kwargify({
					Name = "Color Picker",
					Color = Color3.fromRGB(255,255,255),
					Alpha = 0,
					FireOnInit = false,
					FireOnSet = true,
					CallbackInterval = 0.03,
					Callback = function(value) end,
					OnFinished = function(value) end,
				}, ColorPickerSettings or {})

				if typeof(ColorPickerSettings.Color) ~= "Color3" then ColorPickerSettings.Color = Color3.new(1,1,1) end
				local ColorPicker = Elements.Template.ColorPicker:Clone()
				local Background = ColorPicker.CPBackground
				local Display = Background.Display
				local Main = Background.MainCP
				local HueSlider = ColorPicker.ColorSlider
				local closedSize = UDim2.new(0, 75, 0, 22)
				local openedSize = UDim2.new(0, 219, 0, 129)
				local opened = false
				local dragMode
				local activeInput
				local h, s, v = ColorPickerSettings.Color:ToHSV()
				local lastCallback = -math.huge

				ColorPicker.Name = tostring(ColorPickerSettings.Name)
				ColorPicker.Title.Text = tostring(ColorPickerSettings.Name)
				ColorPicker.Visible = true
				ColorPicker.Parent = TabPage
				ColorPicker.Size = UDim2.new(1.042, -25, 0, 38)
				Background.Size = closedSize
				Display.BackgroundTransparency = 0
				Main.Image = "http://www.roblox.com/asset/?id=11415645739"

				local function colorToHex(color)
					return string.format("#%02X%02X%02X", math.floor(color.R*255+0.5), math.floor(color.G*255+0.5), math.floor(color.B*255+0.5))
				end

				local function emit(color, force)
					if not IsComponentUsable(ColorPickerV) then return end
					local interval = math.max(0, tonumber(ColorPickerSettings.CallbackInterval) or 0.03)
					if not force and os.clock() - lastCallback < interval then return end
					lastCallback = os.clock()
					SafeCall(ColorPickerSettings.Callback, color)
				end

				local function finish(color)
					if IsComponentUsable(ColorPickerV) then SafeCall(ColorPickerSettings.OnFinished, color) end
				end

				local function updateDisplay()
					local color = Color3.fromHSV(h,s,v)
					Main.MainPoint.Position = UDim2.new(s, -Main.MainPoint.AbsoluteSize.X/2, 1-v, -Main.MainPoint.AbsoluteSize.Y/2)
					Main.MainPoint.ImageColor3 = color
					Background.BackgroundColor3 = Color3.fromHSV(h,1,1)
					Display.BackgroundColor3 = color
					local x = h * HueSlider.AbsoluteSize.X
					HueSlider.SliderPoint.Position = UDim2.new(0, x-HueSlider.SliderPoint.AbsoluteSize.X/2, 0.5, 0)
					HueSlider.SliderPoint.ImageColor3 = Color3.fromHSV(h,1,1)
					local rr,gg,bb = math.floor(color.R*255+0.5), math.floor(color.G*255+0.5), math.floor(color.B*255+0.5)
					ColorPicker.RInput.InputBox.Text = tostring(rr)
					ColorPicker.GInput.InputBox.Text = tostring(gg)
					ColorPicker.BInput.InputBox.Text = tostring(bb)
					ColorPicker.HexInput.InputBox.Text = colorToHex(color)
					ColorPickerSettings.Color = color
					ColorPickerV.Color = color
					ColorPickerV.Alpha = tonumber(ColorPickerSettings.Alpha) or 0
					return color
				end

				local function setColor(color, fireCallback, force)
					if typeof(color) ~= "Color3" then return ColorPickerV.Color end
					h,s,v = color:ToHSV()
					local updated = updateDisplay()
					if fireCallback then emit(updated, force) end
					return updated
				end

				local function inputPosition(input)
					if input and input.UserInputType == Enum.UserInputType.Touch then return input.Position end
					return UserInputService:GetMouseLocation()
				end

				local function updateDrag(input)
					if not dragMode or not IsComponentUsable(ColorPickerV) then return end
					local pos = inputPosition(input)
					if dragMode == "main" then
						if Main.AbsoluteSize.X <= 0 or Main.AbsoluteSize.Y <= 0 then return end
						s = math.clamp((pos.X-Main.AbsolutePosition.X)/Main.AbsoluteSize.X, 0, 1)
						v = 1-math.clamp((pos.Y-Main.AbsolutePosition.Y)/Main.AbsoluteSize.Y, 0, 1)
					else
						if HueSlider.AbsoluteSize.X <= 0 then return end
						h = math.clamp((pos.X-HueSlider.AbsolutePosition.X)/HueSlider.AbsoluteSize.X, 0, 1)
					end
					emit(updateDisplay(), false)
				end

				local function beginDrag(mode, input)
					if not opened or not IsComponentUsable(ColorPickerV) then return end
					if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
					dragMode = mode
					activeInput = input
					updateDrag(input)
				end

				ConnectComponent(ColorPickerV, ColorPicker.MouseEnter, function()
					if not ColorPickerV.Disabled then tween(ColorPicker.UIStroke, {Color = Color3.fromRGB(87,84,104)}) end
				end)
				ConnectComponent(ColorPickerV, ColorPicker.MouseLeave, function()
					tween(ColorPicker.UIStroke, {Color = Color3.fromRGB(64,61,76)})
				end)
				ConnectComponent(ColorPickerV, ColorPicker.Interact.MouseButton1Click, function()
					if not IsComponentUsable(ColorPickerV) then return end
					opened = not opened
					if opened then
						tween(ColorPicker, {Size = UDim2.new(1.042,-25,0,165)}, nil, TweenInfo.new(0.4, Enum.EasingStyle.Exponential))
						tween(Background, {Size = openedSize})
						tween(Display, {BackgroundTransparency = 1})
					else
						tween(ColorPicker, {Size = UDim2.new(1.042,-25,0,38)}, nil, TweenInfo.new(0.4, Enum.EasingStyle.Exponential))
						tween(Background, {Size = closedSize})
						tween(Display, {BackgroundTransparency = 0})
					end
				end)
				ConnectComponent(ColorPickerV, Main.InputBegan, function(input) beginDrag("main", input) end)
				ConnectComponent(ColorPickerV, Main.MainPoint.InputBegan, function(input) beginDrag("main", input) end)
				ConnectComponent(ColorPickerV, HueSlider.InputBegan, function(input) beginDrag("hue", input) end)
				ConnectComponent(ColorPickerV, HueSlider.SliderPoint.InputBegan, function(input) beginDrag("hue", input) end)
				ConnectComponent(ColorPickerV, UserInputService.InputChanged, function(input)
					if not dragMode then return end
					if activeInput and activeInput.UserInputType == Enum.UserInputType.Touch then
						if input ~= activeInput then return end
					elseif input.UserInputType ~= Enum.UserInputType.MouseMovement then
						return
					end
					updateDrag(input)
				end)
				ConnectComponent(ColorPickerV, UserInputService.InputEnded, function(input)
					if dragMode and (input == activeInput or input.UserInputType == Enum.UserInputType.MouseButton1) then
						local color = updateDisplay()
						dragMode = nil
						activeInput = nil
						emit(color, true)
						finish(color)
					end
				end)

				ConnectComponent(ColorPickerV, ColorPicker.HexInput.InputBox.FocusLost, function()
					local rr,gg,bb = ColorPicker.HexInput.InputBox.Text:match("^#?(%x%x)(%x%x)(%x%x)$")
					if not rr then ColorPicker.HexInput.InputBox.Text = colorToHex(ColorPickerV.Color); return end
					local color = Color3.fromRGB(tonumber(rr,16), tonumber(gg,16), tonumber(bb,16))
					setColor(color, true, true)
					finish(color)
				end)

				local function applyRgb(channel, box)
					local color = ColorPickerV.Color or Color3.new(1,1,1)
					local rr,gg,bb = math.floor(color.R*255+0.5), math.floor(color.G*255+0.5), math.floor(color.B*255+0.5)
					local value = tonumber(box.Text)
					if not value then updateDisplay(); return end
					value = math.clamp(math.floor(value+0.5), 0, 255)
					if channel == "R" then rr=value elseif channel == "G" then gg=value else bb=value end
					local updated = Color3.fromRGB(rr,gg,bb)
					setColor(updated, true, true)
					finish(updated)
				end
				ConnectComponent(ColorPickerV, ColorPicker.RInput.InputBox.FocusLost, function() applyRgb("R", ColorPicker.RInput.InputBox) end)
				ConnectComponent(ColorPickerV, ColorPicker.GInput.InputBox.FocusLost, function() applyRgb("G", ColorPicker.GInput.InputBox) end)
				ConnectComponent(ColorPickerV, ColorPicker.BInput.InputBox.FocusLost, function() applyRgb("B", ColorPicker.BInput.InputBox) end)

				function ColorPickerV:Set(NewColorPickerSettings)
					NewColorPickerSettings = Kwargify(ColorPickerSettings, NewColorPickerSettings or {})
					ColorPickerSettings = NewColorPickerSettings
					ColorPickerV.Settings = NewColorPickerSettings
					ColorPicker.Name = tostring(ColorPickerSettings.Name)
					ColorPicker.Title.Text = tostring(ColorPickerSettings.Name)
					ColorPickerSettings.Alpha = math.clamp(tonumber(ColorPickerSettings.Alpha) or 0, 0, 1)
					local shouldFire = NewColorPickerSettings.Silent ~= true and ColorPickerSettings.FireOnSet ~= false
					setColor(ColorPickerSettings.Color, shouldFire, true)
					return ColorPickerV
				end

				function ColorPickerV:Destroy()
					RemoveOption(ColorPickerV)
					if ColorPicker.Parent then ColorPicker:Destroy() end
				end

				if Flag then RegisterOption(Flag, ColorPickerV) end
				ColorPickerV._Object = ColorPicker
				ColorPickerV = EnhanceComponent(ColorPickerV)
				setColor(ColorPickerSettings.Color, ColorPickerSettings.FireOnInit == true, true)
				return ColorPickerV
			end

			Section._Header = Sectiont
			Section._Body = TabPage
			Section._Object = Sectiont
			EnhanceComponent(Section)
			Section._Window = Window
			Section._Tab = Tab
			EnhanceContainerAPI(Section, TabPage, Window, Tab, {
				Name = Section.Name,
				Header = Sectiont,
				IsSection = true,
			})
			EnhanceCollapsibleSection(Section, SectionSettings)
			return Section

		end

		-- Divider
		function Tab:CreateDivider()
			local b = Elements.Template.Divider:Clone()
			b.Parent = TabPage
			b.Line.BackgroundTransparency = 1
			tween(b.Line, {BackgroundTransparency = 0})
		end

		-- Button
		function Tab:CreateButton(ButtonSettings)

			ButtonSettings = Kwargify({
				Name = "Button",
				Description = nil,
				Callback = function()

				end,
			}, ButtonSettings or {})

			local ButtonV = {
				Hover = false,
				Settings = ButtonSettings
			}


			local Button
			if ButtonSettings.Description == nil or ButtonSettings.Description == "" then
				Button = Elements.Template.Button:Clone()
			else
				Button = Elements.Template.ButtonDesc:Clone()
			end
			Button.Name = ButtonSettings.Name
			Button.Title.Text = ButtonSettings.Name
			if ButtonSettings.Description ~= nil and ButtonSettings.Description ~= "" then
				Button.Desc.Text = ButtonSettings.Description
			end
			Button.Visible = true
			Button.Parent = TabPage

			Button.UIStroke.Transparency = 1
			Button.Title.TextTransparency = 1
			if ButtonSettings.Description ~= nil and ButtonSettings.Description ~= "" then
				Button.Desc.TextTransparency = 1
			end

			TweenService:Create(Button, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0.5}):Play()
			TweenService:Create(Button.UIStroke, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {Transparency = 0.5}):Play()
			TweenService:Create(Button.Title, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {TextTransparency = 0}):Play()	
			if ButtonSettings.Description ~= nil and ButtonSettings.Description ~= "" then
				TweenService:Create(Button.Desc, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {TextTransparency = 0}):Play()	
			end

			ConnectComponent(ButtonV, Button.Interact.MouseButton1Click, function()
				local Success,Response = pcall(ButtonSettings.Callback)

				if not Success then
					TweenService:Create(Button, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0}):Play()
					TweenService:Create(Button, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {BackgroundColor3 = Color3.fromRGB(85, 0, 0)}):Play()
					TweenService:Create(Button.UIStroke, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {Transparency = 1}):Play()
					Button.Title.Text = "Callback Error"
					print("Luna Interface Suite | "..ButtonSettings.Name.." Callback Error " ..tostring(Response))
					task.wait(0.5)
					Button.Title.Text = ButtonSettings.Name
					TweenService:Create(Button, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0.5}):Play()
					TweenService:Create(Button, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {BackgroundColor3 = Color3.fromRGB(32, 30, 38)}):Play()
					TweenService:Create(Button.UIStroke, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {Transparency = 0.5}):Play()
				else
					tween(Button.UIStroke, {Color = Color3.fromRGB(136, 131, 163)})
					task.wait(0.2)
					if ButtonV.Hover then
						tween(Button.UIStroke, {Color = Color3.fromRGB(87, 84, 104)})
					else
						tween(Button.UIStroke, {Color = Color3.fromRGB(64,61,76)})
					end
				end
			end)

			ConnectComponent(ButtonV, Button.MouseEnter, function()
				ButtonV.Hover = true
				tween(Button.UIStroke, {Color = Color3.fromRGB(87, 84, 104)})
			end)

			ConnectComponent(ButtonV, Button.MouseLeave, function()
				ButtonV.Hover = false
				tween(Button.UIStroke, {Color = Color3.fromRGB(64,61,76)})
			end)

			function ButtonV:Set(ButtonSettings2)
				ButtonSettings2 = Kwargify({
					Name = ButtonSettings.Name,
					Description = ButtonSettings.Description,
					Callback = ButtonSettings.Callback
				}, ButtonSettings2 or {})

				ButtonSettings = ButtonSettings2
				ButtonV.Settings = ButtonSettings2

				Button.Name = ButtonSettings.Name
				Button.Title.Text = ButtonSettings.Name
				if ButtonSettings.Description ~= nil and ButtonSettings.Description ~= "" and Button.Desc ~= nil then
					Button.Desc.Text = ButtonSettings.Description
				end
			end

			function ButtonV:Destroy()
				RemoveOption(ButtonV)
				Button.Visible = false
				Button:Destroy()
			end

			ButtonV._Object = Button

			return EnhanceComponent(ButtonV)
		end

		-- Label
		function Tab:CreateLabel(LabelSettings)

			local LabelV = {}

			LabelSettings = Kwargify({
				Text = "Label",
				Style = 1
			}, LabelSettings or {}) 

			LabelV.Settings = LabelSettings

			local Label
			if LabelSettings.Style == 1 then
				Label = Elements.Template.Label:Clone()
			elseif LabelSettings.Style == 2 then
				Label = Elements.Template.Info:Clone()
			elseif LabelSettings.Style == 3 then
				Label = Elements.Template.Warn:Clone()
			end

			Label.Text.Text = LabelSettings.Text
			Label.Visible = true
			Label.Parent = TabPage

			Label.BackgroundTransparency = 1
			Label.UIStroke.Transparency = 1
			Label.Text.TextTransparency = 1

			if LabelSettings.Style ~= 1 then
				TweenService:Create(Label, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0.8}):Play()
			else
				TweenService:Create(Label, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {BackgroundTransparency = 1}):Play()
			end
			TweenService:Create(Label.UIStroke, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {Transparency = 0.5}):Play()
			TweenService:Create(Label.Text, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {TextTransparency = 0}):Play()	

			function LabelV:Set(NewLabel)
				LabelSettings.Text = NewLabel
				LabelV.Settings = LabelSettings
				Label.Text.Text = NewLabel
			end

			function LabelV:Destroy()
				RemoveOption(LabelV)
				Label.Visible = false
				Label:Destroy()
			end

			LabelV._Object = Label

			return EnhanceComponent(LabelV)
		end

		-- Paragraph
		function Tab:CreateParagraph(ParagraphSettings)

			ParagraphSettings = Kwargify({
				Title = "Paragraph",
				Text = "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Vivamus venenatis lacus sed tempus eleifend. Mauris interdum bibendum felis, in tempor augue egestas vel. Praesent tristique consectetur ex, eu pretium sem placerat non. Vestibulum a nisi sit amet augue facilisis consectetur sit amet et nunc. Integer fermentum ornare cursus. Pellentesque sed ultricies metus, ut egestas metus. Vivamus auctor erat ac sapien vulputate, nec ultricies sem tempor. Quisque leo lorem, faucibus nec pulvinar nec, congue eu velit. Duis sodales massa efficitur imperdiet ultrices. Donec eros ipsum, ornare pharetra purus aliquam, tincidunt elementum nisi. Ut mi tortor, feugiat eget nunc vitae, facilisis interdum dui. Vivamus ullamcorper nunc dui, a dapibus nisi pretium ac. Integer eleifend placerat nibh, maximus malesuada tellus. Cras in justo in ligula scelerisque suscipit vel vitae quam."
			}, ParagraphSettings or {})

			local ParagraphV = {
				Settings = ParagraphSettings
			}

			local Paragraph = Elements.Template.Paragraph:Clone()
			Paragraph.Title.Text = ParagraphSettings.Title
			Paragraph.Text.Text = ParagraphSettings.Text
			Paragraph.Visible = true
			Paragraph.Parent = TabPage

			Paragraph.BackgroundTransparency = 1
			Paragraph.UIStroke.Transparency = 1
			Paragraph.Title.TextTransparency = 1
			Paragraph.Text.TextTransparency = 1

			TweenService:Create(Paragraph, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {BackgroundTransparency = 1}):Play()
			TweenService:Create(Paragraph.UIStroke, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {Transparency = 0.5}):Play()
			TweenService:Create(Paragraph.Title, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {TextTransparency = 0}):Play()	
			TweenService:Create(Paragraph.Text, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {TextTransparency = 0}):Play()	

			function ParagraphV:Update()
				Paragraph.Text.Size = UDim2.new(Paragraph.Text.Size.X.Scale, Paragraph.Text.Size.X.Offset, 0, math.huge)
				Paragraph.Text.Size = UDim2.new(Paragraph.Text.Size.X.Scale, Paragraph.Text.Size.X.Offset, 0, Paragraph.Text.TextBounds.Y)
				tween(Paragraph, {Size = UDim2.new(Paragraph.Size.X.Scale, Paragraph.Size.X.Offset, 0, Paragraph.Text.TextBounds.Y + 40)})
			end

			function ParagraphV:Set(NewParagraphSettings)

				NewParagraphSettings = Kwargify({
					Title = ParagraphSettings.Title,
					Text = ParagraphSettings.Text
				}, NewParagraphSettings or {})

				ParagraphV.Settings = NewParagraphSettings

				Paragraph.Title.Text = NewParagraphSettings.Title
				Paragraph.Text.Text = NewParagraphSettings.Text

				ParagraphV:Update()

			end

			function ParagraphV:Destroy()
				RemoveOption(ParagraphV)
				Paragraph.Visible = false
				Paragraph:Destroy()
			end

			ParagraphV:Update()

			ParagraphV._Object = Paragraph

			return EnhanceComponent(ParagraphV)
		end

		-- Slider
		function Tab:CreateSlider(SliderSettings, Flag)
			local SliderV = {IgnoreConfig = false, Class = "Slider", Settings = SliderSettings}

			SliderSettings = Kwargify({
				Name = "Slider",
				Range = {0, 200},
				Increment = 1,
				CurrentValue = 100,
				FireOnInit = false,
				FireOnSet = true,
				CallbackInterval = 0.03,
				Callback = function(Value) end,
				OnFinished = function(Value) end,
			}, SliderSettings or {})
			SliderV.Settings = SliderSettings

			local Slider = Elements.Template.Slider:Clone()
			Slider.Name = tostring(SliderSettings.Name) .. " - Slider"
			Slider.Title.Text = tostring(SliderSettings.Name)
			Slider.Visible = true
			Slider.Parent = TabPage
			Slider.BackgroundTransparency = 1
			Slider.UIStroke.Transparency = 1
			Slider.Title.TextTransparency = 1

			TweenService:Create(Slider, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0.5}):Play()
			TweenService:Create(Slider.UIStroke, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {Transparency = 0.5}):Play()
			TweenService:Create(Slider.Title, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {TextTransparency = 0}):Play()

			local updatingText = false
			local dragging = false
			local activeInput
			local lastCallbackAt = -math.huge

			local function normalizedRange()
				local range = type(SliderSettings.Range) == "table"
					and SliderSettings.Range or {0, 100}
				local minimum = tonumber(range[1]) or 0
				local maximum = tonumber(range[2]) or 100
				if minimum > maximum then minimum, maximum = maximum, minimum end
				local increment = math.abs(tonumber(SliderSettings.Increment) or 1)
				if increment <= 0 then increment = 1 end
				return minimum, maximum, increment
			end

			local function decimalPlaces(number)
				local output = string.format("%.6f", math.abs(tonumber(number) or 0))
				output = output:gsub("0+$", ""):gsub("%.$", "")
				local decimals = output:match("%.(%d+)$")
				return decimals and #decimals or 0
			end

			local function formatNumber(value, increment)
				local decimals = math.clamp(decimalPlaces(increment), 0, 6)
				local output = string.format("%." .. decimals .. "f", value)
				if decimals > 0 then
					output = output:gsub("(%..-)0+$", "%1"):gsub("%.$", "")
				end
				return output
			end

			local function setProgress(value)
				local minimum, maximum = normalizedRange()
				local width = math.max(0, Slider.Main.AbsoluteSize.X)
				local alpha = maximum == minimum and 0
					or math.clamp((value - minimum) / (maximum - minimum), 0, 1)
				Slider.Main.Progress.Size = UDim2.new(0, math.max(5, width * alpha), 1, 0)
			end

			local function emitCallback(value, force)
				local interval = math.max(0, tonumber(SliderSettings.CallbackInterval) or 0.03)
				local now = os.clock()
				if force == true or now - lastCallbackAt >= interval then
					lastCallbackAt = now
					SafeCall(SliderSettings.Callback, value)
					return true
				end
				return false
			end

			local function setValue(value, fireCallback, forceCallback)
				local minimum, maximum, increment = normalizedRange()
				value = tonumber(value) or tonumber(SliderSettings.CurrentValue) or minimum
				value = math.clamp(value, minimum, maximum)
				value = minimum + math.floor(((value - minimum) / increment) + 0.5) * increment
				value = math.clamp(value, minimum, maximum)
				value = math.floor(value * 1000000 + 0.5) / 1000000

				local changed = tonumber(SliderSettings.CurrentValue) ~= value
				SliderSettings.CurrentValue = value
				SliderV.CurrentValue = value
				updatingText = true
				Slider.Value.Text = formatNumber(value, increment)
				Slider.Value.Size = UDim2.fromOffset(math.max(20, Slider.Value.TextBounds.X), 23)
				updatingText = false
				setProgress(value)

				if fireCallback and (changed or forceCallback == true)
					and IsComponentUsable(SliderV)
				then
					emitCallback(value, forceCallback == true)
				end
				return value
			end

			local function inputX(input)
				if input and input.UserInputType == Enum.UserInputType.Touch then
					return input.Position.X
				end
				return UserInputService:GetMouseLocation().X
			end

			local function updateFromInput(input)
				if not dragging or not IsComponentUsable(SliderV) then return end
				local width = Slider.Main.AbsoluteSize.X
				if width <= 0 then return end
				local minimum, maximum = normalizedRange()
				local alpha = math.clamp(
					(inputX(input) - Slider.Main.AbsolutePosition.X) / width,
					0,
					1
				)
				setValue(minimum + alpha * (maximum - minimum), true, false)
			end

			ConnectComponent(SliderV, Slider.MouseEnter, function()
				if not SliderV.Disabled then
					tween(Slider.UIStroke, {Color = Color3.fromRGB(87, 84, 104)})
				end
			end)
			ConnectComponent(SliderV, Slider.MouseLeave, function()
				tween(Slider.UIStroke, {Color = Color3.fromRGB(64,61,76)})
			end)
			ConnectComponent(SliderV, Slider.Interact.InputBegan, function(input)
				if not IsComponentUsable(SliderV) then return end
				if input.UserInputType == Enum.UserInputType.MouseButton1
					or input.UserInputType == Enum.UserInputType.Touch
				then
					dragging = true
					activeInput = input
					updateFromInput(input)
				end
			end)
			ConnectComponent(SliderV, UserInputService.InputChanged, function(input)
				if not dragging then return end
				if activeInput and activeInput.UserInputType == Enum.UserInputType.Touch then
					if input ~= activeInput then return end
				elseif input.UserInputType ~= Enum.UserInputType.MouseMovement then
					return
				end
				updateFromInput(input)
			end)
			ConnectComponent(SliderV, UserInputService.InputEnded, function(input)
				if input == activeInput
					or input.UserInputType == Enum.UserInputType.MouseButton1
				then
					local wasDragging = dragging
					dragging = false
					activeInput = nil
					if wasDragging and IsComponentUsable(SliderV) then
						setValue(SliderV.CurrentValue, true, true)
						SafeCall(SliderSettings.OnFinished, SliderV.CurrentValue)
					end
				end
			end)

			if Slider.Value:IsA("TextBox") then
				ConnectComponent(SliderV, Slider.Value.FocusLost, function()
					if updatingText then return end
					setValue(Slider.Value.Text, true, true)
					SafeCall(SliderSettings.OnFinished, SliderV.CurrentValue)
				end)
			end

			ConnectComponent(SliderV, LunaUI.ThemeRemote:GetPropertyChangedSignal("Value"), function()
				if Slider.Parent then
					Slider.Main.color.Color = Luna.ThemeGradient
					Slider.Main.UIStroke.color.Color = Luna.ThemeGradient
				end
			end)

			function SliderV:UpdateValue(value, silent)
				setValue(value, silent ~= true, false)
				return self
			end

			function SliderV:Set(NewSliderSettings)
				NewSliderSettings = Kwargify(SliderSettings, NewSliderSettings or {})
				SliderSettings = NewSliderSettings
				SliderV.Settings = NewSliderSettings
				Slider.Name = tostring(SliderSettings.Name) .. " - Slider"
				Slider.Title.Text = tostring(SliderSettings.Name)
				local shouldFire = NewSliderSettings.Silent ~= true
					and SliderSettings.FireOnSet ~= false
				setValue(
					SliderSettings.CurrentValue,
					shouldFire,
					NewSliderSettings.ForceCallback == true
				)
				return self
			end

			function SliderV:Destroy()
				RemoveOption(SliderV)
				if Slider.Parent then Slider:Destroy() end
			end

			if Flag then RegisterOption(Flag, SliderV) end
			SliderV._Object = Slider
			SliderV = EnhanceComponent(SliderV)
			setValue(SliderSettings.CurrentValue, false, false)
			if SliderSettings.FireOnInit and IsComponentUsable(SliderV) then
				emitCallback(SliderV.CurrentValue, true)
			end
			task.defer(function()
				if Slider.Parent then
					setProgress(tonumber(SliderSettings.CurrentValue) or 0)
				end
			end)
			return SliderV
		end
		-- Toggle
		function Tab:CreateToggle(ToggleSettings, Flag)
			local ToggleV = { IgnoreConfig = false, Class = "Toggle" }

			ToggleSettings = Kwargify({
				Name = "Toggle",
				Description = nil,
				CurrentValue = false,
				FireOnInit = false,
				FireOnSet = true,
				Group = nil,
				AllowNone = true,
				FireGroupCallbacks = true,
				Callback = function(Value) end,
			}, ToggleSettings or {})

			ToggleV.Settings = ToggleSettings

			local Toggle
			if ToggleSettings.Description ~= nil and ToggleSettings.Description ~= "" then
				Toggle = Elements.Template.ToggleDesc:Clone()
			else
				Toggle = Elements.Template.Toggle:Clone()
			end

			Toggle.Visible = true
			Toggle.Parent = TabPage
			Toggle.Name = tostring(ToggleSettings.Name) .. " - Toggle"
			Toggle.Title.Text = tostring(ToggleSettings.Name)
			if ToggleSettings.Description ~= nil and ToggleSettings.Description ~= "" then
				Toggle.Desc.Text = tostring(ToggleSettings.Description)
			end

			Toggle.UIStroke.Transparency = 1
			Toggle.Title.TextTransparency = 1
			if ToggleSettings.Description ~= nil and ToggleSettings.Description ~= "" then
				Toggle.Desc.TextTransparency = 1
			end

			TweenService:Create(Toggle, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0.5}):Play()
			if ToggleSettings.Description ~= nil and ToggleSettings.Description ~= "" then
				TweenService:Create(Toggle.Desc, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {TextTransparency = 0}):Play()
			end
			TweenService:Create(Toggle.UIStroke, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {Transparency = 0.5}):Play()
			TweenService:Create(Toggle.Title, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {TextTransparency = 0}):Play()

			local function Render(state)
				state = state == true
				if state then
					Toggle.toggle.color.Enabled = true
					tween(Toggle.toggle, {BackgroundTransparency = 0})
					Toggle.toggle.UIStroke.color.Enabled = true
					tween(Toggle.toggle.UIStroke, {Color = Color3.fromRGB(255,255,255)})
					tween(Toggle.toggle.val, {
						BackgroundColor3 = Color3.fromRGB(255,255,255),
						Position = UDim2.new(1,-23,0.5,0),
						BackgroundTransparency = 0.45,
					})
				else
					Toggle.toggle.color.Enabled = false
					Toggle.toggle.UIStroke.color.Enabled = false
					Toggle.toggle.UIStroke.Color = Color3.fromRGB(97,97,97)
					tween(Toggle.toggle, {BackgroundTransparency = 1})
					tween(Toggle.toggle.val, {
						BackgroundColor3 = Color3.fromRGB(97,97,97),
						Position = UDim2.new(0,5,0.5,0),
						BackgroundTransparency = 0,
					})
				end
			end

			local function ShowCallbackError(response)
				if not Toggle.Parent then return end
				Luna._Stats.CallbackErrors += 1
				warn("Luna UI callback error: " .. tostring(response))
				TweenService:Create(Toggle, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0}):Play()
				TweenService:Create(Toggle, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {BackgroundColor3 = Color3.fromRGB(85, 0, 0)}):Play()
				TweenService:Create(Toggle.UIStroke, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {Transparency = 1}):Play()
				Toggle.Title.Text = "Callback Error"
				task.delay(0.5, function()
					if not Toggle.Parent then return end
					Toggle.Title.Text = tostring(ToggleSettings.Name)
					TweenService:Create(Toggle, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0.5}):Play()
					TweenService:Create(Toggle, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {BackgroundColor3 = Color3.fromRGB(32, 30, 38)}):Play()
					TweenService:Create(Toggle.UIStroke, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {Transparency = 0.5}):Play()
				end)
			end

			local function EmitCallback(state)
				if not IsComponentUsable(ToggleV) then return false end
				local success, response = pcall(ToggleSettings.Callback, state)
				if not success then
					ShowCallbackError(response)
				end
				return success, response
			end

			local function SetRawState(state)
				state = state == true
				ToggleSettings.CurrentValue = state
				ToggleV.CurrentValue = state
				Render(state)
				return state
			end

			local function ApplyState(state, fireCallback, enforceGroup, fireGroupCallbacks, force)
				state = state == true
				force = force == true
				local group = ToggleV._ToggleGroup

				if group and Luna._MutatingToggleGroups[group] and not force then
					return ToggleV, false, "Toggle group is busy."
				end

				if not state
					and group
					and enforceGroup ~= false
					and not force
					and not ToggleGroupAllowsNone(group)
					and not ToggleGroupHasOtherActive(ToggleV)
				then
					return ToggleV, false, "At least one toggle in this group must remain active."
				end

				if state and group and enforceGroup ~= false then
					if not BeginToggleGroupMutation(group) then
						return ToggleV, false, "Toggle group is busy."
					end

					local deactivated = DeactivateToggleGroup(ToggleV)
					SetRawState(true)

					if fireGroupCallbacks == true then
						for _, member in ipairs(deactivated) do
							if type(member._EmitExclusiveCallback) == "function" then
								member:_EmitExclusiveCallback(false)
							end
						end
					end
					if fireCallback == true then
						EmitCallback(true)
					end
					EndToggleGroupMutation(group)
				else
					SetRawState(state)
					if fireCallback == true then
						EmitCallback(state)
					end
				end
				return ToggleV, true
			end

			function ToggleV:_ApplyExclusiveState(state, fireCallback)
				SetRawState(state)
				if fireCallback == true then
					EmitCallback(state == true)
				end
				return self
			end

			function ToggleV:_EmitExclusiveCallback(state)
				return EmitCallback(state == true)
			end

			function ToggleV:GetGroup()
				return self._ToggleGroup
			end

			function ToggleV:SetGroup(group, fireGroupCallbacks)
				ToggleSettings.Group = group
				RegisterToggleGroup(self, group)
				if self.CurrentValue == true and self._ToggleGroup then
					ApplyState(true, false, true, fireGroupCallbacks == true, true)
				end
				NormalizeAllToggleGroups(false)
				return self
			end

			ConnectComponent(ToggleV, Toggle.Interact.MouseButton1Click, function()
				if not IsComponentUsable(ToggleV) then return end
				ApplyState(
					not ToggleSettings.CurrentValue,
					true,
					true,
					ToggleSettings.FireGroupCallbacks ~= false,
					false
				)
			end)

			ConnectComponent(ToggleV, Toggle.MouseEnter, function()
				if not ToggleV.Disabled then
					tween(Toggle.UIStroke, {Color = Color3.fromRGB(87, 84, 104)})
				end
			end)

			ConnectComponent(ToggleV, Toggle.MouseLeave, function()
				tween(Toggle.UIStroke, {Color = Color3.fromRGB(64,61,76)})
			end)

			function ToggleV:UpdateState(state, force)
				return ApplyState(state, false, true, false, force == true)
			end

			function ToggleV:Set(NewToggleSettings)
				NewToggleSettings = Kwargify({
					Name = ToggleSettings.Name,
					Description = ToggleSettings.Description,
					CurrentValue = ToggleSettings.CurrentValue,
					FireOnInit = ToggleSettings.FireOnInit,
					FireOnSet = ToggleSettings.FireOnSet,
					Group = ToggleSettings.Group,
					AllowNone = ToggleSettings.AllowNone,
					FireGroupCallbacks = ToggleSettings.FireGroupCallbacks,
					Callback = ToggleSettings.Callback,
				}, NewToggleSettings or {})

				ToggleSettings = NewToggleSettings
				ToggleV.Settings = NewToggleSettings
				RegisterToggleGroup(ToggleV, ToggleSettings.Group)

				Toggle.Name = tostring(ToggleSettings.Name) .. " - Toggle"
				Toggle.Title.Text = tostring(ToggleSettings.Name)
				if Toggle.Desc ~= nil then
					Toggle.Desc.Text = tostring(ToggleSettings.Description or "")
				end

				local shouldFire = NewToggleSettings.Silent ~= true
					and ToggleSettings.FireOnSet ~= false
				return ApplyState(
					ToggleSettings.CurrentValue,
					shouldFire,
					true,
					shouldFire and ToggleSettings.FireGroupCallbacks ~= false,
					NewToggleSettings.Force == true
				)
			end

			function ToggleV:Destroy()
				RemoveToggleFromGroup(ToggleV)
				RemoveOption(ToggleV)
				if Toggle.Parent then Toggle:Destroy() end
			end

			ConnectComponent(ToggleV, LunaUI.ThemeRemote:GetPropertyChangedSignal("Value"), function()
				if Toggle.Parent then
					Toggle.toggle.color.Color = Luna.ThemeGradient
					Toggle.toggle.UIStroke.color.Color = Luna.ThemeGradient
				end
			end)

			if Flag then RegisterOption(Flag, ToggleV) end
			ToggleV._Object = Toggle
			ToggleV = EnhanceComponent(ToggleV)
			RegisterToggleGroup(ToggleV, ToggleSettings.Group)

			ApplyState(
				ToggleSettings.CurrentValue,
				ToggleSettings.CurrentValue == true and ToggleSettings.FireOnInit == true,
				true,
				false,
				true
			)
			task.defer(function()
				if not ToggleV._Destroyed then
					NormalizeAllToggleGroups(false)
				end
			end)
			return ToggleV
		end
		-- Bind
		function Tab:CreateBind(BindSettings, Flag)
			local BindV = {Class = "Bind", IgnoreConfig = false, Settings = BindSettings, Active = false}

			BindSettings = Kwargify({
				Name = "Bind",
				Description = nil,
				CurrentBind = "Q",
				HoldToInteract = false,
				FireOnInit = false,
				Callback = function(active) end,
				OnChangedCallback = function(bind) end,
			}, BindSettings or {})

			local checkingForKey = false
			local Bind
			if BindSettings.Description ~= nil and BindSettings.Description ~= "" then
				Bind = Elements.Template.BindDesc:Clone()
			else
				Bind = Elements.Template.Bind:Clone()
			end

			Bind.Visible = true
			Bind.Parent = TabPage
			Bind.Name = tostring(BindSettings.Name)
			Bind.Title.Text = tostring(BindSettings.Name)
			if Bind.Desc and BindSettings.Description then Bind.Desc.Text = tostring(BindSettings.Description) end
			Bind.BindFrame.BindBox.Text = tostring(BindSettings.CurrentBind)
			BindV.CurrentBind = tostring(BindSettings.CurrentBind)

			local function resizeBindBox()
				Bind.BindFrame.BindBox.Size = UDim2.new(0, Bind.BindFrame.BindBox.TextBounds.X + 20, 0, 42)
			end
			resizeBindBox()

			local function currentBinding()
				return NormalizeInputBinding(BindSettings.CurrentBind)
			end

			local function setBind(newBind, fireChanged)
				local binding = NormalizeInputBinding(
					newBind,
					BindSettings.CurrentBind or "Q"
				)
				if not binding then return false end
				local bindName = binding.Name
				local changed = tostring(BindSettings.CurrentBind) ~= bindName
				BindSettings.CurrentBind = bindName
				BindV.CurrentBind = bindName
				Bind.BindFrame.BindBox.Text = bindName
				resizeBindBox()
				if changed and fireChanged and IsComponentUsable(BindV) then
					SafeCall(BindSettings.OnChangedCallback, bindName)
				end
				return true
			end

			setBind(BindSettings.CurrentBind, false)

			ConnectComponent(BindV, Bind.BindFrame.BindBox.Focused, function()
				if BindV.Disabled then return end
				checkingForKey = true
				Bind.BindFrame.BindBox.Text = "..."
			end)
			ConnectComponent(BindV, Bind.BindFrame.BindBox.FocusLost, function()
				checkingForKey = false
				Bind.BindFrame.BindBox.Text = tostring(BindSettings.CurrentBind)
				resizeBindBox()
			end)
			ConnectComponent(BindV, Bind.MouseEnter, function()
				if not BindV.Disabled then tween(Bind.UIStroke, {Color = Color3.fromRGB(87,84,104)}) end
			end)
			ConnectComponent(BindV, Bind.MouseLeave, function()
				tween(Bind.UIStroke, {Color = Color3.fromRGB(64,61,76)})
			end)

			ConnectComponent(BindV, UserInputService.InputBegan, function(input, processed)
				if Luna._Destroyed or BindV._Destroyed then return end
				if checkingForKey then
					local newBinding = InputToBinding(input)
					if newBinding then
						setBind(newBinding.Name, true)
						Bind.BindFrame.BindBox:ReleaseFocus()
					end
					return
				end
				if processed or BindV.Disabled then return end
				local binding = currentBinding()
				if not binding or not InputMatchesBinding(input, binding) then return end

				if BindSettings.HoldToInteract then
					if not BindV.Active then
						BindV.Active = true
						SafeCall(BindSettings.Callback, true)
					end
				else
					BindV.Active = not BindV.Active
					SafeCall(BindSettings.Callback, BindV.Active)
				end
			end)

			ConnectComponent(BindV, UserInputService.InputEnded, function(input)
				if BindV._Destroyed or not BindSettings.HoldToInteract or not BindV.Active then return end
				local binding = currentBinding()
				if binding and InputMatchesBinding(input, binding) then
					BindV.Active = false
					SafeCall(BindSettings.Callback, false)
				end
			end)

			function BindV:Set(NewBindSettings)
				NewBindSettings = Kwargify(BindSettings, NewBindSettings or {})
				local oldBind = tostring(BindSettings.CurrentBind)
				BindSettings = NewBindSettings
				BindV.Settings = NewBindSettings
				Bind.Name = tostring(BindSettings.Name)
				Bind.Title.Text = tostring(BindSettings.Name)
				if Bind.Desc and BindSettings.Description ~= nil then Bind.Desc.Text = tostring(BindSettings.Description) end
				setBind(BindSettings.CurrentBind, NewBindSettings.Silent ~= true and oldBind ~= tostring(BindSettings.CurrentBind))
				return BindV
			end

			function BindV:Destroy()
				if BindV.Active and BindSettings.HoldToInteract then SafeCall(BindSettings.Callback, false) end
				BindV.Active = false
				RemoveOption(BindV)
				if Bind.Parent then Bind:Destroy() end
			end

			if Flag then RegisterOption(Flag, BindV) end
			BindV._Object = Bind
			BindV = EnhanceComponent(BindV)
			local baseSetDisabled = BindV.SetDisabled
			function BindV:SetDisabled(disabled)
				if disabled == true and BindV.Active and BindSettings.HoldToInteract then
					BindV.Active = false
					SafeCall(BindSettings.Callback, false)
				end
				return baseSetDisabled(self, disabled)
			end
			if BindSettings.FireOnInit then SafeCall(BindSettings.Callback, BindV.Active) end
			return BindV
		end

		function Tab:CreateKeybind(BindSettings, Flag)
			return Tab:CreateBind(BindSettings, Flag)
		end

		function Tab:CreateInput(InputSettings, Flag)
			local InputV = { IgnoreConfig = false, Class = "Input", Settings = InputSettings }

			InputSettings = Kwargify({
				Name = "Dynamic Input",
				Description = nil,
				CurrentValue = "",
				PlaceholderText = "Input Placeholder",
				RemoveTextAfterFocusLost = false,
				Numeric = false,
				AllowNegative = true,
				AllowDecimal = true,
				Enter = false,
				MaxCharacters = nil,
				FireOnInit = false,
				FireOnSet = true,
				Callback = function(Text) end,
			}, InputSettings or {})

			InputV.Settings = InputSettings
			local descriptionEnabled = InputSettings.Description ~= nil
				and InputSettings.Description ~= ""
			local Input = descriptionEnabled
				and Elements.Template.InputDesc:Clone()
				or Elements.Template.Input:Clone()
			local TextBox = Input.InputFrame.InputBox

			Input.Name = tostring(InputSettings.Name)
			Input.Title.Text = tostring(InputSettings.Name)
			if descriptionEnabled and Input:FindFirstChild("Desc") then
				Input.Desc.Text = tostring(InputSettings.Description)
			end
			Input.Visible = true
			Input.Parent = TabPage

			Input.BackgroundTransparency = 1
			Input.UIStroke.Transparency = 1
			Input.Title.TextTransparency = 1
			if descriptionEnabled and Input:FindFirstChild("Desc") then
				Input.Desc.TextTransparency = 1
			end
			Input.InputFrame.BackgroundTransparency = 1
			Input.InputFrame.UIStroke.Transparency = 1
			TextBox.TextTransparency = 1

			TweenService:Create(Input, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0.5}):Play()
			TweenService:Create(Input.UIStroke, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {Transparency = 0.5}):Play()
			TweenService:Create(Input.Title, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {TextTransparency = 0}):Play()
			if descriptionEnabled and Input:FindFirstChild("Desc") then
				TweenService:Create(Input.Desc, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {TextTransparency = 0}):Play()
			end
			TweenService:Create(Input.InputFrame, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0.9}):Play()
			TweenService:Create(Input.InputFrame.UIStroke, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {Transparency = 0.3}):Play()
			TweenService:Create(TextBox, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {TextTransparency = 0}):Play()

			local updatingText = false

			local function sanitizeNumeric(text)
				text = tostring(text or "")
				local negative = InputSettings.AllowNegative ~= false
					and text:sub(1, 1) == "-"
				local body = text:gsub("[^%d%.]", "")
				if InputSettings.AllowDecimal == false then
					body = body:gsub("%.", "")
				else
					local firstDot = body:find(".", 1, true)
					if firstDot then
						body = body:sub(1, firstDot)
							.. body:sub(firstDot + 1):gsub("%.", "")
					end
				end
				return (negative and "-" or "") .. body
			end

			local function sanitizeText(value)
				local text = tostring(value or "")
				if InputSettings.Numeric then
					text = sanitizeNumeric(text)
				end
				local maximum = tonumber(InputSettings.MaxCharacters)
				if maximum then
					maximum = math.max(0, math.floor(maximum))
					if #text > maximum then
						text = text:sub(1, maximum)
					end
				end
				return text
			end

			local function resizeInput()
				local width = math.clamp(TextBox.TextBounds.X + 52, 90, 320)
				Input.InputFrame.Size = UDim2.fromOffset(width, 30)
			end

			local function emitCallback(text)
				if IsComponentUsable(InputV) then
					return SafeCall(InputSettings.Callback, text)
				end
				return false
			end

			local function applyText(value, fireCallback, forceCallback)
				local text = sanitizeText(value)
				local changed = tostring(InputV.CurrentValue or "") ~= text
				InputSettings.CurrentValue = text
				InputV.CurrentValue = text
				if TextBox.Text ~= text then
					updatingText = true
					TextBox.Text = text
					updatingText = false
				end
				resizeInput()
				if fireCallback == true and (changed or forceCallback == true) then
					emitCallback(text)
				end
				return text
			end

			TextBox.PlaceholderText = tostring(InputSettings.PlaceholderText or "")
			ConnectComponent(InputV, TextBox:GetPropertyChangedSignal("Text"), function()
				if updatingText or not IsComponentUsable(InputV) then return end
				applyText(TextBox.Text, not InputSettings.Enter, false)
			end)

			ConnectComponent(InputV, TextBox.FocusLost, function(enterPressed)
				local shouldFire = InputSettings.Enter and enterPressed == true
				applyText(TextBox.Text, shouldFire, shouldFire)
				if InputSettings.RemoveTextAfterFocusLost then
					applyText("", false, false)
				end
			end)

			ConnectComponent(InputV, Input.MouseEnter, function()
				if not InputV.Disabled then
					tween(Input.UIStroke, {Color = Color3.fromRGB(87, 84, 104)})
				end
			end)
			ConnectComponent(InputV, Input.MouseLeave, function()
				tween(Input.UIStroke, {Color = Color3.fromRGB(64,61,76)})
			end)

			function InputV:UpdateValue(value, silent)
				applyText(value, silent ~= true, false)
				return self
			end

			function InputV:Set(NewInputSettings)
				NewInputSettings = Kwargify(InputSettings, NewInputSettings or {})
				InputSettings = NewInputSettings
				InputV.Settings = NewInputSettings
				Input.Name = tostring(InputSettings.Name)
				Input.Title.Text = tostring(InputSettings.Name)
				TextBox.PlaceholderText = tostring(InputSettings.PlaceholderText or "")
				if Input:FindFirstChild("Desc") then
					Input.Desc.Text = tostring(InputSettings.Description or "")
				end
				local shouldFire = NewInputSettings.Silent ~= true
					and InputSettings.FireOnSet ~= false
				applyText(
					InputSettings.CurrentValue,
					shouldFire,
					NewInputSettings.ForceCallback == true
				)
				return self
			end

			function InputV:Destroy()
				RemoveOption(InputV)
				if Input.Parent then Input:Destroy() end
			end

			if Flag then RegisterOption(Flag, InputV) end
			InputV._Object = Input
			InputV = EnhanceComponent(InputV)
			applyText(InputSettings.CurrentValue, false, false)
			if InputSettings.FireOnInit then
				emitCallback(InputV.CurrentValue)
			end
			return InputV
		end
		-- Dropdown
		function Tab:CreateDropdown(DropdownSettings, Flag)
			local DropdownV = { IgnoreConfig = false, Class = "Dropdown", Settings = DropdownSettings}
			local PlayerConnections = {}
			local OptionConnections = {}

			DropdownSettings = Kwargify({
				Name = "Dropdown",
				Description = nil,
				Options = {"Option 1", "Option 2"},
				CurrentOption = {"Option 1"},
				MultipleOptions = false,
				SpecialType = nil, -- supports "Player"
				AllowLocalPlayer = false,
				ReturnPlayerInstance = false,
				SortPlayers = true,
				AutoSelectFirst = true,
				FireOnInit = false,
				Callback = function(Options)
					-- The function that takes place when the selected option is changed
					-- The variable (Options) is a table of strings for the current selected options or a string if multioptions is false
				end,
			}, DropdownSettings or {})

			DropdownV.CurrentOption = DropdownSettings.CurrentOption

			local descriptionbool = false
			if DropdownSettings.Description ~= nil and DropdownSettings.Description ~= "" then
				descriptionbool = true
			end
			local closedsize
			local openedsize
			if descriptionbool then
				closedsize = 48
				openedsize = 170
			elseif not descriptionbool then
				closedsize = 38
				openedsize = 160
			end
			local opened = false

			local Dropdown
			if descriptionbool then Dropdown = Elements.Template.DropdownDesc:Clone() else Dropdown = Elements.Template.Dropdown:Clone() end

			Dropdown.Name = DropdownSettings.Name
			Dropdown.Title.Text = DropdownSettings.Name
			if descriptionbool then Dropdown.Desc.Text = DropdownSettings.Description end

			Dropdown.Parent = TabPage
			Dropdown.Visible = true

			local function Toggle()
				opened = not opened
				if opened then
					local optionCount = math.clamp(#DropdownSettings.Options, 1, 6)
					local dynamicOpenedSize = math.max(openedsize, closedsize + 35 + optionCount * 24)
					tween(Dropdown.icon, {Rotation = 180})
					tween(Dropdown, {Size = UDim2.new(1, -25, 0, dynamicOpenedSize)})
				else
					tween(Dropdown.icon, {Rotation = 0})
					tween(Dropdown, {Size = UDim2.new(1, -25, 0, closedsize)})
				end
			end

			local function SafeCallback(param, c2, silent)
				if silent == true then
					if c2 then c2() end
					return true
				end
				local callbackParam = param
				if DropdownSettings.SpecialType == "Player" and DropdownSettings.ReturnPlayerInstance then
					if type(param) == "string" then
						callbackParam = Players:FindFirstChild(param)
					elseif type(param) == "table" then
						callbackParam = {}
						for _, name in ipairs(param) do
							local target = Players:FindFirstChild(tostring(name))
							if target then table.insert(callbackParam, target) end
						end
					end
				end
				local Success, Response = pcall(function()
					DropdownSettings.Callback(callbackParam)
				end)
				if not Success then
					TweenService:Create(Dropdown, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0}):Play()
					TweenService:Create(Dropdown, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {BackgroundColor3 = Color3.fromRGB(85, 0, 0)}):Play()
					TweenService:Create(Dropdown.UIStroke, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {Transparency = 1}):Play()
					Dropdown.Title.Text = "Callback Error"
					print("Luna Interface Suite | "..DropdownSettings.Name.." Callback Error " ..tostring(Response))
					task.wait(0.5)
					Dropdown.Title.Text = DropdownSettings.Name
					TweenService:Create(Dropdown, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0.5}):Play()
					TweenService:Create(Dropdown, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {BackgroundColor3 = Color3.fromRGB(32, 30, 38)}):Play()
					TweenService:Create(Dropdown.UIStroke, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {Transparency = 0.5}):Play()
				end
				if Success and c2 then
					c2()
				end
			end

			-- fixed by justhey
			ConnectComponent(DropdownV, Dropdown.Selected:GetPropertyChangedSignal("Text"), function()
				local text = Dropdown.Selected.Text:lower()
				for _, Item in ipairs(Dropdown.List:GetChildren()) do
					if Item:IsA("TextLabel") and Item.Name ~= "Template" then
						Item.Visible = text == "" or string.find(Item.Name:lower(), text, 1, true) ~= nil
					end
				end
			end)


			local function Clear()
				DisconnectConnections(OptionConnections)
				for _, option in ipairs(Dropdown.List:GetChildren()) do
					if option.ClassName == "TextLabel" and option.Name ~= "Template" then
						option:Destroy()
					end
				end
			end

			local function ActivateColorSingle(name)
				for _, Option in pairs(Dropdown.List:GetChildren()) do
					if Option.ClassName == "TextLabel" and Option.Name ~= "Template" then
						tween(Option, {BackgroundTransparency = 0.98})
					end
				end

				Toggle()
				local targetOption = name and Dropdown.List:FindFirstChild(tostring(name)); if targetOption then tween(targetOption, {BackgroundTransparency = 0.95, TextColor3 = Color3.fromRGB(240,240,240)}) end
			end

			local function Refresh()
				Clear()
				for i,v in pairs(DropdownSettings.Options) do
					local Option = Dropdown.List.Template:Clone()
					local optionhover = false
					Option.Text = v
					if v == "Template" then v = "Template (Name)" end
					Option.Name = v
					TrackConnection(Option.Interact.MouseButton1Click:Connect(function()
						local bleh
						if DropdownSettings.MultipleOptions then
							if table.find(DropdownSettings.CurrentOption, v) then
								RemoveTable(DropdownSettings.CurrentOption, v)
								DropdownV.CurrentOption = DropdownSettings.CurrentOption
								if not optionhover then
									tween(Option, {TextColor3 = Color3.fromRGB(200,200,200)})
								end
								tween(Option, {BackgroundTransparency = 0.98})
							else
								table.insert(DropdownSettings.CurrentOption, v)
								DropdownV.CurrentOption = DropdownSettings.CurrentOption
								tween(Option, {TextColor3 = Color3.fromRGB(240,240,240), BackgroundTransparency = 0.95})
							end
							bleh = DropdownSettings.CurrentOption
						else
							DropdownSettings.CurrentOption = {v}
							bleh = v
							DropdownV.CurrentOption = bleh
							ActivateColorSingle(v)
						end

						SafeCallback(bleh, function()
							if DropdownSettings.MultipleOptions then
								if DropdownSettings.CurrentOption and type(DropdownSettings.CurrentOption) == "table" then
									if #DropdownSettings.CurrentOption == 1 then
										Dropdown.Selected.PlaceholderText = DropdownSettings.CurrentOption[1]
									elseif #DropdownSettings.CurrentOption == 0 then
										Dropdown.Selected.PlaceholderText = "None"
									else
										Dropdown.Selected.PlaceholderText = unpackt(DropdownSettings.CurrentOption)
									end
								else
									DropdownSettings.CurrentOption = {}
									Dropdown.Selected.PlaceholderText = "None"
								end
							end
							if not DropdownSettings.MultipleOptions then
								Dropdown.Selected.PlaceholderText = DropdownSettings.CurrentOption[1] or "None"
							end
							Dropdown.Selected.Text = ""
						end)
					end), OptionConnections)
					Option.Visible = true
					Option.Parent = Dropdown.List
					TrackConnection(Option.MouseEnter:Connect(function()
						optionhover = true
						if Option.BackgroundTransparency == 0.95 then
							return
						else
							tween(Option, {TextColor3 = Color3.fromRGB(240,240,240)})
						end
					end), OptionConnections)
					TrackConnection(Option.MouseLeave:Connect(function()
						optionhover = false
						if Option.BackgroundTransparency == 0.95 then
							return
						else
							tween(Option, {TextColor3 = Color3.fromRGB(200,200,200)})
						end
					end), OptionConnections)	
				end
			end

			local function PlayerTableRefresh()
				table.clear(DropdownSettings.Options)
				for _, player in ipairs(Players:GetPlayers()) do
					if DropdownSettings.AllowLocalPlayer or player ~= Player then
						table.insert(DropdownSettings.Options, player.Name)
					end
				end
				if DropdownSettings.SortPlayers then table.sort(DropdownSettings.Options) end

				local current = DropdownSettings.CurrentOption
				if type(current) == "string" then current = {current} end
				if type(current) ~= "table" then current = {} end
				local valid = {}
				for _, name in ipairs(current) do
					if table.find(DropdownSettings.Options, name) then table.insert(valid, name) end
				end
				if not DropdownSettings.MultipleOptions and #valid == 0 and DropdownSettings.AutoSelectFirst and DropdownSettings.Options[1] then
					valid = {DropdownSettings.Options[1]}
				end
				DropdownSettings.CurrentOption = valid
				DropdownV.CurrentOption = DropdownSettings.MultipleOptions and valid or valid[1]
			end

			ConnectComponent(DropdownV, Dropdown.Interact.MouseButton1Click, function()
				Toggle()
			end)

			ConnectComponent(DropdownV, Dropdown.MouseEnter, function()
				tween(Dropdown.UIStroke, {Color = Color3.fromRGB(87, 84, 104)})
			end)

			ConnectComponent(DropdownV, Dropdown.MouseLeave, function()
				tween(Dropdown.UIStroke, {Color = Color3.fromRGB(64,61,76)})
			end)

			if DropdownSettings.SpecialType == "Player" then
				DropdownV.IgnoreConfig = true
				PlayerTableRefresh()

				local function refreshPlayers()
					if not Dropdown.Parent then return end
					PlayerTableRefresh()
					Refresh()
					Dropdown.Selected.PlaceholderText = DropdownSettings.CurrentOption[1] or "None"
				end
				TrackConnection(Players.PlayerAdded:Connect(function() task.defer(refreshPlayers) end), PlayerConnections)
				TrackConnection(Players.PlayerRemoving:Connect(function() task.defer(refreshPlayers) end), PlayerConnections)
				TrackConnection(Dropdown.AncestryChanged:Connect(function(_, parent)
					if parent == nil then DisconnectConnections(PlayerConnections) end
				end), PlayerConnections)
			end

			Refresh()

			if DropdownSettings.CurrentOption then
				if type(DropdownSettings.CurrentOption) == "string" then
					DropdownSettings.CurrentOption = {DropdownSettings.CurrentOption}
				end
				if not DropdownSettings.MultipleOptions and type(DropdownSettings.CurrentOption) == "table" then
					DropdownSettings.CurrentOption = {DropdownSettings.CurrentOption[1]}
				end
			else
				DropdownSettings.CurrentOption = {}
			end

			local bleh, ind = nil,0
			for i,v in pairs(DropdownSettings.CurrentOption) do
				ind = ind + 1
			end
			if ind == 1 then bleh = DropdownSettings.CurrentOption[1] else bleh = DropdownSettings.CurrentOption end
			if DropdownSettings.FireOnInit then SafeCallback(bleh) end
			if type(bleh) == "string" then 
				local targetOption = bleh and Dropdown.List:FindFirstChild(tostring(bleh)); if targetOption then tween(targetOption, {TextColor3 = Color3.fromRGB(240,240,240), BackgroundTransparency = 0.95}) end
			else
				for i,v in pairs(bleh) do
					local targetOption = v and Dropdown.List:FindFirstChild(tostring(v)); if targetOption then tween(targetOption, {TextColor3 = Color3.fromRGB(240,240,240), BackgroundTransparency = 0.95}) end
				end
			end

			if DropdownSettings.MultipleOptions then
				if DropdownSettings.CurrentOption and type(DropdownSettings.CurrentOption) == "table" then
					if #DropdownSettings.CurrentOption == 1 then
						Dropdown.Selected.PlaceholderText = DropdownSettings.CurrentOption[1]
					elseif #DropdownSettings.CurrentOption == 0 then
						Dropdown.Selected.PlaceholderText = "None"
					else
						Dropdown.Selected.PlaceholderText = unpackt(DropdownSettings.CurrentOption)
					end
				else
					DropdownSettings.CurrentOption = {}
					Dropdown.Selected.PlaceholderText = "None"
				end
				for _, name in pairs(DropdownSettings.CurrentOption) do
					local targetOption = name and Dropdown.List:FindFirstChild(tostring(name)); if targetOption then tween(targetOption, {TextColor3 = Color3.fromRGB(227,227,227), BackgroundTransparency = 0.95}) end
				end
			else
				Dropdown.Selected.PlaceholderText = DropdownSettings.CurrentOption[1] or "None"
			end
			Dropdown.Selected.Text = ""

			function DropdownV:Set(NewDropdownSettings)
				NewDropdownSettings = Kwargify(DropdownSettings, NewDropdownSettings or {})

				DropdownV.Settings = NewDropdownSettings
				DropdownSettings = NewDropdownSettings

				Dropdown.Name = DropdownSettings.Name
				Dropdown.Title.Text = DropdownSettings.Name
				if DropdownSettings.Description ~= nil and DropdownSettings.Description ~= "" and Dropdown.Desc ~= nil then
					Dropdown.Desc.Text = DropdownSettings.Description
				end

				if DropdownSettings.SpecialType == "Player" then
					DropdownV.IgnoreConfig = true
					PlayerTableRefresh()
				end

				Refresh()

				if DropdownSettings.CurrentOption then
					if type(DropdownSettings.CurrentOption) == "string" then
						DropdownSettings.CurrentOption = {DropdownSettings.CurrentOption}
					end
					if not DropdownSettings.MultipleOptions and type(DropdownSettings.CurrentOption) == "table" then
						DropdownSettings.CurrentOption = {DropdownSettings.CurrentOption[1]}
					end
				else
					DropdownSettings.CurrentOption = {}
				end

				local bleh, ind = nil,0
				for i,v in pairs(DropdownSettings.CurrentOption) do
					ind = ind + 1
				end
				if ind == 1 then bleh = DropdownSettings.CurrentOption[1] else bleh = DropdownSettings.CurrentOption end
				DropdownV.CurrentOption = DropdownSettings.CurrentOption
				SafeCallback(bleh, nil, NewDropdownSettings.Silent == true)
				for _, Option in pairs(Dropdown.List:GetChildren()) do
					if Option.ClassName == "TextLabel" then
						tween(Option, {TextColor3 = Color3.fromRGB(200,200,200), BackgroundTransparency = 0.98})
					end
				end
				local targetOption = bleh and Dropdown.List:FindFirstChild(tostring(bleh)); if targetOption then tween(targetOption, {TextColor3 = Color3.fromRGB(240,240,240), BackgroundTransparency = 0.95}) end

				if DropdownSettings.MultipleOptions then
					if DropdownSettings.CurrentOption and type(DropdownSettings.CurrentOption) == "table" then
						if #DropdownSettings.CurrentOption == 1 then
							Dropdown.Selected.PlaceholderText = DropdownSettings.CurrentOption[1]
						elseif #DropdownSettings.CurrentOption == 0 then
							Dropdown.Selected.PlaceholderText = "None"
						else
							Dropdown.Selected.PlaceholderText = unpackt(DropdownSettings.CurrentOption)
						end
					else
						DropdownSettings.CurrentOption = {}
						Dropdown.Selected.PlaceholderText = "None"
					end
					for _, name in pairs(DropdownSettings.CurrentOption) do
						local targetOption = name and Dropdown.List:FindFirstChild(tostring(name)); if targetOption then tween(targetOption, {TextColor3 = Color3.fromRGB(227,227,227), BackgroundTransparency = 0.95}) end
					end
				else
					Dropdown.Selected.PlaceholderText = DropdownSettings.CurrentOption[1] or "None"
				end
				Dropdown.Selected.Text = ""

				-- Luna.Flags[DropdownSettings.Flag] = DropdownSettings
				return self
			end

			function DropdownV:Destroy()
				DisconnectConnections(PlayerConnections)
				DisconnectConnections(OptionConnections)
				RemoveOption(DropdownV)
				Dropdown.Visible = false
				Dropdown:Destroy()
			end

			if Flag then
				RegisterOption(Flag, DropdownV)
			end

			-- Luna.Flags[DropdownSettings.Flag] = DropdownSettings

			DropdownV._Object = Dropdown

			return EnhanceComponent(DropdownV)

		end

		-- Color Picker
		function Tab:CreateColorPicker(ColorPickerSettings, Flag)
			local ColorPickerV = {IgnoreClass = false, Class = "Colorpicker", Settings = ColorPickerSettings}

			ColorPickerSettings = Kwargify({
				Name = "Color Picker",
				Color = Color3.fromRGB(255,255,255),
				Alpha = 0,
				FireOnInit = false,
				FireOnSet = true,
				CallbackInterval = 0.03,
				Callback = function(value) end,
				OnFinished = function(value) end,
			}, ColorPickerSettings or {})

			if typeof(ColorPickerSettings.Color) ~= "Color3" then ColorPickerSettings.Color = Color3.new(1,1,1) end
			local ColorPicker = Elements.Template.ColorPicker:Clone()
			local Background = ColorPicker.CPBackground
			local Display = Background.Display
			local Main = Background.MainCP
			local HueSlider = ColorPicker.ColorSlider
			local closedSize = UDim2.new(0, 75, 0, 22)
			local openedSize = UDim2.new(0, 219, 0, 129)
			local opened = false
			local dragMode
			local activeInput
			local h, s, v = ColorPickerSettings.Color:ToHSV()
			local lastCallback = -math.huge

			ColorPicker.Name = tostring(ColorPickerSettings.Name)
			ColorPicker.Title.Text = tostring(ColorPickerSettings.Name)
			ColorPicker.Visible = true
			ColorPicker.Parent = TabPage
			ColorPicker.Size = UDim2.new(1.042, -25, 0, 38)
			Background.Size = closedSize
			Display.BackgroundTransparency = 0
			Main.Image = "http://www.roblox.com/asset/?id=11415645739"

			local function colorToHex(color)
				return string.format("#%02X%02X%02X", math.floor(color.R*255+0.5), math.floor(color.G*255+0.5), math.floor(color.B*255+0.5))
			end

			local function emit(color, force)
				if not IsComponentUsable(ColorPickerV) then return end
				local interval = math.max(0, tonumber(ColorPickerSettings.CallbackInterval) or 0.03)
				if not force and os.clock() - lastCallback < interval then return end
				lastCallback = os.clock()
				SafeCall(ColorPickerSettings.Callback, color)
			end

			local function finish(color)
				if IsComponentUsable(ColorPickerV) then SafeCall(ColorPickerSettings.OnFinished, color) end
			end

			local function updateDisplay()
				local color = Color3.fromHSV(h,s,v)
				Main.MainPoint.Position = UDim2.new(s, -Main.MainPoint.AbsoluteSize.X/2, 1-v, -Main.MainPoint.AbsoluteSize.Y/2)
				Main.MainPoint.ImageColor3 = color
				Background.BackgroundColor3 = Color3.fromHSV(h,1,1)
				Display.BackgroundColor3 = color
				local x = h * HueSlider.AbsoluteSize.X
				HueSlider.SliderPoint.Position = UDim2.new(0, x-HueSlider.SliderPoint.AbsoluteSize.X/2, 0.5, 0)
				HueSlider.SliderPoint.ImageColor3 = Color3.fromHSV(h,1,1)
				local rr,gg,bb = math.floor(color.R*255+0.5), math.floor(color.G*255+0.5), math.floor(color.B*255+0.5)
				ColorPicker.RInput.InputBox.Text = tostring(rr)
				ColorPicker.GInput.InputBox.Text = tostring(gg)
				ColorPicker.BInput.InputBox.Text = tostring(bb)
				ColorPicker.HexInput.InputBox.Text = colorToHex(color)
				ColorPickerSettings.Color = color
				ColorPickerV.Color = color
				ColorPickerV.Alpha = tonumber(ColorPickerSettings.Alpha) or 0
				return color
			end

			local function setColor(color, fireCallback, force)
				if typeof(color) ~= "Color3" then return ColorPickerV.Color end
				h,s,v = color:ToHSV()
				local updated = updateDisplay()
				if fireCallback then emit(updated, force) end
				return updated
			end

			local function inputPosition(input)
				if input and input.UserInputType == Enum.UserInputType.Touch then return input.Position end
				return UserInputService:GetMouseLocation()
			end

			local function updateDrag(input)
				if not dragMode or not IsComponentUsable(ColorPickerV) then return end
				local pos = inputPosition(input)
				if dragMode == "main" then
					if Main.AbsoluteSize.X <= 0 or Main.AbsoluteSize.Y <= 0 then return end
					s = math.clamp((pos.X-Main.AbsolutePosition.X)/Main.AbsoluteSize.X, 0, 1)
					v = 1-math.clamp((pos.Y-Main.AbsolutePosition.Y)/Main.AbsoluteSize.Y, 0, 1)
				else
					if HueSlider.AbsoluteSize.X <= 0 then return end
					h = math.clamp((pos.X-HueSlider.AbsolutePosition.X)/HueSlider.AbsoluteSize.X, 0, 1)
				end
				emit(updateDisplay(), false)
			end

			local function beginDrag(mode, input)
				if not opened or not IsComponentUsable(ColorPickerV) then return end
				if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
				dragMode = mode
				activeInput = input
				updateDrag(input)
			end

			ConnectComponent(ColorPickerV, ColorPicker.MouseEnter, function()
				if not ColorPickerV.Disabled then tween(ColorPicker.UIStroke, {Color = Color3.fromRGB(87,84,104)}) end
			end)
			ConnectComponent(ColorPickerV, ColorPicker.MouseLeave, function()
				tween(ColorPicker.UIStroke, {Color = Color3.fromRGB(64,61,76)})
			end)
			ConnectComponent(ColorPickerV, ColorPicker.Interact.MouseButton1Click, function()
				if not IsComponentUsable(ColorPickerV) then return end
				opened = not opened
				if opened then
					tween(ColorPicker, {Size = UDim2.new(1.042,-25,0,165)}, nil, TweenInfo.new(0.4, Enum.EasingStyle.Exponential))
					tween(Background, {Size = openedSize})
					tween(Display, {BackgroundTransparency = 1})
				else
					tween(ColorPicker, {Size = UDim2.new(1.042,-25,0,38)}, nil, TweenInfo.new(0.4, Enum.EasingStyle.Exponential))
					tween(Background, {Size = closedSize})
					tween(Display, {BackgroundTransparency = 0})
				end
			end)
			ConnectComponent(ColorPickerV, Main.InputBegan, function(input) beginDrag("main", input) end)
			ConnectComponent(ColorPickerV, Main.MainPoint.InputBegan, function(input) beginDrag("main", input) end)
			ConnectComponent(ColorPickerV, HueSlider.InputBegan, function(input) beginDrag("hue", input) end)
			ConnectComponent(ColorPickerV, HueSlider.SliderPoint.InputBegan, function(input) beginDrag("hue", input) end)
			ConnectComponent(ColorPickerV, UserInputService.InputChanged, function(input)
				if not dragMode then return end
				if activeInput and activeInput.UserInputType == Enum.UserInputType.Touch then
					if input ~= activeInput then return end
				elseif input.UserInputType ~= Enum.UserInputType.MouseMovement then
					return
				end
				updateDrag(input)
			end)
			ConnectComponent(ColorPickerV, UserInputService.InputEnded, function(input)
				if dragMode and (input == activeInput or input.UserInputType == Enum.UserInputType.MouseButton1) then
					local color = updateDisplay()
					dragMode = nil
					activeInput = nil
					emit(color, true)
					finish(color)
				end
			end)

			ConnectComponent(ColorPickerV, ColorPicker.HexInput.InputBox.FocusLost, function()
				local rr,gg,bb = ColorPicker.HexInput.InputBox.Text:match("^#?(%x%x)(%x%x)(%x%x)$")
				if not rr then ColorPicker.HexInput.InputBox.Text = colorToHex(ColorPickerV.Color); return end
				local color = Color3.fromRGB(tonumber(rr,16), tonumber(gg,16), tonumber(bb,16))
				setColor(color, true, true)
				finish(color)
			end)

			local function applyRgb(channel, box)
				local color = ColorPickerV.Color or Color3.new(1,1,1)
				local rr,gg,bb = math.floor(color.R*255+0.5), math.floor(color.G*255+0.5), math.floor(color.B*255+0.5)
				local value = tonumber(box.Text)
				if not value then updateDisplay(); return end
				value = math.clamp(math.floor(value+0.5), 0, 255)
				if channel == "R" then rr=value elseif channel == "G" then gg=value else bb=value end
				local updated = Color3.fromRGB(rr,gg,bb)
				setColor(updated, true, true)
				finish(updated)
			end
			ConnectComponent(ColorPickerV, ColorPicker.RInput.InputBox.FocusLost, function() applyRgb("R", ColorPicker.RInput.InputBox) end)
			ConnectComponent(ColorPickerV, ColorPicker.GInput.InputBox.FocusLost, function() applyRgb("G", ColorPicker.GInput.InputBox) end)
			ConnectComponent(ColorPickerV, ColorPicker.BInput.InputBox.FocusLost, function() applyRgb("B", ColorPicker.BInput.InputBox) end)

			function ColorPickerV:Set(NewColorPickerSettings)
				NewColorPickerSettings = Kwargify(ColorPickerSettings, NewColorPickerSettings or {})
				ColorPickerSettings = NewColorPickerSettings
				ColorPickerV.Settings = NewColorPickerSettings
				ColorPicker.Name = tostring(ColorPickerSettings.Name)
				ColorPicker.Title.Text = tostring(ColorPickerSettings.Name)
				ColorPickerSettings.Alpha = math.clamp(tonumber(ColorPickerSettings.Alpha) or 0, 0, 1)
				local shouldFire = NewColorPickerSettings.Silent ~= true and ColorPickerSettings.FireOnSet ~= false
				setColor(ColorPickerSettings.Color, shouldFire, true)
				return ColorPickerV
			end

			function ColorPickerV:Destroy()
				RemoveOption(ColorPickerV)
				if ColorPicker.Parent then ColorPicker:Destroy() end
			end

			if Flag then RegisterOption(Flag, ColorPickerV) end
			ColorPickerV._Object = ColorPicker
			ColorPickerV = EnhanceComponent(ColorPickerV)
			setColor(ColorPickerSettings.Color, ColorPickerSettings.FireOnInit == true, true)
			task.defer(function() if ColorPicker.Parent then updateDisplay() end end)
			return ColorPickerV
		end

		function Tab:BuildConfigSection(ConfigUISettings)
			ConfigUISettings = Kwargify({
				ShowBrowser = true,
				BrowserHeight = 190,
				Searchable = true,
				Sortable = true,
				DefaultExpanded = true,
			}, ConfigUISettings or {})

			local inputPath = ""
			local renamePath = ""
			local selectedConfig
			local deleteCandidate
			local deleteCandidateTime = 0
			local deleteAllCandidateTime = 0
			local configBrowser
			local selectedLabel
			local listStatus
			local autoloadLabel
			local setAutoloadButton
			local deleteAutoloadButton

			local Title = Elements.Template.Title:Clone()
			Title.Text = "Configurations"
			Title.Visible = true
			Title.Parent = TabPage
			Title.TextTransparency = 1
			TweenService:Create(Title, TweenInfo.new(0.4, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {TextTransparency = 0}):Play()

			local function notify(content, icon)
				Luna:Notification({
					Title = "Configurations",
					Icon = icon or "info",
					ImageSource = "Material",
					Content = content,
				})
			end

			local function normalizeSelection(value)
				if type(value) == "table" then value = value[1] end
				value = value == nil and nil or tostring(value)
				if value == "" or value == "No saved configs" then return nil end
				return value
			end

			local function requireSelected()
				if not selectedConfig or selectedConfig == "" then
					notify("Please select a config first.", "warning")
					return nil
				end
				return selectedConfig
			end

			local function updateSelectedVisual(name)
				selectedConfig = normalizeSelection(name)
				if selectedConfig and selectedConfig:lower() == "nil" then
					selectedConfig = nil
				end
				if selectedLabel then
					selectedLabel:Set({
						Title = "Selected Config",
						Text = selectedConfig or "None",
					})
				end
				if configBrowser and type(configBrowser.SetSelected) == "function" then
					configBrowser:SetSelected(selectedConfig)
				end
			end

			local function makeBrowserRows(options)
				local rows = {}
				local seen = {}
				for _, rawName in ipairs(type(options) == "table" and options or {}) do
					local name = normalizeSelection(rawName)
					if name and name:lower() ~= "nil" and not seen[name] then
						seen[name] = true
						table.insert(rows, name)
					end
				end
				table.sort(rows)
				return rows
			end

			local function refreshSelection(selectName, preserveSelection)
				local options = Luna:RefreshConfigList()
				selectName = normalizeSelection(selectName)

				if not selectName and preserveSelection and selectedConfig
					and table.find(options, selectedConfig)
				then
					selectName = selectedConfig
				end
				if selectName and not table.find(options, selectName) then
					selectName = nil
				end

				if configBrowser then
					configBrowser:SetRows(makeBrowserRows(options))
				end

				updateSelectedVisual(selectName)

				if listStatus then
					local listingSupported = type(listfiles) == "function"
					local message
					if #options > 0 then
						message = string.format(
							"%d config(s) found in %s/settings",
							#options,
							tostring(Luna.Folder)
						)
					elseif listingSupported then
						message = "No saved configs found. Create one above, then press Refresh."
					else
						message = "Executor does not support listfiles. Configs created in this session will still appear."
					end
					listStatus:Set({Title = "Config List", Text = message})
				end

				if autoloadLabel then
					local currentAutoload = Luna:GetAutoload()
					autoloadLabel:Set({
						Title = "Autoload Config",
						Text = currentAutoload or "None",
					})
				end
				return options
			end

			Tab:CreateSection("Config Creator")
			Tab:CreateInput({
				Name = "Config Name",
				Description = "Insert a name for your config.",
				PlaceholderText = "Name",
				CurrentValue = "",
				Numeric = false,
				Enter = false,
				Callback = function(input) inputPath = tostring(input or "") end,
			})

			Tab:CreateButton({
				Name = "Create Config",
				Description = "Save all current settings into a validated JSON config.",
				Callback = function()
					local success, result = Luna:SaveConfig(inputPath)
					if not success then
						notify("Unable to save config: " .. tostring(result), "error")
						return
					end
					inputPath = result
					notify(string.format("Created config %q", result), "check_circle")
					refreshSelection(result, false)
				end,
			})

			Tab:CreateSection("Saved Configs")
			listStatus = Tab:CreateParagraph({Title = "Config List", Text = "Loading..."})
			selectedLabel = Tab:CreateParagraph({Title = "Selected Config", Text = "None"})
			autoloadLabel = Tab:CreateParagraph({Title = "Autoload Config", Text = "None"})

			if ConfigUISettings.ShowBrowser ~= false then
				local expandedHeight = math.max(140, tonumber(ConfigUISettings.BrowserHeight) or 190)
				local collapsedHeight = 36
				local expanded = ConfigUISettings.DefaultExpanded ~= false
				local browserCard = CreateCard(
					TabPage,
					"Select Config",
					expanded and expandedHeight or collapsedHeight
				)
				browserCard.ClipsDescendants = true

				local headerButton = Instance.new("TextButton")
				headerButton.Name = "Header"
				headerButton.Active = true
				headerButton.AutoButtonColor = false
				headerButton.BackgroundColor3 = Color3.fromRGB(32, 30, 38)
				headerButton.BackgroundTransparency = 0.55
				headerButton.BorderSizePixel = 0
				headerButton.Font = Enum.Font.GothamSemibold
				headerButton.TextColor3 = ProductivityColors.Text
				headerButton.TextSize = 14
				headerButton.TextXAlignment = Enum.TextXAlignment.Left
				headerButton.Position = UDim2.fromOffset(0, 0)
				headerButton.Size = UDim2.new(1, 0, 0, collapsedHeight)
				headerButton.ZIndex = browserCard.ZIndex + 2
				headerButton.Parent = browserCard
				CreatePadding(headerButton, 14, 10, 0, 0)

				local searchBox
				local topOffset = collapsedHeight + 7
				if ConfigUISettings.Searchable ~= false then
					searchBox = Instance.new("TextBox")
					searchBox.Name = "Search"
					searchBox.BackgroundColor3 = Color3.fromRGB(23, 22, 28)
					searchBox.BackgroundTransparency = 0.15
					searchBox.BorderSizePixel = 0
					searchBox.ClearTextOnFocus = false
					searchBox.Font = Enum.Font.Gotham
					searchBox.PlaceholderText = "Search saved configs..."
					searchBox.PlaceholderColor3 = ProductivityColors.Muted
					searchBox.Text = ""
					searchBox.TextColor3 = ProductivityColors.Text
					searchBox.TextSize = 12
					searchBox.TextXAlignment = Enum.TextXAlignment.Left
					searchBox.Position = UDim2.fromOffset(14, topOffset)
					searchBox.Size = UDim2.new(1, -28, 0, 28)
					searchBox.Visible = expanded
					searchBox.ZIndex = browserCard.ZIndex + 1
					searchBox.Parent = browserCard
					CreateCorner(searchBox, 6)
					CreatePadding(searchBox, 9, 9, 0, 0)
					topOffset = topOffset + 34
				end

				local rowsFrame = Instance.new("ScrollingFrame")
				rowsFrame.Name = "SavedConfigs"
				rowsFrame.BackgroundTransparency = 1
				rowsFrame.BorderSizePixel = 0
				rowsFrame.Position = UDim2.fromOffset(14, topOffset)
				rowsFrame.Size = UDim2.new(1, -28, 1, -(topOffset + 12))
				rowsFrame.ScrollBarThickness = 4
				rowsFrame.ScrollBarImageColor3 = Color3.fromRGB(95, 93, 108)
				rowsFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
				rowsFrame.CanvasSize = UDim2.new()
				rowsFrame.Visible = expanded
				rowsFrame.ZIndex = browserCard.ZIndex + 1
				rowsFrame.Parent = browserCard

				local rowsLayout = Instance.new("UIListLayout")
				rowsLayout.SortOrder = Enum.SortOrder.LayoutOrder
				rowsLayout.Padding = UDim.new(0, 4)
				rowsLayout.Parent = rowsFrame

				local rowConnections = {}
				local filterText = ""
				local selectedName
				local browser = {
					Class = "ConfigBrowser",
					Rows = {},
					Selected = nil,
					Expanded = expanded,
					_Object = browserCard,
				}

				local function updateHeader()
					headerButton.Text = (expanded and "▼  " or "▶  ") .. "Select Config"
				end

				local function applyExpanded(state)
					expanded = state ~= false
					browser.Expanded = expanded
					browserCard.Size = UDim2.new(
						1,
						0,
						0,
						expanded and expandedHeight or collapsedHeight
					)
					if searchBox then searchBox.Visible = expanded end
					rowsFrame.Visible = expanded
					updateHeader()
				end

				local function renderBrowserRows()
					DisconnectConnections(rowConnections)
					for _, child in ipairs(rowsFrame:GetChildren()) do
						if child:IsA("GuiObject") then child:Destroy() end
					end

					local visibleCount = 0
					for _, rawName in ipairs(browser.Rows) do
						local name = normalizeSelection(rawName)
						if name and name:lower() ~= "nil"
							and (filterText == "" or name:lower():find(filterText, 1, true))
						then
							visibleCount = visibleCount + 1
							local isSelected = selectedName == name
							local rowButton = Instance.new("TextButton")
							rowButton.Name = "Config - " .. name
							rowButton.AutoButtonColor = false
							rowButton.BackgroundColor3 = isSelected
								and Color3.fromRGB(55, 64, 76)
								or (visibleCount % 2 == 0 and Color3.fromRGB(35, 33, 41) or Color3.fromRGB(30, 29, 36))
							rowButton.BackgroundTransparency = isSelected and 0.05 or 0.25
							rowButton.BorderSizePixel = 0
							rowButton.Font = Enum.Font.Gotham
							rowButton.Text = (isSelected and "✓  " or "   ") .. name
							rowButton.TextColor3 = isSelected and Color3.fromRGB(240, 245, 255) or ProductivityColors.Text
							rowButton.TextSize = 12
							rowButton.TextXAlignment = Enum.TextXAlignment.Left
							rowButton.Size = UDim2.new(1, -2, 0, 30)
							rowButton.LayoutOrder = visibleCount
							rowButton.Parent = rowsFrame
							CreateCorner(rowButton, 5)
							CreatePadding(rowButton, 10, 6, 0, 0)

							TrackConnection(rowButton.MouseEnter:Connect(function()
								if selectedName ~= name then
									rowButton.BackgroundTransparency = 0.1
								end
							end), rowConnections)
							TrackConnection(rowButton.MouseLeave:Connect(function()
								if selectedName ~= name then
									rowButton.BackgroundTransparency = 0.25
								end
							end), rowConnections)
							TrackConnection(rowButton.MouseButton1Click:Connect(function()
								updateSelectedVisual(name)
								browser:_EmitChanged(name, nil, {
									Source = "ConfigBrowser",
									Selected = true,
									Force = true,
								})
							end), rowConnections)
						end
					end

					if visibleCount == 0 then
						local emptyLabel = CreateText(
							rowsFrame,
							filterText ~= "" and "No matching configs" or "No saved configs",
							12,
							false
						)
						emptyLabel.Name = "Empty"
						emptyLabel.Size = UDim2.new(1, -2, 0, 34)
						emptyLabel.TextColor3 = ProductivityColors.Muted
						emptyLabel.TextXAlignment = Enum.TextXAlignment.Center
					end
				end

				function browser:SetRows(rows)
					self.Rows = makeBrowserRows(rows)
					if selectedName and not table.find(self.Rows, selectedName) then
						selectedName = nil
						self.Selected = nil
					end
					renderBrowserRows()
					return self
				end

				function browser:SetSelected(name)
					name = normalizeSelection(name)
					if name and not table.find(self.Rows, name) then name = nil end
					selectedName = name
					self.Selected = name
					renderBrowserRows()
					return self
				end

				function browser:GetSelected()
					return selectedName
				end

				function browser:SetFilter(value)
					filterText = tostring(value or ""):lower()
					if searchBox and searchBox.Text ~= tostring(value or "") then
						searchBox.Text = tostring(value or "")
					end
					renderBrowserRows()
					return self
				end

				function browser:SetExpanded(state)
					applyExpanded(state)
					return self
				end

				function browser:Expand()
					return self:SetExpanded(true)
				end

				function browser:Collapse()
					return self:SetExpanded(false)
				end

				function browser:Toggle()
					return self:SetExpanded(not expanded)
				end

				function browser:IsExpanded()
					return expanded
				end

				function browser:Destroy()
					DisconnectConnections(rowConnections)
					if browserCard.Parent then browserCard:Destroy() end
				end

				configBrowser = EnhanceComponent(browser)
				ConnectComponent(configBrowser, headerButton.MouseEnter, function()
					headerButton.BackgroundTransparency = 0.35
				end)
				ConnectComponent(configBrowser, headerButton.MouseLeave, function()
					headerButton.BackgroundTransparency = 0.55
				end)
				ConnectComponent(configBrowser, headerButton.MouseButton1Click, function()
					configBrowser:Toggle()
				end)
				if searchBox then
					ConnectComponent(configBrowser, searchBox:GetPropertyChangedSignal("Text"), function()
						filterText = searchBox.Text:lower()
						renderBrowserRows()
					end)
				end
				applyExpanded(expanded)
				configBrowser:SetRows({})
			end

			Tab:CreateButton({
				Name = "Refresh Config List",
				Description = "Refresh the Select Config list.",
				Callback = function()
					refreshSelection(nil, true)
				end,
			})

			Tab:CreateSection("Config Load/Settings")
			Tab:CreateButton({Name = "Load Config", Description = "Load the selected config.", Callback = function()
				local name = requireSelected(); if not name then return end
				local success, result, warnings = Luna:LoadConfig(name)
				if not success then notify("Unable to load config: " .. tostring(result), "error"); return end
				if type(warnings) == "table" and #warnings > 0 then
					notify(string.format("Loaded %q with %d skipped setting(s).", name, #warnings), "warning")
				else
					notify(string.format("Loaded config %q", name), "check_circle")
				end
			end})

			Tab:CreateButton({Name = "Overwrite Config", Description = "Safely overwrite the selected JSON config.", Callback = function()
				local name = requireSelected(); if not name then return end
				local success, result = Luna:SaveConfig(name)
				if not success then notify("Unable to overwrite config: " .. tostring(result), "error"); return end
				notify(string.format("Overwrote config %q", result), "check_circle")
				refreshSelection(result, false)
			end})

			Tab:CreateInput({
				Name = "Rename Selected Config",
				Description = "Enter a new name, then press Rename Config.",
				PlaceholderText = "New name",
				CurrentValue = "",
				Enter = false,
				Callback = function(value) renamePath = tostring(value or "") end,
			})

			Tab:CreateButton({Name = "Rename Config", Description = "Rename the selected config without changing its contents.", Callback = function()
				local name = requireSelected(); if not name then return end
				local success, result = Luna:RenameConfig(name, renamePath)
				if not success then notify("Unable to rename config: " .. tostring(result), "error"); return end
				notify(string.format("Renamed %q to %q", name, result), "check_circle")
				renamePath = result
				refreshSelection(result, false)
			end})

			Tab:CreateButton({Name = "Delete Config", Description = "Press twice within 5 seconds to confirm deletion.", Callback = function()
				local name = requireSelected(); if not name then return end
				if deleteCandidate ~= name or (os.clock() - deleteCandidateTime) > 5 then
					deleteCandidate, deleteCandidateTime = name, os.clock()
					notify(string.format("Press Delete Config again to delete %q.", name), "warning")
					return
				end
				local success, result = Luna:DeleteConfig(name)
				deleteCandidate = nil
				if not success then notify("Unable to delete config: " .. tostring(result), "error"); return end
				notify(string.format("Deleted config %q", name), "check_circle")
				refreshSelection(nil, false)
			end})

			Tab:CreateButton({Name = "Delete All Configs", Description = "Press twice within 5 seconds to permanently delete every saved config.", Callback = function()
				local options = Luna:RefreshConfigList()
				if #options == 0 then
					notify("There are no saved configs to delete.", "info")
					return
				end
				if (os.clock() - deleteAllCandidateTime) > 5 then
					deleteAllCandidateTime = os.clock()
					notify(string.format("Press Delete All Configs again within 5 seconds to delete all %d config(s).", #options), "warning")
					return
				end

				deleteAllCandidateTime = 0
				local success, deletedCount, errors = Luna:DeleteAllConfigs()
				updateSelectedVisual(nil)
				if success then
					notify(string.format("Deleted all %d saved config(s).", tonumber(deletedCount) or 0), "check_circle")
				else
					local failedCount = type(errors) == "table" and #errors or 0
					notify(string.format("Deleted %d config(s), but %d could not be deleted.", tonumber(deletedCount) or 0, failedCount), "warning")
				end
				refreshSelection(nil, false)
			end})

			setAutoloadButton = Tab:CreateButton({
				Name = "Set as Autoload",
				Description = "Set the currently selected config to load automatically next session.",
				Callback = function()
					local name = requireSelected()
					if not name then return end

					local success, result = Luna:SetAutoload(name)
					if not success then
						notify("Unable to set autoload: " .. tostring(result), "error")
						refreshSelection(name, false)
						return
					end

					notify(string.format("Set %q to autoload", result), "check_circle")
					refreshSelection(name, false)
				end,
			})

			deleteAutoloadButton = Tab:CreateButton({
				Name = "Delete Autoload",
				Description = "Disable automatic config loading without deleting any saved config.",
				Callback = function()
					local currentAutoload = Luna:GetAutoload()
					if not currentAutoload then
						notify("Autoload is already disabled.", "info")
						refreshSelection(selectedConfig, true)
						return
					end

					local success, result = Luna:DeleteAutoload()
					if not success then
						notify("Unable to delete autoload: " .. tostring(result), "error")
						refreshSelection(selectedConfig, true)
						return
					end

					notify(string.format("Deleted autoload %q", currentAutoload), "check_circle")
					refreshSelection(selectedConfig, true)
				end,
			})

			-- Keep selection manual when the panel opens. Existing autoload status is
			-- shown only in the Autoload Config paragraph until the user selects a file.
			refreshSelection(nil, false)
			return {
				Refresh = function(_, selectName) return refreshSelection(selectName, true) end,
				GetSelected = function() return selectedConfig end,
				Select = function(_, name)
					local options = refreshSelection(name, false)
					return table.find(options, tostring(name)) ~= nil
				end,
				Browser = configBrowser,
				SetAutoloadButton = setAutoloadButton,
				DeleteAutoloadButton = deleteAutoloadButton,
			}
		end

		local ClassParser = {
			["Toggle"] = {
				Save = function(flag, data)
					return {
						type = "Toggle",
						flag = flag,
						state = data.CurrentValue == true,
					}
				end,
				Validate = function(data)
					return type(data.state) == "boolean",
						"Toggle state must be a boolean."
				end,
				Load = function(flag, data, loadOptions)
					Luna.Options[flag]:Set({
						CurrentValue = data.state,
						Silent = loadOptions and loadOptions.Silent == true,
						Force = loadOptions and loadOptions.Force == true,
					})
					return true
				end,
			},
			["Slider"] = {
				Save = function(flag, data)
					local value = tonumber(data.CurrentValue)
					if value == nil then
						return nil, "Slider value is not numeric."
					end
					return {
						type = "Slider",
						flag = flag,
						value = value,
					}
				end,
				Validate = function(data)
					return tonumber(data.value) ~= nil,
						"Slider value must be numeric."
				end,
				Load = function(flag, data, loadOptions)
					Luna.Options[flag]:Set({
						CurrentValue = tonumber(data.value),
						Silent = loadOptions and loadOptions.Silent == true,
						ForceCallback = loadOptions and loadOptions.ForceCallback == true,
					})
					return true
				end,
			},
			["Input"] = {
				Save = function(flag, data)
					return {
						type = "Input",
						flag = flag,
						text = tostring(data.CurrentValue or ""),
					}
				end,
				Validate = function(data)
					return type(data.text) == "string",
						"Input text must be a string."
				end,
				Load = function(flag, data, loadOptions)
					Luna.Options[flag]:Set({
						CurrentValue = data.text,
						Silent = loadOptions and loadOptions.Silent == true,
						ForceCallback = loadOptions and loadOptions.ForceCallback == true,
					})
					return true
				end,
			},
			["Dropdown"] = {
				Save = function(flag, data)
					local value = data.CurrentOption
					if type(value) ~= "table" and type(value) ~= "string" then
						return nil, "Dropdown value must be a string or table."
					end
					return {
						type = "Dropdown",
						flag = flag,
						value = value,
					}
				end,
				Validate = function(data)
					local valueType = type(data.value)
					return valueType == "table" or valueType == "string",
						"Dropdown value must be a string or table."
				end,
				Load = function(flag, data, loadOptions)
					Luna.Options[flag]:Set({
						CurrentOption = data.value,
						Silent = loadOptions and loadOptions.Silent == true,
					})
					return true
				end,
			},
			["Bind"] = {
				Save = function(flag, data)
					local bindName = InputBindingName(
						data.CurrentBind
							or (data.Settings and data.Settings.CurrentBind)
					)
					if not bindName then
						return nil, "Keybind is invalid."
					end
					return {
						type = "Bind",
						flag = flag,
						bind = bindName,
					}
				end,
				Validate = function(data)
					return InputBindingName(data.bind) ~= nil,
						"Keybind is invalid."
				end,
				Load = function(flag, data, loadOptions)
					local option = Luna.Options[flag]
					local bindName = InputBindingName(data.bind)
					option:Set({
						CurrentBind = bindName,
						Silent = loadOptions and loadOptions.Silent == true,
					})
					if loadOptions
						and loadOptions.ForceCallback == true
						and option.Settings
					then
						SafeCall(option.Settings.OnChangedCallback, bindName)
					end
					return true
				end,
			},
			["Colorpicker"] = {
				Save = function(flag, data)
					if typeof(data.Color) ~= "Color3" then
						return nil, "Colorpicker value is invalid."
					end
					local hex = string.format(
						"#%02X%02X%02X",
						math.floor(data.Color.R * 255 + 0.5),
						math.floor(data.Color.G * 255 + 0.5),
						math.floor(data.Color.B * 255 + 0.5)
					)
					return {
						type = "Colorpicker",
						flag = flag,
						color = hex,
						alpha = math.clamp(tonumber(data.Alpha) or 0, 0, 1),
					}
				end,
				Validate = function(data)
					if type(data.color) ~= "string"
						or not data.color:match("^#%x%x%x%x%x%x$")
					then
						return false, "Colorpicker hex value is invalid."
					end
					local alpha = tonumber(data.alpha)
					if alpha == nil or alpha < 0 or alpha > 1 then
						return false, "Colorpicker alpha must be between 0 and 1."
					end
					return true
				end,
				Load = function(flag, data, loadOptions)
					local color = Color3.fromRGB(
						tonumber(data.color:sub(2, 3), 16),
						tonumber(data.color:sub(4, 5), 16),
						tonumber(data.color:sub(6, 7), 16)
					)
					Luna.Options[flag]:Set({
						Color = color,
						Alpha = tonumber(data.alpha) or 0,
						Silent = loadOptions and loadOptions.Silent == true,
					})
					return true
				end,
			},
		}

		local CONFIG_FORMAT = "LunaJSON"
		local AUTOLOAD_FORMAT = "LunaAutoloadJSON"

		local function ValidateConfigDocument(decoded, requireCurrentOptions)
			if type(decoded) ~= "table" then
				return false, "Config root must be a JSON object."
			end

			local version = tonumber(decoded.version)
			if not version or version < 1 or version % 1 ~= 0 then
				return false, "Config version is invalid."
			end

			if version > Luna.ConfigVersion then
				return false, "Config was created by a newer Luna version."
			end

			if decoded.format ~= nil and decoded.format ~= CONFIG_FORMAT then
				return false, "Unsupported config format."
			end

			if type(decoded.objects) ~= "table" then
				return false, "Config objects must be an array."
			end

			local seenFlags = {}

			for index, object in ipairs(decoded.objects) do
				if type(object) ~= "table" then
					return false, ("Config object #%d is invalid."):format(index)
				end

				local flag = object.flag
				local objectType = object.type

				if type(flag) ~= "string" or flag == "" then
					return false, ("Config object #%d has an invalid flag."):format(index)
				end

				if seenFlags[flag] then
					return false, ("Duplicate flag %q exists in the JSON config."):format(flag)
				end
				seenFlags[flag] = true

				local parser = ClassParser[objectType]
				if not parser then
					return false, ("Unsupported config object type %q."):format(tostring(objectType))
				end

				local valid, validationError = parser.Validate(object)
				if not valid then
					return false, ("Invalid %s object %q: %s"):format(
						tostring(objectType),
						flag,
						tostring(validationError)
					)
				end

				if requireCurrentOptions then
					local current = Luna.Options[flag]
					if not current then
						return false, ("Config flag %q does not exist in the current interface."):format(flag)
					end
					if current.Class ~= objectType then
						return false, ("Config flag %q expects %s but found %s."):format(
							flag,
							tostring(current.Class),
							tostring(objectType)
						)
					end
				end
			end

			return true
		end


		function Tab:BuildThemeSection()

			local Title = Elements.Template.Title:Clone()
			Title.Text = "Theming"
			Title.Visible = true
			Title.Parent = TabPage
			Title.TextTransparency = 1
			TweenService:Create(Title, TweenInfo.new(0.4, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {TextTransparency = 0}):Play()

			Tab:CreateSection("Custom Editor")

			local c1cp = Tab:CreateColorPicker({
				Name = "Color 1",
				Color = Color3.fromRGB(117, 164, 206),
			}, "LunaInterfaceSuitePrebuiltCPC1") -- A flag is the identifier for the configuration file, make sure every element has a different flag if you're using configuration saving to ensure no overlaps

			local c2cp = Tab:CreateColorPicker({
				Name = "Color 2",
				Color = Color3.fromRGB(123, 201, 201),
			}, "LunaInterfaceSuitePrebuiltCPC2")

			local c3cp = Tab:CreateColorPicker({
				Name = "Color 3",
				Color = Color3.fromRGB(224, 138, 175),
			}, "LunaInterfaceSuitePrebuiltCPC3") 


			c1cp:Set({
				Callback = function(Value)
					if c2cp and c3cp then
						Luna.ThemeGradient = ColorSequence.new{ColorSequenceKeypoint.new(0.00, Value or Color3.fromRGB(255,255,255)), ColorSequenceKeypoint.new(0.50, c2cp.Color or Color3.fromRGB(255,255,255)), ColorSequenceKeypoint.new(1.00, c3cp.Color or Color3.fromRGB(255,255,255))}
						LunaUI.ThemeRemote.Value = not LunaUI.ThemeRemote.Value
					end
				end
			})

			c2cp:Set({
				Callback = function(Value)
					if c1cp and c3cp then
						Luna.ThemeGradient = ColorSequence.new{ColorSequenceKeypoint.new(0.00, c1cp.Color or Color3.fromRGB(255,255,255)), ColorSequenceKeypoint.new(0.50, Value or Color3.fromRGB(255,255,255)), ColorSequenceKeypoint.new(1.00, c3cp.Color or Color3.fromRGB(255,255,255))}
						LunaUI.ThemeRemote.Value = not LunaUI.ThemeRemote.Value
					end
				end
			})

			c3cp:Set({
				Callback = function(Valuex)
					if c2cp and c1cp then
						Luna.ThemeGradient = ColorSequence.new{ColorSequenceKeypoint.new(0.00, c1cp.Color or Color3.fromRGB(255,255,255)), ColorSequenceKeypoint.new(0.50, c2cp.Color or Color3.fromRGB(255,255,255)), ColorSequenceKeypoint.new(1.00, Valuex or Color3.fromRGB(255,255,255))}
						LunaUI.ThemeRemote.Value = not LunaUI.ThemeRemote.Value
					end
				end
			})

			Tab:CreateSection("Preset Gradients")

			for i,v in pairs(PresetGradients) do
				Tab:CreateButton({
					Name = tostring(i),
					Callback = function()
						c1cp:Set({ Color = v[1] })
						c2cp:Set({ Color = v[2] })
						c3cp:Set({ Color = v[3] })
					end,
				})
			end

		end


		local function BuildFolderTree()
			return EnsureFolderPath(Luna.Folder .. "/settings")
		end

		local function SetFolder()
			if WindowSettings.ConfigSettings.RootFolder ~= nil
				and WindowSettings.ConfigSettings.RootFolder ~= ""
			then
				Luna.Folder =
					tostring(WindowSettings.ConfigSettings.RootFolder)
					.. "/"
					.. tostring(WindowSettings.ConfigSettings.ConfigFolder)
			else
				Luna.Folder =
					tostring(WindowSettings.ConfigSettings.ConfigFolder)
			end
			return BuildFolderTree()
		end
		SetFolder()

		local function ConfigName(path)
			local name = tostring(path or "")
			name = name:gsub("%.[Jj][Ss][Oo][Nn]$", "")
			return SanitizeFileName(name)
		end

		local function ConfigPath(path)
			local safe = ConfigName(path)
			if not safe then
				return nil, "Please provide a valid config name."
			end
			local loweredName = safe:lower()
			if loweredName == "autoload" or loweredName == "nil" then
				return nil, ('The name %q is reserved by Luna.'):format(safe)
			end
			return Luna.Folder
				.. "/settings/"
				.. safe
				.. Luna.ConfigExtension,
				safe
		end

		local function AutoloadPath()
			return Luna.Folder .. "/settings/autoload.json"
		end

		local function WriteVerifiedFile(path, content)
			if type(writefile) ~= "function" then
				return false, "Executor does not support writefile."
			end

			local temporary =
				path
				.. ".tmp-"
				.. HttpService:GenerateGUID(false)

			local tempSuccess, tempError =
				pcall(writefile, temporary, content)
			if not tempSuccess then
				return false, tostring(tempError)
			end

			if type(readfile) == "function" then
				local verifySuccess, verifyContent =
					pcall(readfile, temporary)
				if not verifySuccess or verifyContent ~= content then
					if type(delfile) == "function" then
						pcall(delfile, temporary)
					end
					return false, "Temporary config verification failed."
				end
			end

			local writeSuccess, writeError =
				pcall(writefile, path, content)
			if not writeSuccess then
				if type(delfile) == "function" then
					pcall(delfile, temporary)
				end
				return false, tostring(writeError)
			end

			if type(readfile) == "function" then
				local verifySuccess, verifyContent =
					pcall(readfile, path)
				if not verifySuccess or verifyContent ~= content then
					if type(delfile) == "function" then
						pcall(delfile, temporary)
					end
					return false, "Final config verification failed."
				end
			end

			if type(delfile) == "function" then
				pcall(delfile, temporary)
			end

			return true
		end

		local function EncodeJson(value)
			local success, encoded =
				pcall(HttpService.JSONEncode, HttpService, value)
			if not success then
				return false, "Unable to encode JSON: " .. tostring(encoded)
			end
			return true, encoded
		end

		local function DecodeJson(raw)
			local success, decoded =
				pcall(HttpService.JSONDecode, HttpService, tostring(raw or ""))
			if not success then
				return false, "Unable to decode JSON: " .. tostring(decoded)
			end
			return true, decoded
		end

		function Luna:SaveConfig(path)
			local fullPath, safeName = ConfigPath(path)
			if not fullPath then return false, safeName end

			local folderSuccess, folderError = BuildFolderTree()
			if not folderSuccess then return false, folderError end

			local createdAt = os.time()

			if type(isfile) == "function"
				and type(readfile) == "function"
				and isfile(fullPath)
			then
				local oldReadSuccess, oldRaw = pcall(readfile, fullPath)
				if oldReadSuccess then
					local oldDecodeSuccess, oldDecoded = DecodeJson(oldRaw)
					if oldDecodeSuccess and type(oldDecoded) == "table" then
						createdAt = tonumber(oldDecoded.createdAt) or createdAt
					end
				end
			end

			local data = {
				format = CONFIG_FORMAT,
				version = Luna.ConfigVersion,
				libraryVersion = Luna.Version,
				createdAt = createdAt,
				updatedAt = os.time(),
				placeId = game.PlaceId,
				objects = {},
			}

			local flags = {}
			for flag, option in pairs(Luna.Options) do
				if ClassParser[option.Class] and not option.IgnoreConfig then
					table.insert(flags, flag)
				end
			end
			table.sort(flags)

			for _, flag in ipairs(flags) do
				local option = Luna.Options[flag]
				local parser = ClassParser[option.Class]
				local success, object, saveError =
					pcall(parser.Save, flag, option)

				if not success then
					return false, ("Unable to save flag %q: %s"):format(
						flag,
						tostring(object)
					)
				end

				if type(object) ~= "table" then
					return false, ("Unable to save flag %q: %s"):format(
						flag,
						tostring(saveError or "parser returned no object")
					)
				end

				table.insert(data.objects, object)
			end

			local valid, validationError =
				ValidateConfigDocument(data, true)
			if not valid then
				return false, validationError
			end

			local encodedSuccess, encoded = EncodeJson(data)
			if not encodedSuccess then return false, encoded end

			local writeSuccess, writeError =
				WriteVerifiedFile(fullPath, encoded)
			if not writeSuccess then
				EmitEvent("ConfigFailed", "Save", safeName, writeError)
				return false, writeError
			end

			Luna._KnownConfigs[safeName] = true
			EmitEvent("ConfigSaved", safeName, data)
			return true, safeName
		end

		function Luna:LoadConfig(path, loadOptions)
			loadOptions = type(loadOptions) == "table" and loadOptions or {}
			EmitEvent("ConfigLoading", path, loadOptions)
			local strict = loadOptions.Strict
			if strict == nil then strict = Luna.StrictConfig == true end
			local fireCallbacks = loadOptions.FireCallbacks ~= false

			local fullPath, safeName = ConfigPath(path)
			if not fullPath then return false, safeName end

			if type(isfile) ~= "function"
				or type(readfile) ~= "function"
			then
				return false, "Executor does not support config reading."
			end

			if not isfile(fullPath) then
				return false, "Config does not exist."
			end

			local readSuccess, raw = pcall(readfile, fullPath)
			if not readSuccess then return false, tostring(raw) end

			local decodeSuccess, decoded = DecodeJson(raw)
			if not decodeSuccess then return false, decoded end

			local valid, validationError =
				ValidateConfigDocument(decoded, false)
			if not valid then return false, validationError end

			local applicable = {}
			local warnings = {}

			for _, object in ipairs(decoded.objects) do
				local current = Luna.Options[object.flag]
				if not current then
					local warning =
						("Config flag %q does not exist in the current interface."):format(
							object.flag
						)
					if strict then return false, warning end
					table.insert(warnings, warning)
				elseif current.Class ~= object.type then
					local warning =
						("Config flag %q expects %s but found %s."):format(
							object.flag,
							tostring(current.Class),
							tostring(object.type)
						)
					if strict then return false, warning end
					table.insert(warnings, warning)
				else
					table.insert(applicable, object)
				end
			end

			local snapshots = {}
			for _, object in ipairs(applicable) do
				local option = Luna.Options[object.flag]
				local parser = ClassParser[option.Class]
				local snapshotSuccess, snapshot, snapshotError =
					pcall(parser.Save, object.flag, option)
				if not snapshotSuccess or type(snapshot) ~= "table" then
					return false, ("Unable to snapshot flag %q: %s"):format(
						object.flag,
						tostring(snapshotError or snapshot)
					)
				end
				table.insert(snapshots, snapshot)
			end

			local function applyObjects(objects, silent, forceCallbacks)
				for _, object in ipairs(objects) do
					local parser = ClassParser[object.type]
					local success, result = pcall(
						parser.Load,
						object.flag,
						object,
						{
							Silent = silent == true,
							Force = true,
							ForceCallback = forceCallbacks == true,
						}
					)
					if not success or result ~= true then
						return false, ("Unable to load flag %q: %s"):format(
							object.flag,
							tostring(result)
						)
					end
				end
				return true
			end

			-- Phase one is silent so component state can be rolled back safely.
			local applySuccess, applyError = applyObjects(applicable, true, false)
			if applySuccess then
				NormalizeAllToggleGroups(false)
			else
				applyObjects(snapshots, true, false)
				NormalizeAllToggleGroups(false)
				Luna._Stats.ConfigRollbacks += 1
				return false, applyError
			end

			-- Preserve the old Luna behaviour by notifying components only after
			-- every state has been applied successfully.
			if fireCallbacks then
				local callbackSuccess, callbackError =
					applyObjects(applicable, false, true)
				if not callbackSuccess then
					applyObjects(snapshots, true, false)
					NormalizeAllToggleGroups(false)
					Luna._Stats.ConfigRollbacks += 1
					return false, callbackError
				end
				NormalizeAllToggleGroups(false)
			end

			Luna._Stats.ConfigWarnings += #warnings
			Luna._KnownConfigs[safeName] = true
			EmitEvent("ConfigLoaded", safeName, warnings)
			return true, safeName, warnings
		end

		function Luna:RefreshConfigList()
			local output = {}
			local seen = {}

			local function addName(name)
				name = ConfigName(name)
				if name and name:lower() ~= "autoload" and name:lower() ~= "nil" and not seen[name] then
					seen[name] = true
					table.insert(output, name)
				end
			end

			for name in pairs(Luna._KnownConfigs or {}) do
				addName(name)
			end

			if type(listfiles) == "function" then
				local folderSuccess = BuildFolderTree()
				if folderSuccess then
					local success, files = pcall(listfiles, Luna.Folder .. "/settings")
					if success and type(files) == "table" then
						for _, filePath in ipairs(files) do
							local name = tostring(filePath):match("([^/\\]+)%.json$")
							if name then addName(name) end
						end
					end
				end
			end

			table.sort(output)
			return output
		end

		function Luna:DeleteConfig(path)
			local fullPath, safeName = ConfigPath(path)
			if not fullPath then return false, safeName end

			if type(isfile) ~= "function"
				or type(delfile) ~= "function"
			then
				return false, "Executor does not support deleting files."
			end

			if not isfile(fullPath) then
				return false, "Config does not exist."
			end

			local success, deleteError = pcall(delfile, fullPath)
			if not success then return false, tostring(deleteError) end

			if self:GetAutoload() == safeName then
				self:DeleteAutoload()
			end

			Luna._KnownConfigs[safeName] = nil
			return true, safeName
		end

		function Luna:DeleteAllConfigs()
			local configs = self:RefreshConfigList()
			local deleted = {}
			local errors = {}

			for _, name in ipairs(configs) do
				local success, result = self:DeleteConfig(name)
				if success then
					table.insert(deleted, result or name)
				else
					table.insert(errors, {
						Config = name,
						Error = tostring(result),
					})
				end
			end

			if #errors == 0 and self:GetAutoload() then
				self:DeleteAutoload()
			end

			return #errors == 0, #deleted, errors
		end

		function Luna:RenameConfig(oldName, newName)
			local oldPath, safeOld = ConfigPath(oldName)
			local newPath, safeNew = ConfigPath(newName)
			if not oldPath then return false, safeOld end
			if not newPath then return false, safeNew end

			if type(readfile) ~= "function"
				or type(writefile) ~= "function"
				or type(delfile) ~= "function"
				or type(isfile) ~= "function"
			then
				return false, "Executor does not support renaming files."
			end

			if not isfile(oldPath) then
				return false, "Original config does not exist."
			end
			if isfile(newPath) then
				return false, "A config with the new name already exists."
			end

			local readSuccess, raw = pcall(readfile, oldPath)
			if not readSuccess then return false, tostring(raw) end

			local decodeSuccess, decoded = DecodeJson(raw)
			if not decodeSuccess then return false, decoded end
			local valid, validationError =
				ValidateConfigDocument(decoded, false)
			if not valid then return false, validationError end

			local writeSuccess, writeError =
				WriteVerifiedFile(newPath, raw)
			if not writeSuccess then return false, writeError end

			local deleteSuccess, deleteError =
				pcall(delfile, oldPath)
			if not deleteSuccess then
				pcall(delfile, newPath)
				return false,
					"Rename rollback: unable to delete original config: "
					.. tostring(deleteError)
			end

			if self:GetAutoload() == safeOld then
				local autoloadSuccess, autoloadError =
					self:SetAutoload(safeNew)
				if not autoloadSuccess then
					return false,
						"Config renamed, but autoload update failed: "
						.. tostring(autoloadError)
				end
			end

			Luna._KnownConfigs[safeOld] = nil
			Luna._KnownConfigs[safeNew] = true
			return true, safeNew
		end

		function Luna:SetAutoload(path)
			local fullPath, safeName = ConfigPath(path)
			if not fullPath then
				return false, safeName
			end

			if not table.find(self:RefreshConfigList(), safeName) then
				return false, "Config does not exist."
			end

			local data = {
				format = AUTOLOAD_FORMAT,
				version = 1,
				config = safeName,
			}

			local encodeSuccess, encoded = EncodeJson(data)
			if not encodeSuccess then return false, encoded end

			local writeSuccess, writeError =
				WriteVerifiedFile(AutoloadPath(), encoded)
			return writeSuccess,
				writeSuccess and safeName or writeError
		end

		function Luna:GetAutoload()
			local path = AutoloadPath()
			if type(isfile) ~= "function"
				or type(readfile) ~= "function"
				or not isfile(path)
			then
				return nil
			end

			local readSuccess, raw = pcall(readfile, path)
			if not readSuccess then return nil end

			local decodeSuccess, decoded = DecodeJson(raw)
			if not decodeSuccess
				or type(decoded) ~= "table"
				or decoded.format ~= AUTOLOAD_FORMAT
				or tonumber(decoded.version) ~= 1
			then
				return nil
			end

			local safeName = ConfigName(decoded.config)
			if not safeName then return nil end

			local configPath = ConfigPath(safeName)
			if type(isfile) == "function" and not isfile(configPath) then
				return nil
			end

			return safeName
		end

		function Luna:DeleteAutoload()
			local path = AutoloadPath()
			if type(isfile) ~= "function"
				or type(delfile) ~= "function"
			then
				return false, "Executor does not support deleting files."
			end

			if not isfile(path) then
				return true, "Autoload is already disabled."
			end

			local success, deleteError = pcall(delfile, path)
			return success,
				success and "Autoload deleted." or tostring(deleteError)
		end

		function Luna:LoadAutoloadConfig(loadOptions)
			local name = self:GetAutoload()
			if not name then
				return false, "No valid autoload JSON is set."
			end

			local success, result, warnings = self:LoadConfig(name, loadOptions)
			if not success then
				self:Notification({
					Title = "Interface",
					Icon = "warning",
					ImageSource = "Material",
					Content =
						"Failed to load autoload config: "
						.. tostring(result),
				})
				return false, result
			end

			local warningCount = type(warnings) == "table" and #warnings or 0
			self:Notification({
				Title = "Interface",
				Icon = warningCount > 0 and "warning" or "sparkle",
				ImageSource = "Material",
				Content = warningCount > 0
					and string.format(
						"Auto loaded %q with %d skipped setting(s).",
						name,
						warningCount
					)
					or string.format("Auto loaded JSON config %q", name),
			})
			return true, name, warnings
		end

		function Luna:ExportConfig(path)
			local fullPath, safeName = ConfigPath(path)
			if not fullPath then return false, safeName end

			if type(isfile) ~= "function"
				or type(readfile) ~= "function"
				or not isfile(fullPath)
			then
				return false, "Config does not exist."
			end

			local success, raw = pcall(readfile, fullPath)
			return success,
				success and raw or tostring(raw)
		end

		function Luna:ImportConfig(path, json)
			local decodeSuccess, decoded = DecodeJson(json)
			if not decodeSuccess then return false, decoded end

			local valid, validationError =
				ValidateConfigDocument(decoded, true)
			if not valid then return false, validationError end

			decoded.format = CONFIG_FORMAT
			decoded.version = Luna.ConfigVersion
			decoded.libraryVersion = Luna.Version
			decoded.updatedAt = os.time()
			decoded.createdAt =
				tonumber(decoded.createdAt) or os.time()

			local fullPath, safeName = ConfigPath(path)
			if not fullPath then return false, safeName end

			local folderSuccess, folderError = BuildFolderTree()
			if not folderSuccess then return false, folderError end

			local encodeSuccess, normalized = EncodeJson(decoded)
			if not encodeSuccess then return false, normalized end

			local writeSuccess, writeError =
				WriteVerifiedFile(fullPath, normalized)
			if writeSuccess then Luna._KnownConfigs[safeName] = true end
			return writeSuccess,
				writeSuccess and safeName or writeError
		end


		Tab._Page = TabPage
		Tab._Button = TabButton
		Tab._Object = TabPage
		EnhanceComponent(Tab)
		Tab._Window = Window
		Tab._Name = TabSettings.Name
		EnhanceContainerAPI(Tab, TabPage, Window, Tab, {
			Name = TabSettings.Name,
			Button = TabButton,
			IsTab = true,
		})
		if type(Window._RegisterTab) == "function" then Window:_RegisterTab(Tab) end
		return Tab
	end


	Elements.Parent.Visible = true
	tween(Elements.Parent, {BackgroundTransparency = 0.1})
	Navigation.Visible = true
	tween(Navigation.Line, {BackgroundTransparency = 0})

	for _, TopbarButton in ipairs(Main.Controls:GetChildren()) do
		if TopbarButton.ClassName == "Frame" and TopbarButton.Name ~= "Theme" then
			TopbarButton.Visible = true
			tween(TopbarButton, {BackgroundTransparency = 0.25})
			tween(TopbarButton.UIStroke, {Transparency = 0.5})
			tween(TopbarButton.ImageLabel, {ImageTransparency = 0.25})
		end
	end

	local function HideWindow()
		if Luna._Destroyed or not Window.State then
			return false
		end

		-- Commit logical state before touching visuals so a second input
		-- always sees the newest state, even when keys are spammed.
		Window.State = false
		dragBar.Visible = false
		if StatusDisplay then StatusDisplay.Visible = false end

		Hide(
			Main,
			Window.MinimizeBind,
			Window.MinimizeShowNotification,
			Window.MinimizeNotificationCooldown
		)

		if UserInputService.KeyboardEnabled == false then
			LunaUI.MobileSupport.Visible = true
		end
		EmitEvent("WindowHidden", Window)
		return true
	end

	local function ShowWindow()
		if Luna._Destroyed or Window.State then
			return false
		end

		Window.State = true
		LunaUI.MobileSupport.Visible = false
		dragBar.Visible = true
		Unhide(Main, Window.CurrentTab)
		RefreshStatusDisplay()
		EmitEvent("WindowOpened", Window)
		return true
	end

	local function ToggleWindowVisibility()
		if Window.State then
			return HideWindow()
		end
		return ShowWindow()
	end

	local function CloseWindow()
		if Luna._Destroyed then return end
		Window.State = false
		dragBar.Visible = false
		LunaUI.MobileSupport.Visible = false
		Luna:Destroy()
	end

	-- Minus button: hide the GUI and show the hidden-interface notification.
	if HideControl and HideControl:FindFirstChild("ImageLabel") then
		local HideTarget = HideControl.ImageLabel
		local MinusGlyph = HideTarget:FindFirstChild("MinusGlyph")

		TrackConnection(HideTarget.MouseButton1Click:Connect(function()
			if Window.MinimizeEnabled then
				HideWindow()
			end
		end))
		TrackConnection(HideControl.MouseEnter:Connect(function()
			if MinusGlyph then tween(MinusGlyph, {TextColor3 = Color3.new(1,1,1)}) end
		end))
		TrackConnection(HideControl.MouseLeave:Connect(function()
			if MinusGlyph then tween(MinusGlyph, {TextColor3 = Color3.fromRGB(195,195,195)}) end
		end))
	end

	-- X button: permanently destroy the interface and all tracked connections.
	TrackConnection(Main.Controls.Close.ImageLabel.MouseButton1Click:Connect(CloseWindow))
	TrackConnection(Main.Controls.Close["MouseEnter"]:Connect(function()
		tween(Main.Controls.Close.ImageLabel, {ImageColor3 = Color3.new(1,1,1)})
	end))
	TrackConnection(Main.Controls.Close["MouseLeave"]:Connect(function()
		tween(Main.Controls.Close.ImageLabel, {ImageColor3 = Color3.fromRGB(195,195,195)})
	end))

	TrackConnection(UserInputService.InputBegan:Connect(function(input, gpe)
		if gpe or Luna._Destroyed or not Window.MinimizeEnabled then
			return
		end

		-- Do not hide the UI while the user is typing or recording a bind.
		if UserInputService:GetFocusedTextBox() then
			return
		end

		if InputMatchesBinding(input, Window.MinimizeBind) then
			ToggleWindowVisibility()
		end
	end))

	TrackConnection(Main.Logo.MouseButton1Click:Connect(function()
		if Navigation.Size.X.Offset == 205 then
			tween(Elements.Parent, {Size = UDim2.new(1, -55, Elements.Parent.Size.Y.Scale, Elements.Parent.Size.Y.Offset)})
			tween(Navigation, {Size = UDim2.new(Navigation.Size.X.Scale, 55, Navigation.Size.Y.Scale, Navigation.Size.Y.Offset)})
		else
			tween(Elements.Parent, {Size = UDim2.new(1, -205, Elements.Parent.Size.Y.Scale, Elements.Parent.Size.Y.Offset)})
			tween(Navigation, {Size = UDim2.new(Navigation.Size.X.Scale, 205, Navigation.Size.Y.Scale, Navigation.Size.Y.Offset)})
		end
	end))

	TrackConnection(Main.Controls.ToggleSize.ImageLabel.MouseButton1Click:Connect(function()
		Window.Size = not Window.Size
		if Window.Size then
			Minimize(Main)
			dragBar.Visible = false
		else
			Maximise(Main)
			dragBar.Visible = true
		end
	end))
	TrackConnection(Main.Controls.ToggleSize.MouseEnter:Connect(function()
		tween(Main.Controls.ToggleSize.ImageLabel, {ImageColor3 = Color3.new(1,1,1)})
	end))
	TrackConnection(Main.Controls.ToggleSize.MouseLeave:Connect(function()
		tween(Main.Controls.ToggleSize.ImageLabel, {ImageColor3 = Color3.fromRGB(195,195,195)})
	end))

	TrackConnection(Main.Controls.Theme.ImageLabel.MouseButton1Click:Connect(function()
		if Window.Settings then
			Window.Settings:Activate()
			Elements.Settings.CanvasPosition = Vector2.new(0,698)
		end
	end))
	TrackConnection(Main.Controls.Theme.MouseEnter:Connect(function()
		tween(Main.Controls.Theme.ImageLabel, {ImageColor3 = Color3.new(1,1,1)})
	end))
	TrackConnection(Main.Controls.Theme.MouseLeave:Connect(function()
		tween(Main.Controls.Theme.ImageLabel, {ImageColor3 = Color3.fromRGB(195,195,195)})
	end))	


	TrackConnection(LunaUI.MobileSupport.Interact.MouseButton1Click:Connect(function()
		ShowWindow()
	end))

	function Window:SetMinimizeKeybind(value)
		local binding, bindError = NormalizeInputBinding(value)
		if not binding then
			return false, bindError
		end

		self.MinimizeBind = binding
		self.Bind = binding.EnumItem
		WindowSettings.MinimizeSettings.Keybind = binding.EnumItem
		return true, binding.Name
	end

	function Window:GetMinimizeKeybind()
		return InputBindingName(self.MinimizeBind)
	end

	function Window:GetMinimizeKeybindEnum()
		return self.MinimizeBind and self.MinimizeBind.EnumItem or nil
	end

	function Window:SetMinimizeEnabled(enabled)
		local nextState = enabled ~= false
		if not nextState and not self.State then
			ShowWindow()
		end
		self.MinimizeEnabled = nextState
		return self.MinimizeEnabled
	end

	function Window:ToggleVisibility()
		return ToggleWindowVisibility()
	end

	function Window:Minimize()
		return HideWindow()
	end

	function Window:Restore()
		return ShowWindow()
	end

	function Window:Hide() return HideWindow() end
	function Window:Close() CloseWindow() end
	function Window:Destroy() CloseWindow() end
	function Window:DestroyLibrary() Luna:Destroy() end
	function Window:GetDiagnostics() return Luna:GetDiagnostics() end
	EnhanceWindowProductivity(Window, WindowSettings)
	Luna._Windows[Window] = true
	EmitEvent("WindowCreated", Window)
	return Window
end

function Luna:Destroy()
	if Luna._Destroyed then return end
	Luna._Destroyed = true
	EmitEvent("Destroyed", Luna)

	while #Luna._NotificationQueue > 0 do
		CloseNotificationRecord(Luna._NotificationQueue[1], true)
	end
	Luna._Stats.ActiveNotifications = 0

	for _, cleanup in ipairs(Luna._Cleanups) do
		pcall(cleanup)
	end
	table.clear(Luna._Cleanups)
	DisconnectConnections(Luna._Connections)

	pcall(function() Main.Visible = false end)
	for _, notification in ipairs(Notifications:GetChildren()) do
		if notification.ClassName == "Frame" then
			pcall(function() notification:Destroy() end)
		end
	end
	table.clear(Luna.Options)
	table.clear(Luna._Components)
	table.clear(Luna._ToggleGroups)
	table.clear(Luna._MutatingToggleGroups)
	table.clear(Luna._Events)
	table.clear(Luna._NotificationHistory)
	table.clear(Luna._NotificationById)
	table.clear(Luna._Themes)
	table.clear(Luna._Windows)
	table.clear(ActiveTweens)
	Luna._Stats.RenderLoops = 0
	if rawget(GlobalEnvironment, "__LUNA_ACTIVE_LIBRARY") == Luna then
		GlobalEnvironment.__LUNA_ACTIVE_LIBRARY = nil
	end
	pcall(function() LunaUI:Destroy() end)
end

return Luna
