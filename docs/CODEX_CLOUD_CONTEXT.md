# Codex Cloud Context

## Current Goal

Build/adapt an FSM for a taxi ordering service.

The original repository is a server-side FSM for delivery from address to
address across cities using lockers/postamats. The imported `WATaxiBot-main`
folder is a niche WhatsApp taxi bot that was translated to an FSM-style flow.
The task is to reuse the best foundation for the taxi-ordering domain, then
move toward a working server-side FSM and bot integration.

## Prior Decision

Use the existing server-side FSM/database/stored-procedure approach as the core
foundation, not the WhatsApp bot FSM as the main process engine.

Reasoning:

- The current server FSM is table-driven and already has process persistence:
  `fsm_states`, `fsm_actions`, `fsm_transitions`, `fsm_action_logs`,
  `fsm_errors_log`.
- The stored-procedure engine is closer to the desired backend/process layer.
- `WATaxiBot-main` is useful as a domain/reference implementation for taxi
  collection flows, route prompts, WhatsApp integration, and payload mapping,
  but it should not become the central source of process state.
- If the bot talks to our server FSM, this FSM database is the primary process
  database.
- If the bot talks directly to iBronevik/MultiBot, their API model also matters,
  but this repository should still act as the local adapter/model for now.

## Current Implemented Direction

The repo has been extended toward a taxi Vote/OFFER flow.

Key concepts already present in SQL dumps and smoke scripts:

- Vote states:
  - `order_vote_waiting_candidates`
  - `order_vote_driver_assigned`
  - `order_vote_no_show`
- Vote actions:
  - `order_publish_vote`
  - `order_select_candidate`
  - `order_release_candidate`
  - `order_cancel_by_client`
  - `order_no_show`
- Taxi/order JSON layer:
  - `orders.order_json`
  - `taxi_order_payload_keys`
  - `taxi_order_payload_templates`
  - VOTE and OFFER payload templates

The intent is to keep `fsm_perform_action()` and the state/action/transition
tables as the engine, while taxi-specific details live in JSON payload metadata
and adapter code.

## Important Files

- `Описание.txt` - Russian product/task description. Read this first for the
  desired business flow.
- `procedure.txt` - stored-procedure/FSM reference material.
- `main.py`, `db_layer.py`, `models.py` - current Python service layer.
- `vote_hp_smoke.sql` - minimal smoke script for Vote states/actions/transitions
  on the existing MySQL FSM.
- `vote_fsm_original_schema_with_order_json_dump.sql` - focused SQL extension
  for Vote FSM and taxi order JSON/payload templates.
- `vote_fsm_original_schema_with_order_json_full_dump.sql` - full dump variant.
- `vote_fsm_testdb_dump.sql` - test DB dump with Vote cases.
- `vote-client-emulator-spec.json` - client/emulator scenario spec.
- `driver-emulator/` - JS driver/client emulator and Vote scenarios.
- `WATaxiBot-main/src/states/machines/orderMachine.ts` - taxi bot FSM reference.
- `WATaxiBot-main/src/handlers/routes/order/` - WhatsApp taxi order collection
  flow reference.

## Recommended Cloud Starting Prompt

Use this when starting a Codex Cloud task:

```text
Read AGENTS.md and docs/CODEX_CLOUD_CONTEXT.md first. Then inspect Описание.txt,
procedure.txt, vote_hp_smoke.sql, vote_fsm_original_schema_with_order_json_dump.sql,
main.py, db_layer.py, models.py, and the relevant WATaxiBot-main order FSM files.

Continue the taxi FSM adaptation using the existing database/stored-procedure FSM
as the core. Do not replace it with the WhatsApp bot FSM. Use WATaxiBot-main as a
domain/reference source. First summarize the current architecture and the smallest
next implementation step; then implement that step with focused changes and verify
what can be verified in the cloud environment.
```

## Working Notes

- Prefer small, inspectable steps.
- Keep the server-side FSM engine table-driven.
- Avoid unrelated refactors.
- Be careful with `.env.*`, SQL dumps, and emulator data; this repo is intended
  to stay private.
- Before changing state names, actions, or transitions, search the SQL dumps and
  Python code for existing usage.

