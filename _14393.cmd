@setlocal EnableDelayedExpansion
@echo off & title Update Windows 10 Build 14393 Image
chcp 936 >nul
set "_DISM=DISM.exe"
set "WorkDir=%~dp0"
set "WorkDir=%WorkDir:~0,-1%"
set "Mount=%~1"
set "UPD=14393"
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
@REM set "INTEL=%UPDPath%\%~1\FILES\KB5019182-%~1"
@REM set "NETFX3=%UPDPath%\%~1\FILES\NetFx3-%~1"
@REM set "DNF48=%UPDPath%\%~1\FILES\KB4486129-%~1"
@REM set "DNF48CHS=%UPDPath%\%~1\FILES\KB4486131-%~1"
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
set "SETUPDU1=%UPDPath%\%~1\FILES\KB4039556-%~1"
set "SETUPDU2=%UPDPath%\%~1\FILES\%SETUPDU_%-%~1"
set "INTEL=%UPDPath%\%~1\FILES\KB5019182-%~1"
set "NETFX3=%UPDPath%\%~1\FILES\NetFx3-%~1"
set "DNF48=%UPDPath%\%~1\FILES\KB4486129-%~1"
set "DNF48CHS=%UPDPath%\%~1\FILES\KB4486131-%~1"
for /l %%a in (%~2,2,10) do (
    if not exist "%Mount%\%%a" md "%Mount%\%%a"
    echo %_DISM% /Quiet /Mount-Wim /WimFile:%WIMIMAGE%.wim /Index:%%a /MountDir:%Mount%\%%a
    %_DISM% /Quiet /Mount-Wim /WimFile:%WIMIMAGE%.wim /Index:%%a /MountDir:%Mount%\%%a
    if exist %Mount%\%%a\Windows\regedit.exe (
        if exist %Mount%\%%a\Windows\explorer.exe call :AddESU "%Mount%\%%a" >nul 2>nul
        call :addpkg %Mount%\%%a %SSU%
        call :addpkg %Mount%\%%a %INTEL%
        if exist %Mount%\%%a\Windows\explorer.exe (
            call :addpkg %Mount%\%%a %DNF48%
            call :addpkg %Mount%\%%a %DNF48CHS%
            call :addpkg %Mount%\%%a %DNFCU%
            robocopy %NETFX3% %NETFX3%-Backup /MIR >nul
            call :addpkg %Mount%\%%a %NETFX3%
            rd /s /q %NETFX3%
            ren %NETFX3%-Backup NetFx3-%~1
        )
        call :addpkg %Mount%\%%a %LCU%
        if not exist %Mount%\%%a\Windows\explorer.exe call :cleanimg %Mount%\%%a RB
    )
)
set /a b2=%~2+4
pushd %SETUPDU1%
for /f %%a in ('dir /b /a-d') do copy /y %%a %Mount%\%~2\sources >nul
popd
xcopy /CIDERY %SETUPDU1%\replacementmanifests %Mount%\%~2\sources\replacementmanifests >nul
xcopy /CIDRY %SETUPDU1% %Mount%\%~2\sources >nul
xcopy /CIDRY %SETUPDU1%\zh-cn %Mount%\%~2\sources\zh-cn >nul
pushd %SETUPDU2%
for /f %%a in ('dir /b /a-d') do copy /y %%a %Mount%\%~2\sources >nul
popd
xcopy /CIDERY %SETUPDU2%\replacementmanifests %Mount%\%~2\sources\replacementmanifests >nul
xcopy /CIDRY %SETUPDU2% %Mount%\%~2\sources >nul
xcopy /CIDRY %SETUPDU2%\zh-cn %Mount%\%~2\sources\zh-cn >nul
ren %Mount%\%~2\sources\setupcompat.dll setupcompat.dll.bak
xcopy /CIDRY %Mount%\%b2%\sources %Mount%\%~2\sources >nul
move /y %Mount%\%~2\sources\setupcompat.dll.bak %Mount%\%~2\sources\setupcompat.dll >nul
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
    copy /y %Mount%\%b2%\Windows\Boot\EFI\bootmgr.efi %Mount%\%~2 >nul
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
wimlib-imagex.exe append %UPD%\x64 %UPD%_u.wim "Windows 10 UpdatePack I x64" --compress=LZX:20 --no-acls --quiet
wimlib-imagex.exe append %UPD%\x86 %UPD%_u.wim "Windows 10 UpdatePack I x86" --compress=LZX:20 --no-acls --quiet
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

