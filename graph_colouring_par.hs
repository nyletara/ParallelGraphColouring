import qualified Data.Map as Map
import System.Exit(die)
import System.IO(Handle, hIsEOF, hGetLine, withFile, IOMode(ReadMode))
import System.Environment(getArgs, getProgName)
import Control.Parallel.Strategies
import qualified Data.List as List

-- resources:
-- https://stackoverflow.com/questions/4978578/how-to-split-a-string-in-haskell
-- https://hackage.haskell.org/package/containers-0.4.2.0/docs/Data-Map.html#g:5
-- http://ijmcs.future-in-tech.net/11.1/R-Anderson.pdf

type Node = String
type Color = Int
type AdjList = [Node]
type Graph = Map.Map(Node) (AdjList, Color)
-- ghci> import System.IO(stdin)
-- ghci> readGraphLine stdin Map.empty
-- A:B,C,D

-- stack ghc -- --make -Wall -O graph_colouring.hs
-- ./graph_colouring samples/CLIQUE_300_3.3color 3
main :: IO ()
main = do
  args <- getArgs
  case args of
    [graph_file, number_colours] -> do
      let colours = read number_colours
      g <- readGraphFile graph_file
      let output = colorGraph (Map.keys g) [1..colours] g
      print $ getColors (Map.keys output) output
      let result = isValidGraph $ output

      if result then do 
        putStrLn "Successfully coloured graph"
        writeFile "out" ("true\n")
      else do 
        putStrLn "Unable to colour graph"
        writeFile "out" ("false\n")

    _ -> do 
        pn <- getProgName
        die $ "Usage: " ++ pn ++ " <graph-filename> <number-of-colors>"

readGraphLine :: Handle -> Graph -> IO Graph
readGraphLine handle g = do args  <- (wordsWhen (==':')) <$> hGetLine handle
                            case args of
                              [node, adj] -> return $ Map.insert node (readAdjList adj, 0) g
                              _           -> return g                          

-- construct a graph from input file
-- g <- readGraphFile "samples/CLIQUE_300_3.3color"
readGraphFile :: String -> IO Graph
readGraphFile filename  = withFile filename ReadMode $ \handle -> loop handle readGraphLine Map.empty

loop :: Handle -> (Handle -> Graph -> IO Graph) -> Graph -> IO Graph
loop h f g = do 
              outgraph <- f h g
              eof <- hIsEOF h
              if eof then do return outgraph
              else do (loop h f outgraph) >>= (\y -> return y)

wordsWhen :: (Char -> Bool) -> String -> [String]
wordsWhen p s = case dropWhile p s of
                    "" -> []
                    s' -> w : wordsWhen p s''
                         where (w, s'') = break p s'

readAdjList :: String ->  AdjList
readAdjList x = wordsWhen (==',') x

-- color of a vertex
-- e.g. color "A" g
getColor :: Node -> Graph -> Color
getColor n g = case Map.lookup n g of
                 Just v -> (snd v)
                 Nothing -> 0

-- given a list of nodes and a graph, retrieve all colour assignments to the node
getColors :: [Node] -> Graph -> [Color]
getColors [] _ = []
getColors (x:xs) g = getColor x g : getColors xs g

-- gets all neighbors for a node in a graph
getNeighbors :: Node -> Graph -> AdjList
getNeighbors n g = case Map.lookup n g of
                 Just v -> (fst v)
                 Nothing -> []

-- assings a colour to a single node in the graph
setColor :: Graph -> Node -> Color -> Graph
setColor g n c = case Map.lookup n g of
                  Just v -> Map.insert n ((fst v), c) g
                  Nothing -> g

setColors :: Graph -> [Node] -> Color -> Graph
setColors g [] _ = g
setColors g [n] c = setColor g n c
setColors g (n:ns) c = setColors (setColor g n c) ns c

-- assigns a colour to each node in the graph
-- e.g. colorGraph (Map.keys g) [1,2,3,4] g
colorGraph :: [Node] -> [Color] -> Graph -> Graph
colorGraph _ [] g = g
colorGraph [] _ g = g
colorGraph (n:ns) colors g
  | allVerticesColored g = g
  | otherwise = 
      if nodeColor > 0 then do
        colorGraph ns colors $ setColor g n nodeColor
      else do
        error "can't color graph"
      where nodeColor = colorNode n colors g

colorGraphPar :: [Node] -> [Color] -> Graph -> Graph
colorGraphPar _ [] g = g
colorGraphPar [] _ g = g
colorGraphPar [n] colors g
  | allVerticesColored g = g
  | otherwise = 
      if nodeColor > 0 then do
          setColor g n nodeColor
      else do
          error "can't color graph"
      where nodeColor = colorNode n colors g
colorGraphPar nodes colors g
  | allVerticesColored g = g
  | otherwise = runEval $ do
    front <- rpar $ colorGraphPar first colors $ subGraph first g Map.empty
    back <- rpar $ colorGraphPar second colors $ subGraph second g Map.empty
    let join  = Map.union front back
    return $ merge (Map.keys join) colors join
    where first = take ((length nodes) `div` 2) nodes
          second = drop ((length nodes) `div` 2) nodes

merge :: [Node] -> [Color] -> Graph -> Graph
merge [] _ g = g
merge [x] colors g = setColors g (findClashingNodes x g) $ head updateColors 
  where updateColors = filter (validColor x g) colors
merge (x:xs) colors g = merge xs colors $ setColors g (findClashingNodes x g) $ head updateColors
  where updateColors = filter (validColor x g) colors

findClashingNodes :: Node -> Graph -> [Node]
findClashingNodes n g = [ x | x <- (getNeighbors n g), (getColor n g) == (getColor x g) ]

subGraph :: [Node] -> Graph -> Graph -> Graph 
subGraph [] _ x = x
subGraph [n] g x = Map.union x (Map.insert n ((getNeighbors n g), (getColor n g)) x)
subGraph (n:ns) g x = subGraph ns g (Map.union x (Map.insert n ((getNeighbors n g), (getColor n g)) x))

colorNode :: Node -> [Color] -> Graph -> Color
colorNode n c g | ncolors == length c = 0
                | otherwise = ncolors + 1
                where ncolors = length $ colorNodePar n c g

colorNodePar :: Node -> [Color] -> Graph -> [Bool]
colorNodePar n c g = takeWhile (\x -> not x) [ x | x <- map (validColor n g) c `using` parList rpar]

-- checks if all vertices have been coloured
-- e.g. allVerticesColored g
allVerticesColored :: Graph -> Bool
allVerticesColored g = 0 `notElem` getColors (Map.keys g) g

isValidGraph :: Graph -> Bool
isValidGraph g = isValidGraphPar (Map.keys g) g

isValidGraphPar :: [Node] -> Graph -> Bool
isValidGraphPar [] _ = False
isValidGraphPar [n] g = getColor n g `notElem` getColors (getNeighbors n g) g
isValidGraphPar nodes g = runEval $ do
    front <- rpar $ isValidGraphPar first g
    back <- rpar $ isValidGraphPar second g
    return $ front && back
  where first = take ((length nodes) `div` 2) nodes
        second = drop ((length nodes) `div` 2) nodes

validColor :: Node -> Graph -> Color -> Bool
validColor n g c = c `notElem` getColors (getNeighbors n g) g


