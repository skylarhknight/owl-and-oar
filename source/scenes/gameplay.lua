-- gameplay.lua
import "CoreLibs/graphics"
import "CoreLibs/sprites"
import "CoreLibs/timer"

local gfx = playdate.graphics

GameplayScene = {}
GameplayScene.__index = GameplayScene

-- screen & layout
local SCREEN_W, SCREEN_H = 400, 240
local DOCK_X, DOCK_Y = 100, 137
local OWL_X, OWL_Y = 189, 110
-- 165, 120 for first poll

-- optional fonts (auto-fallback to system font)
local FONT_TITLE = gfx.font.new("fonts/title")
local FONT_BODY  = gfx.font.new("fonts/body")
local function withFont(font, fn)
  local prev = gfx.getFont()
  if font then gfx.setFont(font) end
  fn()
  gfx.setFont(prev)
end

----------------------------------------------------------------
-- Fish catalog with short descriptions
----------------------------------------------------------------
local FISH = {
  {name="Bass",          rarity="Common", size={10,18}, strength=0.20, pattern="steady", desc="Reliable river resident with a taste for shiny lures."},
  {name="Carp",          rarity="Common", size={12,22}, strength=0.30, pattern="gentle", desc="Bottom-feeder philosopher. Slow, steady, contemplative."},
  {name="Minnow",        rarity="Common", size={2,4},   strength=0.10, pattern="calm",   desc="Tiny but spirited. Blink and you’ll miss it."},
  {name="Catfish",       rarity="Medium", size={16,30}, strength=0.55, pattern="steady", desc="Whiskered bulldozer. Likes mud, dislikes losing."},
  {name="Trout",         rarity="Medium", size={12,20}, strength=0.45, pattern="jerky",  desc="Stream acrobat. Slippery, jumpy, proud of it."},
  {name="Salmon",        rarity="Medium", size={18,32}, strength=0.50, pattern="bursty", desc="Migratory muscle. Built for upstream brawls."},
  {name="Golden Koi",    rarity="Rare",   size={14,26}, strength=0.90, pattern="rhythm", desc="Regal glitter fish. Prefers tranquil water and applause."},
  {name="Ghost Fish",    rarity="Rare",   size={10,18}, strength=0.65, pattern="quick",  desc="You didn’t see it… but it saw you."},
  {name="Flying Fish",   rarity="Rare",   size={8,14},  strength=0.40, pattern="bursty", desc="Part fish, part rumor. Catches air and attitudes."},
  {name="Boot Fish",     rarity="Common", size={8,8},   strength=0.15, pattern="calm",   desc="Just a soggy boot pretending to be a fish. Still counts!"},
  {name="Can O' Worms",  rarity="Medium", size={4,6},   strength=0.35, pattern="jerky",  desc="It opened itself. That’s the problem."},
  {name="Pixel Piranha", rarity="Rare",   size={6,9},   strength=1.00, pattern="spiky",  desc="Glitched teeth with a byte. Handle carefully."},
  {name="Space Jelly",   rarity="Rare",   size={7,12},  strength=0.25, pattern="quick",  desc="Soft, glowy, and probably extraterrestrial."},
  {name="Kraken Jr.",    rarity="Medium", size={5,10},  strength=0.70, pattern="bursty", desc="Tiny tentacles, big ego. Claims royalty."},
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
    name      = fish.name,
    rarity    = fish.rarity,
    sizeIn    = sz,
    strength  = fish.strength or 0.5,
    pattern   = fish.pattern  or "steady",
    desc      = fish.desc     or "One for the bucket.",
    iconSlug  = slugify(fish.name),
  }
end

