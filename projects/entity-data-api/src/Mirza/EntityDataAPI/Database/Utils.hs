{-# LANGUAGE LambdaCase          #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# OPTIONS_GHC -fno-warn-orphans  #-}

module Mirza.EntityDataAPI.Database.Utils where

import           Database.PostgreSQL.Simple           as DB
import           Database.PostgreSQL.Simple.FromField (FromField (..),
                                                       returnError)
import           Database.PostgreSQL.Simple.ToField   (ToField (..))

import           Mirza.EntityDataAPI.Errors           (AppError (..),
                                                       DBError (..))
import           Mirza.EntityDataAPI.Types

import           Crypto.JWT                           (StringOrURI)

import qualified Control.Exception                    as E

import           Control.Monad.Except                 (throwError)
import           Control.Monad.Reader                 (asks, liftIO)

import           Data.Pool                            (withResource)

import           Data.Aeson

import qualified Data.Text                            as T

doesSubExist :: StringOrURI -> AppM EDAPIContext AppError Bool
doesSubExist s = runDb $ \conn -> do
    [Only cnt]  <- query conn "SELECT COUNT(*) FROM users WHERE user_sub = ?" [s] :: IO [Only Integer]
    case cnt of
      1 -> pure True
      _ -> pure False

runDb :: (Connection -> IO a) -> AppM EDAPIContext AppError a
runDb act = do
  pool <- asks dbConnPool
  res <- liftIO $ withResource pool $ \conn ->
          E.try $ withTransaction conn $ act conn
  case res of
    Left (err :: SqlError) -> throwError . DatabaseError . SqlErr $ err
    Right lol              -> pure lol


instance ToField StringOrURI where
  toField = toField . unpackStringOrURI

instance FromField StringOrURI where
  fromField f bs = fromField f bs >>= \case
    Nothing -> returnError ConversionFailed f "Could not read value for StringOrURI"
    Just val -> pure val

unpackStringOrURI :: StringOrURI -> String
unpackStringOrURI sUri =
  let (String str) = toJSON sUri
    in T.unpack str

addUserSub :: StringOrURI -> StringOrURI -> AppM EDAPIContext AppError ()
addUserSub existingUser toAddUser =
  doesSubExist existingUser >>= \case
    False -> throwError . DatabaseError $ UnauthorisedInsertionAttempt existingUser
    True -> addUser toAddUser

addUser :: StringOrURI -> AppM EDAPIContext AppError ()
addUser toAddUser = do
  res <- runDb $ \conn -> DB.execute conn "INSERT INTO users (user_sub) values (?)" [toAddUser]
  case res of
    1 -> pure ()
    _ -> throwError . DatabaseError $ InsertionFailed
