{-# LANGUAGE DeriveGeneric         #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE StandaloneDeriving    #-}
{-# LANGUAGE TypeFamilies          #-}
{-# LANGUAGE UndecidableInstances  #-}

-- | This module contains all the table definitions
-- Convention: Table types and constructors are suffixed with T (for Table).
module Mirza.OrgRegistry.Database.Schema.V0001 where

import           Mirza.OrgRegistry.Types     (OAuthSub (..), oAuthSubFieldType)

import qualified Data.GS1.EPC                as EPC
import           Mirza.Common.Beam           (lastUpdateField, pkSerialType, defaultFkConstraint)
import           Mirza.Common.GS1BeamOrphans
import           Mirza.Common.Types          (PrimaryKeyType)
import           Mirza.OrgRegistry.Types

import           Control.Lens

import           Crypto.JOSE.JWK             (JWK)
import           Data.Text                   (Text)
import           Data.Time                   (LocalTime)

import           Servant                     (FromHttpApiData (parseUrlPiece),
                                              ToHttpApiData (toUrlPiece))

import           Database.Beam               as B
import           Database.Beam.Migrate.SQL   as BSQL
import           Database.Beam.Migrate.Types
import           Database.Beam.Postgres      (PgJSON, Postgres, json, text)

import           Data.Aeson                  hiding (json)
import           Data.Swagger                hiding (prefix)

import           GHC.Generics                (Generic)

-- Convention: Table types and constructors are suffixed with T (for Table).

-- Database
data OrgRegistryDB f = OrgRegistryDB
  { _orgs         :: f (TableEntity OrgT)
  , _users        :: f (TableEntity UserT)
  , _orgMapping   :: f (TableEntity OrgMappingT)
  , _keys         :: f (TableEntity KeyT)
  , _locations    :: f (TableEntity LocationT)
  , _geoLocations :: f (TableEntity GeoLocationT)
  }
  deriving Generic
instance Database anybackend OrgRegistryDB


-- Migration: Intialisation -> V1.
migration :: () -> Migration Postgres (CheckedDatabaseSettings Postgres OrgRegistryDB)
migration () = do
  orgsT <- createTable "orgs" $
    OrgT (field "org_gs1_company_prefix" gs1CompanyPrefixFieldType notNull)
         (field "org_name" text notNull)
         (field "org_url" text notNull)
         lastUpdateField
            
  usersT <- createTable "users" $
    UserT (field "oauth_sub" oAuthSubFieldType notNull)
          lastUpdateField

  orgMappingT <- createTable "org_mapping" $
    OrgMappingT (OrgPrimaryKey $ field "mapping_org_id" gs1CompanyPrefixFieldType notNull (defaultFkConstraint "orgs" ["org_gs1_company_prefix"]))
                (UserPrimaryKey $ field "mapping_user_oauth_sub" oAuthSubFieldType notNull (defaultFkConstraint "users" ["oauth_sub"]))
                lastUpdateField

  keysT <- createTable "keys" $
    KeyT (field "key_id" pkSerialType notNull)
         (OrgPrimaryKey $ field "key_org" gs1CompanyPrefixFieldType notNull (defaultFkConstraint "orgs" ["org_gs1_company_prefix"]))
         (field "jwk" json notNull)
         (field "creation_time" timestamp)
         (field "revocation_time" (maybeType timestamp))
         (UserPrimaryKey $ field "revoking_user_id" (maybeType oAuthSubFieldType) (defaultFkConstraint "users" ["oauth_sub"]))
         (field "expiration_time" (maybeType timestamp))
         lastUpdateField

  locationT <- createTable "location" $
    LocationT (field "location_gln" locationEPCType notNull)
              (OrgPrimaryKey $ field "location_org_id" gs1CompanyPrefixFieldType notNull (defaultFkConstraint "orgs" ["org_gs1_company_prefix"]))
              lastUpdateField

  geoLocationT <- createTable "geo_location" $
    GeoLocationT (field "geo_location_id" pkSerialType notNull)
                 (LocationPrimaryKey $ field "geo_location_gln" locationEPCType notNull (defaultFkConstraint "location" ["location_gln"]))
                 (field "geo_location_lat"     (maybeType latitudeType))
                 (field "geo_location_lon"     (maybeType longitudeType))
                 (field "geo_location_address" (maybeType text))
                 lastUpdateField
    
  pure $ OrgRegistryDB orgsT usersT orgMappingT keysT locationT geoLocationT


--------------------------------------------------------------------------------
-- User table.
--------------------------------------------------------------------------------

type User = UserT Identity
deriving instance Show User

data UserT f = UserT
  { user_oauth_sub   :: C f OAuthSub
  , user_last_update :: C f (Maybe LocalTime)
  } deriving Generic

type UserPrimaryKey = PrimaryKey UserT Identity
deriving instance Show (PrimaryKey UserT Identity)
instance ToSchema UserPrimaryKey
instance ToParamSchema UserPrimaryKey
instance ToJSON (PrimaryKey UserT Identity) where
  toJSON (UserPrimaryKey uid) = toJSON uid
instance FromJSON (PrimaryKey UserT Identity) where
  parseJSON = fmap UserPrimaryKey . parseJSON

instance Beamable UserT
instance Beamable (PrimaryKey UserT)

instance Table UserT where
  data PrimaryKey UserT f = UserPrimaryKey (C f OAuthSub)
    deriving Generic
  primaryKey = UserPrimaryKey . user_oauth_sub
deriving instance Eq (PrimaryKey UserT Identity)


--------------------------------------------------------------------------------
-- Org Table
--------------------------------------------------------------------------------

-- CBV-Standard-1-2-r-2016-09-29.pdf Page 11

type Org = OrgT Identity
deriving instance Show Org

data OrgT f = OrgT
  { org_gs1_company_prefix :: C f EPC.GS1CompanyPrefix
  , org_name               :: C f Text
  , org_url                :: C f Text
  , org_last_update        :: C f (Maybe LocalTime)
  }
  deriving Generic

type OrgPrimaryKey = PrimaryKey OrgT Identity
deriving instance Show (PrimaryKey OrgT Identity)

instance Beamable OrgT
instance Beamable (PrimaryKey OrgT)

instance Table OrgT where
  data PrimaryKey OrgT f = OrgPrimaryKey (C f EPC.GS1CompanyPrefix)
    deriving Generic
  primaryKey = OrgPrimaryKey . org_gs1_company_prefix
deriving instance Eq (PrimaryKey OrgT Identity)


orgPrimaryKeyToGS1CompanyPrefix :: OrgPrimaryKey -> EPC.GS1CompanyPrefix
orgPrimaryKeyToGS1CompanyPrefix (OrgPrimaryKey prefix) = prefix


--------------------------------------------------------------------------------
-- Organisation Mapping Table
--------------------------------------------------------------------------------

type OrgMapping = OrgMappingT Identity
deriving instance Show OrgMapping

data OrgMappingT f = OrgMappingT
  { org_mapping_gs1_company_prefix :: PrimaryKey OrgT f
  , org_mapping_user_oauth_sub     :: PrimaryKey UserT f
  , org_mapping_last_update        :: C f (Maybe LocalTime)
  }
  deriving Generic

type OrgMappingId = PrimaryKey OrgMappingT Identity
deriving instance Show (PrimaryKey OrgMappingT Identity)

instance Beamable OrgMappingT
instance Beamable (PrimaryKey OrgMappingT)

instance Table OrgMappingT where
  data PrimaryKey OrgMappingT f = OrgMappingId (PrimaryKey OrgT f) (PrimaryKey UserT f)
    deriving Generic
  primaryKey = OrgMappingId <$> org_mapping_gs1_company_prefix <*> org_mapping_user_oauth_sub
deriving instance Eq (PrimaryKey OrgMappingT Identity)


--------------------------------------------------------------------------------
-- Keys Table
--------------------------------------------------------------------------------

type Key = KeyT Identity
deriving instance Show Key
deriving instance Show ( PrimaryKey UserT (Nullable Identity))

-- The types are not ``UTCTime`` because beam does not support UTCTime
-- See this discussion for details:
-- https://groups.google.com/forum/#!topic/beam-discussion/DcC0yik7Pxc
-- However, all times are converted to UTCTime using methods from typeclasses
-- defined in Mirza.Common.Time
data KeyT f = KeyT
  { key_id           :: C f PrimaryKeyType
  , key_org          :: PrimaryKey OrgT f
  , key_jwk          :: C f (PgJSON JWK)
  , creation_time    :: C f LocalTime -- Stored as UTC Time
  -- It would be nicer and cleaner to store the revocation time and user as a
  -- Maybe (LocalTime, UserId) rather then as two independent Maybe fields as
  -- they should only ever be stored in composite and would prevent accidental
  -- errors where they are not stored the same (i.e. one is a Just and the other
  -- is Nothing), but currently we don't know how to do this / if it is even
  -- possible and so have this implementation for now...
  , revocation_time  :: C f (Maybe LocalTime) -- Stored as UTC Time
  , revoking_user_id :: PrimaryKey UserT (Nullable f)
  , expiration_time  :: C f (Maybe LocalTime) -- Stored as UTC Time
  , key_last_update  :: C f (Maybe LocalTime)
  }
  deriving Generic

type KeyPrimaryKey = PrimaryKey KeyT Identity
deriving instance Show (PrimaryKey KeyT Identity)

instance Beamable KeyT
instance Beamable (PrimaryKey KeyT)

instance Table KeyT where
  data PrimaryKey KeyT f = KeyPrimaryKey (C f PrimaryKeyType)
    deriving Generic
  primaryKey = KeyPrimaryKey . key_id
deriving instance Eq (PrimaryKey KeyT Identity)


--------------------------------------------------------------------------------
-- Locations Table
--------------------------------------------------------------------------------

type Location = LocationT Identity
deriving instance Show Location

data LocationT f = LocationT
  { location_gln         :: C f EPC.LocationEPC
  , location_org_id      :: PrimaryKey OrgT f
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


--------------------------------------------------------------------------------
-- GeoLocations Table
--------------------------------------------------------------------------------

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
