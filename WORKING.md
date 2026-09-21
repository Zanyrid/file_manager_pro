# WORKING.md (project handoff)

Last updated: 21 Sep 2026. Update "Status" after each phase, then commit and push.

## Project
Flutter Android file manager + ZArchiver-style archiver + terminal/Termux. Split-screen: left bubble menu (no text), right file list that switches to a real-time terminal log during operations (black bg, green text, "Back to files" button when done). Shizuku for protected folders. Min SDK 26. State: Riverpod. ZIP: `archive` package in an Isolate.

## Status
- Phase 1 (static UI): done
- Phase 2 (real browsing, rename, delete): done, tested on Windows
- Phase 3A (copy/move/delete + terminal log): done, tested on Windows
- Phase 3B (ZIP extraction): done, tested on Windows
- Phase 3C (select all/clear/invert, ZIP compression, batch extraction): done, tested on Windows
- Next: Phase 3D, then Search, Phase 4 (Shizuku), Phase 5 (interactive terminal + Termux), Settings last, Phase 6 optional

## Phase 3D (next)
- 3D-1: floating "+" button: New folder, New file (any name/extension), New empty ZIP. Same name validation + conflict helper as rename. Never overwrite.
- 3D-2: (i) button in selection bar: scrollable sheet, one card per selected item (name, full path, type/MIME, size + exact bytes, created/modified/accessed, read-only/hidden, parent). Folders: file count, subfolder count, total size (recursive in Isolate, loading + Cancel, report unreadable items). "Copy path" action.
- 3D-3: folders in the main list show "N items" next to the date (direct children only, async with cache, must not slow scrolling).

## Structure
lib/ main.dart, models/, services/ (file_service, operation_service), state/, screens/home_screen.dart, widgets/ (bubble_menu, file_list_panel, terminal_panel, conflict_dialog)

## Rules for the agent
- Project already exists, do NOT recreate it. Read this file first, then only files needed for the task. Do not scan the whole project.
- Do not touch android/, ios/, web/, windows/, or tests unless the task says so (Phase 4-5 will touch android/).
- Run flutter analyze once at the end and fix errors. Do not run flutter build or run the app.
- Write files directly, no long planning. Update this file (max 3 lines). Reply in max 3-6 lines, then stop and wait.
- Never fake functionality. If an Android/Shizuku limit exists, say so and build the closest architecture behind the service interface. Never claim Shizuku/Termux features work until tested on a real phone.
- Never fake terminal logs. Log lines must come from the real operation.

## App behavior rules (do not break)
- Never overwrite silently. Reuse the name-conflict helper in file_service.dart. Copy name format: `name (1).ext`.
- Copy in the same folder: only Keep both / Skip (no Replace). Cut in the same folder: do nothing, show "Already in this folder".
- Name validation: not empty, no `/ \ < > : " | ? *`, not only dots. Changing only letter case on the same file is allowed.
- Operation status: Done (green) only if at least one item processed and none failed. Zero processed = "Nothing done" + reason. Any failure = "Completed with errors". Always print processed / skipped / failed summary.
- Skipped items must be reported (amber). Log colors: green normal, red error, amber warning. Max ~5000 log lines. Cancel must clean up partially written files.
- Snackbar: floating, 4 seconds, clearSnackBars() before showing.
- ZIP: zip-slip protection, handle corrupt/fake/encrypted ZIPs, one failed entry must not stop the others.

## Dev environment
- Windows RDP (destroyed after ~6 hours). Back up to GitHub often. Repo: github.com/fauzan-ridani/file_manager_pro (private).
- Paths: Flutter C:\src\flutter, project C:\file_manager_pro, test folder C:\test_files. Test with `flutter run -d windows`.
- No Android emulator. Shizuku/Android storage/Android/data/Termux can only be tested on a real phone.
- windows/CMakeLists.txt has add_compile_definitions(_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS) for permission_handler. Keep it.

## Known issues / notes
- Settings and Search buttons are placeholders.
- Android/data and Android/obb bubbles show "Requires Shizuku (Phase 4)".
- Root bubble icon looks similar to the Shizuku top-bar icon (cosmetic, fix later).
- Flutter warning about ListTile inside ColoredBox (press-effect shadow): fix if it still appears.
- Git warning "LF will be replaced by CRLF" is harmless.
