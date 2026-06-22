@echo off
setlocal EnableExtensions DisableDelayedExpansion
cls

rem ============================================================
rem Folder Encryption / Decryption
rem ============================================================
rem Encrypt or decrypt configured folders with 7-Zip.
rem
rem Author: River Du
rem Date: 2026-06-22
rem Repository: https://github.com/River-Du/folder-encryption
rem
rem Mode rules:
rem - If all available targets are folders, encrypt mode is selected automatically.
rem - If all available targets are .7z archives, decrypt mode is selected automatically.
rem - If both encryptable and decryptable targets exist, choose D / E / Q globally.
rem - In encrypt mode, targets without folders are skipped.
rem - In decrypt mode, targets without archives are skipped.
rem
rem Safety rules:
rem - Every real encrypt/decrypt task first writes the new result into a temp folder.
rem - The temp folder is created beside the target folder:
rem     __target_name_tmp_random
rem - Only after the new result is verified, the old target is removed or replaced.
rem - If a recoverable failure happens, the temp folder is kept for manual recovery.
rem
rem Encoding note:
rem - This file is ASCII-only and should be saved with CRLF line endings.
rem - Do not add non-ASCII characters to this file if Win10 compatibility is important.
rem - No chcp command is needed because all script text is plain ASCII.

rem ============================================================
rem User settings
rem ============================================================

rem TARGETS: folder names or folder paths to process.
rem Do not include the .7z extension here.
rem Examples:
rem set TARGETS="private" "my folder" "D:\Important Files"
set TARGETS="private_1" "private_2" "private_3" "private_4"

rem Delete the source folder after successful encryption.
rem 1 = delete, 0 = keep
set "DELETE_SOURCE_AFTER_ENCRYPT=1"

rem Delete the source archive after successful decryption.
rem 1 = delete, 0 = keep
set "DELETE_ARCHIVE_AFTER_DECRYPT=1"

rem SEVENZIP_EXE: path to 7z.exe or 7za.exe.
rem
rem Recommended: keep it empty and let the script search automatically.
rem Search priority when empty:
rem   1. 7z.exe beside this bat file
rem   2. 7za.exe beside this bat file
rem   3. C:\Program Files\7-Zip\7z.exe
rem   4. C:\Program Files (x86)\7-Zip\7z.exe
rem   5. 7z.exe in PATH
rem   6. 7za.exe in PATH
rem
rem If you set a path manually, the script uses only that path.
rem If the path is invalid, the script stops instead of falling back to auto search.
rem
rem Examples:
rem set "SEVENZIP_EXE="
rem set "SEVENZIP_EXE=C:\Program Files\7-Zip\7z.exe"
set "SEVENZIP_EXE="

rem ============================================================
rem Program
rem ============================================================

title 7Z Folder Encrypt / Decrypt

set "ARCHIVE_EXT=.7z"
set "FINAL_EXIT_CODE=0"

set "TOTAL_COUNT=0"
set "ACTION_COUNT=0"
set "NEED_PASSWORD_COUNT=0"

set "TARGET_ROW_COUNT=0"
set "PLAN_ROW_COUNT=0"
set "RESULT_ROW_COUNT=0"

set "HAS_ENCRYPT_OPTION=0"
set "HAS_DECRYPT_OPTION=0"
set "SELECTED_MODE="

set "FAILED_COUNT=0"
set "ABORTED=0"

set "PASSWORD_READY="
set "PASSWORD_B64="
set "REQUESTED_TARGETS_TEXT="

set "ACTION_TEMP_DIR="
set "PROCESS_NOTE=None"
set "RESULT_SOURCE="
set "RESULT_OUTPUT="

pushd "%~dp0" >nul
if errorlevel 1 (
    echo [ERROR] Cannot enter the bat file directory:
    call :PRINT_VALUE "%~dp0"
    set "FINAL_EXIT_CODE=1"
    goto :END
)
set "DID_PUSHD=1"

echo.
echo 7-Zip Folder Encrypt / Decrypt
echo.

call :FIND_7Z
if errorlevel 1 (
    set "FINAL_EXIT_CODE=1"
    goto :FINISH
)

echo [INFO] Using 7-Zip:
call :PRINT_VALUE "%SEVENZIP_EXE%"
echo.

for %%F in (%TARGETS%) do (
    call :SCAN_TARGET "%%~F"
)

if defined REQUESTED_TARGETS_TEXT (
    echo Targets: "%REQUESTED_TARGETS_TEXT%"
    echo.
)

echo [Found files]
call :PRINT_TABLE "TARGET_ROW" "%TARGET_ROW_COUNT%" "File|Location" "LABEL|PATH"
echo.

call :RESOLVE_GLOBAL_MODE
if "%ABORTED%"=="1" (
    set "FINAL_EXIT_CODE=2"
    goto :FINISH
)

for /l %%N in (1,1,%TOTAL_COUNT%) do (
    call :ADD_SELECTED_PLAN %%N
)

echo.
echo [Plan]
call :PRINT_TABLE "PLAN_ROW" "%PLAN_ROW_COUNT%" "Target|Action|Source|Output" "TARGET|ACTION|SOURCE|OUTPUT"

if "%NEED_PASSWORD_COUNT%"=="0" goto :HANDLE_ACTIONS

call :READ_PASSWORD
if errorlevel 1 (
    set "FINAL_EXIT_CODE=2"
    set "ABORTED=1"
    goto :FINISH
)

