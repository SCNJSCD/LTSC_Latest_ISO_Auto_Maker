@setlocal EnableDelayedExpansion
@echo off & title Update Windows 11 Build 26100 Image
chcp 936 >nul
set "_DISM=DISM.exe"
set "WorkDir=%~dp0"
set "WorkDir=%WorkDir:~0,-1%"
set "Mount=%~1"
set "UPD=26100"
set "UPDPath=%WorkDir%\%UPD%\FILES"
set "WIMIMAGE=%WorkDir%\%UPD%"

@REM 手动定义最新更新的 KB 号
set "LCUTOTAL=2"
set "SSU_=%~2"
set "DNFCU_=%~3"
set "LCU1_=KB5043080"
set "LCU2_=%~4"
set "SETUPDU_=%~5"

reg query "HKU\S-1-5-19" >nul 2>nul || (echo. & echo  需要管理员权限, 按任意键退出 & pause >nul & goto :end)
echo %WorkDir%| find " ">nul && (echo. & echo  路径不能包含空格, 按任意键退出 & pause >nul & goto :end)
if exist %~dp0%UPD%_u.wim (echo. & echo  %UPD%_u.wim 已存在, 按任意键退出 & pause >nul & goto :end)
copy /y %WIMIMAGE%.wim %WIMIMAGE%_org.wim >nul
if not exist %WIMIMAGE%_org.wim (echo. & echo  发生错误, 按任意键退出 & pause >nul & goto :end)
set "StartTime=%TIME%"
call :instupd
goto :final

:instupd
set "SSU=%UPDPath%\%SSU_%"
for /l %%# in (1,1,%LCUTOTAL%) do set "LCU%%#=!UPDPath!\!LCU%%#_!"
set "DNFCU=%UPDPath%\%DNFCU_%"
set "SETUPDU=%UPDPath%\%SETUPDU_%"
set "NETFX3=%UPDPath%\NetFx3"
set "_25H2=%UPDPath%\KB5054156"
for /l %%a in (1,1,5) do (
    if not exist "%Mount%\%%a" md "%Mount%\%%a"
    echo %_DISM% /Quiet /Mount-Wim /WimFile:%WIMIMAGE%.wim /Index:%%a /MountDir:%Mount%\%%a
    %_DISM% /Quiet /Mount-Wim /WimFile:%WIMIMAGE%.wim /Index:%%a /MountDir:%Mount%\%%a
    if exist %Mount%\%%a\Windows\regedit.exe (
        call :addpkg %Mount%\%%a %SSU%
        call :addpkg %Mount%\%%a %_25H2%
        if exist %Mount%\%%a\Windows\explorer.exe call :addpkg %Mount%\%%a %DNFCU%
        for /l %%# in (1,1,%LCUTOTAL%) do (
            call :addpkg %Mount%\%%a !LCU%%#!
            if exist %Mount%\%%a\Windows\explorer.exe (
                call :cleanimg %Mount%\%%a
            ) else (
                call :cleanimg %Mount%\%%a RB
            )
        )
        if exist %Mount%\%%a\Windows\explorer.exe (
            call :addpkg %Mount%\%%a %NETFX3%
            set "RPKG=/PackagePath:%DNFCU%"
            for /l %%# in (1,1,%LCUTOTAL%) do set "RPKG=!RPKG! /PackagePath:!LCU%%#!"
            echo %_DISM% /Quiet /Image:%Mount%\%%a /Add-Package !RPKG!
            %_DISM% /Quiet /Image:%Mount%\%%a /Add-Package !RPKG!
            if not exist %Mount%\%%a\Windows\Setup\Scripts md %Mount%\%%a\Windows\Setup\Scripts
            (
                echo @echo off
                echo DISM.exe /Online /Cleanup-Image /StartComponentCleanup
                echo del /f /q "%%~0"
            )>%Mount%\%%a\Windows\Setup\Scripts\SetupComplete.cmd
        )
    )
)
pushd %SETUPDU%
for /f %%a in ('dir /b /a-d') do copy /y %%a %Mount%\1\sources >nul
popd
xcopy /CIDERY %SETUPDU%\replacementmanifests %Mount%\1\sources\replacementmanifests >nul
xcopy /CIDRY %SETUPDU% %Mount%\1\sources >nul
xcopy /CIDRY %SETUPDU%\zh-cn %Mount%\1\sources\zh-cn >nul
xcopy /CIDRY %Mount%\3\sources %Mount%\1\sources >nul
xcopy /CIDRY %Mount%\3\sources\zh-cn %Mount%\1\sources\zh-cn >nul
del /f /q %Mount%\1\sources\background.bmp
del /f /q %Mount%\1\sources\testplugin.dll
del /f /q %Mount%\1\sources\xmllite.dll
del /f /q %Mount%\1\sources\zh-CN\vofflps_server.rtf
@REM copy /y %Mount%\3\Windows\Boot\PCAT\memtest.exe %Mount%\1\boot >nul
@REM copy /y %Mount%\3\Windows\Boot\PCAT\bootmgr %Mount%\1 >nul
copy /y %Mount%\3\Windows\Boot\EFI\memtest.efi %Mount%\1\efi\microsoft\boot >nul
copy /y %Mount%\3\Windows\Boot\EFI\boot.stl %Mount%\1\efi\microsoft\boot >nul
copy /y %Mount%\3\Windows\Boot\EFI\boot.pnd.stl %Mount%\1\efi\microsoft\boot >nul
if exist %Mount%\3\Windows\Boot\EFI_EX\*_EX.efi (
    copy /y %Mount%\3\Windows\Boot\EFI_EX\bootmgfw_EX.efi %Mount%\1\efi\boot\bootx64.efi >nul
    copy /y %Mount%\3\Windows\Boot\EFI_EX\bootmgr_EX.efi %Mount%\1\bootmgr.efi >nul
    copy /y %Mount%\3\Windows\Boot\DVD_EX\EFI\en-US\efisys_EX.bin %Mount%\1\efi\microsoft\boot\efisys.bin >nul
    copy /y %Mount%\3\Windows\Boot\DVD_EX\EFI\en-US\efisys_noprompt_EX.bin %Mount%\1\efi\microsoft\boot\efisys_noprompt.bin >nul
    copy /y %Mount%\3\Windows\Boot\Fonts_EX\*.ttf %Mount%\1\boot\fonts >nul
    copy /y %Mount%\3\Windows\Boot\Fonts_EX\*.ttf %Mount%\1\efi\microsoft\boot\fonts >nul
    for /f "tokens=1-3 delims=_." %%i in ('dir /b "%Mount%\1\boot\fonts\*_EX.ttf"') do move /y %Mount%\1\boot\fonts\%%i_%%j_%%k.ttf %Mount%\1\boot\fonts\%%i_%%j.ttf >nul
    for /f "tokens=1-3 delims=_." %%i in ('dir /b "%Mount%\1\efi\microsoft\boot\fonts\*_EX.ttf"') do move /y %Mount%\1\efi\microsoft\boot\fonts\%%i_%%j_%%k.ttf %Mount%\1\efi\microsoft\boot\fonts\%%i_%%j.ttf >nul
) else (
    copy /y %Mount%\3\Windows\Boot\EFI\bootmgfw.efi %Mount%\1\efi\boot\bootx64.efi >nul
    copy /y %Mount%\3\Windows\Boot\EFI\bootmgr.efi %Mount%\1 >nul
    copy /y %Mount%\3\Windows\Boot\DVD\EFI\en-US\efisys.bin %Mount%\1\efi\microsoft\boot >nul
    copy /y %Mount%\3\Windows\Boot\DVD\EFI\en-US\efisys_noprompt.bin %Mount%\1\efi\microsoft\boot >nul
    copy /y %Mount%\3\Windows\Boot\Fonts\*.ttf %Mount%\1\boot\fonts >nul
    copy /y %Mount%\3\Windows\Boot\Fonts\*.ttf %Mount%\1\efi\microsoft\boot\fonts >nul
)
copy /y %Mount%\5\Windows\System32\wlanapi.dll %Mount%\2\Windows\System32 >nul
copy /y %Mount%\5\Windows\System32\mobilenetworking.dll %Mount%\2\Windows\System32 >nul
copy /y %Mount%\5\Windows\System32\wlanapi.dll %Mount%\3\Windows\System32 >nul
copy /y %Mount%\5\Windows\System32\mobilenetworking.dll %Mount%\3\Windows\System32 >nul
if exist %Mount%\5\Recovery rd %Mount%\5\Recovery
for /l %%a in (1,1,5) do (
    if not "%%a"=="1" ("%~dp0superUser64.exe" /s /w %WorkDir%\Cleanup.cmd %Mount%\%%a)
    echo %_DISM% /Quiet /Unmount-Wim /MountDir:%Mount%\%%a /Commit
    %_DISM% /Quiet /Unmount-Wim /MountDir:%Mount%\%%a /Commit
    rd %Mount%\%%a
)
goto :eof

