# Architecture

`wavectl_host` is organized by feature, with `lib/core/` for cross-feature device and rendering code. Repositories and models remain dependency-light; Flutter presentation code is grouped under each feature.

## Module map

- `lib/core/` — device geometry and specs, Protocol V2 transport/client/codec, canvas rendering, and theme.
- `lib/features/device/` — device repository and connection sub-view-model.
- `lib/features/profiles/` — profile/key models, config persistence, and profile editor sub-view-model.
- `lib/features/actions/` — flat action model, executor, host launcher, action plugin contract/registry, category plugins, and key interaction sub-view-model.
- `lib/features/home_assistant/` — entity model, service/repository, per-action handlers, and HA sub-view-model.
- `lib/features/audio/` — WAV management sub-view-model.
- `lib/features/studio/` — the `StudioViewModel` compatibility facade, shared `StudioSession`, panel registry, screen, and panels.

## Extension registries

### Action categories

`ActionPluginRegistry` is keyed by `ActionCategory` and keeps the default plugin order aligned with `ActionCategory.values`. A plugin owns its category's JSON parsing/serialization, summary badge, execution, editor widget, and key telemetry rendering. `ButtonAction.fromJson` folds `readFields` through every plugin, so fields continue to parse regardless of the selected category; each plugin's `toJson` must preserve the current key order and aliases.

To add a category:

1. Add the stable JSON enum value to `ActionCategory`.
2. Add one plugin under `lib/features/actions/plugins/<category>/` implementing `matchesJson`, `readFields`, `toJson`, `summaryBadge`, `execute`, and `buildEditor`.
3. Add that plugin to `defaultActionPlugins()` in enum order, and add category-specific telemetry painting if needed.
4. Add round-trip, alias, execution, editor-key, and painting tests; update the JSON golden only if the accepted format intentionally changes.

### Home Assistant action types

`HaActionHandlerRegistry` maps every `HaActionType` to a handler. The handler owns the service-call plan, optimistic state, default `step`, pill text, and overlay painting. `HomeAssistantService` and the HA action plugin both delegate to this registry.

To add an HA action type:

1. Add the stable JSON enum value to `HaActionType`.
2. Add a `HaActionHandler` under `lib/features/home_assistant/domain/handlers/` and implement its service plan, default step, pill, and optional overlay.
3. Register the handler in `HaActionHandlerRegistry.defaults()` and add tests for payloads, optimistic state, pill, and default step.

### Device models

`DeviceModelRegistry` owns each model's `DeviceModelSpec`, simulator URI and port hints, default profile factory, and simulated device-info factory. Geometry parsing, simulator discovery, device defaults, and profile seeding read the descriptors rather than branching by model.

To add a model:

1. Add its stable `WaveshareModel` enum value and `DeviceModelSpec`.
2. Add a `DeviceModelDescriptor` to `DeviceModelRegistry.defaults()` with its simulator URI, port hints, default profile, and portrait/landscape simulated info factories.
3. Add geometry, port discovery, profile-seeding, and simulated `getInfo` tests. Keep existing model aliases and the `sk18` fallback unchanged.

### Studio panels

`StudioPanelRegistry.defaults` describes the wide order (Profiles & Device, LCD Canvas, Key Inspector), widths (300 px, expanded, 340 px), and compact tab order (LCD Canvas, Key Inspector, Profiles & Device).

To add a panel, create its widget and a `StudioPanelDescriptor`, then add that descriptor to both `wideOrder` and `compactTabOrder` at the intended positions. Set `fixedWidth` for fixed-width wide panels or leave it `null` for an expanded panel; `tabTitle` supplies the compact tab label.

## Studio state ownership

`StudioViewModel` remains the public `ChangeNotifier` facade with the original constructor and API. It owns the clock, frame-stream callback/pump, and device-event subscription, and routes cross-feature flows through `device`, `profileEditor`, `keys`, `ha`, and `audio`. The legacy `profiles` getter remains a `List<Sk18Profile>`; the profile editor sub-view-model is exposed as `profileEditor`. Sub-view-model notifications share a `StudioSession` and request a frame only once per logical change. Timers and subscriptions are canceled during disposal.

## Behavior compatibility

- `test/fixtures/studio_config_golden.json` pins the byte-exact studio configuration, including the built-in profiles; `test/domain/json_golden_test.dart` also covers category aliases and legacy field names.
- Existing widget keys, editor controls, status strings, Protocol V2 framing, and serialized config keys/order remain compatibility contracts.
- Run `flutter analyze` and `flutter test` after registry or facade changes.
