@setlocal EnableDelayedExpansion
@echo off & title Update Windows 10 Build 17763 Image
chcp 936 >nul
set "_DISM=DISM.exe"
set "WorkDir=%~dp0"
set "WorkDir=%WorkDir:~0,-1%"
set "Mount=%~1"
set "UPD=17763"
set "UPDPath=%WorkDir%\%UPD%"
set "WIMIMAGE=%WorkDir%\%UPD%"

@REM 手动定义最新更新的 KB 号
set "SSU_=%~2"
set "DNFCU_=%~3"
set "LCU_=%~4"
set "SETUPDU_=%~5"

@REM 此部分用于仅生成更新脚本而无需执行完整流程, 需要使用时解注释即可
@REM -->
@REM pushd %~dp0
@REM call :GenCMDOnly x64
@REM call :GenCMDOnly x86
@REM call :GenInstallCMD x64 amd64
@REM call :GenInstallCMD x86 x86
@REM popd
@REM echo. & echo  仅生成更新脚本已完成 & pause >nul
@REM goto :end
@REM :GenCMDOnly
@REM set "SSU=%UPDPath%\%~1\FILES\%SSU_%-%~1"
@REM set "INTEL=%UPDPath%\%~1\FILES\KB5019181-%~1"
@REM set "NETFX3=%UPDPath%\%~1\FILES\NetFx3-%~1"
@REM set "DNF48=%UPDPath%\%~1\FILES\KB4486153-%~1"
@REM set "DNF48CHS=%UPDPath%\%~1\FILES\KB4486155-%~1"
@REM set "DNFCU=%UPDPath%\%~1\FILES\%DNFCU_%-%~1"
@REM set "LCU=%UPDPath%\%~1\FILES\%LCU_%-%~1"
@REM goto :eof
@REM <--

reg query "HKU\S-1-5-19" >nul 2>nul || (echo. & echo  需要管理员权限, 按任意键退出 & pause >nul & goto :end)
echo %WorkDir%| find " ">nul && (echo. & echo  路径包含空格, 按任意键退出 & pause >nul & goto :end)
if exist %~dp0%UPD%_u.wim (echo. & echo  %UPD%_u.wim 已存在, 按任意键退出 & pause >nul & goto :end)
copy /y %WIMIMAGE%.wim %WIMIMAGE%_org.wim >nul
if not exist %WIMIMAGE%_org.wim (echo. & echo  发生错误, 按任意键退出 & pause >nul & goto :end)
set "StartTime=%TIME%"
call :instupd x64 1
call :instupd x86 2
goto :final