:HANDLE_ACTIONS
for /l %%N in (1,1,%ACTION_COUNT%) do (
    call :HANDLE_PLAN %%N
)

goto :FINISH


rem ============================================================
rem Find 7-Zip
rem ============================================================
:FIND_7Z
if not defined SEVENZIP_EXE goto :FIND_7Z_AUTO

set "SEVENZIP_EXE=%SEVENZIP_EXE:"=%"
call :USE_7Z_PATH "%SEVENZIP_EXE%"
if errorlevel 1 (
    echo [ERROR] SEVENZIP_EXE does not exist or is not a file:
    call :PRINT_VALUE "%SEVENZIP_EXE%"
    exit /b 1
)

exit /b 0


:FIND_7Z_AUTO
call :USE_7Z_PATH "%~dp07z.exe"
if not errorlevel 1 exit /b 0

call :USE_7Z_PATH "%~dp07za.exe"
if not errorlevel 1 exit /b 0

call :USE_7Z_PATH "%ProgramFiles%\7-Zip\7z.exe"
if not errorlevel 1 exit /b 0

call :USE_7Z_PATH "%ProgramFiles(x86)%\7-Zip\7z.exe"
if not errorlevel 1 exit /b 0

for /f "delims=" %%Z in ('where 7z.exe 2^>nul') do (
    call :USE_7Z_PATH "%%~fZ"
    if not errorlevel 1 exit /b 0
)

for /f "delims=" %%Z in ('where 7za.exe 2^>nul') do (
    call :USE_7Z_PATH "%%~fZ"
    if not errorlevel 1 exit /b 0
)

echo [ERROR] 7-Zip command-line tool was not found.
echo Put 7z.exe or 7za.exe beside this bat file, or set SEVENZIP_EXE.
exit /b 1


:USE_7Z_PATH
set "CANDIDATE_7Z=%~1"

if not defined CANDIDATE_7Z exit /b 1
if not exist "%CANDIDATE_7Z%" exit /b 1
if exist "%CANDIDATE_7Z%\" exit /b 1

for %%Z in ("%CANDIDATE_7Z%") do set "SEVENZIP_EXE=%%~fZ"
exit /b 0


rem ============================================================
rem Scan targets
rem ============================================================
:SCAN_TARGET
set /a TOTAL_COUNT+=1
set "RAW_TARGET=%~1"

call :NORMALIZE_TARGET "%RAW_TARGET%"

if defined REQUESTED_TARGETS_TEXT (
    set "REQUESTED_TARGETS_TEXT=%REQUESTED_TARGETS_TEXT%, %TARGET_NAME%"
) else (
    set "REQUESTED_TARGETS_TEXT=%TARGET_NAME%"
)

set "HAS_FOLDER=0"
set "HAS_ARCHIVE=0"
set "HAS_TARGET_FILE=0"
set "HAS_ARCHIVE_DIR=0"

if "%TARGET_VALID%"=="0" (
    call :ADD_TARGET_ROW "%TARGET_NAME%" "%TARGET_INVALID_REASON%"
    goto :SCAN_TARGET_SAVE
)

if exist "%TARGET_FOLDER%\" set "HAS_FOLDER=1"
if "%HAS_FOLDER%"=="0" if exist "%TARGET_FOLDER%" set "HAS_TARGET_FILE=1"

if exist "%TARGET_ARCHIVE%\" set "HAS_ARCHIVE_DIR=1"
if "%HAS_ARCHIVE_DIR%"=="0" if exist "%TARGET_ARCHIVE%" set "HAS_ARCHIVE=1"

if "%HAS_FOLDER%"=="1" call :ADD_TARGET_ROW "%TARGET_NAME%/" "%TARGET_FOLDER%"
if "%HAS_TARGET_FILE%"=="1" call :ADD_TARGET_ROW "%TARGET_NAME%" "Same-name file exists; not a folder"
if "%HAS_ARCHIVE%"=="1" call :ADD_TARGET_ROW "%TARGET_NAME%%ARCHIVE_EXT%" "%TARGET_ARCHIVE%"
if "%HAS_ARCHIVE_DIR%"=="1" call :ADD_TARGET_ROW "%TARGET_NAME%%ARCHIVE_EXT%" "Same-name .7z folder exists"

if "%HAS_FOLDER%"=="0" if "%HAS_ARCHIVE%"=="0" if "%HAS_TARGET_FILE%"=="0" if "%HAS_ARCHIVE_DIR%"=="0" (
    call :ADD_TARGET_ROW "%TARGET_NAME%" "No folder or same-name archive found"
)

if "%HAS_FOLDER%"=="1" set "HAS_ENCRYPT_OPTION=1"
if "%HAS_ARCHIVE%"=="1" set "HAS_DECRYPT_OPTION=1"

:SCAN_TARGET_SAVE
set "TARGET_VALID_%TOTAL_COUNT%=%TARGET_VALID%"
set "TARGET_INVALID_REASON_%TOTAL_COUNT%=%TARGET_INVALID_REASON%"
set "TARGET_FOLDER_%TOTAL_COUNT%=%TARGET_FOLDER%"
set "TARGET_ARCHIVE_%TOTAL_COUNT%=%TARGET_ARCHIVE%"
set "TARGET_PARENT_%TOTAL_COUNT%=%TARGET_PARENT%"
set "TARGET_NAME_%TOTAL_COUNT%=%TARGET_NAME%"
set "TARGET_HAS_FOLDER_%TOTAL_COUNT%=%HAS_FOLDER%"
set "TARGET_HAS_ARCHIVE_%TOTAL_COUNT%=%HAS_ARCHIVE%"
set "TARGET_HAS_TARGET_FILE_%TOTAL_COUNT%=%HAS_TARGET_FILE%"
set "TARGET_HAS_ARCHIVE_DIR_%TOTAL_COUNT%=%HAS_ARCHIVE_DIR%"

