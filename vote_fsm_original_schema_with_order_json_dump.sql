-- Vote FSM + taxi core order JSON dump for the original Maskit26/FSM schema.
--
-- Compatible with the original database dumps from:
--   https://github.com/Maskit26/FSM/tree/main/database
--
-- What this dump adds:
--   1. The Vote FSM states/actions/transitions for fsm_perform_action().
--   2. A JSON metadata column on local orders for taxi-core payload/context.
--   3. Mapping/runtime tables from the xlsx comparison where they are relevant
--      for core API integration:
--        - core_order_mapping
--        - server_fsm_instances
--   4. A registry of API payload keys and full VOTE/OFFER JSON templates.
--
-- Notes:
--   - The stored-procedure engine remains table-driven through fsm_states,
--     fsm_actions and fsm_transitions.
--   - Taxi API order details live in JSON metadata/templates instead of being
--     forced into the delivery-specific orders columns.
--   - The b_options/c_options keys are based on the public API description and
--     /taxi/c/gruzvill/api/v1/data site_constants.
--   - This file is idempotent: repeated import should not duplicate rows.

USE `testdb`;

-- ---------------------------------------------------------------------------
-- Schema extensions for taxi core integration
-- ---------------------------------------------------------------------------

SET @orders_metadata_json_exists := (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'orders'
    AND COLUMN_NAME = 'metadata_json'
);

SET @orders_metadata_json_sql := IF(
  @orders_metadata_json_exists = 0,
  'ALTER TABLE `orders` ADD COLUMN `metadata_json` JSON NULL AFTER `description`',
  'SELECT 1'
);

PREPARE stmt_orders_metadata_json FROM @orders_metadata_json_sql;
EXECUTE stmt_orders_metadata_json;
DEALLOCATE PREPARE stmt_orders_metadata_json;

