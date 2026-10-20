-- NIGHT OF THE BURIED MOON — curse presentation (StarterPlayerScripts.HalloweenClient.CurseFX). WP10a.
-- Reads the server attribute player.MoonCurse (0..100, Config.Curse.Thresholds) and presents it progressively — never a
-- jumpscare:
--   >= 55  Whisper : CurseWhisper loop (2D, volume grows with the curse) — occasional positional whispers from >= 70
--   >= 70  Vignette: four gradient edge frames (no images), deep purple -> blood at 100, slow breathing pulse
--   >= 85  Distort : camera ColorCorrection saturation/contrast pulse + a light Blur (no blur on Low), soft heartbeat >= 92
--   100    Max     : the CurseMax sting ONCE (re-armed below 90), a steady (non-pulsing) vignette, one hint toast / 90 s
-- ReducedMotion: no pulsing (steady values). Everything fades out as the curse decays outside the yard; event off = cleanup.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local M = {}
local C3 = Color3.fromRGB
local function kp(t, v)
	return NumberSequenceKeypoint.new(t, v)
end

function M.Start(ctx)
	local Shared, Audio, Bus = ctx.Shared, ctx.Audio, ctx.Bus
	if not Shared.Enabled() then
		return
	end
	local player = ctx.Player or Players.LocalPlayer
	local th = (ctx.Config.Curse and ctx.Config.Curse.Thresholds) or { Whisper = 55, Vignette = 70, Distort = 85, Max = 100 }
	local alive = true
	local shown = player:GetAttribute("MoonCurse") or 0
	local whisper = nil
	local armed = true
	local lastHint = -1e9
	local nextWhisper, nextBeat = 0, 0

	-- vignette (own ScreenGui under the HUD; edges only, the centre of the screen stays clear)
	local gui = Instance.new("ScreenGui")
	gui.Name = "DOGROTS_HalloweenCurse"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = -1
	gui.ScreenInsets = Enum.ScreenInsets.None
	gui.Enabled = false
	gui:SetAttribute("NoTranslate", true)
	gui.Parent = player:WaitForChild("PlayerGui")
	local edges = {}
	local function edge(name: string, pos: UDim2, size: UDim2, rotation: number)
		local f = Instance.new("Frame")
		f.Name = name
		f.BorderSizePixel = 0
		f.BackgroundColor3 = C3(26, 6, 36)
		f.Position = pos
		f.Size = size
		f.Parent = gui
		local g = Instance.new("UIGradient")
		g.Rotation = rotation
		g.Parent = f
		table.insert(edges, { Frame = f, Gradient = g })
	end
	edge("Top", UDim2.fromScale(0, 0), UDim2.fromScale(1, .26), 90)
	edge("Bottom", UDim2.fromScale(0, .74), UDim2.fromScale(1, .26), -90)
	edge("Left", UDim2.fromScale(0, 0), UDim2.fromScale(.2, 1), 0)
	edge("Right", UDim2.fromScale(.8, 0), UDim2.fromScale(.2, 1), 180)
	local lastAlpha, lastColor = -1, nil
	local function vignette(alpha: number, color: Color3)
		alpha = math.floor(alpha * 100 + .5) / 100
		if alpha == lastAlpha and color == lastColor then
			return
		end
		lastAlpha, lastColor = alpha, color
		gui.Enabled = alpha > .01
		if not gui.Enabled then
			return
		end
		-- gradient: opaque-ish at the screen edge (offset 0) -> clear inward
		local seq = NumberSequence.new({ kp(0, 1 - alpha), kp(.45, 1 - alpha * .45), kp(1, 1) })
		for _, e in ipairs(edges) do
			e.Gradient.Transparency = seq
			e.Frame.BackgroundColor3 = color
		end
	end

	-- distortion (camera effects; safe: nobody else drives them)
	local grade, blur = nil, nil
	local function camFX(strength: number, pulse: number)
		local cam = workspace.CurrentCamera
		if strength <= .005 then
			if grade then
				grade.Enabled = false
			end
			if blur then
				blur.Enabled = false
			end
			return
		end
		if not cam then
			return
		end
		if not grade then
			grade = Instance.new("ColorCorrectionEffect")
			grade.Name = "DOGROTS_HalloweenCurseGrade"
		end
		if grade.Parent ~= cam then
			grade.Parent = cam
		end
		grade.Enabled = true
		grade.Saturation = -(.1 + .12 * pulse) * strength
		grade.Contrast = (.05 + .06 * pulse) * strength
		grade.TintColor = Color3.new(1, 1, 1):Lerp(C3(236, 222, 255), strength * .6)
		if Shared.Low() then
			if blur then
				blur.Enabled = false
			end
		else
			if not blur then
				blur = Instance.new("BlurEffect")
				blur.Name = "DOGROTS_HalloweenCurseBlur"
			end
			if blur.Parent ~= cam then
				blur.Parent = cam
			end
			blur.Enabled = true
			blur.Size = math.floor((1 + 2 * pulse) * strength * 10 + .5) / 10
		end
	end

	local function cleanup()
		if not alive then
			return
		end
		alive = false
		if whisper then
			whisper:Stop(.6)
			whisper = nil
		end
		gui:Destroy()
		if grade then
			grade:Destroy()
		end
		if blur then
			blur:Destroy()
		end
	end
	M.Stop = cleanup

	local conn
	conn = RunService.Heartbeat:Connect(function(dt)
		if not alive then
			conn:Disconnect()
			return
		end
		local ok, err = pcall(function()
			if not Shared.Enabled() then
				cleanup()
				return
			end
			local target = math.clamp(player:GetAttribute("MoonCurse") or 0, 0, 100)
			shown += (target - shown) * (1 - math.exp(-dt / .5))
			if math.abs(target - shown) < .05 then
				shown = target
			end
			local c = shown
			local reduced = Shared.ReducedMotion()
			local t = os.clock()
			-- whispers
			if c >= th.Whisper or (whisper and c >= th.Whisper - 3) then
				local v = .35 + .65 * math.clamp((c - th.Whisper) / (100 - th.Whisper), 0, 1)
				if not whisper then
					whisper = Audio.Loop("CurseWhisper", nil, { Volume = 1 })
					whisper:SetVolume(0)
					whisper:SetVolume(v, 1.2)
					whisper.Shown = v
				elseif math.abs((whisper.Shown or 0) - v) > .04 then
					whisper.Shown = v
					whisper:SetVolume(v, .5)
				end
			elseif whisper then
				whisper:Stop(1.5)
				whisper = nil
			end
			if c >= th.Vignette and t >= nextWhisper then
				nextWhisper = t + 7 + math.random() * 8
				local cam = workspace.CurrentCamera
				if cam then
					local at = (cam.CFrame * CFrame.new(math.random() * 12 - 6, math.random() * 2, 7 + math.random() * 6)).Position
					Audio.Play("Whisper", at, { Volume = .5 + .4 * (c - th.Vignette) / (100 - th.Vignette) })
				end
			end
			-- vignette
			local vk = math.clamp((c - th.Vignette) / (th.Max - th.Vignette), 0, 1)
			local maxed = c >= th.Max - .25
			local breathe = (reduced or maxed) and .5 or (.5 + .5 * math.sin(t * math.pi * 2 * .25))
			local alpha = vk * (.5 + .1 * breathe)
			vignette(alpha, C3(26, 6, 36):Lerp(C3(60, 2, 14), math.clamp((c - 85) / 15, 0, 1)))
			-- distortion
			local dk = math.clamp((c - th.Distort) / (th.Max - th.Distort), 0, 1)
			local pulse = reduced and .5 or (.5 + .5 * math.sin(t * math.pi * 2 * .35))
			camFX(dk, pulse)
			if c >= 92 and t >= nextBeat then
				nextBeat = t + 1.35
				Audio.Play("Heartbeat", nil, { Volume = .22 + .1 * dk })
			end
			-- max: one sting, re-armed below 90
			if maxed and armed then
				armed = false
				Audio.Play("CurseMax", nil, { Volume = .8 })
				if t - lastHint > 90 then
					lastHint = t
					Bus.Fire("Toast", { Text = Shared.L("The curse has you! Dig, mine or fight to break it.",
						"Проклятие настигло тебя! Копай, добывай или сражайся, чтобы снять его."), Kind = "Curse", NoTranslate = true })
				end
			elseif c < 90 then
				armed = true
			end
		end)
		if not ok and not M.Warned then
			M.Warned = true
			warn("Halloween CurseFX failed: " .. tostring(err))
		end
	end)
end

return M
