import "CoreLibs/graphics"
import "CoreLibs/sprites"
import "CoreLibs/timer"

import "scenes/title"
import "scenes/instructions"
import "scenes/gameplay"

local gfx = playdate.graphics

SceneManager = { current = nil }

function SceneManager:change(scene)
  if self.current and self.current.leave then self.current:leave() end
  self.current = scene
  if self.current and self.current.enter then self.current:enter() end
end

-- ONE update call, and draw HUD last
function playdate.update()
  gfx.sprite.update()            -- draw sprites first
  playdate.timer.updateTimers()  -- tick timers
  if SceneManager.current and SceneManager.current.update then
    SceneManager.current:update()  -- scene/UI last (on top)
  end
end

function playdate.AButtonDown()
  if SceneManager.current and SceneManager.current.AButtonDown then
    SceneManager.current:AButtonDown()
  end
end

function playdate.BButtonDown()
  if SceneManager.current and SceneManager.current.BButtonDown then
    SceneManager.current:BButtonDown()
  end
end

function playdate.cranked(change, acceleratedChange)
  if SceneManager.current and SceneManager.current.cranked then
    SceneManager.current:cranked(change, acceleratedChange)
  end
end

-- Start on Title
SceneManager:change(TitleScene.new(SceneManager))
