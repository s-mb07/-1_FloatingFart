--!strict
--[[
	@class TrophyPadConfig
	Win pads (Workspace/_WORLD/MAP/Interactive/Lvl*/Pads). Each pad Part
	carries TagNames.WinPad, a number attribute `Stage` (picks its entry below)
	and a boolean attribute `Vip` (TagNames.Attr.X2) that marks a blue x2 pad.
	ADDING A PAD = a Part with the tag + Stage (+ Vip) in Studio, and one
	`Stages` entry here.

	Blue x2 pads pay X2Multiplier times more and are unlocked by the X2Wins
	gamepass (AccessGate). That pass does nothing else: it never multiplies
	any other win gain.

	A pad's `Stage` is the stage it OPENS ON: the pad tagged Stage = N sits at
	the end of the course shown as "STAGE N-1" on the walls, right before the
	"STAGE N" wall (and is claimable once checkpoint N is reached).

	Shared: TrophyPadService pays from it, WinPadController writes each pad's
	"+N Wins" label from it.
]]

local TrophyPadConfig = {
	--- Enter padding (studs): pads are thin plates the character stands ~3
	--- studs above (HRP height).
	Padding = 4.5,
	--- Trophies multiplier on a blue x2 pad (paid, see X2GamePass).
	X2Multiplier = 2,
	--- GamePassConfig key unlocking the blue x2 pads (see AccessGate).
	X2GamePass = "X2Wins",

	--- [pad Stage attribute] = trophies granted on the claim (x2 pad: x X2Multiplier).
	--- Hardcoded from the "+N Wins" texts authored on the pads in Studio.
	Stages = {
		[2] = { Trophies = 1 }, -- end of STAGE 1
		[3] = { Trophies = 1 }, -- end of STAGE 2
		[4] = { Trophies = 3 }, -- end of STAGE 3
		[5] = { Trophies = 5 }, -- end of STAGE 4
		[6] = { Trophies = 10 }, -- end of STAGE 5
		[7] = { Trophies = 20 }, -- end of STAGE 6
		[8] = { Trophies = 50 }, -- end of STAGE 7
		[9] = { Trophies = 100 }, -- end of STAGE 8
		[10] = { Trophies = 200 }, -- end of STAGE 9
		[11] = { Trophies = 400 }, -- end of STAGE 10
		[12] = { Trophies = 800 }, -- end of STAGE 11
	} :: { [number]: { Trophies: number } },
}

return TrophyPadConfig