exit /b 0


:NORMALIZE_TARGET
set "RAW_TARGET=%~1"
set "TARGET_VALID=1"
set "TARGET_INVALID_REASON="
set "TARGET_FOLDER="
set "TARGET_ARCHIVE="
set "TARGET_PARENT="
set "TARGET_NAME="

if not defined RAW_TARGET (
    set "TARGET_VALID=0"
    set "TARGET_NAME=Empty target"
    set "TARGET_INVALID_REASON=Target is empty"
    exit /b 0
)

:STRIP_TARGET_SLASH
if "%RAW_TARGET:~-1%"=="\" (
    if /i not "%RAW_TARGET:~-2%"==":\" (
        set "RAW_TARGET=%RAW_TARGET:~0,-1%"
        goto :STRIP_TARGET_SLASH
    )
)

if "%RAW_TARGET:~-1%"=="/" (
    set "RAW_TARGET=%RAW_TARGET:~0,-1%"
    goto :STRIP_TARGET_SLASH
)

if not defined RAW_TARGET (
    set "TARGET_VALID=0"
    set "TARGET_NAME=Empty target"
    set "TARGET_INVALID_REASON=Target is empty"
    exit /b 0
)

for %%A in ("%RAW_TARGET%") do (
    set "TARGET_FOLDER=%%~fA"
    set "TARGET_PARENT=%%~dpA"
    set "TARGET_NAME=%%~nxA"
)

if not defined TARGET_NAME (
    set "TARGET_VALID=0"
    set "TARGET_NAME=%RAW_TARGET%"
    set "TARGET_INVALID_REASON=Target cannot be a drive root or empty path"
    set "TARGET_FOLDER="
    set "TARGET_ARCHIVE="
    set "TARGET_PARENT="
    exit /b 0
)

if "%TARGET_NAME%"=="." (
    set "TARGET_VALID=0"
    set "TARGET_INVALID_REASON=Target cannot be ."
    exit /b 0
)

if "%TARGET_NAME%"==".." (
    set "TARGET_VALID=0"
    set "TARGET_INVALID_REASON=Target cannot be .."
    exit /b 0
)

set "TARGET_ARCHIVE=%TARGET_FOLDER%%ARCHIVE_EXT%"
exit /b 0


rem ============================================================
rem Resolve global mode
rem ============================================================
:RESOLVE_GLOBAL_MODE
if "%HAS_ENCRYPT_OPTION%"=="1" if "%HAS_DECRYPT_OPTION%"=="1" goto :CHOOSE_GLOBAL_MODE

if "%HAS_ENCRYPT_OPTION%"=="1" (
    set "SELECTED_MODE=ENCRYPT"
    exit /b 0
)

if "%HAS_DECRYPT_OPTION%"=="1" (
    set "SELECTED_MODE=DECRYPT"
    exit /b 0
)

set "SELECTED_MODE=NONE"
exit /b 0


:CHOOSE_GLOBAL_MODE
echo.
echo Choose this run:
echo D Decrypt all targets that have same-name archives
echo E Encrypt all targets that have folders
echo Q Quit
echo.

choice /C DEQ /N /M "Choose D/E/Q: "
set "CHOICE_RET=%ERRORLEVEL%"

if "%CHOICE_RET%"=="3" (
    set "ABORTED=1"
    exit /b 2
)

if "%CHOICE_RET%"=="2" (
    set "SELECTED_MODE=ENCRYPT"
    exit /b 0
)

if "%CHOICE_RET%"=="1" (
    set "SELECTED_MODE=DECRYPT"
    exit /b 0
)

set "ABORTED=1"
exit /b 2


rem ============================================================
rem Target rows
rem ============================================================
:ADD_TARGET_ROW
set /a TARGET_ROW_COUNT+=1
set "TARGET_ROW_LABEL_%TARGET_ROW_COUNT%=%~1"
set "TARGET_ROW_PATH_%TARGET_ROW_COUNT%=%~2"
exit /b 0


rem ============================================================
rem Build plan
rem ============================================================
:ADD_SELECTED_PLAN
set "IDX=%~1"

call set "VALID=%%TARGET_VALID_%IDX%%%"
call set "INVALID_REASON=%%TARGET_INVALID_REASON_%IDX%%%"
call set "FOLDER=%%TARGET_FOLDER_%IDX%%%"
call set "ARCHIVE=%%TARGET_ARCHIVE_%IDX%%%"
call set "PARENT=%%TARGET_PARENT_%IDX%%%"
call set "NAME=%%TARGET_NAME_%IDX%%%"
call set "HAS_FOLDER=%%TARGET_HAS_FOLDER_%IDX%%%"
call set "HAS_ARCHIVE=%%TARGET_HAS_ARCHIVE_%IDX%%%"
call set "HAS_TARGET_FILE=%%TARGET_HAS_TARGET_FILE_%IDX%%%"
call set "HAS_ARCHIVE_DIR=%%TARGET_HAS_ARCHIVE_DIR_%IDX%%%"

