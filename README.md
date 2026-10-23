# HerPattern Watch — standalone wearable intelligence

Native watchOS 10+ SwiftUI app. HealthKit permission and entitlement are
configured in `project.yml`/Info.plist. The app reads actual available heart
rate, **HRV SDNN**, resting heart rate, sleep samples, respiration, wrist
temperature (compatible models), and activity. It computes experimental
within-person feature deltas using an older multiweek baseline and runs the
ported `HerPatternPocketPCA` artifact on-watch. No synthetic data is generated.

The app displays state/confidence/3 explanatory contributors/missing fields,
asks a brief pain question on changed patterns and can submit a minimal
continuity record. Bee connects directly from the watch using the user's Bee
Developer Mode token, stored in the watch-only ThisDeviceOnly Keychain. Users
can review and select tasks to import into HerPattern and separately review and
confirm a written plan before sending it to Bee. Users may select one of their
own Bee conversation statements, write a short note, and separately preview and
confirm adding it to the HerPattern daily log; raw conversation text is not
uploaded. No Bee journal endpoints are assumed.
All wearable uploads are **OFF by default** until the patient opts in; their
offline outbox is encrypted in ThisDeviceOnly Keychain.

The original next-day *endometriosis burden forecast* remains a distinct
server-sourced forecast from `/assistant/context`. Recovery score is an
experimental wearable index and must not be confused with clinical risk.

## Before running
1. Deploy the HerPattern mobile API with the Bee and wearable routes, and apply
   the required Bee-import and wearable-event SQL migrations.
2. Set `HP_SUPABASE_PUBLISHABLE_KEY` to the project's public/publishable key in
   the Xcode target's build settings or pass it to `xcodebuild`. The project URL
   is already configured; never use a service-role key.
3. From `native/watchos`, run `xcodegen generate`, then build the
   `HerPatternWatch` scheme for a watchOS Simulator or physical watch. Select an
   Apple signing team to install on hardware.

For a simulator build with the key held outside source control:

```sh
export HP_SUPABASE_PUBLISHABLE_KEY="sb_publishable_..."
xcodebuild -project HerPatternWatchStandalone.xcodeproj \
  -scheme HerPatternWatch \
  -destination 'platform=watchOS Simulator,name=Apple Watch Series 12 (46mm)' \
  "HP_SUPABASE_PUBLISHABLE_KEY=$HP_SUPABASE_PUBLISHABLE_KEY" build
```

4. Sign in with an approved HerPattern account. Open **Bee** on the watch,
   enter your Bee Developer Mode token and connect. Select Bee tasks and confirm
   to import them into HerPattern. To send a plan to Bee, write it on the watch,
   review the displayed text and confirm the send.
5. Run on a physical watch with approved HealthKit access; missing sensors
   must show as missing. Test revoked HealthKit access and an offline upload.

This is **source not a compiled/signed watch app**, and the PCA weights have
not been validated clinically. Apple HRV SDNN is **not** the RMSSD sensor
measure named in the browser demo. Investigate/calibrate that mismatch
before clinical or scientific claims.
