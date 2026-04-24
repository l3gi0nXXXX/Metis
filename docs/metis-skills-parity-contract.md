# Metis Skills Contract

## Scope

This contract defines the expected behavior for the current skills flow in Metis.

## Decision Rules

1. If `skills.enabled=false`, no skill is selected.
2. If user input is explicit slash skill (`/<skill>`), that skill is selected with `forced=true`.
3. Otherwise, skill selection uses deterministic name hit only.
4. If no clear skill match exists, selection is `none`.

## Prompt Rules

1. Prompt must include `<available_skills>` metadata when skills are enabled.
2. Metadata must include `name`, `description`, `location`, and `enabled`.
3. Skill body is not pre-injected; agent must `read` SKILL.md on demand after selecting a skill.
4. Never inject multiple skill bodies up front.

## Disabled Skill Rules

1. If a selected skill is disabled by config (`skills.entries.<name>.enabled=false`), tools for that skill path must not be executed.
2. The response should fall back to generic model answer path.

## CLI/Gateway Routing Rules

1. `/skills` must work in both CLI and Gateway chat path.
2. `/<skill>` must force the same selection logic in both CLI and Gateway.

## Model Rules

1. Skills must not define request-time `model` override behavior.
2. Skills must not define request-time `api_key` or `api_key_env` override behavior.

## Regression Matrix

- Case A: `/weather Shanghai` -> forced `weather`, metadata included, weather tool path allowed.
- Case B: non-explicit natural-language ask without deterministic skill name hit -> `none`, metadata included, no skill body injected.
- Case C: ambiguous generic ask -> `none`, metadata included, no skill body injected.
- Case D: disabled skill matched -> generic answer path, no skill tool execution.
- Case E: skill file contains `model/api_key_env` fields -> ignored for runtime model/key selection.
