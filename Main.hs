{-# LANGUAGE Arrows #-}
module Main where

import FRP.Yampa
import FRP.Yampa.Vector3
import FRP.Yampa.Utilities
import Graphics.UI.GLUT hiding (Level,Vector3(..),normalize)
import qualified Graphics.UI.GLUT as G(Vector3(..))

import Data.IORef
import Control.Arrow
import Data.Maybe
import Data.List

import GLAdapter

-- | Event Definition:

data Input = Keyboard { key       :: Key,
                        keyState  :: KeyState,
                        modifiers :: Modifiers }
-- | Rendering Code:

data Point3D = P3D { x :: Integer, y :: Integer, z :: Integer }
p3DtoV3 (P3D x y z) = vector3 (fromInteger x) (fromInteger y) (fromInteger z)

vectorApply f v = vector3 (f $ vector3X v) (f $ vector3Y v) (f $ vector3Z v)

data Level = Level { startingPoint :: Point3D, obstacles :: [Point3D] }

size :: Level -> Integer
size = (+1) . maximum . map (\(P3D x y z) -> maximum [x,y,z]) . obstacles

data GameState = Game { level     :: Level,
                        rotX      :: Double, 
                        rotY      :: Double, 
                        playerPos :: Vector3 Double }

type R = Double

-- TODO: List can't be empty!
testLevel = Level (P3D 0 0 1) [P3D 0 0 0, P3D 5 5 5, P3D 0 5 1, P3D 0 0 5]

-- | Helpful OpenGL constants for rotation
xAxis = G.Vector3 1 0 0 :: G.Vector3 R 
yAxis = G.Vector3 0 1 0 :: G.Vector3 R
zAxis = G.Vector3 0 0 1 :: G.Vector3 R 

initGL :: IO (Event Input)
initGL = do
    getArgsAndInitialize
    createWindow "AnaCube!"
    initialDisplayMode $= [ WithDepthBuffer ]
    depthFunc          $= Just Less
    clearColor         $= Color4 0 0 0 0
    light (Light 0)    $= Enabled
    lighting           $= Enabled 
    lightModelAmbient  $= Color4 0.5 0.5 0.5 1 
    diffuse (Light 0)  $= Color4 1 1 1 1
    blend              $= Enabled
    blendFunc          $= (SrcAlpha, OneMinusSrcAlpha) 
    colorMaterial      $= Just (FrontAndBack, AmbientAndDiffuse)
    reshapeCallback    $= Just resizeScene
    return NoEvent

renderGame :: GameState -> IO ()
renderGame (Game l rotX rotY pPos) = do
    loadIdentity
    translate $ G.Vector3 (0 :: R) 0 (-1.5*(fromInteger $ size l))
    rotate (rotX * 10) xAxis
    rotate (rotY * 10) yAxis
    color $ Color3 (1 :: R) 1 1
    position (Light 0) $= Vertex4 0 0 0 1  
    renderObject Wireframe (Cube $ fromInteger $ size l)
    renderPlayer pPos
    mapM_ (renderObstacle . p3DtoV3) $ obstacles l
    flush
    where size2 :: R
          size2 = (fromInteger $ size l)/2
          green = Color4 0.8 1.0 0.7 0.9 :: Color4 R
          red   = Color4 1.0 0.7 0.8 1.0 :: Color4 R 
          renderShapeAt s p = preservingMatrix $ do
            translate $ G.Vector3 (0.5 - size2 + vector3X p)
                                  (0.5 - size2 + vector3Y p)
                                  (0.5 - size2 + vector3Z p)
            renderObject Solid s
          renderObstacle = (color green >>) . (renderShapeAt $ Cube 1)
          renderPlayer   = (color red >>) . (renderShapeAt $ Sphere' 0.5 20 20)

keyDowns :: SF (Event Input) (Event Input)
keyDowns = arr $ filterE ((==Down) . keyState)

countHold :: SF (Event a) Integer
countHold = count >>> hold 0

game :: SF GameState (IO ())
game = arr $ (\gs -> do
        clear [ ColorBuffer, DepthBuffer ]
        renderGame gs
        flush)

data ParsedInput = 
    ParsedInput { ws :: Integer, as :: Integer, ss :: Integer, ds :: Integer,
                  upEvs :: Event Input, downEvs :: Event Input, 
                  rightEvs :: Event Input, leftEvs :: Event Input }
                        
-- | Input
parseInput :: SF (Event Input) ParsedInput
parseInput = proc i -> do
    down     <- keyDowns                        -< i
    ws       <- countKey 'w'                    -< down
    as       <- countKey 'a'                    -< down
    ss       <- countKey 's'                    -< down
    ds       <- countKey 'd'                    -< down
    upEvs    <- filterKey (SpecialKey KeyUp)    -< down
    downEvs  <- filterKey (SpecialKey KeyDown)  -< down
    rightEvs <- filterKey (SpecialKey KeyRight) -< down
    leftEvs  <- filterKey (SpecialKey KeyLeft)  -< down
    returnA -< ParsedInput ws as ss ds upEvs downEvs rightEvs leftEvs
    where countKey c  = filterE ((==(Char c)) . key) ^>> countHold
          filterKey k = arr $ filterE ((==k) . key)

-- | Logic
calculateState :: SF ParsedInput GameState
calculateState = proc pi@(ParsedInput ws as ss ds _ _ _ _) -> do
    rec speed <- selectSpeed -< (pi, pos, speed)
        pos   <- (integral :: SF (Vector3 Double) (Vector3 Double)) -< speed
 
    -- TODO: watch for leak on ws/as/ss/ds
    returnA -< Game { level     = levelChoice,
                      rotX      = (fromInteger $ (ws - ss)),
                      rotY      = (fromInteger $ (ds - as)),
                      playerPos = calculatePPos $ pos }

    where calculatePPos pos = pos ^+^ (p3DtoV3 $ startingPoint levelChoice) 
          collision obss (_,pos,speed) = 
            any (\obs -> norm ((calculatePPos pos) ^+^ (2 *^ speed)
                        ^-^ (p3DtoV3 obs)) <= 0.001) obss
          levelChoice = testLevel
          xAxis = vector3 1 0 0 
          yAxis = vector3 0 1 0
          zAxis = vector3 0 0 1
          v = 0.5

          boolToEvent = arr (\bool -> if bool then Event () else NoEvent)

          selectSpeed :: SF (ParsedInput, Vector3 Double, Vector3 Double) 
                            (Vector3 Double)
          selectSpeed = proc (pi, pos, speed) -> do
            speedC <- drSwitch (constant zeroVector) -< 
                (undefined, tagKeys (upEvs pi) speed ((-v) *^ zAxis) `merge` 
                            tagKeys (downEvs pi) speed (v *^ zAxis) `merge`
                            tagKeys (leftEvs pi) speed ((-v) *^ yAxis) `merge`
                            tagKeys (rightEvs pi) speed (v *^ yAxis))
            cols   <- collision (obstacles levelChoice) ^>> boolToEvent 
                        -< (pi, pos, speedC)
            speedf <- rSwitch (constant zeroVector) -< (speedC, tagCols cols) 
            returnA -< speedf
    
          tagKeys event speed vector
            | speed == zeroVector = event `tag` constant vector
            | otherwise           = NoEvent
          tagCols cols
            | isNoEvent cols  = Event identity
            | otherwise       = cols `tag` constant zeroVector

-- | Main, initializes Yampa and sets up reactimation loop
main :: IO ()
main = do
    newInput <- newIORef NoEvent
    rh <- reactInit initGL (\_ _ b -> b >> return False) 
                    (parseInput >>> calculateState >>> game)
    displayCallback $= return ()
    keyboardMouseCallback $= Just 
        (\k ks m _ -> writeIORef newInput (Event $ Keyboard k ks m))
    idleCallback $= Just (idle newInput rh) 
    mainLoop

-- | Reactimation iteration, supplying the input
idle :: IORef (Event Input) -> ReactHandle (Event Input) (IO ()) -> IO ()
idle newInput rh = do
    newInput' <- readIORef newInput
    react rh (1, Just newInput')
    return ()
    
