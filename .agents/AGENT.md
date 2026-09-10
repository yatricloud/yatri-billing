# Agent Context & Directives

This file contains the context, history, and operational directives for AI agents working on the Yatri Billing / Invoiso project.

## Project State & History
- **Project Name:** Invoiso / Yatri Billing Cloud
- **Framework:** Flutter (Web & Desktop)
- **Database:** `sqflite_common_ffi_web` for IndexedDB web persistence.
- **Boot Process:** We use a highly customized `flutter_bootstrap.js` to manage the splash screen, initializing `sqflite_sw.js` (SQLite web worker), and bypassing default Service Worker cache to avoid "Failed to fetch a worker script" errors.
- **Seeding:** E2E Data seeder `TestDataSeeder` is available to seed the local database for rapid testing.

## Constraints & Rules
- Always use `mobile-web-app-capable` meta tags; do not use Apple-specific legacy tags.
- For Web testing, use `flutter build web --profile` and serve the `/build/web` directory. Do not serve the root `/web` directory directly, as it lacks compiled assets and the SQLite Web Worker.
- Do NOT use 3D animations or heavy libraries for the loading screen; stick to the clean, minimal HTML/CSS spinner.
- All database interactions must account for FFI constraints on the Web by utilizing `databaseFactoryFfiWeb`.

## Running Locally
To test the web build locally with persistent data:
1. Build: `flutter build web --profile`
2. Serve: `npx serve build/web -l 8080`
