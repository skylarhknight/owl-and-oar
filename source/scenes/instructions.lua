local gfx = playdate.graphics

InstructionsScene = {}
InstructionsScene.__index = InstructionsScene

function InstructionsScene.new(manager)
  local s = setmetatable({}, InstructionsScene)
  s.manager = manager

  -- ordered pages of instruction images
  s.pages = {
    gfx.image.new("images/instructions"),   -- page 1
    gfx.image.new("images/instructions2"),  -- page 2
    gfx.image.new("images/instructions3"),  -- page 3 (add this file)
  }
  s.page = 1

  return s
end

function InstructionsScene:update()
  gfx.clear(gfx.kColorBlack)

  local img = self.pages[self.page]
  if img then
    img:draw(0, 0)
  end

  -- optional helper text overlay:
  -- gfx.drawTextAligned("Press A to continue", 200, 210, kTextAlignment.center)
end

function InstructionsScene:AButtonDown()
  if self.page < #self.pages then
    -- go to next instruction image
    self.page += 1
  else
    -- finished all pages → go to gameplay
    self.manager:change(GameplayScene.new(self.manager))
  end
end
