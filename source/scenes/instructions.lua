local gfx = playdate.graphics
import "scenes/gameplay"  -- add this line

InstructionsScene = {}
InstructionsScene.__index = InstructionsScene

function InstructionsScene.new(manager)
  local s = setmetatable({}, InstructionsScene)
  s.manager = manager
  s.bg = gfx.image.new("images/instructions")
  return s
end

function InstructionsScene:update()
  gfx.clear()
  if self.bg then self.bg:draw(0, 0) end
  -- (optional) prompt text
  -- gfx.drawTextAligned("Press A to start", 200, 210, kTextAlignment.center)
end

function InstructionsScene:AButtonDown()
  self.manager:change(GameplayScene.new(self.manager))
end
