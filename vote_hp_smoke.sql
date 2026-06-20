-- Smoke-check for Vote client scenarios on the existing MySQL stored-procedure FSM.
--
-- What this file does:
-- 1. Adds minimal taxi/Vote states, actions and transitions to the existing FSM tables.
-- 2. Creates several synthetic orders.
-- 3. Runs the same client-side operations that are described in vote-client-emulator-spec.json
--    through CALL fsm_perform_action(...).
--
-- This is NOT a production migration. It is a quick manual check template.

-- ---------------------------------------------------------------------------
-- 1. Minimal Vote states
-- ---------------------------------------------------------------------------

INSERT INTO fsm_states (name, label)
SELECT 'order_vote_waiting_candidates', 'Vote: waiting for candidate drivers'
WHERE NOT EXISTS (
  SELECT 1 FROM fsm_states WHERE name = 'order_vote_waiting_candidates'
);

INSERT INTO fsm_states (name, label)
SELECT 'order_vote_driver_assigned', 'Vote: driver selected as performer'
WHERE NOT EXISTS (
  SELECT 1 FROM fsm_states WHERE name = 'order_vote_driver_assigned'
);

INSERT INTO fsm_states (name, label)
SELECT 'order_vote_no_show', 'Vote: client no-show'
WHERE NOT EXISTS (
  SELECT 1 FROM fsm_states WHERE name = 'order_vote_no_show'
);

-- Existing terminal state in the dump:
--   order_cancelled

-- ---------------------------------------------------------------------------
-- 2. Minimal Vote actions
-- ---------------------------------------------------------------------------

INSERT INTO fsm_actions (name, label)
SELECT 'order_publish_vote', 'Publish Vote order'
WHERE NOT EXISTS (
  SELECT 1 FROM fsm_actions WHERE name = 'order_publish_vote'
);

INSERT INTO fsm_actions (name, label)
SELECT 'order_select_candidate', 'Client selects candidate driver'
WHERE NOT EXISTS (
  SELECT 1 FROM fsm_actions WHERE name = 'order_select_candidate'
);

INSERT INTO fsm_actions (name, label)
SELECT 'order_release_candidate', 'Release selected candidate'
WHERE NOT EXISTS (
  SELECT 1 FROM fsm_actions WHERE name = 'order_release_candidate'
);

INSERT INTO fsm_actions (name, label)
SELECT 'order_cancel_by_client', 'Client cancels order'
WHERE NOT EXISTS (
  SELECT 1 FROM fsm_actions WHERE name = 'order_cancel_by_client'
);

INSERT INTO fsm_actions (name, label)
SELECT 'order_no_show', 'Client no-show'
WHERE NOT EXISTS (
  SELECT 1 FROM fsm_actions WHERE name = 'order_no_show'
);

-- ---------------------------------------------------------------------------
-- 3. Minimal Vote transitions
-- ---------------------------------------------------------------------------

-- order_created -> order_vote_waiting_candidates
INSERT INTO fsm_transitions (from_state_id, action_id, to_state_id)
SELECT fs_from.id, a.id, fs_to.id
FROM fsm_states fs_from
JOIN fsm_actions a ON a.name = 'order_publish_vote'
JOIN fsm_states fs_to ON fs_to.name = 'order_vote_waiting_candidates'
WHERE fs_from.name = 'order_created'
  AND NOT EXISTS (
    SELECT 1
    FROM fsm_transitions t
    WHERE t.from_state_id = fs_from.id
      AND t.action_id = a.id
      AND t.to_state_id = fs_to.id
  );

-- order_vote_waiting_candidates -> order_vote_driver_assigned
INSERT INTO fsm_transitions (from_state_id, action_id, to_state_id)
SELECT fs_from.id, a.id, fs_to.id
FROM fsm_states fs_from
JOIN fsm_actions a ON a.name = 'order_select_candidate'
JOIN fsm_states fs_to ON fs_to.name = 'order_vote_driver_assigned'
WHERE fs_from.name = 'order_vote_waiting_candidates'
  AND NOT EXISTS (
    SELECT 1
    FROM fsm_transitions t
    WHERE t.from_state_id = fs_from.id
      AND t.action_id = a.id
      AND t.to_state_id = fs_to.id
  );