if not "%VALID%"=="1" (
    call :ADD_PLAN_ROW "%NAME%" "Skip" "Invalid target" "%INVALID_REASON%"
    call :ADD_PLAN "SKIP" "%FOLDER%" "%ARCHIVE%" "%PARENT%" "%NAME%" "%NAME%" "Skip" "Invalid target" "%INVALID_REASON%"
    exit /b 0
)

if "%SELECTED_MODE%"=="NONE" (
    call :ADD_PLAN_ROW "%NAME%" "Skip" "None" "None"
    call :ADD_PLAN "SKIP" "%FOLDER%" "%ARCHIVE%" "%PARENT%" "%NAME%" "%NAME%" "Skip" "None" "None"
    exit /b 0
)

if "%SELECTED_MODE%"=="ENCRYPT" goto :ADD_PLAN_ENCRYPT_MODE
if "%SELECTED_MODE%"=="DECRYPT" goto :ADD_PLAN_DECRYPT_MODE

call :ADD_PLAN_ROW "%NAME%" "Skip" "None" "None"
call :ADD_PLAN "SKIP" "%FOLDER%" "%ARCHIVE%" "%PARENT%" "%NAME%" "%NAME%" "Skip" "None" "None"
exit /b 0


:ADD_PLAN_ENCRYPT_MODE
if "%HAS_FOLDER%"=="1" goto :ADD_PLAN_ENCRYPT_CHECK_OUTPUT

set "SOURCE_STATE=No folder"
if "%HAS_TARGET_FILE%"=="1" set "SOURCE_STATE=Same-name file"

set "OUTPUT_STATE=No action"
if "%HAS_ARCHIVE%"=="1" set "OUTPUT_STATE=Archive exists"
if "%HAS_ARCHIVE_DIR%"=="1" set "OUTPUT_STATE=.7z folder exists"

call :ADD_PLAN_ROW "%NAME%" "Skip" "%SOURCE_STATE%" "%OUTPUT_STATE%"
call :ADD_PLAN "SKIP" "%FOLDER%" "%ARCHIVE%" "%PARENT%" "%NAME%" "%NAME%" "Skip" "%SOURCE_STATE%" "%OUTPUT_STATE%"
exit /b 0


:ADD_PLAN_ENCRYPT_CHECK_OUTPUT
if "%HAS_ARCHIVE_DIR%"=="1" (
    call :ADD_PLAN_ROW "%NAME%" "Skip" "Keep" ".7z folder exists"
    call :ADD_PLAN "SKIP" "%FOLDER%" "%ARCHIVE%" "%PARENT%" "%NAME%" "%NAME%" "Skip" "Keep" ".7z folder exists"
    exit /b 0
)

goto :ADD_PLAN_ENCRYPT_FOUND


:ADD_PLAN_ENCRYPT_FOUND
set "SOURCE_STATE=Keep"
if "%DELETE_SOURCE_AFTER_ENCRYPT%"=="1" set "SOURCE_STATE=Delete"

set "OUTPUT_STATE=Create"
if "%HAS_ARCHIVE%"=="1" set "OUTPUT_STATE=Replace"

call :ADD_PLAN_ROW "%NAME%" "Encrypt" "%SOURCE_STATE%" "%OUTPUT_STATE%"
call :ADD_PLAN "ENCRYPT" "%FOLDER%" "%ARCHIVE%" "%PARENT%" "%NAME%" "%NAME%" "Encrypt" "%SOURCE_STATE%" "%OUTPUT_STATE%"
exit /b 0


:ADD_PLAN_DECRYPT_MODE
if "%HAS_ARCHIVE%"=="1" goto :ADD_PLAN_DECRYPT_CHECK_OUTPUT

set "SOURCE_STATE=No archive"
if "%HAS_ARCHIVE_DIR%"=="1" set "SOURCE_STATE=.7z is folder"

set "OUTPUT_STATE=No action"
if "%HAS_FOLDER%"=="1" set "OUTPUT_STATE=Folder exists"
if "%HAS_TARGET_FILE%"=="1" set "OUTPUT_STATE=Same-name file"

call :ADD_PLAN_ROW "%NAME%" "Skip" "%SOURCE_STATE%" "%OUTPUT_STATE%"
call :ADD_PLAN "SKIP" "%FOLDER%" "%ARCHIVE%" "%PARENT%" "%NAME%" "%NAME%" "Skip" "%SOURCE_STATE%" "%OUTPUT_STATE%"
exit /b 0


:ADD_PLAN_DECRYPT_CHECK_OUTPUT
if "%HAS_TARGET_FILE%"=="1" (
    call :ADD_PLAN_ROW "%NAME%" "Skip" "Keep" "Same-name file"
    call :ADD_PLAN "SKIP" "%FOLDER%" "%ARCHIVE%" "%PARENT%" "%NAME%" "%NAME%" "Skip" "Keep" "Same-name file"
    exit /b 0
)

goto :ADD_PLAN_DECRYPT_FOUND


:ADD_PLAN_DECRYPT_FOUND
set "SOURCE_STATE=Keep"
if "%DELETE_ARCHIVE_AFTER_DECRYPT%"=="1" set "SOURCE_STATE=Delete"

set "OUTPUT_STATE=Create"
if "%HAS_FOLDER%"=="1" set "OUTPUT_STATE=Replace"

