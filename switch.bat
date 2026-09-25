@echo off
setlocal enabledelayedexpansion
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
if "%~1"=="" (
    call "%CSWAP_BIN%" %CSWAP_MODULE% --switch
) else (
    call "%CSWAP_BIN%" %CSWAP_MODULE% switch %*
)
set "RC=%errorlevel%"
echo %cmdcmdline% | find /i "%~nx0" >nul && pause
exit /b %RC%