:instupd
set "SSU=%UPDPath%\%~1\FILES\%SSU_%-%~1"
set "DNFCU=%UPDPath%\%~1\FILES\%DNFCU_%-%~1"
set "LCU=%UPDPath%\%~1\FILES\%LCU_%-%~1"
set "SETUPDU=%UPDPath%\%~1\FILES\%SETUPDU_%-%~1"
set "INTEL=%UPDPath%\%~1\FILES\KB5019181-%~1"
set "NETFX3=%UPDPath%\%~1\FILES\NetFx3-%~1"
set "DNF48=%UPDPath%\%~1\FILES\KB4486153-%~1"
set "DNF48CHS=%UPDPath%\%~1\FILES\KB4486155-%~1"
for /l %%a in (%~2,2,10) do (
    if not exist "%Mount%\%%a" md "%Mount%\%%a"
    echo %_DISM% /Quiet /Mount-Wim /WimFile:%WIMIMAGE%.wim /Index:%%a /MountDir:%Mount%\%%a
    %_DISM% /Quiet /Mount-Wim /WimFile:%WIMIMAGE%.wim /Index:%%a /MountDir:%Mount%\%%a
    if exist %Mount%\%%a\Windows\regedit.exe (
        call :addpkg %Mount%\%%a %SSU%
        call :addpkg %Mount%\%%a %INTEL%
        if exist %Mount%\%%a\Windows\explorer.exe (
            call :addpkg %Mount%\%%a %DNF48%
            call :addpkg %Mount%\%%a %DNF48CHS%
            call :addpkg %Mount%\%%a %NETFX3%
            call :addpkg %Mount%\%%a %DNFCU%
        )
        call :addpkg %Mount%\%%a %LCU%
        if not exist %Mount%\%%a\Windows\explorer.exe call :cleanimg %Mount%\%%a RB
    )
)
set /a b2=%~2+4
pushd %SETUPDU%
for /f %%a in ('dir /b /a-d') do copy /y %%a %Mount%\%~2\sources >nul
popd
xcopy /CIDERY %SETUPDU%\replacementmanifests %Mount%\%~2\sources\replacementmanifests >nul
xcopy /CIDRY %SETUPDU% %Mount%\%~2\sources >nul
xcopy /CIDRY %SETUPDU%\zh-cn %Mount%\%~2\sources\zh-cn >nul
xcopy /CIDRY %Mount%\%b2%\sources %Mount%\%~2\sources >nul
xcopy /CIDRY %Mount%\%b2%\sources\zh-cn %Mount%\%~2\sources\zh-cn >nul
del /f /q %Mount%\%~2\sources\background.bmp
del /f /q %Mount%\%~2\sources\xmllite.dll
del /f /q %Mount%\%~2\sources\zh-CN\vofflps_server.rtf
copy /y %Mount%\%b2%\Windows\Boot\PCAT\memtest.exe %Mount%\%~2\boot >nul
copy /y %Mount%\%b2%\Windows\Boot\PCAT\bootmgr %Mount%\%~2 >nul
copy /y %Mount%\%b2%\Windows\Boot\EFI\memtest.efi %Mount%\%~2\efi\microsoft\boot >nul
copy /y %Mount%\%b2%\Windows\Boot\EFI\boot.stl %Mount%\%~2\efi\microsoft\boot >nul
if exist %Mount%\%b2%\Windows\Boot\EFI_EX\*_EX.efi (
    if "%~1"=="x64" copy /y %Mount%\%b2%\Windows\Boot\EFI_EX\bootmgfw_EX.efi %Mount%\%~2\efi\boot\bootx64.efi >nul
    if "%~1"=="x86" copy /y %Mount%\%b2%\Windows\Boot\EFI_EX\bootmgfw_EX.efi %Mount%\%~2\efi\boot\bootia32.efi >nul
    copy /y %Mount%\%b2%\Windows\Boot\EFI_EX\bootmgr_EX.efi %Mount%\%~2\bootmgr.efi >nul
    copy /y %Mount%\%b2%\Windows\Boot\DVD_EX\EFI\en-US\efisys_EX.bin %Mount%\%~2\efi\microsoft\boot\efisys.bin >nul
    copy /y %Mount%\%b2%\Windows\Boot\DVD_EX\EFI\en-US\efisys_noprompt_EX.bin %Mount%\%~2\efi\microsoft\boot\efisys_noprompt.bin >nul
    copy /y %Mount%\%b2%\Windows\Boot\Fonts_EX\*.ttf %Mount%\%~2\boot\fonts >nul
    copy /y %Mount%\%b2%\Windows\Boot\Fonts_EX\*.ttf %Mount%\%~2\efi\microsoft\boot\fonts >nul
    for /f "tokens=1-3 delims=_." %%i in ('dir /b "%Mount%\%~2\boot\fonts\*_EX.ttf"') do move /y %Mount%\%~2\boot\fonts\%%i_%%j_%%k.ttf %Mount%\%~2\boot\fonts\%%i_%%j.ttf >nul
    for /f "tokens=1-3 delims=_." %%i in ('dir /b "%Mount%\%~2\efi\microsoft\boot\fonts\*_EX.ttf"') do move /y %Mount%\%~2\efi\microsoft\boot\fonts\%%i_%%j_%%k.ttf %Mount%\%~2\efi\microsoft\boot\fonts\%%i_%%j.ttf >nul
) else (
    if "%~1"=="x64" copy /y %Mount%\%b2%\Windows\Boot\EFI\bootmgfw.efi %Mount%\%~2\efi\boot\bootx64.efi >nul
    if "%~1"=="x86" copy /y %Mount%\%b2%\Windows\Boot\EFI\bootmgfw.efi %Mount%\%~2\efi\boot\bootia32.efi >nul
    copy /y %Mount%\%b2%\Windows\Boot\EFI\bootmgr.efi %Mount%\%~2\bootmgr.efi >nul
    copy /y %Mount%\%b2%\Windows\Boot\DVD\EFI\en-US\efisys.bin %Mount%\%~2\efi\microsoft\boot >nul
    copy /y %Mount%\%b2%\Windows\Boot\DVD\EFI\en-US\efisys_noprompt.bin %Mount%\%~2\efi\microsoft\boot >nul
    copy /y %Mount%\%b2%\Windows\Boot\Fonts\*.ttf %Mount%\%~2\boot\fonts >nul
    copy /y %Mount%\%b2%\Windows\Boot\Fonts\*.ttf %Mount%\%~2\efi\microsoft\boot\fonts >nul
)
for /l %%a in (%~2,2,10) do (
    if not "%%a"=="%~2" ("%~dp0superUser64.exe" /s /w %WorkDir%\Cleanup.cmd %Mount%\%%a)
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
    echo Repair-WindowsImage -Path '%~1' -StartComponentCleanup -ResetBase ^| Out-Null
    powershell -nop -c "Repair-WindowsImage -Path '%~1' -StartComponentCleanup -ResetBase | Out-Null"
) else (
    echo Repair-WindowsImage -Path '%~1' -StartComponentCleanup ^| Out-Null
    powershell -nop -c "Repair-WindowsImage -Path '%~1' -StartComponentCleanup | Out-Null"
)
for /f %%a in ('dir %~1\Windows\WinSxS /ad /b ^| find /c /v ""') do set "after_count=%%a"
echo WinSxS cleanup result: %before_count% -^> %after_count%
goto :eof

