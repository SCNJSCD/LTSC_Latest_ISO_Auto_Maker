@echo off
setlocal EnableDelayedExpansion

@REM Capture UpdatePack Build Version
set CAPTURE_UPD_VER=26100

@REM Work Dictionary
set WORK_DIR=D:\NT10

@REM Mount Dictionary
set MOUNT_DIR=D:\Mount

set ESD_HASH=HASH_%VERSION%
set UPD_HASH=HASH_%VERSION%_BASE_UPD
set ESD_FILE=%VERSION%.esd
set UPD_FILE=%VERSION%_BASE_UPD.esd
echo %FILEN_AUTH%>.filen-cli-auth-config

echo NUMBER_OF_PROCESSORS = %NUMBER_OF_PROCESSORS%

echo Disable Telemetry
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection" /v "AllowTelemetry" /t REG_DWORD /d "0" /f >nul

echo Download Filen-CLI
curl -sS -L -o filen-cli.exe https://github.com/FilenCloudDienste/filen-cli/releases/download/v0.0.36/filen-cli-v0.0.36-win-x64.exe

for %%A in (!ESD_HASH!) do set EXPECTED_HASH=!%%A!
if "%EXPECTED_HASH%"=="" (echo [ERROR]  %VERSION% SHA256 value not found & exit /b)
echo Download %ESD_FILE%
filen-cli.exe download /ESD/%ESD_FILE%
if not exist %ESD_FILE% (echo [ERROR] %ESD_FILE% not found & exit /b)
echo Verify %ESD_FILE%
for /f %%H in ('powershell -nop -c "(Get-FileHash %ESD_FILE% -Algorithm SHA256).Hash.ToLower()"') do set REAL_HASH=%%H
if not "%REAL_HASH%"=="%EXPECTED_HASH%" (echo [ERROR] Verify Failed & exit /b)

for %%A in (!UPD_HASH!) do set EXPECTED_HASH=!%%A!
if "%EXPECTED_HASH%"=="" (echo [ERROR]  %VERSION% SHA256 value not found & exit /b)
echo Download %UPD_FILE%
filen-cli.exe download /ESD/%UPD_FILE%
if not exist %UPD_FILE% (echo [ERROR] %UPD_FILE% not found & exit /b)
echo Verify %UPD_FILE%
for /f %%H in ('powershell -nop -c "(Get-FileHash %UPD_FILE% -Algorithm SHA256).Hash.ToLower()"') do set REAL_HASH=%%H
if not "%REAL_HASH%"=="%EXPECTED_HASH%" (echo [ERROR] Verify Failed & exit /b)

if not exist %WORK_DIR% md %WORK_DIR%
@REM echo Download UpdateList
@REM powershell -ep Bypass -f Update-Meta4.ps1 -Build %VERSION%
echo Download Updates
if %VERSION% GEQ 22000 (
    aria2c.exe --no-conf --check-certificate=false -x16 -s16 -j5 -c -R -d %WORK_DIR%\%VERSION%\FILES -M XML\%VERSION%.xml --metalink-language="x64" --file-allocation=none --summary-interval=0 --console-log-level=warn --download-result=hide >nul
) else (
    aria2c.exe --no-conf --check-certificate=false -x16 -s16 -j5 -c -R -d %WORK_DIR%\%VERSION%\x64\FILES -M XML\%VERSION%.xml --metalink-language="x64" --file-allocation=none --summary-interval=0 --console-log-level=warn --download-result=hide >nul
    aria2c.exe --no-conf --check-certificate=false -x16 -s16 -j5 -c -R -d %WORK_DIR%\%VERSION%\x86\FILES -M XML\%VERSION%.xml --metalink-language="x86" --file-allocation=none --summary-interval=0 --console-log-level=warn --download-result=hide >nul
)

echo.
echo %ESD_FILE% -^> %VERSION%.wim
wimlib-imagex.exe export %ESD_FILE% all %WORK_DIR%\%VERSION%.wim --compress=LZX:20 --check --quiet
echo Extract %UPD_FILE% -^> %WORK_DIR%\%VERSION%
wimlib-imagex.exe apply %UPD_FILE% 1 %WORK_DIR% --no-acls --quiet
del /f /q %ESD_FILE% %UPD_FILE%

