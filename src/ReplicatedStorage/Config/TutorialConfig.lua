--!strict
--[[
	@module TutorialConfig
	@description New-player tutorial. Shared: TutorialService advances the
	stages from real game events, TutorialController shows the guide text and
	the guide beam, RebirthFocusController reads the "done" stage.

	THE STAGES (server-enforced, see TutorialService) -- once per player, saved:
	  1. Step on a treadmill                  (treadmill entered)
	  2. Train to level TargetLevel           (traversal level >= TargetLevel)
	  3. Finish the obby and get 1 win        (any win pad claimed)
	  4. Stand on the first length upgrade    (owns skin UpgradeSkinId)
	  5. Closing message, shown FinalSeconds  (then finished)
	Stage #Stages + 1 = finished: nothing is shown anymore.

	`Target` = where the guide beam leads: a CollectionService tag, and
	optionally the attribute values (TagNames.Attr) a tagged part must have.
]]

local TagNames = require(script.Parent.AssetIds.TagNames)

export type Target = {
	Tag: string,
	Attributes: { [string]: any }?,
}

export type Stage = {
	--- Guide text. "%d" is replaced by the stage progress where shown.
	Text: string,
	Target: Target?,
}

local TutorialConfig = {
	TargetLevel = 3,
	UpgradeSkinId = "2",
	FinalSeconds = 6,

	--- How often (Hz) the client re-targets the guide beam (Assets/VFX/Tutorial).
	RefreshHz = 6,

	Stages = {
		{
			Text = "Step on a treadmill to train!",
			Target = { Tag = TagNames.Treadmill, Attributes = { [TagNames.Attr.Id] = "1" } },
		},
		{ Text = "Reach level 3 (%d/3)" },
		{
			Text = "Finish the obby: get 1 win! (%d/1)",
			-- The win pad of stage 1 (not the checkpoint hitbox).
			Target = {
				Tag = TagNames.WinPad,
				Attributes = { [TagNames.Attr.Stage] = 2, [TagNames.Attr.X2] = false },
			},
		},
		{
			Text = "Unlock your first length upgrade!",
			Target = { Tag = TagNames.SkinPad, Attributes = { [TagNames.Attr.Id] = "2" } },
		},
		{ Text = "Tutorial done, the sky is yours!" },
	} :: { Stage },
}

--- Stage value once the whole tutorial is done.
function TutorialConfig.GetFinishedStage(): number
	return #TutorialConfig.Stages + 1
end

return TutorialConfig
