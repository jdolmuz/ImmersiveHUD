-- Immersive HUD options: Settings panel (Esc > Options > AddOns) + slash commands.

local ADDON_NAME, ns = ...

BINDING_HEADER_IMMERSIVEHUD = "Immersive HUD"
BINDING_NAME_IMMERSIVEHUD_PEEK = "Pin / unpin HUD"
BINDING_NAME_IMMERSIVEHUD_TOGGLE = "Enable / disable auto-fade"

local function Print(msg)
    print("|cff66ccffImmersive HUD:|r " .. msg)
end

local category

local function BuildPanel(IHUD)
    local db = IHUD.db
    category = Settings.RegisterVerticalLayoutCategory("Immersive HUD")
    local layout = SettingsPanel and SettingsPanel.GetLayout and SettingsPanel:GetLayout(category)

    local function Header(text)
        if layout and CreateSettingsListSectionHeaderInitializer then
            layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text))
        end
    end

    local function OnChange()
        IHUD:Refresh()
    end

    local function Register(key, name, varType)
        local setting = Settings.RegisterAddOnSetting(category, "IHUD_" .. key, key, db,
            varType, name, IHUD.DEFAULTS[key])
        if setting.SetValueChangedCallback then
            setting:SetValueChangedCallback(OnChange)
        elseif Settings.SetOnValueChangedCallback then
            Settings.SetOnValueChangedCallback("IHUD_" .. key, OnChange)
        end
        return setting
    end

    local function Checkbox(key, name, tooltip)
        Settings.CreateCheckbox(category, Register(key, name, Settings.VarType.Boolean), tooltip)
    end

    local function Slider(key, name, min, max, step, fmt, tooltip)
        local setting = Register(key, name, Settings.VarType.Number)
        local opts = Settings.CreateSliderOptions(min, max, step)
        opts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v)
            return fmt:format(v)
        end)
        Settings.CreateSlider(category, setting, opts, tooltip)
    end

    Header("General")
    Checkbox("enabled", "Enable auto-fade", "Fade the HUD while you travel.")
    Slider("moveDelay", "Fade after moving for", 0, 10, 0.5, "%.1fs",
        "How long you must keep moving before the HUD starts to fade.")
    Slider("fadeOutTime", "Fade-out duration", 0.2, 6, 0.1, "%.1fs", "How slowly the HUD disappears.")
    Slider("fadeInTime", "Fade-in duration", 0, 2, 0.05, "%.2fs", "How quickly the HUD comes back.")
    Slider("holdTime", "Stay visible after a reveal", 0, 15, 0.5, "%.1fs",
        "After combat, a click or a target change, keep the HUD up at least this long.")
    Slider("hiddenAlpha", "Faded opacity", 0, 0.5, 0.05, "%.2f",
        "0 = fully invisible. Raise it to keep a faint ghost of the HUD.")

    Header("Bring the HUD back when...")
    Checkbox("revealCombat", "Entering combat")
    Checkbox("revealClick", "Clicking or targeting something",
        "Quick clicks only, so holding a mouse button to turn the camera won't trigger it.")
    Checkbox("revealTarget", "You have an attackable target")
    Checkbox("revealCasting", "Casting or channeling")
    Checkbox("revealMouseover", "Hovering over a hidden element")
    Checkbox("revealTyping", "Typing (chat, search boxes)")
    Checkbox("revealLowHealth", "Your health is low")
    Slider("lowHealthPct", "Low health threshold", 10, 90, 5, "%d%%")
    Checkbox("revealWhenStopped", "Standing still",
        "Off: the HUD stays hidden until combat/click. On: it returns after you stop for a moment.")
    Slider("stopDelay", "Standing still for", 0.5, 10, 0.5, "%.1fs")

    Header("Elements to fade")
    for _, g in ipairs(IHUD.GROUPS) do
        Checkbox("fade_" .. g.key, g.label)
    end

    Settings.RegisterAddOnCategory(category)
end

function ns.SetupOptions(IHUD)
    if Settings and Settings.RegisterVerticalLayoutCategory then
        local ok, err = pcall(BuildPanel, IHUD)
        if not ok then
            category = nil
            Print("options panel unavailable (" .. tostring(err) .. "). Use /ihud help.")
        end
    end

    SLASH_IMMERSIVEHUD1 = "/ihud"
    SLASH_IMMERSIVEHUD2 = "/immersivehud"
    SlashCmdList.IMMERSIVEHUD = ns.Safe("SlashCommand", function(msg)
        local db = IHUD.db
        local cmd, rest = (msg or ""):lower():match("^(%S*)%s*(.-)$")

        if cmd == "" then
            if category and Settings.OpenToCategory then
                Settings.OpenToCategory(category:GetID())
            else
                SlashCmdList.IMMERSIVEHUD("help")
            end
        elseif cmd == "on" or cmd == "off" then
            IHUD:SetEnabled(cmd == "on")
            Print("auto-fade " .. (db.enabled and "enabled" or "disabled"))
        elseif cmd == "pin" then
            Print(IHUD:ToggleForceShow() and "HUD pinned visible" or "auto-fade resumed")
        elseif cmd == "toggle" then
            local found
            for _, g in ipairs(IHUD.GROUPS) do
                if g.key:lower() == rest then
                    found = g
                    db["fade_" .. g.key] = not db["fade_" .. g.key]
                    IHUD:Refresh()
                    Print(g.label .. ": " .. (db["fade_" .. g.key] and "fades" or "always visible"))
                end
            end
            if not found then
                local keys = {}
                for _, g in ipairs(IHUD.GROUPS) do keys[#keys + 1] = g.key end
                Print("unknown element. Choose: " .. table.concat(keys, ", "))
            end
        elseif cmd == "status" then
            Print(IHUD:Status())
        elseif cmd == "errors" then
            local report = ns.ErrorReport()
            if report then ns.ShowCopyBox(report) else Print("no errors this session") end
        elseif cmd == "frames" then
            ns.ShowCopyBox(IHUD:FrameReport())
        elseif cmd == "reset" then
            wipe(db)
            for k, v in pairs(IHUD.DEFAULTS) do db[k] = v end
            IHUD:Refresh()
            Print("settings reset (/reload to refresh the panel)")
        else
            Print("/ihud - open options")
            Print("/ihud on | off - enable/disable auto-fade")
            Print("/ihud pin - keep HUD visible until you pin again")
            Print("/ihud toggle <element> - e.g. chat, minimap, questTracker")
            Print("/ihud status | reset")
            Print("/ihud errors - copyable error report")
            Print("/ihud frames - which HUD frames were found")
        end
    end)
end
