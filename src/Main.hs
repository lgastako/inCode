{-# LANGUAGE OverloadedStrings #-}

-- import Control.Monad.IO.Class
-- import Debug.Trace
-- import Network.Wai
-- import Web.Blog.Database
import Config.SiteData
import Control.Applicative                  ((<$>))
import Data.ByteString                      (ByteString, isPrefixOf)
import Development.Blog.Util
import Network.Wai                          (rawPathInfo)
import Network.Wai.Middleware.Cache
import Network.Wai.Middleware.Headers
import Network.Wai.Middleware.RequestLogger
import Network.Wai.Middleware.Static
import System.Environment                   (getEnv)
import Web.Blog.Routes
import Web.Blog.Types
import Web.Scotty
import qualified Data.IntMap                as IM

main :: IO ()
main = do
  startupHelpers

  port <- case hostConfigPort $ siteDataHostConfig siteData of
    Just p' -> return p'
    Nothing -> read <$> getEnv "PORT"

  scotty port $ do

    middleware logStdoutDev
    -- middleware $ addHeaders [("Cache-Control","max-age=86400")]
    middleware headerETag
    middleware $ cache cacheBackend
    middleware $ staticPolicy (noDots >-> addBase "static")
    middleware $ staticPolicy (noDots >-> addBase "tmp/static")
    middleware $ addHeaders [("Cache-Control","max-age=900")]

    route $ SiteDatabase IM.empty IM.empty IM.empty IM.empty

cacheBackend :: CacheBackend
cacheBackend app req =
  case lookupETag req of
    Just _  ->
      if anyPrefixes toCache && not (anyPrefixes toNotCache)
        then
          return Nothing
        else
          Just <$> app req
    Nothing -> Just <$> app req
  where
    anyPrefixes = any (`isPrefixOf` rawPathInfo req)

toCache :: [ByteString]
toCache = [
    "/css"
  , "/favicon.ico"
  , "/font"
  , "/img"
  , "/js"
  , "/robots.txt"
  ]

toNotCache :: [ByteString]
toNotCache = [ "/img/entries" ]

