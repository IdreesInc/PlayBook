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
-- The maximum size of a file to read in bytes
local MAX_FILE_SIZE = 4 * 1024 * 1024
-- The width of the screen in pixels
local DEVICE_WIDTH = 400
-- The height of the screen in pixels
local DEVICE_HEIGHT = 240
-- The acceleration of the volume while scrolling
local VOLUME_ACCELERATION = 0.05
-- The maximum volume of the scrolling noise
local MAX_VOLUME = 0.025
-- The speed of scrolling via the crank
local CRANK_SCROLL_SPEED = 1.2
-- The speed of scrolling via the D-pad
local BTN_SCROLL_SPEED = 5
local MARGIN_WITH_BORDER = 24
local MARGIN_WITHOUT_BORDER = 10

-- Variables
-- The scroll offset
local offset = 0;
-- The sound to play while scrolling
local sound = playdate.sound.synth.new(playdate.sound.kWaveNoise)
-- The height of a line of text in the current font
local lineHeight = 0
-- Whether the screen is inverted
local inverted = false
-- The direction the user is scrolling via the D-pad
local directionHeld = 0
-- The margin on the left of the screen
local leftMargin = 10
-- The margin on the right of the screen
local rightMargin = 10
-- The processed text that is being read
local text = nil
-- The lines of text that are currently being displayed
local lines = {}
-- The number of empty lines to draw above the first line
local emptyLinesAbove = 0
-- The number of ticks to skip modulating the volume
local skipSoundTicks = 0
-- The number of ticks to skip modulating the scroll offset
local skipScrollTicks = 0
-- The crank offset from before skipScrollTicks was set
local previousCrankOffset = 0

local init = function ()
	-- Load the font
	local font = graphics.font.new("fonts/RobotoSlab-VariableFont_wght-12")
	assert(font)
	graphics.setFont(font)

	-- Read something from the filesystem
	local file = playdate.file.open("rough.txt")
	local sourceText = file:read(MAX_FILE_SIZE)
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

-- Draw call
local drawText = function ()
	graphics.clear()
	-- Draw offset for debugging
	graphics.drawText(playdate.getCrankPosition(), leftMargin, offset)
	-- Calculate where to begin drawing lines
	local drawOffset = floor(offset) + emptyLinesAbove * lineHeight
	local numOfLines = #lines
	local lineEnd = min(ceil((DEVICE_HEIGHT - drawOffset) / lineHeight), numOfLines)
	for i = 1, lineEnd do
		local y = drawOffset + i * lineHeight
		graphics.drawText(lines[i].text, leftMargin, y)
	end
	-- Detect when user is close to beginning or end of streamed lines
	if #lines > 0 then
		-- Detect beginning of text
		if drawOffset + 2 * lineHeight > 0 then
			local lineRange = ceil((drawOffset + 2 * lineHeight) / lineHeight)
			-- lineRange = 1
			removeLines(prependLines(lineRange), true)
		end
		-- Detect end of text
		if drawOffset + numOfLines * lineHeight < DEVICE_HEIGHT then
			local lineRange = ceil((DEVICE_HEIGHT - (drawOffset + numOfLines * lineHeight)) / lineHeight)
			-- lineRange = 1
			removeLines(appendLines(lineRange), false)
		end
	end
end

-- Update loop
function playdate.update()
	drawText()
	-- Update offset when the D-pad is held
	offset = offset + directionHeld * BTN_SCROLL_SPEED
	-- Modulate volume based on scroll speed
	local vol = min(abs(playdate.getCrankChange() * VOLUME_ACCELERATION * MAX_VOLUME), MAX_VOLUME)
	if skipSoundTicks > 0 then
		skipSoundTicks = skipSoundTicks - 1
	else
		-- Update the sound
		sound:setVolume(vol)
	end
end

-- Initialize the first batch of lines
function initializeLines()
	appendLines(20)
	emptyLinesAbove = 0
	print(#lines)
end

-- Remove the given number of lines
function removeLines(numOfLines, fromBottom)
	if numOfLines == 0 then
		return
	end
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

-- Add lines to the top of the list
function prependLines(additionalLines, startChar)
	local linesAdded  = addLines(additionalLines, false, startChar)
	emptyLinesAbove = emptyLinesAbove - linesAdded
	return linesAdded
end

-- Add lines to the bottom of the list
function appendLines(additionalLines, startChar)
	local linesAdded = addLines(additionalLines, true, startChar)
	emptyLinesAbove = emptyLinesAbove + linesAdded
	return linesAdded
end

-- Add the given number of lines to the list
-- Note that if there are no more lines available, less than the given number of lines will be returned
function addLines(additionalLines, append, startChar)
	-- Keep track of time taken
	playdate.resetElapsedTime()
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
	local MAX_WIDTH = DEVICE_WIDTH - leftMargin - rightMargin
	-- The size of the text in characters
	local textSize = #text
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
	-- Size of the line in pixels
	local lineSize = 0
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
		lineSize = graphics.getTextSize(nextLine)
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
		if charIndex < 1 or charIndex > textSize then
			if currentLine ~= "" then
				insertLine(currentLine, lineStart, lineStop)
			end
			break
		end
		local char = sub(text, charIndex, charIndex)
		local charSize = graphics.getTextSize(char)
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
		elseif lineSize + charSize > MAX_WIDTH then
			if lastSpace then
				-- Wrap at last space, excluding the space
				if append then
					local textBeforeWrap = sub(currentLine, 1, lastSpace)
					local textAfterWrap = sub(currentLine, lastSpace + 1) .. char
					insertLine(textBeforeWrap, lineStart, lastSpaceIndex, textAfterWrap)
					-- print(textBeforeWrap .. "|" .. textAfterWrap)
				else
					local invertedLastSpace = #currentLine - lastSpace + 1
					local textBeforeWrap = sub(currentLine, invertedLastSpace + 1)
					local textAfterWrap = char .. sub(currentLine, 1, invertedLastSpace)
					insertLine(textBeforeWrap, lineStart + invertedLastSpace, lineStop, textAfterWrap)
					-- print(textAfterWrap .. "|" .. textBeforeWrap)
				end
			else
				-- Sharp wrap at character
				insertLine(currentLine, lineStart, lineStop, char)
			end
		else
			-- Normal letter
			currentLine = combined
			lineSize = lineSize + charSize
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
	-- skipScrollTicks = 1
	-- skipSoundTicks = 5
	-- print("Added " .. (numOfLines - initialNumOfLines) .. " lines in " .. playdate.getElapsedTime() .. " seconds")
	return numOfLines - initialNumOfLines
end

-- Process the text to display better on the Playdate
function preprocessText(text)
	-- Remove tabs
	local newText = string.gsub(text, "	", "")
	return newText
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
	-- lines = initializeLines(sourceText)
end

function playdate.BButtonDown()
	print("B")
	inverted = not inverted
	playdate.display.setInverted(inverted)
end

init()