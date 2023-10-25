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
local sound = playdate.sound.synth.new(playdate.sound.kWaveNoise)
local lineHeight = 0
local inverted = false
local directionHeld = 0
local pattern = graphics.image.new("pattern")
local showBorder = false
local margin = 10
local sourceText = nil
local text = nil
local lines = {}
local emptyLinesAbove = 0
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
	text = preprocessText(sourceText)

	-- Split the text into lines
	initializeLines()
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
	local drawOffset = floor(offset) + emptyLinesAbove * lineHeight
	local numOfLines = #lines
	local lineEnd = min(ceil((DEVICE_HEIGHT - drawOffset) / lineHeight), numOfLines)
	for i = 1, lineEnd do
		local y = drawOffset + i * lineHeight
		graphics.drawText(lines[i].text, margin, y)
	end
	local patternMargin = 0
	if showBorder then
		for i=-1, ceil(DEVICE_HEIGHT / pattern.height) do
			pattern:draw(patternMargin, i * pattern.height + drawOffset % pattern.height)
			pattern:draw(DEVICE_WIDTH - pattern.width - patternMargin, i * pattern.height + drawOffset % pattern.height, -1)
		end
	end
	if #lines > 0 then
		-- Detect beginning of text
		if drawOffset + 2 * lineHeight > 0 then
			local lineRange = ceil((drawOffset + 2 * lineHeight) / lineHeight)
			prependLines(lineRange)
			removeLines(lineRange, true)
		end
		-- Detect end of text
		if drawOffset + numOfLines * lineHeight < DEVICE_HEIGHT then
			local lineRange = ceil((DEVICE_HEIGHT - (drawOffset + numOfLines * lineHeight)) / lineHeight)
			appendLines(lineRange)
			removeLines(lineRange, false)
		end
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

function initializeLines()
	appendLines(20)
	prependLines(20)
	print(#lines)
end

function removeLines(numOfLines, fromBottom)
	print("Removing " .. numOfLines .. " lines")
	if fromBottom then
		for i = 1, numOfLines do
			table.remove(lines)
		end
	else
		for i = 1, numOfLines do
			table.remove(lines, 1)
		end
	end
end

function prependLines(additionalLines, startChar)
	addLines(additionalLines, false, startChar)
	emptyLinesAbove = emptyLinesAbove - additionalLines
end

function appendLines(additionalLines, startChar)
	addLines(additionalLines, true, startChar)
	emptyLinesAbove = emptyLinesAbove + additionalLines
end

function addLines(additionalLines, append, startChar)
	if text == nil then
		print("Error: text is nil")
		return
	end
	-- Initial number of lines
	local initialNumOfLines = #lines
	-- Live number of lines
	local numOfLines = initialNumOfLines
	-- Index of the character currently being processed
	local charIndex = 1
	if startChar then
		charIndex = startChar
	elseif numOfLines > 0 then
		if append then
			charIndex = lines[#lines].stop + 1
		else
			charIndex = lines[1].start - 1
		end
	end
	-- The max width in pixels that a line can be
	local MAX_WIDTH = DEVICE_WIDTH - 2 * margin
	-- The text of the current line as it is processed
	local currentLine = ""
	-- The index of the first character of the current line
	local lineStart = charIndex
	-- The index of the last character of the current line
	local lineStop = charIndex
	-- Index within the line of the last space character in for word wrapping
	local lastSpace = nil
	-- Index within the text of the last space character
	local lastSpaceIndex = nil
	-- Function to insert a line into the lines table
	local insertLine = function (line, start, stop, nextLine)
		if nextLine == nil then
			nextLine = ""
		end
		if append then
			insert(lines, { text = line, start = start, stop = stop })
		else
			insert(lines, 1, { text = line, start = start, stop = stop })
		end
		currentLine = nextLine
		numOfLines = numOfLines + 1
		lastSpace = nil
		lastSpaceIndex = nil
		if append then
			lineStart = stop + 1
			lineStop = lineStart + #nextLine
		else
			lineStop = start - 1
			lineStart = lineStop - #nextLine
		end
	end
	-- Add lines until the target number of lines is reached
	while numOfLines < initialNumOfLines + additionalLines do
		local char = sub(text, charIndex, charIndex)
		local combined
		if append then
			combined = currentLine .. char
		else
			combined = char .. currentLine
		end
		if char == "\n" then
			-- Newline is converted to a space before being added so it counts
			-- as a character without the draw func printing an extra newline
			if append then
				insertLine(currentLine .. " ", lineStart, lineStop)
			else
				insertLine(" " .. currentLine, lineStart, lineStop)
			end
		elseif graphics.getTextSize(combined) > MAX_WIDTH then
			if lastSpace then
				if append then
					-- Wrap at last space, including the space
					local textBeforeWrap = sub(currentLine, 1, lastSpace)
					local textAfterWrap = sub(currentLine, lastSpace + 1) .. char
					insertLine(textBeforeWrap, lineStart, lastSpaceIndex, textAfterWrap)
					-- print(textBeforeWrap .. "|" .. textAfterWrap)
				else
					-- Wrap at last space, excluding the space
					local textBeforeWrap = sub(currentLine, #currentLine - lastSpace + 2)
					local textAfterWrap = char .. sub(currentLine, 1, #currentLine - lastSpace)
					-- print(lastSpace .. " " .. currentLine)
					insertLine(textBeforeWrap, lineStart, lastSpaceIndex, textAfterWrap)
					print(textBeforeWrap .. "|" .. textAfterWrap)
				end
			else
				-- Sharp wrap at character
				insertLine(currentLine, lineStart, lineStop, char)
			end
		else
			-- Normal letter
			currentLine = combined
			if char == " " then
				-- Update last space to the local index
				lastSpace = #currentLine
				-- Update this to the index within the text
				lastSpaceIndex = charIndex
			end
			if append then
				lineStop = charIndex
			else
				lineStart = charIndex
			end
		end
		if append then
			charIndex = charIndex + 1
		else
			charIndex = charIndex - 1
		end
	end
	print("Added " .. (numOfLines - initialNumOfLines) .. " lines")
end

function split(text)
	-- split on spaces
	return string.gmatch(text, "%S+")
end

function preprocessText(text)
	-- Remove tabs
	-- local newText = string.gsub(text, "	", "")
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
	-- lines = initializeLines(sourceText)
end

function playdate.BButtonDown()
	print("B")
	inverted = not inverted
	playdate.display.setInverted(inverted)
end

init()