call :ADD_PLAN_ROW "%NAME%" "Decrypt" "%SOURCE_STATE%" "%OUTPUT_STATE%"
call :ADD_PLAN "DECRYPT" "%FOLDER%" "%ARCHIVE%" "%PARENT%" "%NAME%" "%NAME%" "Decrypt" "%SOURCE_STATE%" "%OUTPUT_STATE%"
exit /b 0


rem ============================================================
rem Plan rows
rem ============================================================
:ADD_PLAN_ROW
set /a PLAN_ROW_COUNT+=1
set "PLAN_ROW_TARGET_%PLAN_ROW_COUNT%=%~1"
set "PLAN_ROW_ACTION_%PLAN_ROW_COUNT%=%~2"
set "PLAN_ROW_SOURCE_%PLAN_ROW_COUNT%=%~3"
set "PLAN_ROW_OUTPUT_%PLAN_ROW_COUNT%=%~4"
exit /b 0


:ADD_PLAN
set /a ACTION_COUNT+=1

set "ACTION_%ACTION_COUNT%=%~1"
set "FOLDER_%ACTION_COUNT%=%~2"
set "ARCHIVE_%ACTION_COUNT%=%~3"
set "PARENT_%ACTION_COUNT%=%~4"
set "NAME_%ACTION_COUNT%=%~5"

set "DISPLAY_TARGET_%ACTION_COUNT%=%~6"
set "DISPLAY_ACTION_%ACTION_COUNT%=%~7"
set "DISPLAY_SOURCE_%ACTION_COUNT%=%~8"
set "DISPLAY_OUTPUT_%ACTION_COUNT%=%~9"

if /i not "%~1"=="SKIP" set /a NEED_PASSWORD_COUNT+=1
exit /b 0


rem ============================================================
rem Read password
rem ============================================================
:READ_PASSWORD
if defined PASSWORD_READY exit /b 0

set "PASSWORD_B64="
echo.

if "%SELECTED_MODE%"=="ENCRYPT" (
    set "_PROMPT=Set archive password"
) else (
    set "_PROMPT=Enter archive password"
)

