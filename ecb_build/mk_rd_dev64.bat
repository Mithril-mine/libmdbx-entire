@echo off
setlocal

:: 1. Сохраняем аргумент в уникальную переменную MY_CONFIG
set "MY_CONFIG=%~1"

:: 2. Выбор конфигурации
if "%MY_CONFIG%"=="" goto :DO_RELEASE
if /i "%MY_CONFIG%"=="release" goto :DO_RELEASE
if /i "%MY_CONFIG%"=="debug" goto :DO_DEBUG
goto :DO_RELEASE

:DO_DEBUG
set "BUILD_TYPE=Debug"
set "COMPILER_FLAGS=-O0 -g -fno-inline -D_DEBUG"
goto :MAIN_BUILD

:DO_RELEASE
set "BUILD_TYPE=Release"
set "COMPILER_FLAGS=-O3 -finline-functions -DNDEBUG"
goto :MAIN_BUILD

:MAIN_BUILD
echo ====================================
echo Building Win64 Configuration: %BUILD_TYPE% (devel, non-amalgamated, alloy.c)
echo Flags: %COMPILER_FLAGS%
echo ====================================

:: Батник лежит в PRJDIR\ecb_build, поэтому PRJDIR вычисляется динамически
for %%I in ("%~dp0..") do set "PRJDIR=%%~fI"
SET "SRCDIR=%PRJDIR%\src"
SET "OUTDIR=%PRJDIR%\OUT_devel\Win64\%BUILD_TYPE%"

SET "BCBENV64=C:\Program Files (x86)\Embarcadero\Studio\37.0\bin64\rsvars64.bat"
SET "COMPILER=C:\Program Files (x86)\Embarcadero\Studio\37.0\bin64\bcc64x.exe"
SET "LLVM_LIB=C:\Program Files (x86)\Embarcadero\Studio\37.0\bin64\llvm-lib.exe"

if not exist "%OUTDIR%\TEMP" mkdir "%OUTDIR%\TEMP"
if not exist "%OUTDIR%\LIB" mkdir "%OUTDIR%\LIB"

cd /d "%PRJDIR%"
call "%BCBENV64%"
del /f /q "%OUTDIR%\TEMP\*.o" "%OUTDIR%\LIB\mdbx.lib" 2>nul

:: --- Генерация src\version.c (замена CMake configure_file из version.c.in) ---
:: alloy.c делает #include "version.c" относительно своей папки (src),
:: поэтому файл должен физически лежать в src, а не в OUTDIR.
set "MJ=0"
set "MN=14"
for /f "tokens=3" %%v in ('findstr /C:"#define MDBX_VERSION_MAJOR " "%PRJDIR%\mdbx.h"') do set "MJ=%%v"
for /f "tokens=3" %%v in ('findstr /C:"#define MDBX_VERSION_MINOR " "%PRJDIR%\mdbx.h"') do set "MN=%%v"

set "GIT_COMMIT=unknown"
set "GIT_TIMESTAMP=unknown"
set "GIT_DESCRIBE=unknown"
where git >nul 2>nul
if not errorlevel 1 (
    pushd "%PRJDIR%"
    for /f "delims=" %%g in ('git rev-parse HEAD 2^>nul') do set "GIT_COMMIT=%%g"
    for /f "delims=" %%g in ('git log -1 --format=%%cI 2^>nul') do set "GIT_TIMESTAMP=%%g"
    for /f "delims=" %%g in ('git describe --tags --long 2^>nul') do set "GIT_DESCRIBE=%%g"
    popd
)

(
echo #include "internals.h"
echo.
echo static const char sourcery[] = "ecb_build_devel";
echo.
echo __dll_export const struct MDBX_version_info mdbx_version = {
echo     %MJ%, %MN%, 0, 0,
echo     "",
echo     {"%GIT_TIMESTAMP%", "%GIT_COMMIT%", "%GIT_COMMIT%", "%GIT_DESCRIBE%"},
echo     sourcery};
echo.
echo __dll_export const char *const mdbx_sourcery_anchor = sourcery;
) > "%SRCDIR%\version.c"

@echo on
:: Компиляция alloy.c (официальный unity-build из src, аналог старого mdbx.c). Выходное расширение .o для Clang
"%COMPILER%" -c -I"%PRJDIR%" -I"%SRCDIR%" %COMPILER_FLAGS% ^
-std=c11 ^
-DMDBX_WITHOUT_MSVC_CRT=1 ^
-DMDBX_BUILD_CXX=1 ^
-DMDBX_BUILD_SHARED_LIBRARY=0 ^
-DMDBX_MANUAL_MODULE_HANDLER=0 ^
-DMDBX_BUILD_FLAGS="\"bcc64x Win64 %BUILD_TYPE% devel\"" ^
"%SRCDIR%\alloy.c" -o "%OUTDIR%\TEMP\mdbx.o"

:: Компиляция mdbx.c++ (из src, инклюдит ../mdbx.h++ и корневую папку mdbx++)
"%COMPILER%" -c -I"%PRJDIR%" -I"%SRCDIR%" %COMPILER_FLAGS% ^
-DMDBX_WITHOUT_MSVC_CRT=1 ^
-DMDBX_BUILD_CXX=1 ^
-DMDBX_BUILD_SHARED_LIBRARY=0 ^
-DMDBX_MANUAL_MODULE_HANDLER=0 ^
-DMDBX_BUILD_FLAGS="\"bcc64x Win64 %BUILD_TYPE% devel\"" ^
"%SRCDIR%\mdbx.c++" -o "%OUTDIR%\TEMP\mdbxpp.o"

echo Creating 64-bit library mdbx.lib...
"%LLVM_LIB%" /OUT:"%OUTDIR%\LIB\mdbx.lib" "%OUTDIR%\TEMP\mdbx.o" "%OUTDIR%\TEMP\mdbxpp.o"
