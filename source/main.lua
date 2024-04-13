import 'CoreLibs/graphics'
import "CoreLibs/ui"
import "CoreLibs/crank"

local playdate <const> = playdate
local graphics <const> = playdate.graphics
local json <const> = playdate.json
local min <const> = math.min
local max <const> = math.max
local abs <const> = math.abs
local floor <const> = math.floor
local ceil <const> = math.ceil
local sub <const> = string.sub
local insert <const> = table.insert

-- Constants
-- The maximum size of a file to read in bytes
local MAX_FILE_SIZE <const> = 4 * 1024 * 1024
-- The width of the screen in pixels
local DEVICE_WIDTH <const> = 400
-- The height of the screen in pixels
local DEVICE_HEIGHT <const> = 240
-- The acceleration of the volume while scrolling
local VOLUME_ACCELERATION <const> = 0.05
-- The maximum volume of the scrolling noise
local MAX_VOLUME <const> = 0.025
-- The speed of scrolling via the crank
local CRANK_SCROLL_SPEED <const> = 1.2
-- The speed of scrolling via the D-pad
local BTN_SCROLL_SPEED <const> = 6
local MARGIN_WITH_BORDER <const> = 22
local MARGIN_WITHOUT_BORDER <const> = 6
local BOOK_SEPARATION <const> = 42
local BOOK_OFFSET_SIZE <const> = 25
local FOLDER_SPACING <const> = 385
-- The font options available
local FONTS <const> = {
	{
		name = "Roboto Slab",
		font = graphics.font.new("fonts/roboto-slab-12")
	},
	{
		name = "Asheville Ayu",
		font = graphics.font.new("fonts/asheville/Asheville-Ayu"),
		height = 20
	},
	{
		name = "Roobert",
		font = graphics.font.new("fonts/roobert/Roobert-11-Medium")
	},
	{
		name = "Monocraft",
		font = graphics.font.new("fonts/monocraft-18")
	},
}
local MANUAL_NAME <const> = "The PlayBook Manual.txt"
-- Scene names
local LIBRARY = "LIBRARY"
local READER = "READER"

-- Variables

-- Loaded from Save State
-- Whether the screen is inverted
local inverted = false
-- The font key of the font to use for the reader
local readerFontId = 1
-- The current speed modifier for the crank
local crankSpeedModifier = 1
-- The state of the books loaded from the save file
local booksState = {}
-- Which progress indicator to use (1 = none, 2 = candle)
local progressIndicator = 2
-- Whether to show the books included with the app
local showDefaultBooks = true
local DEFAULT_BOOKS <const> = {
	"Adventures of Sherlock Holmes.txt",
	"Northanger Abbey.txt",
	"Pride and Prejudice.txt",
	"Frankenstein.txt",
	"The Great Gatsby.txt",
}

-- Shared
-- The current scene being displayed
local scene = LIBRARY
-- The key of the currently selected book
local currentBookKey = nil
-- The state of the currently selected book
local currentBookSettings = nil
-- The scroll offset
local offset = 0;
-- Whether the scroll sound should be played
local playScrollSound = true

-- Library
-- Book selection background
local bookImage <const> = graphics.image.new("images/book.png")
-- Bookmark tab image
local bookmarkImage <const> = graphics.image.new("images/bookmark.png")
local bookmarkBorderImage <const> = graphics.image.new("images/bookmark-border.png")
-- List of books available in the filesystem
-- Format: { path = "path/to/file.txt", name = "file" }
local availableBooks = {}
-- The number of books in each folder
local booksPerFolder = {}
-- The book index currently highlighted by the user
local highlightedBook = nil
-- The index of the currently selected book in the current folder
local highlightedBookInFolder = 1
-- The index of the currently selected folder
local folderIndex = 1
-- The offset of the library scroll while switching selected books
local highlightedBookScrollOffset = 0
-- The offset of the library scroll while switching selected folders
local folderIndexScrollOffset = 0
-- The offset of the falling book animation
local fallingBookProgress = 0
-- The offset of the title animation
local titleAnimationProgress = 0
-- The PlayBook title image
local titleImage <const> = graphics.image.new("images/title.png")
-- A list of potential subtitles to display
local POSSIBLE_SUBTITLES <const> = {
	{"Made by Idrees"},
	{ "A reader lives a thousand", "lives before he dies" },
	{"Books are a uniquely", "portable magic"},
	{"Books are the mirrors", "of the soul."},
	{"There is no friend", "as loyal as a book"},
	{"We read to know", "we're not alone"},
	{"A book is a dream", "that you hold in your hand"},
	{"A book is a device", "to ignite the imagination"},
}
-- The subtitle currently being displayed
local subtitle = POSSIBLE_SUBTITLES[8]