----------------------------------------------------------------
-- Scene
----------------------------------------------------------------
function GameplayScene.new(manager)
  local s = setmetatable({}, GameplayScene)
  s.manager = manager

  -- background
  s.bg = gfx.image.new("images/bg_day")

  -- player poses (fallbacks to images/player.png)
  s.poseImgs = {
    neutral = gfx.image.new("images/player_neutral") or gfx.image.new("images/player"),
    cast    = gfx.image.new("images/player_cast")    or gfx.image.new("images/player"),
    fish    = gfx.image.new("images/player_fish")    or gfx.image.new("images/player"),
    reel    = gfx.image.new("images/player_reel")    or gfx.image.new("images/player"),
  }

  s.player = gfx.sprite.new(s.poseImgs.neutral or gfx.image.new("images/player"))
  s.player:moveTo(DOCK_X, DOCK_Y)
  s.player:setZIndex(10)
  s.player:add()

  -- OWL (neutral/alert)
  s.owlImgs = {
    neutral = gfx.image.new("images/owl_neutral"),
    alert   = gfx.image.new("images/owl_alert"),
  }
  s.owl = gfx.sprite.new(s.owlImgs.neutral or gfx.image.new("images/owl_neutral"))
  s.owl:moveTo(OWL_X, OWL_Y)
  s.owl:setZIndex(25)  -- above player
  s.owl:add()
  s.owlAlertTimer = nil

  -- state
  s.state = "idle"              -- idle | casting | waiting | hooking | reeling | catch_card | notice_card
  s.power = 0                   -- 0..1
  s.lastCrankPos = playdate.getCrankPosition()

  -- timers
  s.biteTimer = nil
  s.hookWindowTimer = nil
  s.catchCardTimer = nil
  s.noticeCardTimer = nil

  -- fish / reeling
  s.pendingFish = nil
  s.currentFish = nil
  s.fishDistance = 0            -- 1.0 -> 0.0 to land
  s.tension = 0                 -- 0..1
  s.fightTime = 0               -- seconds since start of reeling
  s._lastFrameTime = playdate.getCurrentTimeMilliseconds()

  -- UI text
  s.statusText = nil

  -- catch/notice card data
  s.catchInfo = nil
  s.noticeText = nil

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
function GameplayScene:_setPose(which)
  local img = self.poseImgs[which]
  if img and self.player and self.player.setImage then
    self.player:setImage(img)
  elseif img and self.player then
    local x, y = self.player.x, self.player.y
    local z = self.player:getZIndex()
    self.player:remove()
    self.player = gfx.sprite.new(img)
    self.player:moveTo(x, y)
    self.player:setZIndex(z or 10)
    self.player:add()
  end
end

function GameplayScene:_setOwlPose(which)
  if not self.owl or not self.owlImgs then return end
  local img = self.owlImgs[which]
  if not img then return end
  if self.owl.setImage then
    self.owl:setImage(img)
  else
    local x, y = self.owl.x, self.owl.y
    local z = self.owl:getZIndex()
    self.owl:remove()
    self.owl = gfx.sprite.new(img)
    self.owl:moveTo(x, y)
    self.owl:setZIndex(z or 25)
    self.owl:add()
  end
end

function GameplayScene:_owlFlashAlert(ms)
  ms = ms or 5000
  self:_setOwlPose("alert")
  if self.owlAlertTimer then self.owlAlertTimer:remove() end
  self.owlAlertTimer = playdate.timer.new(ms, function()
    self:_setOwlPose("neutral")
    self.owlAlertTimer = nil
  end)
end

function GameplayScene:_clearTimers()
  if self.biteTimer then self.biteTimer:remove(); self.biteTimer = nil end
  if self.hookWindowTimer then self.hookWindowTimer:remove(); self.hookWindowTimer = nil end
  if self.catchCardTimer then self.catchCardTimer:remove(); self.catchCardTimer = nil end
  if self.noticeCardTimer then self.noticeCardTimer:remove(); self.noticeCardTimer = nil end
  if self.owlAlertTimer then self.owlAlertTimer:remove(); self.owlAlertTimer = nil end
end

function GameplayScene:_choosePendingFish() self.pendingFish = pickFish() end