:AddESU
if exist "%~1\Windows\SysWOW64" (
    set "ARCH=amd64"
    set "_EsuCom=amd64_microsoft-windows-s..edsecurityupdatesai_31bf3856ad364e35_25.10.0.0_none_eeb9d8760f514b22"
    set "_EsuKey=HKLM\TK_SOFTWARE\Microsoft\Windows\CurrentVersion\SideBySide\Winners\amd64_microsoft-windows-s..edsecurityupdatesai_31bf3856ad364e35_none_0e1abda7d0e42ef6"
    set "_EsuIdt=4D6963726F736F66742D57696E646F77732D53656375726974792D5350502D436F6D706F6E656E742D457874656E64656453656375726974795570646174657341492C2043756C747572653D6E65757472616C2C2056657273696F6E3D32352E31302E302E302C205075626C69634B6579546F6B656E3D333162663338353661643336346533352C2050726F636573736F724172636869746563747572653D616D6436342C2076657273696F6E53636F70653D4E6F6E537853"
    set "_EsuHsh=701BF35FBF494A904E9811D1C19977EB976F979C201243AF282A24E49AF73B92"
    set "_EsuFnd=microsoft-w..-foundation_31bf3856ad364e35_10.0.14393.0_0ddb1b3b887f47d8"
) else (
    set "ARCH=x86"
    set "_EsuCom=x86_microsoft-windows-s..edsecurityupdatesai_31bf3856ad364e35_25.10.0.0_none_929b3cf256f3d9ec"
    set "_EsuKey=HKLM\TK_SOFTWARE\Microsoft\Windows\CurrentVersion\SideBySide\Winners\x86_microsoft-windows-s..edsecurityupdatesai_31bf3856ad364e35_none_b1fc22241886bdc0"
    set "_EsuIdt=4D6963726F736F66742D57696E646F77732D53656375726974792D5350502D436F6D706F6E656E742D457874656E64656453656375726974795570646174657341492C2043756C747572653D6E65757472616C2C2056657273696F6E3D32352E31302E302E302C205075626C69634B6579546F6B656E3D333162663338353661643336346533352C2050726F636573736F724172636869746563747572653D7838362C2076657273696F6E53636F70653D4E6F6E537853"
    set "_EsuHsh=E7441D48CB75F658B6CAA663E1983A9EB9B9694BB1B815802E0CA619C156C619"
    set "_EsuFnd=microsoft-w..-foundation_31bf3856ad364e35_10.0.14393.0_b1bc7fb7d021d6a2"
)
if exist "%~1\Windows\WinSxS\Manifests\%_EsuCom%.manifest" goto :eof
(
    echo ^<?xml version="1.0" encoding="UTF-8" standalone="yes"?^>
    echo ^<assembly xmlns="urn:schemas-microsoft-com:asm.v3" manifestVersion="1.0" copyright="Copyright (c) Microsoft Corporation. All Rights Reserved."^>
    echo   ^<assemblyIdentity name="Microsoft-Windows-Security-SPP-Component-ExtendedSecurityUpdatesAI" version="25.10.0.0" processorArchitecture="%ARCH%" language="neutral" buildType="release" publicKeyToken="31bf3856ad364e35" versionScope="nonSxS" /^>
    echo ^</assembly^>
)>"%Temp%\%_EsuCom%.manifest"
icacls "%~1\Windows\WinSxS\Manifests" /save "%Temp%\acl.txt"
takeown /f "%~1\Windows\WinSxS\Manifests" /A
icacls "%~1\Windows\WinSxS\Manifests" /grant:r "*S-1-5-32-544:(OI)(CI)(F)"
move /y "%Temp%\%_EsuCom%.manifest" "%~1\Windows\WinSxS\Manifests"
icacls "%~1\Windows\WinSxS\Manifests" /setowner *S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464
icacls "%~1\Windows\WinSxS" /restore "%Temp%\acl.txt"
del /f /q "%Temp%\acl.txt"
reg load HKLM\TK_SOFTWARE "%~1\Windows\System32\config\SOFTWARE"
reg load HKLM\TK_COMPONENTS "%~1\Windows\System32\config\COMPONENTS"
reg delete "HKLM\TK_COMPONENTS\DerivedData\Components\%_EsuCom%" /f >nul 2>nul
reg add "HKLM\TK_COMPONENTS\DerivedData\Components\%_EsuCom%" /f /v "c^!%_EsuFnd%" /t REG_BINARY /d ""
reg add "HKLM\TK_COMPONENTS\DerivedData\Components\%_EsuCom%" /f /v identity /t REG_BINARY /d "%_EsuIdt%"
reg add "HKLM\TK_COMPONENTS\DerivedData\Components\%_EsuCom%" /f /v S256H /t REG_BINARY /d "%_EsuHsh%"
reg add "HKLM\TK_COMPONENTS\DerivedData\Components\%_EsuCom%" /f /v CF /t REG_DWORD /d "64"
reg add "%_EsuKey%" /f /ve /d 25.10
reg add "%_EsuKey%\25.10" /f /ve /d 25.10.0.0
reg add "%_EsuKey%\25.10" /f /v 25.10.0.0 /t REG_BINARY /d 01
for /f "tokens=* delims=" %%# in ('reg query HKLM\TK_COMPONENTS\DerivedData\VersionedIndex 2^>nul ^| findstr /i VersionedIndex') do reg delete "%%#" /f
reg unload HKLM\TK_SOFTWARE
reg unload HKLM\TK_COMPONENTS
goto :eof