:final
rd %Mount%
if exist %Mount% (%_DISM% /Quiet /Cleanup-Mountpoints & rd %Mount%)
pushd "%~dp0"
echo Export %UPD%_u.wim
for /l %%a in (1,2,10) do %_DISM% /Quiet /Export-Image /SourceImageFile:%UPD%_org.wim /SourceIndex:%%a /DestinationImageFile:%UPD%_u.wim
for /l %%a in (2,2,10) do %_DISM% /Quiet /Export-Image /SourceImageFile:%UPD%_org.wim /SourceIndex:%%a /DestinationImageFile:%UPD%_u.wim
for /l %%a in (1,2,10) do %_DISM% /Quiet /Export-Image /SourceImageFile:%UPD%.wim /SourceIndex:%%a /DestinationImageFile:%UPD%_u.wim
for /l %%a in (2,2,10) do %_DISM% /Quiet /Export-Image /SourceImageFile:%UPD%.wim /SourceIndex:%%a /DestinationImageFile:%UPD%_u.wim
move /y %UPD%_org.wim %UPD%.wim >nul
echo Archive UpdatePack
call :GenInstallCMD x64 amd64
call :GenInstallCMD x86 x86
(
    echo [ExclusionList]
    echo \FILES\%LCU_%-x64\amd64_microsoft-windows-edgechromium_31bf3856ad364e35_10.0.17763.1935_none_4cee4fa62dd79a7e\edge.wim
    echo \FILES\%LCU_%-x86\x86_microsoft-windows-edgechromium_31bf3856ad364e35_10.0.17763.1935_none_f0cfb422757a2948\edge.wim
)>WimScript.ini
wimlib-imagex.exe append %UPD%\x64 %UPD%_u.wim "Windows 10 UpdatePack I x64" --compress=lzx:20 --no-acls --config=WimScript.ini --quiet
wimlib-imagex.exe append %UPD%\x86 %UPD%_u.wim "Windows 10 UpdatePack I x86" --compress=lzx:20 --no-acls --config=WimScript.ini --quiet
del /f /q WimScript.ini
for /f "delims=" %%# in ('powershell -nop -c "$v=([xml](Get-Content \"%LCU%\update.mum\")).assembly.package.customInformation.Version;($v -split '\.')[2,3] -join '.'"') do set "isover=%%#"
for /f "delims=" %%# in ('powershell -nop -c "(Get-Item \"%UPDPath%\x64\FILES\%LCU_%-x64\update.mum\").LastWriteTime.ToString(\"MM/dd/yyyy HH:mm:00\")"') do set "isodate_x64=%%#"
for /f "delims=" %%# in ('powershell -nop -c "(Get-Item \"%UPDPath%\x86\FILES\%LCU_%-x86\update.mum\").LastWriteTime.ToString(\"MM/dd/yyyy HH:mm:00\")"') do set "isodate_x86=%%#"
echo.
echo %isover%
echo %isodate_x64%
echo %isodate_x86%
echo %isover%>%UPD%.txt
echo %isodate_x64%>>%UPD%.txt
echo %isodate_x86%>>%UPD%.txt
echo.
popd
pause >nul
goto :end

