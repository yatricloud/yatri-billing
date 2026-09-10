# Project Memory

## Current Implementation Details
- **UI Theme:** Custom branding with specific blue primary color (`0xFF007CFF`).
- **Web Loader:** Clean and minimal spinner with Yatri Billing logo, implemented directly in HTML/CSS within `index.html` and managed by `flutter_bootstrap.js`.
- **Database:**
  - `sqflite` is used across platforms.
  - On Web, it leverages `sqflite_common_ffi_web` and relies on `sqflite_sw.js` and `sqlite3.wasm` which are built into the web bundle.
  - If you encounter a frozen loader or `Failed to fetch a worker script`, ensure `dart run sqflite_common_ffi_web:setup` has been run and the assets exist in `build/web/`.
- **E2E Testing:** `TestDataSeeder` automatically populates the dashboard with dummy invoices and clients for UI testing.

## Known Issues Resolved
- **Service Worker Cache Loops:** Solved by disabling default Flutter service workers in `flutter_bootstrap.js` and unregistering old ones.
- **WASM Missing Error:** Solved by correctly setting up the sqflite web binaries.
