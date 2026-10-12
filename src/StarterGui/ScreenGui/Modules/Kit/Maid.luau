-- Cleanup bag (maid / janitor pattern). The implementation is shared with non-UI code and lives
-- in ReplicatedStorage.Perf.Maid: Give(connection | instance | function | thread | tween | object
-- with Destroy / Disconnect / Cancel), Connect(signal, fn), Set(key, item), Clean() / Destroy().
return require(game:GetService("ReplicatedStorage"):WaitForChild("Perf"):WaitForChild("Maid"))