-- Reader
-- The sound to play while scrolling
local sound <const> = playdate.sound.synth.new(playdate.sound.kWaveNoise)
-- The height of a line of text in the current font
local lineHeight = 0
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
-- Whether the options menu is visible and active
local menuActive = false

-- Menu
-- The views for each option
local optionViews = {}
-- The index of the currently selected option
local activeSetting = 1
-- The width of the options menu
local OPTIONS_WIDTH <const> = 150
-- The options for the menu
local MENU_OPTIONS <const> = {
	{
		label = "Theme",
		options =  {
			"Light Mode",
			"Dark Mode"
		},
		initialValue = function ()
			if inverted then
				return 2
			else
				return 1
			end
		end,
		callback = function (index)
			if index == 1 then
				setInverted(false)
			else
				setInverted(true)
			end
		end
	},
	{
		label = "Reader Font",
		-- Dynamically generated
		options = {},
		initialValue = function ()
			return readerFontId
		end,
		callback = function (index)
			readerFontId = index
			print("Setting font to " .. FONTS[readerFontId].name)
			reloadReader()
		end
	},
	{
		label = "Crank Speed",
		options =  {
			"Slower",
			"Default",
			"Faster"
		},
		initialValue = function ()
			if crankSpeedModifier == 0.75 then
				return 1
			elseif crankSpeedModifier == 1 then
				return 2
			elseif crankSpeedModifier == 1.25 then
				return 3
			else
				print("Warning: invalid crank speed modifier " .. crankSpeedModifier)
				return 2
			end
		end,
		callback = function (index)
			if index == 1 then
				crankSpeedModifier = 0.75
			elseif index == 2 then
				crankSpeedModifier = 1
			elseif index == 3 then
				crankSpeedModifier = 1.5
			end
		end
	},
	{
		label = "Progress Bar",
		options =  {
			"None",
			"Candle",
			"Scrollbar"
		},
		initialValue = function ()
			return progressIndicator
		end,
		callback = function (index)
			setProgressIndicator(index)
		end
	},
	{
		label = "Scroll Sound",
		options =  {
			"Enabled",
			"Disabled"
		},
		initialValue = function ()
			if playScrollSound then
				return 1
			else
				return 2
			end
		end,
		callback = function (index)
			if index == 1 then
				playScrollSound = true
			elseif index == 2 then
				playScrollSound = false
			end
		end
	},
	{
		label = "Included Books",
		options =  {
			"Shown in Library",
			"Hidden"
		},
		initialValue = function ()
			if showDefaultBooks then
				return 1
			else
				return 2
			end
		end,
		callback = function (index)
			if index == 1 then
				showDefaultBooks = true
			elseif index == 2 then
				showDefaultBooks = false
			end
		end
	},
}

-- Generate the options for the reader font menu
for i = 1, #FONTS do
	insert(MENU_OPTIONS[2].options, FONTS[i].name)
end

-- Candle parts
local candleFlameOne = graphics.image.new("images/candle-flame-1.png")
local candleFlameTwo = graphics.image.new("images/candle-flame-2.png")
local candleFlameThree = graphics.image.new("images/candle-flame-3.png")
local candleTop = graphics.image.new("images/candle-top.png")
local candleSection = graphics.image.new("images/candle-section.png")
local candleDripLeft = graphics.image.new("images/candle-drip-left.png")
local candleDripRight = graphics.image.new("images/candle-drip-right.png")
local candleHolder = graphics.image.new("images/candle-holder.png")
-- The flame frame currently being displayed
local flame = candleFlameOne
-- Scrollbar parts
local scrollbarArrow = graphics.image.new("images/scrollbar-arrow.png")
local scrollbarButton = graphics.image.new("images/scrollbar-button.png")
local scrollbarSection = graphics.image.new("images/scrollbar-section.png")
local scrollbarSlider = graphics.image.new("images/scrollbar-slider.png")
-- Folder arrow
local folderArrow = graphics.image.new("images/arrow.png")

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
		currentBookSettings.progress = textProgress
		booksState[currentBookKey] = currentBookSettings
	end
	state.books = booksState
	state.font = readerFontId
	state.crankSpeedModifier = crankSpeedModifier
	state.progressIndicator = progressIndicator
	state.playScrollSound = playScrollSound
	state.showDefaultBooks = showDefaultBooks
	playdate.datastore.write(state)
	print("State saved!")
	-- print("State saved: " .. json.encode(state))
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
	setInverted(getOrDefault(state, "inverted", "boolean", inverted))
	booksState = getOrDefault(state, "books", "table", {})
	readerFontId = getOrDefault(state, "font", "number", readerFontId)
	crankSpeedModifier = getOrDefault(state, "crankSpeedModifier", "number", crankSpeedModifier)
	setProgressIndicator(getOrDefault(state, "progressIndicator", "number", progressIndicator))
	playScrollSound = getOrDefault(state, "playScrollSound", "boolean", playScrollSound)
	showDefaultBooks = getOrDefault(state, "showDefaultBooks", "boolean", showDefaultBooks)