----------------------------------------------------------------
-- State transitions
----------------------------------------------------------------
function GameplayScene:_startCasting()
  self.state = "casting"
  self.power = 0
  self.lastCrankPos = playdate.getCrankPosition()
  self:_setPose("cast")
end

function GameplayScene:_releaseCast()
  self:_choosePendingFish()
  local baseMs = math.random(1000, 6000) -- 1–6 s
  local rarityAdd = (self.pendingFish.rarity == "Rare" and 700)
                 or (self.pendingFish.rarity == "Medium" and 300) or 0
  local waitMs = baseMs + rarityAdd

  self.state = "waiting"
  self:_setPose("fish")
  self.biteTimer = playdate.timer.new(waitMs, function() self:_triggerBite() end)
end

function GameplayScene:_triggerBite()
  if self.state ~= "waiting" then return end
  self.state = "hooking"

  -- OWL alert for ~1s
  self:_owlFlashAlert(1000)

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
  self.fightTime = 0.0
  self.state = "reeling"
  self:_setPose("reel")
end

-- SNAP → immediate neutral + notice popup (and owl back to neutral)
function GameplayScene:_snapLine()
  self:_clearTimers()
  self.pendingFish = nil
  self.currentFish = nil
  self.tension = 0
  self.fishDistance = 0
  self:_setPose("neutral")
  self:_setOwlPose("neutral")

  self.noticeText = "Line snapped!\nEase off when the meter is high."
  self.state = "notice_card"
  self.noticeCardTimer = playdate.timer.new(1600, function()
    if self.state == "notice_card" then self:_closeNoticeCard() end
  end)
end

-- CAUGHT → immediate neutral + caught popup (and owl back to neutral)
function GameplayScene:_finishCatch()
  self:_clearTimers()
  local info = self.currentFish or pickFish()
  self.currentFish = nil
  self.pendingFish = nil
  self.tension = 0
  self.fishDistance = 0

  self.catchInfo = info
  self:_setPose("neutral")
  self:_setOwlPose("neutral")

  self.state = "catch_card"
  self.catchCardTimer = playdate.timer.new(1800, function()
    if self.state == "catch_card" then self:_closeCatchCard() end
  end)
end

function GameplayScene:_closeCatchCard()
  if self.catchCardTimer then self.catchCardTimer:remove(); self.catchCardTimer = nil end
  self.catchInfo = nil
  self.state = "idle"
  self:_setPose("neutral")
  self:_setOwlPose("neutral")
end

function GameplayScene:_closeNoticeCard()
  if self.noticeCardTimer then self.noticeCardTimer:remove(); self.noticeCardTimer = nil end
  self.noticeText = nil
  self.state = "idle"
  self:_setPose("neutral")
  self:_setOwlPose("neutral")
end

-- ends a cast, back to idle (miss, or manual cancel from waiting)
function GameplayScene:_endCast(msg)
  self.state = "idle"
  self:_clearTimers()
  self.pendingFish = nil
  self.currentFish = nil
  self:_setPose("neutral")
  self:_setOwlPose("neutral")
  self.tension = 0
  if msg then
    self.statusText = msg
    playdate.timer.new(1000, function() self.statusText = nil end)
  end
end

----------------------------------------------------------------
-- Icon loader (24x24 fit) for the catch card
----------------------------------------------------------------
function GameplayScene:_getIconBySlug(slug, box)
  box = box or 24
  if not slug or slug == "" then return nil end
  self.iconCache = self.iconCache or {}
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

  local iw, ih = img:getSize()
  local scale = math.min(box / iw, box / ih, 1)
  if scale < 1 and img.scaledImage then
    img = img:scaledImage(scale)
  end

  self.iconCache[key] = img
  return img
end

