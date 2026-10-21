## 0.1.0

* First release.
* Event logging with typed metadata, sessions following the app lifecycle and lifetime stats that
  survive log rotation.
* Condition DSL: counts, attribute filters and aggregates, distinct sessions, active days, streaks,
  recency and inactivity, app-wide metrics, loose funnels with windows and drop-off, logical
  composition and `explain()`.
* Nudges: definitions with cooldowns, caps, once per session, group policies, priorities,
  outcome-based policies and chaining; `checkpoint()`, `fire()` and the `fires`/`outcomes` streams.
* Widgets: `NudgeBuilder`, `NudgeListener` and `NudgeFireListener`.
* ObjectBox storage, `InMemoryNudgeStorage` and an injectable clock for tests.
