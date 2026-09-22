# WORKING.md (project handoff)

Last updated: 22 Sep 2026. Update "Status" after each phase, then commit and push.

## Project
Flutter Android file manager + ZArchiver-style archiver + terminal/Termux. Split-screen: left bubble menu (no text), right file list that switches to a real-time terminal log during operations (black bg, green text, "Back to files" button when done). Shizuku for protected folders. Min SDK 26. State: Riverpod. ZIP: `archive` package in an Isolate. Green accent (#8BC34A) for active/selected states, otherwise dark/neutral, no gradients.

## Status
- Phase 1 (static UI): done
- Phase 2 (real browsing, rename, delete): done, tested on Windows
- Phase 3A (copy/move/delete + terminal log): done, tested on Windows
- Phase 3B (ZIP extraction): done, tested on Windows
- Phase 3C (select all/clear/invert, ZIP compression, batch extraction): done, tested on Windows
- Bugfix: compress-to-ZIP with an existing name showed a "Replace" option and deleted the original ZIP; fixed to use Keep both/Skip (no Replace) and write-then-rename so the original is never lost. Fixed and confirmed.
- Next: Phase 3D, then 3E, 3F, 3G (below), then Search, Phase 4 (Shizuku), Phase 5 (terminal + Termux), Settings last, Phase 6 optional

## Phase 3D (next) - creation, item info, folder counts
- 3D-1: floating "+" button: New folder, New file (any name/extension), New empty ZIP. Same name validation + conflict helper as rename. Never overwrite.
- 3D-2: (i) button in selection bar: scrollable sheet, one card per selected item (name, full path, type/MIME, size + exact bytes, created/modified/accessed, read-only/hidden, parent). Folders: file count, subfolder count, total size (recursive in Isolate, loading + Cancel, report unreadable items). "Copy path" action.
- 3D-3: folders in the main list show "N items" next to the date (direct children only, async with cache, must not slow scrolling).

## Phase 3E (new) - "View type" popup
Toolbar menu (☰) opens an overlay popup, dismissible by tapping outside, applies live with no OK button, persists to SharedPreferences.
- Row 1 "View type" (radio, green underline on active): Detailed (name+size+date list), Compact (name only, denser), Grid (thumbnails). Separate toggle at the end: "Hidden files" switch.
- Row 2 "Sort" (radio): Name, Size, Date, Type. Separate toggle at the end: sort direction (ascending/descending), label flips.

## Phase 3F (new) - "Create Archive" dialog (ZIP-only for now)
Replaces the current simple "Compress to ZIP" flow. UI shows all fields from the original spec, but only ZIP + "No encryption" are functional; every other option is visibly present but disabled with a "Coming soon" label - never fake the function.
- Name input (default from selection, e.g. archiveNew.zip) + "..." button to pick destination folder.
- Format dropdown: zip (enabled), 7z/tar/tar.gz/tar.bz2/tar.xz/tar.lz4/tar.zstd (disabled, "Coming soon").
- Compression level dropdown: None/Fastest/Fast/Normal/Maximum/Ultra (maps to the `archive` package's level options for zip).
- Encryption dropdown (only shown for zip/7z): "None" enabled; ZipCrypto/AES-128/192/256 disabled ("Coming soon", pending koni_archive research below).
- Password field with show/hide icon: stays disabled while encryption = None.
- Split into volumes dropdown: all options disabled ("Coming soon", not supported yet).
- Checkboxes: "Delete source files after compression" (enabled), "Create separate archives" (one archive per selected file, enabled).
- Buttons: Cancel, OK. Same conflict helper as elsewhere - never silently overwrite.

## Phase 3G (new) - Archive Viewer (ZIP-only for now)
Tapping a ZIP opens a new screen showing its contents without extracting.
- Entry list: name, size, modified date. Folder navigation inside the archive (breadcrumb, back to parent).
- Long-press enters multi-select mode with checkboxes.
- Selection mode shows vertical FABs (green): Add file, Add folder, Cancel/close.
- Selected existing entries: Copy (extract to another location), Delete (rebuild the archive without that entry, with progress indicator), Rename, Extract here, Extract to.
- For any archive format this build cannot write to (anything but zip, once other formats are supported later) hide the write actions (Add/Delete) and only allow Copy/Extract.

## Research track (parallel, does not block phases 3D-3G)
- Investigating the `koni_archive` package family (koni_zip, koni_sevenz, koni_rar, koni_codecs) which claims pure-Dart support for 7z/RAR/tar + AES encryption + no native/FFI needed.
- Caution: very new (published ~1 month ago), unverified publisher, ~0-2 likes, ~200 downloads per package, no track record. Do NOT depend on it in file_manager_pro yet.
- Test it in a separate throwaway Flutter project first: round-trip zip/7z/rar with real passwords, verify output opens correctly in real 7-Zip/WinRAR, before considering it for Phase 6.

## Search
- Search by name in the active folder, optional recursive. Runs in an Isolate with progress + Cancel. Filters: extension, size, date. Results shown in the right panel (can jump to location). Search inside protected folders needs Shizuku (after Phase 4).

## Phase 4 - Shizuku (hardest, use a strong model, do it in small steps)
- 4.1 Kotlin setup: `dev.rikka.shizuku:api` and `:provider` deps, `ShizukuProvider` in AndroidManifest.
- 4.2 Status detection: installed (`moe.shizuku.privileged.api`, needs `<queries>` on Android 11+), service running (`pingBinder`), permission granted (`checkSelfPermission`). Binder received/dead listeners. Report status to Flutter; top-bar icon red/yellow/green.
- 4.3 Permission flow: explanation dialog, `requestPermission`, handle denial and "don't ask again", handle binder death without crashing.
- 4.4 UserService (AIDL): list, stat, rename, delete, mkdir, copy, move, read/write stream. Large data must NOT go through plain Binder (~1MB transaction limit) - use ParcelFileDescriptor/stream, send only progress.
- 4.5 Flutter bridge: MethodChannel for commands, EventChannel for progress/log. `shizuku_service.dart` with the same interface as `file_service` so the UI doesn't care about the source.
- 4.6 Integration: Android/data and Android/obb bubbles use Shizuku only when the normal API can't (Android 11+ restricts these). Fallback to normal API if Shizuku is absent. Never assume Shizuku is available.
- 4.7 Honesty: Root (/) without real root is read-only in part. Use UserService, not `Shizuku.newProcess`. State manual test steps for anything untestable without a phone - never claim it works.
- Manual test steps: install Shizuku, enable via wireless debugging, install debug APK, check each status icon, open Android/data, copy/rename/delete in a test folder, revoke permission and stop Shizuku to test fallback.

## Phase 5 - Interactive terminal and Termux
- Terminal button in the top bar opens an interactive terminal popup/sheet (`xterm`). Working dir follows the active folder. Font size from Settings.
- With Shizuku active: shell via UserService (stdin/stdout streamed). Without: an ordinary-privilege shell with a warning about limited access. Document limits if a real PTY isn't feasible.
- "Open in Termux": intent `com.termux.RUN_COMMAND` (`com.termux.permission.RUN_COMMAND`), send command + WORKDIR. Check Termux installed (`<queries>` for `com.termux`) and `allow-external-apps=true` in `~/.termux/termux.properties`; show setup guidance if missing.
- The interactive terminal is separate from the read-only operation-log panel; both stay.

## Settings (done last)
Show hidden files, list order, terminal font size, log line limit (~5000), default extract destination, Shizuku status + permission button, Termux setup guide, theme/density.

## Phase 6 - Optional ZArchiver-style extras (feasibility not confirmed)
- View archive contents without extracting for non-zip formats (7z, rar) - depends on the koni_archive research track above.
- 7z/rar/tar.xz/tar.lz4/tar.zstd support in the Create Archive dialog and Archive Viewer, once koni_archive (or an alternative) is verified safe.
- ZipCrypto/AES encryption, split volumes - same dependency.
- Password-protected archives, partial extraction of entries.

## Structure
lib/ main.dart, models/, services/ (file_service, operation_service), state/, screens/home_screen.dart, widgets/ (bubble_menu, file_list_panel, terminal_panel, conflict_dialog)

## Rules for the agent
- Project already exists, do NOT recreate it. Read this file first, then only files needed for the task. Do not scan the whole project.
- Do not touch android/, ios/, web/, windows/, or tests unless the task says so (Phase 4-5 will touch android/).
- Run flutter analyze once at the end and fix errors. Do not run flutter build or run the app.
- Write files directly, no long planning. Update this file (max 3 lines). Reply format: "Changed: <files>. Analyze: <result>." Nothing else - no explanations, no plans, no code in the reply.
- Never fake functionality. If a format/library limit exists, disable that option in the UI with a "Coming soon" label rather than pretending it works. Never claim Shizuku/Termux features work until tested on a real phone. Never fake terminal logs - log lines must come from the real operation.

## App behavior rules (do not break)
- Never overwrite silently. Reuse the name-conflict helper in file_service.dart. Copy name format: `name (1).ext`.
- Copy in the same folder: only Keep both / Skip (no Replace). Cut in the same folder: do nothing, show "Already in this folder".
- Name validation: not empty, no `/ \ < > : " | ? *`, not only dots. Changing only letter case on the same file is allowed.
- Operation status: Done (green) only if at least one item processed and none failed. Zero processed = "Nothing done" + reason. Any failure = "Completed with errors". Always print processed / skipped / failed summary.
- Skipped items must be reported (amber). Log colors: green normal, red error, amber warning. Max ~5000 log lines. Cancel must clean up partially written files.
- Snackbar: floating, 4 seconds, clearSnackBars() before showing.
- ZIP: zip-slip protection, handle corrupt/fake/encrypted ZIPs, one failed entry must not stop the others. Never delete an original file before its replacement is fully and successfully written (write to temp, rename on success).

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