:GenInstallCMD
for /f tokens^=4^ delims^=^" %%a in ('type %LCU%\update.mum^| find "Package_for_RollupFix"') do set "LCUVER=%%a"
for /f tokens^=4^ delims^=^" %%a in ('type %SSU%\update.mum^| find "Package_for_KB"') do set "SSUVER=%%a"
for /f tokens^=4^ delims^=^" %%a in ('type %DNFCU%\update.mum^| find "Package_for_DotNetRollup"') do set "DNFCUVER=%%a"

@REM install_Offline.cmd -->
(
echo @echo off ^& chcp 936 ^>nul
echo title Updates for Windows 10 Build 14393 ^& cd /d "%%WinDir%%\System32"
echo reg query "HKU\S-1-5-19" ^>nul 2^>nul ^|^| ^(echo. ^& echo  错误: 需要管理员权限 ^& pause ^>nul ^& goto :end^)
echo.
echo @REM 在此处设置脱机映像源文件, 索引号, 挂载目录, DISM 的位置
echo set "IMAGE=D:\14393.wim"
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
echo call :AddESU ^>nul 2^>nul
echo.
echo call :INSTPKG %SSU_% %SSU_% Package_for_%SSU_%~%%PKEY%%~%%ARCH2%%~~%SSUVER%
echo call :INSTPKG KB5019182 KB5019182 Package_for_KB5019182~%%PKEY%%~%%ARCH2%%~~14393.5793.1.2
echo call :INSTPKG KB4486129 KB4486129 Package_for_KB4486129~%%PKEY%%~%%ARCH2%%~~10.0.1.2752
echo call :INSTPKG KB4486131 KB4486131 Package_for_KB4486131~%%PKEY%%~%%ARCH2%%~~10.0.1.2752
echo call :INSTPKG %DNFCU_% %DNFCU_% Package_for_DotNetRollup~%%PKEY%%~%%ARCH2%%~~%DNFCUVER%
echo call :INSTNETFX3
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
echo     robocopy "%%UPDPATH%%\NetFx3-%%ARCH1%%" "%%UPDPATH%%\NetFx3-%%ARCH1%%-Backup" /MIR ^>nul
echo     %%_DISM%% /Image:"%%MOUNT%%" /Quiet /Add-Package /PackagePath:"%%UPDPATH%%\NetFx3-%%ARCH1%%"
echo     rd /s /q "%%UPDPATH%%\NetFx3-%%ARCH1%%"
echo     ren "%%UPDPATH%%\NetFx3-%%ARCH1%%-Backup" NetFx3-%%ARCH1%%
echo ^)
echo goto :eof
echo.
echo :AddESU
echo if exist "%%MOUNT%%\Windows\SysWOW64" ^(
echo     set "ARCH=amd64"
echo     set "_EsuCom=amd64_microsoft-windows-s..edsecurityupdatesai_%%PKEY%%_25.10.0.0_none_eeb9d8760f514b22"
echo     set "_EsuKey=HKLM\TK_SOFTWARE\Microsoft\Windows\CurrentVersion\SideBySide\Winners\amd64_microsoft-windows-s..edsecurityupdatesai_%%PKEY%%_none_0e1abda7d0e42ef6"
echo     set "_EsuIdt=4D6963726F736F66742D57696E646F77732D53656375726974792D5350502D436F6D706F6E656E742D457874656E64656453656375726974795570646174657341492C2043756C747572653D6E65757472616C2C2056657273696F6E3D32352E31302E302E302C205075626C69634B6579546F6B656E3D333162663338353661643336346533352C2050726F636573736F724172636869746563747572653D616D6436342C2076657273696F6E53636F70653D4E6F6E537853"
echo     set "_EsuHsh=701BF35FBF494A904E9811D1C19977EB976F979C201243AF282A24E49AF73B92"
echo     set "_EsuFnd=microsoft-w..-foundation_%%PKEY%%_10.0.14393.0_0ddb1b3b887f47d8"
echo ^) else ^(
echo     set "ARCH=x86"
echo     set "_EsuCom=x86_microsoft-windows-s..edsecurityupdatesai_%%PKEY%%_25.10.0.0_none_929b3cf256f3d9ec"
echo     set "_EsuKey=HKLM\TK_SOFTWARE\Microsoft\Windows\CurrentVersion\SideBySide\Winners\x86_microsoft-windows-s..edsecurityupdatesai_%%PKEY%%_none_b1fc22241886bdc0"
echo     set "_EsuIdt=4D6963726F736F66742D57696E646F77732D53656375726974792D5350502D436F6D706F6E656E742D457874656E64656453656375726974795570646174657341492C2043756C747572653D6E65757472616C2C2056657273696F6E3D32352E31302E302E302C205075626C69634B6579546F6B656E3D333162663338353661643336346533352C2050726F636573736F724172636869746563747572653D7838362C2076657273696F6E53636F70653D4E6F6E537853"
echo     set "_EsuHsh=E7441D48CB75F658B6CAA663E1983A9EB9B9694BB1B815802E0CA619C156C619"
echo     set "_EsuFnd=microsoft-w..-foundation_%%PKEY%%_10.0.14393.0_b1bc7fb7d021d6a2"
echo ^)
echo if exist "%%MOUNT%%\Windows\WinSxS\Manifests\%%_EsuCom%%.manifest" goto :eof
echo ^(
echo     echo ^^^<?xml version="1.0" encoding="UTF-8" standalone="yes"?^^^>
echo     echo ^^^<assembly xmlns="urn:schemas-microsoft-com:asm.v3" manifestVersion="1.0" copyright="Copyright (c) Microsoft Corporation. All Rights Reserved."^^^>
echo     echo   ^^^<assemblyIdentity name="Microsoft-Windows-Security-SPP-Component-ExtendedSecurityUpdatesAI" version="25.10.0.0" processorArchitecture="%%ARCH%%" language="neutral" buildType="release" publicKeyToken="%%PKEY%%" versionScope="nonSxS" /^^^>
echo     echo ^^^</assembly^^^>
echo ^)^>"%%Temp%%\%%_EsuCom%%.manifest"
echo icacls "%%MOUNT%%\Windows\WinSxS\Manifests" /save "%%Temp%%\acl.txt"
echo takeown /f "%%MOUNT%%\Windows\WinSxS\Manifests" /A
echo icacls "%%MOUNT%%\Windows\WinSxS\Manifests" /grant:r "*S-1-5-32-544:(OI)(CI)(F)"
echo move /y "%%Temp%%\%%_EsuCom%%.manifest" "%%MOUNT%%\Windows\WinSxS\Manifests"
echo icacls "%%MOUNT%%\Windows\WinSxS\Manifests" /setowner *S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464
echo icacls "%%MOUNT%%\Windows\WinSxS" /restore "%%Temp%%\acl.txt"
echo del /f /q "%%Temp%%\acl.txt"
echo reg load HKLM\TK_SOFTWARE "%%MOUNT%%\Windows\System32\config\SOFTWARE"
echo reg load HKLM\TK_COMPONENTS "%%MOUNT%%\Windows\System32\config\COMPONENTS"
echo reg delete "HKLM\TK_COMPONENTS\DerivedData\Components\%%_EsuCom%%" /f ^>nul 2^>nul
echo reg add "HKLM\TK_COMPONENTS\DerivedData\Components\%%_EsuCom%%" /f /v "c^!%%_EsuFnd%%" /t REG_BINARY /d ""
echo reg add "HKLM\TK_COMPONENTS\DerivedData\Components\%%_EsuCom%%" /f /v identity /t REG_BINARY /d "%%_EsuIdt%%"
echo reg add "HKLM\TK_COMPONENTS\DerivedData\Components\%%_EsuCom%%" /f /v S256H /t REG_BINARY /d "%%_EsuHsh%%"
echo reg add "HKLM\TK_COMPONENTS\DerivedData\Components\%%_EsuCom%%" /f /v CF /t REG_DWORD /d "64"
echo reg add "%%_EsuKey%%" /f /ve /d 25.10
echo reg add "%%_EsuKey%%\25.10" /f /ve /d 25.10.0.0
echo reg add "%%_EsuKey%%\25.10" /f /v 25.10.0.0 /t REG_BINARY /d 01
echo for /f "tokens=* delims=" %%%%# in ^('reg query HKLM\TK_COMPONENTS\DerivedData\VersionedIndex 2^^^>nul ^^^| findstr /i VersionedIndex'^) do reg delete "%%%%#" /f
echo reg unload HKLM\TK_SOFTWARE
echo reg unload HKLM\TK_COMPONENTS
echo goto :eof
echo.
echo :end
)>%UPD%\%~1\install_Offline.cmd
@REM <-- install_Offline.cmd

