{-# LANGUAGE MultiParamTypeClasses #-}

module Mirza.SupplyChain.Handlers.Users
  (
    newUser, userTableToModel, searchUserByCompanyId
  ) where


import           Mirza.Common.Utils
import           Mirza.SupplyChain.Database.Schema        as Schema
import           Mirza.SupplyChain.ErrorUtils             (getSqlErrorCode,
                                                           throwBackendError,
                                                           toServerError)
import           Mirza.SupplyChain.Handlers.Common
import           Mirza.SupplyChain.QueryUtils
import           Mirza.SupplyChain.Types                  hiding (NewUser (..),
                                                           User (userId))
import qualified Mirza.SupplyChain.Types                  as ST

import           Data.GS1.EPC                             (GS1CompanyPrefix (..))

import           Database.Beam                            as B
import           Database.Beam.Backend.SQL.BeamExtensions
import           Database.PostgreSQL.Simple.Errors        (ConstraintViolation (..),
                                                           constraintViolation)
import           Database.PostgreSQL.Simple.Internal      (SqlError (..))

import qualified Crypto.Scrypt                            as Scrypt

import           Control.Lens                             (view, (^?), _2)
import           Control.Monad.Except                     (MonadError,
                                                           throwError)
import           Control.Monad.IO.Class                   (liftIO)
import           Data.Text.Encoding                       (encodeUtf8)

newUser :: (SCSApp context err, HasScryptParams context)
        => ST.NewUser
        -> AppM context err ST.UserId
newUser = runDb . newUserQuery


-- | Hashes the password of the ST.NewUser and inserts the user into the database
newUserQuery :: (AsServiceError err, HasScryptParams context)
             => ST.NewUser
             -> DB context err ST.UserId
newUserQuery (ST.NewUser phone (EmailAddress email) firstName lastName biz password) = do
  params <- view $ _2 . scryptParams
  encPass <- liftIO $ Scrypt.encryptPassIO params (Scrypt.Pass $ encodeUtf8 password)
  userId <- newUUID
  -- TODO: use Database.Beam.Backend.SQL.runReturningOne?
  res <- handleError errHandler $ pg $ runInsertReturningList (Schema._users Schema.supplyChainDb) $
    insertValues
      [Schema.User userId (Schema.BizId  biz) firstName lastName
               phone (Scrypt.getEncryptedPass encPass) email
      ]
  case res of
        [r] -> return . ST.UserId . Schema.user_id $ r
        -- TODO: Have a proper error response
        _   -> throwBackendError res
  where
    errHandler :: (AsServiceError err, MonadError err m) => err -> m a
    errHandler e = case e ^? _DatabaseError of
      Nothing -> throwError e
      Just sqlErr -> case constraintViolation sqlErr of
        Just (UniqueViolation "users_email_address_key")
          -> throwing _EmailExists (toServerError getSqlErrorCode sqlErr, EmailAddress email)
        _ -> throwing _InsertionFail (toServerError (Just . sqlState) sqlErr, email)


searchUserByCompanyId :: SCSApp context err
                      => ST.User
                      -> GS1CompanyPrefix
                      -> AppM context err (Maybe ST.User)
searchUserByCompanyId _ = runDb . searchUserByCompanyIdQuery


searchUserByCompanyIdQuery :: SCSApp context err
                           => GS1CompanyPrefix
                           -> DB context err (Maybe ST.User)
searchUserByCompanyIdQuery pfx = do
  r <- pg $ runSelectReturningList $ select $ do
          user <- all_ (Schema._users Schema.supplyChainDb)
          guard_ (user_biz_id user ==. (BizId $ val_ pfx))
          pure user
  case r of
    [user] -> return $ Just $ userTableToModel user
    _      -> return Nothing

