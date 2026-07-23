@echo off
if "%~1"=="" exit /b
set "_Mount=%~1"
call :Clean >nul 2>nul
exit /b

:Clean
attrib -s -h -a "%_Mount%\Users\Administrator\AppData\Local\IconCache.db" & del /f /q "%_Mount%\Users\Administrator\AppData\Local\IconCache.db"
del /f /q "%_Mount%\Users\Administrator\AppData\Local\Microsoft\Windows Mail\*.log"
del /f /q "%_Mount%\Windows\inf\*.pnf"
del /f /q "%_Mount%\Windows\ServiceProfiles\LocalService\AppData\Local\FontCache*.dat"
del /f /q "%_Mount%\Windows\System32\fntcache.dat"
del /f /q "%_Mount%\Windows\WinSxS\Backup\*"
del /f /q "%_Mount%\Windows\WinSxS\ManifestCache\*.bin"
del /f /q "%_Mount%\Windows\WinSxS\Temp\PendingDeletes\*"
del /f /q "%_Mount%\Windows\WinSxS\Temp\TransformerRollbackData\*"
del /f /q /s "%_Mount%\Users\Administrator\AppData\Local\Microsoft\Windows\Explorer\*"
del /f /q /s "%_Mount%\Users\Administrator\AppData\Local\Temp\*"
del /f /q /s "%_Mount%\Windows\CbsTemp\*"
del /f /q /s "%_Mount%\Windows\Microsoft.NET\*.log"
del /f /q /s "%_Mount%\Windows\rescache\*"
del /f /q /s "%_Mount%\Windows\security\logs\*"
del /f /q /s "%_Mount%\Windows\System32\LogFiles\*"
for /f %%a in ('dir /b /ad "%_Mount%\Windows\assembly"^| find /i "NativeImages"') do rd /s /q "%_Mount%\Windows\assembly\%%a"
rd /s /q "%_Mount%\$Recycle.Bin"
rd /s /q "%_Mount%\PerfLogs"
for %%a in (
    Windows
    Windows\Performance\WinSAT
    Windows\ServiceProfiles\LocalService\AppData\Local\Microsoft\Windows
    Windows\System32
    Windows\System32\catroot2
    Windows\System32\wbem\Logs
) do del /f /q "%_Mount%\%%a\*.log"
for %%a in (
    Users\Default
    Users\Administrator
    Users\Administrator\AppData\Local\Microsoft\Windows
    Windows\System32\config
    Windows\System32\config\systemprofile
    Windows\System32\SMI\Store\Machine
    Windows\ServiceProfiles\LocalService
    Windows\ServiceProfiles\NetworkService
) do (
    attrib -s -h -a "%_Mount%\%%a\*.LOG*" & del /f /q "%_Mount%\%%a\*.LOG*"
    attrib -s -h -a "%_Mount%\%%a\*.TM.blf" & del /f /q "%_Mount%\%%a\*.TM.blf"
    attrib -s -h -a "%_Mount%\%%a\*.regtrans-ms" & del /f /q "%_Mount%\%%a\*.regtrans-ms"
)
goto :eof
