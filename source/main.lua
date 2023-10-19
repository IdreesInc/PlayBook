import 'CoreLibs/graphics.lua'

local graphics = playdate.graphics
-- 50 Hz is max refresh rate
playdate.display.setRefreshRate(50)

-- Constants
local MAX_FILE_SIZE = 4 * 1024 * 1024
local DEVICE_WIDTH = 400
local DEVICE_HEIGHT = 240
local VOLUME_ACCELERATION = 0.05
local MAX_VOLUME = 0.025
local CRANK_SCROLL_SPEED = 1.5
local BTN_SCROLL_SPEED = 5
local MARGIN_WITH_BORDER = 24
local MARGIN_WITHOUT_BORDER = 10

-- Variables
local offset = 0;
local lines = {}
local sound = playdate.sound.synth.new(playdate.sound.kWaveNoise)
local lineHeight = 0
local inverted = false
local directionHeld = 0
local pattern = graphics.image.new("pattern")
local showBorder = false
local margin = 10
local sourceText = nil
local startLine = 1
local endLine = 0
local startLineCharIndex = 0
local endLineCharIndex = 0

function init()
	-- Load the font
	local font = graphics.font.new("fonts/RobotoSlab-VariableFont_wght-12")
	assert(font)
	graphics.setFont(font)

	-- Read something from the filesystem
	local file = playdate.file.open("rough.txt")
	sourceText = file:read(MAX_FILE_SIZE)
	assert(sourceText)

	-- Split the text into lines
	generateLines(sourceText, 10)
	lineHeight = graphics.getTextSize("A") * 1.6

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
	graphics.drawText(playdate.getCrankPosition(), margin, offset)
	-- Only draw the lines that are visible
	-- local start = math.max(math.floor(-offset / lineHeight), 1)
	-- local stop = math.min(start + math.floor(DEVICE_HEIGHT / lineHeight) + 1, #lines)
	local flooredOffset = math.floor(offset)
	-- for i = start, stop do
	-- 	local y = flooredOffset + i * lineHeight
	-- 	graphics.drawText(lines[i], margin, y)
	-- end
	for i = startLine, endLine do
		local y = flooredOffset + i * lineHeight
		graphics.drawText(lines[i], margin, y)
	end
	local patternMargin = 0
	if showBorder then
		for i=-1, math.ceil(DEVICE_HEIGHT / pattern.height) do
			pattern:draw(patternMargin, i * pattern.height + flooredOffset % pattern.height)
			pattern:draw(DEVICE_WIDTH - pattern.width - patternMargin, i * pattern.height + flooredOffset % pattern.height, -1)
		end
	end
	-- Detect end of text
	if flooredOffset + endLine * lineHeight < 0 then
		-- Add more lines
		generateLines(sourceText, 5)
	end
end

-- Split text into lines with a maximum width of 400 - 2 * MARGIN
-- Size is the number of lines to add, negative to prepend, positive to append
function generateLines(text, size)
	print("Splitting text...")
	local maxLength = getMaxLineLength()
	if size < 0 then
		-- Prepend
	else
		-- Append
		local newEnd = endLineCharIndex + maxLength * size
		local chunk = getLines(text, endLineCharIndex + 1, newEnd)
		-- Chunk should always have more lines than requested
		print("Chunk has " .. #chunk .. " lines")
		-- Determine if the first line is a continuation of the last line
		for i, line in ipairs(chunk) do
			table.insert(lines, line)
		end
		endLineCharIndex = newEnd
		endLine = endLine + #chunk
		print("Size of lines: " .. #lines)
		print("End line: " .. endLine)
	end
end

-- Get the maximum number of characters that can fit on a line
function getMaxLineLength()
	local maxWidth = DEVICE_WIDTH
	local lineLength = 0
	local i = 1
	while lineLength < maxWidth do
		lineLength = graphics.getTextSize(string.rep("I", i))
		i = i + 1
	end
	return i - 1
end


function getLines(wholeText, startChar, endChar)
	-- Split text into lines from the starting character to the ending character
	local someLines = {}
	local line = ""
	local maxWidth = DEVICE_WIDTH - 2 * margin
	local text = string.sub(wholeText, startChar, endChar)
	local spliterator = split(text)
	for word in spliterator do
		if word == "{newline}" then
			-- Newline
			table.insert(someLines, line)
			line = ""
		elseif line == "" then
			-- First word
			line = word
		elseif graphics.getTextSize(line .. " " .. word) > maxWidth then
			-- Line is too long, commit it and start again with this word
			table.insert(someLines, line)
			line = word
		else
			line = line .. " " .. word
		end
	end
	table.insert(someLines, line)
	return someLines
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
	offset = offset - change * CRANK_SCROLL_SPEED
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
	showBorder = not showBorder
	if showBorder then
		margin = MARGIN_WITH_BORDER
	else
		margin = MARGIN_WITHOUT_BORDER
	end
	lines = generateLines(sourceText)
end

function playdate.BButtonDown()
	print("B")
	inverted = not inverted
	playdate.display.setInverted(inverted)
end

init()