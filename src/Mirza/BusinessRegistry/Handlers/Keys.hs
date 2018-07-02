{-# LANGUAGE MultiParamTypeClasses #-}

module Mirza.BusinessRegistry.Handlers.Keys
  (
    getPublicKey
  , getPublicKeyInfo
  , revokePublicKey
  , addPublicKey
  ) where


import           Mirza.BusinessRegistry.Database.Schema
import           Mirza.BusinessRegistry.Handlers.Common
import           Mirza.BusinessRegistry.Types             as BT
import           Mirza.Common.Types
import           Mirza.Common.Utils

import           Database.Beam                            as B
import           Database.Beam.Backend.SQL.BeamExtensions

import           Data.Text                                (pack, unpack)
import           Data.Time.Clock                          (UTCTime)

import           OpenSSL.EVP.PKey                         (SomePublicKey,
                                                           toPublicKey)
import           OpenSSL.PEM                              (readPublicKey,
                                                           writePublicKey)
import           OpenSSL.RSA                              (RSAPubKey, rsaSize)



minPubKeySize :: Bit
minPubKeySize = Bit 2048

getPublicKey ::  BRApp context err => KeyID -> AppM context err PEM_RSAPubKey
getPublicKey = notImplemented


getPublicKeyInfo ::  BRApp context err => KeyID -> AppM context err BT.KeyInfo
getPublicKeyInfo = notImplemented


addPublicKey :: (BRApp context err, AsKeyError err) => BT.AuthUser
             -> PEM_RSAPubKey
             -> Maybe ExpirationTime
             -> AppM context err KeyID
addPublicKey user pemKey@(PEM_RSAPubKey pemStr) mExp = do
  somePubKey <- liftIO $ readPublicKey (unpack pemStr) -- TODO: Catch exception from OpenSSL - any invalid PEM string causes exception
  rsaKey <- checkPubKey somePubKey pemKey              -- Input: "x"
  runDb $ addPublicKeyQuery user mExp rsaKey           -- Error: user error (error:0906D06C:PEM routines:PEM_read_bio:no start line)



checkPubKey :: (MonadError err m, AsKeyError err)
            => SomePublicKey -> PEM_RSAPubKey-> m RSAPubKey
checkPubKey spKey pemKey =
  maybe (throwing _InvalidRSAKey pemKey)
  (\pubKey ->
    let keySizeBits = Bit $ rsaSize pubKey * 8 in
    -- rsaSize returns size in bytes
    if keySizeBits < minPubKeySize
      then throwing _InvalidRSAKeySize (Expected minPubKeySize, Received keySizeBits)
      else pure pubKey
  )
  (toPublicKey spKey)


addPublicKeyQuery :: AsKeyError err => AuthUser
                  -> Maybe ExpirationTime
                  -> RSAPubKey
                  -> DB context err KeyID
addPublicKeyQuery (AuthUser uid) expTime rsaPubKey = do
  keyStr <- liftIO $ pack <$> writePublicKey rsaPubKey
  keyId <- newUUID
  timeStamp <- generateTimestamp
  ks <- pg $ runInsertReturningList (_keys businessRegistryDB) $
        insertValues
        [ KeyT keyId uid keyStr
            timeStamp Nothing (toLocalTime . unExpirationTime <$> expTime)
        ]
  case ks of
    [rowId] -> return (KeyID $ key_id rowId)
    _       -> throwing _PublicKeyInsertionError (map primaryKey ks)



revokePublicKey :: BRApp context err => BT.AuthUser -> KeyID -> AppM context err UTCTime
revokePublicKey = notImplemented
