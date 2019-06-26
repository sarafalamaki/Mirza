{-# LANGUAGE DeriveGeneric         #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE StandaloneDeriving    #-}
{-# LANGUAGE TypeFamilies          #-}



module Mirza.OrgRegistry.Database.Schema.V0002
 ( module Mirza.OrgRegistry.Database.Schema.V0002
 , module V0001
 ) where

import qualified Data.GS1.EPC                            as EPC
import           Mirza.Common.Beam                       (lastUpdateField)
import           Mirza.Common.GS1BeamOrphans
import           Mirza.Common.Types                      (PrimaryKeyType)
import           Mirza.OrgRegistry.Types

import           Control.Lens
import           Data.Text                               (Text)
import           Data.Time                               (LocalTime)


import           Database.Beam                           as B
import           Database.Beam.Migrate.SQL.Tables
import           Database.Beam.Migrate.Types
import           Database.Beam.Postgres

import           Data.Aeson
import           Data.Swagger
import           Servant                                 (FromHttpApiData (parseUrlPiece),
                                                          ToHttpApiData (toUrlPiece))

import           GHC.Generics                            (Generic)

import           Mirza.OrgRegistry.Database.Schema.V0001 as V0001' hiding (OrgRegistryDB (..),
                                                                    migration)
import qualified Mirza.OrgRegistry.Database.Schema.V0001 as V0001



-- Database
data OrgRegistryDB f = OrgRegistryDB
  { _orgs         :: f (TableEntity V0001.OrgT)
  , _users        :: f (TableEntity V0001.UserT)
  , _orgMapping   :: f (TableEntity V0001.OrgMappingT)
  , _keys         :: f (TableEntity V0001.KeyT)
  , _locations    :: f (TableEntity       LocationT)
  , _geoLocations :: f (TableEntity       GeoLocationT)
  }
  deriving Generic
instance Database anybackend OrgRegistryDB


migration :: CheckedDatabaseSettings Postgres V0001.OrgRegistryDB
          -> Migration PgCommandSyntax (CheckedDatabaseSettings Postgres OrgRegistryDB)
migration v0001 = OrgRegistryDB
  <$> preserve (V0001._orgs          v0001)
  <*> preserve (V0001._users               v0001)
  <*> preserve (V0001._orgMapping v0001)
  <*> preserve (V0001._keys                v0001)
  <*> createTable "location" (LocationT
        (field "location_id" V0001.pkSerialType)
        (field "location_gln" locationEPCType)
        (V0001.OrgPrimaryKey $ field "location_org_id" gs1CompanyPrefixFieldType)
        lastUpdateField
        )
  <*> createTable "geo_location" (GeoLocationT
        (field "geo_location_id"      V0001.pkSerialType)
        (LocationPrimaryKey $ field "geo_location_gln" locationEPCType)
        (field "geo_location_lat"     (maybeType latitudeType))
        (field "geo_location_lon"     (maybeType longitudeType))
        (field "geo_location_address" (maybeType $ varchar Nothing))
        lastUpdateField
        )

type Location = LocationT Identity
deriving instance Show Location

data LocationT f = LocationT
  { location_id          :: C f PrimaryKeyType
  , location_gln         :: C f EPC.LocationEPC
  , location_org_id      :: PrimaryKey V0001.OrgT f
  , location_last_update :: C f (Maybe LocalTime)
  }
  deriving Generic

type LocationPrimaryKey = PrimaryKey LocationT Identity
deriving instance Show (PrimaryKey LocationT Identity)
instance ToSchema LocationPrimaryKey
instance ToParamSchema LocationPrimaryKey
instance ToJSON (PrimaryKey LocationT Identity) where
  toJSON (LocationPrimaryKey uid) = toJSON uid
instance FromJSON (PrimaryKey LocationT Identity) where
  parseJSON = fmap LocationPrimaryKey . parseJSON

instance Beamable LocationT
instance Beamable (PrimaryKey LocationT)

instance Table LocationT where
  newtype PrimaryKey LocationT f = LocationPrimaryKey (C f EPC.LocationEPC)
    deriving Generic
  primaryKey = LocationPrimaryKey . location_gln
deriving instance Eq (PrimaryKey LocationT Identity)

instance ToHttpApiData (PrimaryKey LocationT Identity) where
  toUrlPiece (LocationPrimaryKey locId) = toUrlPiece locId

instance FromHttpApiData (PrimaryKey LocationT Identity) where
  parseUrlPiece t = LocationPrimaryKey <$> parseUrlPiece t



type GeoLocation = GeoLocationT Identity
deriving instance Show GeoLocation

data GeoLocationT f = GeoLocationT
  { geoLocation_id          :: C f PrimaryKeyType
  , geoLocation_gln         :: PrimaryKey LocationT f
  , geoLocation_latitude    :: C f (Maybe Latitude)
  , geoLocation_longitude   :: C f (Maybe Longitude)
  , geoLocation_address     :: C f (Maybe Text)
  , geoLocation_last_update :: C f (Maybe LocalTime)
  }
  deriving Generic

type GeoLocationPrimaryKey = PrimaryKey GeoLocationT Identity
deriving instance Show (PrimaryKey GeoLocationT Identity)
instance ToSchema GeoLocationPrimaryKey
instance ToParamSchema GeoLocationPrimaryKey
instance ToJSON (PrimaryKey GeoLocationT Identity) where
  toJSON (GeoLocationPrimaryKey uid) = toJSON uid
instance FromJSON (PrimaryKey GeoLocationT Identity) where
  parseJSON = fmap GeoLocationPrimaryKey . parseJSON

instance Beamable GeoLocationT
instance Beamable (PrimaryKey GeoLocationT)

instance Table GeoLocationT where
  newtype PrimaryKey GeoLocationT f = GeoLocationPrimaryKey (C f PrimaryKeyType)
    deriving Generic
  primaryKey = GeoLocationPrimaryKey . geoLocation_id
deriving instance Eq (PrimaryKey GeoLocationT Identity)

instance ToHttpApiData (PrimaryKey GeoLocationT Identity) where
  toUrlPiece (GeoLocationPrimaryKey locId) = toUrlPiece locId

instance FromHttpApiData (PrimaryKey GeoLocationT Identity) where
  parseUrlPiece t = GeoLocationPrimaryKey <$> parseUrlPiece t
