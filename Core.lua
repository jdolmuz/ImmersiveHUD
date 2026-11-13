-- Immersive HUD
-- Fades HUD elements out while you travel; brings them back for combat,
-- clicks, targets, casting, typing, and mouseover.
-- Only SetAlpha is used (never Show/Hide), so nothing here is a protected
-- action and it is safe to run in combat.

local ADDON_NAME, ns = ...
local IHUD = {}
ns.IHUD = IHUD
_G.ImmersiveHUD = IHUD

---------------------------------------------------------------------------
-- Element groups. Each can be toggled in the options.
-- Frame names cover both older and Midnight-era names; missing ones are skipped.
---------------------------------------------------------------------------
IHUD.GROUPS = {
    { key = "actionBars",  label = "Action bars",              default = true,
      frames = { "MainActionBar", "MainMenuBar", "MultiBarBottomLeft", "MultiBarBottomRight",
                 "MultiBarRight", "MultiBarLeft", "MultiBar5", "MultiBar6", "MultiBar7",
                 "StanceBar", "PetActionBar", "PossessActionBar" } },
    { key = "playerFrame", label = "Player & pet frames",       default = true,
      frames = { "PlayerFrame", "PetFrame" } },
    { key = "targetFrame", label = "Target & focus frames",     default = true,
      frames = { "TargetFrame", "FocusFrame" } },
    { key = "partyFrames", label = "Party & raid frames",       default = false,
      frames = { "PartyFrame", "CompactPartyFrame", "CompactRaidFrameContainer" } },
    { key = "buffs",       label = "Buffs & debuffs",           default = true,
      frames = { "BuffFrame", "DebuffFrame" } },
    { key = "cooldowns",   label = "Cooldown Manager",          default = true,
      frames = { "EssentialCooldownViewer", "UtilityCooldownViewer",
                 "BuffIconCooldownViewer", "BuffBarCooldownViewer" } },
    { key = "microMenu",   label = "Micro menu & bag bar",      default = true,
      frames = { "MicroMenuContainer", "BagsBar" } },
    { key = "statusBars",  label = "XP / reputation bars",      default = true,
      frames = { "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer" } },
    { key = "questTracker",label = "Quest / objective tracker", default = false,
      frames = { "ObjectiveTrackerFrame" } },
    { key = "chat",        label = "Chat",                      default = true,
      frames = function()
          local t = { "GeneralDockManager", "ChatFrameMenuButton", "ChatFrameChannelButton",
                      "ChatFrameToggleVoiceDeafenButton", "ChatFrameToggleVoiceMuteButton",
                      "QuickJoinToastButton" }
          for i = 1, (NUM_CHAT_WINDOWS or 10) do
              t[#t + 1] = "ChatFrame" .. i
              t[#t + 1] = "ChatFrame" .. i .. "Tab"
              t[#t + 1] = "ChatFrame" .. i .. "EditBox"
          end
          return t
      end },
    { key = "minimap",     label = "Minimap",                   default = false,
      frames = { "MinimapCluster" } },
}

---------------------------------------------------------------------------
-- Defaults
---------------------------------------------------------------------------
IHUD.DEFAULTS = {
    enabled           = true,
    hiddenAlpha       = 0,     -- 0..0.5, how faded "hidden" is
    fadeOutTime       = 2.0,   -- seconds, slow fade
    fadeInTime        = 0.25,  -- seconds, snappy return
    moveDelay         = 1.5,   -- seconds of moving before the fade starts
    holdTime          = 4.0,   -- seconds the HUD stays after any reveal

    revealCombat      = true,
    revealClick       = true,
    revealTarget      = true,  -- keep HUD while you have an attackable target
    revealCasting     = true,
    revealMouseover   = true,
    revealTyping      = true,
    revealLowHealth   = true,
    lowHealthPct      = 50,
    revealWhenStopped = false,
    stopDelay         = 2.0,
}
for _, g in ipairs(IHUD.GROUPS) do
    IHUD.DEFAULTS["fade_" .. g.key] = g.default
end

local db

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------
local factor       = 1      -- current visibility multiplier (1 = fully shown)
local targetFactor = 1
local moving       = false
local moveStart    = 0
local stopTime     = 0
local lastReveal   = 0
local casting      = false
local mouseDownAt  = nil
local forceShow    = false

local captured = {}  -- [frame] = base alpha captured before we started fading
local managed  = {}  -- list of frames currently under our control
local managedSet = {}

local GetTime = GetTime

---------------------------------------------------------------------------
-- Frame list
---------------------------------------------------------------------------
local function ResolveFrames(list)
    if type(list) == "function" then list = list() end
    return list
end

function IHUD:BuildFrameList()
    wipe(managed)
    local newSet = {}
    for _, g in ipairs(self.GROUPS) do
        if db["fade_" .. g.key] then
            for _, name in ipairs(ResolveFrames(g.frames)) do
                local f = _G[name]
                if f and type(f) == "table" and f.SetAlpha and not newSet[f]
                   and not (f.IsForbidden and f:IsForbidden()) then
                    newSet[f] = true
                    managed[#managed + 1] = f
                end
            end
        end
    end
    -- Anything we touched that is no longer managed gets its alpha back.
    for f, base in pairs(captured) do
        if not newSet[f] then
            f:SetAlpha(base)
            captured[f] = nil
        end
    end
    managedSet = newSet
end

local badFrames = {} -- [frame] = error text; frames that refuse SetAlpha are dropped

local function SafeSetAlpha(f, a)
    if badFrames[f] then return end
    local ok, err = pcall(f.SetAlpha, f, a)
    if not ok then
        badFrames[f] = tostring(err)
        captured[f] = nil
    end
end

local function ApplyAlpha()
    if factor >= 1 then
        for f, base in pairs(captured) do
            -- An edit box that got focus while hidden should come back fully opaque,
            -- not at the dimmed alpha it had when it was idle.
            if f.HasFocus and f:HasFocus() then base = 1 end
            SafeSetAlpha(f, base)
        end
        wipe(captured)
        return
    end
    for _, f in ipairs(managed) do
        if not badFrames[f] then
            local base = captured[f]
            if not base then
                local ok, a = pcall(f.GetAlpha, f)
                base = (ok and type(a) == "number" and not (issecretvalue and issecretvalue(a))) and a or 1
                captured[f] = base
            end
            SafeSetAlpha(f, base * factor)
        end
    end
end

---------------------------------------------------------------------------
-- Reveal conditions
---------------------------------------------------------------------------
local function PlayerHealthPct()
    local ok, pct = pcall(function()
        local h, m = UnitHealth("player"), UnitHealthMax("player")
        if issecretvalue and (issecretvalue(h) or issecretvalue(m)) then return nil end
        if not m or m == 0 then return nil end
        return (h / m) * 100
    end)
    return ok and pct or nil
end

local function MouseOverHUD()
    if IsMouselooking and IsMouselooking() then return false end
    for _, f in ipairs(managed) do
        if not badFrames[f] and f:IsVisible() then
            local ok, over = pcall(f.IsMouseOver, f)
            if ok and over == true then return true end
        end
    end
    return false
end

local function EditModeActive()
    local m = EditModeManagerFrame
    if not m then return false end
    if m.IsEditModeActive then return m:IsEditModeActive() end
    return m:IsShown()
end

function IHUD:ShouldReveal()
    if forceShow or EditModeActive() then return true end
    if db.revealCombat and (InCombatLockdown() or UnitAffectingCombat("player")) then return true end
    if db.revealCasting and casting then return true end
    if db.revealTyping and GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus() then return true end
    if db.revealTarget and UnitExists("target") and UnitCanAttack("player", "target")
       and not UnitIsDead("target") then return true end
    if db.revealLowHealth then
        local pct = PlayerHealthPct()
        if pct and pct <= db.lowHealthPct then return true end
    end
    if db.revealMouseover and factor < 1 and MouseOverHUD() then return true end
    return false
end

-- One-shot reveal (click, new target, etc.): shows the HUD and starts the hold timer.
function IHUD:Poke()
    if not db or not db.enabled then return end
    lastReveal = GetTime()
    targetFactor = 1
end

---------------------------------------------------------------------------
-- Movement
---------------------------------------------------------------------------
local function IsMovingNow()
    if UnitOnTaxi and UnitOnTaxi("player") then return true end
    if IsPlayerMoving and IsPlayerMoving() then return true end
    local ok, speed = pcall(GetUnitSpeed, "player")
    if ok and type(speed) == "number" and not (issecretvalue and issecretvalue(speed)) then
        return speed > 0
    end
    return false
end

local function UpdateMoving(now)
    local m = IsMovingNow()
    if m and not moving then
        moving, moveStart = true, now
    elseif not m and moving then
        moving, stopTime = false, now
    end
end

---------------------------------------------------------------------------
-- Main loop
---------------------------------------------------------------------------
local evalElapsed, rebuildElapsed, reapplyElapsed = 0, 0, 0

local function Evaluate(now)
    if not db.enabled then
        targetFactor = 1
        return
    end
    UpdateMoving(now)

    if IHUD:ShouldReveal() then
        lastReveal = now
        targetFactor = 1
    elseif moving and (now - moveStart) >= db.moveDelay and (now - lastReveal) >= db.holdTime then
        targetFactor = db.hiddenAlpha
    elseif not moving and db.revealWhenStopped and targetFactor < 1 and (now - stopTime) >= db.stopDelay then
        targetFactor = 1
    end
    -- otherwise keep the current target: stopping doesn't bring the HUD back
end

local driver = CreateFrame("Frame")
driver:SetScript("OnUpdate", ns.Safe("OnUpdate", function(_, elapsed)
    if not db then return end
    local now = GetTime()

    evalElapsed = evalElapsed + elapsed
    if evalElapsed >= 0.1 then
        evalElapsed = 0
        Evaluate(now)
    end

    rebuildElapsed = rebuildElapsed + elapsed
    if rebuildElapsed >= 5 then   -- pick up frames created late (load-on-demand UI)
        rebuildElapsed = 0
        IHUD:BuildFrameList()
    end

    if factor ~= targetFactor then
        local lo = math.min(db.hiddenAlpha, 0.999)
        local span = 1 - lo
        if targetFactor > factor then
            local rate = span / math.max(db.fadeInTime, 0.01)
            factor = math.min(targetFactor, factor + rate * elapsed)
        else
            local rate = span / math.max(db.fadeOutTime, 0.01)
            factor = math.max(targetFactor, factor - rate * elapsed)
        end
        ApplyAlpha()
    elseif factor < 1 then
        -- Blizzard code sometimes resets alpha (new target, bar paging); re-assert it.
        reapplyElapsed = reapplyElapsed + elapsed
        if reapplyElapsed >= 0.25 then
            reapplyElapsed = 0
            ApplyAlpha()
        end
    end
end))

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
pcall(ev.RegisterEvent, ev, "ADDON_LOADED")
pcall(ev.RegisterEvent, ev, "PLAYER_LOGIN")
pcall(ev.RegisterEvent, ev, "PLAYER_REGEN_DISABLED")
pcall(ev.RegisterEvent, ev, "PLAYER_TARGET_CHANGED")
pcall(ev.RegisterEvent, ev, "GLOBAL_MOUSE_DOWN")
pcall(ev.RegisterEvent, ev, "GLOBAL_MOUSE_UP")
pcall(ev.RegisterEvent, ev, "LOOT_OPENED")
pcall(ev.RegisterEvent, ev, "GOSSIP_SHOW")
pcall(ev.RegisterEvent, ev, "MERCHANT_SHOW")
pcall(ev.RegisterEvent, ev, "QUEST_DETAIL")
pcall(ev.RegisterUnitEvent, ev, "UNIT_SPELLCAST_START", "player")
pcall(ev.RegisterUnitEvent, ev, "UNIT_SPELLCAST_STOP", "player")
pcall(ev.RegisterUnitEvent, ev, "UNIT_SPELLCAST_FAILED", "player")
pcall(ev.RegisterUnitEvent, ev, "UNIT_SPELLCAST_INTERRUPTED", "player")
pcall(ev.RegisterUnitEvent, ev, "UNIT_SPELLCAST_CHANNEL_START", "player")
pcall(ev.RegisterUnitEvent, ev, "UNIT_SPELLCAST_CHANNEL_STOP", "player")
pcall(ev.RegisterUnitEvent, ev, "UNIT_SPELLCAST_EMPOWER_START", "player")
pcall(ev.RegisterUnitEvent, ev, "UNIT_SPELLCAST_EMPOWER_STOP", "player")

local CLICK_MAX = 0.3 -- a press held longer than this is a camera drag, not a click

ev:SetScript("OnEvent", ns.Safe("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        ImmersiveHUDDB = ImmersiveHUDDB or {}
        db = ImmersiveHUDDB
        for k, v in pairs(IHUD.DEFAULTS) do
            if db[k] == nil then db[k] = v end
        end
        IHUD.db = db
        if ns.SetupOptions then ns.Safe("SetupOptions", ns.SetupOptions)(IHUD) end
        return
    end
    if not db then return end

    if event == "PLAYER_LOGIN" then
        IHUD:BuildFrameList()
        IHUD:Poke()
    elseif event == "GLOBAL_MOUSE_DOWN" then
        mouseDownAt = GetTime()
    elseif event == "GLOBAL_MOUSE_UP" then
        if db.revealClick and mouseDownAt and (GetTime() - mouseDownAt) <= CLICK_MAX then
            IHUD:Poke()
        end
        mouseDownAt = nil
    elseif event == "PLAYER_TARGET_CHANGED" then
        if db.revealClick and UnitExists("target") then IHUD:Poke() end
    elseif event == "PLAYER_REGEN_DISABLED" then
        if db.revealCombat then IHUD:Poke() end
    elseif event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START"
        or event == "UNIT_SPELLCAST_EMPOWER_START" then
        casting = true
    elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_FAILED"
        or event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_CHANNEL_STOP"
        or event == "UNIT_SPELLCAST_EMPOWER_STOP" then
        casting = false
    else
        -- interacting with the world (loot, NPCs, quests)
        IHUD:Poke()
    end
end))

---------------------------------------------------------------------------
-- Public helpers
---------------------------------------------------------------------------
function IHUD:Refresh()
    self:BuildFrameList()
    if not db.enabled then
        targetFactor = 1
    end
    if factor < 1 then ApplyAlpha() end
end

function IHUD:SetEnabled(on)
    db.enabled = on and true or false
    self:Refresh()
end

function IHUD:ToggleForceShow()
    forceShow = not forceShow
    if not forceShow then lastReveal = GetTime() end
    return forceShow
end

function IHUD:FrameReport()
    local out = { "Immersive HUD frame report", "" }
    for _, g in ipairs(self.GROUPS) do
        out[#out + 1] = string.format("[%s] %s", db["fade_" .. g.key] and "fade" or "keep", g.label)
        for _, name in ipairs(ResolveFrames(g.frames)) do
            local f = _G[name]
            local state
            if not f then state = "not found"
            elseif badFrames[f] then state = "ERROR: " .. badFrames[f]
            elseif managedSet[f] then state = string.format("managed (alpha %.2f)", f:GetAlpha() or -1)
            else state = "found, not managed" end
            out[#out + 1] = "   " .. name .. ": " .. state
        end
    end
    return table.concat(out, "\n")
end

function IHUD:Status()
    return string.format("enabled=%s  visibility=%.2f  moving=%s  frames=%d",
        tostring(db.enabled), factor, tostring(moving), #managed)
end

-- Key binding hooks (Bindings.xml)
function ImmersiveHUD_TogglePeek()
    local on = IHUD:ToggleForceShow()
    UIErrorsFrame:AddMessage(on and "Immersive HUD: HUD pinned" or "Immersive HUD: auto-fade resumed", 1, 0.82, 0)
end

function ImmersiveHUD_ToggleEnabled()
    IHUD:SetEnabled(not db.enabled)
    UIErrorsFrame:AddMessage("Immersive HUD " .. (db.enabled and "enabled" or "disabled"), 1, 0.82, 0)
end
