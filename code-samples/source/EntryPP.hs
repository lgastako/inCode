module Development.Blog.Util.EntryPP (readPreProcess) where

import "base" Prelude
import Config.SiteData
import Control.Applicative    ((*>))
import Control.Arrow          ((&&&))
import Control.Monad
import Data.Functor
import Data.Maybe             (fromMaybe)
import System.FilePath        ((</>))
import Text.Parsec
import Text.Parsec.Text
import Web.Blog.Render        (renderUrl')
import Web.Blog.Types
import qualified Data.Text    as T
import qualified Data.Text.IO as T

samplesDir :: FilePath
samplesDir = "code-samples"

readPreProcess :: FilePath -> IO String
readPreProcess entryFile = do
    eLines <- T.lines <$> T.readFile entryFile

    eLinesPP <- forM eLines $ \line ->
      if "!!!" `T.isPrefixOf` line
        then insertSample . T.strip . T.dropWhile (== '!') $ line
        else return line

    return . T.unpack . T.unlines $ eLinesPP

data SampleSpec = SampleSpec  { sSpecFile       :: FilePath
                              , _sSpecLive      :: Maybe String
                              , _sSpecKeywords  :: [(String,Maybe Int)]
                              } deriving (Show)

insertSample :: T.Text -> IO T.Text
insertSample sampline = do
    let spec' = runP sampleSpec () (T.unpack sampline) sampline

    case spec' of
        Left err    ->
            return $ T.pack (show err)
        Right spec  -> do
            rawSamp <- T.readFile (samplesDir </> sSpecFile spec)
            return $ processSample spec rawSamp

processSample :: SampleSpec -> T.Text -> T.Text
processSample (SampleSpec sFile sLive sKeys) rawSamp = processed
  where
    rawLines = T.lines rawSamp
    zipped = zip rawLines [1..]
    blocks =
      if null sKeys
        then
          return
            ( (snd . head &&& snd . last) zipped
            , T.unlines (map fst zipped)        )
        else
          map (uncurry (grabBlock zipped)) sKeys
    startLine = minimum . map (fst . fst) $ blocks
    endLine   = maximum . map (snd . fst) $ blocks
    sampCode  = T.unlines . map snd $ blocks
    toHeading key val = T.pack . concat $ ["-- ", key, ": ", val, "\n"]
    sourceHeading   =
      case sampleBlobs of
        Nothing -> ""
        Just blob ->
          let suffix  = concat ["#L",show startLine,"-",show endLine]
              suffix' = if null sKeys then "" else suffix
          in  toHeading
                "source"
                (blob </> sFile ++ suffix')
    interHeading =
      let maybeHeading = do
            inter <- interactiveUrl
            live <- sLive
            return $ toHeading "interactive" (inter </> live)
      in fromMaybe "" maybeHeading
    processed = T.concat [sourceHeading, interHeading, sampCode]


grabBlock :: [(T.Text,Int)] -> String -> Maybe Int -> ((Int,Int), T.Text)
grabBlock zipped key limit = grabbed
  where
    zDropped =
      dropWhile (not . (T.pack key `T.isInfixOf`) . fst) zipped
    (zHead,zRest) =
      span (\(l,_) -> not (T.null l)) zDropped
    zBlock        =
      takeWhile (\(l,_) -> T.null l || " " `T.isPrefixOf` l) zRest
    zBlock'       =
      reverse . dropWhile (T.null . fst) . reverse $ zBlock
    zAll =
      case limit of
        Just lim -> take lim zDropped
        Nothing  -> zHead ++ zBlock'
    startLine     = snd . head $ zAll
    endLine       = snd . last $ zAll
    sampCode      = T.unlines . map fst $ zAll
    grabbed = ((startLine, endLine), sampCode)

sampleBlobs :: Maybe String
sampleBlobs = do
    void $ siteDataPublicBlobs siteData
    return . T.unpack . renderUrl' . T.pack $ "/source" </> samplesDir

interactiveUrl :: Maybe String
interactiveUrl = T.unpack <$> siteDataInteractiveUrl siteData

sampleSpec :: Parser SampleSpec
sampleSpec = do
    filePath <- noSpaces <?> "sample filePath"
    spaces
    keywords <- many $ do
      keyword <- char '"' *> manyTill anyChar (char '"') <?> "keyword"
      keylimit <- optionMaybe (read <$> many1 digit <?> "keyword limit")
      spaces
      return (keyword,keylimit)

    live <- optionMaybe noSpaces <?> "live url"
    let
      live' = mfilter (not . null) live

    return $ SampleSpec filePath live' keywords
  where
    noSpaces = manyTill anyChar (space <|> ' ' <$ eof)
