-- IWIN rotation data.
--
-- Each class lists its specs in the order they are tried. The spec is the talent tree with the most
-- points, matched by name ("Feral Combat" matches "Feral"). With no points spent, or a tree that has
-- no entry here, a spec is picked when the player knows any spell in its `sig` list; the last spec
-- of each class has no `sig` and catches everyone else (low levels, healers playing solo).
--
-- A macro is tried top to bottom on every press, and the game stops at nothing: a line whose spell
-- is on cooldown, out of range, short on mana or otherwise unusable just fails and the next line is
-- tried. Only one global-cooldown spell can succeed per press, so the first one that works wins.
-- That is the whole "priority" mechanism, and it is all Blizzard's addon rules allow in combat.
--
-- Line kinds:
--   raw  = "/startattack"                      a slash command, kept as is
--   cast = "Execute"                           "/cast Execute", dropped when the spell is unknown
--   seq  = { "Serpent Sting", "Arcane Shot" }  "/castsequence reset=<reset> ...", unknown spells
--                                              removed; one spell left becomes a plain /cast. An
--                                              item may be a list of alternatives, first known wins:
--                                              { "Seal of Fury", "Seal of Righteousness" }
-- Options:
--   cond   = "[combat]"   macro conditions. Druid form tokens {cat} {bear} {feral} {caster} are
--                         replaced by the form's index on this character; a line naming a form the
--                         character lacks is dropped. {caster} also matches Moonkin Form.
--   reset  = "target"     castsequence reset clause
--   offgcd = true         not on the global cooldown (on-next-swing, cooldown buffs); never shown
--                         as the predicted next spell, because it never blocks the line after it
--   cut    = n            may be dropped to fit the 255 character macro limit, highest n first
--
-- Spell names are English. A sequence that repeats its filler is how a damage-over-time spell is
-- reapplied: the macro cannot see debuffs in combat, so it reapplies after a fixed number of casts.

local _, ns = ...