:addpkg
echo %_DISM% /Quiet /Image:%~1 /Add-Package /PackagePath:%~2
%_DISM% /Quiet /Image:%~1 /Add-Package /PackagePath:%~2
goto :eof

:cleanimg
for /f %%a in ('dir %~1\Windows\WinSxS /ad /b ^| find /c /v ""') do set "before_count=%%a"
if "%~2" == "RB" (
    echo %_DISM% /Quiet /Image:%~1 /Cleanup-Image /StartComponentCleanup /ResetBase
    %_DISM% /Quiet /Image:%~1 /Cleanup-Image /StartComponentCleanup /ResetBase
) else (
    echo %_DISM% /Quiet /Image:%~1 /Cleanup-Image /StartComponentCleanup
    %_DISM% /Quiet /Image:%~1 /Cleanup-Image /StartComponentCleanup
)
for /f %%a in ('dir %~1\Windows\WinSxS /ad /b ^| find /c /v ""') do set "after_count=%%a"
echo WinSxS cleanup result: %before_count% -^> %after_count%
goto :eof

:final
rd %Mount%
if exist %Mount% (%_DISM% /Quiet /Cleanup-Mountpoints & rd %Mount%)
pushd "%~dp0"
echo Export %UPD%_u.wim
for /l %%a in (1,1,5) do %_DISM% /Quiet /Export-Image /SourceImageFile:%UPD%_org.wim /SourceIndex:%%a /DestinationImageFile:%UPD%_u.wim
for /l %%a in (1,1,5) do %_DISM% /Quiet /Export-Image /SourceImageFile:%UPD%.wim /SourceIndex:%%a /DestinationImageFile:%UPD%_u.wim
move /y %UPD%_org.wim %UPD%.wim >nul
set VAR=LCU%LCUTOTAL%
call set "updmum=%%%VAR%%%\update.mum"
for /f "delims=" %%# in ('powershell -nop -c "(Get-Item \"%updmum%\").LastWriteTime.ToString(\"MM/dd/yyyy HH:mm:00\")"') do set "isodate=%%#"
for /f "delims=" %%# in ('powershell -nop -c "$v=([xml](Get-Content \"%updmum%\")).assembly.package.customInformation.Version;($v -split '\.')[2,3] -join '.'"') do set "isover=%%#"
echo.
echo %isover%
echo %isodate%
echo %isover%>%UPD%.txt
echo %isodate%>>%UPD%.txt
echo.
popd
pause >nul
goto :end

:end
