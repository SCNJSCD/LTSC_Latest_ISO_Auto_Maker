@setlocal EnableDelayedExpansion
@echo off & title Update Windows 10 Build 19041 Image
chcp 936 >nul
set "_DISM=DISM.exe"
set "WorkDir=%~dp0"
set "WorkDir=%WorkDir:~0,-1%"
set "Mount=%~1"
set "UPD=19041"
set "UPDPath=%WorkDir%\%UPD%"
set "WIMIMAGE=%WorkDir%\%UPD%"

@REM 手动定义最新更新的 KB 号
set "SSU_=%~2"
set "DNFCU_=%~3"
set "LCU_=%~4"
set "SETUPDU_=%~5"

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
set "_21H2=%UPDPath%\%~1\FILES\KB5003791-%~1"
set "INTEL=%UPDPath%\%~1\FILES\KB5019180-%~1"
set "NETFX3=%UPDPath%\%~1\FILES\NetFx3-%~1"
set "DNF35DU=%UPDPath%\%~1\FILES\KB5007401-%~1"
set "DNF481=%UPDPath%\%~1\FILES\KB5011048-%~1"
set "DNF481CHS=%UPDPath%\%~1\FILES\KB5011050-%~1"
for /l %%a in (%~2,2,10) do (
    if not exist "%Mount%\%%a" md "%Mount%\%%a"
    echo %_DISM% /Quiet /Mount-Wim /WimFile:%WIMIMAGE%.wim /Index:%%a /MountDir:%Mount%\%%a
    %_DISM% /Quiet /Mount-Wim /WimFile:%WIMIMAGE%.wim /Index:%%a /MountDir:%Mount%\%%a
    if exist %Mount%\%%a\Windows\regedit.exe (
        if exist %Mount%\%%a\Windows\explorer.exe call :AddESU "%Mount%\%%a" >nul 2>nul
        call :addpkg %Mount%\%%a %SSU%
        call :addpkg %Mount%\%%a %_21H2%
        call :addpkg %Mount%\%%a %INTEL%
        call :addpkg %Mount%\%%a %LCU%
        if exist %Mount%\%%a\Windows\explorer.exe (
            echo %_DISM% /Quiet /Image:%Mount%\%%a /Set-Edition:IoTEnterpriseS
            %_DISM% /Quiet /Image:%Mount%\%%a /Set-Edition:IoTEnterpriseS
            if exist %Mount%\%%a\Windows\EnterpriseS.xml del /f /q %Mount%\%%a\Windows\EnterpriseS.xml
            call :addpkg %Mount%\%%a %DNF35DU%
            call :addpkg %Mount%\%%a %DNF481%
            call :addpkg %Mount%\%%a %DNF481CHS%
            call :addpkg %Mount%\%%a %DNFCU%
            call :cleanimg %Mount%\%%a
            call :RemoveEdge_CBS "%Mount%\%%a"
            call :addpkg %Mount%\%%a %NETFX3%
            call :addpkg2 %Mount%\%%a %DNFCU% %LCU%
            if not exist %Mount%\%%a\Windows\Setup\Scripts md %Mount%\%%a\Windows\Setup\Scripts
            (
                echo @echo off
                echo DISM.exe /Online /Cleanup-Image /StartComponentCleanup
                echo del /f /q "%%~0"
            )>%Mount%\%%a\Windows\Setup\Scripts\SetupComplete.cmd
        ) else (
            call :cleanimg %Mount%\%%a RB
        )
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
    copy /y %Mount%\%b2%\Windows\Boot\EFI\bootmgr.efi %Mount%\%~2 >nul
    copy /y %Mount%\%b2%\Windows\Boot\DVD\EFI\en-US\efisys.bin %Mount%\%~2\efi\microsoft\boot >nul
    copy /y %Mount%\%b2%\Windows\Boot\DVD\EFI\en-US\efisys_noprompt.bin %Mount%\%~2\efi\microsoft\boot >nul
    copy /y %Mount%\%b2%\Windows\Boot\Fonts\*.ttf %Mount%\%~2\boot\fonts >nul
    copy /y %Mount%\%b2%\Windows\Boot\Fonts\*.ttf %Mount%\%~2\efi\microsoft\boot\fonts >nul
)
(
    echo [EditionID]
    echo IoTEnterpriseS
    echo.
    echo [Channel]
    echo Volume
    echo.
    echo [VL]
    echo 1
)>%Mount%\%~2\sources\ei.cfg

for /l %%a in (%~2,2,10) do (
    if not "%%a"=="%~2" ("%~dp0superUser64.exe" /s /w %WorkDir%\Cleanup.cmd %Mount%\%%a)
    echo %_DISM% /Quiet /Unmount-Wim /MountDir:%Mount%\%%a /Commit
    %_DISM% /Quiet /Unmount-Wim /MountDir:%Mount%\%%a /Commit
    rd %Mount%\%%a
)
goto :eof

:RemoveEdge_CBS
if exist "%~1\Windows\SysWOW64" (
    set "_ARCH2=amd64"
    rd /s /q "%~1\Program Files (x86)\Microsoft"
) else (
    set "_ARCH2=x86"
    rd /s /q "%~1\Program Files\Microsoft"
)
set "_Key=HKLM\TK_SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\Packages\Microsoft-Windows-Internet-Browser-Package~31bf3856ad364e35~%_ARCH2%~~10.0.19041.3758"
reg load HKLM\TK_SOFTWARE "%~1\Windows\System32\config\SOFTWARE" >nul
reg add "%_Key%" /v "Visibility" /d "1" /t REG_DWORD /f >nul
reg add "%_Key%" /v "DefVis" /d "2" /t REG_DWORD /f >nul
reg delete "%_Key%\Owners" /f >nul
reg unload HKLM\TK_SOFTWARE >nul
echo %_DISM% /Quiet /Image:%~1 /Remove-Package /PackageName:Microsoft-Windows-Internet-Browser-Package~31bf3856ad364e35~%_ARCH2%~~10.0.19041.3758
%_DISM% /Quiet /Image:%~1 /Remove-Package /PackageName:Microsoft-Windows-Internet-Browser-Package~31bf3856ad364e35~%_ARCH2%~~10.0.19041.3758
goto :eof

:addpkg
echo %_DISM% /Quiet /Image:%~1 /Add-Package /PackagePath:%~2
%_DISM% /Quiet /Image:%~1 /Add-Package /PackagePath:%~2
goto :eof

:addpkg2
echo %_DISM% /Quiet /Image:%~1 /Add-Package /PackagePath:%~2 /PackagePath:%~3
%_DISM% /Quiet /Image:%~1 /Add-Package /PackagePath:%~2 /PackagePath:%~3
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
for /l %%a in (1,2,10) do %_DISM% /Quiet /Export-Image /SourceImageFile:%UPD%_org.wim /SourceIndex:%%a /DestinationImageFile:%UPD%_u.wim
for /l %%a in (2,2,10) do %_DISM% /Quiet /Export-Image /SourceImageFile:%UPD%_org.wim /SourceIndex:%%a /DestinationImageFile:%UPD%_u.wim
for /l %%a in (1,2,10) do %_DISM% /Quiet /Export-Image /SourceImageFile:%UPD%.wim /SourceIndex:%%a /DestinationImageFile:%UPD%_u.wim
for /l %%a in (2,2,8) do %_DISM% /Quiet /Export-Image /SourceImageFile:%UPD%.wim /SourceIndex:%%a /DestinationImageFile:%UPD%_u.wim
%_DISM% /Quiet /Export-Image /SourceImageFile:%UPD%.wim /SourceIndex:10 /DestinationImageFile:%UPD%_x86_u.wim
wimlib-imagex.exe info %UPD%_u.wim 15 "Windows 10 IoT Enterprise LTSC 2021" "Windows 10 IoT Enterprise LTSC 2021" --image-property FLAGS="IoTEnterpriseS" --image-property DISPLAYNAME="Windows 10 IoT 企业版 LTSC" --image-property DISPLAYDESCRIPTION="Windows 10 IoT 企业版 LTSC" --quiet
wimlib-imagex.exe info %UPD%_x86_u.wim 1 "Windows 10 IoT Enterprise LTSC 2021" "Windows 10 IoT Enterprise LTSC 2021" --image-property FLAGS="IoTEnterpriseS" --image-property DISPLAYNAME="Windows 10 IoT 企业版 LTSC" --image-property DISPLAYDESCRIPTION="Windows 10 IoT 企业版 LTSC" --quiet
%_DISM% /Quiet /Export-Image /SourceImageFile:%UPD%_x86_u.wim /SourceIndex:1 /DestinationImageFile:%UPD%_u.wim
del /f /q %UPD%_x86_u.wim
move /y %UPD%_org.wim %UPD%.wim >nul
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
    set "_EsuFnd=microsoft-w..-foundation_31bf3856ad364e35_10.0.19041.1_9657bd44112a29ec"
) else (
    set "ARCH=x86"
    set "_EsuCom=x86_microsoft-windows-s..edsecurityupdatesai_31bf3856ad364e35_25.10.0.0_none_929b3cf256f3d9ec"
    set "_EsuKey=HKLM\TK_SOFTWARE\Microsoft\Windows\CurrentVersion\SideBySide\Winners\x86_microsoft-windows-s..edsecurityupdatesai_31bf3856ad364e35_none_b1fc22241886bdc0"
    set "_EsuIdt=4D6963726F736F66742D57696E646F77732D53656375726974792D5350502D436F6D706F6E656E742D457874656E64656453656375726974795570646174657341492C2043756C747572653D6E65757472616C2C2056657273696F6E3D32352E31302E302E302C205075626C69634B6579546F6B656E3D333162663338353661643336346533352C2050726F636573736F724172636869746563747572653D7838362C2076657273696F6E53636F70653D4E6F6E537853"
    set "_EsuHsh=E7441D48CB75F658B6CAA663E1983A9EB9B9694BB1B815802E0CA619C156C619"
    set "_EsuFnd=microsoft-w..-foundation_31bf3856ad364e35_10.0.19041.1_3a3921c058ccb8b6"
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

:end