for /f "usebackq delims=" %%P in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "$p=Read-Host $env:_PROMPT -AsSecureString; $b=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($p); try{$s=[Runtime.InteropServices.Marshal]::PtrToStringBSTR($b); if($s.Length -eq 0){exit 2}; [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($s))} finally{if($b -ne [IntPtr]::Zero){[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b)}}"`) do set "PASSWORD_B64=%%P"

set "READ_PASSWORD_RET=%ERRORLEVEL%"
set "_PROMPT="

if not "%READ_PASSWORD_RET%"=="0" (
    echo [ERROR] Password cannot be empty. Task stopped.
    exit /b 1
)

if not defined PASSWORD_B64 (
    echo [ERROR] Failed to read password. Task stopped.
    exit /b 1
)

set "PASSWORD_READY=1"
echo.
exit /b 0


rem ============================================================
rem Object temp folder
rem ============================================================
:MAKE_OBJECT_TEMP_DIR
set "TEMP_OBJECT_NAME=%~1"
set "TEMP_PARENT=%~2"

if not defined TEMP_PARENT set "TEMP_PARENT=%CD%\"
if not "%TEMP_PARENT:~-1%"=="\" set "TEMP_PARENT=%TEMP_PARENT%\"

if not exist "%TEMP_PARENT%" (
    echo [FAIL] Target parent folder does not exist:
    call :PRINT_VALUE "%TEMP_PARENT%"
    call :APPEND_NOTE "Target parent missing"
    exit /b 1
)

:MAKE_OBJECT_TEMP_DIR_AGAIN
set "ACTION_TEMP_DIR=%TEMP_PARENT%__%TEMP_OBJECT_NAME%_tmp_%RANDOM%%RANDOM%"

if exist "%ACTION_TEMP_DIR%\" goto :MAKE_OBJECT_TEMP_DIR_AGAIN
if exist "%ACTION_TEMP_DIR%" goto :MAKE_OBJECT_TEMP_DIR_AGAIN

mkdir "%ACTION_TEMP_DIR%"
if errorlevel 1 (
    echo [FAIL] Cannot create temp folder:
    call :PRINT_VALUE "%ACTION_TEMP_DIR%"
    call :APPEND_NOTE "Temp folder create failed"
    exit /b 1
)

exit /b 0


:CLEAN_TEMP_DIR
set "TMP_DIR_TO_CLEAN=%~1"

if not defined TMP_DIR_TO_CLEAN exit /b 0
if not exist "%TMP_DIR_TO_CLEAN%\" exit /b 0

rmdir /s /q "%TMP_DIR_TO_CLEAN%" >nul 2>nul

if exist "%TMP_DIR_TO_CLEAN%\" (
    echo [INFO] Temp folder cleanup failed. Check it manually:
    call :PRINT_VALUE "%TMP_DIR_TO_CLEAN%"
    call :APPEND_NOTE "Temp folder not cleaned"
)

exit /b 0


:APPEND_NOTE
if "%~1"=="" exit /b 0

if not defined PROCESS_NOTE (
    set "PROCESS_NOTE=%~1"
    exit /b 0
)

if "%PROCESS_NOTE%"=="None" (
    set "PROCESS_NOTE=%~1"
    exit /b 0
)

set "PROCESS_NOTE=%PROCESS_NOTE%; %~1"
exit /b 0


:LOG_STEP
echo(%~1
if not "%~2"=="" call :PRINT_VALUE "%~2"
exit /b 0


:PRINT_VALUE
<nul set /p "_PRINT_VALUE=%~1"
echo.
set "_PRINT_VALUE="
exit /b 0


rem ============================================================
rem Execute plan
rem ============================================================
:HANDLE_PLAN
set "IDX=%~1"

call set "TASK_ACTION=%%ACTION_%IDX%%%"
call set "FOLDER=%%FOLDER_%IDX%%%"
call set "ARCHIVE=%%ARCHIVE_%IDX%%%"
call set "PARENT=%%PARENT_%IDX%%%"
call set "NAME=%%NAME_%IDX%%%"

call set "DISPLAY_TARGET=%%DISPLAY_TARGET_%IDX%%%"
call set "DISPLAY_ACTION=%%DISPLAY_ACTION_%IDX%%%"
call set "DISPLAY_SOURCE=%%DISPLAY_SOURCE_%IDX%%%"
call set "DISPLAY_OUTPUT=%%DISPLAY_OUTPUT_%IDX%%%"

if "%TASK_ACTION%"=="SKIP" (
    call :ADD_RESULT_ROW "%DISPLAY_TARGET%" "%DISPLAY_ACTION%" "%DISPLAY_SOURCE%" "%DISPLAY_OUTPUT%" "SKIP" "No action"
    exit /b 0
)

set "PROCESS_NOTE=None"
set "RESULT_SOURCE=%DISPLAY_SOURCE%"
set "RESULT_OUTPUT=%DISPLAY_OUTPUT%"

call :PROCESS_ACTION
set "PROCESS_RET=%ERRORLEVEL%"

if "%PROCESS_RET%"=="0" (
    call :ADD_RESULT_ROW "%DISPLAY_TARGET%" "%DISPLAY_ACTION%" "%RESULT_SOURCE%" "%RESULT_OUTPUT%" "OK" "%PROCESS_NOTE%"
    exit /b 0
)

call :ADD_RESULT_ROW "%DISPLAY_TARGET%" "%DISPLAY_ACTION%" "%RESULT_SOURCE%" "%RESULT_OUTPUT%" "FAIL" "%PROCESS_NOTE%"
set /a FAILED_COUNT+=1
exit /b 1


:PROCESS_ACTION
if "%TASK_ACTION%"=="ENCRYPT" goto :PROCESS_ENCRYPT
if "%TASK_ACTION%"=="DECRYPT" goto :PROCESS_DECRYPT

echo [FAIL] Unknown task type:
call :PRINT_VALUE "%TASK_ACTION%"
call :APPEND_NOTE "Unknown task type"
set "RESULT_SOURCE=None"
set "RESULT_OUTPUT=None"
exit /b 1


:PROCESS_ENCRYPT
call :DO_ENCRYPT_ONE "%FOLDER%" "%ARCHIVE%" "%PARENT%" "%NAME%"
exit /b %ERRORLEVEL%


:PROCESS_DECRYPT
call :DO_DECRYPT_ONE "%FOLDER%" "%ARCHIVE%" "%PARENT%" "%NAME%"
exit /b %ERRORLEVEL%


rem ============================================================
rem Encrypt one target
rem ============================================================
:DO_ENCRYPT_ONE
set "FOLDER=%~1"
set "ARCHIVE=%~2"
set "PARENT=%~3"
set "NAME=%~4"

if "%DISPLAY_OUTPUT%"=="Replace" (
    set "RESULT_OUTPUT=Not replaced"
) else (
    set "RESULT_OUTPUT=Not created"
)
set "RESULT_SOURCE=Keep"

echo.
call :LOG_STEP "Encrypting:" "%FOLDER%"

if not exist "%FOLDER%\" (
    echo [FAIL] Source folder does not exist.
    call :APPEND_NOTE "Source folder missing"
    exit /b 1
)

if exist "%ARCHIVE%\" (
    echo [FAIL] Archive path is a folder:
    call :PRINT_VALUE "%ARCHIVE%"
    call :APPEND_NOTE ".7z folder exists"
    exit /b 1
)

call :MAKE_OBJECT_TEMP_DIR "%NAME%" "%PARENT%"
if errorlevel 1 exit /b 1

set "TMP_DIR=%ACTION_TEMP_DIR%"
set "TMP_ARCHIVE=%TMP_DIR%\%NAME%%ARCHIVE_EXT%"

call :LOG_STEP "Creating temp archive:" "%TMP_ARCHIVE%"

call :RUN_7Z encrypt "%PARENT%" "%TMP_ARCHIVE%" "%NAME%"
if errorlevel 1 (
    echo [FAIL] Compression failed. Existing files were kept.
    call :APPEND_NOTE "Compression failed"
    call :CLEAN_TEMP_DIR "%TMP_DIR%"
    exit /b 1
)

if not exist "%TMP_ARCHIVE%" (
    echo [FAIL] 7-Zip returned success but the temp archive was not found.
    call :APPEND_NOTE "Temp archive missing"
    call :CLEAN_TEMP_DIR "%TMP_DIR%"
    exit /b 1
)

if exist "%ARCHIVE%" (
    call :LOG_STEP "Deleting old archive:" "%ARCHIVE%"
    del /f /q "%ARCHIVE%"
    if exist "%ARCHIVE%" (
        echo [FAIL] Failed to delete old archive.
        echo [KEEP] New archive remains at:
        call :PRINT_VALUE "%TMP_ARCHIVE%"
        call :APPEND_NOTE "Old archive delete failed; new archive kept"
        exit /b 1
    )
)

call :LOG_STEP "Moving new archive to final location:" "%ARCHIVE%"
move /y "%TMP_ARCHIVE%" "%ARCHIVE%" >nul
if errorlevel 1 (
    echo [FAIL] Failed to move new archive.
    echo [KEEP] New archive remains at:
    call :PRINT_VALUE "%TMP_ARCHIVE%"
    call :APPEND_NOTE "New archive move failed"
    exit /b 1
)

if not exist "%ARCHIVE%" (
    echo [FAIL] Archive was not found after move.
    call :APPEND_NOTE "Archive missing after move"
    exit /b 1
)

set "RESULT_OUTPUT=%DISPLAY_OUTPUT%"

if "%DELETE_SOURCE_AFTER_ENCRYPT%"=="1" (
    call :LOG_STEP "Deleting source folder:" "%FOLDER%"
    rmdir /s /q "%FOLDER%"
    if exist "%FOLDER%\" (
        echo [FAIL] Archive completed, but source folder delete failed.
        set "RESULT_SOURCE=Keep"
        call :APPEND_NOTE "Source folder delete failed"
        call :CLEAN_TEMP_DIR "%TMP_DIR%"
        exit /b 1
    )
    set "RESULT_SOURCE=Delete"
) else (
    set "RESULT_SOURCE=Keep"
)

call :CLEAN_TEMP_DIR "%TMP_DIR%"

echo [DONE]
exit /b 0


rem ============================================================
rem Decrypt one target
rem ============================================================
:DO_DECRYPT_ONE
set "FOLDER=%~1"
set "ARCHIVE=%~2"
set "PARENT=%~3"
set "NAME=%~4"

if "%DISPLAY_OUTPUT%"=="Replace" (
    set "RESULT_OUTPUT=Not replaced"
) else (
    set "RESULT_OUTPUT=Not created"
)
set "RESULT_SOURCE=Keep"

echo.
call :LOG_STEP "Decrypting:" "%ARCHIVE%"

if exist "%ARCHIVE%\" (
    echo [FAIL] Archive path is a folder:
    call :PRINT_VALUE "%ARCHIVE%"
    call :APPEND_NOTE "Archive path is folder"
    exit /b 1
)

if not exist "%ARCHIVE%" (
    echo [FAIL] Archive does not exist.
    call :APPEND_NOTE "Archive missing"
    exit /b 1
)

if exist "%FOLDER%" if not exist "%FOLDER%\" (
    echo [FAIL] Same-name file blocks output folder:
    call :PRINT_VALUE "%FOLDER%"
    call :APPEND_NOTE "Same-name file blocks output"
    exit /b 1
)

call :MAKE_OBJECT_TEMP_DIR "%NAME%" "%PARENT%"
if errorlevel 1 exit /b 1

set "TMP_DIR=%ACTION_TEMP_DIR%"
set "TMP_FOLDER=%TMP_DIR%\%NAME%"

call :LOG_STEP "Extracting temp folder:" "%TMP_FOLDER%"

call :RUN_7Z decrypt "%TMP_DIR%" "%ARCHIVE%" ""
if errorlevel 1 (
    echo [FAIL] Extraction failed. The password may be wrong or the archive may be damaged.
    call :APPEND_NOTE "Extraction failed"
    call :CLEAN_TEMP_DIR "%TMP_DIR%"
    exit /b 1
)

if not exist "%TMP_FOLDER%\" (
    echo [FAIL] Extraction finished, but same-name top folder was not found:
    call :PRINT_VALUE "%TMP_FOLDER%"
    echo [KEEP] Temp extraction remains at:
    call :PRINT_VALUE "%TMP_DIR%"
    call :APPEND_NOTE "Archive has no same-name top folder"
    exit /b 1
)

if exist "%FOLDER%\" (
    call :LOG_STEP "Deleting old folder:" "%FOLDER%"
    rmdir /s /q "%FOLDER%"
    if exist "%FOLDER%\" (
        echo [FAIL] Failed to delete old folder.
        echo [KEEP] New folder remains at:
        call :PRINT_VALUE "%TMP_FOLDER%"
        call :APPEND_NOTE "Old folder delete failed; new folder kept"
        exit /b 1
    )
)

call :LOG_STEP "Moving new folder to final location:" "%FOLDER%"
move /y "%TMP_FOLDER%" "%PARENT%" >nul
if errorlevel 1 (
    echo [FAIL] Failed to move new folder.
    echo [KEEP] New folder remains at:
    call :PRINT_VALUE "%TMP_FOLDER%"
    call :APPEND_NOTE "New folder move failed"
    exit /b 1
)

if not exist "%FOLDER%\" (
    echo [FAIL] Folder was not found after move.
    call :APPEND_NOTE "Folder missing after move"
    exit /b 1
)

set "RESULT_OUTPUT=%DISPLAY_OUTPUT%"

if "%DELETE_ARCHIVE_AFTER_DECRYPT%"=="1" (
    call :LOG_STEP "Deleting archive:" "%ARCHIVE%"
    del /f /q "%ARCHIVE%"
    if exist "%ARCHIVE%" (
        echo [FAIL] Folder completed, but archive delete failed.
        set "RESULT_SOURCE=Keep"
        call :APPEND_NOTE "Archive delete failed"
        call :CLEAN_TEMP_DIR "%TMP_DIR%"
        exit /b 1
    )
    set "RESULT_SOURCE=Delete"
) else (
    set "RESULT_SOURCE=Keep"
)

call :CLEAN_TEMP_DIR "%TMP_DIR%"

echo [DONE]
exit /b 0


rem ============================================================
rem Run 7-Zip
rem %1 = encrypt / decrypt
rem %2 = working folder for encrypt, output folder for decrypt
rem %3 = archive path
rem %4 = folder name for encrypt
rem ============================================================
:RUN_7Z
set "Z_MODE=%~1"
set "Z_WORKDIR=%~2"
set "Z_ARCHIVE=%~3"
set "Z_NAME=%~4"
set "Z_EXE=%SEVENZIP_EXE%"

powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $code=1; try { $pwd=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($env:PASSWORD_B64)); $pflag='-p' + $pwd; if($env:Z_MODE -eq 'encrypt'){ $sevenArgs=@('a','-t7z','-mhe=on','-mx=9','-y','-bso0','-bse0','-bsp0',$pflag,$env:Z_ARCHIVE,'--',($env:Z_NAME + '\')); Push-Location -LiteralPath $env:Z_WORKDIR; try { & $env:Z_EXE @sevenArgs; $code=$LASTEXITCODE } finally { Pop-Location } } else { $sevenArgs=@('x','-y','-bso0','-bse0','-bsp0',$pflag,$env:Z_ARCHIVE,('-o' + $env:Z_WORKDIR)); & $env:Z_EXE @sevenArgs; $code=$LASTEXITCODE } } catch { Write-Error $_; $code=1 }; exit $code"

exit /b %ERRORLEVEL%


rem ============================================================
rem Result rows
rem ============================================================
:ADD_RESULT_ROW
set /a RESULT_ROW_COUNT+=1
set "RESULT_ROW_TARGET_%RESULT_ROW_COUNT%=%~1"
set "RESULT_ROW_ACTION_%RESULT_ROW_COUNT%=%~2"
set "RESULT_ROW_SOURCE_%RESULT_ROW_COUNT%=%~3"
set "RESULT_ROW_OUTPUT_%RESULT_ROW_COUNT%=%~4"
set "RESULT_ROW_RESULT_%RESULT_ROW_COUNT%=%~5"
set "RESULT_ROW_NOTE_%RESULT_ROW_COUNT%=%~6"
exit /b 0


rem ============================================================
rem Print table
rem %1 = variable prefix
rem %2 = row count
rem %3 = headers separated by |
rem %4 = fields separated by |
rem ============================================================
:PRINT_TABLE
set "TABLE_PREFIX=%~1"
set "TABLE_COUNT=%~2"
set "TABLE_HEADERS=%~3"
set "TABLE_FIELDS=%~4"

powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; function W($s){$s=[string]$s;return $s.Length}; function P($s,$w){[string]$s + (' ' * [Math]::Max(0,$w-(W $s)))}; $prefix=$env:TABLE_PREFIX; $count=[int]$env:TABLE_COUNT; $headers=$env:TABLE_HEADERS -split '\|'; $fields=$env:TABLE_FIELDS -split '\|'; if($count -le 0){exit}; $rows=@(); for($i=1;$i -le $count;$i++){ $o=[ordered]@{}; for($c=0;$c -lt $fields.Count;$c++){ $v=[Environment]::GetEnvironmentVariable($prefix + '_' + $fields[$c] + '_' + $i); if($null -eq $v){$v=''}; $o[$headers[$c]]=$v }; $rows += [pscustomobject]$o }; $widths=@(); for($c=0;$c -lt $headers.Count;$c++){ $max=W $headers[$c]; foreach($r in $rows){ $v=$r.PSObject.Properties[$headers[$c]].Value; $w=W $v; if($w -gt $max){$max=$w} }; if($c -lt $headers.Count-1){$max+=2}; $widths += $max }; $line=''; for($c=0;$c -lt $headers.Count;$c++){ if($c -lt $headers.Count-1){$line += P $headers[$c] $widths[$c]}else{$line += $headers[$c]} }; Write-Host $line; $sum=0; foreach($w in $widths){$sum+=$w}; Write-Host ('-' * $sum); foreach($r in $rows){ $line=''; for($c=0;$c -lt $headers.Count;$c++){ $v=$r.PSObject.Properties[$headers[$c]].Value; if($c -lt $headers.Count-1){$line += P $v $widths[$c]}else{$line += [string]$v} }; Write-Host $line }"

exit /b 0


rem ============================================================
rem Finish
rem ============================================================
:FINISH
set "PASSWORD_B64="

if not "%RESULT_ROW_COUNT%"=="0" (
    echo.
    echo [Result]
    call :PRINT_TABLE "RESULT_ROW" "%RESULT_ROW_COUNT%" "Target|Action|Source|Output|Result|Note" "TARGET|ACTION|SOURCE|OUTPUT|RESULT|NOTE"
)

if "%ABORTED%"=="1" (
    set "FINAL_EXIT_CODE=2"
)

if "%FINAL_EXIT_CODE%"=="0" if not "%FAILED_COUNT%"=="0" set "FINAL_EXIT_CODE=1"

goto :END


:END
echo.
echo Press any key to exit...
pause >nul

if defined DID_PUSHD popd >nul
endlocal & exit /b %FINAL_EXIT_CODE%
