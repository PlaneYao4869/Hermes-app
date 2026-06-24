@echo off
REM Hermes Gateway QR Code Generator
REM Usage: generate_qr.bat [port] [token]
REM Example: generate_qr.bat 8642 mytoken123

set PORT=%1
set TOKEN=%2
if "%PORT%"=="" set PORT=8642

python "%~dp0generate_qr.py" --port %PORT% %TOKEN_ARG%
if not "%TOKEN%"=="" (
    python "%~dp0generate_qr.py" --port %PORT% --token %TOKEN%
) else (
    python "%~dp0generate_qr.py" --port %PORT%
)
pause
