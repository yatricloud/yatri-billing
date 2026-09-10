# Prompt for New Session

You are taking over development on the **Yatri Billing / Invoiso** Flutter project. 

**Critical Context:**
- We are running a Flutter Web app that uses `sqflite_common_ffi_web` for local database persistence using IndexedDB.
- To test the app, you MUST compile it (`flutter build web --profile`) and serve the `build/web/` folder locally (e.g., `npx serve build/web -l 8080`). Do not serve the uncompiled `web/` folder.
- We recently fixed initialization bugs where the web loader would hang because of missing `sqflite_sw.js` worker scripts and Service Worker cache conflicts. The boot sequence is carefully managed in `web/index.html` and `web/flutter_bootstrap.js`.
- The UI contains a custom E2E `TestDataSeeder` to populate the UI.

**Your task:**
Review the current state, ensure the app successfully loads on port 8080, and continue building out the user's requested features following the styling rules in `DESIGN.md`.