----------------------------------------------------------------
-- INPUT
----------------------------------------------------------------
function GameplayScene:AButtonDown()
  if self.state == "idle" then
    self:_startCasting()
  elseif self.state == "casting" then
    self:_releaseCast()
  elseif self.state == "catch_card" then
    self:_closeCatchCard()
  elseif self.state == "notice_card" then
    self:_closeNoticeCard()
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

-- We only use cranked() for charging power; reeling handled per-frame.
function GameplayScene:cranked(change, acceleratedChange)
  if self.state == "casting" then
    local delta = math.abs(change) / 180
    self.power = clamp(self.power + delta, 0, 1)
  end
end

----------------------------------------------------------------
-- Fight model helpers (fishPull 0..1)
----------------------------------------------------------------
function GameplayScene:_fishPullValue(dt)
  if not self.currentFish then return 0 end
  self.fightTime = self.fightTime + dt
  local t = self.fightTime
  local pat = self.currentFish.pattern

  if pat == "steady" then
    return 0.55
  elseif pat == "gentle" then
    return 0.35 + 0.15 * math.sin(t * 1.2)
  elseif pat == "calm" then
    return 0.20 + 0.10 * math.sin(t * 0.8)
  elseif pat == "jerky" then
    local base = 0.30 + 0.10 * math.sin(t * 1.3)
    if math.random() < 0.10 then base = base + 0.40 end
    return clamp(base, 0, 1)
  elseif pat == "bursty" then
    local phase = (t * 0.6) % 1.0
    local burst = (phase < 0.35) and 0.85 or 0.25
    return burst
  elseif pat == "rhythm" then
    return 0.45 + 0.35 * (0.5 + 0.5 * math.sin(t * 1.8))
  elseif pat == "quick" then
    return 0.30 + 0.40 * (0.5 + 0.5 * math.sin(t * 3.0))
  elseif pat == "spiky" then
    local base = 0.40 + 0.25 * math.sin(t * 2.5)
    if math.random() < 0.18 then base = base + 0.45 end
    return clamp(base, 0, 1)
  else
    return 0.5
  end
end

----------------------------------------------------------------
-- Reeling/tension update (per frame while reeling)
----------------------------------------------------------------
function GameplayScene:_updateReeling(dt)
  local dAngle = playdate.getCrankChange() or 0
  local reelSpeed = math.abs(dAngle) / 90
  local fishPull = self:_fishPullValue(dt)
  local resist = lerp(0.35, 1.0, fishPull)
  local fishStrength = self.currentFish and self.currentFish.strength or 0.5
  local gain = 0.9 * fishStrength

  if dAngle > 0 then
    self.tension = self.tension + (reelSpeed * resist * gain) * dt * 1.2
  elseif dAngle < 0 then
    local relief = (-dAngle / 90) * 0.9
    self.tension = self.tension - relief * dt
  end

  -- passive decay
  self.tension = self.tension - 0.20 * dt
  self.tension = clamp(self.tension, 0, 1)

  -- reel progress
  if dAngle > 0 then
    local effectiveness = lerp(1.0, 0.4, fishPull)
    self.fishDistance = clamp(self.fishDistance - (reelSpeed * 0.035 * effectiveness) * dt * 50, 0, 1)
  elseif dAngle < 0 then
    self.fishDistance = clamp(self.fishDistance + (math.abs(dAngle) / 90) * 0.015 * dt * 50, 0, 1)
  end

  if self.tension >= 1.0 then
    self:_snapLine(); return
  end
  if self.fishDistance <= 0 then
    self:_finishCatch(); return
  end
end

