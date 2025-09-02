local gfx = playdate.graphics

GameplayScene = {}
GameplayScene.__index = GameplayScene

-- screen & layout
local SCREEN_W, SCREEN_H = 400, 240
local DOCK_X, DOCK_Y = 200, 70          -- player sprite center (you set these)
local WATER_X_MIN, WATER_X_MAX = 120, 360
local WATER_Y = 180

-- rod tip offset from player sprite center (where line starts)
local ROD_TIP_OFFSET_X, ROD_TIP_OFFSET_Y = 8, -20

----------------------------------------------------------------
-- Fish catalog (starter set) with basic fight traits
----------------------------------------------------------------
local FISH = {
  {name="Bass",          rarity="Common", size={10,18}, strength=0.20, pattern="steady"},
  {name="Carp",          rarity="Common", size={12,22}, strength=0.18, pattern="gentle"},
  {name="Minnow",        rarity="Common", size={2,4},   strength=0.08, pattern="calm"},
  {name="Catfish",       rarity="Medium", size={16,30}, strength=0.35, pattern="steady"},
  {name="Trout",         rarity="Medium", size={12,20}, strength=0.30, pattern="jerky"},
  {name="Salmon",        rarity="Medium", size={18,32}, strength=0.32, pattern="bursty"},
  {name="Golden Koi",    rarity="Rare",   size={14,26}, strength=0.45, pattern="rhythm"},
  {name="Ghost Fish",    rarity="Rare",   size={10,18}, strength=0.38, pattern="quick"},
  {name="Flying Fish",   rarity="Rare",   size={8,14},  strength=0.28, pattern="bursty"},
  {name="Boot Fish",     rarity="Common", size={8,8},   strength=0.10, pattern="calm"},
  {name="Can O' Worms",  rarity="Medium", size={4,6},   strength=0.22, pattern="jerky"},
  {name="Pixel Piranha", rarity="Rare",   size={6,9},   strength=0.50, pattern="spiky"},
  {name="Space Jelly",   rarity="Rare",   size={7,12},  strength=0.12, pattern="quick"},
  {name="Kraken Jr.",    rarity="Medium", size={5,10},  strength=0.40, pattern="bursty"},
}
local RARITY_WEIGHT = { Common = 0.60, Medium = 0.30, Rare = 0.10 }

-- utils
local function clamp(v, a, b) if v<a then return a elseif v>b then return b else return v end end
local function lerp(a,b,t) return a + (b-a)*t end
local function slugify(name)
  return (name:lower():gsub("[^%w]+","_"):gsub("^_+",""):gsub("_+$",""):gsub("_+","_"))
end

