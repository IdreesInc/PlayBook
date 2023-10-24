import 'CoreLibs/graphics.lua'

local playdate = playdate
local graphics = playdate.graphics
local min = math.min
local max = math.max
local abs = math.abs
local floor = math.floor
local ceil = math.ceil
local sub = string.sub
local insert = table.insert

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
local cleanText = nil
local range = 500
local previousAnchorIndex = 1
local previousAnchorLine = nil
local anchorIndex = 1
local anchorLine = 1
local nextAnchorIndex = 1
local nextAnchorLine = nil
local skipSoundTicks = 0
local skipScrollTicks = 0
local previousCrankOffset = 0

local init = function ()
	-- Load the font
	local font = graphics.font.new("fonts/RobotoSlab-VariableFont_wght-12")
	assert(font)
	graphics.setFont(font)

	-- Read something from the filesystem
	local file = playdate.file.open("rough.txt")
	sourceText = file:read(MAX_FILE_SIZE)
	assert(sourceText)
	cleanText = preprocessText(sourceText)

	-- Split the text into lines
	generateLines()
	lineHeight = graphics.getTextSize("A") * 1.6

	-- Set the background color
	graphics.setBackgroundColor(graphics.kColorWhite)

	-- Set up scrolling sound
	sound:setVolume(0)
	sound:playNote(850)
end

local drawText = function ()
	graphics.clear()
	graphics.drawText(playdate.getCrankPosition(), margin, offset)
	-- Only draw the lines that are visible
	-- local start = math.max(math.floor(-offset / lineHeight), 1)
	-- local stop = math.min(start + math.floor(DEVICE_HEIGHT / lineHeight) + 1, #lines)
	local flooredOffset = floor(offset)
	-- for i = start, stop do
	-- 	local y = flooredOffset + i * lineHeight
	-- 	graphics.drawText(lines[i], margin, y)
	-- end
	local startLine
	if previousAnchorLine == nil then
		startLine = anchorLine
	else
		startLine = previousAnchorLine
	end
	startLine = max(startLine, 1)
	local endLine
	if nextAnchorLine == nil then
		endLine = anchorLine + #lines - 1
	else
		endLine = nextAnchorLine - 1
	end
	-- print("Start line: " .. startLine, "End line: " .. endLine)
	-- endLine = min(endLine, #lines)
	for i = startLine, endLine do
		local y = flooredOffset + i * lineHeight
		graphics.drawText(lines[i], margin, y)
	end
	local patternMargin = 0
	if showBorder then
		for i=-1, ceil(DEVICE_HEIGHT / pattern.height) do
			pattern:draw(patternMargin, i * pattern.height + flooredOffset % pattern.height)
			pattern:draw(DEVICE_WIDTH - pattern.width - patternMargin, i * pattern.height + flooredOffset % pattern.height, -1)
		end
	end
	-- Detect end of text
	if flooredOffset + endLine * lineHeight < DEVICE_HEIGHT then
		-- Add more lines
		appendLines()
	end
end

-- Update loop
function playdate.update()
	drawText()
	offset = offset + directionHeld * BTN_SCROLL_SPEED
	local vol = min(abs(playdate.getCrankChange() * VOLUME_ACCELERATION * MAX_VOLUME), MAX_VOLUME)
	if skipSoundTicks > 0 then
		skipSoundTicks = skipSoundTicks - 1
	else
		-- Update the sound
		sound:setVolume(vol)
	end
end

function appendLines()
	-- Check performance
	playdate.resetElapsedTime()
	local newLines, indexLast = getLines(cleanText, nextAnchorIndex, nextAnchorIndex + range)
	-- insert(lines, "     [APPEND]")
	local start = nextAnchorLine
	local stop = start + #newLines - 1
	for i = start, stop do
		lines[i] = newLines[i - start + 1]
	end
	if previousAnchorLine ~= nil then
		-- Remove all lines before the previous anchor line
		for i = previousAnchorLine, anchorLine - 1 do
			lines[i] = nil
		end
	end
	previousAnchorIndex = anchorIndex
	previousAnchorLine = anchorLine
	if nextAnchorLine == nil then
		nextAnchorLine = anchorLine + #newLines
	else
		local previousNext = nextAnchorLine
		anchorLine = nextAnchorLine
		nextAnchorLine = previousNext + #newLines
	end
	nextAnchorIndex = indexLast + nextAnchorIndex
	-- print("Previous anchor line: " .. previousAnchorLine, "Current anchor line: " .. anchorLine, "Next anchor line: " .. nextAnchorLine)
	-- skipSoundTicks = 5
	skipScrollTicks = 1
	print("Append time: " .. (playdate.getElapsedTime()))
end

function generateLines()
	print("Splitting text...")
	lines, indexLast = getLines(cleanText, anchorIndex, anchorIndex + range)
	nextAnchorIndex = indexLast
	nextAnchorLine = anchorLine + #lines
	print(#lines)
end


function getLines(wholeText, startChar, endChar)
	-- Split text into lines from the starting character to the ending character
	local newLines = {}
	local text = string.sub(wholeText, startChar, endChar)
	-- https://stackoverflow.com/questions/829063/how-to-iterate-individual-characters-in-lua-string
	local maxWidth = DEVICE_WIDTH - 2 * margin
	local lastSpace = nil
	local currentLine = ""
	local lineWidth = 0
	local indexOfStartOfLastLine = 1
	for i = 1, #text do
		local char = sub(text, i, i)
		local charWidth = graphics.getTextSize(char)
		if char == "\n" then
			-- Newline
			insert(newLines, currentLine)
			currentLine = ""
			lineWidth = 0
			lastSpace = nil
			indexOfStartOfLastLine = i + 1
		else
			if lineWidth + charWidth > maxWidth then
				if lastSpace then
					-- Cut off at the last space
					insert(newLines, sub(currentLine, 1, lastSpace))
					-- Add the rest of the line, excluding the space
					currentLine = sub(currentLine, lastSpace + 2) .. char
					lineWidth = graphics.getTextSize(currentLine)
					indexOfStartOfLastLine = i - #currentLine
					lastSpace = nil
				else
					-- Cut off at the last character
					insert(newLines, currentLine)
					currentLine = char
					lineWidth = charWidth
					indexOfStartOfLastLine = i
				end
			elseif char == " " then
				-- Update last space
				lastSpace = #currentLine
				currentLine = currentLine .. char
				lineWidth = lineWidth + charWidth
			elseif char == "	" then
				-- Ignore tabs
			else
				-- Normal letter
				currentLine = currentLine .. char
				lineWidth = lineWidth + charWidth
			end
		end
	end
	return newLines, indexOfStartOfLastLine
end

function split(text)
	-- split on spaces
	return string.gmatch(text, "%S+")
end

function preprocessText(text)
	-- replace \n with "{newline}"
	-- local newText = string.gsub(text, "\n", " {newline} ")
	return text
end

-- Register input callbacks
function playdate.cranked(change, acceleratedChange)
	-- print("cranked", change, acceleratedChange)
	if skipScrollTicks > 0 then
		skipScrollTicks = skipScrollTicks - 1
		offset = offset - previousCrankOffset
	else
		offset = offset - change * CRANK_SCROLL_SPEED
		previousCrankOffset = change * CRANK_SCROLL_SPEED
	end
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