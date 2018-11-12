{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedLists       #-}
{-# LANGUAGE ScopedTypeVariables   #-}

module Mirza.SupplyChain.Handlers.Signatures
  (
    eventSign, getEventBS, insertSignature, eventHashed
  , findSignedEventByEvent, findSignatureByEvent
  , findSignedEventByUser, findSignatureByUser
  , signatureToSignedEvent
  ) where

import           Mirza.Common.Time
import           Mirza.Common.Types                       (BRKeyId)
import           Mirza.Common.Utils

import           Mirza.SupplyChain.Database.Schema        as Schema
import           Mirza.SupplyChain.ErrorUtils             (throwBackendError)
import           Mirza.SupplyChain.Handlers.Common
import           Mirza.SupplyChain.Types                  hiding (NewUser (..),
                                                           User (userId),
                                                           UserId)
import qualified Mirza.SupplyChain.Types                  as ST


import qualified Data.GS1.EventId                         as EvId

import           Database.Beam                            as B
import           Database.Beam.Backend.SQL.BeamExtensions
import           Database.Beam.Postgres                   (PgJSON (..))


import           Crypto.JOSE                              (Alg (..), AsError,
                                                           CompactJWS,
                                                           JWSHeader,
                                                           ValidationSettings,
                                                           defaultValidationSettings,
                                                           validationSettingsAlgorithms,
                                                           verifyJWS)
import           Data.ByteString                          (ByteString)

import           Control.Lens                             ((&), (.~))

import           Mirza.BusinessRegistry.Client.Servant    (getPublicKey)

scsJWSValidationSettings :: ValidationSettings
scsJWSValidationSettings = defaultValidationSettings
    & validationSettingsAlgorithms .~ [RS256,RS384,RS512,PS256,PS384,PS512]

eventSign :: (HasBRClientEnv context, AsServantError err, AsError err, SCSApp context err)
          => ST.User
          -> SignedEvent
          -> AppM context err PrimaryKeyType
eventSign user (SignedEvent eventId keyId sig) = do
  jwk <- runClientFunc $ getPublicKey keyId
  runDb $ do
    eventBS <- getEventBS eventId
    event' <- verifyJWS scsJWSValidationSettings jwk sig
    if eventBS == event'
      then insertSignature (ST.userId user) eventId keyId sig
      else throwing _SigVerificationFailure (show sig) -- TODO: This should be more than show

-- TODO: Should this return Text or a JSON value?
getEventBS :: AsServiceError err => EvId.EventId -> DB context err ByteString
getEventBS eventId = do
  r <- pg $ runSelectReturningList $ select $ do
    allEvents <- all_ (Schema._events Schema.supplyChainDb)
    guard_ ((Schema.event_id allEvents) ==. val_ (EvId.unEventId eventId))
    pure (Schema.event_to_sign allEvents)
  case r of
    [eventBS] -> pure eventBS
    _         -> throwing _InvalidEventId eventId


insertSignature :: (AsServiceError err) => ST.UserId
                -> EvId.EventId
                -> BRKeyId
                -> CompactJWS JWSHeader
                -> DB environmentUnused err PrimaryKeyType

insertSignature userId@(ST.UserId uId) eId kId sig = do
  sigId <- newUUID
  timestamp <- generateTimestamp
  r <- pg $ runInsertReturningList (Schema._signatures Schema.supplyChainDb) $
        insertValues
        [Schema.Signature Nothing sigId (Schema.UserId uId) (Schema.EventId $ EvId.unEventId eId)
         (BRKeyId $ getBRKeyId kId) (PgJSON sig) (toDbTimestamp timestamp)]
  case r of
    [rowId] -> do
      updateUserEventSignature userId eId True
      pure ( Schema.signature_id rowId)
    _       -> throwing _BackendErr "Failed to add signature"

updateUserEventSignature :: AsServiceError err
                         => ST.UserId
                         -> EvId.EventId
                         -> Bool
                         -> DB environmentUnused err ()
updateUserEventSignature (ST.UserId userId) (EvId.EventId eventId) hasSignedNew = do
  _r <- pg $ runUpdate $ update
              (_user_events supplyChainDb)
              (\userEvent -> [user_events_has_signed userEvent <-. val_ hasSignedNew])
              (\userEvent -> (user_events_event_id userEvent ==. val_ (Schema.EventId eventId) &&.
                              (user_events_user_id userEvent ==. val_ (Schema.UserId userId))))
  pure ()

findSignatureByEvent :: (AsServiceError err)
                     => EvId.EventId
                     -> DB context err [Schema.Signature]
findSignatureByEvent (EvId.EventId eId) =
  pg $ runSelectReturningList $ select $ do
    sig <- all_ (Schema._signatures Schema.supplyChainDb)
    guard_ ((Schema.signature_event_id sig) ==. (val_ (Schema.EventId eId)))
    pure sig

findSignedEventByEvent :: (AsServiceError err)
                       => EvId.EventId
                       -> DB context err [ST.SignedEvent]
findSignedEventByEvent eventId = fmap signatureToSignedEvent <$> findSignatureByEvent eventId

findSignatureByUser :: AsServiceError err
                    => ST.UserId
                    -> EvId.EventId
                    -> DB context err Schema.Signature
findSignatureByUser (ST.UserId uId) (EvId.EventId eId) = do
  r <- pg $ runSelectReturningList $ select $ do
    sig <- all_ (Schema._signatures Schema.supplyChainDb)
    guard_ ((Schema.signature_event_id sig) ==. (val_ (Schema.EventId eId)) &&.
            (Schema.signature_user_id sig) ==. (val_ (Schema.UserId uId)))
    pure sig
  case r of
    [sig] -> pure sig
    _     -> throwBackendError ("Invalid User - Event pair" :: String) -- TODO: wrong error to throw here

findSignedEventByUser :: AsServiceError err
                      => ST.UserId
                      -> EvId.EventId
                      -> DB context err ST.SignedEvent
findSignedEventByUser uId eventId = signatureToSignedEvent <$> (findSignatureByUser uId eventId)

signatureToSignedEvent :: Schema.Signature -> ST.SignedEvent
signatureToSignedEvent (Schema.Signature _ _userId _sigId (Schema.EventId eId) brKeyId (PgJSON sig) _)
  = ST.SignedEvent (EvId.EventId eId) brKeyId sig

-- do we need this?
eventHashed :: ST.User -> EvId.EventId -> AppM context err HashedEvent
eventHashed _user _eventId = error "not implemented yet"
-- pure (HashedEvent eventId (EventHash "Blob"))

{-
eventHashed user eventId = do
  mHash <- liftIO $ Storage.eventHashed user eventId
  case mHash of
    Nothing -> throwError err404 { errBody = "Unknown eventId" }
    Just i -> pure i
-}

-- BeamQueries residue

-- -- TODO - convert these below functions, and others in original file Storage.hs
-- -- TODO = use EventId or EventId ???
-- -- TODO = implement... there is no hash...
-- createBlockchainPackage ::  (MonadError SigError m, MonadIO m) => EventId -> m C.BlockchainPackage


-- createBlockchainPackage eventID = do
--   -- XXX do we want to explicitly check that the hash is signed before assuming the first one is not?
--   r <- liftIO $ query_ conn "SELECT hash, signedByUserID FROM Hashes WHERE eventID=? ORDER BY isSigned ASC;" $ Only eventID
--   if length r > 2
--     then
--       let (plainHash, userID) = head r
--           signatures = NonEmpty.fromList (map (\(s, u) -> ((Signature s), u)) (tail r))
--       in
--         pure $ C.BlockchainPackage (EventHash plainHash) signatures
--     else throwError SE_BlockchainSendFailed
-- --TODO - Implement me
-- checkSignature :: (MonadError SigError m, MonadIO m) => PEM_RSAPubKey -> ByteString.ByteString -> Signature -> m ()
-- checkSignature pubkey blob signature =
--   unless (C.verifySignature pubkey blob signature) $
--     throwError SE_InvalidSignature
-- -- TODO = use EventId or EventId
-- -- ready to send to blockchain when all the parties have signed
-- checkReadyForBlockchain :: (MonadError SigError m, MonadIO m) => Connection -> EventId -> m ()
-- checkReadyForBlockchain eventID = do
--   r <- liftIO $ query_ conn "SELECT COUNT(id) FROM UserEvents WHERE eventID=? AND hasSigned=FALSE;" $ Only eventID
--   case r of
--     [Only 0] -> pure ()
--     _ -> throwError SE_NeedMoreSignatures

