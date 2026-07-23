@REM WUE - Windows Update Extractor

@echo off
setlocal EnableDelayedExpansion

set "_cwd=D:\NT10"
if "%_cwd:~-1%"=="\" set "_cwd=%_cwd:~0,-1%"
set "_cab=%WinDir%\System32\expand.exe"
set "_psf=%_cwd%\PSFExtractor.exe"
set "_wim=%_cwd%\wimlib-imagex.exe"
if not exist "%_wim%" set "_wim=%WinDir%\System32\wimlib-imagex.exe"

set "src=%~1"
set "dest=%~dp2%~nx2"
if "%dest:~-1%"=="\" set "dest=%dest:~0,-1%"
set "_random=%random%"
set "tmp_dir=%dest%\_%_random%"
set "tmp_dir_inner=%dest%\_%_random%\_%_random%"

set "dpx_dix="
if "%~3"=="14393" set "dpx_dix=1"
set "no_arch="
if "%~3"=="26100" set "no_arch=1"

if "%~x1"==".cab" call :cab "%~1"
if "%~x1"==".msu" call :msu "%~1"
exit /b

:cab
@REM Common CAB
if exist "%tmp_dir%" rd /s /q "%tmp_dir%"
md "%tmp_dir%"
"%_cab%" -f:* "%~1" "%tmp_dir%" >nul
if exist "%dest%\%~n1" rd /s /q "%dest%\%~n1"
move /y "%tmp_dir%" "%dest%\%~n1" >nul
echo Extracted: %dest%\%~n1
if exist "%dest%\%~n1\*.dll" (
    set "_SDU=%~n1"
    set "_SDU=!_SDU:-x64=!"
    set "_SDU=!_SDU:-x86=!"
    echo !_SDU!>_SDU.txt
)
exit /b

:msu
if exist "%tmp_dir%" rd /s /q "%tmp_dir%"
md "%tmp_dir%"
"%_wim%" info "%~1" >nul 2>nul && goto :psf
if "%dpx_dix%"=="1" (
    @REM Windows 10 LTSB 2016 LCU
    set "_cab=%tmp_dir%\expand.exe"
    if not exist "%tmp_dir%\dpx.dll" copy /y "%_cwd%\dpx_14393.dll" "%tmp_dir%\dpx.dll" >nul
    if not exist "%tmp_dir%\expand.exe" copy /y "%WinDir%\System32\expand.exe" "%tmp_dir%\expand.exe" >nul
)
"%_cab%" -f:Windows*.cab "%~1" "%tmp_dir%" >nul
for /f %%a in ("%tmp_dir%\*.cab") do (
    if exist "%tmp_dir_inner%" rd /s /q "%tmp_dir_inner%"
    md "%tmp_dir_inner%"
    if exist "%tmp_dir%\%%~na" rd /s /q "%tmp_dir%\%%~na"
    md "%tmp_dir%\%%~na"
    "%_cab%" -f:Windows*.cab "%%a" "%tmp_dir_inner%" >nul
    "%_cab%" -f:SSU*.cab "%%a" "%tmp_dir_inner%" >nul
    "%_cab%" -f:Cab_*_for_KB*.cab "%%a" "%tmp_dir_inner%" >nul
    if not exist "%tmp_dir_inner%\*.cab" (
        @REM Common MSU
        "%_cab%" -f:* "%%a" "%tmp_dir%\%%~na" >nul
        call :kb_arch "%tmp_dir%\%%~na\update.mum" %no_arch%
        if exist "%dest%\!dir_name!" rd /s /q "%dest%\!dir_name!"
        move /y "%tmp_dir%\%%~na" "%dest%\!dir_name!" >nul
        echo Extracted: %dest%\!dir_name!
    )
    if exist "%tmp_dir_inner%\Cab_*_for_KB*.cab" (
        @REM Windows 10 LTSB 2015 (x64 / x86) / 2016 (x64 / x86) LCU
        "%_cab%" -f:update.* "%%a" "%tmp_dir%\%%~na" >nul
        for %%# in ("%tmp_dir_inner%\Cab_*_for_KB*.cab") do "%_cab%" -f:* "%%#" "%tmp_dir%\%%~na" >nul
        del /f /q %tmp_dir_inner%\Cab_*_for_KB*.cab
        call :kb_arch "%tmp_dir%\%%~na\update.mum"
        if exist "%dest%\!dir_name!" rd /s /q "%dest%\!dir_name!"
        move /y "%tmp_dir%\%%~na" "%dest%\!dir_name!" >nul
        echo Extracted: %dest%\!dir_name!
    )
)
for %%a in ("%tmp_dir_inner%\*.cab") do (
    if exist "%tmp_dir_inner%\%%~na" rd /s /q "%tmp_dir_inner%\%%~na"
    md "%tmp_dir_inner%\%%~na"
    "%_cab%" -f:Cab_*_for_KB*.cab "%%a" "%tmp_dir_inner%" >nul
    if exist "%tmp_dir_inner%\Cab_*_for_KB*.cab" (
        @REM Windows 10 LTSC 2019 (x64) / 2021 (x64 / x86) LCU
        "%_cab%" -f:update.* "%%a" "%tmp_dir_inner%\%%~na" >nul
        for %%# in ("%tmp_dir_inner%\Cab_*_for_KB*.cab") do "%_cab%" -f:* "%%#" "%tmp_dir_inner%\%%~na" >nul
    ) else (
        @REM Windows 10 LTSC 2019 (x86) LCU and SSU
        "%_cab%" -f:* "%%a" "%tmp_dir_inner%\%%~na" >nul
    )
    call :kb_arch "%tmp_dir_inner%\%%~na\update.mum"
    if exist "%dest%\!dir_name!" rd /s /q "%dest%\!dir_name!"
    move /y "%tmp_dir_inner%\%%~na" "%dest%\!dir_name!" >nul
    echo Extracted: %dest%\!dir_name!
)
rd /s /q "%tmp_dir%"
exit /b

