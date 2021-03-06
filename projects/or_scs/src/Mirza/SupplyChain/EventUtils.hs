{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TupleSections         #-}

module Mirza.SupplyChain.EventUtils
  ( insertEvent
  , insertDWhat, insertDWhen, insertDWhere, insertDWhy
  , insertWhatLabel, insertLabelEvent, insertLabel, findInstLabelIdByUrn, getAction
  , findEvent, findSchemaEvent, getEventList
  , findLabelId, getParent, getLabelsWithType
  , findDWhere
  ) where

import qualified Mirza.Common.GS1BeamOrphans       as MU
import           Mirza.Common.Time                 (toDbTimestamp)
import           Mirza.SupplyChain.Database.Schema as Schema
import           Mirza.SupplyChain.ErrorUtils      (throwBackendError)
import           Mirza.SupplyChain.Types

import qualified Mirza.SupplyChain.QueryUtils      as QU


import           Data.GS1.EPC                      as EPC
import           Data.GS1.Event                    (Event (..))
import qualified Data.GS1.Event                    as Ev
import qualified Data.GS1.EventId                  as EvId

import           Data.GS1.DWhat                    (AggregationDWhat (..),
                                                    AssociationDWhat (..),
                                                    DWhat (..), InputEPC (..),
                                                    LabelEPC (..),
                                                    ObjectDWhat (..),
                                                    OutputEPC (..),
                                                    ParentLabel (..),
                                                    TransactionDWhat (..),
                                                    TransformationDWhat (..))
import           Data.GS1.DWhen                    (DWhen (..))
import           Data.GS1.DWhere                   (BizLocation (..),
                                                    DWhere (..),
                                                    DestinationLocation (..),
                                                    ReadPointLocation (..),
                                                    SourceLocation (..))
import           Data.GS1.DWhy                     (DWhy (..))

import           Data.Maybe                        (catMaybes, listToMaybe,
                                                    maybeToList)

import           Data.ByteString                   (ByteString)
import qualified Data.Text                         as T

import           Data.Time.LocalTime               (timeZoneOffsetString)

import           Database.Beam                     as B
import           Database.Beam.Postgres            (PgJSON (..))

import           Crypto.JOSE.Types                 (Base64Octets (..))

-- Helper functions

epcToStorageLabel :: Schema.LabelId
                  -> LabelEPC
                  -> Schema.Label
epcToStorageLabel (Schema.LabelId pKey) (IL labelEpc@(SGTIN gs1Prefix fv ir sn)) =
  Schema.Label Nothing pKey
           gs1Prefix (Just ir)
           (Just sn) Nothing Nothing
           fv
           Nothing Nothing Nothing
           (MU.LabelEPCUrn $ renderURL labelEpc)

epcToStorageLabel (Schema.LabelId pKey) (IL labelEpc@(GIAI gs1Prefix sn)) =
  Schema.Label Nothing pKey
           gs1Prefix Nothing (Just sn)
           Nothing Nothing Nothing Nothing Nothing Nothing
           (MU.LabelEPCUrn $ renderURL labelEpc)

epcToStorageLabel (Schema.LabelId pKey) (IL labelEpc@(SSCC gs1Prefix sn)) =
  Schema.Label Nothing pKey
           gs1Prefix Nothing (Just sn)
           Nothing Nothing Nothing Nothing Nothing Nothing
           (MU.LabelEPCUrn $ renderURL labelEpc)

epcToStorageLabel (Schema.LabelId pKey) (IL labelEpc@(GRAI gs1Prefix at sn)) =
  Schema.Label Nothing pKey
           gs1Prefix Nothing (Just sn)
           Nothing Nothing Nothing (Just at) Nothing Nothing
           (MU.LabelEPCUrn $ renderURL labelEpc)

epcToStorageLabel (Schema.LabelId pKey) (CL labelEpc@(LGTIN gs1Prefix ir lot) mQ) =
  Schema.Label Nothing pKey
           gs1Prefix (Just ir) Nothing
           Nothing (Just lot) Nothing Nothing
           (getQuantityAmount mQ) (getQuantityUom mQ)
           (MU.LabelEPCUrn $ renderURL labelEpc)

epcToStorageLabel (Schema.LabelId pKey) (CL labelEpc@(CSGTIN gs1Prefix fv ir) mQ) =
  Schema.Label Nothing pKey
           gs1Prefix (Just ir) Nothing
           Nothing Nothing fv Nothing
           (getQuantityAmount mQ) (getQuantityUom mQ)
           (MU.LabelEPCUrn $ renderURL labelEpc)

getQuantityAmount :: Maybe Quantity -> Maybe Amount
getQuantityAmount Nothing                       = Nothing
getQuantityAmount (Just (MeasuredQuantity a _)) = Just . Amount . realToFrac . unAmount $ a
getQuantityAmount (Just (ItemCount c))          = Just . Amount . realToFrac $ c

getQuantityUom :: Maybe Quantity -> Maybe EPC.Uom
getQuantityUom Nothing                       = Nothing
getQuantityUom (Just (MeasuredQuantity _ u)) = Just u
getQuantityUom (Just (ItemCount _))          = Nothing


-- | GS1 DWhat to Storage DWhat
-- For an object event
toStorageDWhat :: PrimaryKeyType
               -> Maybe PrimaryKeyType
               -> Maybe PrimaryKeyType
               -> Schema.EventId
               -> DWhat
               -> Schema.What
toStorageDWhat pKey mParentId mOrgTranId eventId dwhat
   = Schema.What Nothing pKey
        (Just . Ev.getEventType $ dwhat)
        (getAction dwhat)
        (Schema.LabelId mParentId)
        (Schema.OrgTransactionId mOrgTranId)
        (Schema.TransformationId $ unTransformationId <$> getTransformationId dwhat)
        eventId

getTransformationId :: DWhat -> Maybe EPC.TransformationId
getTransformationId (TransformWhat t) = _transformationId t
getTransformationId _                 = Nothing


getAction :: DWhat -> Maybe Action
getAction (TransformWhat _)                           = Nothing
getAction (AssociationWhat _)                         = Nothing
getAction (ObjWhat (ObjectDWhat act _))               = Just act
getAction (TransactWhat (TransactionDWhat act _ _ _)) = Just act
getAction (AggWhat (AggregationDWhat act _ _))        = Just act


findInstLabelId :: InstanceLabelEPC -> DB context err (Maybe PrimaryKeyType)
findInstLabelId (GIAI cp sn) = findInstLabelId' cp sn Nothing Nothing Nothing
findInstLabelId (SSCC cp sn) = findInstLabelId' cp sn Nothing Nothing Nothing
findInstLabelId (SGTIN cp msfv ir sn) = findInstLabelId' cp sn msfv (Just ir) Nothing
findInstLabelId (GRAI cp at sn) = findInstLabelId' cp sn Nothing Nothing (Just at)


findInstLabelIdByUrn :: InstanceLabelEPC -> DB context err [PrimaryKeyType]
findInstLabelIdByUrn labelEpc = do
  let labelUrn = MU.LabelEPCUrn . renderURL $ labelEpc
  l <- pg $ runSelectReturningList $ select $ do
    labels <- all_ (Schema._labels Schema.supplyChainDb)
    guard_ (Schema.label_urn labels ==. val_ labelUrn)
    pure labels
  pure $ Schema.label_id <$> l


findInstLabelId' :: GS1CompanyPrefix
                 -> SerialNumber
                 -> Maybe SGTINFilterValue
                 -> Maybe ItemReference
                 -> Maybe AssetType
                 -> DB context err (Maybe PrimaryKeyType)
findInstLabelId' cp sn msfv mir mat = do
  l <- pg $ runSelectReturningList $ select $ do
    labels <- all_ (Schema._labels Schema.supplyChainDb)
    guard_ (Schema.label_gs1_company_prefix labels ==. val_ cp &&.
            Schema.label_serial_number labels ==. val_ (Just sn) &&.
            (Schema.label_sgtin_filter_value labels) ==. (val_ msfv) &&.
            Schema.label_asset_type labels ==. val_ mat &&.
            Schema.label_item_reference labels ==. val_ mir)
    pure labels
  pure $ case l of
    [lbl] -> Just $ Schema.label_id lbl
    _     -> Nothing

findClassLabelId :: ClassLabelEPC -> DB context err (Maybe PrimaryKeyType)
findClassLabelId (LGTIN cp ir lot)  = findClassLabelId' cp Nothing ir (Just lot)
findClassLabelId (CSGTIN cp msfv ir) = findClassLabelId' cp msfv ir Nothing

findClassLabelId' :: GS1CompanyPrefix
                  -> Maybe SGTINFilterValue
                  -> ItemReference
                  -> Maybe Lot
                  -> DB context err (Maybe PrimaryKeyType)
findClassLabelId' cp msfv ir lot = do
  l <- pg $ runSelectReturningList $ select $ do
    labels <- all_ (Schema._labels Schema.supplyChainDb)
    guard_ (
             Schema.label_gs1_company_prefix labels ==. val_ cp &&.
             (Schema.label_sgtin_filter_value labels) ==. (val_ msfv) &&.
             Schema.label_lot labels ==. (val_ lot) &&.
             Schema.label_item_reference labels ==. (val_ . Just $ ir)
           )
    pure labels
  pure $ case l of
    [lbl] -> Just $ Schema.label_id lbl
    _     -> Nothing


findLabelId :: LabelEPC -> DB context err (Maybe PrimaryKeyType)
findLabelId (IL l)   = findInstLabelId l
findLabelId (CL c _) = findClassLabelId c

getParent :: DWhat -> Maybe ParentLabel
getParent (TransactWhat (TransactionDWhat _ p _ _)) = p
getParent (AggWhat (AggregationDWhat _ p _) )       = p
getParent _                                         = Nothing

getParentId :: DWhat -> DB context err (Maybe PrimaryKeyType)
getParentId dwhat = do
  let mParentLabel = getParent dwhat
  case mParentLabel of
    Nothing              -> pure Nothing
    Just (ParentLabel p) -> findInstLabelId p

toStorageDWhen :: Schema.WhenId
               -> DWhen
               -> Schema.EventId
               -> Schema.When
toStorageDWhen (Schema.WhenId pKey) (DWhen eventTime mRecordTime tZone) =
  Schema.When Nothing pKey
    (toDbTimestamp eventTime)
    (toDbTimestamp <$> mRecordTime)
    (T.pack . timeZoneOffsetString $ tZone)

-- | Extracts all labels from a DWhat, and stores it alongside its type
-- so that we don't lose the labeltype information
getLabelsWithType :: DWhat -> [LabelWithType]
getLabelsWithType (ObjWhat (ObjectDWhat _act epcList))
    = LabelWithType Nothing <$> epcList
getLabelsWithType (AggWhat (AggregationDWhat _act mParent childEpcList))
    =  (LabelWithType Nothing <$> childEpcList)
    <> (LabelWithType (Just MU.Parent) <$> maybeToList (IL . unParentLabel <$> mParent))
getLabelsWithType (TransactWhat (TransactionDWhat _act mParent _orgT epcList))
    =  (LabelWithType Nothing <$> epcList)
    <> (LabelWithType (Just MU.Parent) <$> maybeToList (IL . unParentLabel <$> mParent))
getLabelsWithType (TransformWhat (TransformationDWhat _tId input output))
    =  (LabelWithType (Just MU.Input)  . unInputEPC <$> input)
    <> (LabelWithType (Just MU.Output) . unOutputEPC <$> output)
getLabelsWithType (AssociationWhat (AssociationDWhat parent children))
    =  LabelWithType (Just MU.Parent) (IL $ unParentLabel parent)
       : (LabelWithType Nothing <$> children)



toStorageDWhy :: Schema.WhyId -> DWhy -> Schema.EventId -> Schema.Why
toStorageDWhy (Schema.WhyId pKey) (DWhy mOrg mDisp)
  = Schema.Why Nothing pKey (renderURL <$> mOrg) (renderURL <$> mDisp)

toStorageEvent :: Schema.EventId
               -> Maybe EvId.EventId
               -> PgJSON Ev.Event
               -> ByteString
               -> Schema.Event
toStorageEvent (Schema.EventId pKey) mEventId =
  Schema.Event Nothing pKey (EvId.unEventId <$> mEventId)

insertDWhat :: Maybe PrimaryKeyType
            -> DWhat
            -> Schema.EventId
            -> DB context err PrimaryKeyType
insertDWhat mOrgTranId dwhat eventId = QU.withPKey $ \pKey ->  do
    mParentId <- getParentId dwhat
    pg $ B.runInsert $ B.insert (Schema._whats Schema.supplyChainDb)
          $ insertValues [toStorageDWhat pKey mParentId mOrgTranId eventId dwhat]


insertDWhen :: DWhen -> Schema.EventId -> DB context err PrimaryKeyType
insertDWhen dwhen eventId = QU.withPKey $ \pKey ->
  pg $ B.runInsert $ B.insert (Schema._whens Schema.supplyChainDb)
             $ insertValues [toStorageDWhen (Schema.WhenId pKey) dwhen eventId]


insertDWhy :: DWhy -> Schema.EventId -> DB context err PrimaryKeyType
insertDWhy dwhy eventId = QU.withPKey $ \pKey ->
  pg $ B.runInsert $ B.insert (Schema._whys Schema.supplyChainDb)
             $ insertValues [toStorageDWhy (Schema.WhyId pKey) dwhy eventId]

-- | Maps the relevant insert function for all
-- ReadPoint, OrgLocation, Src, Dest
insertDWhere :: DWhere -> Schema.EventId -> DB context err ()
insertDWhere (DWhere rPoint orgLoc srcTs destTs) eventId = do
  sequence_ $ (insertQ MU.ReadPoint Nothing . unReadPointLocation) <$> rPoint
  sequence_ $ (insertQ MU.OrgLocation Nothing . unBizLocation) <$> orgLoc
  sequence_ $ (\(sdType, epc) -> insertQ MU.Src (Just sdType) epc) . unwrapSrc <$> srcTs
  sequence_ $ (\(sdType, epc) -> insertQ MU.Dest (Just sdType) epc) . unwrapDest <$> destTs

  where
    insertQ locField sdType locationEPC =
      QU.withPKey ( pg
                    . B.runInsert
                    . B.insert (Schema._wheres Schema.supplyChainDb)
                    . insertValues
                    . pure -- []
                    . createWhere sdType locField locationEPC
                  )

    createWhere sdType locField (SGLN pfix locationRef ext) pK =
      Schema.Where Nothing pK (Just pfix) sdType (Just locationRef) locField ext Nothing eventId
    createWhere sdType locField (Geo x) pK =
      Schema.Where Nothing pK Nothing sdType Nothing locField Nothing (Just x) eventId

    unwrapSrc (SourceLocation t l) = (t, l)

    unwrapDest (DestinationLocation t l) = (t, l)


-- | Given a DWhere, looks for all the insertions associated with the DWHere
-- Think of this as the inverse of ``insertDWhere``
findDWhere :: Schema.EventId -> DB context err (Maybe DWhere)
findDWhere eventId = do
  rPoints <- findDWhereByLocationField MU.ReadPoint eventId
  orgLocs <- findDWhereByLocationField MU.OrgLocation eventId
  srcTs <- findDWhereByLocationField MU.Src eventId
  destTs <- findDWhereByLocationField MU.Dest eventId
  pure $ mergeSBWheres
    (fmap ReadPointLocation (constructLocation =<< listToMaybe rPoints))
    (fmap BizLocation (constructLocation =<< listToMaybe orgLocs))
    srcTs destTs

findDWhereByLocationField :: MU.LocationField -> Schema.EventId -> DB context err [Schema.WhereT Identity]
findDWhereByLocationField locField eventId = pg $ runSelectReturningList $ select $ do
    wheres <- all_ (Schema._wheres Schema.supplyChainDb)
    guard_ (
      Schema.where_event_id wheres ==. val_ eventId &&.
      Schema.where_location_field wheres ==. val_ locField)
    pure wheres

-- | Merges a list of Schema.Wheres into one Data.GS1.DWhere
-- mergeSBWheres :: [Schema.WhereT Identity] -> DWhere
mergeSBWheres :: Maybe ReadPointLocation
              -> Maybe BizLocation
              -> [Schema.WhereT Identity]
              -> [Schema.WhereT Identity]
              -> Maybe DWhere
mergeSBWheres rPoints orgLocs srcTsW destTsW =
  let srcTs = constructSrcDestLocation SourceLocation <$> srcTsW
      destTs = constructSrcDestLocation DestinationLocation <$> destTsW
      in
        DWhere rPoints orgLocs <$> sequence srcTs <*> sequence destTs

-- | This relies on the user calling this function in the appropriate WhereT
constructSrcDestLocation :: (SourceDestType -> LocationEPC -> srcOrDest)
                         -> WhereT Identity
                         -> Maybe srcOrDest
constructSrcDestLocation c whereT = constructLocation whereT >>= \location ->
  flip c location <$> Schema.where_source_dest_type whereT

-- | This relies on the user calling this function in the appropriate WhereT
constructLocation :: Schema.WhereT Identity -> Maybe LocationEPC
constructLocation (Schema.Where _ _ (Just pfx) _ (Just ref) _ ext Nothing _) = Just $ EPC.SGLN pfx ref ext
constructLocation (Schema.Where _ _ Nothing _ Nothing _ Nothing (Just geo) _) = Just $ EPC.Geo geo
constructLocation _ = Nothing



insertEvent :: Ev.Event
            -> DB context err (EventInfo, Schema.EventId)
insertEvent event = do
  let toSignEvent = QU.constructEventToSign event
  eventId <- fmap (Schema.EventId <$>) QU.withPKey $ \pKey ->
    pg  $ B.runInsert $ B.insert (Schema._events Schema.supplyChainDb)
        $ insertValues
        [ toStorageEvent (Schema.EventId pKey) (_eid event) (PgJSON event) toSignEvent]

  pure ((EventInfo event (Base64Octets toSignEvent) NeedMoreSignatures), eventId)

insertWhatLabel :: Maybe MU.LabelType
                -> Schema.WhatId
                -> Schema.LabelId
                -> DB context err PrimaryKeyType
insertWhatLabel labelType (Schema.WhatId whatId) (Schema.LabelId labelId) = QU.withPKey $ \pKey ->
  pg $ B.runInsert $ B.insert (Schema._what_labels Schema.supplyChainDb)
        $ insertValues
        [
          Schema.WhatLabel Nothing pKey
          (Schema.WhatId whatId)
          (Schema.LabelId labelId)
          labelType
        ]

-- | Given the necessary information,
-- converts a ``LabelEPC`` to Schema.Label and writes it to the database
insertLabel :: LabelEPC
            -> DB context err PrimaryKeyType
insertLabel labelEpc = do
  mLabelId <- findLabelId labelEpc
  case mLabelId of
    Just lblId -> pure lblId
    Nothing -> QU.withPKey $ \pKey ->
            pg $ B.runInsert $ B.insert (Schema._labels Schema.supplyChainDb)
            (insertValues [ epcToStorageLabel (Schema.LabelId pKey) labelEpc])

-- | Ties up a label and an event entry in the database
insertLabelEvent :: Maybe MU.LabelType
                 -> Schema.EventId
                 -> Schema.LabelId
                 -> DB context err PrimaryKeyType
insertLabelEvent labelType eventId labelId = QU.withPKey $ \pKey ->
  pg $ B.runInsert $ B.insert (Schema._label_events Schema.supplyChainDb)
        $ insertValues [ Schema.LabelEvent Nothing pKey labelId eventId labelType ]

getEventList :: AsServiceError err
             => Schema.LabelId
             -> DB context err [Ev.Event]
getEventList labelId = do
  labelEvents <- pg $ runSelectReturningList $ select $ do
        labelEvent <- all_ (Schema._label_events Schema.supplyChainDb)
        guard_ (Schema.label_event_label_id labelEvent ==. val_ labelId)
        guard_ (Schema.label_event_label_type labelEvent /=. val_ (Just MU.Parent))
        pure labelEvent
  let eventIds = Schema.label_event_event_id <$> labelEvents
      allEvents = findEvent <$> eventIds
  catMaybes <$> sequence allEvents

findEvent :: AsServiceError err
          => Schema.EventId
          -> DB context err (Maybe Ev.Event)
findEvent eventId = do
  mschemaEvent <- findSchemaEvent eventId
  pure $ mschemaEvent >>= (Just . QU.storageToModelEvent)

findSchemaEvent :: AsServiceError err
                => Schema.EventId
                -> DB context err (Maybe Schema.Event)
findSchemaEvent (Schema.EventId eventId) = do
  r <- pg $
        runSelectReturningList $ select $ do
        event <- all_ (Schema._events Schema.supplyChainDb)
        guard_ (Schema.event_id event ==. (val_ eventId))
        pure event
  case r of
    [event] -> pure $ Just event
    []      -> pure Nothing
    -- TODO: Do the right thing here
    _       -> throwBackendError r
