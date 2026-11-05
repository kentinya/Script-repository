# Jellyfin Cinema Windows RC1 integration

This branch is isolated from existing Script-repository projects.

## Build prerequisites
Copy all files from `Jellyfin_Cinema_V1_RC1_Windows_Installer_Build_Kit.zip` into `jellyfin-cinema/`, EXCEPT its `.github/workflows/windows-build.yml`. The repository-level workflow is `.github/workflows/jellyfin-cinema-windows.yml`.

GitHub Actions builds Windows only after the source files exist in that directory. The workflow checks for the required Flutter files, performs analysis/tests, builds Windows Release, packages portable ZIP and Inno Setup EXE, verifies SHA-256, then uploads artifacts.

**Status:** workflow staged; source transfer and a successful Windows build are not yet confirmed.
