# Metis Control-UI Mapping

This file records the intended one-to-one module mapping between the upstream
control-ui runtime and Metis's gateway control-ui runtime.

## Current Mapping

| Reference Runtime | Responsibility | Metis |
| --- | --- | --- |
| `src/gateway/control-ui.ts` | top-level control-ui request handling, asset serving, SPA shell delivery | [`gateway_control_ui_server.cj`](/Users/l3gi0n/work/workspace_cangjie/Metis/src/gateway/runtime/gateway_control_ui_server.cj) + [`gateway_control_ui_routes.cj`](/Users/l3gi0n/work/workspace_cangjie/Metis/src/gateway/runtime/gateway_control_ui_routes.cj) + [`gateway_control_ui_content.cj`](/Users/l3gi0n/work/workspace_cangjie/Metis/src/gateway/runtime/gateway_control_ui_content.cj) |
| `src/gateway/control-ui-contract.ts` | contract/bootstrap config boundary | [`gateway_control_ui_contract.cj`](/Users/l3gi0n/work/workspace_cangjie/Metis/src/gateway/runtime/gateway_control_ui_contract.cj) |
| `src/gateway/control-ui-routing.ts` | route classification and SPA/static boundary | [`gateway_control_ui_runtime.cj`](/Users/l3gi0n/work/workspace_cangjie/Metis/src/gateway/runtime/gateway_control_ui_runtime.cj) + [`gateway_control_ui_routes.cj`](/Users/l3gi0n/work/workspace_cangjie/Metis/src/gateway/runtime/gateway_control_ui_routes.cj) |
| `src/gateway/control-ui-csp.ts` | CSP/header policy | [`gateway_control_ui_contract.cj`](/Users/l3gi0n/work/workspace_cangjie/Metis/src/gateway/runtime/gateway_control_ui_contract.cj) + [`gateway_control_ui_runtime.cj`](/Users/l3gi0n/work/workspace_cangjie/Metis/src/gateway/runtime/gateway_control_ui_runtime.cj) |
| `src/gateway/control-ui-http-utils.ts` | response helpers / request method rules | [`gateway_control_ui_routes.cj`](/Users/l3gi0n/work/workspace_cangjie/Metis/src/gateway/runtime/gateway_control_ui_routes.cj) |
| `src/gateway/control-ui-shared.ts` | shared URLs / avatar helpers / path helpers | [`gateway_control_ui_runtime.cj`](/Users/l3gi0n/work/workspace_cangjie/Metis/src/gateway/runtime/gateway_control_ui_runtime.cj) |
| asset/bootstrap pipeline | static assets and injected bootstrap data | [`gateway_control_ui_templates.cj`](/Users/l3gi0n/work/workspace_cangjie/Metis/src/gateway/runtime/gateway_control_ui_templates.cj) + [`gateway_control_ui_content.cj`](/Users/l3gi0n/work/workspace_cangjie/Metis/src/gateway/runtime/gateway_control_ui_content.cj) |

## Remaining Structure Work

1. Split [`gateway_control_ui_content.cj`](/Users/l3gi0n/work/workspace_cangjie/Metis/src/gateway/runtime/gateway_control_ui_content.cj) into:
   - page shell/template
   - injected bootstrap/config fragment
   - client-side script bundle text
2. Move more route/security helpers out of [`gateway_control_ui_runtime.cj`](/Users/l3gi0n/work/workspace_cangjie/Metis/src/gateway/runtime/gateway_control_ui_runtime.cj) if they become contract-only concerns.
3. Keep [`dashboard_server.cj`](/Users/l3gi0n/work/workspace_cangjie/Metis/src/gateway/runtime/dashboard_server.cj) as compatibility shim only.