@REM install_Online.cmd -->
(
echo @echo off ^& chcp 936 ^>nul
echo title Updates for Windows 10 Build 14393 ^& cd /d "%%WinDir%%\System32"
echo ver ^| find "10.0.14393" ^>nul ^|^| ^(echo. ^& echo  错误: 需要 Windows 10 Build 14393 操作系统 ^& pause ^>nul ^& goto :end^)
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
echo title Updates for Windows 10 Build 14393 ^(阶段: 1/2^)
echo for /f %%%%a in ^('type "%%WinDir%%\CompleteStep0"'^) do set "COUNT=%%%%a"
echo call :AddESU ^>nul 2^>nul
echo call :INSTPKG %SSU_% %SSU_% Package_for_%SSU_%~%%PKEY%%~%%ARCH2%%~~%SSUVER%
echo call :INSTPKG KB5019182 KB5019182 Package_for_KB5019182~%%PKEY%%~%%ARCH2%%~~14393.5793.1.2
echo call :INSTNETFX3
echo call :INSTPKG KB4486129 KB4486129 Package_for_KB4486129~%%PKEY%%~%%ARCH2%%~~10.0.1.2752
echo call :INSTPKG KB4486131 KB4486131 Package_for_KB4486131~%%PKEY%%~%%ARCH2%%~~10.0.1.2752
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
echo title Updates for Windows 10 Build 14393 ^(阶段: 2/2^)
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
echo     robocopy "%%UPDPATH%%\NetFx3-%%ARCH1%%" "%%UPDPATH%%\NetFx3-%%ARCH1%%-Backup" /MIR ^>nul
echo     %%_DISM%% /Online /Quiet /NoRestart /Add-Package /PackagePath:"%%UPDPATH%%\NetFx3-%%ARCH1%%"
echo     rd /s /q "%%UPDPATH%%\NetFx3-%%ARCH1%%"
echo     ren "%%UPDPATH%%\NetFx3-%%ARCH1%%-Backup" NetFx3-%%ARCH1%%
echo ^)
echo goto :eof
echo.
echo :AddESU
echo if exist "%%WinDir%%\SysWOW64" ^(
echo     set "ARCH=amd64"
echo     set "_EsuCom=amd64_microsoft-windows-s..edsecurityupdatesai_%%PKEY%%_25.10.0.0_none_eeb9d8760f514b22"
echo     set "_EsuKey=HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\SideBySide\Winners\amd64_microsoft-windows-s..edsecurityupdatesai_%%PKEY%%_none_0e1abda7d0e42ef6"
echo     set "_EsuIdt=4D6963726F736F66742D57696E646F77732D53656375726974792D5350502D436F6D706F6E656E742D457874656E64656453656375726974795570646174657341492C2043756C747572653D6E65757472616C2C2056657273696F6E3D32352E31302E302E302C205075626C69634B6579546F6B656E3D333162663338353661643336346533352C2050726F636573736F724172636869746563747572653D616D6436342C2076657273696F6E53636F70653D4E6F6E537853"
echo     set "_EsuHsh=701BF35FBF494A904E9811D1C19977EB976F979C201243AF282A24E49AF73B92"
echo     set "_EsuFnd=microsoft-w..-foundation_%%PKEY%%_10.0.14393.0_0ddb1b3b887f47d8"
echo ^) else ^(
echo     set "ARCH=x86"
echo     set "_EsuCom=x86_microsoft-windows-s..edsecurityupdatesai_%%PKEY%%_25.10.0.0_none_929b3cf256f3d9ec"
echo     set "_EsuKey=HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\SideBySide\Winners\x86_microsoft-windows-s..edsecurityupdatesai_%%PKEY%%_none_b1fc22241886bdc0"
echo     set "_EsuIdt=4D6963726F736F66742D57696E646F77732D53656375726974792D5350502D436F6D706F6E656E742D457874656E64656453656375726974795570646174657341492C2043756C747572653D6E65757472616C2C2056657273696F6E3D32352E31302E302E302C205075626C69634B6579546F6B656E3D333162663338353661643336346533352C2050726F636573736F724172636869746563747572653D7838362C2076657273696F6E53636F70653D4E6F6E537853"
echo     set "_EsuHsh=E7441D48CB75F658B6CAA663E1983A9EB9B9694BB1B815802E0CA619C156C619"
echo     set "_EsuFnd=microsoft-w..-foundation_%%PKEY%%_10.0.14393.0_b1bc7fb7d021d6a2"
echo ^)
echo if exist "%%WinDir%%\WinSxS\Manifests\%%_EsuCom%%.manifest" goto :eof
echo ^(
echo     echo ^^^<?xml version="1.0" encoding="UTF-8" standalone="yes"?^^^>
echo     echo ^^^<assembly xmlns="urn:schemas-microsoft-com:asm.v3" manifestVersion="1.0" copyright="Copyright (c) Microsoft Corporation. All Rights Reserved."^^^>
echo     echo   ^^^<assemblyIdentity name="Microsoft-Windows-Security-SPP-Component-ExtendedSecurityUpdatesAI" version="25.10.0.0" processorArchitecture="%%ARCH%%" language="neutral" buildType="release" publicKeyToken="%%PKEY%%" versionScope="nonSxS" /^^^>
echo     echo ^^^</assembly^^^>
echo ^)^>"%%Temp%%\%%_EsuCom%%.manifest"
echo icacls "%%WinDir%%\WinSxS\Manifests" /save "%%Temp%%\acl.txt"
echo takeown /f "%%WinDir%%\WinSxS\Manifests" /A
echo icacls "%%WinDir%%\WinSxS\Manifests" /grant:r "*S-1-5-32-544:(OI)(CI)(F)"
echo move /y "%%Temp%%\%%_EsuCom%%.manifest" "%%WinDir%%\WinSxS\Manifests"
echo icacls "%%WinDir%%\WinSxS\Manifests" /setowner *S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464
echo icacls "%%WinDir%%\WinSxS" /restore "%%Temp%%\acl.txt"
echo del /f /q "%%Temp%%\acl.txt"
echo reg query HKLM\COMPONENTS ^>nul 2^>nul ^|^| reg load HKLM\COMPONENTS "%%WinDir%%\System32\config\COMPONENTS"
echo reg delete "HKLM\COMPONENTS\DerivedData\Components\%%_EsuCom%%" /f ^>nul 2^>nul
echo reg add "HKLM\COMPONENTS\DerivedData\Components\%%_EsuCom%%" /f /v "c^!%%_EsuFnd%%" /t REG_BINARY /d ""
echo reg add "HKLM\COMPONENTS\DerivedData\Components\%%_EsuCom%%" /f /v identity /t REG_BINARY /d "%%_EsuIdt%%"
echo reg add "HKLM\COMPONENTS\DerivedData\Components\%%_EsuCom%%" /f /v S256H /t REG_BINARY /d "%%_EsuHsh%%"
echo reg add "HKLM\COMPONENTS\DerivedData\Components\%%_EsuCom%%" /f /v CF /t REG_DWORD /d "64"
echo reg add "%%_EsuKey%%" /f /ve /d 25.10
echo reg add "%%_EsuKey%%\25.10" /f /ve /d 25.10.0.0
echo reg add "%%_EsuKey%%\25.10" /f /v 25.10.0.0 /t REG_BINARY /d 01
echo for /f "tokens=* delims=" %%%%# in ^('reg query HKLM\COMPONENTS\DerivedData\VersionedIndex 2^^^>nul ^^^| findstr /i VersionedIndex'^) do reg delete "%%%%#" /f
echo goto :eof
echo.
echo :end
)>%UPD%\%~1\install_Online.cmd
@REM <-- install_Online.cmd

@REM install_WinPE.cmd -->
(
echo @echo off ^& chcp 936 ^>nul
echo title Updates for Windows PE 14393 ^& cd /d "%%WinDir%%\System32"
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
echo     ver ^| find "10.0.14393" ^>nul ^|^| ^(echo. ^& echo  错误: 需要 Windows 10 Build 14393 操作系统 ^& pause ^>nul ^& goto :end^)
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
echo call :INSTPKG %SSU_% %SSU_% Package_for_%SSU_%~%%PKEY%%~%%ARCH2%%~~%SSUVER%
echo call :INSTPKG KB5019182 KB5019182 Package_for_KB5019182~%%PKEY%%~%%ARCH2%%~~14393.5793.1.2
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
