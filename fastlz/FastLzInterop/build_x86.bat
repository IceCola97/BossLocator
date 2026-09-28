@echo off
rem ---------------------------------------------------------------
rem  Rebuild fastlz.dll for x86 (32-bit).
rem  Reason: the bundled lua51.dll is 32-bit LuaJIT, while the
rem  provided fastlz.dll is 64-bit; a single process cannot load
rem  both. We compile the same build\fastlz.c source to 32-bit so
rem  the C# program can P/Invoke both DLLs from one process.
rem ---------------------------------------------------------------
setlocal

set "NATIVE=%~dp0native"
set "SRC=%~dp0..\build\fastlz.c"
set "DEF=%~dp0..\build\fastlz.def"
set "VSROOT=D:\ClsIDE\VisualStudio\2026\Community"

if not exist "%NATIVE%\obj" mkdir "%NATIVE%\obj"

call "%VSROOT%\VC\Auxiliary\Build\vcvarsall.bat" x86
if errorlevel 1 (
  echo [ERROR] vcvarsall.bat x86 failed
  exit /b 1
)

cl /nologo /O2 /LD /W3 /D_CRT_SECURE_NO_WARNINGS ^
   "%SRC%" ^
   /Fo"%NATIVE%\obj\\" ^
   /Fe"%NATIVE%\fastlz_x86.dll" ^
   /link /DEF:"%DEF%" /MACHINE:X86

set RC=%errorlevel%
if exist "%NATIVE%\fastlz_x86.exp" del "%NATIVE%\fastlz_x86.exp"
if exist "%NATIVE%\fastlz_x86.lib" del "%NATIVE%\fastlz_x86.lib"
exit /b %RC%
