# WORKING.md (project handoff)

## Project
Flutter Android file manager. Split-screen: left bubble menu (no text), right file list that switches to a terminal log during operations. Shizuku for protected folders. Min SDK 26. State: Riverpod.

## Status
- Phase 1 (static UI): done
- Phase 2 (real browsing, rename, delete): done, tested on Windows
- Phase 3A (copy/move/delete + terminal log): done, tested on Windows
- Phase 3B (ZIP extraction): in progress
- Next: Search, Phase 4 (Shizuku), Phase 5 (interactive terminal + Termux), Settings last

## Structure
lib/ main.dart, models/, services/ (file_service, operation_service), state/, screens/home_screen.dart, widgets/ (bubble_menu, file_list_panel, terminal_panel, conflict_dialog)

## Rules for the agent
- Read only files needed for the task. Do not scan the whole project.
- Do not touch android/, ios/, web/, windows/, or tests unless the task says so.
- Run flutter analyze once at the end. Do not run flutter build or run the app.
- Never overwrite silently. Reuse the name-conflict helper in file_service.dart.
- Never fake terminal logs. Log lines must come from the real operation.
- Reply in max 6 lines, then stop.

## Dev environment
- Testing on Windows (flutter run -d windows). Test folder: C:\test_files
- No Android emulator. Shizuku/Android storage can only be tested on a real phone.
- windows/CMakeLists.txt has add_compile_definitions(_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS) for permission_handler. Keep it.
- Repo: github.com/fauzan-ridani/file_manager_pro

## Known issues / notes
- Settings and Search buttons are placeholders.
- Android/data and Android/obb bubbles show "Requires Shizuku (Phase 4)".