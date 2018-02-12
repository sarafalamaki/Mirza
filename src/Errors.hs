{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DeriveGeneric     #-}

module Errors where

import qualified Model as M
import           GHC.Generics (Generic)
import qualified Data.Text as T
import qualified Data.ByteString as BS

type ErrorText = T.Text
type ErrorCode = BS.ByteString

data ServerError = ServerError (Maybe ErrorCode) ErrorText
                   deriving (Show, Read)

-- | A sum type of errors that may occur in the Service layer
data ServiceError = NeedMoreSignatures ServerError T.Text
                  | InvalidSignature ServerError BS.ByteString
                  | BlockchainSendFailed ServerError
                  | InvalidEventID ServerError Int
                  | InvalidKeyID M.KeyID
                  | InvalidUserID M.UserID
                  | InsertionFail ServerError T.Text
                  | EmailExists ServerError M.Email
                  | EmailNotFound M.Email
                  | UnexpectedDBResponse ServerError
                  | AuthFailed  M.Email
                  | UserNotFound M.Email
                  | BackendErr -- fallback
                  deriving (Show, Read, Generic)

{-
Do not remove the following commented out code until explicitly asked to
They serve as reference to what the errors used to be before they
were merged into ``ServiceError``
-}
-- -- Interface for converting custom errors to ServantErr
-- class AppServantError err where
--   toServantErr :: err -> ServantErr

-- data SigError = SE_NeedMoreSignatures T.Text
--               | SE_InvalidSignature BS.ByteString
--               | SE_InvalidUser T.Text
--               | SE_BlockchainSendFailed
--               | SE_InvalidEventID Int
--               | SE_InvalidKeyID
--               deriving (Show, Read, Generic)

-- instance AppServantError SigError where
--   toServantErr e = err500 {errBody = LBSC8.pack $ show e}


-- data GetPropertyError = KE_InvalidKeyID
--                       | KE_InvalidUserID
--                       deriving (Show, Read, Generic)

-- instance AppServantError GetPropertyError where
--   toServantErr e = err500 {errBody = LBSC8.pack $ show e}

-- data DBError = DBE_InsertionFail
--              | DBE_EmailExists
--              deriving (Show, Read, Generic)

-- instance AppServantError DBError where
--   toServantErr e = err500 {errBody = LBSC8.pack $ show e}