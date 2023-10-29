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
local BTN_SCROLL_SPEED = 6
local MARGIN_WITH_BORDER = 24
local MARGIN_WITHOUT_BORDER = 10
-- Scene options
local MENU = "MENU"
local READER = "READER"

-- Variables
-- Shared
-- The current scene being displayed
local scene = MENU
-- The state of the books loaded from the save file
local booksState = {}
-- The key of the currently selected book
local currentBookKey = nil
-- The state of the currently selected book
local currentBookSettings = nil
-- The scroll offset
local offset = 0;

-- Menu
-- Book selection background
local bookImage = graphics.image.new("book.png")
-- List of books available in the filesystem
-- Format: { path = "path/to/file.txt", name = "file" }
local availableBooks = {}
-- The book index currently highlighted by the user
local highlightedBook = nil

-- Reader
-- The sound to play while scrolling
local sound = playdate.sound.synth.new(playdate.sound.kWaveNoise)
-- The height of a line of text in the current font
local lineHeight = 0
-- Whether the screen is inverted
local inverted = false
-- The direction the user is scrolling via the D-pad
local directionHeld = 0
-- The margin on the left of the screen
local leftMargin = 6
-- The margin on the right of the screen
local rightMargin = 22
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
-- The index of the first character to initialize lines from
-- local initialIndex = 1
-- The start of the first line visible on the screen
local indexAtTopOfScreen = 1
-- The percentage (between 0 and 1) of the text that has been read
local textProgress = 0
-- Candle parts
local candleFlameOne = graphics.image.new("candle-flame-1.png")
local candleFlameTwo = graphics.image.new("candle-flame-2.png")
local candleFlameThree = graphics.image.new("candle-flame-3.png")
local candleTop = graphics.image.new("candle-top.png")
local candleSection = graphics.image.new("candle-section.png")
local candleDripLeft = graphics.image.new("candle-drip-left.png")
local candleDripRight = graphics.image.new("candle-drip-right.png")
local candleHolder = graphics.image.new("candle-holder.png")
-- The flame frame currently being displayed
local flame = candleFlameOne

-- Get a value from a table if it exists or return a default value
local getOrDefault = function (table, key, expectedType, default)
	local value = table[key]
	if value == nil then
		return default
	else
		if type(value) ~= expectedType then
			print("Warning: value for key " .. key .. " is type " .. type(value) .. " but expected type " .. expectedType)
			return default
		end
		return value
	end
end

-- Save the state of the game to the datastore
local saveState = function ()
	print("Saving state...")
	local state = {}
	state.inverted = inverted
	if currentBookKey ~= nil and currentBookSettings ~= nil then
		currentBookSettings.readIndex = indexAtTopOfScreen
		booksState[currentBookKey] = currentBookSettings
	end
	state.books = booksState
	playdate.datastore.write(state)
	print("State saved!")
end

-- Load the state of the game from the datastore
local loadState = function ()
	print("Loading state...")
	local state = playdate.datastore.read()
	if state == nil then
		state = {}
		print("No state found, using defaults")
	else
		print("State found!")
	end
	inverted = getOrDefault(state, "inverted", "boolean", inverted)
	booksState = getOrDefault(state, "books", "table", {})
end

local loadCurrentBook = function ()
	currentBookSettings = booksState[currentBookKey]
	if currentBookSettings == nil then
		print("No state found for book " .. currentBookKey .. ", using defaults")
		currentBookSettings = {}
	end
	currentBookSettings.readIndex = getOrDefault(currentBookSettings, "readIndex", "number", 1)
end

function playdate.gameWillTerminate()
	saveState()
end

function playdate.deviceWillSleep()
	saveState()
end

function playdate.deviceWillLock()
	saveState()
end

local init = function ()
	loadState()
	-- Load the font
	local font = graphics.font.new("fonts/RobotoSlab-VariableFont_wght-12")
	assert(font)
	graphics.setFont(font)

	-- Set the background color
	graphics.setBackgroundColor(graphics.kColorWhite)
	playdate.display.setInverted(inverted)

	initMenu()
end

function initMenu()
	-- Set the scene
	scene = MENU

	-- Reset variables
	offset = 0
	directionHeld = 0

	-- Stop the sound
	sound:setVolume(0)

	scanForBooks()
end

-- Initialize the reader application. Should be able to be called more than once
function initReader(selectedBook)
	-- Set the scene
	scene = READER

	-- Reset variables
	offset = 0
	directionHeld = 0
	text = nil
	lines = {}
	emptyLinesAbove = 0
	skipSoundTicks = 0
	skipScrollTicks = 0
	previousCrankOffset = 0
	indexAtTopOfScreen = 1
	textProgress = 0

	-- Set the current book
	currentBookKey = selectedBook.name
	loadCurrentBook()
	if currentBookSettings == nil then
		-- Should not happen
		print("Error: currentBookSettings is nil")
		return
	end

	-- Read the book from the filesystem
	local file = playdate.file.open(selectedBook.path)
	local sourceText = file:read(MAX_FILE_SIZE)
	assert(sourceText)
	text = preprocessText(sourceText)

	-- Calculate the line height
	lineHeight = graphics.getTextSize("A") * 1.6

	-- Split the text into lines
	initializeLines(currentBookSettings.readIndex)

	-- Set up scrolling sound
	sound:setVolume(0)
	sound:playNote(850)

	-- Reset the crank position
	offset = 0
end

