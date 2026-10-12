@echo off
cd /d "%~dp0"

set http_proxy=http://127.0.0.1:7897
set https_proxy=http://127.0.0.1:7897

rd /s /q .git
git init
git config core.autocrlf false
git branch -M main
git remote remove origin
git remote add origin https://github.com/SCNJSCD/LTSC_Latest_ISO_Auto_Maker.git
git add -A
git status
git commit -m "Update latest version"
git push -u origin main --force

echo.
pause
