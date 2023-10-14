local gfx = playdate.graphics
playdate.display.setRefreshRate(60)

gfx.setBackgroundColor(gfx.kColorWhite)
gfx.drawText("Lorem ipsum dolor sit amet, consectetur", 10, 25)
gfx.drawText("adipiscing elit, sed do eiusmod tempor", 10, 50)
gfx.drawText("incididunt ut labore et dolore magna aliqua.", 10, 75)

gfx.drawText("Lorem ipsum dolor sit amet, consectetur", 10, 125)
gfx.drawText("adipiscing elit, sed do eiusmod tempor", 10, 150)
gfx.drawText("incididunt ut labore et dolore magna aliqua.", 10, 175)

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