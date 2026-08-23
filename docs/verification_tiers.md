# What each kind of test actually proves

Three tiers. The point of writing them down is not bookkeeping — it is that
when the emulator is broken, the honest answer is "these nine gates still hold
and those two do not", not "tests pass".

A skipped check that reports success is the failure mode this whole project
keeps rediscovering: an empty lint package cited as a build guarantee, a
milestone with no rows that could not fail, a Gradle test task with no JUnit
engine that ran zero tests and went green, a release build that handed over an
unsigned APK and exited 0. Every one of them was a green tick over an empty
room. So a deferral here is written down, dated, and expires.

---

## Tier A — host `flutter test`

Always available. No Android SDK, no device, no network.

**Proves:**

- Every arithmetic guarantee: paisa, thousandths, milli-paisa, apportionment,
  rounding, unit conversion, overflow refusal.
- The schema invariants, against real in-memory SQLite: FKs declared and
  indexed, no `REAL` affinity, every table `STRICT`, the envelope present.
- The write path: one transaction, `Σdebit == Σcredit` at integer equality
  before commit, append-only tables refusing updates, firm scoping, the outbox
  written on every mutation, a failed write leaving nine empty tables.
- Widget trees driven by taps and typing against that same real database —
  including the demo script, which reads rows back out and asserts column
  values.
- Semantics labels, text scaling to 200%, layout at phone and tablet sizes,
  and insets against a **synthetic** `MediaQuery`.
- Every file-shaped fact: the manifests as source text, the Gradle config, the
  ledger's own rules, the ARB coverage.

**Cannot prove:**

- That the app compiles for Android at all.
- That SQLite's native library loads on the device ABI.
- That the application-support directory is writable inside the app sandbox.
- That a commit reached disk rather than a page cache — `synchronous = FULL`
  means nothing to a host test.
- That a runtime permission was granted, or that Android's permission model
  exists. *(This is not hypothetical. The LAN printer shipped against a release
  manifest with no `INTERNET` permission, which Android requires for any
  socket. Every test passed.)*
- That the real system bars sit where the synthetic ones did.
- That predictive back behaves, or that any printer works.

---

## Tier B — host plus the Android SDK, no emulator

Available on any machine with the SDK, **including this one right now**. This
is the tier people forget exists, and it carries most of the Android surface.

`melos run android` proves:

| Gate | What it catches |
|---|---|
| Release build compiles | The plugin registrant machinery, the AGP 9 / Kotlin 2.3 toolchain, R8 keep rules |
| **Signing** | `apksigner verify --print-certs` must not print `CN=Android Debug`, and must verify at all |
| **Merged manifest permissions** | A dependency injecting `ACCESS_FINE_LOCATION` or `QUERY_ALL_PACKAGES`. The Dart permission test reads the two *source* manifests and structurally cannot see the merger's output |
| **16 KB alignment** | `zipalign -c -P 16` — a hard Play upload gate for API 35+ |
| **Size** | Under the committed ceiling, asserted rather than printed |
| Plugin unit tests | With a `>0 tests ran` assertion, because the task once reported success having run none |

**Nine of the twelve Android gates are here, not on a device.** An emulator
outage is much cheaper than it looks.

---

## Tier C — an emulator or a real handset

Only two things need it:

- `integration_test/` — the demo script and cart recovery, driving the real
  widget tree against the app's own on-disk database, including the
  fault-injection run that asserts nine empty tables after a failed write.
- The physical-handset rows: the demo run done by hand on a Transsion-class
  device, and the committed screen recording of it.

Everything else that *feels* like it needs a device is Tier B.

---

## When Tier C is unavailable

Run `dart run tool/device_gate.dart`. If no device or emulator answers, it
prints the exact YAML to paste into the ledger row:

```yaml
    deferred:
      proof: the demo script rings a cash sale on a real handset
      reason: no emulator on this machine — KVM/HAXM unavailable
      recorded: 2026-08-23
      recorded_by: safiurrehman07@gmail.com
      expires: 2026-09-06
```

`verify_ledger` then does four things, and the third is the one that matters:

1. Prints a `DEFERRED (n)` block at the top of **every** run.
2. **Drops the row from `done` to `wip`,** so the milestone percentage falls
   immediately and visibly. Nobody has to remember to mention it — the number
   in the next status report is already lower.
3. Exits 1 if any `expires` date has passed.
4. Exits 1 on any deferral at all unless `--allow-deferred` is passed.

**CI never passes that flag.** A deferral is for a developer without a device
this afternoon. It is not a way through the gate, and it cannot reach a release
tag.
