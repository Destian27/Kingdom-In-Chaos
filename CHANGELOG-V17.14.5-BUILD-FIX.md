# v17.14.5 build fix (tanpa ganti versi)

- `NativeGameRuntimeBridge`: `GameOnlineOverlay.refreshBarterStatus(app)` (DtpApp bukan Activity, error javac) diganti
  `refreshBarterStatus()`; overload tanpa argumen ditambahkan di `GameOnlineOverlay` dan memakai activity aktif.
- `.github/workflows/build-apk.yml`: `python3 -m pip install --quiet pillow` sebelum `build_dtp.py` (dipakai `tools/patch_ui_polish.py`).
- `.gitignore`: `tools/*` + `!tools/*.py` supaya script patch ikut ter-commit.
- Native: patch retain tombol uang (v17.11) sudah ada di libgame.so.
