{-# LANGUAGE DataKinds             #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE NamedFieldPuns        #-}
{-# LANGUAGE RecordWildCards       #-}


module Mirza.BusinessRegistry.Handlers.Location
  ( addLocation
  , getLocationByGLN
  , searchLocation
  , uxLocation
  ) where


import           Mirza.BusinessRegistry.Database.Schema   as DB
import           Mirza.BusinessRegistry.SqlUtils
import           Mirza.BusinessRegistry.Types             as BT
import           Mirza.Common.Types                       (Member)
import           Mirza.Common.Utils
import           Mirza.Common.Time                        (toDbTimestamp)
import qualified Mirza.BusinessRegistry.Handlers.Business as BRHB (searchBusinesses)


import           Data.GS1.EPC                             (LocationEPC, GS1CompanyPrefix)

import           Database.Beam                            as B
import           Database.Beam.Backend.SQL.BeamExtensions

import           GHC.Stack                                (HasCallStack,
                                                           callStack)

import           Control.Lens                             (( # ))
import           Control.Lens.Operators                   ((&))
import           Control.Monad.Error.Hoist                ((<!?>))
import           Data.Time                                (UTCTime)
import           Data.Foldable                            (for_, find)

addLocation :: ( Member context '[HasEnvType, HasConnPool, HasLogging]
               , Member err     '[AsSqlError, AsBRError])
            => AuthUser
            -> NewLocation
            -> AppM context err LocationId
addLocation auser newLoc = do
  newLocId <- newUUID
  newGeoLocId <- newUUID
  (fmap primaryKey)
    . (handleError (handleSqlUniqueViloation "location_pkey" (\_sqlerr -> _LocationExistsBRE # ())))
    . runDb
    . addLocationQuery auser newLocId (GeoLocationId newGeoLocId)
    $ newLoc
  -- TODO: discover which constraints are needed and what we should catch here
  -- (awaiting tests)
  -- where
  --   errHandler :: (AsSqlError err, AsBRError err, MonadError err m, MonadIO m) => err -> m a
  --   errHandler e = case e ^? _SqlError of
  --     Nothing -> throwError e
  --     Just sqlErr ->
  --       case constraintViolation sqlErr of
  --         Just (UniqueViolation "businesses_pkey") -> throwing_ _GS1CompanyPrefixExistsBRE
  --         _ -> throwError e

addLocationQuery  :: ( Member context '[]
                     , Member err     '[AsBRError]
                     , HasCallStack)
                  => AuthUser
                  -> PrimaryKeyType
                  -> GeoLocationId
                  -> NewLocation
                  -> DB context err Location
addLocationQuery (AuthUser (BT.UserId uId)) locId geoLocId newLoc = do
  mbizId <- pg $ runSelectReturningOne $ select $ do
    user <- all_ (_users businessRegistryDB)
    guard_ (user_id user ==. val_ uId)
    pure $ user_biz_id user
  case mbizId of
               -- Since the user has authenticated, this should never happen
    Nothing -> throwing _UnexpectedErrorBRE callStack
    Just bizId -> do
      let (loc,geoLoc) = newLocationToLocation locId geoLocId bizId newLoc
      res <- pg $ runInsertReturningList (_locations businessRegistryDB) $
                  insertValues [loc]
      case res of
        [r] -> do

            _ <- pg $ runInsertReturningList (_geoLocations businessRegistryDB) $
                 insertValues [geoLoc]
            pure r
        _   -> throwing _UnexpectedErrorBRE callStack


newLocationToLocation :: PrimaryKeyType
                      -> GeoLocationId
                      -> BizId
                      -> NewLocation
                      -> (Location, GeoLocation)
newLocationToLocation
  locId (GeoLocationId geoLocId) bizId
  NewLocation{newLocGLN, newLocCoords, newLocAddress} =
    ( LocationT
        { location_id          = locId
        , location_biz_id      = bizId
        , location_gln         = newLocGLN
        , location_last_update = Nothing
        }
      , GeoLocationT
        { geoLocation_id          = geoLocId
        , geoLocation_gln         = LocationId newLocGLN
        , geoLocation_latitude    = fst <$> newLocCoords
        , geoLocation_longitude   = snd <$> newLocCoords
        , geoLocation_address     = newLocAddress
        , geoLocation_last_update = Nothing
        }
    )


getLocationByGLN :: ( Member context '[HasLogging, HasConnPool, HasEnvType]
                    , Member err     '[AsBRError, AsSqlError]
                    , HasCallStack)
                    => AuthUser
                    -> LocationEPC
                    -> AppM context err LocationResponse
getLocationByGLN _user gln = locationToLocationResponse
  <$> (runDb (getLocationByGLNQuery gln) <!?>  (_LocationNotKnownBRE # ()))


locationToLocationResponse :: (Location,GeoLocation) -> LocationResponse
locationToLocationResponse (LocationT{location_biz_id = BizId bizId,..} , GeoLocationT{..}) = LocationResponse
  { locationId    = location_id
  , locationGLN   = location_gln
  , locationBiz   = bizId
  , geoLocId      = geoLocation_id
  , geoLocCoord   = (,) <$> geoLocation_latitude <*> geoLocation_longitude
  , geoLocAddress = geoLocation_address
  }


getLocationByGLNQuery :: ( Member context '[]
                         , Member err     '[AsBRError])
                         => LocationEPC
                         -> DB context err (Maybe (Location, GeoLocation))
getLocationByGLNQuery gln = pg $ runSelectReturningOne $ select $ do
  loc   <- all_ (_locations businessRegistryDB)
  geoloc <- all_ (_geoLocations businessRegistryDB)
             & orderBy_ (desc_ . geoLocation_last_update)
  guard_ (primaryKey loc ==. val_ (LocationId gln))
  guard_ (geoLocation_gln geoloc ==. primaryKey loc)
  pure (loc,geoloc)


searchLocation :: (Member context '[HasDB]
                  , Member err    '[AsSqlError])
               => AuthUser -> Maybe GS1CompanyPrefix -> Maybe UTCTime -> AppM context err [LocationResponse]
searchLocation _user mpfx mafter = fmap locationToLocationResponse
  <$> runDb (searchLocationQuery mpfx mafter)

searchLocationQuery :: Maybe GS1CompanyPrefix -> Maybe UTCTime -> DB context err [(Location,GeoLocation)]
searchLocationQuery mpfx mafter = pg $ runSelectReturningList $ select $ do

  loc    <- all_ (_locations businessRegistryDB)
  geoloc <- all_ (_geoLocations businessRegistryDB)
              & orderBy_ (desc_ . geoLocation_last_update)
              -- Temporarily remove the following constraint which restricts the search to the last entry added.
              -- This was causing a bug which effected the implementation of https://github.com/data61/Mirza/issues/340.
              -- This issue is being tracked with issue: https://github.com/data61/Mirza/issues/364
              -- & limit_ 1

  guard_ (geoLocation_gln geoloc `references_` loc)

  for_ mpfx $ \pfx -> do
    biz    <- all_ (_businesses businessRegistryDB)
    guard_ (location_biz_id loc `references_` biz)
    guard_ (val_ (BizId pfx) `references_` biz)

  for_ mafter $ \after ->
    guard_ (location_last_update loc       >=. just_ (val_ (toDbTimestamp after))
        ||. geoLocation_last_update geoloc >=. just_ (val_ (toDbTimestamp after)))

  pure (loc, geoloc)


-- The maximum number of companies that can be searched for in a single uxLocation query.
maxPrefixesForUxLocations :: Int
maxPrefixesForUxLocations = 25


uxLocation :: ( Member context '[HasDB]
              , Member err     '[AsSqlError])
           => AuthUser -> [GS1CompanyPrefix] -> AppM context err [BusinessAndLocationResponse]
uxLocation user userPrefixes = do
  -- We constrain the maximum number of company prefixes that can be quired in a single invocation to prevent abuse.
  let prefixes = take maxPrefixesForUxLocations userPrefixes
  let locations = traverse getLocations prefixes
  let businesses = traverse getBusinesses prefixes
  buildBusinessAndLocationResponses <$> (concat <$> businesses) <*> (concat <$> locations)

  where
    getLocations :: (Member context '[HasDB], Member err '[AsSqlError])
                 => GS1CompanyPrefix -> AppM context err [LocationResponse]
    getLocations prefix = searchLocation user (Just prefix) Nothing

    getBusinesses :: (Member context '[HasDB], Member err '[AsSqlError])
                  => GS1CompanyPrefix -> AppM context err [BusinessResponse]
    getBusinesses prefix  = BRHB.searchBusinesses (Just prefix) Nothing Nothing

    matchId :: LocationResponse -> BusinessResponse -> Bool
    matchId location business = (locationBiz location) == (businessGS1CompanyPrefix business)

    buildBusinessAndLocationResponse :: [BusinessResponse] -> LocationResponse -> BusinessAndLocationResponse
    buildBusinessAndLocationResponse businesses location = BusinessAndLocationResponse business location
                                                           where
                                                             -- todo should probably also log here to indicate that something went wrong.
                                                             unfoundBusiness = (BusinessResponse (locationBiz location) "[Unknown]")
                                                             business = maybe unfoundBusiness id $ find (matchId location) businesses

    buildBusinessAndLocationResponses :: [BusinessResponse] -> [LocationResponse] -> [BusinessAndLocationResponse]
    buildBusinessAndLocationResponses businesses locations = (buildBusinessAndLocationResponse businesses) <$> locations