CREATE TABLE IF NOT EXISTS `core_order_mapping` (
  `id` int NOT NULL AUTO_INCREMENT,
  `local_order_id` int NOT NULL,
  `core_order_id` int DEFAULT NULL,
  `role` varchar(50) DEFAULT NULL,
  `kind` int DEFAULT 1,
  `upper` int DEFAULT NULL,
  `b_state` int DEFAULT NULL,
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `client_local_user_id` int DEFAULT NULL,
  `performer_local_user_id` int DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_core_order_mapping_local_order` (`local_order_id`),
  KEY `idx_core_order_mapping_core_order` (`core_order_id`),
  KEY `idx_core_order_mapping_kind_upper` (`kind`, `upper`),
  CONSTRAINT `core_order_mapping_ibfk_1`
    FOREIGN KEY (`local_order_id`) REFERENCES `orders` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS `server_fsm_instances` (
  `id` int NOT NULL AUTO_INCREMENT,
  `entity_type` varchar(50) NOT NULL,
  `entity_id` int NOT NULL,
  `process_name` varchar(100) NOT NULL,
  `fsm_state` varchar(100) DEFAULT NULL,
  `next_timer_at` datetime DEFAULT NULL,
  `attempts_count` int DEFAULT 0,
  `last_error` text,
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `requested_by_user_id` int DEFAULT NULL,
  `requested_user_role` varchar(50) DEFAULT NULL,
  `target_user_id` int DEFAULT NULL,
  `target_role` varchar(50) DEFAULT NULL,
  `metadata_json` JSON DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_server_fsm_instances_entity` (`entity_type`, `entity_id`),
  KEY `idx_server_fsm_instances_process` (`process_name`, `fsm_state`),
  KEY `idx_server_fsm_instances_timer` (`next_timer_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS `taxi_order_payload_keys` (
  `scope` enum('create_payload','b_options','c_options','reserved_b_options','edit_payload','action_payload') NOT NULL,
  `key_name` varchar(100) NOT NULL,
  `is_required` tinyint(1) DEFAULT 0,
  `allowed_json` JSON DEFAULT NULL,
  `source` varchar(100) DEFAULT NULL,
  `notes` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`scope`, `key_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS `taxi_order_payload_templates` (
  `id` int NOT NULL AUTO_INCREMENT,
  `code` varchar(100) NOT NULL,
  `order_mode` enum('DIRECT','VOTE','OFFER') NOT NULL,
  `title` varchar(255) DEFAULT NULL,
  `create_payload_json` JSON NOT NULL,
  `b_options_json` JSON NOT NULL,
  `edit_options_ops_json` JSON DEFAULT NULL,
  `backend_actions_json` JSON NOT NULL,
  `notes` text,
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_taxi_order_payload_templates_code` (`code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

START TRANSACTION;

-- ---------------------------------------------------------------------------
-- Vote states
-- ---------------------------------------------------------------------------

INSERT INTO `fsm_states` (`name`, `label`)
SELECT 'order_vote_waiting_candidates', 'Vote: waiting for candidate drivers'
WHERE NOT EXISTS (
  SELECT 1 FROM `fsm_states` WHERE `name` = 'order_vote_waiting_candidates'
);

INSERT INTO `fsm_states` (`name`, `label`)
SELECT 'order_vote_driver_assigned', 'Vote: driver selected as performer'
WHERE NOT EXISTS (
  SELECT 1 FROM `fsm_states` WHERE `name` = 'order_vote_driver_assigned'
);

INSERT INTO `fsm_states` (`name`, `label`)
SELECT 'order_vote_no_show', 'Vote: client no-show'
WHERE NOT EXISTS (
  SELECT 1 FROM `fsm_states` WHERE `name` = 'order_vote_no_show'
);

-- ---------------------------------------------------------------------------
-- Vote actions
-- ---------------------------------------------------------------------------

INSERT INTO `fsm_actions` (`name`, `label`)
SELECT 'order_publish_vote', 'Publish Vote order'
WHERE NOT EXISTS (
  SELECT 1 FROM `fsm_actions` WHERE `name` = 'order_publish_vote'
);

INSERT INTO `fsm_actions` (`name`, `label`)
SELECT 'order_select_candidate', 'Client selects candidate driver'
WHERE NOT EXISTS (
  SELECT 1 FROM `fsm_actions` WHERE `name` = 'order_select_candidate'
);

INSERT INTO `fsm_actions` (`name`, `label`)
SELECT 'order_release_candidate', 'Release selected candidate'
WHERE NOT EXISTS (
  SELECT 1 FROM `fsm_actions` WHERE `name` = 'order_release_candidate'
);

INSERT INTO `fsm_actions` (`name`, `label`)
SELECT 'order_cancel_by_client', 'Client cancels order'
WHERE NOT EXISTS (
  SELECT 1 FROM `fsm_actions` WHERE `name` = 'order_cancel_by_client'
);

INSERT INTO `fsm_actions` (`name`, `label`)
SELECT 'order_no_show', 'Client no-show'
WHERE NOT EXISTS (
  SELECT 1 FROM `fsm_actions` WHERE `name` = 'order_no_show'
);

-- ---------------------------------------------------------------------------
-- Vote transitions
-- ---------------------------------------------------------------------------

INSERT INTO `fsm_transitions` (`from_state_id`, `action_id`, `to_state_id`)
SELECT fs_from.`id`, action.`id`, fs_to.`id`
FROM `fsm_states` fs_from
JOIN `fsm_actions` action ON action.`name` = 'order_publish_vote'
JOIN `fsm_states` fs_to ON fs_to.`name` = 'order_vote_waiting_candidates'
WHERE fs_from.`name` = 'order_created'
  AND NOT EXISTS (
    SELECT 1 FROM `fsm_transitions` existing
    WHERE existing.`from_state_id` = fs_from.`id`
      AND existing.`action_id` = action.`id`
      AND existing.`to_state_id` = fs_to.`id`
  );

INSERT INTO `fsm_transitions` (`from_state_id`, `action_id`, `to_state_id`)
SELECT fs_from.`id`, action.`id`, fs_to.`id`
FROM `fsm_states` fs_from
JOIN `fsm_actions` action ON action.`name` = 'order_select_candidate'
JOIN `fsm_states` fs_to ON fs_to.`name` = 'order_vote_driver_assigned'
WHERE fs_from.`name` = 'order_vote_waiting_candidates'
  AND NOT EXISTS (
    SELECT 1 FROM `fsm_transitions` existing
    WHERE existing.`from_state_id` = fs_from.`id`
      AND existing.`action_id` = action.`id`
      AND existing.`to_state_id` = fs_to.`id`
  );

INSERT INTO `fsm_transitions` (`from_state_id`, `action_id`, `to_state_id`)
SELECT fs_from.`id`, action.`id`, fs_to.`id`
FROM `fsm_states` fs_from
JOIN `fsm_actions` action ON action.`name` = 'order_cancel_by_client'
JOIN `fsm_states` fs_to ON fs_to.`name` = 'order_cancelled'
WHERE fs_from.`name` = 'order_vote_waiting_candidates'
  AND NOT EXISTS (
    SELECT 1 FROM `fsm_transitions` existing
    WHERE existing.`from_state_id` = fs_from.`id`
      AND existing.`action_id` = action.`id`
      AND existing.`to_state_id` = fs_to.`id`
  );

INSERT INTO `fsm_transitions` (`from_state_id`, `action_id`, `to_state_id`)
SELECT fs_from.`id`, action.`id`, fs_to.`id`
FROM `fsm_states` fs_from
JOIN `fsm_actions` action ON action.`name` = 'order_cancel_by_client'
JOIN `fsm_states` fs_to ON fs_to.`name` = 'order_cancelled'
WHERE fs_from.`name` = 'order_vote_driver_assigned'
  AND NOT EXISTS (
    SELECT 1 FROM `fsm_transitions` existing
    WHERE existing.`from_state_id` = fs_from.`id`
      AND existing.`action_id` = action.`id`
      AND existing.`to_state_id` = fs_to.`id`
  );

INSERT INTO `fsm_transitions` (`from_state_id`, `action_id`, `to_state_id`)
SELECT fs_from.`id`, action.`id`, fs_to.`id`
FROM `fsm_states` fs_from
JOIN `fsm_actions` action ON action.`name` = 'order_release_candidate'
JOIN `fsm_states` fs_to ON fs_to.`name` = 'order_vote_waiting_candidates'
WHERE fs_from.`name` = 'order_vote_driver_assigned'
  AND NOT EXISTS (
    SELECT 1 FROM `fsm_transitions` existing
    WHERE existing.`from_state_id` = fs_from.`id`
      AND existing.`action_id` = action.`id`
      AND existing.`to_state_id` = fs_to.`id`
  );

INSERT INTO `fsm_transitions` (`from_state_id`, `action_id`, `to_state_id`)
SELECT fs_from.`id`, action.`id`, fs_to.`id`
FROM `fsm_states` fs_from
JOIN `fsm_actions` action ON action.`name` = 'order_no_show'
JOIN `fsm_states` fs_to ON fs_to.`name` = 'order_vote_no_show'
WHERE fs_from.`name` = 'order_vote_driver_assigned'
  AND NOT EXISTS (
    SELECT 1 FROM `fsm_transitions` existing
    WHERE existing.`from_state_id` = fs_from.`id`
      AND existing.`action_id` = action.`id`
      AND existing.`to_state_id` = fs_to.`id`
  );

-- ---------------------------------------------------------------------------
-- Taxi API key registry
-- ---------------------------------------------------------------------------

INSERT INTO `taxi_order_payload_keys`
  (`scope`, `key_name`, `is_required`, `allowed_json`, `source`, `notes`)
VALUES
  ('create_payload','b_start_address',0,NULL,'api_docs','Pickup address. Address or coordinates must be present.'),
  ('create_payload','b_start_latitude',0,NULL,'api_docs','Pickup latitude.'),
  ('create_payload','b_start_longitude',0,NULL,'api_docs','Pickup longitude.'),
  ('create_payload','b_destination_address',0,NULL,'api_docs','Destination address.'),
  ('create_payload','b_destination_latitude',0,NULL,'api_docs','Destination latitude.'),
  ('create_payload','b_destination_longitude',0,NULL,'api_docs','Destination longitude.'),
  ('create_payload','b_start_datetime',1,NULL,'api_docs','Taxi arrival datetime; supports now/any.'),
  ('create_payload','b_custom_comment',0,NULL,'api_docs','Free comment; used for [CASE] scenario marker.'),
  ('create_payload','b_flight_number',0,NULL,'api_docs','Flight number.'),
  ('create_payload','b_terminal',0,NULL,'api_docs','Terminal.'),
  ('create_payload','b_passengers_count',0,NULL,'api_docs','Passenger count.'),
  ('create_payload','b_luggage_count',0,NULL,'api_docs','Luggage count.'),
  ('create_payload','b_placard',0,NULL,'api_docs','Placard text.'),
  ('create_payload','b_car_class',0,NULL,'api_docs','Car class id.'),
  ('create_payload','b_payment_way',1,NULL,'api_docs','Payment way id.'),
  ('create_payload','b_payment_card',0,NULL,'api_docs','Payment card id.'),
  ('create_payload','b_cars_count',0,NULL,'api_docs','Required car count; 0 is used by offer/intercity mode.'),
  ('create_payload','b_max_waiting',0,NULL,'api_docs','Max waiting seconds.'),
  ('create_payload','b_options',0,NULL,'api_docs','Client JSON options.'),
  ('create_payload','b_contact',0,NULL,'api_docs','Contact data. Current emulator sends phone string.'),
  ('create_payload','b_comments',0,NULL,'api_docs','Booking comment ids.'),
  ('create_payload','b_services',0,NULL,'api_docs','Service ids; service 5 is used for Vote.'),
  ('create_payload','b_location_class',0,NULL,'api_docs','Booking location class id.'),
  ('create_payload','b_currency',0,NULL,'api_docs','Currency code.'),
  ('create_payload','b_only_offer',0,NULL,'api_docs','If 1, backend creates booking_states=6.'),
  ('create_payload','countries_list_start',0,NULL,'api_docs','Pickup country; backend may autofill from coordinates.'),
  ('create_payload','countries_list_destination',0,NULL,'api_docs','Destination country; backend may autofill from coordinates.'),
  ('create_payload','region_start',0,NULL,'api_docs','Pickup region; backend may autofill from coordinates.'),
  ('create_payload','region_destination',0,NULL,'api_docs','Destination region; backend may autofill from coordinates.'),
  ('create_payload','city_start',0,NULL,'api_docs','Pickup city; backend may autofill from coordinates.'),
  ('create_payload','city_destination',0,NULL,'api_docs','Destination city; backend may autofill from coordinates.'),
  ('create_payload','u_id',0,NULL,'api_docs','Client id; admin only.'),
  ('create_payload','b_pc',0,NULL,'api_docs','Promo code for stadium profile.'),
  ('create_payload','kind',0,'{"default":1,"normal":1,"driver_suborder":2,"courier_suborder":3}','api_docs','Order kind.'),
  ('create_payload','upper',0,NULL,'api_docs','Parent order id.'),
  ('b_options','fromShortAddress',0,NULL,'gruzvill_site_constants','Allowed b_options key.'),
  ('b_options','toShortAddress',0,NULL,'gruzvill_site_constants','Allowed b_options key.'),
  ('b_options','courier_auto',0,NULL,'gruzvill_site_constants','Allowed b_options key.'),
  ('b_options','from_porch',0,NULL,'gruzvill_site_constants','Allowed b_options key.'),
  ('b_options','from_floor',0,NULL,'gruzvill_site_constants','Allowed b_options key.'),
  ('b_options','from_room',0,NULL,'gruzvill_site_constants','Allowed b_options key.'),
  ('b_options','from_way',0,NULL,'gruzvill_site_constants','Allowed b_options key.'),
  ('b_options','from_mission',0,NULL,'gruzvill_site_constants','Allowed b_options key.'),
  ('b_options','from_tel',0,NULL,'gruzvill_site_constants','Allowed b_options key.'),
  ('b_options','from_day',0,NULL,'gruzvill_site_constants','Allowed b_options key.'),
  ('b_options','from_time_from',0,NULL,'gruzvill_site_constants','Allowed b_options key.'),
  ('b_options','from_time_to',0,NULL,'gruzvill_site_constants','Allowed b_options key.'),
  ('b_options','to_porch',0,NULL,'gruzvill_site_constants','Allowed b_options key.'),
  ('b_options','to_floor',0,NULL,'gruzvill_site_constants','Allowed b_options key.'),
  ('b_options','to_room',0,NULL,'gruzvill_site_constants','Allowed b_options key.'),
  ('b_options','to_way',0,NULL,'gruzvill_site_constants','Allowed b_options key.'),
  ('b_options','to_mission',0,NULL,'gruzvill_site_constants','Allowed b_options key.'),
  ('b_options','to_tel',0,NULL,'gruzvill_site_constants','Allowed b_options key.'),
  ('b_options','to_day',0,NULL,'gruzvill_site_constants','Allowed b_options key.'),
  ('b_options','to_time_from',0,NULL,'gruzvill_site_constants','Allowed b_options key.'),
  ('b_options','to_time_to',0,NULL,'gruzvill_site_constants','Allowed b_options key.'),
  ('b_options','object',0,NULL,'gruzvill_site_constants','Allowed b_options key.'),
  ('b_options','weight',0,NULL,'gruzvill_site_constants','Allowed b_options key.'),
  ('b_options','is_big_size',0,NULL,'gruzvill_site_constants','Allowed b_options key.'),
  ('b_options','cost',0,NULL,'gruzvill_site_constants','Allowed b_options key.'),
  ('b_options','is_loading_needs',0,NULL,'gruzvill_site_constants','Allowed b_options key.'),
  ('b_options','customer_price',0,NULL,'gruzvill_site_constants','Allowed b_options key used by emulator.'),
  ('b_options','moveType',0,NULL,'gruzvill_site_constants','Allowed b_options key.'),
  ('b_options','steps',0,NULL,'gruzvill_site_constants','Allowed b_options key.'),
  ('b_options','elevator',0,NULL,'gruzvill_site_constants','Allowed b_options key.'),
  ('b_options','furniture',0,NULL,'gruzvill_site_constants','Allowed b_options key.'),
  ('b_options','time_is_not_important',0,NULL,'gruzvill_site_constants','Allowed b_options key.'),
  ('b_options','fromDateTimeInterval',0,NULL,'gruzvill_site_constants','Allowed b_options key.'),
  ('b_options','tillDateTimeInterval',0,NULL,'gruzvill_site_constants','Allowed b_options key.'),
  ('b_options','bigTruckCargo',0,NULL,'gruzvill_site_constants','Allowed b_options key.'),
  ('b_options','size',0,NULL,'gruzvill_site_constants','Allowed b_options key.'),
  ('b_options','bigTruckCargoWeight',0,NULL,'gruzvill_site_constants','Allowed b_options key.'),
  ('b_options','carsCount',0,NULL,'gruzvill_site_constants','Allowed b_options key.'),
  ('b_options','bigTruckCarTypes',0,NULL,'gruzvill_site_constants','Allowed b_options key.'),
  ('b_options','bigTruckCarLogic',0,NULL,'gruzvill_site_constants','Allowed b_options key.'),
  ('b_options','bigTruckServices',0,NULL,'gruzvill_site_constants','Allowed b_options key.'),
  ('b_options','tickets',0,'{"t_id":true,"seats":true,"payment":true}','gruzvill_site_constants','Nested allowed b_options key.'),
  ('b_options','collage',0,NULL,'gruzvill_site_constants','Allowed b_options key.'),
  ('b_options','sms',0,NULL,'gruzvill_site_constants','Allowed b_options key.'),
  ('b_options','feedback',0,NULL,'gruzvill_site_constants','Allowed b_options key.'),
  ('b_options','submitPrice',0,NULL,'gruzvill_site_constants','Allowed b_options key used by WATaxiBot.'),
  ('b_options','createdBy',0,NULL,'gruzvill_site_constants','Allowed b_options key used by WATaxiBot.'),
  ('b_options','CalculationDetails',0,NULL,'gruzvill_site_constants','Allowed b_options key.'),
  ('b_options','pricingModel',0,NULL,'gruzvill_site_constants','Allowed b_options key used by WATaxiBot.'),
  ('b_options','driveStartedTimestamp',0,NULL,'gruzvill_site_constants','Allowed b_options key.'),
  ('reserved_b_options',':public',0,NULL,'api_docs','Reserved service key.'),
  ('reserved_b_options',':u_id_alias',0,NULL,'api_docs','Reserved service key mapping driver user id to public data index.'),
  ('reserved_b_options',':private',0,NULL,'api_docs','Hidden from driver responses.'),
  ('c_options','performers_price',0,NULL,'gruzvill_site_constants','Allowed c_options key for offer/candidate price.'),
  ('c_options','driver_offer_comment',0,NULL,'gruzvill_site_constants','Allowed c_options key for driver offer comment.'),
  ('c_options','driver_offer_eta',0,NULL,'gruzvill_site_constants','Allowed c_options key for driver ETA.'),
  ('action_payload','set_confirm_state',0,'{"b_estimate_waiting":true}','api_docs','Confirm created trip.'),
  ('action_payload','set_offer',0,'{"u_id":true,"t_id":true}','api_docs','Offer trip to selected driver.'),
  ('action_payload','set_performer',0,'{"u_id":true,"t_id":true,"performer":true,"b_driver_code":true,"data":true}','api_docs','Candidate or performer selection.'),
  ('action_payload','set_cancel_state',0,'{"reason":true,"cancel_states":true,"forced":true}','api_docs','Cancel order.'),
  ('action_payload','set_arrive_state',0,NULL,'api_docs','Driver arrived.'),
  ('action_payload','set_start_state',0,NULL,'api_docs','Driver started trip.'),
  ('action_payload','set_complete_state',0,NULL,'api_docs','Complete order.'),
  ('edit_payload','b_options',0,'{"operators":["=","+","-"],"shape":[["=",["key"],"value"]]}','api_docs','Edit b_options as operation array.'),
  ('edit_payload','c_options',0,'{"operators":["=","+","-"],"shape":[["=",["key"],"value"]]}','api_docs','Edit c_options as operation array.')
ON DUPLICATE KEY UPDATE
  `is_required` = VALUES(`is_required`),
  `allowed_json` = VALUES(`allowed_json`),
  `source` = VALUES(`source`),
  `notes` = VALUES(`notes`);

-- ---------------------------------------------------------------------------
-- Full JSON templates for client emulator orders
-- ---------------------------------------------------------------------------

INSERT INTO `taxi_order_payload_templates`
  (`code`, `order_mode`, `title`, `create_payload_json`, `b_options_json`, `edit_options_ops_json`, `backend_actions_json`, `notes`)
VALUES
  (
    'vote_client_emulator_v1',
    'VOTE',
    'Vote order for manual Driver UI testing',
    '{
      "b_start_address":"<pickup_address>",
      "b_start_latitude":"<pickup_latitude>",
      "b_start_longitude":"<pickup_longitude>",
      "b_destination_address":"<destination_address>",
      "b_destination_latitude":"<destination_latitude>",
      "b_destination_longitude":"<destination_longitude>",
      "b_start_datetime":"now",
      "b_custom_comment":"[CASE] <scenario_name>",
      "b_flight_number":null,
      "b_terminal":null,
      "b_passengers_count":1,
      "b_luggage_count":0,
      "b_placard":null,
      "b_car_class":null,
      "b_payment_way":1,
      "b_payment_card":null,
      "b_cars_count":1,
      "b_max_waiting":7200,
      "b_contact":"+70000000000",
      "b_comments":[],
      "b_services":[5],
      "b_location_class":null,
      "b_currency":"RUB",
      "b_only_offer":0,
      "countries_list_start":null,
      "countries_list_destination":null,
      "region_start":null,
      "region_destination":null,
      "city_start":null,
      "city_destination":null,
      "u_id":null,
      "b_pc":null,
      "kind":1,
      "upper":null,
      "b_voting":1,
      "b_options":{
        "fromShortAddress":"<pickup_short_address>",
        "toShortAddress":"<destination_short_address>",
        "customer_price":350,
        "submitPrice":0,
        "createdBy":"client-simulator",
        "pricingModel":"manual-vote",
        "from_porch":null,
        "from_floor":null,
        "from_room":null,
        "from_tel":null,
        "to_porch":null,
        "to_floor":null,
        "to_room":null,
        "to_tel":null,
        "time_is_not_important":true,
        "fromDateTimeInterval":null,
        "tillDateTimeInterval":null,
        "carsCount":1,
        "sms":false,
        "feedback":false,
        "driveStartedTimestamp":null,
        ":public":[],
        ":u_id_alias":{},
        ":private":{
          "scenarioKey":"<scenario_key>",
          "testerUserId":"<tester_user_id>",
          "selectedDriverUserId":null,
          "passengerChoiceMirror":"driver-emulator/data/passenger-choices.json"
        }
      }
    }',
    '{
      "fromShortAddress":"<pickup_short_address>",
      "toShortAddress":"<destination_short_address>",
      "customer_price":350,
      "submitPrice":0,
      "createdBy":"client-simulator",
      "pricingModel":"manual-vote",
      "from_porch":null,
      "from_floor":null,
      "from_room":null,
      "from_tel":null,
      "to_porch":null,
      "to_floor":null,
      "to_room":null,
      "to_tel":null,
      "time_is_not_important":true,
      "fromDateTimeInterval":null,
      "tillDateTimeInterval":null,
      "carsCount":1,
      "sms":false,
      "feedback":false,
      "driveStartedTimestamp":null,
      ":public":[],
      ":u_id_alias":{},
      ":private":{
        "scenarioKey":"<scenario_key>",
        "testerUserId":"<tester_user_id>",
        "selectedDriverUserId":null,
        "passengerChoiceMirror":"driver-emulator/data/passenger-choices.json"
      }
    }',
    '[
      ["=",["customer_price"],350],
      ["=",["submitPrice"],0],
      ["=",["createdBy"],"client-simulator"],
      ["=",["pricingModel"],"manual-vote"],
      ["=",["carsCount"],1],
      ["=",["time_is_not_important"],true],
      ["=",[":public"],[]],
      ["=",[":u_id_alias"],{}],
      ["=",[":private","scenarioKey"],"<scenario_key>"],
      ["=",[":private","testerUserId"],"<tester_user_id>"],
      ["=",[":private","selectedDriverUserId"],null],
      ["=",[":private","passengerChoiceMirror"],"driver-emulator/data/passenger-choices.json"]
    ]',
    '[
      {"clientSimulatorAction":"createVoteOrder","endpoint":"POST /drive","payloadLocation":"data","fsmAction":"order_publish_vote"},
      {"clientSimulatorAction":"confirmVoteOrder","endpoint":"POST /drive/get/<orderId>","payload":{"action":"set_confirm_state"}},
      {"clientSimulatorAction":"selectDriver","endpoint":"POST /drive/get/<orderId>","payload":{"action":"set_performer","performer":"1","u_id":"<driver_user_id>"},"fsmAction":"order_select_candidate"},
      {"clientSimulatorAction":"clearSelection","endpoint":"POST /drive/get/<orderId>","payload":{"action":"set_performer","performer":"0","u_id":"<driver_user_id>"},"fsmAction":"order_release_candidate"},
      {"clientSimulatorAction":"cancelOrder","endpoint":"POST /drive/get/<orderId>","payload":{"action":"set_cancel_state","reason":"<reason>"},"fsmAction":"order_cancel_by_client"},
      {"clientSimulatorAction":"noShow","endpoint":null,"payload":null,"fsmAction":"order_no_show"}
    ]',
    'Adds all create-payload keys documented for /drive plus the gruzvill b_options_valid_keys needed by the emulator. b_voting is preserved as existing backend flag even though it is documented as response data.'
  ),
  (
    'offer_client_emulator_v1',
    'OFFER',
    'Offer/intercity order payload reference',
    '{
      "b_start_address":"<pickup_address>",
      "b_start_latitude":"<pickup_latitude>",
      "b_start_longitude":"<pickup_longitude>",
      "b_destination_address":"<destination_address>",
      "b_destination_latitude":"<destination_latitude>",
      "b_destination_longitude":"<destination_longitude>",
      "b_start_datetime":"now",
      "b_custom_comment":"[CASE] <scenario_name>",
      "b_flight_number":null,
      "b_terminal":null,
      "b_passengers_count":1,
      "b_luggage_count":0,
      "b_placard":null,
      "b_car_class":null,
      "b_payment_way":1,
      "b_payment_card":null,
      "b_cars_count":0,
      "b_max_waiting":7200,
      "b_contact":"+70000000000",
      "b_comments":[],
      "b_services":[],
      "b_location_class":null,
      "b_currency":"RUB",
      "b_only_offer":0,
      "countries_list_start":null,
      "countries_list_destination":null,
      "region_start":null,
      "region_destination":null,
      "city_start":null,
      "city_destination":null,
      "u_id":null,
      "b_pc":null,
      "kind":1,
      "upper":null,
      "b_options":{
        "fromShortAddress":"<pickup_short_address>",
        "toShortAddress":"<destination_short_address>",
        "customer_price":350,
        "submitPrice":0,
        "createdBy":"client-simulator",
        "pricingModel":"manual-offer",
        "carsCount":0,
        ":public":[],
        ":u_id_alias":{},
        ":private":{
          "scenarioKey":"<scenario_key>",
          "offerMode":true
        }
      }
    }',
    '{
      "fromShortAddress":"<pickup_short_address>",
      "toShortAddress":"<destination_short_address>",
      "customer_price":350,
      "submitPrice":0,
      "createdBy":"client-simulator",
      "pricingModel":"manual-offer",
      "carsCount":0,
      ":public":[],
      ":u_id_alias":{},
      ":private":{
        "scenarioKey":"<scenario_key>",
        "offerMode":true
      }
    }',
    '[
      ["=",["customer_price"],350],
      ["=",["submitPrice"],0],
      ["=",["createdBy"],"client-simulator"],
      ["=",["pricingModel"],"manual-offer"],
      ["=",["carsCount"],0],
      ["=",[":public"],[]],
      ["=",[":u_id_alias"],{}],
      ["=",[":private","scenarioKey"],"<scenario_key>"],
      ["=",[":private","offerMode"],true]
    ]',
    '[
      {"clientSimulatorAction":"createOfferOrder","endpoint":"POST /drive","payloadLocation":"data"},
      {"clientSimulatorAction":"setOffer","endpoint":"POST /drive/get/<orderId>","payload":{"action":"set_offer","u_id":"<driver_user_id>","t_id":"<trip_ids_optional>"}},
      {"clientSimulatorAction":"selectOffer","endpoint":"POST /drive/get/<orderId>","payload":{"action":"set_performer","u_id":"<driver_user_id>","t_id":"<trip_ids_optional>"}}
    ]',
    'Reference only. Current task focuses on Vote; Offer is included because the API exposes b_cars_count=0 and set_offer.'
  )
