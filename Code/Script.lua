GameVar("MarsKeepsSpinningPreferredSpeed", "normal")

local original_set_game_speed = SetGameSpeed
local original_pause = Pause
local original_resume = Resume
local DEBUG = false
local pending_normal_speed = false

local function LogState(event)
	if not DEBUG then
		return
	end
	local reasons = {}
	for reason in pairs(PauseReasons) do
		reasons[#reasons + 1] = tostring(type(reason) == "table" and reason.class or reason)
	end
	table.sort(reasons)
	print("[MarsKeepsSpinning] " .. event
		.. " | factor=" .. tostring(GetTimeFactor())
		.. " paused=" .. tostring(IsPaused())
		.. " preferred=" .. tostring(MarsKeepsSpinningPreferredSpeed)
		.. " last=" .. tostring(LastGameSpeed)
		.. " reasons=" .. table.concat(reasons, ","))
end

local function HasAutomaticPause()
	for reason in pairs(PauseReasons) do
		if reason ~= "UI" then
			return true
		end
	end
	return false
end

function SetGameSpeed(speed, gamepad, keep_sounds)
	local requested = speed
	if HasAutomaticPause() then
		LogState("Speed request ignored during automatic pause: " .. tostring(requested))
		return
	end
	if speed == "pause" or type(speed) == "number" and speed < const.GameSpeeds.normal then
		speed = "normal"
	elseif speed == "prev" and GetTimeFactor() <= const.DefaultTimeFactor * 2 then
		speed = "normal"
	end
	local result = original_set_game_speed(speed, gamepad, keep_sounds)
	local selected = const.GameSpeeds[LastGameSpeed] or LastGameSpeed
	if type(selected) == "number" and selected > const.GameSpeeds.normal then
		MarsKeepsSpinningPreferredSpeed = LastGameSpeed
	end
	LogState("Speed request " .. tostring(requested) .. " -> " .. tostring(speed))
	return result
end

local function ApplyPendingNormalSpeed()
	if not pending_normal_speed or HasAutomaticPause() then
		return
	end
	pending_normal_speed = false
	Resume("UI")
	SetGameSpeed("normal")
	LogState("Deferred normal default applied")
end

function Pause(reason, keep_sounds)
	if reason == "UI" then
		LogState("Manual UI pause blocked")
		return
	end
	local result = original_pause(reason, keep_sounds)
	LogState("Automatic pause added")
	return result
end

function Resume(reason)
	local was_paused_for_reason = PauseReasons[reason or false]
	local result = original_resume(reason)
	if was_paused_for_reason then
		LogState("Pause reason removed: " .. tostring(type(reason) == "table" and reason.class or reason))
	end
	ApplyPendingNormalSpeed()
	return result
end

function TogglePause()
	if HasAutomaticPause() then
		LogState("Speed toggle ignored during automatic pause")
		return
	end
	if GetTimeFactor() > const.DefaultTimeFactor then
		SetGameSpeed("normal")
	else
		SetGameSpeed(MarsKeepsSpinningPreferredSpeed)
	end
end

local function StartAtNormalSpeed(event)
	LogState(event .. ": requesting normal default")
	pending_normal_speed = true
	Resume("UI")
	ApplyPendingNormalSpeed()
	if pending_normal_speed then
		LogState("Normal default deferred until automatic pauses end")
	end
end

function OnMsg.NewGame()
	StartAtNormalSpeed("NewGame")
end

function OnMsg.PostLoadGame()
	StartAtNormalSpeed("PostLoadGame")
end

function OnMsg.DoneGame()
	pending_normal_speed = false
end

local disabled_buttons = setmetatable({}, {__mode = "k"})
local patched_classes = setmetatable({}, {__mode = "k"})

local function UpdatePauseAction()
	local actions = XShortcutsTarget and XShortcutsTarget:GetActions()
	for _, action in ipairs(actions or empty_table) do
		if action.ActionId == "actionPauseGame" then
			action.ActionBindable = false
			action:SetActionShortcuts("Space", "", "RightThumbClick")
			action.OnAction = function()
				local hud = GetHUD()
				if hud and hud:IsVisible() then
					TogglePause()
				end
			end
		end
	end
end

local function DisablePauseButton(hud)
	local button = hud.idPause
	if not button then
		return
	end
	button:SetEnabled(false)
	button:SetToggled(false)
	if disabled_buttons[button] then
		return
	end
	disabled_buttons[button] = true
	button:SetOnPress(empty_func)
	button:SetRolloverDisabledTitle(Untranslated("Pause disabled"))
	button:SetRolloverDisabledText(Untranslated("Mars keeps spinning."))
	button:SetRolloverHint("")
	button:SetRolloverHintGamepad("")
	button:AddInterpolation {
		id = "MarsKeepsSpinningDesaturation",
		type = const.intDesaturation,
		startValue = 255,
	}
	LogState("HUD pause button disabled; creating red cross")
	local overlay = XWindow:new({
		Dock = "box",
		HandleMouse = false,
		ZOrder = 10,
		DrawContent = function()
			local bounds = button.content_box
			local half_size = math.floor(math.min(bounds:sizex(), bounds:sizey()) * 0.3)
			if half_size <= 0 then
				return
			end
			local center_x = math.floor((bounds:minx() + bounds:maxx()) / 2)
			local center_y = math.floor((bounds:miny() + bounds:maxy()) / 2)
			local color = RGB(230, 45, 45)
			for offset = -1, 1 do
				UIL.DrawLine(
					point(center_x - half_size, center_y - half_size + offset),
					point(center_x + half_size, center_y + half_size + offset), color)
				UIL.DrawLine(
					point(center_x - half_size, center_y + half_size + offset),
					point(center_x + half_size, center_y - half_size + offset), color)
			end
		end,
	}, button.parent)
	overlay:Open()
end

local function InstallUIHooks()
	local options_class = g_Classes and g_Classes.OptionsObject
	if options_class and not patched_classes[options_class] then
		patched_classes[options_class] = true
		local original_get_shortcuts = options_class.GetShortcuts
		function options_class:GetShortcuts(...)
			UpdatePauseAction()
			return original_get_shortcuts(self, ...)
		end
	end
	UpdatePauseAction()
end

MapRealTimeRepeat("MarsKeepsSpinningPauseButton", 250, function()
	local hud = GetHUD()
	if hud and hud.window_state ~= "destroying" then
		DisablePauseButton(hud)
	end
end)

OnMsg.ClassesPostprocess = InstallUIHooks
OnMsg.ModsReloaded = InstallUIHooks
OnMsg.ShortcutsReloaded = UpdatePauseAction
InstallUIHooks()
LogState("Mod code loaded")