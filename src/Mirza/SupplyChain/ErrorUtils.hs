{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE MultiParamTypeClasses #-}
-- | This module contains the helper functions that are used in error handling
module Mirza.SupplyChain.ErrorUtils where

import           Mirza.SupplyChain.AppConfig         (AppError (..), AppM)
import           Mirza.SupplyChain.Errors            (ErrorCode, Expected (..),
                                                      Received (..),
                                                      ServerError (..),
                                                      ServiceError (..))
import qualified Mirza.SupplyChain.Model             as M
import qualified Mirza.SupplyChain.Utils             as U

import           Control.Monad.Except                (MonadError (..),
                                                      throwError)
import           Data.ByteString                     (ByteString)
import qualified Data.ByteString.Lazy.Char8          as LBSC8
import           Data.Text.Encoding                  (encodeUtf8)
import           Text.Printf                         (printf)

import           Data.GS1.EPC
import           Database.PostgreSQL.Simple.Internal (SqlError (..))
import           Servant.Server

-- | Takes in a ServiceError and converts it to an HTTP error (eg. err400)
appErrToHttpErr :: ServiceError -> Handler a
appErrToHttpErr (EmailExists _ (M.EmailAddress email)) =
  throwError $ err400 {
    errBody = LBSC8.fromChunks ["User email ", encodeUtf8 email, " exists."]
  }
appErrToHttpErr (InvalidKeyID _) =
  throwError $ err400 {
    errBody = "Invalid Key ID entered."
  }
appErrToHttpErr (InvalidSignature _) =
  throwError $ err400 {
    errBody = "Invalid Signature entered."
  }
appErrToHttpErr (InvalidEventID _) =
  throwError $ err400 {
    errBody = "No such event."
  }
appErrToHttpErr (InvalidUserID _) =
  throwError $ err400 {
    errBody = "No such user."
  }
appErrToHttpErr (InvalidRSAKey _) =
  throwError $ err400 {
    errBody = "Failed to parse RSA Public key."
  }
appErrToHttpErr (EventPermissionDenied _ _) =
  throwError $ err400 {
    errBody = "User not associated with the event."
  }
appErrToHttpErr (InvalidRSAKeySize (Expected (U.Byte expSize)) (Received (U.Byte recSize))) =
  throwError $ err400 {
    errBody = LBSC8.pack $ printf "Invalid RSA Key size. Expected: %d, Received: %d\n" expSize recSize
  }
appErrToHttpErr (InvalidDigest _) =
  throwError $ err400 {
    errBody = "Invalid Key ID entered."
  }
appErrToHttpErr (ParseError err) =
  throwError $ err400 {
    errBody = LBSC8.append
                  "We could not parse the input provided. Error(s) encountered"
                  (parseFailureToErrorMsg err)
    -- TODO: ^ Add more information on what's wrong?
  }
appErrToHttpErr (AuthFailed _) =
  throwError $ err403 { errBody = "Authentication failed. Invalid username or password." }
appErrToHttpErr (UserNotFound (M.EmailAddress _email)) =
  throwError $ err404 { errBody = "User not found." }
appErrToHttpErr (EmailNotFound (M.EmailAddress _email)) =
  throwError $ err404 { errBody = "User not found." }
appErrToHttpErr (InvalidRSAKeyInDB _) = generic500err
appErrToHttpErr (InsertionFail _ _email) = generic500err
appErrToHttpErr (BlockchainSendFailed _) = generic500err
appErrToHttpErr (BackendErr _) = generic500err
appErrToHttpErr (DatabaseError _) = generic500err
-- TODO: The above error messages may need to be more descriptive

generic500err :: Handler a
generic500err = throwError err500 {errBody = "Something went wrong"}

throw500Err :: MonadError ServantErr m => LBSC8.ByteString -> m a
throw500Err bdy = throwError err500 {errBody = bdy}

-- TODO: Some of these might benefit from HasCallStack constraints

-- | Takes in a function that can extract errorcode out of an error, the error
-- itself and constructs a ``ServerError`` with it
toServerError :: Show a => (a -> Maybe ErrorCode) -> a -> ServerError
toServerError f e = ServerError (f e) (U.toText e)

-- | Shorthand for ``toServerError``.
-- Use if you can't think of a function to extract the error code
defaultToServerError :: Show a => a -> ServerError
defaultToServerError = toServerError (const Nothing)

-- | Shorthand for only SqlError types
sqlToServerError :: SqlError -> ServiceError
sqlToServerError = DatabaseError -- toServerError getSqlErrorCode

-- | Shorthand for throwing a Generic Backend error
throwBackendError :: (Show a, MonadError AppError m) => a -> m b
throwBackendError er = throwAppError $ BackendErr $ U.toText er

-- | Shorthand for throwing AppErrors
-- Added because we were doing a lot of it
throwAppError :: MonadError AppError m => ServiceError -> m a
throwAppError = throwError . AppError

-- | Extracts error code from an ``SqlError``
getSqlErrorCode :: SqlError -> Maybe ByteString
getSqlErrorCode e@SqlError{} = Just $ sqlState e

throwParseError :: ParseFailure -> AppM a
throwParseError = throwAppError . ParseError


parseFailureToErrorMsg :: ParseFailure -> LBSC8.ByteString
-- TODO: Include XML Snippet in the error
parseFailureToErrorMsg InvalidLength = "The length of one of your URN's is not correct"
parseFailureToErrorMsg InvalidFormat = "Incorrectly formatted XML. Possible Causes: \
                                      \ Some components of the URN missing,\
                                      \Incorrectly structured, Wrong payload"
parseFailureToErrorMsg InvalidAction = "Could not parse the Action provided"
parseFailureToErrorMsg InvalidBizTransaction = "Could not parse business transaction"
parseFailureToErrorMsg InvalidEvent = "Could not parse the event supplied"
parseFailureToErrorMsg TimeZoneError = "There was an error in parsing the timezone"
parseFailureToErrorMsg TagNotFound = "One or more required tags missing"
parseFailureToErrorMsg InvalidDispBizCombination = "The combination of Disposition\
                                                  \ and Business Transaction is incorrect"
-- TODO: map parseFailureToErrorMsg <all_failures> joined by "\n"
parseFailureToErrorMsg (ChildFailure _) = "Encountered several errors while parsing the data provided."
