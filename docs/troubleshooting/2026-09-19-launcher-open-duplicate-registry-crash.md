# 2026-09-19 Launcher open crashes host on duplicate runtime registry rows

## Symptoms

- Clicking a web app in the notch launcher (or otherwise opening one) makes the **host** NeatWebApp process disappear.
- Crash report: `EXC_BREAKPOINT` / `SIGTRAP` on the main thread.
- Stack centers on `Dictionary.init(uniqueKeysWithValues:)` → `WebAppRuntimeCoordinator.refreshRegistry()` → `open` → launcher selection.

Observed twice on 2026-09-19 (13:47 and 15:18), build `0.3.15` (3033).

## Cause

Runtime state files are stored **per instance ID**. The host maps them by **app ID** when refreshing the in-memory registry.

Under restart / migrate races (or when a lock directory was missing while a live state still existed), two live state files can share the same `appID`. `Dictionary(uniqueKeysWithValues:)` traps on duplicate keys and kills the host.

Contributing gaps:

1. `refreshRegistry` assumed app IDs were unique.
2. `cleanupStaleStates` only dropped dead PIDs, not extra live rows for the same app.
3. `RuntimeAppLock.acquire` only checked for an existing live state when a lock directory was already present.
4. `waitForRuntimeShutdown` could finish without removing the old instance’s state file before a replacement launch.

## Fix

- Build the registry with `uniquingKeysWith`, keeping the newest row (`loadAllStates` is newest-first).
- In `cleanupStaleStates`, after removing dead processes, keep one live row per `appID` and drop older duplicates (terminate orphan runtime PIDs when safe).
- Always consult live registry state in `acquire`, and treat lock-directory create races as “not acquired”.
- After shutdown wait times out, always remove that instance’s state and bootstrap before relaunch.

## Verification

- Unit: `RuntimeRegistryStoreTests.testCleanupKeepsNewestLiveStateWhenAppIDDuplicatesExist`
- Unit: `RuntimeRegistryStoreTests.testAcquireFailsWhenLiveStateExistsEvenWithoutLockDirectory`
- Manual: with at least one collapsed web app running, open another (or the same) from the launcher — host must stay alive.