end

local loadCurrentBookSettings = function ()
	currentBookSettings = booksState[currentBookKey]
	if currentBookSettings == nil then
		print("No state found for book " .. currentBookKey .. ", using defaults")
		currentBookSettings = {}
	end
	currentBookSettings.readIndex = getOrDefault(currentBookSettings, "readIndex", "number", 1)
	currentBookSettings.progress = getOrDefault(currentBookSettings, "progress", "number", 0)
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
	-- 50 Hz is max refresh rate
	playdate.display.setRefreshRate(50)

	-- Ensure that the "book" directory exists while ensuring that later SDK changes
	-- won't cause this call to overwrite the books directory
	playdate.file.mkdir("books/.ignore-this")

	-- Load the state
	loadState()

	-- Load the font
	graphics.setFont(FONTS[readerFontId].font)

	-- Set the background color
	graphics.setBackgroundColor(graphics.kColorWhite)
	setInverted(inverted)

	initLibrary()
	initMenu()
end

-- Initialize the book selection menu, can be called more than once
function initLibrary()
	-- Set the scene
	scene = LIBRARY

	-- Reset variables
	offset = 0
	directionHeld = 0

	fallingBookProgress = 0 - DEVICE_HEIGHT * 4.75
	titleAnimationProgress = 0
	highlightedBookScrollOffset = 0
	subtitle = POSSIBLE_SUBTITLES[math.random(#POSSIBLE_SUBTITLES)]

	-- Stop the sound
	sound:setVolume(0)

	availableBooks = scanForBooks()
	booksPerFolder = {}
	local currentFolder = nil
	for i = 1, #availableBooks do
		if availableBooks[i].folder ~= currentFolder then
			currentFolder = availableBooks[i].folder
			insert(booksPerFolder, 1)
		else
			booksPerFolder[#booksPerFolder] = booksPerFolder[#booksPerFolder] + 1
		end
	end
end

-- Load the given book into memory
function loadBook(selectedBook)
	-- Reset variables
	text = nil

	-- Set the current book
	currentBookKey = selectedBook.name
	loadCurrentBookSettings()

	-- Read the book from the filesystem
	local file = playdate.file.open("books/" .. selectedBook.path)
	local sourceText = file:read(MAX_FILE_SIZE)
	assert(sourceText)
	text = preprocessText(sourceText)
end

-- Start or restart the reader application
function reloadReader()
	-- Set the scene
	scene = READER

	-- Reset variables
	offset = 0
	directionHeld = 0
	lines = {}
	emptyLinesAbove = 0
	skipSoundTicks = 0
	skipScrollTicks = 0
	previousCrankOffset = 0
	textProgress = 0

	-- Set up scrolling sound
	sound:setVolume(0)
	sound:playNote(850)

	-- Reset the crank position
	offset = 0

	-- Update the font
	graphics.setFont(FONTS[readerFontId].font)

	-- Calculate the line height
	if FONTS[readerFontId].height ~= nil then
		lineHeight = FONTS[readerFontId].height
	else
		lineHeight = graphics.getTextSize("A") * 1.6
	end

	if currentBookSettings ~= nil then
		-- Split the text into lines
		initializeLines(currentBookSettings.readIndex)
	end
end

-- Initialize the options menu, only needs to be called once as it is not a separate scene
function initMenu()
	for i = 1, #MENU_OPTIONS do
		local options = MENU_OPTIONS[i].options
		local gridview = playdate.ui.gridview.new(OPTIONS_WIDTH, 28)
		gridview:setNumberOfRows(1)
		gridview:setNumberOfColumns(#options)
		local initialValue = MENU_OPTIONS[i].initialValue()
		-- Need to select next column multiple times due to SDK limitations
		for j = 1, initialValue - 1 do
			gridview:selectNextColumn(false, true, false)
		end
		function gridview:drawCell(section, row, column, selected, x, y, width, height)
			if selected then
				if activeSetting == i then
					graphics.fillRoundRect(x, y, width, height, 4)
					graphics.setImageDrawMode(graphics.kDrawModeFillWhite)
				else
					graphics.drawRoundRect(x, y, width, height, 4)
				end
			end
			local fontHeight = graphics.getSystemFont():getHeight()
			graphics.setFont(graphics.getSystemFont())
			graphics.drawTextInRect(options[column], x, y + (height / 2 - fontHeight / 2) + 2, width, height, nil, nil, kTextAlignment.center)
		end
		optionViews[i] = gridview
	end
end

-- Scan the filesystem for books
function scanForBooks()
	-- Determine which folders are available
	local folders = {}
	-- Add the root folder
	insert(folders, "")
	-- Scan for folders
	local files = playdate.file.listFiles("books")
	for i = 1, #files do
		if playdate.file.isdir("books/" .. files[i]) then
			insert(folders, files[i])
		end
	end
	-- Add books from each folder
	local foundBooks = {}
	for i = 1, #folders do
		local folderBooks = addBooksFromFolder(folders[i])
		for j = 1, #folderBooks do
			insert(foundBooks, folderBooks[j])
		end
	end
	return foundBooks
end

function addBooksFromFolder(folderPath)
	local files = playdate.file.listFiles("books/" .. folderPath)
	local books = {}
	-- Filter out default books if necessary
	-- TODO: Determine if Lua has a better way to do this (i.e. a set)
	if not showDefaultBooks then
		for i = #files, 1, -1 do
			for j = 1, #DEFAULT_BOOKS do
				if files[i] == DEFAULT_BOOKS[j] then
					table.remove(files, i)
					break
				end
			end
		end
	end
	-- Filter files to only include those that end with .txt
	for i = #files, 1, -1 do
		if sub(files[i], #files[i] - 3) == ".txt" then
			-- It's a book
			local path = folderPath .. files[i]
			print("Found book: '" .. path .. "'")
			local name = sub(files[i], 1, #files[i] - 4)
			local folderKey = folderPath
			if folderKey == "" then
				folderKey = "root"
			end
			-- Remove trailing slash
			if sub(folderKey, #folderKey) == "/" then
				folderKey = sub(folderKey, 1, #folderKey - 1)
			end
			local book = {
				path = path,
				name = name,
				folder = folderKey,
			}
			insert(books, book)
		end
	end
	-- Sort alphabetically to ensure deterministic order
	table.sort(books, function (a, b)
		return a.name > b.name
	end)
	return books
end

-- Draw a candle to the side of the text to indicate progress
local drawCandle = function ()
	local TOP = textProgress * (DEVICE_HEIGHT - candleTop.height - 10 - candleHolder.height) + 4
	local LEFT = DEVICE_WIDTH - 1 - candleSection.width
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
	-- Draw the holder
	candleHolder:draw(LEFT, DEVICE_HEIGHT - candleHolder.height)
	-- Draw the drips
	local bottom = DEVICE_HEIGHT - candleDripLeft.height + 4 - candleHolder.height
	candleDripLeft:draw(LEFT, min(bottom, TOP + 40 + textProgress * 115))
	candleDripRight:draw(LEFT + candleSection.width - candleDripRight.width, min(bottom, TOP + 90 + textProgress * 20))
end

local drawScrollbar = function ()
	local VERT_MARGIN = 2
	local LEFT = DEVICE_WIDTH - 2 - scrollbarSection.width
	-- Draw the top arrow
	scrollbarButton:draw(LEFT, VERT_MARGIN)
	scrollbarArrow:draw(LEFT + 2, VERT_MARGIN + 2)
	-- Draw the scrollbar length
	for i = 1, 17 do
		scrollbarSection:draw(LEFT, VERT_MARGIN + scrollbarButton.height + (i - 1) * scrollbarSection.height)
	end
	-- Draw the bottom arrow
	scrollbarButton:draw(LEFT, DEVICE_HEIGHT - VERT_MARGIN - scrollbarButton.height)
	scrollbarArrow:draw(LEFT + 2, DEVICE_HEIGHT - VERT_MARGIN - scrollbarButton.height + 3, graphics.kImageFlippedY)
	-- Draw the slider
	local progress = textProgress
	if progress <= 0.01 then
		progress = 0
	elseif progress >= 0.99 then
		progress = 1
	end
	local sliderY = VERT_MARGIN + scrollbarButton.height + floor(progress * (DEVICE_HEIGHT - VERT_MARGIN * 2 - scrollbarButton.height * 2 - scrollbarSlider.height))
	scrollbarSlider:draw(LEFT + 1, sliderY)
end

-- Draw the reader application
local drawText = function ()
	graphics.clear()
	graphics.setFont(FONTS[readerFontId].font)
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
	if progressIndicator == 2 then
		drawCandle()
	elseif progressIndicator == 3 then
		drawScrollbar()
	end
end

-- Draw an individual book
local drawBook = function (x, y, title, progress, selected)
	graphics.setFont(FONTS[1].font)
	if selected then
		graphics.setImageDrawMode(graphics.kDrawModeInverted)
	end
	local MAX_TEXT_WIDTH = 200
	local cutOffText = title
	while graphics.getTextSize(cutOffText) > MAX_TEXT_WIDTH and #cutOffText > 0 do
		cutOffText = sub(cutOffText, 1, #cutOffText - 1)
	end
	local marginX = 30
	if cutOffText ~= title then
		cutOffText = cutOffText .. "..."
		marginX = 25
	end
	bookImage:draw(x, y)
	graphics.drawText(cutOffText, x + marginX, y + 40)
	if progress > 0.001 then
		-- Draw bookmark
		local bookmarkHeight = math.floor(progress * 10 + 0.5) * 3
		local bookmarkX = x + 250
		local bookmarkY = y + 30
		if selected then
			bookmarkBorderImage:draw(bookmarkX, bookmarkY + bookmarkHeight)
		else
			bookmarkImage:draw(bookmarkX, bookmarkY + bookmarkHeight)
		end
	end
	graphics.setImageDrawMode(graphics.kDrawModeCopy)
end

local easeOut = function(t)
	return 1 - (1 - t) * (1 - t)
end

local drawLibrary = function ()
	local libraryOffset = highlightedBookInFolder * BOOK_SEPARATION - 40 + highlightedBookScrollOffset
	graphics.clear()
	local bottom = DEVICE_HEIGHT - 103 + libraryOffset
	local separation = BOOK_SEPARATION
	-- Draw title
	titleAnimationProgress = min(1, titleAnimationProgress + 0.03)
	local titleOffset = -210 + easeOut(titleAnimationProgress) * 200
	local subtitleOffset = 240 - easeOut(titleAnimationProgress) * 250
	titleImage:draw(DEVICE_WIDTH / 2 - titleImage.width / 2, DEVICE_HEIGHT / 2 - titleImage.height / 2 + 0 + 0 + titleOffset)
	if highlightedBook == nil or highlightedBook < 2 then
		-- Only draw subtitle if the first book is selected to prevent it peeking over the top of the stack
		for i = 1, #subtitle do
			local width, height = graphics.getTextSize(subtitle[i])
			graphics.drawText(subtitle[i], DEVICE_WIDTH / 2 - width / 2, DEVICE_HEIGHT / 2 - height / 2 + 30 + 0 + 20 * i + subtitleOffset)
		end
	end
	-- The indices of each folder
	local folderIndices = {}
	-- The indices of the books within each folder
	local bookWithinFolderIndices = {}
	local folderCount = 0
	-- Draw books
	fallingBookProgress = fallingBookProgress + 20
	for i = 1, #availableBooks do
		local folder = availableBooks[i].folder
		if folderIndices[folder] == nil then
			folderIndices[folder] = folderCount
			bookWithinFolderIndices[folder] = 0
			folderCount = folderCount + 1
		end
		bookWithinFolderIndices[folder] = bookWithinFolderIndices[folder] + 1
		local index = bookWithinFolderIndices[folder]
		local x = 60
		if index % 2 == 0 then
			x = 80
		end
		x = x + FOLDER_SPACING * (folderIndices[folder] - folderIndex + 1) + folderIndexScrollOffset
		local fallingY = fallingBookProgress - separation * (index - 1) * 4
		local endY = bottom - separation * (index - 1)
		local y = min(endY, fallingY)
		-- if folderIndex == folderIndices[folder] and folderIndexScrollOffset == 0 then
		-- 	y = y - 10
		-- end
		local progress = 0
		if booksState[availableBooks[i].name] ~= nil and booksState[availableBooks[i].name].progress ~= nil then
			progress = booksState[availableBooks[i].name].progress
		end
		drawBook(x, y, availableBooks[i].name, progress, highlightedBook == i)
	end
	-- Draw folder label
	if folderCount > 1 then
		local folder = availableBooks[highlightedBook].folder
		if folder == "root" then
			folder = "library"
		end
		-- Capitalize first letter of each word
		folder = folder:gsub("(%a)([%w_']*)", function(first, rest)
			return first:upper() .. rest:lower()
		end)
		local width, height = graphics.getTextSize(folder)
		local labelX = DEVICE_WIDTH / 2 - width / 2
		local labelY = DEVICE_HEIGHT - 31 + libraryOffset - min(0, fallingBookProgress / 2 - bottom)
		graphics.fillRoundRect(labelX - 10, labelY + 2, width + 20, height - 2, 8)
		graphics.setImageDrawMode(graphics.kDrawModeInverted)
		graphics.drawText(folder, labelX, labelY)
		graphics.setImageDrawMode(graphics.kDrawModeCopy)
		local arrowSpacing = 25
		if folderIndex > 1 then
			folderArrow:draw(labelX - folderArrow.width - arrowSpacing, labelY + height / 2 - folderArrow.height / 2 + 1, graphics.kImageFlippedX)
		end
		if folderIndex < folderCount then
			folderArrow:draw(labelX + width + arrowSpacing, labelY + height / 2 - folderArrow.height / 2 + 1)
		end
	end
end

-- Scroll to the previous option in selected setting
function previousOption()
	optionViews[activeSetting]:selectPreviousColumn(true)
	local _, _, selCol = optionViews[activeSetting]:getSelection()
	MENU_OPTIONS[activeSetting].callback(selCol)
end

-- Scroll to the next option in the selected setting
function nextOption()
	optionViews[activeSetting]:selectNextColumn(true)
	local _, _, selCol = optionViews[activeSetting]:getSelection()
	MENU_OPTIONS[activeSetting].callback(selCol)
end

-- Scroll to the previous setting in the menu
function previousSetting()
	activeSetting = activeSetting - 1
	if activeSetting < 1 then
		activeSetting = #optionViews
	end
end

-- Scroll to the next setting in the menu
function nextSetting()
	activeSetting = activeSetting + 1
	if activeSetting > #optionViews then
		activeSetting = 1
	end
end

local drawMenu = function ()
	graphics.clear()
	local menuWidth = 280
	local optionRowHeight = 32
	local topMargin = DEVICE_HEIGHT / 2 - (#optionViews - 1) * optionRowHeight / 2 - 11
	for i = 1, #optionViews do
		graphics.setFont(graphics.getSystemFont())
		local label = MENU_OPTIONS[i].label
		graphics.drawText("*" .. label .. "*", (DEVICE_WIDTH - menuWidth) / 2, topMargin + (i - 1) * optionRowHeight + optionRowHeight / 2 - 11)
		local optionsX = (DEVICE_WIDTH - menuWidth) / 2 +  (menuWidth - OPTIONS_WIDTH)
		optionViews[i]:drawInRect(optionsX, topMargin + (i - 1) * optionRowHeight, OPTIONS_WIDTH, optionRowHeight)
	end
	graphics.setFont(FONTS[readerFontId].font)
	if playdate.buttonJustPressed(playdate.kButtonLeft) then
		previousOption()
	end
	if playdate.buttonJustPressed(playdate.kButtonRight) then
		nextOption()
	end
	if playdate.buttonJustPressed(playdate.kButtonUp) then
		previousSetting()
	end
	if playdate.buttonJustPressed(playdate.kButtonDown) then
		nextSetting()
	end
end

-- Update loop
function playdate.update()
	if scene == LIBRARY then
		local folderSwitched = false
		if playdate.buttonJustPressed(playdate.kButtonLeft) then
			if booksPerFolder[folderIndex - 1] == nil then
				return
			end
			local bookDifference = highlightedBookInFolder + math.max(0, booksPerFolder[folderIndex - 1] - highlightedBookInFolder)
			if bookDifference == nil then
				bookDifference = 0
			end
			offset = offset - BOOK_OFFSET_SIZE * bookDifference
			folderIndexScrollOffset = -FOLDER_SPACING
			folderSwitched = true
		end
		if playdate.buttonJustPressed(playdate.kButtonRight) then
			if booksPerFolder[folderIndex + 1] == nil then
				return
			end
			local bookDifference = booksPerFolder[folderIndex] - highlightedBookInFolder + math.min(highlightedBookInFolder, booksPerFolder[folderIndex + 1])
			offset = offset + BOOK_OFFSET_SIZE * bookDifference
			folderIndexScrollOffset = FOLDER_SPACING
			folderSwitched = true
		end

		local maxLibraryOffset = (#availableBooks - 0.45) * BOOK_OFFSET_SIZE
		offset = max(0, offset)
		offset = min(offset, maxLibraryOffset)
		local bookIndex = min(#availableBooks, floor(offset / BOOK_OFFSET_SIZE) + 1)
		if highlightedBook ~= nil then
			if folderSwitched then
				highlightedBookScrollOffset = 0
			elseif bookIndex < highlightedBook then
				highlightedBookScrollOffset = 30
			elseif bookIndex > highlightedBook then
				highlightedBookScrollOffset = -30
			end
		end
		highlightedBook = bookIndex
		if highlightedBookScrollOffset > 0 then
			highlightedBookScrollOffset = max(0, highlightedBookScrollOffset - 5)
		elseif highlightedBookScrollOffset < 0 then
			highlightedBookScrollOffset = min(0, highlightedBookScrollOffset + 5)
		end
		if folderIndexScrollOffset > 0 then
			folderIndexScrollOffset = max(0, folderIndexScrollOffset - 45)
		elseif folderIndexScrollOffset < 0 then
			folderIndexScrollOffset = min(0, folderIndexScrollOffset + 45)
		end
		local sum = 0
		for i = 1, #booksPerFolder do
			if sum + booksPerFolder[i] > highlightedBook - 1 then
				highlightedBookInFolder = highlightedBook - sum
				folderIndex = i
				break
			else
				sum = sum + booksPerFolder[i]
			end
		end
		drawLibrary()
	elseif scene == READER then
		drawText()
		-- Update offset when the D-pad is held
		offset = offset + directionHeld * BTN_SCROLL_SPEED
		if menuActive or not playScrollSound then
			sound:setVolume(0)
		else
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
	if menuActive then
		-- Draw menu over everything else
		drawMenu()
	end
	playdate.timer.updateTimers()
end

-- Initialize the first batch of lines
function initializeLines(startChar)
	local linesAdded = appendLines(20, startChar)
	prependLines(20 - linesAdded)
	emptyLinesAbove = 0
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

local function isStartOfChar(byte)
	-- Determine if a byte is an ASCII character or the start of a multi-byte UTF-8 character
	-- ASCII characters are 0xxxxxxx in binary, which is less than 128 in decimal
	-- The start of a multi-byte UTF-8 character is 110xxxxx or 1110xxxx or 11110xxx in binary, which is greater than or equal to 192 in decimal
	return byte < 128 or byte >= 192
end

local function isContinuationByte(byte)
	return byte >= 128 and byte < 192
end

local function getCharLength(byte)
	if byte < 192 then
		return 1
	elseif byte < 224 then
		return 2
	elseif byte < 240 then
		return 3
	elseif byte < 248 then
		return 4
	else
		return 1
	end
end

local function findStartOfChar(characters, index, direction)
	local i = index
	while i > 1 and i < #characters and not isStartOfChar(characters:byte(i)) do
		i = i + direction
	end
	if isStartOfChar(characters:byte(i)) then
		return i
	else
		return nil
	end
end

local function isCompleteChar(char)
	local firstByte = char:byte(1)
	if not isStartOfChar(firstByte) then
		return false
	end

	local charLength = getCharLength(firstByte)

	if #char ~= charLength then
		return false
	end

	for i = 2, charLength do
		if not isContinuationByte(char:byte(i)) then
			return false
		end
	end

	return true
end

local function stringToBinary(str)
	local result = ""
	for i = 1, #str do
		local byte = string.byte(str, i)
		local binary = ""
		for j = 7, 0, -1 do
			binary = binary .. tostring((byte >> j) & 1)
		end
		result = result .. binary .. " "
	end
	return result
end

local function isEndOfChar(characters, index)
	if isCompleteChar(sub(characters, index, index)) then
		return true
	end
	local i = index
	while i > 0 and not isStartOfChar(characters:byte(i)) do
		i = i - 1
	end
	if isStartOfChar(characters:byte(i)) then
		return getCharLength(characters:byte(i)) == index - i + 1
	else
		return false
	end
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
	local initialNumOfLines <const> = #lines
	-- Live number of lines
	local numOfLines = initialNumOfLines
	-- The length of the text in characters
	local textLength <const> = #text
	-- Index of the character currently being processed
	local byteIndex = 1
	-- Calculate the starting index
	if startChar then
		byteIndex = startChar
	elseif numOfLines > 0 then
		if append then
			byteIndex = lines[#lines].stop + 1
		else
			byteIndex = lines[1].start - 1
		end
	end
	if byteIndex < 1 or byteIndex > textLength then
		-- We are at the beginning or end of the text, no more lines can be added
		return 0
	end
	-- Determine if the start index is valid or needs to be repaired
	if append then
		-- When appending, the start index must be the start of a character
		if not isStartOfChar(sub(text, byteIndex, byteIndex):byte()) then
			local result = findStartOfChar(text, byteIndex, 1)
			if result then
				byteIndex = result
				print("Repaired start index while appending: " .. byteIndex)
			else
				-- If no start of character is found, the text is invalid
				print("Error: No start of character found while appending, text must be corrupted!")
				-- TODO: Handle this error
				return 0
			end
		end
	else
		-- When prepending, the start index must be the end of a character
		-- Get the index of the start of the character
		if not isEndOfChar(text, byteIndex) then
			local result = findStartOfChar(text, byteIndex, -1)
			if result then
				local oldIndex = byteIndex
				byteIndex = result + getCharLength(text:byte(result)) - 1
				print("Repaired start index while prepending: " .. byteIndex)
			else
				-- If no start of character is found, the text is invalid
				print("Error: No start of character found while prepending, text must be corrupted!")
				-- TODO: Handle this error
				return 0
			end
		end
	end

	-- The max width in pixels that a line can be
	local MAX_WIDTH <const> = DEVICE_WIDTH - leftMargin - rightMargin
	-- The text of the current line as it is processed
	local currentLine = ""
	-- The index of the first character of the current line
	local lineStart = byteIndex
	-- The index of the last character of the current line
	local lineStop = byteIndex
	-- Index within the line of the last space character in for word wrapping
	local lastSpace = nil
	-- Index within the text of the last space character
	local lastSpaceIndex = nil
	-- Size of the line in pixels
	local lineSize = 0
	-- Constants for calculating the size of characters
	local TEST_SIZE <const> = graphics.getTextSize("  ")
	local MIN_SIZE <const> = graphics.getTextSize("i")
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

	-- The character being built
	local char = ""
	local chunkCount = 0
	-- Add lines until the target number of lines is reached
	while numOfLines < initialNumOfLines + additionalLines do
		-- Determine if we are at the beginning or end of the text
		if byteIndex < 1 or byteIndex > textLength then
			if currentLine ~= "" then
				insertLine(currentLine, lineStart, lineStop)
			end
			break
		end
		local chunk = sub(text, byteIndex, byteIndex)
		if append then
			char = char .. chunk
		else
			char = chunk .. char
		end
		chunkCount = chunkCount + 1
		-- Check if the character is complete
		local charComplete <const> = isCompleteChar(char)
		if charComplete then
			-- Necessary hack for characters like comma and period
			local charSize = max(MIN_SIZE, graphics.getTextSize(" " .. char .. " ") - TEST_SIZE)
			if charSize == 1 and string.byte(char) > 10 then
				if append then
					print("Character is corrupt while appending: " .. stringToBinary(char))
				else
					print("Character is corrupt while prepending: " .. stringToBinary(char))
				end
			end
			local combined
			if append then
				combined = currentLine .. char
			else
				combined = char .. currentLine
			end
			if char == "\n" then
				-- Line is added to the list immediately to avoid reinserting the newline the next
				-- time this function is called
				if append then
					lineStop = byteIndex
				else
					lineStart = byteIndex
				end
				-- Newline is replaced with whitespace (at the end of the line to avoid printing)
				insertLine(currentLine .. " ", lineStart, lineStop)
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
					lastSpaceIndex = byteIndex
				end
				if append then
					lineStop = byteIndex
				else
					lineStart = byteIndex
				end
			end
			-- Reset the character
			char = ""
			chunkCount = 0
		end
		-- Iterate to the next byte
		if append then
			byteIndex = byteIndex + 1
		else
			byteIndex = byteIndex - 1
		end
	end
	return numOfLines - initialNumOfLines
end

-- Process the text to display better on the Playdate
function preprocessText(text)
	-- Remove tabs
	local newText = string.gsub(text, "	", "")
	-- Collapse multiple newlines into two
	newText = string.gsub(newText, "\n\n+", "\n\n")
	-- Replace CR + LF with LF
	newText = string.gsub(newText, "\r\n", "\n")
	-- Replace "–" with "-"
	newText = string.gsub(newText, "–", "-")
	return newText
end

function setInverted(darkMode)
	inverted = darkMode
	playdate.display.setInverted(inverted)
end

function setProgressIndicator(indicator)
	progressIndicator = indicator
	if progressIndicator == 1 then
		rightMargin = MARGIN_WITHOUT_BORDER
	else
		rightMargin = MARGIN_WITH_BORDER
	end
	reloadReader()
end

-- Register input callbacks
function playdate.cranked(change, acceleratedChange)
	-- print("cranked", change, acceleratedChange)
	if scene == LIBRARY then
		offset = offset - change * 0.6
	elseif scene == READER then
		if menuActive then
			local ticks = playdate.getCrankTicks(8)
			if ticks == 1 then
				nextSetting()
			elseif ticks == -1 then
				previousSetting()
			end
		else
			if skipScrollTicks > 0 then
				skipScrollTicks = skipScrollTicks - 1
				offset = offset - previousCrankOffset
			else
				offset = offset - change * CRANK_SCROLL_SPEED * crankSpeedModifier
				previousCrankOffset = change * CRANK_SCROLL_SPEED * crankSpeedModifier
			end
		end
	end
end

function playdate.upButtonDown()
	-- print("up")
	if scene == LIBRARY then
		offset = offset + BOOK_OFFSET_SIZE
	else
		if not menuActive then
			directionHeld = 1
		end
	end
end

function playdate.upButtonUp()
	directionHeld = 0
end

function playdate.downButtonDown()
	-- print("down")
	if scene == LIBRARY then
		offset = offset - BOOK_OFFSET_SIZE
	else
		if not menuActive then
			directionHeld = -1
		end
	end
end

function playdate.downButtonUp()
	directionHeld = 0
end

function playdate.leftButtonDown()
	-- print("left")
	if scene == READER then
		directionHeld = 6
	end
end

function playdate.leftButtonUp()
	directionHeld = 0
end

function playdate.rightButtonDown()
	-- print("right")
	if scene == READER then
		directionHeld = -6
	end
end

function playdate.rightButtonUp()
	directionHeld = 0
end

function playdate.AButtonDown()
	-- print("A")
	if scene == LIBRARY then
		if highlightedBook ~= nil then
			loadBook(availableBooks[highlightedBook])
			reloadReader()
		end
	elseif scene == READER then
		if not menuActive then
			saveState()
			menuActive = true
		else
			saveState()
			menuActive = false
		end
	end
end

function playdate.BButtonDown()
	-- print("B")
	-- setInverted(not inverted)
	if menuActive then
		saveState()
		menuActive = false
	elseif scene == READER then
		saveState()
		initLibrary()
	end
end

init()