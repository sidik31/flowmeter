@echo off
setlocal

rem Uji baca DEBIT Modbus RTU (read-only). Tidak pernah menulis register.
rem Pemakaian:
rem   tes-modbus-com3.cmd [PORT] [SLAVE_ID] [FUNCTION] [REGISTER] [JUMLAH_REGISTER]
rem Bawaan: COM3, slave 5, function 03, register 6, 2 register.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tes-modbus-com3.ps1" %*
set "MB_EXIT=%ERRORLEVEL%"

echo.
if not "%MB_EXIT%"=="0" echo GAGAL: tidak dapat membaca respons Modbus. Lihat pesan di atas.
pause
exit /b %MB_EXIT%