-- Scan the filesystem for books
function scanForBooks()
	local files = playdate.file.listFiles()
	availableBooks = {}
	-- Filter files to only include those that end with .txt
	for i = #files, 1, -1 do
		if sub(files[i], #files[i] - 3) == ".txt" then
			-- It's a book
			local path = files[i]
			local name = sub(path, 1, #path - 4)
			local book = {
				path = path,
				name = name
			}
			insert(availableBooks, book)
		end
	end
	-- Sort alphabetically to ensure deterministic order
	table.sort(availableBooks, function (a, b)
		return a.name < b.name
	end)
end

-- Draw a candle to the side of the text to indicate progress
local drawCandle = function ()
	local TOP = textProgress * (DEVICE_HEIGHT - candleTop.height - 10 - candleHolder.height) + 6
	local LEFT = DEVICE_WIDTH - 4 - candleSection.width
	-- Draw the top of the candle
	candleTop:draw(LEFT, TOP)
	-- Draw the flame flickering
	local timeInMilliseconds = playdate.getCurrentTimeMilliseconds()
	if timeInMilliseconds % 27 == 0 then
		if flame == candleFlameOne or flame == candleFlameThree then
			flame = candleFlameTwo
		elseif flame == candleFlameTwo then
			if math.random() < 0.6 then
				flame = candleFlameOne
			else
				flame = candleFlameThree
			end
		end
	end
	flame:draw(LEFT, TOP)
	-- Draw the candle length
	local sections = floor((DEVICE_HEIGHT - TOP - candleTop.height) / candleSection.height) + 1
	for i = 1, sections do
		candleSection:draw(LEFT, TOP + candleTop.height + (i - 1) * candleSection.height)
	end
	-- Draw the drips
	local bottom = DEVICE_HEIGHT - candleDripLeft.height + 3 - candleHolder.height
	candleDripLeft:draw(LEFT - candleDripLeft.width + 1, min(bottom, TOP + 40 + textProgress * 115))
	candleDripRight:draw(LEFT + candleSection.width - 1, min(bottom, TOP + 80 + textProgress * 40))
	-- Draw the holder
	candleHolder:draw(LEFT - 3, DEVICE_HEIGHT - candleHolder.height)
end

-- Draw the reader application
local drawText = function ()
	graphics.clear()
	-- Draw offset for debugging
	-- graphics.drawText(playdate.getCrankPosition(), leftMargin, offset)
	if #lines > 0 then
		-- Calculate where to begin drawing lines
		local drawOffset = floor(offset) + emptyLinesAbove * lineHeight
		local numOfLines = #lines
		local lineEnd = min(ceil((DEVICE_HEIGHT - drawOffset) / lineHeight), numOfLines)
		local topLineStart = nil
		local topLineStop = nil
		for i = 1, lineEnd do
			local y = drawOffset + i * lineHeight
			if topLineStart == nil and y > 0 then
				topLineStart = lines[i].start
				topLineStop = lines[i].stop
			end
			graphics.drawText(lines[i].text, leftMargin, y)
		end
		if topLineStart ~= nil then
			indexAtTopOfScreen = topLineStart
			local offsetWithinLine = 1 - (drawOffset % lineHeight) / lineHeight
			local progressWithinLine = (topLineStop - topLineStart) * offsetWithinLine
			textProgress = (topLineStart + progressWithinLine) / #text
		end
		-- Detect when user is close to beginning or end of streamed lines
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
	drawCandle()
end

local drawBook = function (x, y, title, selected)
	if selected then
		graphics.setImageDrawMode(graphics.kDrawModeInverted)
	end
	local MAX_TEXT_WIDTH = 190
	local cutOffText = title
	while graphics.getTextSize(cutOffText) > MAX_TEXT_WIDTH and #cutOffText > 0 do
		cutOffText = sub(cutOffText, 1, #cutOffText - 1)
	end
	if cutOffText ~= title then
		cutOffText = cutOffText .. "..."
	end
	bookImage:draw(x, y)
	graphics.drawText(cutOffText, x + 30, y + 40)
	graphics.setImageDrawMode(graphics.kDrawModeCopy)
end

local drawMenu = function ()
	graphics.clear()
	local bottom = DEVICE_HEIGHT - 100 + offset
	local separation = 42
	-- Determine which book is closest to center of screen
	highlightedBook = nil
	local dist = 1000
	for i = 1, #availableBooks do
		local distance = abs(bottom - separation * (i - 1) - 120)
		if distance < dist then
			dist = distance
			highlightedBook = i
		end
	end
	for i = 1, #availableBooks do
		local x = 60
		if i % 2 == 0 then
			x = 80
		end
		drawBook(x, bottom - separation * (i - 1), availableBooks[i].name, i == highlightedBook)
	end
end

-- Update loop
function playdate.update()
	if scene == MENU then
		offset = max(0, offset)
		drawMenu()
	elseif scene == READER then
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
end

-- Initialize the first batch of lines
function initializeLines(startChar)
	appendLines(20, startChar)
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
	if scene == MENU then
		offset = offset - change
	elseif scene == READER then
		if skipScrollTicks > 0 then
			skipScrollTicks = skipScrollTicks - 1
			offset = offset - previousCrankOffset
		else
			offset = offset - change * CRANK_SCROLL_SPEED
			previousCrankOffset = change * CRANK_SCROLL_SPEED
		end
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
	directionHeld = 6
end

function playdate.leftButtonUp()
	directionHeld = 0
end

function playdate.rightButtonDown()
	print("right")
	directionHeld = -6
end

function playdate.rightButtonUp()
	directionHeld = 0
end

function playdate.AButtonDown()
	print("A")
	-- lines = initializeLines(sourceText)
	if scene == MENU then
		if highlightedBook ~= nil then
			initReader(availableBooks[highlightedBook])
		end
	elseif scene == READER then
		initMenu()
	end
end

function playdate.BButtonDown()
	print("B")
	inverted = not inverted
	playdate.display.setInverted(inverted)
end

init()