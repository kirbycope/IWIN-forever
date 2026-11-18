-- Plain Lua tests for IWIN's macro builder. No game client needed:
--   luajit tests/run_tests.lua      (from the repository root)
-- Core.lua stops before touching the game when CreateFrame is missing, so only the pure builder loads.

local ns = {}
local function load(path)
	local chunk = assert(loadfile(path))
	chunk("IWIN", ns)
end
load("Rotations.lua")
load("Core.lua")

local passed, failed = 0, 0
local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then
		passed = passed + 1
	else
		failed = failed + 1
		print("FAIL " .. name .. "\n     " .. tostring(err))
	end
end
local function eq(a, b, msg)
	if a ~= b then error((msg or "") .. " expected [" .. tostring(b) .. "] got [" .. tostring(a) .. "]", 2) end
end
local function has(text, needle)
	if not text:find(needle, 1, true) then error("missing [" .. needle .. "] in:\n" .. text, 2) end
end
local function lacks(text, needle)
	if text:find(needle, 1, true) then error("unexpected [" .. needle .. "] in:\n" .. text, 2) end
end
local function set(list)
	local s = {}
	for _, n in ipairs(list) do s[n] = true end
	return s
end

-- Every spell a spec names, plus its signature: a level 60 character of that spec.
local function everything(spec)
	local s = {}
	for _, l in ipairs(spec.lines) do
		if l.cast then s[(l.cast:gsub("^!", ""))] = true end
		if l.seq then
			for _, n in ipairs(l.seq) do
				if type(n) == "table" then
					for _, alt in ipairs(n) do s[alt] = true end
				else
					s[n] = true
				end
			end
		end
	end
	for _, n in ipairs(spec.sig or {}) do s[n] = true end
	return s
end

local ALL_FORMS = { bear = 1, cat = 3, moonkin = 5 }
local CLASSES = { "WARRIOR", "ROGUE", "HUNTER", "MAGE", "PRIEST", "WARLOCK", "PALADIN", "SHAMAN", "DRUID" }

test("all nine classes have rotations", function()
	for _, c in ipairs(CLASSES) do assert(ns.ROTATIONS[c], c) end
end)