ns.ROTATIONS = {
	WARRIOR = {
		{ spec = "Arms", sig = { "Mortal Strike" }, lines = {
			{ raw = "/startattack" },
			{ cast = "Charge" },
			{ cast = "Bloodrage", cond = "[combat]", offgcd = true, cut = 1 },
			{ cast = "Execute" },
			{ cast = "Overpower" },
			{ cast = "Mortal Strike" },
			{ cast = "Whirlwind" },
			{ cast = "Heroic Strike", offgcd = true },
		} },
		{ spec = "Fury", sig = { "Bloodthirst" }, lines = {
			{ raw = "/startattack" },
			{ cast = "Charge" },
			{ cast = "Intercept", cut = 2 },
			{ cast = "Bloodrage", cond = "[combat]", offgcd = true, cut = 1 },
			{ cast = "Execute" },
			{ cast = "Bloodthirst" },
			{ cast = "Whirlwind" },
			{ cast = "Heroic Strike", offgcd = true },
		} },
		{ spec = "Protection", sig = { "Shield Slam" }, lines = {
			{ raw = "/startattack" },
			{ cast = "Bloodrage", cond = "[combat]", offgcd = true, cut = 1 },
			{ cast = "Revenge" },
			{ cast = "Shield Slam" },
			{ cast = "Heroic Strike", offgcd = true },
			{ cast = "Sunder Armor" },
		} },
		{ spec = "Leveling", lines = {
			{ raw = "/startattack" },
			{ cast = "Charge" },
			{ cast = "Bloodrage", cond = "[combat]", offgcd = true, cut = 1 },
			{ cast = "Execute" },
			{ cast = "Overpower" },
			{ cast = "Heroic Strike", offgcd = true },
		} },
	},

	ROGUE = {
		{ spec = "Subtlety", sig = { "Hemorrhage" }, lines = {
			{ raw = "/startattack" },
			{ cast = "Cheap Shot", cond = "[stealth]" },
			{ cast = "Riposte" },
			{ seq = { "Hemorrhage", "Hemorrhage", "Slice and Dice", "Hemorrhage", "Hemorrhage", "Hemorrhage", "Eviscerate" },
			  reset = "target/combat" },
		} },
		{ spec = "Combat", lines = {
			{ raw = "/startattack" },
			{ cast = "Cheap Shot", cond = "[stealth]" },
			{ cast = "Riposte" },
			{ seq = { "Sinister Strike", "Sinister Strike", "Slice and Dice", "Sinister Strike", "Sinister Strike", "Sinister Strike", "Eviscerate" },
			  reset = "target/combat" },
		} },
	},

	HUNTER = {
		{ spec = "Marksmanship", sig = { "Aimed Shot", "Trueshot Aura" }, lines = {
			{ raw = "/petattack" },
			{ cast = "Hunter's Mark", cond = "[nocombat]" },
			{ cast = "!Auto Shot", offgcd = true },
			{ cast = "Rapid Fire", offgcd = true, cut = 1 },
			{ cast = "Raptor Strike", offgcd = true },
			{ cast = "Mongoose Bite" },
			{ seq = { "Serpent Sting", "Aimed Shot", "Arcane Shot" }, reset = "target" },
			{ cast = "Arcane Shot" },
		} },
		{ spec = "Beast Mastery", lines = {
			{ raw = "/petattack" },
			{ cast = "Hunter's Mark", cond = "[nocombat]" },
			{ cast = "!Auto Shot", offgcd = true },
			{ cast = "Bestial Wrath", offgcd = true, cut = 2 },
			{ cast = "Rapid Fire", offgcd = true, cut = 1 },
			{ cast = "Raptor Strike", offgcd = true },
			{ cast = "Mongoose Bite" },
			{ seq = { "Serpent Sting", "Arcane Shot", "Arcane Shot" }, reset = "target" },
		} },
	},

	MAGE = {
		{ spec = "Fire", sig = { "Pyroblast", "Blast Wave", "Combustion" }, lines = {
			{ raw = "/stopmacro [channeling]" },
			{ cast = "Combustion", offgcd = true, cut = 1 },
			{ cast = "Pyroblast", cond = "[nocombat]" },
			{ cast = "Fire Blast" },
			{ cast = "Fireball" },
			{ cast = "!Shoot", cut = 2 },
		} },
		{ spec = "Arcane", sig = { "Arcane Power", "Presence of Mind" }, lines = {
			{ raw = "/stopmacro [channeling]" },
			{ cast = "Arcane Power", offgcd = true, cut = 1 },
			{ cast = "Fire Blast" },
			{ cast = "Arcane Missiles" },
			{ cast = "Frostbolt" },
			{ cast = "!Shoot", cut = 2 },
		} },
		{ spec = "Frost", lines = {
			{ raw = "/stopmacro [channeling]" },
			{ cast = "Ice Barrier", cut = 3 },
			{ cast = "Fire Blast" },
			{ cast = "Frostbolt" },
			{ cast = "Fireball" },
			{ cast = "!Shoot", cut = 2 },
		} },
	},

	PRIEST = {
		{ spec = "Shadow", sig = { "Mind Flay", "Shadowform" }, lines = {
			{ raw = "/stopmacro [channeling]" },
			{ cast = "Shadowform", cond = "[noform]", cut = 1 },
			{ cast = "Mind Blast" },
			{ seq = { "Shadow Word: Pain", "Mind Flay", "Mind Flay", "Mind Flay", "Mind Flay" }, reset = "target" },
			{ cast = "!Shoot", cut = 2 },
		} },
		{ spec = "Holy", lines = {
			{ raw = "/stopmacro [channeling]" },
			{ cast = "Holy Fire", cond = "[nocombat]" },
			{ cast = "Mind Blast" },
			{ seq = { "Shadow Word: Pain", "Smite", "Smite", "Smite" }, reset = "target" },
			{ cast = "!Shoot", cut = 2 },
		} },
	},

	WARLOCK = {
		{ spec = "Affliction", sig = { "Siphon Life", "Dark Pact", "Amplify Curse" }, lines = {
			{ raw = "/petattack" },
			{ raw = "/stopmacro [channeling]" },
			{ seq = { "Corruption", "Curse of Agony", "Siphon Life", "Shadow Bolt", "Shadow Bolt", "Shadow Bolt" }, reset = "target" },
			{ cast = "!Shoot", cut = 2 },
		} },
		{ spec = "Destruction", sig = { "Conflagrate", "Shadowburn" }, lines = {
			{ raw = "/petattack" },
			{ raw = "/stopmacro [channeling]" },
			{ cast = "Conflagrate" },
			{ seq = { "Immolate", "Curse of Agony", "Shadow Bolt", "Shadow Bolt", "Shadow Bolt" }, reset = "target" },
			{ cast = "!Shoot", cut = 2 },
		} },
		{ spec = "Demonology", lines = {
			{ raw = "/petattack" },
			{ raw = "/stopmacro [channeling]" },
			{ seq = { "Corruption", "Curse of Agony", "Immolate", "Shadow Bolt", "Shadow Bolt", "Shadow Bolt" }, reset = "target" },
			{ cast = "!Shoot", cut = 2 },
		} },
	},

	-- In Forever, Judgement no longer consumes the Seal (Blizzard's Paladin deep dive), and Holy Strike
	-- is baseline from level 6. So the Seal goes up once per fight and again after three Judgements,
	-- about the 30 seconds it lasts; while Judgement is on cooldown the sequence waits and the lines
	-- after it fire.
	PALADIN = {
		{ spec = "Protection", sig = { "Holy Shield", "Blessing of Sanctuary", "Templar's Bulwark", "Swift Judgement" }, lines = {
			{ raw = "/startattack" },
			{ seq = { { "Seal of Fury", "Seal of Righteousness" }, "Judgement", "Judgement", "Judgement" }, reset = "combat" },
			{ cast = "Holy Shield" },
			{ cast = "Holy Strike" },
			{ cast = "Consecration", cond = "[combat]" },
			{ cast = "Hammer of Wrath", cut = 1 },
		} },
		{ spec = "Retribution", sig = { "Seal of Command", "Repentance" }, lines = {
			{ raw = "/startattack" },
			{ seq = { { "Seal of Command", "Seal of Righteousness" }, "Judgement", "Judgement", "Judgement" }, reset = "combat" },
			{ cast = "Holy Strike" },
			{ cast = "Hammer of Wrath" },
			{ cast = "Exorcism", cut = 1 },
		} },
		{ spec = "Holy", lines = {
			{ raw = "/startattack" },
			{ cast = "Holy Shock" },
			{ seq = { "Seal of Righteousness", "Judgement", "Judgement", "Judgement" }, reset = "combat" },
			{ cast = "Holy Strike" },
			{ cast = "Hammer of Wrath" },
			{ cast = "Exorcism", cut = 1 },
		} },
	},

	SHAMAN = {
		{ spec = "Enhancement", sig = { "Stormstrike" }, lines = {
			{ raw = "/startattack" },
			{ cast = "Stormstrike" },
			{ seq = { "Flame Shock", "Earth Shock", "Earth Shock" }, reset = "target" },
		} },
		{ spec = "Elemental", sig = { "Elemental Mastery" }, lines = {
			{ cast = "Elemental Mastery", offgcd = true, cut = 1 },
			{ seq = { "Flame Shock", "Lightning Bolt", "Lightning Bolt", "Earth Shock", "Lightning Bolt" }, reset = "target" },
			{ cast = "Lightning Bolt" },
		} },
		{ spec = "Leveling", lines = {
			{ raw = "/startattack" },
			{ cast = "Lightning Bolt", cond = "[nocombat]" },
			{ seq = { "Flame Shock", "Earth Shock", "Earth Shock" }, reset = "target" },
		} },
	},

	DRUID = {
		{ spec = "Balance", sig = { "Moonkin Form" }, lines = {
			{ raw = "/startattack", cond = "[{feral}]" },
			{ cast = "Pounce", cond = "[{cat},stealth]" },
			{ seq = { "Rake", "Claw", "Claw", "Claw", "Ferocious Bite" }, cond = "[{cat}]", reset = "target" },
			{ cast = "Maul", cond = "[{bear}]", offgcd = true },
			{ seq = { "Moonfire", "Starfire", "Starfire", "Starfire" }, cond = "[{caster}]", reset = "target" },
		} },
		{ spec = "Feral", lines = {
			{ raw = "/startattack", cond = "[{feral}]" },
			{ cast = "Pounce", cond = "[{cat},stealth]" },
			{ seq = { "Rake", "Claw", "Claw", "Claw", "Ferocious Bite" }, cond = "[{cat}]", reset = "target" },
			{ cast = "Maul", cond = "[{bear}]", offgcd = true },
			{ seq = { "Moonfire", "Wrath", "Wrath", "Wrath" }, cond = "[{caster}]", reset = "target" },
		} },
	},
}
