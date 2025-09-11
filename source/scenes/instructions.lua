local gfx = playdate.graphics
import "scenes/instructions2"

InstructionsScene = {}
InstructionsScene.__index = InstructionsScene

function InstructionsScene.new(manager)
  local s = setmetatable({}, InstructionsScene)
  s.manager = manager
  s.bg = gfx.image.new("images/instructions")
  return s
end

function InstructionsScene:update()
  gfx.clear(gfx.kColorBlack)
  if self.bg then self.bg:draw(0, 0) end
  -- gfx.drawTextAligned("Press A to continue", 200, 210, kTextAlignment.center)
end

function InstructionsScene:AButtonDown()
  self.manager:change(Instructions2Scene.new(self.manager))
end