-- order_vote_waiting_candidates -> order_cancelled
INSERT INTO fsm_transitions (from_state_id, action_id, to_state_id)
SELECT fs_from.id, a.id, fs_to.id
FROM fsm_states fs_from
JOIN fsm_actions a ON a.name = 'order_cancel_by_client'
JOIN fsm_states fs_to ON fs_to.name = 'order_cancelled'
WHERE fs_from.name = 'order_vote_waiting_candidates'
  AND NOT EXISTS (
    SELECT 1
    FROM fsm_transitions t
    WHERE t.from_state_id = fs_from.id
      AND t.action_id = a.id
      AND t.to_state_id = fs_to.id
  );

-- order_vote_driver_assigned -> order_cancelled
INSERT INTO fsm_transitions (from_state_id, action_id, to_state_id)
SELECT fs_from.id, a.id, fs_to.id
FROM fsm_states fs_from
JOIN fsm_actions a ON a.name = 'order_cancel_by_client'
JOIN fsm_states fs_to ON fs_to.name = 'order_cancelled'
WHERE fs_from.name = 'order_vote_driver_assigned'
  AND NOT EXISTS (
    SELECT 1
    FROM fsm_transitions t
    WHERE t.from_state_id = fs_from.id
      AND t.action_id = a.id
      AND t.to_state_id = fs_to.id
  );

-- order_vote_driver_assigned -> order_vote_waiting_candidates
INSERT INTO fsm_transitions (from_state_id, action_id, to_state_id)
SELECT fs_from.id, a.id, fs_to.id
FROM fsm_states fs_from
JOIN fsm_actions a ON a.name = 'order_release_candidate'
JOIN fsm_states fs_to ON fs_to.name = 'order_vote_waiting_candidates'
WHERE fs_from.name = 'order_vote_driver_assigned'
  AND NOT EXISTS (
    SELECT 1
    FROM fsm_transitions t
    WHERE t.from_state_id = fs_from.id
      AND t.action_id = a.id
      AND t.to_state_id = fs_to.id
  );

-- order_vote_driver_assigned -> order_vote_no_show
INSERT INTO fsm_transitions (from_state_id, action_id, to_state_id)
SELECT fs_from.id, a.id, fs_to.id
FROM fsm_states fs_from
JOIN fsm_actions a ON a.name = 'order_no_show'
JOIN fsm_states fs_to ON fs_to.name = 'order_vote_no_show'
WHERE fs_from.name = 'order_vote_driver_assigned'
  AND NOT EXISTS (
    SELECT 1
    FROM fsm_transitions t
    WHERE t.from_state_id = fs_from.id
      AND t.action_id = a.id
      AND t.to_state_id = fs_to.id
  );

-- ---------------------------------------------------------------------------
-- 4. Synthetic orders for manual stored-procedure checks
-- ---------------------------------------------------------------------------

INSERT INTO orders (status, description, pickup_type, delivery_type, from_city, to_city)
VALUES
  ('order_created', '[CASE] Vote Driver Selected', 'courier', 'courier', 'Rostov', 'Rostov'),
  ('order_created', '[CASE] Vote Other Driver Selected', 'courier', 'courier', 'Rostov', 'Rostov'),
  ('order_created', '[CASE] Vote Auto Select', 'courier', 'courier', 'Rostov', 'Rostov'),
  ('order_created', '[CASE] Vote Cancel During Voting', 'courier', 'courier', 'Rostov', 'Rostov'),
  ('order_created', '[CASE] Vote New Round', 'courier', 'courier', 'Rostov', 'Rostov'),
  ('order_created', '[CASE] Client Cancel After Selection', 'courier', 'courier', 'Rostov', 'Rostov'),
  ('order_created', '[CASE] No Show', 'courier', 'courier', 'Rostov', 'Rostov');

SET @client_user_id = 1001;
SET @tester_driver_id = '205';
SET @other_driver_id = '206';

SELECT id, description, status
FROM orders
WHERE description LIKE '[CASE] %'
ORDER BY id DESC
LIMIT 7;

-- ---------------------------------------------------------------------------
-- 5. Scenario calls
-- ---------------------------------------------------------------------------
-- Replace @..._order_id values with real ids from the SELECT above if needed.

-- Scenario 1: Vote Driver Selected
SET @vote_selected_order_id = (
  SELECT id FROM orders WHERE description = '[CASE] Vote Driver Selected' ORDER BY id DESC LIMIT 1
);
CALL fsm_perform_action('order', @vote_selected_order_id, 'order_publish_vote', @client_user_id, NULL);
CALL fsm_perform_action('order', @vote_selected_order_id, 'order_select_candidate', @client_user_id, @tester_driver_id);

