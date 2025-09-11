import "CoreLibs/graphics"
import "CoreLibs/sprites"
import "CoreLibs/timer"

import "scenes/title"
import "scenes/instructions"

local gfx = playdate.graphics

-- Simple scene manager
SceneManager = {
  current = nil
}

function SceneManager:change(scene)
  if self.current and self.current.leave then self.current:leave() end
  self.current = scene
  if self.current and self.current.enter then self.current:enter() end
end

-- Route the update loop to the current scene
function playdate.update()
  if SceneManager.current and SceneManager.current.update then
    SceneManager.current:update()
  end
  gfx.sprite.update()
  playdate.timer.updateTimers()
  SceneManager.current:update()
end

-- Route A button presses to the current scene
function playdate.AButtonDown()
  if SceneManager.current and SceneManager.current.AButtonDown then
    SceneManager.current:AButtonDown()
  end
end

-- Start on the Title scene
SceneManager:change(TitleScene.new(SceneManager))

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
