@echo off
setlocal enabledelayedexpansion

:: Git zoeken: eerst in PATH, anders standaard locaties + GitHub Desktop
set "GITPATH="
where git >nul 2>&1
if errorlevel 1 (
  if exist "C:\Program Files\Git\bin\git.exe" (
    set "GITPATH=C:\Program Files\Git\bin"
  ) else if exist "C:\Program Files (x86)\Git\bin\git.exe" (
    set "GITPATH=C:\Program Files (x86)\Git\bin"
  ) else (
    if exist "%LOCALAPPDATA%\GitHubDesktop\app-3.5.6\resources\app\git\cmd\git.exe" (
      set "GITPATH=%LOCALAPPDATA%\GitHubDesktop\app-3.5.6\resources\app\git\cmd"
    )
    if not defined GITPATH if exist "%LOCALAPPDATA%\GitHubDesktop\app-3.5.5\resources\app\git\cmd\git.exe" (
      set "GITPATH=%LOCALAPPDATA%\GitHubDesktop\app-3.5.5\resources\app\git\cmd"
    )
  )
  if defined GITPATH set "PATH=!GITPATH!;!PATH!"
)
where git >nul 2>&1
if errorlevel 1 (
  echo Git niet gevonden. Installeer Git for Windows of GitHub Desktop.
  pause
  exit /b 1
)

cd /d "%~dp0"

echo Adding changes...
git add .
if errorlevel 1 (
  echo git add mislukt.
  pause
  exit /b 1
)

echo Committen...
git commit -m "push via push.bat - %date% %time%"
if errorlevel 1 (
  echo Geen wijzigingen om te committen, of commit mislukt.
  echo Probeer nu te pushen...
)

echo Pushen naar origin main...
git push origin main
if errorlevel 1 (
  echo Push mislukt. Controleer je internet en of je ingelogd bent op GitHub.
  pause
  exit /b 1
)

echo.
echo Klaar. Wijzigingen zijn naar GitHub gepusht.
pause