ON DUPLICATE KEY UPDATE
  `order_mode` = VALUES(`order_mode`),
  `title` = VALUES(`title`),
  `create_payload_json` = VALUES(`create_payload_json`),
  `b_options_json` = VALUES(`b_options_json`),
  `edit_options_ops_json` = VALUES(`edit_options_ops_json`),
  `backend_actions_json` = VALUES(`backend_actions_json`),
  `notes` = VALUES(`notes`);

COMMIT;

-- ---------------------------------------------------------------------------
-- Verification queries
-- ---------------------------------------------------------------------------

SELECT 'Vote FSM states' AS section, `id`, `name`, `label`
FROM `fsm_states`
WHERE `name` IN (
  'order_created',
  'order_vote_waiting_candidates',
  'order_vote_driver_assigned',
  'order_vote_no_show',
  'order_cancelled'
)
ORDER BY `id`;

SELECT 'Vote FSM actions' AS section, `id`, `name`, `label`
FROM `fsm_actions`
WHERE `name` IN (
  'order_publish_vote',
  'order_select_candidate',
  'order_release_candidate',
  'order_cancel_by_client',
  'order_no_show'
)
ORDER BY `id`;

SELECT
  'Vote FSM transitions' AS section,
  fs_from.`name` AS from_state,
  action.`name` AS action,
  fs_to.`name` AS to_state
FROM `fsm_transitions` transition_row
JOIN `fsm_states` fs_from ON fs_from.`id` = transition_row.`from_state_id`
JOIN `fsm_actions` action ON action.`id` = transition_row.`action_id`
JOIN `fsm_states` fs_to ON fs_to.`id` = transition_row.`to_state_id`
WHERE action.`name` IN (
  'order_publish_vote',
  'order_select_candidate',
  'order_release_candidate',
  'order_cancel_by_client',
  'order_no_show'
)
ORDER BY fs_from.`name`, action.`name`, fs_to.`name`;

SELECT 'Taxi payload templates' AS section, `code`, `order_mode`, JSON_EXTRACT(`create_payload_json`, '$.kind') AS kind
FROM `taxi_order_payload_templates`
ORDER BY `code`;

SELECT 'Taxi payload keys' AS section, `scope`, COUNT(*) AS keys_count
FROM `taxi_order_payload_keys`
GROUP BY `scope`
ORDER BY `scope`;
