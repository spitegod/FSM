-- Vote FSM seed/dump for the original Maskit26/FSM database schema.
--
-- Compatible with:
--   https://github.com/Maskit26/FSM/tree/main/database
--   database/Dump20251127 (1).sql
--
-- Purpose:
--   Adds the minimal Vote-order FSM model to the existing table-driven
--   MySQL stored-procedure engine:
--     - fsm_states
--     - fsm_actions
--     - fsm_transitions
--
-- This file does NOT:
--   - recreate database or tables;
--   - drop any existing data;
--   - insert smoke-test orders;
--   - insert fsm_action_logs.
--
-- It is intentionally idempotent: repeated import should not duplicate rows.

USE `testdb`;

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

-- Existing original state reused by Vote:
--   order_created
--   order_cancelled

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

-- order_created + order_publish_vote -> order_vote_waiting_candidates
INSERT INTO `fsm_transitions` (`from_state_id`, `action_id`, `to_state_id`)
SELECT fs_from.`id`, action.`id`, fs_to.`id`
FROM `fsm_states` fs_from
JOIN `fsm_actions` action ON action.`name` = 'order_publish_vote'
JOIN `fsm_states` fs_to ON fs_to.`name` = 'order_vote_waiting_candidates'
WHERE fs_from.`name` = 'order_created'
  AND NOT EXISTS (
    SELECT 1
    FROM `fsm_transitions` existing
    WHERE existing.`from_state_id` = fs_from.`id`
      AND existing.`action_id` = action.`id`
      AND existing.`to_state_id` = fs_to.`id`
  );

-- order_vote_waiting_candidates + order_select_candidate -> order_vote_driver_assigned
INSERT INTO `fsm_transitions` (`from_state_id`, `action_id`, `to_state_id`)
SELECT fs_from.`id`, action.`id`, fs_to.`id`
FROM `fsm_states` fs_from
JOIN `fsm_actions` action ON action.`name` = 'order_select_candidate'
JOIN `fsm_states` fs_to ON fs_to.`name` = 'order_vote_driver_assigned'
WHERE fs_from.`name` = 'order_vote_waiting_candidates'
  AND NOT EXISTS (
    SELECT 1
    FROM `fsm_transitions` existing
    WHERE existing.`from_state_id` = fs_from.`id`
      AND existing.`action_id` = action.`id`
      AND existing.`to_state_id` = fs_to.`id`
  );

-- order_vote_waiting_candidates + order_cancel_by_client -> order_cancelled
INSERT INTO `fsm_transitions` (`from_state_id`, `action_id`, `to_state_id`)
SELECT fs_from.`id`, action.`id`, fs_to.`id`
FROM `fsm_states` fs_from
JOIN `fsm_actions` action ON action.`name` = 'order_cancel_by_client'
JOIN `fsm_states` fs_to ON fs_to.`name` = 'order_cancelled'
WHERE fs_from.`name` = 'order_vote_waiting_candidates'
  AND NOT EXISTS (
    SELECT 1
    FROM `fsm_transitions` existing
    WHERE existing.`from_state_id` = fs_from.`id`
      AND existing.`action_id` = action.`id`
      AND existing.`to_state_id` = fs_to.`id`
  );

-- order_vote_driver_assigned + order_cancel_by_client -> order_cancelled
INSERT INTO `fsm_transitions` (`from_state_id`, `action_id`, `to_state_id`)
SELECT fs_from.`id`, action.`id`, fs_to.`id`
FROM `fsm_states` fs_from
JOIN `fsm_actions` action ON action.`name` = 'order_cancel_by_client'
JOIN `fsm_states` fs_to ON fs_to.`name` = 'order_cancelled'
WHERE fs_from.`name` = 'order_vote_driver_assigned'
  AND NOT EXISTS (
    SELECT 1
    FROM `fsm_transitions` existing
    WHERE existing.`from_state_id` = fs_from.`id`
      AND existing.`action_id` = action.`id`
      AND existing.`to_state_id` = fs_to.`id`
  );

-- order_vote_driver_assigned + order_release_candidate -> order_vote_waiting_candidates
INSERT INTO `fsm_transitions` (`from_state_id`, `action_id`, `to_state_id`)
SELECT fs_from.`id`, action.`id`, fs_to.`id`
FROM `fsm_states` fs_from
JOIN `fsm_actions` action ON action.`name` = 'order_release_candidate'
JOIN `fsm_states` fs_to ON fs_to.`name` = 'order_vote_waiting_candidates'
WHERE fs_from.`name` = 'order_vote_driver_assigned'
  AND NOT EXISTS (
    SELECT 1
    FROM `fsm_transitions` existing
    WHERE existing.`from_state_id` = fs_from.`id`
      AND existing.`action_id` = action.`id`
      AND existing.`to_state_id` = fs_to.`id`
  );

-- order_vote_driver_assigned + order_no_show -> order_vote_no_show
INSERT INTO `fsm_transitions` (`from_state_id`, `action_id`, `to_state_id`)
SELECT fs_from.`id`, action.`id`, fs_to.`id`
FROM `fsm_states` fs_from
JOIN `fsm_actions` action ON action.`name` = 'order_no_show'
JOIN `fsm_states` fs_to ON fs_to.`name` = 'order_vote_no_show'
WHERE fs_from.`name` = 'order_vote_driver_assigned'
  AND NOT EXISTS (
    SELECT 1
    FROM `fsm_transitions` existing
    WHERE existing.`from_state_id` = fs_from.`id`
      AND existing.`action_id` = action.`id`
      AND existing.`to_state_id` = fs_to.`id`
  );

COMMIT;

-- ---------------------------------------------------------------------------
-- Quick verification query
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