test("every class ends with a catch-all spec", function()
	for _, c in ipairs(CLASSES) do
		local specs = ns.ROTATIONS[c]
		eq(specs[#specs].sig, nil, c)
	end
end)

-- At level 60 with every spell known, every spec must fit the limit with nothing essential cut.
for _, c in ipairs(CLASSES) do
	for _, spec in ipairs(ns.ROTATIONS[c]) do
		test(c .. " " .. spec.spec .. " fits with every spell known", function()
			local r = assert(ns.BuildMacro(c, everything(spec), ALL_FORMS, { spec = spec.spec }))
			eq(r.spec, spec.spec)
			assert(#r.text <= ns.MAX_MACRO, #r.text .. " characters:\n" .. r.text)
			eq(#r.dropped, 0, "dropped " .. table.concat(r.dropped, " | "))
			assert(r.text ~= "", "empty macro")
			for line in (r.text .. "\n"):gmatch("(.-)\n") do
				assert(line:match("^/%a+"), "not a slash command: " .. line)
				lacks(line, "{")
				lacks(line, "  ")
			end
		end)
	end
end

test("spec is picked by a known signature spell", function()
	eq(ns.BuildMacro("WARRIOR", set({ "Heroic Strike", "Mortal Strike" })).spec, "Arms")
	eq(ns.BuildMacro("WARRIOR", set({ "Heroic Strike", "Bloodthirst" })).spec, "Fury")
	eq(ns.BuildMacro("WARRIOR", set({ "Heroic Strike", "Shield Slam" })).spec, "Protection")
	eq(ns.BuildMacro("WARRIOR", set({ "Heroic Strike" })).spec, "Leveling")
	eq(ns.BuildMacro("MAGE", set({ "Fireball", "Pyroblast" })).spec, "Fire")
	eq(ns.BuildMacro("PRIEST", set({ "Smite", "Mind Flay" })).spec, "Shadow")
end)

test("the talent tree with the most points picks the spec", function()
	-- The bug report: a level 15 Paladin with 6 points in Protection and no Protection spell yet got Holy.
	local paladin15 = set({ "Seal of Righteousness", "Judgement", "Holy Strike", "Seal of Fury" })
	eq(ns.BuildMacro("PALADIN", paladin15).spec, "Holy")
	eq(ns.BuildMacro("PALADIN", paladin15, {}, { tree = "Protection" }).spec, "Protection")
	eq(ns.BuildMacro("DRUID", set({ "Wrath" }), {}, { tree = "Feral Combat" }).spec, "Feral")
	eq(ns.BuildMacro("DRUID", set({ "Wrath" }), {}, { tree = "Balance" }).spec, "Balance")
	-- A tree with no entry of its own falls back to signature spells.
	eq(ns.BuildMacro("ROGUE", set({ "Sinister Strike" }), {}, { tree = "Assassination" }).spec, "Combat")
	-- A forced spec beats the tree.
	eq(ns.BuildMacro("PALADIN", paladin15, {}, { tree = "Protection", spec = "retribution" }).spec, "Retribution")
end)

test("level 15 Protection Paladin: Seal of Fury, Judgement three times, then Holy Strike", function()
	local known = set({ "Seal of Righteousness", "Judgement", "Holy Strike", "Seal of Fury", "Devotion Aura" })
	local r = ns.BuildMacro("PALADIN", known, {}, { tree = "Protection" })
	eq(r.text, "/startattack\n/castsequence reset=combat Seal of Fury, Judgement, Judgement, Judgement\n/cast Holy Strike")
end)

test("a seal alternative falls back when the first is not learned", function()
	local r = ns.BuildMacro("PALADIN", set({ "Seal of Righteousness", "Judgement" }), {}, { tree = "Protection" })
	has(r.text, "/castsequence reset=combat Seal of Righteousness, Judgement, Judgement, Judgement")
end)

test("a forced spec wins, any case", function()
	eq(ns.BuildMacro("WARRIOR", set({ "Heroic Strike", "Mortal Strike" }), {}, { spec = "fury" }).spec, "Fury")
	eq(ns.BuildMacro("WARRIOR", set({ "Heroic Strike" }), {}, { spec = "nonsense" }).spec, "Leveling")
end)

test("unknown spells are left out", function()
	local r = ns.BuildMacro("WARRIOR", set({ "Heroic Strike" }))
	eq(r.text, "/startattack\n/cast Heroic Strike")
end)

test("every class can cast something at level 1", function()
	local starters = { WARRIOR = "Heroic Strike", ROGUE = "Sinister Strike", HUNTER = "Raptor Strike",
		MAGE = "Fireball", PRIEST = "Smite", WARLOCK = "Shadow Bolt", PALADIN = "Seal of Righteousness",
		SHAMAN = "Lightning Bolt", DRUID = "Wrath" }
	for class, spell in pairs(starters) do
		local r = ns.BuildMacro(class, set({ spell }))
		has(r.text, spell)
	end
end)

test("a sequence left with one spell becomes a plain cast", function()
	local r = ns.BuildMacro("PRIEST", set({ "Smite" }))
	eq(r.text, "/stopmacro [channeling]\n/cast Smite")
end)

test("a sequence keeps only known spells, in order", function()
	local r = ns.BuildMacro("PRIEST", set({ "Smite", "Shadow Word: Pain" }))
	has(r.text, "/castsequence reset=target Shadow Word: Pain, Smite, Smite, Smite")
end)

test("a macro with nothing to cast is empty", function()
	eq(ns.BuildMacro("WARRIOR", {}).text, "")
	eq(ns.BuildMacro("HUNTER", {}).text, "")
end)

test("! is kept on the cast but not on the known check", function()
	local r = ns.BuildMacro("HUNTER", set({ "Auto Shot", "Raptor Strike" }))
	has(r.text, "/cast !Auto Shot")
end)

test("unknown class reports a reason", function()
	local r, err = ns.BuildMacro("DEMONHUNTER", {})
	eq(r, nil)
	has(err, "DEMONHUNTER")
end)

test("druid with no forms only gets caster lines", function()
	local r = ns.BuildMacro("DRUID", set({ "Wrath", "Moonfire", "Claw", "Maul" }), {})
	eq(r.text, "/castsequence [noform] reset=target Moonfire, Wrath, Wrath, Wrath")
end)

test("druid form tokens use this character's form indices", function()
	-- No aquatic form yet: cat is the second form.
	local r = ns.BuildMacro("DRUID", set({ "Wrath", "Claw", "Rake", "Maul" }), { bear = 1, cat = 2 })
	has(r.text, "/startattack [form:1/2]")
	has(r.text, "/castsequence [form:2] reset=target Rake, Claw, Claw, Claw")
	has(r.text, "/cast [form:1] Maul")
	has(r.text, "/cast [noform] Wrath")
end)

test("moonkin form counts as caster", function()
	local r = ns.BuildMacro("DRUID", set({ "Moonkin Form", "Moonfire", "Starfire" }), { bear = 1, cat = 3, moonkin = 5 })
	eq(r.spec, "Balance")
	has(r.text, "/castsequence [noform][form:5] reset=target Moonfire, Starfire, Starfire, Starfire")
end)

test("ResolveCond", function()
	eq(ns.ResolveCond(nil, {}), "")
	eq(ns.ResolveCond("[combat]", {}), "[combat]")
	eq(ns.ResolveCond("[{cat},stealth]", { cat = 3 }), "[form:3,stealth]")
	eq(ns.ResolveCond("[{cat}]", {}), nil)
	eq(ns.ResolveCond("[{feral}]", { cat = 2 }), "[form:2]")
	eq(ns.ResolveCond("[{caster}]", {}), "[noform]")
end)

test("auto-target adds a line and is cut first when over the limit", function()
	local r = ns.BuildMacro("WARRIOR", set({ "Heroic Strike" }), {}, { target = true })
	eq(r.text, "/targetenemy [noharm][dead]\n/startattack\n/cast Heroic Strike")
	-- The full Balance druid macro is near the limit, so the target line has to go.
	local balance = ns.ROTATIONS.DRUID[1]
	local full = ns.BuildMacro("DRUID", everything(balance), ALL_FORMS, { target = true })
	assert(#full.text <= ns.MAX_MACRO)
	lacks(full.text, "/targetenemy")
	eq(full.dropped[1], "/targetenemy [noharm][dead]")
end)

test("nothing cuttable left over the limit is an error, not a broken macro", function()
	local saved = ns.MAX_MACRO
	ns.MAX_MACRO = 20
	local r, err = ns.BuildMacro("WARRIOR", set({ "Heroic Strike", "Mortal Strike", "Execute" }))
	ns.MAX_MACRO = saved
	eq(r, nil)
	has(err, "over 20")
end)

test("off-GCD spells are marked so they never show as next", function()
	local r = ns.BuildMacro("WARRIOR", set({ "Heroic Strike", "Mortal Strike" }))
	for _, l in ipairs(r.lines) do
		if l.spell == "Heroic Strike" then assert(l.offgcd) end
		if l.spell == "Mortal Strike" then assert(not l.offgcd) end
	end
end)

-- Print every level 60 macro, for reading.
if os.getenv("IWIN_PRINT") then
	for _, c in ipairs(CLASSES) do
		for _, spec in ipairs(ns.ROTATIONS[c]) do
			local r = ns.BuildMacro(c, everything(spec), ALL_FORMS, { spec = spec.spec })
			print(("== %s %s (%d chars)\n%s\n"):format(c, spec.spec, #r.text, r.text))
		end
	end
end

print(("%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
