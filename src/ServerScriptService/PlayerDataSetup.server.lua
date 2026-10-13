local runtime=require(script.Parent.Economy.Runtime)
runtime.Start()

-- The museum read API must be available even if another world service yields.
require(script.Parent.Economy.MuseumService).Start()

require(script.Parent.Economy.World).Start()