echo Prepare Utils
copy /y libwim-15.dll %WORK_DIR% >nul
copy /y wimlib-imagex.exe %WORK_DIR% >nul
copy /y .filen-cli-auth-config %WORK_DIR% >nul
copy /y filen-cli.exe %WORK_DIR% >nul
copy /y WUE.cmd %WORK_DIR% >nul
copy /y Cleanup.cmd %WORK_DIR% >nul
copy /y superUser64.exe %WORK_DIR% >nul
copy /y dpx_14393.dll %WORK_DIR% >nul
copy /y msdelta.dll %WORK_DIR% >nul
copy /y PSFExtractor.exe %WORK_DIR% >nul
copy /y _%VERSION%.cmd %WORK_DIR% >nul

cd /d %WORK_DIR%

for %%a in (
    "%WORK_DIR%\%VERSION%\FILES\*.msu"
    "%WORK_DIR%\%VERSION%\FILES\*.cab"
    "%WORK_DIR%\%VERSION%\x64\FILES\*.msu"
    "%WORK_DIR%\%VERSION%\x64\FILES\*.cab"
    "%WORK_DIR%\%VERSION%\x86\FILES\*.msu"
    "%WORK_DIR%\%VERSION%\x86\FILES\*.cab"
) do (
    call WUE.cmd "%%a" "%%~dpa" %VERSION%
    del /f /q "%%a"
)

for /f %%a in ('type _SSU.txt') do set "_SSU=%%a"
for /f %%a in ('type _LCU.txt') do set "_LCU=%%a"
for /f %%a in ('type _NET.txt') do set "_NET=%%a"
for /f %%a in ('type _SDU.txt') do set "_SDU=%%a"
del /f /q _SSU.txt _LCU.txt _NET.txt _SDU.txt

echo SSU     = %_SSU%
echo LCU     = %_LCU%
echo DNFCU   = %_NET%
echo SetupDU = %_SDU%

if "%VERSION%"=="14393" call _%VERSION%.cmd %MOUNT_DIR% %_SSU% %_NET% %_LCU% %_SDU%
if "%VERSION%"=="17763" call _%VERSION%.cmd %MOUNT_DIR% %_SSU% %_NET% %_LCU% %_SDU%
if "%VERSION%"=="19041" call _%VERSION%.cmd %MOUNT_DIR% %_SSU% %_NET% %_LCU% %_SDU%
if "%VERSION%"=="26100" call _%VERSION%.cmd %MOUNT_DIR% %_SSU% %_NET% %_LCU% %_SDU%

echo %VERSION%_u.wim -^> %VERSION%.esd
wimlib-imagex.exe export %VERSION%_u.wim all %VERSION%.esd --solid --check --quiet

echo Verify %VERSION%.esd
for /f %%H in ('powershell -nop -c "(Get-FileHash %VERSION%.esd -Algorithm SHA256).Hash.ToLower()"') do (
    echo %VERSION%.esd - SHA256: %%H
    echo H256: %%H>>%VERSION%.txt
)

echo Upload %VERSION%.esd
filen-cli.exe upload %VERSION%.esd /ESD_Completed/%VERSION%.esd
echo Upload %VERSION%.txt
filen-cli.exe upload %VERSION%.txt /ESD_Completed/%VERSION%.txt

set "UPD_ROOT=%WORK_DIR%\%VERSION%\FILES"
if "%VERSION%"=="%CAPTURE_UPD_VER%" if exist %UPD_ROOT% (
    if exist UpdatePack rd /s /q UpdatePack
    md UpdatePack
    move %UPD_ROOT%\%_NET% UpdatePack >nul
    move %UPD_ROOT%\%_SSU% UpdatePack >nul
    move %UPD_ROOT%\%_LCU% UpdatePack >nul

    echo Capture UpdatePack
    wimlib-imagex.exe capture UpdatePack %VERSION%_UPD.esd --no-acls --solid --check --quiet

    move UpdatePack\%_NET% %UPD_ROOT% >nul
    move UpdatePack\%_SSU% %UPD_ROOT% >nul
    move UpdatePack\%_LCU% %UPD_ROOT% >nul

    for /f %%H in ('powershell -nop -c "(Get-FileHash %VERSION%_UPD.esd -Algorithm SHA256).Hash.ToLower()"') do (
        echo %VERSION%_UPD.esd - SHA256: %%H
        echo H256: %%H>>%VERSION%_UPD.txt
    )

    echo Upload %VERSION%_UPD.esd
    filen-cli.exe upload %VERSION%_UPD.esd /ESD_Completed/%VERSION%_UPD.esd
    echo Upload %VERSION%_UPD.txt
    filen-cli.exe upload %VERSION%_UPD.txt /ESD_Completed/%VERSION%_UPD.txt
)

echo All done.
