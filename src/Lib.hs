{-# START_FILE src/Lib.hs #-}
{-# LANGUAGE DataKinds       #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeOperators   #-}
{-# LANGUAGE DeriveGeneric #-}

module Lib
    ( startApp
    , app
    ) where

import Data.Aeson
import Data.Aeson.TH
import Network.Wai
import Network.Wai.Handler.Warp
import Servant
import Data.Maybe
import Data.GS1.Event
import Data.GS1.Object
import Data.GS1.EPC
import Data.GS1.DWhen
import Data.GS1.DWhere
import Data.GS1.DWhat
import Data.GS1.DWhy
import Data.Either.Combinators
import Data.Time
import Data.ByteString
import GHC.Generics

type UserID = Integer
type EventID = Integer

data User = User {
    userId        :: UserID
  , userFirstName :: String
  , userLastName  :: String
} deriving (Generic, Eq, Show)
$(deriveJSON defaultOptions ''User)


data RFIDState = New | InProgress | AwaitingDeploymentToBC | Customer | Finalised
  deriving (Generic, Eq, Show)
$(deriveJSON defaultOptions ''RFIDState)

data RFIDInfo = RFIDInfo {
  state :: RFIDState,
  owner :: Maybe UserID
} deriving (Generic, Eq, Show)
$(deriveJSON defaultOptions ''RFIDInfo)



data NewUser = NewUser {
  phoneNumber :: String,
  firstName :: String,
  lastName :: String,
  company :: String,
  publicKey :: String
} deriving (Generic, Eq, Show)
$(deriveJSON defaultOptions ''NewUser)

data NewObject = NewObject {
  object_userID :: UserID,
  object_epcs :: EPC,
  object_timestamp :: EPCISTime,
  object_timezone:: TimeZone,
  object_objectID :: ObjectID,
  object_location :: GeoLocation
                           } deriving (Show, Generic)
$(deriveJSON defaultOptions ''NewObject)

data AggregatedObject = AggregatedObject {
  aggObject_userID :: UserID,
  aggObject_objectIDs :: [ObjectID],
  aggObject_timestamp :: EPCISTime,
  aggOject_timezone:: TimeZone,
  aggObject_location :: GeoLocation
} deriving (Show, Generic)
$(deriveJSON defaultOptions ''AggregatedObject)

data TransformationInfo = TransformationInfo {
  transObject_userID :: UserID,
  transObject_objectIDs :: [ObjectID],
  transObject_timestamp :: EPCISTime,
  transObject_timezone:: TimeZone,
  transObject_location :: GeoLocation,
  transObject_inputEPC :: [EPC],
  transObject_inputQuantity :: [Quantity],
  transObject_outputEPC :: [EPC],
  transObject_outputQuantity :: [Quantity]
} deriving (Show, Generic)
$(deriveJSON defaultOptions ''TransformationInfo)



data TransactionInfo = TransactionInfo {
  transaction_userID :: UserID,
  transaction_objectIDs :: [ObjectID],
  transaction_parentID :: Maybe ParentID,
  transaction_bizTransaction :: [BizTransaction],
  transaction_epcs :: [EPC],
  transaction_quantities :: [QuantityElement]
} deriving (Show, Generic)
$(deriveJSON defaultOptions ''TransactionInfo)

data EventInfo = EventInfo {
  event_eventID :: Integer,
  eventType :: EventType,
  rfidState :: RFIDState,
  what :: DWhat,
  why :: DWhy,
  location :: DWhen,
  event_users :: [User]
} deriving (Generic, Eq, Show)

$(deriveJSON defaultOptions ''EventInfo)

{-
instance ToJSON EventInfo
instance FromJSON EventInfo
-}

data SignedEvent = SignedEvent {
  signed_eventID :: Integer,
  signed_eventHash :: ByteString,
  signed_Hashes :: [ByteString],
  signed_users :: [UserID]
}
-- $(deriveJSON defaultOptions ''SignedEvent)
-- $(deriveJSON defaultOptions ''ByteString)


type API =       "newUser" :> ReqBody '[JSON] NewUser :> Get '[JSON]  UserID
            :<|> "rfid" :>  Capture "RFID" String :> "info" :> Get '[JSON] (Maybe RFIDInfo)
            :<|> "event" :> Capture "eventID" EventID:> "info" :> Get '[JSON] EventInfo
            :<|> "contacts" :> Capture "userID" Integer :> Get '[JSON] [User]
            :<|> "contacts" :> "add" :> Capture "userID" Integer :> Get '[JSON] Bool
            :<|> "contacts" :> "remove" :> Capture "userID" Integer :> Get '[JSON] Bool
            :<|> "contacts" :> "search" :> Capture "term" String :> Get '[JSON] [User]
            :<|> "event" :> "list" :> Capture "userID" Integer :> Get '[JSON] [EventInfo]
            :<|> "event" :> "createObject" :> ReqBody '[JSON] NewObject :> Get '[JSON] ObjectID
            :<|> "event" :> "aggregateObjects" :> ReqBody '[JSON] AggregatedObject :> Get '[JSON] EventInfo
            :<|> "event" :> "start-transaction" :> ReqBody '[JSON] TransactionInfo :> Get '[JSON] EventInfo
            :<|> "event" :> "transformObject" :> ReqBody '[JSON] TransformationInfo :> Get '[JSON] EventInfo

              {-
type API = :<|> "event" :> "sign" :> ReqBody '[JSON] SignedEvent :> Post '[JSON] SignedEvent
            :<|> "event" :> Capture "eventID" EventID:> "hash" :> Get '[JSON] SignedEvent
            -- :<|> "login" :>  Put '[JSON] [User]
-}



startApp :: IO ()
startApp = run 8080 app

app :: Application
app = serve api server

api :: Proxy API
api = Proxy

server :: Server API
server =  newUser
        :<|> return . rfid
        :<|> return . eventInfo
        :<|> return . contactsInfo
        :<|> return . contactsAdd
        :<|> return . contactsRemove
        :<|> return . contactsSearch
        :<|> return . eventList
        :<|> return . eventCreateObject
        :<|> return . eventAggregateObjects
        :<|> return . eventStartTransaction
        :<|> return . eventTransformObject
          {-
        :<|> return . eventHash
        -}


newUser ::  NewUser -> Handler UserID
newUser _ = return 1

login :: UserID -> String -> Bool
login = error "implement me"

rfid :: String -> Maybe RFIDInfo
rfid str = Just (RFIDInfo New Nothing)

sampleWhat :: DWhat
sampleWhat = ObjectDWhat Observe [GLN "urn:epc:id:sgtin:0614141" "107346" "2017", GLN "urn:epc:id:sgtin:0614141" "107346" "2018"] []

sampleWhy :: DWhy
sampleWhy = DWhy (Just Arriving) (Just Active)

sampleWhen :: DWhen
sampleWhen = DWhen pt (Just pt) tz
  where
      t = "2017-01-24T13:08:24.11+10:00"
      pt = fromRight' (parseStr2Time t :: Either EPCISTimeError EPCISTime)
      tz = fromRight' (parseStr2TimeZone t :: Either EPCISTimeError TimeZone)


eventInfo :: EventID -> EventInfo
eventInfo eID = EventInfo 1 AggregationEventT New sampleWhat sampleWhy sampleWhen []

eventHash :: EventID -> SignedEvent
eventHash eID = SignedEvent eID empty [empty] [1,2]



contactsInfo :: UserID -> [User]
contactsInfo uID = []

contactsAdd :: UserID -> Bool
contactsAdd uID = False

contactsRemove :: UserID -> Bool
contactsRemove uID = False

contactsSearch :: String -> [User]
contactsSearch term = []

eventList :: UserID -> [EventInfo]
eventList uID = [(eventInfo 1)]

eventCreateObject :: NewObject -> ObjectID
eventCreateObject newObject = "newObjectID"

eventAggregateObjects :: AggregatedObject -> EventInfo
eventAggregateObjects _ = eventInfo 1

eventStartTransaction :: TransactionInfo -> EventInfo
eventStartTransaction _ = eventInfo 1

eventTransformObject :: TransformationInfo -> EventInfo
eventTransformObject _ = eventInfo 1