:GenInstallCMD
for /f tokens^=4^ delims^=^" %%a in ('type %LCU%\update.mum^| find "Package_for_RollupFix"') do set "LCUVER=%%a"
for /f tokens^=4^ delims^=^" %%a in ('type %SSU%\update.mum^| find "Package_for_ServicingStack"') do set "SSUVER1=%%a"
for /f tokens^=5^ delims^=^"_ %%a in ('type %SSU%\update.mum^| find "Package_for_ServicingStack"') do set "SSUVER2=%%a"
for /f tokens^=4^ delims^=^" %%a in ('type %DNFCU%\update.mum^| find "Package_for_DotNetRollup"') do set "DNFCUVER=%%a"

@REM install_Offline.cmd -->
(
echo @echo off ^& chcp 936 ^>nul
echo title Updates for Windows 10 Build 17763 ^& cd /d "%%WinDir%%\System32"
echo reg query "HKU\S-1-5-19" ^>nul 2^>nul ^|^| ^(echo. ^& echo  错误: 需要管理员权限 ^& pause ^>nul ^& goto :end^)
echo.
echo @REM 在此处设置脱机映像源文件, 索引号, 挂载目录, DISM 的位置
echo set "IMAGE=D:\17763.wim"
echo set "INDEX=1"
echo set "MOUNT=D:\Mount"
echo set "_DISM=DISM.exe"
echo.
echo if not exist "%%IMAGE%%" ^(echo. ^& echo  错误: 指定的脱机映像不存在 ^& pause ^>nul ^& goto :end^)
echo if exist "%%MOUNT%%" ^(rd "%%MOUNT%%" ^>nul 2^>nul ^|^| ^(echo. ^& echo  错误: 挂载目录非空 ^& pause ^>nul ^& goto :end^)^)
echo md "%%MOUNT%%"
echo echo.
echo echo  正在安装映像
echo %%_DISM%% /Quiet /Mount-Wim /WimFile:"%%IMAGE%%" /Index:%%INDEX%% /MountDir:"%%MOUNT%%"
echo.
echo set "TOTAL=7"
echo set "UPDPATH=%%~dp0FILES"
echo set "PKEY=31bf3856ad364e35"
echo set "PKGS=%%MOUNT%%\Windows\servicing\Packages"
echo set "ARCH1=x86" ^& set "ARCH2=x86"
echo if exist "%%MOUNT%%\Windows\SysWOW64" ^(set "ARCH1=x64" ^& set "ARCH2=amd64"^)
echo.
echo call :INSTPKG %SSU_% %SSU_% Package_for_ServicingStack_%SSUVER2%~%%PKEY%%~%%ARCH2%%~~%SSUVER1%
echo call :INSTPKG KB5019181 KB5019181 Package_for_KB5019181~%%PKEY%%~%%ARCH2%%~~17763.4012.1.1
echo call :INSTNETFX3
echo call :INSTPKG KB4486153 KB4486153 Package_for_KB4486153~%%PKEY%%~%%ARCH2%%~~10.0.1.2752
echo call :INSTPKG KB4486155 KB4486155 Package_for_KB4486155~%%PKEY%%~%%ARCH2%%~~10.0.1.2752
echo call :INSTPKG %DNFCU_% %DNFCU_% Package_for_DotNetRollup~%%PKEY%%~%%ARCH2%%~~%DNFCUVER%
echo call :INSTPKG %LCU_% %LCU_% Package_for_RollupFix~%%PKEY%%~%%ARCH2%%~~%LCUVER%
echo.
echo echo.
echo echo  更新整合完成, 按任意键保存并卸载映像
echo pause ^>nul
echo echo.
echo echo  正在保存并卸载映像
echo %%_DISM%% /Quiet /Unmount-Wim /MountDir:"%%MOUNT%%" /Commit
echo rd "%%MOUNT%%"
echo echo.
echo echo  完成, 按任意键退出
echo pause ^>nul
echo goto :end
echo.
echo :INSTPKG
echo set /a COUNT+=^1
echo if exist "%%PKGS%%\%%~3.mum" ^(
echo     echo.
echo     echo  [%%COUNT%%/%%TOTAL%%] %%~2 已安装
echo ^) else ^(
echo     echo.
echo     echo  [%%COUNT%%/%%TOTAL%%] 正在安装 %%~2
echo     %%_DISM%% /Image:"%%MOUNT%%" /Quiet /Add-Package /PackagePath:"%%UPDPATH%%\%%~1-%%ARCH1%%"
echo ^)
echo goto :eof
echo.
echo :INSTNETFX3
echo set /a COUNT+=^1
echo set "NETFX3="
echo %%_DISM%% /English /Image:"%%MOUNT%%" /Get-CapabilityInfo /CapabilityName:NetFX3~~~~ ^| find "State : Install" ^>nul ^&^& set "NETFX3=Enabled"
echo if "%%NETFX3%%"=="Enabled" ^(
echo     echo.
echo     echo  [%%COUNT%%/%%TOTAL%%] .NET Framework 3.5 ^^^(包括 .NET 2.0 和 3.0^^^) 已安装
echo ^) else ^(
echo     echo.
echo     echo  [%%COUNT%%/%%TOTAL%%] 正在安装 .NET Framework 3.5 ^^^(包括 .NET 2.0 和 3.0^^^)
echo     %%_DISM%% /Image:"%%MOUNT%%" /Quiet /Add-Package /PackagePath:"%%UPDPATH%%\NetFx3-%%ARCH1%%"
echo ^)
echo goto :eof
echo.
echo :end
)>%UPD%\%~1\install_Offline.cmd
@REM <-- install_Offline.cmd

