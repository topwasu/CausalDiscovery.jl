module WaterPlug exposing (..)

-- import Render exposing (..)
import Engine exposing (..)
import Color
import Random
import Update exposing (..)

--Vase
drawVase = (2, 0)
drawPlug = (6, 0)
drawWater = (10,0)
startPos = (14, 0)
startButton = ObjectTag (Box startPos 0 0 Color.black)
buttons = [vaseSpot drawVase, plugSpot drawPlug, waterSpot drawWater, startButton]

mode = 1

modeTransition (x, y) prevMode =
  if (x, y) == drawVase then
    1
  else if (x, y) == drawPlug then
    2
  else if (x, y) == drawWater then
    3
  else if (x, y) == startPos then
    4
  else
    prevMode
vasePositions = []
--vasePositions = [(7, 15), (8, 15), (6, 15), (9, 15), (6, 14), (9, 14), (10, 14),
                        --(5, 14), (5, 13), (10, 13), (4, 13), (11, 13), (4, 12), (11, 12), (4, 11), (11, 11)]
vaseSpot (x, y) = ObjectTag (Box (x, y) 0 0 Color.purple)
makeVase vPositions = List.map vaseSpot vPositions

addToVase (x, y) currentMode =
  if currentMode /= 1 then
    []
  else if y<2 then
    []
  else
    [(x, y)]

addToPlug (x, y) currentMode =
  if currentMode /= 2 then
    []
  else if y < 2 then
    []
  else
    [(x, y)]

addToWater (x, y) currentMode =
  if currentMode /= 3 then
    []
  else if y < 2 then
    []
  else
    [(x, y)]

--Water
waterPositions = []
--waterPositions = [(5, 12), (6, 12), (7, 12), (8, 12), (9, 12), (10, 12), (5, 11), (6, 11), (7, 11), (8, 11), (9, 11), (10, 11)]
waterSpot (x, y) = ObjectTag (Box (x, y) 0 0 Color.blue)
makeWater wPositions = List.map waterSpot wPositions

waterMove (x, y) vase water left =
  let
    moveDown = List.any (\input -> (x, y+1) == input) (vase ++ water) || (y+1 > 15)
    moveRight = List.any (\input -> (x+1, y) == input) (vase ++ water) || ((x + 1) > 15) || (List.any (\input -> (x+1, y-1) == input) water)
    moveLeft = List.any (\input -> (x-1, y) == input) (vase ++ water) || ((x - 1) < 0) || (List.any (\input -> (x-1, y-1) == input) water)
  in
    if not (moveDown==True) then
      (x, y+1)
    else if not moveRight && not left then
      (x+1, y)
    else if not moveLeft && left then
      (x-1, y)
    else
      (x, y)
--Plug
plugPositions = []
--plugPositions = [(7, 14), (8, 14), (6, 13), (7, 13), (8, 13), (9, 13)]
plugSpot (x, y) = ObjectTag (Box (x, y) 0 0 Color.orange)
makePlug pPositions = List.map plugSpot pPositions

gasPumpPressed computer = computer.mouse.click
getX computer = round (computer.mouse.x/25 - 0.5)
getY computer = round (computer.mouse.y/25 - 0.5)

update computer {objects, latent} =
  let
    newMode = modeTransition (getX computer, getY computer) latent.varMode
    removePlug = (newMode == 4)    --pressedAndEmpty = gasPumpPressed computer && latent.plugPos == []
    newPlug = if removePlug then [] else if gasPumpPressed computer then latent.plugPos ++ (addToPlug (getX computer, getY computer) newMode) else latent.plugPos
    newVase = if gasPumpPressed computer then latent.vasePos ++ (addToVase (getX computer, getY computer) newMode) else latent.vasePos
    tempWater = if gasPumpPressed computer then latent.waterPos ++ (addToWater (getX computer, getY computer) newMode) else latent.waterPos
    newWater =  (List.map (\(x, y) -> waterMove (x, y) (newVase ++ newPlug) tempWater latent.left) tempWater)    --newWater = if pressedAndEmpty then nextWater latent.vaseNumber else (List.map (\(x, y) -> waterMove (x, y) (newVase ++ newPlug) latent.waterPos latent.left) latent.waterPos)
    newScene: Scene
    newScene = (buttons) ++ (makeVase newVase) ++ (makePlug newPlug) ++ (makeWater newWater)

  in

  {
    --objects = newScene, latent = latent
    objects = newScene, latent = {varMode = newMode, vasePos = newVase, waterPos = newWater, plugPos = newPlug, left = not latent.left}
  }


main = pomdp {objects = (buttons) ++ (makeVase vasePositions) ++ (makePlug plugPositions) ++ (makeWater waterPositions), latent = {varMode = mode, plugPos = plugPositions, waterPos = waterPositions, vasePos = vasePositions, left = True}} update
