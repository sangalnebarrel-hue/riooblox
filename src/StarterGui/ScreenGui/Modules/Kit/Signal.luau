-- Minimal signal for kit components (no BindableEvent, handlers run in their own thread).
-- The implementation is shared with non-UI code and lives in ReplicatedStorage.Perf.Signal:
-- Signal.new(), :Connect(fn), :Once(fn), :Fire(...), :DisconnectAll() / :Destroy().
return require(game:GetService("ReplicatedStorage"):WaitForChild("Perf"):WaitForChild("Signal"))
