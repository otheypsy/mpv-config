---@meta [exit]

-- Make the script exit at the end of the current event loop iteration. This does not terminate mpv itself or other scripts.
-- This can be polyfilled to support mpv versions older than 0.40 with:
function exit() end

return exit
