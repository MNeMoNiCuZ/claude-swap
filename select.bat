@echo off
setlocal enabledelayedexpansion

rem ===========================================================================
rem  claude2.bat - pick a claude-swap account from a list, then launch Claude
rem                Code as that account in THIS terminal only (`cswap run`).
rem
rem  Usage:
rem    claude2                      list accounts, pick one by number
rem    claude2 2                    skip the menu, launch account 2
rem    claude2 user@example.com     skip the menu, launch by email
rem    claude2 -- --resume          pick from the menu, forward --resume to claude
rem    claude2 2 -- --resume        account 2, forward --resume to claude
rem    claude2 2 --no-share         flags before '--' are passed to `cswap run`
rem
rem  Everything after '--' is handed to claude verbatim. Other terminals and the
rem  VS Code extension keep using your default account.
rem ===========================================================================

rem --- help -------------------------------------------------------------------
if /i "%~1"=="-h"      goto :usage
if /i "%~1"=="--help"  goto :usage
if /i "%~1"=="/?"      goto :usage

rem Prefer the adjacent checkout; a moved script uses the configured location.
set "CSWAP_ROOT=%~dp0"
if not exist "%CSWAP_ROOT%src\claude_swap\cli.py" (
    set "CSWAP_ROOT=C:\AI\LLM\claude-swap\"
    if defined CLAUDE_SWAP_ROOT set "CSWAP_ROOT=!CLAUDE_SWAP_ROOT!\"
)
if not exist "!CSWAP_ROOT!src\claude_swap\cli.py" (
    echo Claude-swap checkout not found. Set CLAUDE_SWAP_ROOT to its folder.
    exit /b 1
)
set "PYTHONPATH=!CSWAP_ROOT!src;%PYTHONPATH%"
set "PYTHONUTF8=1"
set "CSWAP_BIN=cswap.exe"
set "CSWAP_MODULE="
if exist "!CSWAP_ROOT!venv\Scripts\python.exe" (
    set "CSWAP_BIN=!CSWAP_ROOT!venv\Scripts\python.exe"
    set "CSWAP_MODULE=-m claude_swap"
)
if exist "!CSWAP_ROOT!.venv\Scripts\python.exe" (
    set "CSWAP_BIN=!CSWAP_ROOT!.venv\Scripts\python.exe"
    set "CSWAP_MODULE=-m claude_swap"
)

rem --- split args into [account] + [everything else] --------------------------
rem A first argument that does not start with '-' is taken as the account.
set "ACCOUNT="
set "EXTRA="
set "FORWARD_CLAUDE="
set "FIRST=%~1"
if defined FIRST if not "%FIRST:~0,1%"=="-" (
    set "ACCOUNT=%FIRST%"
    shift
)
:collect_args
if "%~1"=="" goto args_done
if defined FORWARD_CLAUDE goto append_arg
if "%~1"=="--" (
    set "FORWARD_CLAUDE=1"
    goto append_arg
)
for %%F in (--no-share --share-history --no-share-history --require-session --debug) do if "%~1"=="%%F" goto append_arg
rem The first Claude argument starts the forwarded tail automatically.
set "EXTRA=!EXTRA! --"
set "FORWARD_CLAUDE=1"
:append_arg
set "EXTRA=!EXTRA! %1"
shift
goto collect_args
:args_done

rem --- no account given: show the menu ----------------------------------------
if defined ACCOUNT goto launch

set "LISTFILE=%TEMP%\claude2-accounts-%RANDOM%%RANDOM%.txt"
echo [claude2] loading accounts...

powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $prefix = @(); if ($env:CSWAP_MODULE) { $prefix = @('-m', 'claude_swap') }; try { $j = (& $env:CSWAP_BIN @prefix --list --json | Out-String | ConvertFrom-Json); if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE } } catch { [Console]::Error.WriteLine('cswap --list failed: ' + $_.Exception.Message); exit 1 }; if ($j.error) { [Console]::Error.WriteLine($j.error.type + ': ' + $j.error.message); exit 1 }; foreach ($a in $j.accounts) { $t = $a.email; if ($a.active) { $t += '  [default]' }; if ($a.usage.fiveHour) { $t += ('  5h ' + [int]$a.usage.fiveHour.pct + '%%') }; if ($a.usage.sevenDay) { $t += ('  7d ' + [int]$a.usage.sevenDay.pct + '%%') }; if ($a.usageStatus -ne 'ok') { $t += ('  (' + $a.usageStatus + ')') }; Write-Output ([string]$a.number + '|' + $t) }" > "%LISTFILE%"
if errorlevel 1 (
    del "%LISTFILE%" >nul 2>&1
    call :maybe_pause
    exit /b 1
)

set "COUNT=0"
echo.
echo   Accounts:
for /f "usebackq tokens=1,* delims=|" %%A in ("%LISTFILE%") do (
    echo     %%A^)  %%B
    set "OK_%%A=1"
    set /a COUNT+=1
)
del "%LISTFILE%" >nul 2>&1
echo.

if !COUNT! EQU 0 (
    echo [claude2] no accounts stored yet. Add one with:  cswap --add-account
    call :maybe_pause
    exit /b 1
)

set "CHOICE="
set /p "CHOICE=  Launch which account? (number or email, blank to cancel): "
rem trim surrounding whitespace so " 2" and "2 " still match
for /f "tokens=* delims= " %%V in ("!CHOICE!") do set "CHOICE=%%V"
:trim_tail
if defined CHOICE if "!CHOICE:~-1!"==" " (
    set "CHOICE=!CHOICE:~0,-1!"
    goto trim_tail
)
if not defined CHOICE (
    echo [claude2] cancelled.
    exit /b 130
)
if defined OK_!CHOICE! goto choice_ok
echo !CHOICE! | findstr /c:"@" >nul
if errorlevel 1 (
    echo [claude2] "!CHOICE!" is not one of the listed accounts.
    call :maybe_pause
    exit /b 1
)
:choice_ok
set "ACCOUNT=!CHOICE!"

rem --- launch -----------------------------------------------------------------
:launch
echo.
echo [claude2] cswap run !ACCOUNT!!EXTRA!
call "%CSWAP_BIN%" %CSWAP_MODULE% run "!ACCOUNT!"!EXTRA!
set "RC=!errorlevel!"
call :maybe_pause
exit /b !RC!

rem --- helpers ----------------------------------------------------------------
:usage
echo claude2 - launch Claude Code as a claude-swap account, in this terminal only.
echo.
echo   claude2                      list accounts, pick one by number
echo   claude2 2                    skip the menu, launch account 2
echo   claude2 user@example.com     skip the menu, launch by email
echo   claude2 -- --resume          pick from the menu, forward --resume to claude
echo   claude2 2 -- --resume        account 2, forward --resume to claude
echo   claude2 2 --no-share         flags before '--' are passed to `cswap run`
echo.
echo Everything after '--' is forwarded to claude verbatim.
exit /b 0

rem Pause only when the window was opened just for this script (double-click),
rem so error messages don't vanish - but stay quiet inside a real terminal.
:maybe_pause
echo %cmdcmdline% | find /i "%~nx0" >nul && pause
goto :eof
