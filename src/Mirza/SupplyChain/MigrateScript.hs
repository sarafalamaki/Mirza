
-- | Contains the migration function of ``supplyChainDb``
module Mirza.SupplyChain.MigrateScript (migrationStorage) where

import           Mirza.Common.GS1BeamOrphans
import           Mirza.Common.Types               hiding (UserId)
import           Mirza.SupplyChain.StorageBeam

import           Data.UUID                        (UUID)
import           Database.Beam.Migrate.SQL        (DataType)
import           Database.Beam.Migrate.SQL.Tables
import           Database.Beam.Migrate.Types
import           Database.Beam.Postgres
import           Database.Beam.Postgres.Syntax    (PgDataTypeSyntax)

maxLen :: Word
maxLen = 120

-- length of the timezone offset
maxTzLen :: Word
maxTzLen = 10

pkSerialType :: DataType PgDataTypeSyntax UUID
pkSerialType = uuid

migrationStorage :: Migration PgCommandSyntax (CheckedDatabaseSettings Postgres SupplyChainDb)
migrationStorage =
  SupplyChainDb
    <$> createTable "users"
    (
      User
          (field "user_id" pkSerialType)
          (BizId (field "user_biz_id" gs1CompanyPrefixType))
          (field "user_first_name" (varchar (Just maxLen)) notNull)
          (field "user_last_name" (varchar (Just maxLen)) notNull)
          (field "user_phone_number" (varchar (Just maxLen)) notNull)
          (field "user_password_hash" binaryLargeObject notNull)
          (field "user_email_address" (varchar (Just maxLen)) unique)
    )
    <*> createTable "businesses"
    (
      Business
          (field "biz_gs1_company_prefix" gs1CompanyPrefixType)
          (field "biz_name" (varchar (Just maxLen)) notNull)
    )
    <*> createTable "contacts"
    (
      Contact
          (field "contact_id" pkSerialType)
          (UserId (field "contact_user1_id" pkSerialType))
          (UserId (field "contact_user2_id" pkSerialType))
    )
    <*> createTable "labels"
    (
      Label
          (field "label_id" pkSerialType)
          (field "label_type" (maybeType labelType))
          (WhatId (field "label_what_id" pkSerialType))
          (field "label_gs1_company_prefix" gs1CompanyPrefixType notNull)
          (field "label_item_reference" (maybeType itemRefType))
          (field "label_serial_number" (maybeType serialNumType))
          (field "label_state" (maybeType $ varchar (Just maxLen)))
          (field "label_lot" (maybeType lotType))
          (field "label_sgtin_filter_value" (maybeType sgtinFilterValue))
          (field "label_asset_type" (maybeType assetType))
          (field "label_quantity_amount" (maybeType amountType))
          (field "label_quantity_uom" (maybeType uomType))
    )
    <*> createTable "what_labels"
    (
      WhatLabel
          (field "what_label_id" pkSerialType)
          (WhatId (field "what_label_what_id" pkSerialType))
          (LabelId (field "what_label_label_id" pkSerialType))
    )
    <*> createTable "items"
    (
      Item
          (field "item_id" pkSerialType)
          (LabelId (field "item_label_id" pkSerialType))
          (field "item_description" (varchar (Just maxLen)) notNull)
    )
    <*> createTable "transformations"
    (
      Transformation
          (field "transformation_id" pkSerialType)
          (field "transformation_description" (varchar (Just maxLen)) notNull)
          (BizId (field "transformation_biz_id" gs1CompanyPrefixType))
    )
    <*> createTable "locations"
    (
      Location
          (field "location_id" locationRefType)
          (BizId (field "location_biz_id" gs1CompanyPrefixType))
          (field "location_function" (varchar (Just maxLen)) notNull)
          (field "location_site_name" (varchar (Just maxLen)) notNull)
          (field "location_address" (varchar (Just maxLen)) notNull)
          -- this needs to be locationReferenceNum
          (field "location_lat" double)
          (field "location_long" double)
    )
    <*> createTable "events"
    (
      Event
          (field "event_id" pkSerialType)
          (field "event_foreign_event_id" (maybeType uuid))
          (UserId (field "event_created_by" pkSerialType))
          (field "event_json" text notNull)
    )
    <*> createTable "whats"
    (
      What
          (field "what_id" pkSerialType)
          (field "what_event_type" (maybeType eventType))
          (field "what_action" (maybeType actionType))
          (LabelId (field "what_parent" (maybeType pkSerialType)))
          (BizTransactionId (field "what_biz_transaction_id" (maybeType pkSerialType)))
          (TransformationId (field "what_transformation_id" (maybeType pkSerialType)))
          (EventId (field "what_event_id" pkSerialType))
    )
    <*> createTable "biz_transactions"
    (
      BizTransaction
          (field "biz_transaction_id" pkSerialType)
          (field "biz_transaction_type_id" (varchar (Just maxLen)))
          (field "biz_transaction_id_urn" (varchar (Just maxLen)))
          (EventId (field "biz_transaction_event_id" pkSerialType))
    )
    <*> createTable "whys"
    (
      Why
          (field "why_id" pkSerialType)
          (field "why_biz_step" (maybeType text))
          (field "why_disposition" (maybeType text))
          (EventId (field "why_event_id" pkSerialType))
    )
    <*> createTable "wheres"
    (
      Where
          (field "where_id" pkSerialType)
          (field "where_gs1_company_prefix" gs1CompanyPrefixType notNull)
          (field "where_source_dest_type" (maybeType srcDestType))
          (field "where_gs1_location_id" (locationRefType) notNull)
          (field "where_location_field" locationType notNull)
          (field "where_sgln_ext" (maybeType sglnExtType))
          (EventId (field "where_event_id" pkSerialType))
    )
    <*> createTable "whens"
    (
      When
          (field "when_id" pkSerialType)
          (field "when_event_time" timestamptz notNull)
          (field "when_record_time" (maybeType timestamptz))
          (field "when_time_zone" (varchar (Just maxTzLen)) notNull)
          (EventId (field "when_event_id" pkSerialType))
    )
    <*> createTable "label_events"
    (
      LabelEvent
          (field "label_event_id" pkSerialType)
          (LabelId (field "label_event_label_id" pkSerialType))
          (EventId (field "label_event_event_id" pkSerialType))
    )
    <*> createTable "user_event"
    (
      UserEvent
          (field "user_events_id" pkSerialType)
          (EventId (field "user_events_event_id" pkSerialType notNull))
          (UserId (field "user_events_user_id" pkSerialType notNull))
          (field "user_events_has_signed" boolean notNull)
          (UserId (field "user_events_added_by" pkSerialType notNull))
          (field "user_events_signed_hash" (maybeType bytea))
    )
    <*> createTable "signatures"
    (
     Signature
          (field "signature_id" pkSerialType)
          (EventId (field "signature_event_id" pkSerialType notNull))
          (field "signature_key_id" keyId notNull)
          (field "signature_signature" bytea notNull)
          (field "signature_digest" bytea notNull)
          (field "signature_timestamp" timestamptz notNull)
    )
    <*> createTable "hashes"
    (
      Hashes
          (field "hashes_id" pkSerialType)
          (EventId (field "hashes_event_id" pkSerialType notNull))
          (field "hashes_hash" bytea notNull)
          (field "hashes_is_signed" boolean notNull)
          (UserId (field "hashes_signed_by_user_id" pkSerialType notNull))
          (field "hashes_key_id" keyId notNull)
    )
    <*> createTable "blockchain"
    (
      BlockChain
          (field "blockchain_id" pkSerialType)
          (EventId (field "blockchain_event_id" pkSerialType notNull))
          (field "blockchain_hash" bytea notNull)
          (field "blockchain_address" text notNull)
          (field "blockchain_foreign_id" int notNull)
    )
