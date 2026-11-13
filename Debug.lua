-- Immersive HUD error catcher.
-- Wraps the add-on's handlers so an error is logged once (with stack trace)
-- instead of spamming every frame, and can be copied out with /ihud errors.

local ADDON_NAME, ns = ...

ns.errors = {}          -- this session's errors, deduplicated
local seen = {}
local disabled = {}     -- handlers turned off after repeated failures

local function Log(where, err)
    local key = where .. "|" .. tostring(err)
    local entry = seen[key]
    if entry then
        entry.count = entry.count + 1
        if entry.count >= 20 and not disabled[where] then
            disabled[where] = true
            print("|cffff5555Immersive HUD:|r '" .. where .. "' keeps failing and was paused. Type /ihud errors.")
        end
        return
    end
    entry = {
        where = where,
        err = tostring(err),
        stack = debugstack and debugstack(3, 12, 0) or "",
        build = select(4, GetBuildInfo()) .. " " .. (select(2, GetBuildInfo()) or ""),
        time = date and date("%H:%M:%S") or "",
        count = 1,
    }
    seen[key] = entry
    ns.errors[#ns.errors + 1] = entry
    print("|cffff5555Immersive HUD error|r in " .. where .. ": " .. tostring(err))
    print("|cffff5555Immersive HUD:|r type |cffffff00/ihud errors|r to copy the full report.")
end

-- Returns a wrapped version of fn that never throws.
function ns.Safe(where, fn)
    return function(...)
        if disabled[where] then return end
        local ok, err = xpcall(fn, function(e) return e end, ...)
        if not ok then Log(where, err) end
    end
end

function ns.ErrorReport()
    if #ns.errors == 0 then return nil end
    local lines = { "Immersive HUD error report", "Client: " .. ns.errors[1].build, "" }
    for i, e in ipairs(ns.errors) do
        lines[#lines + 1] = string.format("#%d [%s] %s (x%d)", i, e.time, e.where, e.count)
        lines[#lines + 1] = e.err
        lines[#lines + 1] = e.stack
        lines[#lines + 1] = ""
    end
    return table.concat(lines, "\n")
end

-- Simple copy window: Ctrl+A, Ctrl+C.
function ns.ShowCopyBox(text)
    local f = ns.copyFrame
    if not f then
        f = CreateFrame("Frame", "ImmersiveHUDCopyFrame", UIParent, "BackdropTemplate")
        f:SetSize(620, 380)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                        edgeSize = 14, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
        f:SetBackdropColor(0, 0, 0, 0.92)
        f:EnableMouse(true)
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)

        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOPLEFT", 12, -10)
        title:SetText("Immersive HUD - Ctrl+A then Ctrl+C to copy")

        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", 0, 0)

        local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 12, -32)
        scroll:SetPoint("BOTTOMRIGHT", -32, 12)

        local edit = CreateFrame("EditBox", nil, scroll)
        edit:SetMultiLine(true)
        edit:SetFontObject(ChatFontNormal)
        edit:SetWidth(570)
        edit:SetAutoFocus(false)
        edit:SetScript("OnEscapePressed", function() f:Hide() end)
        scroll:SetScrollChild(edit)

        f.edit = edit
        ns.copyFrame = f
    end
    f.edit:SetText(text)
    f:Show()
    f.edit:SetFocus()
    f.edit:HighlightText()
end

-- Always-available fallback, in case the add-on fails before /ihud is registered.
SLASH_IMMERSIVEHUDERR1 = "/ihuderr"
SlashCmdList.IMMERSIVEHUDERR = function()
    ns.ShowCopyBox(ns.ErrorReport() or "No Immersive HUD errors caught this session.")
end
