import 'CoreLibs/graphics.lua'

local graphics = playdate.graphics
-- 50 Hz is max refresh rate
playdate.display.setRefreshRate(50)

-- Constants
local MAX_FILE_SIZE = 4 * 1024 * 1024
local MARGIN = 25
local CIRCLE_MARGIN = 8
local CIRCLE_RADIUS = 5
local DEVICE_WIDTH = 400
local DEVICE_HEIGHT = 240
local VOLUME_ACCELERATION = 0.05
local MAX_VOLUME = 0.025
local CRANK_SCROLL_SPEED = 1.5
local BTN_SCROLL_SPEED = 4

-- Variables
local offset = 0;
local lines = {}
local sound = playdate.sound.synth.new(playdate.sound.kWaveNoise)
local lineHeight = 0
local inverted = false
local directionHeld = 0
local pattern = graphics.image.new("pattern")

function init()
	-- Load the font
	local font = graphics.font.new("fonts/Roobert-11-Medium")
	assert(font)
	graphics.setFont(font)

	-- Read something from the filesystem
	local file = playdate.file.open("rough.txt")
	local text = file:read(MAX_FILE_SIZE)
	assert(text)

	-- Split the text into lines
	lines = splitText(text)
	lineHeight = graphics.getTextSize("A") * 1.8

	-- Set the background color
	graphics.setBackgroundColor(graphics.kColorWhite)

	-- Set up scrolling sound
	sound:setVolume(0)
	sound:playNote(850)
end

-- Update loop
function playdate.update()
	drawText()
	offset = offset + directionHeld * BTN_SCROLL_SPEED
	-- Update the sound
	local vol = math.min(math.abs(playdate.getCrankChange() * VOLUME_ACCELERATION * MAX_VOLUME), MAX_VOLUME)
	sound:setVolume(vol)
end


function drawText()
	graphics.clear()
	graphics.drawText(playdate.getCrankPosition(), MARGIN, offset)
	-- Only draw the lines that are visible
	local start = math.max(math.floor(-offset / lineHeight), 1)
	local stop = math.min(start + math.floor(DEVICE_HEIGHT / lineHeight) + 1, #lines)
	local flooredOffset = math.floor(offset)
	for i = start, stop do
		local y = flooredOffset + i * lineHeight
		graphics.drawText(lines[i], MARGIN, y)
	end
	local patternMargin = 0
	for i=-1, math.ceil(DEVICE_HEIGHT / pattern.height) do
		pattern:draw(patternMargin, i * pattern.height + flooredOffset % pattern.height)
		pattern:draw(DEVICE_WIDTH - pattern.width - patternMargin, i * pattern.height + flooredOffset % pattern.height, -1)
	end
end

-- Split text into lines with a maximum width of 400 - 2 * MARGIN
function splitText(text)
	print("Splitting text...")
	local lines = {}
	local line = ""
	local maxWidth = DEVICE_WIDTH - 2 * MARGIN
	local splitty = split(text)
	for i = 1, 10000 do
		local word = splitty(i)
		if word == "{newline}" then
			-- Newline
			table.insert(lines, line)
			line = ""
		elseif line == "" then
			-- First word
			line = word
		elseif graphics.getTextSize(line .. " " .. word) > maxWidth then
			-- Line is too long, commit it and start again with this word
			table.insert(lines, line)
			line = word
		else
			line = line .. " " .. word
		end
	end
	table.insert(lines, line)
	print("Split into " .. #lines .. " lines")
	return lines
end

function split(text)
	-- replace \n with "{newline}"
	local newText = string.gsub(text, "\n", " {newline} ")
	-- split on spaces
	return string.gmatch(newText, "%S+")
end

-- Register input callbacks
function playdate.cranked(change, acceleratedChange)
	-- print("cranked", change, acceleratedChange)
	offset = offset + change * CRANK_SCROLL_SPEED
end

function playdate.upButtonDown()
	print("up")
	directionHeld = 1
end

function playdate.upButtonUp()
	directionHeld = 0
end

function playdate.downButtonDown()
	print("down")
	directionHeld = -1
end

function playdate.downButtonUp()
	directionHeld = 0
end

function playdate.leftButtonDown()
	print("left")
end

function playdate.rightButtonDown()
	print("right")
end

function playdate.AButtonDown()
	print("A")
end

function playdate.BButtonDown()
	print("B")
	inverted = not inverted
	playdate.display.setInverted(inverted)
end

init()