-- Scenario 2: Vote Other Driver Selected
SET @vote_not_selected_order_id = (
  SELECT id FROM orders WHERE description = '[CASE] Vote Other Driver Selected' ORDER BY id DESC LIMIT 1
);
CALL fsm_perform_action('order', @vote_not_selected_order_id, 'order_publish_vote', @client_user_id, NULL);
CALL fsm_perform_action('order', @vote_not_selected_order_id, 'order_select_candidate', @client_user_id, @other_driver_id);

-- Scenario 3: Vote Auto Select
SET @vote_auto_select_order_id = (
  SELECT id FROM orders WHERE description = '[CASE] Vote Auto Select' ORDER BY id DESC LIMIT 1
);
CALL fsm_perform_action('order', @vote_auto_select_order_id, 'order_publish_vote', @client_user_id, NULL);
-- Intentionally no selection. Server-side auto-select / timeout is outside this minimal smoke check.

-- Scenario 4: Vote Cancel During Voting
SET @vote_cancelled_order_id = (
  SELECT id FROM orders WHERE description = '[CASE] Vote Cancel During Voting' ORDER BY id DESC LIMIT 1
);
CALL fsm_perform_action('order', @vote_cancelled_order_id, 'order_publish_vote', @client_user_id, NULL);
CALL fsm_perform_action('order', @vote_cancelled_order_id, 'order_cancel_by_client', @client_user_id, 'client cancel during voting');

-- Scenario 5: Vote New Round
SET @vote_new_round_order_id = (
  SELECT id FROM orders WHERE description = '[CASE] Vote New Round' ORDER BY id DESC LIMIT 1
);
CALL fsm_perform_action('order', @vote_new_round_order_id, 'order_publish_vote', @client_user_id, NULL);
CALL fsm_perform_action('order', @vote_new_round_order_id, 'order_select_candidate', @client_user_id, @other_driver_id);
CALL fsm_perform_action('order', @vote_new_round_order_id, 'order_release_candidate', @client_user_id, @other_driver_id);

-- Scenario 6: Client Cancel After Selection
SET @client_cancel_after_select_order_id = (
  SELECT id FROM orders WHERE description = '[CASE] Client Cancel After Selection' ORDER BY id DESC LIMIT 1
);
CALL fsm_perform_action('order', @client_cancel_after_select_order_id, 'order_publish_vote', @client_user_id, NULL);
CALL fsm_perform_action('order', @client_cancel_after_select_order_id, 'order_select_candidate', @client_user_id, @tester_driver_id);
CALL fsm_perform_action('order', @client_cancel_after_select_order_id, 'order_cancel_by_client', @client_user_id, 'client cancel after selection');

-- Scenario 7: No Show
SET @no_show_order_id = (
  SELECT id FROM orders WHERE description = '[CASE] No Show' ORDER BY id DESC LIMIT 1
);
CALL fsm_perform_action('order', @no_show_order_id, 'order_publish_vote', @client_user_id, NULL);
CALL fsm_perform_action('order', @no_show_order_id, 'order_select_candidate', @client_user_id, @tester_driver_id);
CALL fsm_perform_action('order', @no_show_order_id, 'order_no_show', @client_user_id, @tester_driver_id);

-- ---------------------------------------------------------------------------
-- 6. Result check
-- ---------------------------------------------------------------------------

SELECT id, description, status
FROM orders
WHERE id IN (
  @vote_selected_order_id,
  @vote_not_selected_order_id,
  @vote_auto_select_order_id,
  @vote_cancelled_order_id,
  @vote_new_round_order_id,
  @client_cancel_after_select_order_id,
  @no_show_order_id
)
ORDER BY id;

SELECT entity_type, entity_id, action_name, from_state, to_state, user_id, created_at
FROM fsm_action_logs
WHERE entity_type = 'order'
  AND entity_id IN (
    @vote_selected_order_id,
    @vote_not_selected_order_id,
    @vote_auto_select_order_id,
    @vote_cancelled_order_id,
    @vote_new_round_order_id,
    @client_cancel_after_select_order_id,
    @no_show_order_id
  )
ORDER BY id;