@REM install_Online.cmd -->
(
echo @echo off ^& chcp 936 ^>nul
echo title Updates for Windows 10 Build 17763 ^& cd /d "%%WinDir%%\System32"
echo ver ^| find "10.0.17763" ^>nul ^|^| ^(echo. ^& echo  错误: 需要 Windows 10 Build 17763 操作系统 ^& pause ^>nul ^& goto :end^)
echo reg query "HKU\S-1-5-19" ^>nul 2^>nul ^|^| ^(echo. ^& echo  错误: 需要管理员权限 ^& pause ^>nul ^& goto :end^)
echo if exist "%%WinDir%%\WinSxS\pending.xml" ^(echo. ^& echo  错误: 存在挂起的操作, 请手动重新启动计算机 ^& pause ^>nul ^& goto :end^)
echo set "TOTAL=7"
echo set "UPDPATH=%%~dp0FILES"
echo set "PKEY=31bf3856ad364e35"
echo set "PKGS=%%WinDir%%\servicing\Packages"
echo set "_DISM=DISM.exe"
echo set "ARCH1=x86" ^& set "ARCH2=x86"
echo if exist "%%WinDir%%\SysWOW64" ^(set "ARCH1=x64" ^& set "ARCH2=amd64"^)
echo if exist "%%WinDir%%\CompleteStep0" goto :U10_1
echo if exist "%%WinDir%%\CompleteStep1" goto :U10_2
echo echo.
echo echo  即将更新, 按任意键立即重新启动计算机
echo pause ^>nul
echo echo 0 ^>"%%WinDir%%\CompleteStep0"
echo reg query HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer /v AsyncRunOnce ^| find /i "0x0" ^>nul ^|^| ^(reg add HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer /v AsyncRunOnce /t REG_DWORD /d 0 /f ^>nul ^& echo REG_Restore^>"%%WinDir%%\REG_Restore"^)
echo reg add HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce /v Updates_for_10 /t REG_SZ /d "\"%%~0\"" /f ^>nul
echo shutdown /r /t ^0
echo echo.
echo echo  正在等待计算机重新启动
echo pause ^>nul
echo goto :end
echo.
echo :U10_1
echo title Updates for Windows 10 Build 17763 ^(阶段: 1/2^)
echo for /f %%%%a in ^('type "%%WinDir%%\CompleteStep0"'^) do set "COUNT=%%%%a"
echo call :INSTPKG %SSU_% %SSU_% Package_for_ServicingStack_%SSUVER2%~%%PKEY%%~%%ARCH2%%~~%SSUVER1%
echo call :INSTPKG KB5019181 KB5019181 Package_for_KB5019181~%%PKEY%%~%%ARCH2%%~~17763.4012.1.1
echo call :INSTNETFX3
echo call :INSTPKG KB4486153 KB4486153 Package_for_KB4486153~%%PKEY%%~%%ARCH2%%~~10.0.1.2752
echo call :INSTPKG KB4486155 KB4486155 Package_for_KB4486155~%%PKEY%%~%%ARCH2%%~~10.0.1.2752
echo call :INSTPKG %DNFCU_% %DNFCU_% Package_for_DotNetRollup~%%PKEY%%~%%ARCH2%%~~%DNFCUVER%
echo del /f /q "%%WinDir%%\CompleteStep0"
echo echo %%COUNT%% ^>"%%WinDir%%\CompleteStep1"
echo if not defined UpdateExist goto :U10_2
echo reg add HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce /v Updates_for_10 /t REG_SZ /d "\"%%~0\"" /f ^>nul
echo shutdown /r /t ^0
echo echo.
echo echo  正在等待计算机重新启动
echo pause ^>nul
echo goto :end
echo.
echo :U10_2
echo title Updates for Windows 10 Build 17763 ^(阶段: 2/2^)
echo for /f %%%%a in ^('type "%%WinDir%%\CompleteStep1"'^) do set "COUNT=%%%%a"
echo call :INSTPKG %LCU_% %LCU_% Package_for_RollupFix~%%PKEY%%~%%ARCH2%%~~%LCUVER%
echo if exist "%%WinDir%%\REG_Restore" ^(del /f /q "%%WinDir%%\REG_Restore" ^& reg add HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer /v AsyncRunOnce /t REG_DWORD /d 1 /f ^>nul^)
echo del /f /q "%%WinDir%%\CompleteStep1"
echo shutdown /r /t ^0
echo echo.
echo echo  正在等待计算机重新启动
echo pause ^>nul
echo goto :end
echo.
echo :INSTPKG
echo set /a COUNT+=^1
echo if exist "%%PKGS%%\%%~3.mum" ^(
echo     echo.
echo     echo  [%%COUNT%%/%%TOTAL%%] %%~2 已安装
echo ^) else ^(
echo     set "UpdateExist=Yes"
echo     echo.
echo     echo  [%%COUNT%%/%%TOTAL%%] 正在安装 %%~2
echo     %%_DISM%% /Online /Quiet /NoRestart /Add-Package /PackagePath:"%%UPDPATH%%\%%~1-%%ARCH1%%"
echo ^)
echo goto :eof
echo.
echo :INSTNETFX3
echo set /a COUNT+=^1
echo set "NETFX3="
echo %%_DISM%% /English /Online /Get-CapabilityInfo /CapabilityName:NetFX3~~~~ ^| find "State : Install" ^>nul ^&^& set "NETFX3=Enabled"
echo if "%%NETFX3%%"=="Enabled" ^(
echo     echo.
echo     echo  [%%COUNT%%/%%TOTAL%%] .NET Framework 3.5 ^^^(包括 .NET 2.0 和 3.0^^^) 已安装
echo ^) else ^(
echo     set "UpdateExist=Yes"
echo     echo.
echo     echo  [%%COUNT%%/%%TOTAL%%] 正在安装 .NET Framework 3.5 ^^^(包括 .NET 2.0 和 3.0^^^)
echo     %%_DISM%% /Online /Quiet /NoRestart /Add-Package /PackagePath:"%%UPDPATH%%\NetFx3-%%ARCH1%%"
echo ^)
echo goto :eof
echo.
echo :end
)>%UPD%\%~1\install_Online.cmd
@REM <-- install_Online.cmd