:psf
if exist "%tmp_dir_inner%" rd /s /q "%tmp_dir_inner%"
md "%tmp_dir_inner%"
"%_wim%" extract "%~1" 1 SSU*.cab --dest-dir="%tmp_dir%" --no-acls >nul
for %%a in ("%tmp_dir%\*.cab") do (
    if exist "%tmp_dir%\%%~na" rd /s /q "%tmp_dir%\%%~na"
    md "%tmp_dir%\%%~na"
    "%_cab%" -f:* "%%a" "%tmp_dir%\%%~na" >nul
    call :kb_arch "%tmp_dir%\%%~na\update.mum" %no_arch%
    if exist "%dest%\!dir_name!" rd /s /q "%dest%\!dir_name!"
    move /y "%tmp_dir%\%%~na" "%dest%\!dir_name!" >nul
    echo Extracted: %dest%\!dir_name!
)
"%_wim%" extract "%~1" 1 Windows*.psf --dest-dir="%tmp_dir%" --no-acls >nul
"%_wim%" extract "%~1" 1 Windows*.wim --dest-dir="%tmp_dir%" --no-acls >nul
for %%a in ("%tmp_dir%\*.wim") do "%_wim%" apply "%%a" 1 "%tmp_dir_inner%" --no-acls >nul
for %%a in ("%tmp_dir%\*.psf") do "%_psf%" -v2 "%%a" "%tmp_dir_inner%\express.psf.cix.xml" "%tmp_dir_inner%" >nul
del /f /q "%tmp_dir_inner%\express.psf.cix.xml"
call :kb_arch "%tmp_dir_inner%\update.mum" %no_arch%
if exist "%dest%\%dir_name%" rd /s /q "%dest%\%dir_name%"
move /y "%tmp_dir_inner%" "%dest%\%dir_name%" >nul
echo Extracted: %dest%\%dir_name%
rd /s /q "%tmp_dir%"
exit /b

:kb_arch
for /f %%a in ('powershell -nop -c "[xml]$x=Get-Content '%~1';Write-Host $x.assembly.package.identifier"') do set "_KB=%%a"
for /f %%a in ('powershell -nop -c "[xml]$x=Get-Content '%~1';Write-Host $x.assembly.assemblyIdentity.processorArchitecture"') do set "_ARCH=%%a"
for /f %%a in ('powershell -nop -c "[xml]$x=Get-Content '%~1';Write-Host $x.assembly.assemblyIdentity.name"') do set "_TYPE=%%a"
set "dir_name=%_KB%-x86"
if "%_ARCH%"=="amd64" set "dir_name=%_KB%-x64"
if "%~2"=="1" set "dir_name=%_KB%"
echo "%_TYPE%" | find /i "DotNetRollup" >nul && echo %_KB%>_NET.txt
echo "%_TYPE%" | find /i "ServicingStack" >nul && echo %_KB%>_SSU.txt
echo "%_TYPE%" | find /i "RollupFix" >nul && echo %_KB%>_LCU.txt
echo "%_TYPE%" | find /i "Package_for_KB" >nul && (
    for /f %%a in ('powershell -nop -c "[xml]$x=Get-Content '%~1';Write-Host $x.assembly.assemblyIdentity.version"') do set "_VER=%%a"
    echo "!_VER!" | find /i "14393." >nul && echo %_KB%>_SSU.txt
)
exit /b
