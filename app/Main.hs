{-# LANGUAGE OverloadedStrings     #-}
module Main where

import           Lib
import           Migrate
import           Data.ByteString (ByteString)
import           Migrate (defConnectionStr)
import           Options.Applicative
import           Data.Semigroup ((<>))
import           AppConfig (EnvType(..))
import           Data.GS1.Parser.Parser
import           Data.Aeson.Encode.Pretty
import           Data.GS1.Event
import           Data.Either
import           Text.XML
import           Text.XML.Cursor
import qualified Data.Text.Lazy.IO as TL
import qualified Data.Text.Lazy.Encoding as TLE
import           System.Environment


data ServerOptions = ServerOptions
  { env           :: EnvType
  , initDB        :: Bool
--  , clearDB       :: Bool
  , connectionStr :: ByteString
  , port          :: Int
  , uiFlavour     :: UIFlavour
  }

serverOptions :: Parser ServerOptions
serverOptions = ServerOptions
      <$> option auto
          ( long "env"
         <> short 'e'
         <> help "Environment, Dev | Prod"
         <> showDefault
         <> value Dev )
      <*> switch
          ( long "init-db"
         <> short 'i'
         <> help "Put empty tables into a fresh database" )
    --   <*> switch
    --       ( long "clear-db"
    --      <> short 'e'
    --      <> help "Erase the database - DROP ALL TABLES" )
      <*> option auto
          ( long "conn"
         <> short 'c'
         <> help "database connection string"
         <> showDefault
         <> value defConnectionStr)
       <*> option auto
          ( long "port"
         <> help "Port to run database on"
         <> showDefault
         <> value 8000)
       <*> option auto
          ( long "uiFlavour"
         <> help "Use jensoleg or Original UI Flavour for the Swagger API"
         <> showDefault
         <> value Original)


main :: IO ()
main = runProgram =<< execParser opts
  where
    opts = info (serverOptions <**> helper)
      (fullDesc
      <> progDesc "Run a supply chain server"
      <> header "SupplyChainServer - A server for capturing GS1 events and recording them on a blockchain")


-- Sara's
-- runProgram :: ServerOptions -> IO ()
-- runProgram (ServerOptions isDebug False _connStr portNum flavour) =
--     startApp connStr isDebug (fromIntegral portNum) flavour
-- runProgram (ServerOptions _ _ True connStr portNum flavour) =
--     startApp connStr isDebug (fromIntegral portNum) flavour
-- runProgram _ = migrate defConnectionStr
runProgram :: ServerOptions -> IO ()
runProgram (ServerOptions envT False connStr portNum flavour) =
    startApp connStr envT (fromIntegral portNum) flavour
runProgram _ = runMonkeyPatch
-- runProgram _ = migrate defConnectionStr

fileToParse :: FilePath
fileToParse = "../GS1Combinators/test/test-xml/ObjectEvent.xml"

runMonkeyPatch = do
  doc <- Text.XML.readFile def fileToParse
  let mainCursor = fromDocument doc
  -- scope for optimization: only call parseEventByType on existent EventTypes
      allParsedEvents =
        filter (not . null) $ concat $
        parseEventByType mainCursor <$> allEventTypes
      objEvent = head allParsedEvents

  print objEvent
  -- mapM_ (TL.putStrLn . TLE.decodeUtf8 . encodePretty) (rights allParsedEvents)


-- eventToNewObject :: Event -> M.NewObject


