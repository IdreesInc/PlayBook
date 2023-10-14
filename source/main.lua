local graphics = playdate.graphics
-- 50 Hz is max refresh rate
playdate.display.setRefreshRate(50)

-- Read something from the filesystem

local file = playdate.file.open("test.txt")
local MAX_SIZE = 4 * 1024 * 1024;
local text = file:read(MAX_SIZE)
print(text)

-- Load the font
local font = graphics.font.new("fonts/Roobert-11-Medium")
assert(font)
graphics.setFont(font)

graphics.setBackgroundColor(graphics.kColorWhite)
graphics.drawText("Crank it up", 10, 0)
graphics.drawText("Lorem ipsum dolor sit amet, consectetur", 10, 25)
-- print(graphics.getTextSize("Lorem ipsum dolor sit amet, consectetur"))
graphics.drawText("adipiscing elit, sed do eiusmod tempor", 10, 50)
graphics.drawText("incididunt ut labore et dolore magna aliqua.", 10, 75)
graphics.drawText("---", 10, 100)
graphics.drawText("Lorem ipsum dolor sit amet, consectetur", 10, 125)
graphics.drawText("adipiscing elit, sed do eiusmod tempor", 10, 150)
graphics.drawText("incididunt ut labore et dolore magna aliqua.", 10, 175)

function playdate.update()
	-- Required for some reason
end

-- -- Callbacks
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