local gfx = playdate.graphics

InstructionsScene = {}
InstructionsScene.__index = InstructionsScene

function InstructionsScene.new(manager)
  local s = setmetatable({}, InstructionsScene)
  s.manager = manager
  s.bg = gfx.image.new("images/instructions")
  return s
end

function InstructionsScene:enter()
  -- nothing for now
end

function InstructionsScene:update()
  gfx.clear()
  if self.bg then
    self.bg:draw(0, 0)
  else
    gfx.drawTextAligned("Missing images/instructions.png", 200, 120, kTextAlignment.center)
  end
  -- (Optional) tiny prompt:
  -- gfx.drawText("* press A to continue *", 120, 210)
end

function InstructionsScene:AButtonDown()
  -- For now, do nothing (or later: switch to your gameplay scene)
  -- self.manager:change(GameScene.new(self.manager))
end
