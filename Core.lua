-- IWIN: one button that casts the next spell in your rotation.
--
-- Blizzard's addon rules stop any addon from choosing a spell during combat: a secure button's
-- action can only be changed out of combat. So IWIN builds a priority macro from the spells this
-- character knows, out of combat, and hands it to a secure button; in combat the game itself walks
-- the macro and casts the first spell that works. When the client offers Blizzard's own
-- Single-Button Assistant (C_AssistedCombat), IWIN can use that instead (`/iwin mode`).

local addonName, ns = ...

ns.MAX_MACRO = 255 -- SecureActionButtonTemplate's macrotext limit

-------------------------------------------------------------------------------
-- Building the macro (pure: no game state, covered by tests/run_tests.lua)
-------------------------------------------------------------------------------

-- Replaces druid form tokens in a condition string. Returns nil when the line names a form this
-- character does not have, so the line is dropped.
function ns.ResolveCond(cond, forms)
	if not cond or cond == "" then return "" end
	local missing = false
	local out = cond:gsub("%[([^%]]*)%]", function(group)
		local groups = { group }
		if group:find("{caster}", 1, true) then
			groups[1] = (group:gsub("{caster}", "noform"))
			if forms.moonkin then groups[2] = (group:gsub("{caster}", "form:" .. forms.moonkin)) end
		end
		for i, g in ipairs(groups) do
			g = g:gsub("{(%a+)}", function(token)
				if token == "feral" then
					local list = {}
					if forms.bear then list[#list + 1] = forms.bear end
					if forms.cat then list[#list + 1] = forms.cat end
					if #list == 0 then missing = true return "" end
					return "form:" .. table.concat(list, "/")
				end
				if forms[token] then return "form:" .. forms[token] end
				missing = true
				return ""
			end)
			groups[i] = "[" .. g .. "]"
		end
		return table.concat(groups)
	end)
	if missing then return nil end
	return out
end

local function allSame(items)
	for i = 2, #items do
		if items[i] ~= items[1] then return false end
	end
	return true
end

local function byName(specs, name)
	if not name or name == "" then return nil end
	name = name:lower()
	for _, s in ipairs(specs) do
		local spec = s.spec:lower()
		-- "Feral Combat" is the Feral tree.
		if name == spec or name:sub(1, #spec + 1) == spec .. " " then return s end
	end
end

-- Picks the spec: the forced one, else the talent tree with the most points (`tree`), else the
-- first whose signature spell is known, else the class's catch-all.
function ns.PickSpec(specs, known, forced, tree)
	local s = byName(specs, forced) or byName(specs, tree)
	if s then return s end
	for _, s in ipairs(specs) do
		if not s.sig then return s end
		for _, name in ipairs(s.sig) do
			if known[name] then return s end
		end
	end
	return specs[#specs]
end

-- class: "WARRIOR" etc. known: set of spell names. forms: { bear = n, cat = n, moonkin = n }.
-- opts: { target = bool, spec = forced name or nil, tree = talent tree with most points or nil }.
-- Returns { spec, text, lines, dropped } or nil plus a reason.
function ns.BuildMacro(class, known, forms, opts)
	opts = opts or {}
	forms = forms or {}
	local specs = ns.ROTATIONS[class]
	if not specs then return nil, "no rotation for " .. tostring(class) end
	local spec = ns.PickSpec(specs, known, opts.spec, opts.tree)

	local lines = {}
	if opts.target then
		lines[#lines + 1] = { text = "/targetenemy [noharm][dead]", cut = 100 }
	end
	for _, e in ipairs(spec.lines) do
		local cond = ns.ResolveCond(e.cond, forms)
		if cond then
			local prefix = cond ~= "" and (cond .. " ") or ""
			local line
			if e.raw then
				line = { text = e.raw .. (cond ~= "" and (" " .. cond) or "") }
			elseif e.cast then
				local name = e.cast:gsub("^!", "")
				if known[name] then
					line = { text = "/cast " .. prefix .. e.cast, spell = name }
				end
			elseif e.seq then
				local items = {}
				for _, item in ipairs(e.seq) do
					-- A list of alternatives: the first one known.
					if type(item) == "table" then
						for _, alt in ipairs(item) do
							if known[alt] then item = alt break end
						end
					end
					if type(item) == "string" and known[item] then items[#items + 1] = item end
				end
				if #items > 0 and allSame(items) then
					line = { text = "/cast " .. prefix .. items[1], spell = items[1] }
				elseif #items > 1 then
					local args = (e.reset and ("reset=" .. e.reset .. " ") or "") .. table.concat(items, ", ")
					line = { text = "/castsequence " .. prefix .. args, seq = args, first = items[1] }
				end
			end
			if line then
				line.cond = cond
				line.cut = e.cut
				line.offgcd = e.offgcd
				lines[#lines + 1] = line
			end
		end
	end

	local function length()
		local n = #lines - 1
		for _, l in ipairs(lines) do n = n + #l.text end
		return n
	end
	local dropped = {}
	while length() > ns.MAX_MACRO do
		local worst, at
		for i, l in ipairs(lines) do
			if l.cut and (not worst or l.cut >= worst) then worst, at = l.cut, i end
		end
		if not at then return nil, "macro for " .. spec.spec .. " is over " .. ns.MAX_MACRO .. " characters" end
		dropped[#dropped + 1] = table.remove(lines, at).text
	end

	local texts = {}
	for i, l in ipairs(lines) do texts[i] = l.text end
	-- A macro of nothing but /startattack or /petattack casts nothing, so treat it as empty.
	local casts = false
	for _, l in ipairs(lines) do if l.spell or l.seq then casts = true end end
	return { spec = spec.spec, text = casts and table.concat(texts, "\n") or "", lines = lines, dropped = dropped }
end

-------------------------------------------------------------------------------
-- Everything below talks to the game. Skipped when loaded outside the client.
-------------------------------------------------------------------------------

if not CreateFrame then return end

local C_Spell, C_SpellBook, C_AssistedCombat = C_Spell, C_SpellBook, C_AssistedCombat
local GetSpellTexture = (C_Spell and C_Spell.GetSpellTexture) or GetSpellTexture
local IsSpellUsable = (C_Spell and C_Spell.IsSpellUsable) or IsUsableSpell
local QUESTION_MARK = 134400

local DEFAULTS = { locked = false, shown = true, mode = "auto", target = false, scale = 1, spec = nil,
	point = { "CENTER", "CENTER", 0, -180 } }
local db

local function say(msg) print("|cffff8000IWIN|r " .. msg) end

-- A value Blizzard hides from addons in combat; anything secret is treated as "unknown".
local function plain(v)
	if issecretvalue and issecretvalue(v) then return nil end
	return v
end

local function spellName(id)
	if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
	if C_Spell and C_Spell.GetSpellInfo then
		local info = C_Spell.GetSpellInfo(id)
		return info and info.name
	end
	return GetSpellInfo and (GetSpellInfo(id))
end

-- Every spell in the player's spellbook, by name.
local function ScanSpellbook()
	local known = {}
	if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines then
		local bank = Enum.SpellBookSpellBank.Player
		for i = 1, C_SpellBook.GetNumSpellBookSkillLines() do
			local line = C_SpellBook.GetSpellBookSkillLineInfo(i)
			if line and not line.offSpecID then
				for slot = line.itemIndexOffset + 1, line.itemIndexOffset + line.numSpellBookItems do
					local info = C_SpellBook.GetSpellBookItemInfo(slot, bank)
					if info and info.name and info.itemType == Enum.SpellBookItemType.Spell and not info.isOffSpec then
						known[info.name] = true
					end
				end
			end
		end
	else
		for i = 1, GetNumSpellTabs() do
			local _, _, offset, count = GetSpellTabInfo(i)
			for slot = offset + 1, offset + count do
				local kind = GetSpellBookItemInfo(slot, "spell")
				local name = GetSpellBookItemName(slot, "spell")
				if name and kind == "SPELL" then known[name] = true end
			end
		end
	end
	return known
end

local FORM_KEYS = { ["Bear Form"] = "bear", ["Dire Bear Form"] = "bear", ["Cat Form"] = "cat", ["Moonkin Form"] = "moonkin" }

-- The index of each druid form on this character's stance bar, which is what [form:n] counts.
local function ScanForms()
	local forms = {}
	for i = 1, (GetNumShapeshiftForms and GetNumShapeshiftForms() or 0) do
		local _, _, _, spellID = GetShapeshiftFormInfo(i)
		local key = spellID and FORM_KEYS[spellName(spellID) or ""]
		if key then forms[key] = i end
	end
	return forms
end

-- Forever (1.60.1) keeps its three talent trees as groups of one trait tree, each group with its own
-- spent points. Same reading as TipTacTalents' LibFroznFunctions. Returns the group with the most.
local function TraitTree()
	if not (C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_Traits and C_Traits.GetGroupDisplayInfoByTreeID) then
		return nil
	end
	local configID = C_ClassTalents.GetActiveConfigID()
	local config = configID and C_Traits.GetConfigInfo(configID)
	local treeID = config and config.treeIDs and config.treeIDs[1]
	local groups = treeID and C_Traits.GetGroupDisplayInfoByTreeID(treeID)
	if not groups then return nil end
	local treeFlags = Enum.TraitCurrencyFlag
		and { [Enum.TraitCurrencyFlag.UseClassIcon or -1] = true, [Enum.TraitCurrencyFlag.UseSpecIcon or -1] = true }
	local best, most = nil, 0
	for _, group in ipairs(groups) do
		local infos = C_Traits.GetGroupCurrencyInfo(configID, { group.groupID })
		local currency = infos and infos[1] and infos[1].currencyInfos and infos[1].currencyInfos[1]
		local spent = currency and plain(currency.spent)
		-- Only talent point currencies count, not anything else a group might spend.
		local isTalentPoints = true
		if treeFlags and currency and C_Traits.GetTraitCurrencyInfo then
			isTalentPoints = treeFlags[C_Traits.GetTraitCurrencyInfo(currency.traitCurrencyID)] or false
		end
		if isTalentPoints and type(spent) == "number" and spent > most
			and type(group.displayName) == "string" and group.displayName ~= "" then
			best, most = group.displayName, spent
		end
	end
	return best
end

-- The name of the talent tree with the most points spent, or nil with none spent.
local function TalentTree()
	local ok, tree = pcall(TraitTree)
	if ok and tree then return tree end
	if GetNumTalentTabs and GetTalentTabInfo then
		local best, most = nil, 0
		for i = 1, GetNumTalentTabs() do
			-- Classic returns name, icon, points; later clients id, name, description, icon, points.
			local r = { GetTalentTabInfo(i) }
			local name, points
			if type(r[1]) == "string" then name, points = r[1], r[3] else name, points = r[2], r[5] end
			points = plain(points)
			if type(name) == "string" and type(points) == "number" and points > most then
				best, most = name, points
			end
		end
		if best and best ~= UnitClass("player") then return best end
	end
	local getSpec = (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization) or GetSpecialization
	local getInfo = (C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo) or GetSpecializationInfo
	if getSpec and getInfo then
		local index = getSpec()
		if index and index > 0 then
			local _, name = getInfo(index)
			-- Forever has one specialization per class, named after the class: not a tree.
			if name ~= UnitClass("player") then return name end
		end
	end
end

-- Blizzard's Single-Button Assistant spell, when the client has it and it works for this character.
local function AssistantSpell()
	if not (C_AssistedCombat and C_AssistedCombat.GetActionSpell) then return nil end
	if C_AssistedCombat.IsAvailable and not C_AssistedCombat.IsAvailable() then return nil end
	return C_AssistedCombat.GetActionSpell()
end

-------------------------------------------------------------------------------
-- The button
-------------------------------------------------------------------------------

local button = CreateFrame("Button", "IWIN_Button", UIParent, "SecureActionButtonTemplate")
button:SetSize(48, 48)
button:SetFrameStrata("MEDIUM")
button:SetClampedToScreen(true)
button:SetMovable(true)
-- Both: the secure template acts on whichever one the ActionButtonUseKeyDown setting asks for,
-- which is also what makes /click and the key binding work.
button:RegisterForClicks("AnyDown", "AnyUp")
button:RegisterForDrag("LeftButton")

local icon = button:CreateTexture(nil, "ARTWORK")
icon:SetAllPoints()
icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
icon:SetTexture(QUESTION_MARK)
button.icon = icon
button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
button:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")

local label = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
label:SetPoint("TOP", button, "BOTTOM", 0, -2)
label:SetText("IWIN")

local pending = false
ns.current = nil
ns.usingAssistant = false

-- The spell the macro will most likely cast next, for the icon only. Mirrors what the game does:
-- the first line whose conditions hold and whose spell is usable, off cooldown and in range.
local function ready(name)
	local usable = plain(IsSpellUsable(name))
	if usable == false then return false end
	local duration
	if C_Spell and C_Spell.GetSpellCooldown then
		local cd = C_Spell.GetSpellCooldown(name)
		duration = cd and plain(cd.duration)
	elseif GetSpellCooldown then
		local _, d = GetSpellCooldown(name)
		duration = plain(d)
	end
	if duration and duration > 1.5 then return false end
	if UnitExists("target") then
		local inRange
		if C_Spell and C_Spell.IsSpellInRange then
			inRange = plain(C_Spell.IsSpellInRange(name, "target"))
		elseif IsSpellInRange then
			local r = plain(IsSpellInRange(name, "target"))
			if r ~= nil then inRange = r == 1 end
		end
		if inRange == false then return false end
	end
	return true
end

local function predict()
	if not ns.current then return nil end
	for _, l in ipairs(ns.current.lines) do
		if (l.spell or l.seq) and not l.offgcd then
			local holds = true
			if l.cond and l.cond ~= "" and SecureCmdOptionParse then
				holds = SecureCmdOptionParse(l.cond .. " x") ~= nil
			end
			if holds then
				local name = l.spell
				if l.seq then
					local ok, current = pcall(QueryCastSequence, l.seq)
					name = (ok and current) or l.first
				end
				if name and ready(name) then return name end
			end
		end
	end
end

function ns.UpdateIcon()
	local texture
	if ns.usingAssistant and C_AssistedCombat.GetNextCastSpell then
		local id = C_AssistedCombat.GetNextCastSpell(false)
		texture = id and GetSpellTexture(id)
	else
		local name = predict()
		texture = name and GetSpellTexture(name)
	end
	icon:SetTexture(texture or QUESTION_MARK)
	icon:SetDesaturated(not texture)
end

-- Rebuilds the macro and gives it to the secure button. Waits for the end of combat if needed.
function ns.Apply()
	if InCombatLockdown() then pending = true return end
	pending = false
	local _, class = UnitClass("player")
	ns.tree = TalentTree()
	local result, err = ns.BuildMacro(class, ScanSpellbook(), ScanForms(),
		{ target = db.target, spec = db.spec, tree = ns.tree })
	ns.current = result

	local assistant = db.mode ~= "macro" and AssistantSpell()
	if db.mode == "blizzard" and not assistant then
		say("Blizzard's Single-Button Assistant is not available here; using the macro.")
	end
	ns.usingAssistant = assistant and true or false
	if assistant then
		button:SetAttribute("type", "spell")
		button:SetAttribute("spell", assistant)
		button:SetAttribute("macrotext", nil)
	elseif result and result.text ~= "" then
		button:SetAttribute("type", "macro")
		button:SetAttribute("macrotext", result.text)
		button:SetAttribute("spell", nil)
	else
		button:SetAttribute("type", nil)
		if err then say(err) end
	end
	ns.UpdateIcon()
end

local function place()
	button:ClearAllPoints()
	local p = db.point
	button:SetPoint(p[1], UIParent, p[2], p[3], p[4])
	button:SetScale(db.scale)
end

button:SetScript("OnDragStart", function(self)
	if not db.locked and not InCombatLockdown() then self:StartMoving() end
end)
button:SetScript("OnDragStop", function(self)
	self:StopMovingOrSizing()
	local point, _, relative, x, y = self:GetPoint()
	db.point = { point, relative, x, y }
end)

-- The macro tries every line, so most presses leave "not ready yet" errors behind; clear them.
button:SetScript("PostClick", function()
	if UIErrorsFrame then UIErrorsFrame:Clear() end
end)

button:SetScript("OnEnter", function(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:AddLine("IWIN")
	if ns.usingAssistant then
		GameTooltip:AddLine("Using Blizzard's Single-Button Assistant", 1, 1, 1)
	elseif ns.current then
		GameTooltip:AddLine(ns.current.spec .. " priority:", 1, 1, 1)
		for _, l in ipairs(ns.current.lines) do GameTooltip:AddLine(l.text, 0.8, 0.8, 0.8) end
	end
	if not db.locked then GameTooltip:AddLine("Drag to move. /iwin lock to stop that.", 0.5, 0.5, 0.5) end
	GameTooltip:Show()
end)
button:SetScript("OnLeave", function() GameTooltip:Hide() end)

-------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------

local events = CreateFrame("Frame")
local REBUILD = { "SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB", "CHARACTER_POINTS_CHANGED",
	"PLAYER_TALENT_UPDATE", "UPDATE_SHAPESHIFT_FORMS", "ACTIVE_TALENT_GROUP_CHANGED",
	"PLAYER_SPECIALIZATION_CHANGED", "TRAIT_CONFIG_UPDATED" }
local REDRAW = { "SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_USABLE", "PLAYER_TARGET_CHANGED",
	"UPDATE_SHAPESHIFT_FORM", "ACTIONBAR_UPDATE_STATE", "UNIT_SPELLCAST_SUCCEEDED" }
local isRebuild, isRedraw = {}, {}

local function register(list, set)
	for _, e in ipairs(list) do
		-- Not every event exists on every client; an unknown one is skipped rather than fatal.
		if pcall(events.RegisterEvent, events, e) then set[e] = true end
	end
end

local redrawQueued = false
local function queueRedraw()
	if redrawQueued then return end
	redrawQueued = true
	C_Timer.After(0.05, function() redrawQueued = false ns.UpdateIcon() end)
end

events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 ~= addonName then return end
		IWIN_DB = IWIN_DB or {}
		for k, v in pairs(DEFAULTS) do
			if IWIN_DB[k] == nil then IWIN_DB[k] = v end
		end
		db = IWIN_DB
		events:UnregisterEvent("ADDON_LOADED")
	elseif event == "PLAYER_LOGIN" then
		place()
		button:SetShown(db.shown)
		register(REBUILD, isRebuild)
		register(REDRAW, isRedraw)
		ns.Apply()
	elseif event == "PLAYER_REGEN_ENABLED" then
		if pending then ns.Apply() else queueRedraw() end
	elseif isRebuild[event] then
		ns.Apply()
	elseif isRedraw[event] then
		queueRedraw()
	end
end)

-------------------------------------------------------------------------------
-- Slash command
-------------------------------------------------------------------------------

BINDING_HEADER_IWIN = "IWIN"
_G["BINDING_NAME_CLICK IWIN_Button:LeftButton"] = "Cast the next spell"

local HELP = {
	"/iwin - show the spec and macro in use",
	"/iwin lock | unlock - stop or allow dragging the button",
	"/iwin show | hide - the on-screen button (the key binding works either way)",
	"/iwin bar - put an IWIN macro on your cursor to drop on an action bar",
	"/iwin mode auto | macro | blizzard - auto uses Blizzard's assistant when it exists",
	"/iwin target - toggle picking the nearest enemy when you have none",
	"/iwin spec <name> | auto - force a spec's priority",
	"/iwin scale <0.5-2> | reset",
	"Key binding: Options, Keybindings, IWIN.",
}

local function outOfCombat()
	if InCombatLockdown() then say("Not in combat.") return false end
	return true
end

SLASH_IWIN1 = "/iwin"
SlashCmdList.IWIN = function(input)
	local cmd, rest = (input or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
	if cmd == "" then
		if ns.usingAssistant then
			say("Using Blizzard's Single-Button Assistant (/iwin mode macro for IWIN's own priority).")
		elseif ns.current and ns.current.text ~= "" then
			local why = db.spec and "forced with /iwin spec"
				or ns.tree and ("most talent points in " .. ns.tree)
				or "no talent points spent"
			say(ns.current.spec .. " priority (" .. why .. "):")
			for _, l in ipairs(ns.current.lines) do print("   " .. l.text) end
			for _, d in ipairs(ns.current.dropped) do print("   (left out to fit: " .. d .. ")") end
		else
			say("Nothing to cast yet. Learn a spell, then try again.")
		end
		say("/iwin help for commands.")
	elseif cmd == "help" then
		for _, line in ipairs(HELP) do print(line) end
	elseif cmd == "lock" or cmd == "unlock" then
		db.locked = cmd == "lock"
		say(db.locked and "Locked." or "Unlocked: drag the button to move it.")
	elseif cmd == "show" or cmd == "hide" then
		if outOfCombat() then
			db.shown = cmd == "show"
			button:SetShown(db.shown)
		end
	elseif cmd == "reset" then
		if outOfCombat() then
			db.point, db.scale = { "CENTER", "CENTER", 0, -180 }, 1
			place()
		end
	elseif cmd == "scale" then
		local s = tonumber(rest)
		if s and s >= 0.5 and s <= 2 and outOfCombat() then
			db.scale = s
			place()
		end
	elseif cmd == "mode" then
		if rest == "auto" or rest == "macro" or rest == "blizzard" then
			db.mode = rest
			say("Mode: " .. rest)
			ns.Apply()
		else
			say("Mode is " .. db.mode .. ". Use auto, macro or blizzard.")
		end
	elseif cmd == "target" then
		db.target = not db.target
		say("Auto-target " .. (db.target and "on." or "off."))
		ns.Apply()
	elseif cmd == "spec" then
		db.spec = (rest ~= "" and rest ~= "auto") and rest or nil
		ns.Apply()
		if ns.current then say("Spec: " .. ns.current.spec) end
	elseif cmd == "bar" then
		if not outOfCombat() then return end
		local index = GetMacroIndexByName("IWIN")
		if index == 0 then
			index = CreateMacro("IWIN", "INV_MISC_QUESTIONMARK", "/click IWIN_Button", true)
		end
		if index and index > 0 then
			PickupMacro(index)
			say("Drop the IWIN macro on an action bar.")
		else
			say("Could not make the macro: your character macro slots may be full.")
		end
	else
		for _, line in ipairs(HELP) do print(line) end
	end
end
