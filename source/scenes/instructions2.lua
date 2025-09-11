local gfx = playdate.graphics
import "scenes/gameplay"

Instructions2Scene = {}
Instructions2Scene.__index = Instructions2Scene

function Instructions2Scene.new(manager)
  local s = setmetatable({}, Instructions2Scene)
  s.manager = manager
  s.bg = gfx.image.new("images/instructions2")
  return s
end

function Instructions2Scene:update()
  gfx.clear(gfx.kColorBlack)
  if self.bg then self.bg:draw(0, 0) end
  -- gfx.drawTextAligned("Press A to start", 200, 210, kTextAlignment.center)
end

-- NOTE: this must be Instructions2Scene, not InstructionsScene
function Instructions2Scene:AButtonDown()
  self.manager:change(GameplayScene.new(self.manager))
end