@REM install_WinPE.cmd -->
(
echo @echo off ^& chcp 936 ^>nul
echo title Updates for Windows PE 17763 ^& cd /d "%%WinDir%%\System32"
echo reg query "HKU\S-1-5-19" ^>nul 2^>nul ^|^| ^(echo. ^& echo  错误: 需要管理员权限 ^& pause ^>nul ^& goto :end^)
echo.
echo @REM 在此处设置脱机 WinPE / WinRE 映像源文件, 索引号, 挂载目录, DISM 的位置
echo set "IMAGE=D:\boot.wim"
echo set "INDEX=1"
echo set "MOUNT=D:\Mount"
echo set "_DISM=DISM.exe"
echo.
echo :MENU
echo cls
echo echo.
echo echo  [1] 更新当前系统的 WinRE 映像
echo echo.
echo echo  [2] 更新指定的 WinPE / WinRE 脱机映像
echo echo.
echo set /p "CHOOSE=>输入选项并回车: "
echo if "%%CHOOSE%%"=="1" ^(
echo     set "WINRE=Yes"
echo     set "IMAGE=%%WinDir%%\System32\Recovery\WinRE.wim"
echo     set "INDEX=1"
echo     set "MOUNT=%%WinDir%%\Temp\Mount"
echo     goto :UPDWINPE
echo ^)
echo if "%%CHOOSE%%"=="2" ^(
echo     set "WINRE="
echo     goto :UPDWINPE
echo ^)
echo goto :MENU
echo.
echo :UPDWINPE
echo if defined WINRE ^(
echo     ver ^| find "10.0.17763" ^>nul ^|^| ^(echo. ^& echo  错误: 需要 Windows 10 Build 17763 操作系统 ^& pause ^>nul ^& goto :end^)
echo     reagentc /disable ^>nul 2^>nul
echo     if not exist "%%IMAGE%%" ^(
echo         dir "%%IMAGE%%" /ah /b ^| find /i "WinRE.wim" ^>nul ^|^| ^(
echo             reagentc /enable ^>nul 2^>nul
echo             echo.
echo             echo  错误: WinRE 映像不存在
echo             pause ^>nul
echo             goto :end
echo         ^)
echo     ^)
echo     attrib -s -h "%%IMAGE%%" ^>nul
echo ^)
echo if not exist "%%IMAGE%%" ^(echo. ^& echo  错误: 指定的脱机映像不存在 ^& pause ^>nul ^& goto :end^)
echo if exist "%%MOUNT%%" ^(rd "%%MOUNT%%" ^>nul 2^>nul ^|^| ^(echo. ^& echo  错误: 挂载目录非空 ^& pause ^>nul ^& goto :end^)^)
echo md "%%MOUNT%%"
echo echo.
echo echo  正在安装映像
echo %%_DISM%% /Quiet /Mount-Wim /WimFile:"%%IMAGE%%" /Index:%%INDEX%% /MountDir:"%%MOUNT%%"
echo set "TOTAL=3"
echo set "UPDPATH=%%~dp0FILES"
echo set "PKEY=31bf3856ad364e35"
echo set "PKGS=%%MOUNT%%\Windows\servicing\Packages"
echo set "ARCH1=x86" ^& set "ARCH2=x86"
echo if exist "%%MOUNT%%\Windows\SysWOW64" ^(set "ARCH1=x64" ^& set "ARCH2=amd64"^)
echo call :INSTPKG %SSU_% %SSU_% Package_for_ServicingStack_%SSUVER2%~%%PKEY%%~%%ARCH2%%~~%SSUVER1%
echo call :INSTPKG KB5019181 KB5019181 Package_for_KB5019181~%%PKEY%%~%%ARCH2%%~~17763.4012.1.1
echo call :INSTPKG %LCU_% %LCU_% Package_for_RollupFix~%%PKEY%%~%%ARCH2%%~~%LCUVER%
echo echo.
echo echo  正在清理映像
echo %%_DISM%% /Image:"%%MOUNT%%" /Quiet /Cleanup-Image /StartComponentCleanup /ResetBase
echo if not defined WINRE ^(echo. ^& echo  更新整合完成, 按任意键保存并卸载映像 ^& pause ^>nul^)
echo echo.
echo echo  正在保存并卸载映像
echo %%_DISM%% /Quiet /Unmount-Wim /MountDir:"%%MOUNT%%" /Commit
echo rd "%%MOUNT%%"
echo if exist "%%MOUNT%%" ^(echo. ^& echo  错误: 映像更新失败 ^& pause ^>nul ^& goto :end^)
echo if defined WINRE ^(
echo     %%_DISM%% /Export-Image /SourceImageFile:"%%IMAGE%%" /SourceIndex:1 /DestinationImageFile:"%%IMAGE%%.tmp"
echo     move /y "%%IMAGE%%.tmp" "%%IMAGE%%"
echo     attrib +s +h "%%IMAGE%%"
echo     reagentc /enable
echo ^) ^>nul 2^>nul
echo echo.
echo echo  完成, 按任意键退出
echo pause ^>nul
echo goto :end
echo.
echo :INSTPKG
echo set /a COUNT+=^1
echo if exist "%%PKGS%%\%%~3.mum" ^(
echo     echo.
echo     echo  [%%COUNT%%/%%TOTAL%%] %%~2 已安装
echo ^) else ^(
echo     echo.
echo     echo  [%%COUNT%%/%%TOTAL%%] 正在安装 %%~2
echo     %%_DISM%% /Image:"%%MOUNT%%" /Quiet /Add-Package /PackagePath:"%%UPDPATH%%\%%~1-%%ARCH1%%"
echo ^)
echo goto :eof
echo.
echo :end
)>%UPD%\%~1\install_WinPE.cmd
@REM <-- install_WinPE.cmd
goto :eof

:end
