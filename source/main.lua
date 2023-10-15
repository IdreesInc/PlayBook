local graphics = playdate.graphics
-- 50 Hz is max refresh rate
playdate.display.setRefreshRate(50)

-- Constants
local MAX_FILE_SIZE = 4 * 1024 * 1024
local MARGIN = 30
local DEVICE_WIDTH = 400
local DEVICE_HEIGHT = 240

-- Variables
local offset = 0;
local lines = {}
local lineHeight = 0

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
	lineHeight = graphics.getTextSize("A") * 1.5

	-- Set the background color
	graphics.setBackgroundColor(graphics.kColorWhite)
end

-- Update loop
function playdate.update()
	updateText()
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

-- Print the text
function updateText()
	graphics.clear()
	graphics.drawText(playdate.getCrankPosition(), MARGIN, offset)
	-- Only draw the lines that are visible
	local start = math.max(math.floor(-offset / lineHeight), 1)
	local stop = math.min(start + math.floor(DEVICE_HEIGHT / lineHeight), #lines)
	local flooredOffset = math.floor(offset)
	for i = start, stop do
		graphics.drawText(lines[i], MARGIN, flooredOffset + i * lineHeight)
	end
end

-- Register input callbacks
function playdate.cranked(change, acceleratedChange)
	-- print("cranked", change, acceleratedChange)
	offset = offset + change
end

function playdate.upButtonDown()
	print("up")
end

function playdate.downButtonDown()
	print("down")
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
end

init()