local function pickFish()
  local r = math.random()
  local chosen = (r <= RARITY_WEIGHT.Common) and "Common"
              or (r <= RARITY_WEIGHT.Common + RARITY_WEIGHT.Medium) and "Medium" or "Rare"
  local pool = {}
  for _, f in ipairs(FISH) do if f.rarity == chosen then table.insert(pool, f) end end
  local fish = pool[math.random(#pool)]
  local minS, maxS = fish.size[1], fish.size[2]
  local sz = math.random(minS, maxS)
  return {
    name     = fish.name,
    rarity   = fish.rarity,
    sizeIn   = sz,
    strength = fish.strength or 0.3,
    pattern  = fish.pattern  or "steady",
    iconSlug = slugify(fish.name),
  }
end

----------------------------------------------------------------
-- Full-screen sprite that draws the curved fishing line on top
----------------------------------------------------------------
local LineSprite = {}
LineSprite.__index = LineSprite
function LineSprite.new(scene)
  local sp = gfx.sprite.new()
  setmetatable(sp, LineSprite)
  sp.scene = scene

  -- Give the sprite a transparent 400x240 image so :draw() is called.
  local blank = gfx.image.new(SCREEN_W, SCREEN_H, gfx.kColorClear)
  sp:setImage(blank)

  -- Top-left anchored at (0,0) so our curve (which uses screen coords) lines up.
  sp:setCenter(0, 0)
  sp:moveTo(0, 0)

  sp:setZIndex(18)  -- between player (10) and bobber (20)
  sp:add()
  return sp
end


function LineSprite:draw()
  -- Delegate to the scene's curve renderer; this runs AFTER the background.
  if self.scene then self.scene:_drawCurvedLine() end
end

----------------------------------------------------------------
-- Scene
----------------------------------------------------------------
function GameplayScene.new(manager)
  local s = setmetatable({}, GameplayScene)
  s.manager = manager

  -- art
  s.bg = gfx.image.new("images/bg_day")

  s.playerImg = gfx.image.new("images/player")
  s.player = gfx.sprite.new(s.playerImg)
  s.player:moveTo(DOCK_X, DOCK_Y)
  s.player:setZIndex(10)
  s.player:add()

  s.bobberImg = gfx.image.new("images/bobber")
  s.bobber = nil
  s.bobberStartX, s.bobberStartY = nil, nil

  -- line sprite (drawn on top of background)
  s.lineSprite = LineSprite.new(s)

  -- state
  s.state = "idle"              -- idle | casting | waiting | hooking | reeling | catch_card
  s.power = 0                   -- 0..1
  s.lastCrankPos = playdate.getCrankPosition()
  s.biteTimer = nil
  s.hookWindowTimer = nil

  -- fish / reeling
  s.pendingFish = nil
  s.currentFish = nil
  s.fishDistance = 0            -- 1.0 -> 0.0 to land
  s.tension = 0

  -- line curve params
  s.lineStiffness = 0           -- 0=saggy, 1=taut
  s.lineSagBase = 24            -- base sag pixels
  s.fightOffsetX = 0            -- horizontal tug at curve midpoint

  -- UI
  s.statusText = nil
  s.catchInfo = nil
  s.catchCardTimer = nil

  -- icon cache
  s.iconCache = {}

  return s
end

-- background draw callback
local function drawBackground(img)
  gfx.clear()
  if img then img:draw(0, 0) end
end

function GameplayScene:enter()
  gfx.sprite.setBackgroundDrawingCallback(function(x, y, w, h)
    drawBackground(self.bg)
  end)
end
function GameplayScene:leave()
  gfx.sprite.setBackgroundDrawingCallback(nil)
end

----------------------------------------------------------------
-- Helpers
----------------------------------------------------------------
local function rodTipXY()
  return DOCK_X + ROD_TIP_OFFSET_X, DOCK_Y + ROD_TIP_OFFSET_Y
end

function GameplayScene:_spawnBobber(x, y)
  if self.bobber then self.bobber:remove(); self.bobber = nil end
  self.bobber = gfx.sprite.new(self.bobberImg)
  self.bobber:setZIndex(20)
  self.bobber:moveTo(x, y)
  self.bobber:add()
  self.bobberStartX, self.bobberStartY = x, y
end

function GameplayScene:_moveBobberTowardRod(t) -- t in [0..1], 0=start, 1=at rod
  if not self.bobber or not self.bobberStartX then return end
  local rx, ry = rodTipXY()
  local x = lerp(self.bobberStartX, rx, t)
  local y = lerp(self.bobberStartY, ry, t)
  self.bobber:moveTo(x, y)
end

function GameplayScene:_removeBobber()
  if self.bobber then self.bobber:remove(); self.bobber = nil end
  self.bobberStartX, self.bobberStartY = nil, nil
end

function GameplayScene:_clearTimers()
  if self.biteTimer then self.biteTimer:remove(); self.biteTimer = nil end
  if self.hookWindowTimer then self.hookWindowTimer:remove(); self.hookWindowTimer = nil end
end

function GameplayScene:_choosePendingFish()
  self.pendingFish = pickFish()
end

function GameplayScene:_startCasting()
  self.state = "casting"
  self.power = 0
  self.lastCrankPos = playdate.getCrankPosition()
end

function GameplayScene:_releaseCast()
  local p = clamp(self.power, 0, 1)
  local x = WATER_X_MIN + (WATER_X_MAX - WATER_X_MIN) * p
  local y = WATER_Y - math.floor(6 * p)
  self:_spawnBobber(x, y)

  self.lineStiffness = 0.0
  self.fightOffsetX = 0

  -- decide fish now; rarer fish usually mean a bit longer wait
  self:_choosePendingFish()
  local baseMs = math.random(1000, 6000) -- 1–6 s
  local rarityAdd = (self.pendingFish.rarity == "Rare" and 700)
                 or (self.pendingFish.rarity == "Medium" and 300) or 0
  local waitMs = baseMs + rarityAdd

  self.state = "waiting"
  self.biteTimer = playdate.timer.new(waitMs, function() self:_triggerBite() end)
end

function GameplayScene:_triggerBite()
  if self.state ~= "waiting" then return end
  self.state = "hooking"
  local window = math.random(500, 1000)
  if self.pendingFish.rarity == "Rare" then window = math.floor(window * 0.8) end
  if self.pendingFish.pattern == "quick" then window = math.floor(window * 0.8) end
  self.hookWindowTimer = playdate.timer.new(window, function()
    if self.state == "hooking" then self:_endCast("Missed the hook!") end
  end)
end

function GameplayScene:_hookFish()
  if self.state ~= "hooking" then return end
  self.currentFish = self.pendingFish or pickFish()
  self.pendingFish = nil
  self.fishDistance = 1.0
  self.tension = 0.0
  self.state = "reeling"
end

function GameplayScene:_snapLine()
  self:_endCast("Line snapped!")
end

function GameplayScene:_endCast(msg)
  self.state = "idle"
  self:_clearTimers()
  self.pendingFish = nil
  self.currentFish = nil
  self:_removeBobber()
  if msg then
    self.statusText = msg
    playdate.timer.new(1000, function() self.statusText = nil end)
  end
end

function GameplayScene:_finishCatch()
  self:_clearTimers()
  self:_removeBobber()
  self.catchInfo = self.currentFish or pickFish()
  self.currentFish = nil
  self.state = "catch_card"
  self.catchCardTimer = playdate.timer.new(1600, function()
    if self.state == "catch_card" then self:_closeCatchCard() end
  end)
end

function GameplayScene:_closeCatchCard()
  if self.catchCardTimer then self.catchCardTimer:remove(); self.catchCardTimer = nil end
  self.catchInfo = nil
  self.state = "idle"
end

----------------------------------------------------------------
-- Icon loader: prefers icons/, falls back to fish/, scales into 24×24
----------------------------------------------------------------
function GameplayScene:_getIconBySlug(slug, box)
  box = box or 24
  if not slug or slug == "" then return nil end
  local key = slug .. "#" .. tostring(box)
  if self.iconCache[key] ~= nil then return self.iconCache[key] end

  local candidates = {
    "images/fish/icons/" .. slug,  -- preferred tiny icon
    "images/fish/"       .. slug,  -- fallback big art
  }

  local img = nil
  for _, path in ipairs(candidates) do
    img = gfx.image.new(path)  -- tries .png
    if img then break end
  end

  if not img then
    img = gfx.image.new("images/fish/icons/default") or gfx.image.new("images/fish/default")
    if not img then
      print("Fish icon not found for slug: " .. slug)
      return nil
    end
  end

  -- scale to fit (never upscale)
  local iw, ih = img:getSize()
  local scale = math.min(box / iw, box / ih, 1)
  if scale < 1 and img.scaledImage then
    img = img:scaledImage(scale)
  end

  self.iconCache[key] = img
  return img
end

----------------------------------------------------------------
-- Input
----------------------------------------------------------------
function GameplayScene:AButtonDown()
  if self.state == "idle" then
    self:_startCasting()
  elseif self.state == "casting" then
    self:_releaseCast()
  elseif self.state == "catch_card" then
    self:_closeCatchCard()
  end
end

function GameplayScene:BButtonDown()
  if self.state == "hooking" then
    if self.hookWindowTimer then self.hookWindowTimer:remove(); self.hookWindowTimer = nil end
    self:_hookFish()
  elseif self.state == "waiting" then
    self:_endCast("Reeled back empty.")
  end
end

-- crank used for power (casting) and reeling (reeling)
function GameplayScene:cranked(change, acceleratedChange)
  if self.state == "casting" then
    local delta = math.abs(change) / 180    -- tune sensitivity
    self.power = clamp(self.power + delta, 0, 1)

  elseif self.state == "reeling" then
    local forward  = math.max(0,  change) / 90
    local backward = math.max(0, -change) / 90

    if math.random() < 0.08 then
      self.fightOffsetX = clamp(self.fightOffsetX + (math.random() - 0.5) * 8, -18, 18)
    else
      self.fightOffsetX = lerp(self.fightOffsetX, 0, 0.1)
    end

    self.fishDistance = clamp(self.fishDistance - forward * 0.03 + backward * 0.015, 0, 1)

    local accel = math.abs(acceleratedChange) / 720
    local fishStrength = (self.currentFish and self.currentFish.strength) or 0.3
    local pullFactor = (forward > 0) and (forward * fishStrength) or 0
    self.tension = clamp(self.tension + pullFactor * 0.25 + accel * 0.15 - 0.02 - backward * 0.10, 0, 1)

    if self.tension >= 1 then
      self:_snapLine(); return
    end
    if self.fishDistance <= 0 then
      self:_finishCatch(); return
    end
  end
end

----------------------------------------------------------------
-- Update / Draw
----------------------------------------------------------------
function GameplayScene:update()
  -- tighten line as tension rises
  if self.state == "waiting" or self.state == "hooking" or self.state == "reeling" then
    local desired = clamp(0.25 + self.tension * 0.75, 0, 1)
    self.lineStiffness = lerp(self.lineStiffness, desired, 0.07)
  end

  -- during reeling, move bobber toward rod based on fishDistance
  if self.state == "reeling" and self.bobber then
    self:_moveBobberTowardRod(1.0 - self.fishDistance)
  end

  -- HUD overlays (these are fine drawn here; they tend not to be erased)
  if self.state == "casting" then
    self:_drawPowerBar()
  end
  if self.state == "reeling" then
    self:_drawTensionAndDistance()
  end
  if self.statusText and self.state ~= "catch_card" then
    gfx.drawTextAligned(self.statusText, SCREEN_W/2, 12, kTextAlignment.center)
  end
  if self.state == "catch_card" and self.catchInfo then
    self:_drawCatchCard(self.catchInfo)
  end
end

function GameplayScene:_drawPowerBar()
  local w, h = 140, 10
  local x, y = SCREEN_W/2 - w/2, SCREEN_H - 24
  gfx.setColor(gfx.kColorWhite); gfx.fillRect(x-2, y-2, w+4, h+4)
  gfx.setColor(gfx.kColorBlack); gfx.drawRect(x-2, y-2, w+4, h+4)
  gfx.fillRect(x, y, math.floor(w * self.power), h)
  gfx.drawTextAligned("Power", x + w/2, y - 12, kTextAlignment.center)
end

-- quadratic Bézier curve for the line, with sag that stiffens
function GameplayScene:_drawCurvedLine()
  if not self.bobber then return end

  local function rodTipXY_local()
    return DOCK_X + ROD_TIP_OFFSET_X, DOCK_Y + ROD_TIP_OFFSET_Y
  end
  local x0, y0 = rodTipXY_local()
  local x2, y2 = self.bobber.x, self.bobber.y

  local dx, dy = (x2 - x0), (y2 - y0)
  local length = math.sqrt(dx*dx + dy*dy)
  local baseSag = clamp(self.lineSagBase + length * 0.08, 10, 42)
  local sag = baseSag * (1.0 - self.lineStiffness)

  -- control point at midpoint + down by sag + left/right tug
  local cx = (x0 + x2) * 0.5 + self.fightOffsetX
  local cy = (y0 + y2) * 0.5 + sag

  -- render curve as segments
  local steps = 18
  local prevx, prevy = x0, y0
  for i = 1, steps do
    local t = i / steps
    local mt = 1 - t
    local x = mt*mt*x0 + 2*mt*t*cx + t*t*x2
    local y = mt*mt*y0 + 2*mt*t*cy + t*t*y2
    gfx.drawLine(prevx, prevy, x, y)
    prevx, prevy = x, y
  end
end

function GameplayScene:_drawTensionAndDistance()
  local x, y = 8, 8
  gfx.drawText("Tension", x, y)
  gfx.drawRect(x, y+12, 80, 8)
  gfx.fillRect(x, y+12, math.floor(80 * self.tension), 8)

  gfx.drawText("Reel", x, y+28)
  gfx.drawRect(x, y+40, 80, 8)
  gfx.fillRect(x, y+40, math.floor(80 * (1.0 - self.fishDistance)), 8)
end

-- 120×80 centered catch card with icon + text
function GameplayScene:_drawCatchCard(info)
  local w, h = 120, 80
  local x = (SCREEN_W - w) // 2
  local y = (SCREEN_H - h) // 2

  gfx.setColor(gfx.kColorWhite); gfx.fillRect(x, y, w, h)
  gfx.setColor(gfx.kColorBlack); gfx.drawRect(x, y, w, h)

  local cx = x + w // 2
  gfx.drawTextAligned("Caught!", cx, y + 6, kTextAlignment.center)
  gfx.drawLine(x+8, y+20, x+w-8, y+20)

  -- icon (left) + text (right)
  local iconSize, iconX, iconY = 24, x + 10, y + 28
  local icon = self:_getIconBySlug(info.iconSlug, iconSize)

  gfx.setClipRect(iconX, iconY, iconSize, iconSize)
  if icon then
    local iw, ih = icon:getSize()
    local drawX = iconX + math.floor((iconSize - iw) / 2)
    local drawY = iconY + math.floor((iconSize - ih) / 2)
    icon:draw(drawX, drawY)
  end
  gfx.clearClipRect()
  gfx.drawRect(iconX, iconY, iconSize, iconSize)

  local tx = iconX + iconSize + 8
  gfx.drawTextAligned(info.name, tx + 40, y + 28, kTextAlignment.center)
  gfx.drawTextAligned("Rarity: " .. info.rarity, tx + 40, y + 42, kTextAlignment.center)
  gfx.drawTextAligned("Size: " .. tostring(info.sizeIn) .. " in", tx + 40, y + 56, kTextAlignment.center)

  gfx.drawTextAligned("A to close", cx, y + h + 6, kTextAlignment.center)
end
