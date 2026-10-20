--!nolint
-- Offline edit: the game's SoundGroup bus layout (docs/halloween2/DESIGN.md §16.1), built from
-- ReplicatedStorage.AudioMixer.Spec so the place and the runtime mixer can never disagree:
--   SoundService.DOGROTS_AUDIO (Folder)  Music (kept, .7; child "Halloween" = the procedural OST) · WorldEvents (kept, .7)
--                                        · Ambience .8 (new) · UI 1 (new)
--   SoundService.DOGROTS_SFX (Folder)    Pickaxe 1 (child "DOGROTS_MiningSFX", no makeup gain) · Boss 1 · SFX 1 · Cinema 1
-- Each bus that needs one gets exactly one CompressorSoundEffect (Pickaxe: GainMakeup 0). Existing groups keep their
-- Volume (the place's Music / WorldEvents levels are the designer's); a stray DOGROTS_MiningSFX at the SoundService root
-- is moved under Pickaxe. Idempotent: running it twice changes nothing.
return function(ctx)
	local game, sim, report = ctx.game, ctx.sim, ctx.report
	local RS = game:GetService("ReplicatedStorage")
	local SoundService = game:GetService("SoundService")
	local module = RS:FindFirstChild("AudioMixer")
	if not (module and module:IsA("ModuleScript")) then
		report.Skipped = "ReplicatedStorage.AudioMixer missing"
		return
	end
	local Mixer = sim:require(module)
	local result = Mixer.Ensure(SoundService, { KeepVolume = true })
	report.Created = result.Created
	report.NewGroups = result.Groups
	report.Moved = result.Moved

	-- summary of the resulting tree (and a sanity check of the contract the clients rely on)
	local tree = {}
	for _, folderName in ipairs(Mixer.Spec.Folders) do
		local folder = SoundService:FindFirstChild(folderName)
		assert(folder, "05_audio: " .. folderName .. " missing after Ensure")
		for _, g in ipairs(folder:GetChildren()) do
			if g:IsA("SoundGroup") then
				local entry = string.format("%s.%s %.2f", folderName, g.Name, g.Volume)
				for _, c in ipairs(g:GetChildren()) do
					if c.ClassName == "CompressorSoundEffect" then
						entry ..= string.format(" comp(%g dB, %g:1, +%g)", c.Threshold, c.Ratio, c.GainMakeup)
					elseif c:IsA("SoundGroup") then
						entry ..= " > " .. c.Name
					end
				end
				table.insert(tree, entry)
			end
		end
	end
	table.sort(tree)
	report.Tree = tree
	local pickaxe = SoundService.DOGROTS_SFX:FindFirstChild("Pickaxe")
	for _, d in ipairs(pickaxe:GetDescendants()) do
		if d.ClassName == "CompressorSoundEffect" then
			assert(d.GainMakeup <= 0, "05_audio: positive makeup gain on the pickaxe bus")
		end
	end
end
