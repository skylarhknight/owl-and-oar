local gfx = playdate.graphics

TitleScene = {}
TitleScene.__index = TitleScene

function TitleScene.new(manager)
  local s = setmetatable({}, TitleScene)
  s.manager = manager
  s.bg = gfx.image.new("images/title")  -- loads images/title.png
  return s
end

function TitleScene:enter()
  -- nothing special on enter (we draw every frame)
end

function TitleScene:update()
  gfx.clear()
  if self.bg then
    self.bg:draw(0, 0)
  else
    gfx.drawTextAligned("Missing images/title.png", 200, 120, kTextAlignment.center)
  end
end

function TitleScene:AButtonDown()
  -- Go to the instruction scene when A is pressed
  self.manager:change(InstructionsScene.new(self.manager))
end