----------------------------------------------------------------
-- Update / Draw
----------------------------------------------------------------
function GameplayScene:update()
  local nowMs = playdate.getCurrentTimeMilliseconds()
  local dt = (nowMs - (self._lastFrameTime or nowMs)) / 1000
  if dt <= 0 or dt > 0.1 then dt = 1/50 end
  self._lastFrameTime = nowMs

  if self.state == "reeling" then
    self:_updateReeling(dt)
  end

  -- HUD overlays
  if self.state == "casting" then
    self:_drawPowerBar()
  end
  if self.state == "reeling" then
    self:_drawTensionMeter()
    self:_drawReelProgress()
  end

  if self.statusText and self.state ~= "catch_card" and self.state ~= "notice_card" then
    gfx.drawTextAligned(self.statusText, SCREEN_W/2, 12, kTextAlignment.center)
  end

  if self.state == "catch_card" and self.catchInfo then
    self:_drawCaughtCard(self.catchInfo)
  elseif self.state == "notice_card" and self.noticeText then
    self:_drawNoticeCard(self.noticeText)
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

-- === TENSION METER (visible only while reeling) ===
function GameplayScene:_drawTensionMeter()
  local x, y = 8, 8
  local w, h = 120, 10
  local danger = 0.8

  gfx.setColor(gfx.kColorWhite); gfx.fillRect(x-2, y-2, w+4, h+4)
  gfx.setColor(gfx.kColorBlack); gfx.drawRect(x-2, y-2, w+4, h+4)

  local fill = math.floor(w * self.tension)
  gfx.fillRect(x, y, fill, h)

  local dx = x + math.floor(w * danger)
  gfx.drawLine(dx, y-3, dx, y+h+3)

  gfx.drawText("Tension", x, y + h + 4)
  if self.tension >= 0.95 then
    gfx.drawText("!", x + w + 8, y - 2)
  end
end

function GameplayScene:_drawReelProgress()
  local x, y = 8, 36
  local w, h = 120, 8
  gfx.drawText("Reel", x, y - 12)
  gfx.drawRect(x, y, w, h)
  gfx.fillRect(x, y, math.floor(w * (1.0 - self.fishDistance)), h)
end

-- === POPUP CARDS ===

-- Caught card: big title + description + tiny icon
function GameplayScene:_drawCaughtCard(info)
  local w, h = 200, 110
  local x = (SCREEN_W - w) // 2
  local y = (SCREEN_H - h) // 2

  gfx.setColor(gfx.kColorWhite); gfx.fillRect(x, y, w, h)
  gfx.setColor(gfx.kColorBlack); gfx.drawRect(x, y, w, h)

  local title = "YOU CAUGHT A " .. string.upper(info.name)
  local desc  = info.desc or "One for the bucket."
  local cx = x + w // 2

  withFont(FONT_TITLE, function()
    gfx.drawTextAligned(title, cx, y + 10, kTextAlignment.center)
  end)
  withFont(FONT_BODY, function()
    gfx.drawTextAligned(desc,  cx, y + 34, kTextAlignment.center)
  end)

  local iconSize, icon = 24, self:_getIconBySlug(info.iconSlug, 24)
  if icon then
    local iw, ih = icon:getSize()
    local drawX = cx - iw//2
    local drawY = y + h - ih - 16
    icon:draw(drawX, drawY)
  end

  gfx.drawTextAligned("A to close", cx, y + h - 14, kTextAlignment.center)
end

-- Notice card: generic message (e.g., snapped)
function GameplayScene:_drawNoticeCard(text)
  local w, h = 200, 90
  local x = (SCREEN_W - w) // 2
  local y = (SCREEN_H - h) // 2

  gfx.setColor(gfx.kColorWhite); gfx.fillRect(x, y, w, h)
  gfx.setColor(gfx.kColorBlack); gfx.drawRect(x, y, w, h)

  local cx = x + w // 2
  withFont(FONT_TITLE, function()
    gfx.drawTextAligned("LINE SNAPPED!", cx, y + 12, kTextAlignment.center)
  end)
  withFont(FONT_BODY, function()
    gfx.drawTextAligned(text or "Too much tension—ease off the crank!", cx, y + 36, kTextAlignment.center)
  end)
  gfx.drawTextAligned("A to close", cx, y + h - 14, kTextAlignment.center)
end
