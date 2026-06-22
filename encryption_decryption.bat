@echo off
setlocal EnableExtensions DisableDelayedExpansion
chcp 936 >nul

:: ============================================================
::                         脚本简介
:: ============================================================
:: 使用 7-Zip 命令行程序对指定文件夹进行 .7z 加密压缩或解密解压。
::
:: Author: River Du
:: Data: 2026-06-22
:: Repository: https://github.com/River-Du/folder-encryption
::
:: 功能：
:: - 自动判断模式：
::   - 如果所有可操作目标都是文件夹，则自动进入加密模式；
::   - 如果所有可操作目标都是同名 .7z 压缩包，则自动进入解密模式；
::   - 如果同时存在可加密和可解密目标，则手动选择本轮整体模式；
:: - 支持多目标：可以同时处理多个文件夹或压缩包；
:: - 安全处理：
::   - 加密 / 解密均先在临时目录中生成新结果；
::   - 确认新结果生成成功后，再删除旧目标并移动新结果；
::   - 失败时尽量保留原文件夹、原压缩包或临时生成结果，避免静默丢失；
:: - 自动查找 7-Zip：
::   - 如果不指定 SEVENZIP_EXE，脚本会自动查找可用的 7-Zip 命令行程序。
::
:: 使用建议：
:: - 请先用测试文件夹验证流程；
:: - 不建议把磁盘根目录作为目标；
:: - 请勿在处理过程中手动移动、删除或占用相关文件。

:: ============================================================
::                         用户配置
:: ============================================================

:: TARGETS：要处理的文件夹列表
:: - 支持填写多个文件夹；
:: - 支持相对路径和绝对路径；
:: - 每一项应填写“文件夹路径”，不要填写 .7z 后缀；
:: - 示例：
::   set TARGETS="private" "my folder" "D:\Important Files"
set TARGETS="private_1" "private_2" "private_3" "private_4"

:: DELETE_SOURCE_AFTER_ENCRYPT：加密成功后是否删除原文件夹
:: - 1：删除
:: - 0：保留
set "DELETE_SOURCE_AFTER_ENCRYPT=1"

:: DELETE_ARCHIVE_AFTER_DECRYPT：解密成功后是否删除原压缩包
:: - 1：删除
:: - 0：保留
set "DELETE_ARCHIVE_AFTER_DECRYPT=1"

:: SEVENZIP_EXE：7-Zip 命令行程序路径
:: - 留空时，脚本会自动查找可用的 7-Zip 程序，优先级如下：
::   1. bat 同级目录下的 7z.exe
::   2. bat 同级目录下的 7za.exe
::   3. C:\Program Files\7-Zip\7z.exe
::   4. C:\Program Files (x86)\7-Zip\7z.exe
::   5. PATH 中的 7z.exe
::   6. PATH 中的 7za.exe
:: - 也可以手动指定完整路径，脚本将优先使用该路径；
:: - 示例：
::   set "SEVENZIP_EXE=C:\Program Files\7-Zip\7z.exe"
set "SEVENZIP_EXE="

:: ============================================================
::                         程序区
:: ============================================================

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
set "PROCESS_NOTE=无"
set "RESULT_SOURCE="
set "RESULT_OUTPUT="

pushd "%~dp0" >nul
if errorlevel 1 (
    echo [错误] 无法进入 bat 文件所在目录：
    call :PRINT_VALUE "%~dp0"
    set "FINAL_EXIT_CODE=1"
    goto :END
)
set "DID_PUSHD=1"

echo.
echo 7-Zip 文件夹加密解密工具
echo.

call :FIND_7Z
if errorlevel 1 (
    set "FINAL_EXIT_CODE=1"
    goto :FINISH
)

echo [信息] 使用 7-Zip：
call :PRINT_VALUE "%SEVENZIP_EXE%"
echo.

for %%F in (%TARGETS%) do (
    call :SCAN_TARGET "%%~F"
)

if defined REQUESTED_TARGETS_TEXT (
    echo 目标："%REQUESTED_TARGETS_TEXT%"
    echo.
)

echo 【发现的文件】
call :PRINT_TABLE "TARGET_ROW" "%TARGET_ROW_COUNT%" "文件|位置" "LABEL|PATH"
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
echo 【处理计划】
call :PRINT_TABLE "PLAN_ROW" "%PLAN_ROW_COUNT%" "目标|动作|原文件|输出文件" "TARGET|ACTION|SOURCE|OUTPUT"

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


:: ============================================================
:: 查找 7-Zip
:: ============================================================
:FIND_7Z
if not defined SEVENZIP_EXE goto :FIND_7Z_AUTO

set "SEVENZIP_EXE=%SEVENZIP_EXE:"=%"
call :USE_7Z_PATH "%SEVENZIP_EXE%"
if errorlevel 1 (
    echo [错误] SEVENZIP_EXE 不存在或不是文件：
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

echo [错误] 未找到 7-Zip 命令行程序。
echo 请把 7z.exe 或 7za.exe 放到本 bat 同级目录，或在用户配置区设置 SEVENZIP_EXE。
exit /b 1


:USE_7Z_PATH
set "CANDIDATE_7Z=%~1"

if not defined CANDIDATE_7Z exit /b 1
if not exist "%CANDIDATE_7Z%" exit /b 1
if exist "%CANDIDATE_7Z%\" exit /b 1

for %%Z in ("%CANDIDATE_7Z%") do set "SEVENZIP_EXE=%%~fZ"
exit /b 0


:: ============================================================
:: 扫描目标
:: ============================================================
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
if "%HAS_TARGET_FILE%"=="1" call :ADD_TARGET_ROW "%TARGET_NAME%" "存在同名文件，不能作为文件夹处理"
if "%HAS_ARCHIVE%"=="1" call :ADD_TARGET_ROW "%TARGET_NAME%%ARCHIVE_EXT%" "%TARGET_ARCHIVE%"
if "%HAS_ARCHIVE_DIR%"=="1" call :ADD_TARGET_ROW "%TARGET_NAME%%ARCHIVE_EXT%" "存在同名文件夹，不能作为压缩包处理"

if "%HAS_FOLDER%"=="0" if "%HAS_ARCHIVE%"=="0" if "%HAS_TARGET_FILE%"=="0" if "%HAS_ARCHIVE_DIR%"=="0" (
    call :ADD_TARGET_ROW "%TARGET_NAME%" "未找到文件夹或同名压缩包"
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
    set "TARGET_NAME=空目标"
    set "TARGET_INVALID_REASON=目标为空"
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
    set "TARGET_NAME=空目标"
    set "TARGET_INVALID_REASON=目标为空"
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
    set "TARGET_INVALID_REASON=目标不能是磁盘根目录或空路径"
    set "TARGET_FOLDER="
    set "TARGET_ARCHIVE="
    set "TARGET_PARENT="
    exit /b 0
)

if "%TARGET_NAME%"=="." (
    set "TARGET_VALID=0"
    set "TARGET_INVALID_REASON=目标不能是当前目录符号 ."
    exit /b 0
)

if "%TARGET_NAME%"==".." (
    set "TARGET_VALID=0"
    set "TARGET_INVALID_REASON=目标不能是上级目录符号 .."
    exit /b 0
)

set "TARGET_ARCHIVE=%TARGET_FOLDER%%ARCHIVE_EXT%"
exit /b 0


:: ============================================================
:: 全局模式选择
:: ============================================================
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
echo 请选择本次任务：
echo D 解密，处理所有存在同名压缩包的目标
echo E 加密，处理所有存在文件夹的目标
echo Q 终止任务
echo.

choice /C DEQ /N /M "请选择 D/E/Q："
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


:: ============================================================
:: 添加目标表行
:: ============================================================
:ADD_TARGET_ROW
set /a TARGET_ROW_COUNT+=1
set "TARGET_ROW_LABEL_%TARGET_ROW_COUNT%=%~1"
set "TARGET_ROW_PATH_%TARGET_ROW_COUNT%=%~2"
exit /b 0


:: ============================================================
:: 根据全局模式生成计划
:: ============================================================
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
    call :ADD_PLAN_ROW "%NAME%" "跳过" "目标无效" "%INVALID_REASON%"
    call :ADD_PLAN "SKIP" "%FOLDER%" "%ARCHIVE%" "%PARENT%" "%NAME%" "%NAME%" "跳过" "目标无效" "%INVALID_REASON%"
    exit /b 0
)

if "%SELECTED_MODE%"=="NONE" (
    call :ADD_PLAN_ROW "%NAME%" "跳过" "无" "无"
    call :ADD_PLAN "SKIP" "%FOLDER%" "%ARCHIVE%" "%PARENT%" "%NAME%" "%NAME%" "跳过" "无" "无"
    exit /b 0
)

if "%SELECTED_MODE%"=="ENCRYPT" goto :ADD_PLAN_ENCRYPT_MODE
if "%SELECTED_MODE%"=="DECRYPT" goto :ADD_PLAN_DECRYPT_MODE

call :ADD_PLAN_ROW "%NAME%" "跳过" "无" "无"
call :ADD_PLAN "SKIP" "%FOLDER%" "%ARCHIVE%" "%PARENT%" "%NAME%" "%NAME%" "跳过" "无" "无"
exit /b 0


:ADD_PLAN_ENCRYPT_MODE
if "%HAS_FOLDER%"=="1" goto :ADD_PLAN_ENCRYPT_CHECK_OUTPUT

set "SOURCE_STATE=无文件夹"
if "%HAS_TARGET_FILE%"=="1" set "SOURCE_STATE=同名文件不是文件夹"

set "OUTPUT_STATE=无操作"
if "%HAS_ARCHIVE%"=="1" set "OUTPUT_STATE=已有压缩包"
if "%HAS_ARCHIVE_DIR%"=="1" set "OUTPUT_STATE=同名 .7z 文件夹占用"

call :ADD_PLAN_ROW "%NAME%" "跳过" "%SOURCE_STATE%" "%OUTPUT_STATE%"
call :ADD_PLAN "SKIP" "%FOLDER%" "%ARCHIVE%" "%PARENT%" "%NAME%" "%NAME%" "跳过" "%SOURCE_STATE%" "%OUTPUT_STATE%"
exit /b 0


:ADD_PLAN_ENCRYPT_CHECK_OUTPUT
if "%HAS_ARCHIVE_DIR%"=="1" (
    call :ADD_PLAN_ROW "%NAME%" "跳过" "保留" "同名 .7z 文件夹占用"
    call :ADD_PLAN "SKIP" "%FOLDER%" "%ARCHIVE%" "%PARENT%" "%NAME%" "%NAME%" "跳过" "保留" "同名 .7z 文件夹占用"
    exit /b 0
)

goto :ADD_PLAN_ENCRYPT_FOUND


:ADD_PLAN_ENCRYPT_FOUND
set "SOURCE_STATE=保留"
if "%DELETE_SOURCE_AFTER_ENCRYPT%"=="1" set "SOURCE_STATE=删除"

set "OUTPUT_STATE=生成"
if "%HAS_ARCHIVE%"=="1" set "OUTPUT_STATE=替换"

call :ADD_PLAN_ROW "%NAME%" "加密" "%SOURCE_STATE%" "%OUTPUT_STATE%"
call :ADD_PLAN "ENCRYPT" "%FOLDER%" "%ARCHIVE%" "%PARENT%" "%NAME%" "%NAME%" "加密" "%SOURCE_STATE%" "%OUTPUT_STATE%"
exit /b 0


:ADD_PLAN_DECRYPT_MODE
if "%HAS_ARCHIVE%"=="1" goto :ADD_PLAN_DECRYPT_CHECK_OUTPUT

set "SOURCE_STATE=无压缩包"
if "%HAS_ARCHIVE_DIR%"=="1" set "SOURCE_STATE=同名 .7z 是文件夹"

set "OUTPUT_STATE=无操作"
if "%HAS_FOLDER%"=="1" set "OUTPUT_STATE=已有文件夹"
if "%HAS_TARGET_FILE%"=="1" set "OUTPUT_STATE=同名文件占用"

call :ADD_PLAN_ROW "%NAME%" "跳过" "%SOURCE_STATE%" "%OUTPUT_STATE%"
call :ADD_PLAN "SKIP" "%FOLDER%" "%ARCHIVE%" "%PARENT%" "%NAME%" "%NAME%" "跳过" "%SOURCE_STATE%" "%OUTPUT_STATE%"
exit /b 0


:ADD_PLAN_DECRYPT_CHECK_OUTPUT
if "%HAS_TARGET_FILE%"=="1" (
    call :ADD_PLAN_ROW "%NAME%" "跳过" "保留" "同名文件占用"
    call :ADD_PLAN "SKIP" "%FOLDER%" "%ARCHIVE%" "%PARENT%" "%NAME%" "%NAME%" "跳过" "保留" "同名文件占用"
    exit /b 0
)

goto :ADD_PLAN_DECRYPT_FOUND


:ADD_PLAN_DECRYPT_FOUND
set "SOURCE_STATE=保留"
if "%DELETE_ARCHIVE_AFTER_DECRYPT%"=="1" set "SOURCE_STATE=删除"

set "OUTPUT_STATE=生成"
if "%HAS_FOLDER%"=="1" set "OUTPUT_STATE=替换"

call :ADD_PLAN_ROW "%NAME%" "解密" "%SOURCE_STATE%" "%OUTPUT_STATE%"
call :ADD_PLAN "DECRYPT" "%FOLDER%" "%ARCHIVE%" "%PARENT%" "%NAME%" "%NAME%" "解密" "%SOURCE_STATE%" "%OUTPUT_STATE%"
exit /b 0


:: ============================================================
:: 添加处理计划
:: ============================================================
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


:: ============================================================
:: 读取密码
:: ============================================================
:READ_PASSWORD
if defined PASSWORD_READY exit /b 0

set "PASSWORD_B64="
echo.

if "%SELECTED_MODE%"=="ENCRYPT" (
    set "_PROMPT=请设置压缩密码"
) else (
    set "_PROMPT=请输入解压密码"
)

for /f "usebackq delims=" %%P in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "$p=Read-Host $env:_PROMPT -AsSecureString; $b=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($p); try{$s=[Runtime.InteropServices.Marshal]::PtrToStringBSTR($b); if($s.Length -eq 0){exit 2}; [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($s))} finally{if($b -ne [IntPtr]::Zero){[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b)}}"`) do set "PASSWORD_B64=%%P"

set "READ_PASSWORD_RET=%ERRORLEVEL%"
set "_PROMPT="

if not "%READ_PASSWORD_RET%"=="0" (
    echo [错误] 密码不能为空，任务终止。
    exit /b 1
)

if not defined PASSWORD_B64 (
    echo [错误] 密码读取失败，任务终止。
    exit /b 1
)

set "PASSWORD_READY=1"
echo.
exit /b 0


:: ============================================================
:: 对象专属临时目录
::
:: 目录格式：
::   目标父目录\__对象名_tmp_随机数
::
:: 示例：
::   private_1 的父目录为 D:\Safe\
::   临时目录可能为 D:\Safe\__private_1_tmp_23115488\
::
:: 说明：
:: - 临时目录创建在目标父目录；
:: - 这样可以减少跨盘移动问题，也更符合正式替换位置的文件系统逻辑。
:: ============================================================
:MAKE_OBJECT_TEMP_DIR
set "TEMP_OBJECT_NAME=%~1"
set "TEMP_PARENT=%~2"

if not defined TEMP_PARENT set "TEMP_PARENT=%CD%\"
if not "%TEMP_PARENT:~-1%"=="\" set "TEMP_PARENT=%TEMP_PARENT%\"

if not exist "%TEMP_PARENT%" (
    echo [失败] 目标父目录不存在：
    call :PRINT_VALUE "%TEMP_PARENT%"
    call :APPEND_NOTE "目标父目录不存在"
    exit /b 1
)

:MAKE_OBJECT_TEMP_DIR_AGAIN
set "ACTION_TEMP_DIR=%TEMP_PARENT%__%TEMP_OBJECT_NAME%_tmp_%RANDOM%%RANDOM%"

if exist "%ACTION_TEMP_DIR%\" goto :MAKE_OBJECT_TEMP_DIR_AGAIN
if exist "%ACTION_TEMP_DIR%" goto :MAKE_OBJECT_TEMP_DIR_AGAIN

mkdir "%ACTION_TEMP_DIR%"
if errorlevel 1 (
    echo [失败] 无法创建对象临时目录：
    call :PRINT_VALUE "%ACTION_TEMP_DIR%"
    call :APPEND_NOTE "临时目录创建失败"
    exit /b 1
)

exit /b 0


:CLEAN_TEMP_DIR
set "TMP_DIR_TO_CLEAN=%~1"

if not defined TMP_DIR_TO_CLEAN exit /b 0
if not exist "%TMP_DIR_TO_CLEAN%\" exit /b 0

rmdir /s /q "%TMP_DIR_TO_CLEAN%" >nul 2>nul

if exist "%TMP_DIR_TO_CLEAN%\" (
    echo [提示] 临时目录清理失败，请手动检查：
    call :PRINT_VALUE "%TMP_DIR_TO_CLEAN%"
    call :APPEND_NOTE "临时目录未清理"
)

exit /b 0


:APPEND_NOTE
if "%~1"=="" exit /b 0

if not defined PROCESS_NOTE (
    set "PROCESS_NOTE=%~1"
    exit /b 0
)

if "%PROCESS_NOTE%"=="无" (
    set "PROCESS_NOTE=%~1"
    exit /b 0
)

set "PROCESS_NOTE=%PROCESS_NOTE%；%~1"
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


:: ============================================================
:: 执行计划
:: ============================================================
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
    call :ADD_RESULT_ROW "%DISPLAY_TARGET%" "%DISPLAY_ACTION%" "%DISPLAY_SOURCE%" "%DISPLAY_OUTPUT%" "跳过-" "未处理"
    exit /b 0
)

set "PROCESS_NOTE=无"
set "RESULT_SOURCE=%DISPLAY_SOURCE%"
set "RESULT_OUTPUT=%DISPLAY_OUTPUT%"

call :PROCESS_ACTION
set "PROCESS_RET=%ERRORLEVEL%"

if "%PROCESS_RET%"=="0" (
    call :ADD_RESULT_ROW "%DISPLAY_TARGET%" "%DISPLAY_ACTION%" "%RESULT_SOURCE%" "%RESULT_OUTPUT%" "成功√" "%PROCESS_NOTE%"
    exit /b 0
)

call :ADD_RESULT_ROW "%DISPLAY_TARGET%" "%DISPLAY_ACTION%" "%RESULT_SOURCE%" "%RESULT_OUTPUT%" "失败×" "%PROCESS_NOTE%"
set /a FAILED_COUNT+=1
exit /b 1


:PROCESS_ACTION
if "%TASK_ACTION%"=="ENCRYPT" goto :PROCESS_ENCRYPT
if "%TASK_ACTION%"=="DECRYPT" goto :PROCESS_DECRYPT

echo [失败] 未知任务类型：
call :PRINT_VALUE "%TASK_ACTION%"
call :APPEND_NOTE "未知任务类型"
set "RESULT_SOURCE=无"
set "RESULT_OUTPUT=无"
exit /b 1


:PROCESS_ENCRYPT
call :DO_ENCRYPT_ONE "%FOLDER%" "%ARCHIVE%" "%PARENT%" "%NAME%"
exit /b %ERRORLEVEL%


:PROCESS_DECRYPT
call :DO_DECRYPT_ONE "%FOLDER%" "%ARCHIVE%" "%PARENT%" "%NAME%"
exit /b %ERRORLEVEL%


:: ============================================================
:: 加密处理
::
:: 流程：
:: 1. 创建对象专属临时目录；
:: 2. 在临时目录中生成 对象名.7z；
:: 3. 确认临时压缩包存在；
:: 4. 如果正式位置已有旧压缩包，则删除旧压缩包；
:: 5. 把临时压缩包移动到正式位置；
:: 6. 按配置决定是否删除原文件夹；
:: 7. 清理临时目录。
:: ============================================================
:DO_ENCRYPT_ONE
set "FOLDER=%~1"
set "ARCHIVE=%~2"
set "PARENT=%~3"
set "NAME=%~4"

if "%DISPLAY_OUTPUT%"=="替换" (
    set "RESULT_OUTPUT=未替换"
) else (
    set "RESULT_OUTPUT=未生成"
)
set "RESULT_SOURCE=保留"

echo.
call :LOG_STEP "正在加密：" "%FOLDER%"

if not exist "%FOLDER%\" (
    echo [失败] 原文件夹不存在。
    call :APPEND_NOTE "原文件夹不存在"
    exit /b 1
)

if exist "%ARCHIVE%\" (
    echo [失败] 正式位置存在同名 .7z 文件夹，无法生成压缩包：
    call :PRINT_VALUE "%ARCHIVE%"
    call :APPEND_NOTE "同名 .7z 文件夹占用"
    exit /b 1
)

call :MAKE_OBJECT_TEMP_DIR "%NAME%" "%PARENT%"
if errorlevel 1 exit /b 1

set "TMP_DIR=%ACTION_TEMP_DIR%"
set "TMP_ARCHIVE=%TMP_DIR%\%NAME%%ARCHIVE_EXT%"

call :LOG_STEP "生成压缩包到临时目录：" "%TMP_ARCHIVE%"

call :RUN_7Z encrypt "%PARENT%" "%TMP_ARCHIVE%" "%NAME%"
if errorlevel 1 (
    echo [失败] 压缩失败，原文件夹和旧压缩包均已保留。
    call :APPEND_NOTE "压缩失败"
    call :CLEAN_TEMP_DIR "%TMP_DIR%"
    exit /b 1
)

if not exist "%TMP_ARCHIVE%" (
    echo [失败] 7-Zip 返回成功，但未找到临时压缩包。
    call :APPEND_NOTE "未生成临时压缩包"
    call :CLEAN_TEMP_DIR "%TMP_DIR%"
    exit /b 1
)

if exist "%ARCHIVE%" (
    call :LOG_STEP "删除旧压缩包：" "%ARCHIVE%"
    del /f /q "%ARCHIVE%"
    if exist "%ARCHIVE%" (
        echo [失败] 旧压缩包删除失败。
        echo [保留] 新压缩包仍在：
        call :PRINT_VALUE "%TMP_ARCHIVE%"
        call :APPEND_NOTE "旧压缩包删除失败，新压缩包已保留"
        exit /b 1
    )
)

call :LOG_STEP "移动新压缩包到正式位置：" "%ARCHIVE%"
move /y "%TMP_ARCHIVE%" "%ARCHIVE%" >nul
if errorlevel 1 (
    echo [失败] 新压缩包移动失败。
    echo [保留] 新压缩包仍在：
    call :PRINT_VALUE "%TMP_ARCHIVE%"
    call :APPEND_NOTE "新压缩包移动失败"
    exit /b 1
)

if not exist "%ARCHIVE%" (
    echo [失败] 新压缩包移动后，正式位置未找到压缩包。
    call :APPEND_NOTE "新压缩包移动后未找到"
    exit /b 1
)

set "RESULT_OUTPUT=%DISPLAY_OUTPUT%"

if "%DELETE_SOURCE_AFTER_ENCRYPT%"=="1" (
    call :LOG_STEP "删除原文件夹：" "%FOLDER%"
    rmdir /s /q "%FOLDER%"
    if exist "%FOLDER%\" (
        echo [失败] 压缩包已处理完成，但原文件夹删除失败。
        set "RESULT_SOURCE=保留"
        call :APPEND_NOTE "压缩成功，原文件夹删除失败"
        call :CLEAN_TEMP_DIR "%TMP_DIR%"
        exit /b 1
    )
    set "RESULT_SOURCE=删除"
) else (
    set "RESULT_SOURCE=保留"
)

call :CLEAN_TEMP_DIR "%TMP_DIR%"

echo [完成]
exit /b 0


:: ============================================================
:: 解密处理
::
:: 流程：
:: 1. 创建对象专属临时目录；
:: 2. 把压缩包解压到临时目录；
:: 3. 确认临时目录中存在同名顶层文件夹；
:: 4. 如果正式位置已有旧文件夹，则删除旧文件夹；
:: 5. 把临时目录中的新文件夹移动到正式位置；
:: 6. 按配置决定是否删除原压缩包；
:: 7. 清理临时目录。
:: ============================================================
:DO_DECRYPT_ONE
set "FOLDER=%~1"
set "ARCHIVE=%~2"
set "PARENT=%~3"
set "NAME=%~4"

if "%DISPLAY_OUTPUT%"=="替换" (
    set "RESULT_OUTPUT=未替换"
) else (
    set "RESULT_OUTPUT=未生成"
)
set "RESULT_SOURCE=保留"

echo.
call :LOG_STEP "正在解密：" "%ARCHIVE%"

if exist "%ARCHIVE%\" (
    echo [失败] 压缩包路径是文件夹，无法解密：
    call :PRINT_VALUE "%ARCHIVE%"
    call :APPEND_NOTE "压缩包路径是文件夹"
    exit /b 1
)

if not exist "%ARCHIVE%" (
    echo [失败] 压缩包不存在。
    call :APPEND_NOTE "压缩包不存在"
    exit /b 1
)

if exist "%FOLDER%" if not exist "%FOLDER%\" (
    echo [失败] 正式位置存在同名文件，无法解密为文件夹：
    call :PRINT_VALUE "%FOLDER%"
    call :APPEND_NOTE "同名文件占用"
    exit /b 1
)

call :MAKE_OBJECT_TEMP_DIR "%NAME%" "%PARENT%"
if errorlevel 1 exit /b 1

set "TMP_DIR=%ACTION_TEMP_DIR%"
set "TMP_FOLDER=%TMP_DIR%\%NAME%"

call :LOG_STEP "解压文件夹到临时目录：" "%TMP_FOLDER%"

call :RUN_7Z decrypt "%TMP_DIR%" "%ARCHIVE%" ""
if errorlevel 1 (
    echo [失败] 解密失败。可能是密码错误，或压缩包损坏。
    call :APPEND_NOTE "解压失败"
    call :CLEAN_TEMP_DIR "%TMP_DIR%"
    exit /b 1
)

if not exist "%TMP_FOLDER%\" (
    echo [失败] 解压完成，但没有发现同名顶层文件夹：
    call :PRINT_VALUE "%TMP_FOLDER%"
    echo [保留] 临时解压内容仍在：
    call :PRINT_VALUE "%TMP_DIR%"
    call :APPEND_NOTE "压缩包内部不是同名顶层文件夹"
    exit /b 1
)

if exist "%FOLDER%\" (
    call :LOG_STEP "删除旧文件夹：" "%FOLDER%"
    rmdir /s /q "%FOLDER%"
    if exist "%FOLDER%\" (
        echo [失败] 旧文件夹删除失败。
        echo [保留] 新解压文件夹仍在：
        call :PRINT_VALUE "%TMP_FOLDER%"
        call :APPEND_NOTE "旧文件夹删除失败，新文件夹已保留"
        exit /b 1
    )
)

call :LOG_STEP "移动新文件夹到正式位置：" "%FOLDER%"
move /y "%TMP_FOLDER%" "%PARENT%" >nul
if errorlevel 1 (
    echo [失败] 新文件夹移动失败。
    echo [保留] 新解压文件夹仍在：
    call :PRINT_VALUE "%TMP_FOLDER%"
    call :APPEND_NOTE "新文件夹移动失败"
    exit /b 1
)

if not exist "%FOLDER%\" (
    echo [失败] 新文件夹移动后，正式位置未找到文件夹。
    call :APPEND_NOTE "新文件夹移动后未找到"
    exit /b 1
)

set "RESULT_OUTPUT=%DISPLAY_OUTPUT%"

if "%DELETE_ARCHIVE_AFTER_DECRYPT%"=="1" (
    call :LOG_STEP "删除压缩包：" "%ARCHIVE%"
    del /f /q "%ARCHIVE%"
    if exist "%ARCHIVE%" (
        echo [失败] 文件夹已处理完成，但压缩包删除失败。
        set "RESULT_SOURCE=保留"
        call :APPEND_NOTE "解压成功，压缩包删除失败"
        call :CLEAN_TEMP_DIR "%TMP_DIR%"
        exit /b 1
    )
    set "RESULT_SOURCE=删除"
) else (
    set "RESULT_SOURCE=保留"
)

call :CLEAN_TEMP_DIR "%TMP_DIR%"

echo [完成]
exit /b 0


:: ============================================================
:: 调用 7-Zip
:: 参数：
:: %1 = encrypt / decrypt
:: %2 = encrypt 时为工作目录；decrypt 时为输出目录
:: %3 = 压缩包路径
:: %4 = encrypt 时为文件夹名
:: ============================================================
:RUN_7Z
set "Z_MODE=%~1"
set "Z_WORKDIR=%~2"
set "Z_ARCHIVE=%~3"
set "Z_NAME=%~4"
set "Z_EXE=%SEVENZIP_EXE%"

powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $code=1; try { $pwd=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($env:PASSWORD_B64)); $pflag='-p' + $pwd; if($env:Z_MODE -eq 'encrypt'){ $sevenArgs=@('a','-t7z','-mhe=on','-mx=9','-y','-bso0','-bse0','-bsp0',$pflag,$env:Z_ARCHIVE,'--',($env:Z_NAME + '\')); Push-Location -LiteralPath $env:Z_WORKDIR; try { & $env:Z_EXE @sevenArgs; $code=$LASTEXITCODE } finally { Pop-Location } } else { $sevenArgs=@('x','-y','-bso0','-bse0','-bsp0',$pflag,$env:Z_ARCHIVE,('-o' + $env:Z_WORKDIR)); & $env:Z_EXE @sevenArgs; $code=$LASTEXITCODE } } catch { Write-Error $_; $code=1 }; exit $code"

exit /b %ERRORLEVEL%


:: ============================================================
:: 结果表
:: ============================================================
:ADD_RESULT_ROW
set /a RESULT_ROW_COUNT+=1
set "RESULT_ROW_TARGET_%RESULT_ROW_COUNT%=%~1"
set "RESULT_ROW_ACTION_%RESULT_ROW_COUNT%=%~2"
set "RESULT_ROW_SOURCE_%RESULT_ROW_COUNT%=%~3"
set "RESULT_ROW_OUTPUT_%RESULT_ROW_COUNT%=%~4"
set "RESULT_ROW_RESULT_%RESULT_ROW_COUNT%=%~5"
set "RESULT_ROW_NOTE_%RESULT_ROW_COUNT%=%~6"
exit /b 0


:: ============================================================
:: 通用表格打印
:: 参数：
:: %1 = 变量前缀，例如 TARGET_ROW / PLAN_ROW / RESULT_ROW
:: %2 = 行数
:: %3 = 表头，用 | 分隔
:: %4 = 字段名，用 | 分隔
::
:: 示例：
:: call :PRINT_TABLE "TARGET_ROW" "%TARGET_ROW_COUNT%" "文件|位置" "LABEL|PATH"
::
:: 读取变量：
:: TARGET_ROW_LABEL_1
:: TARGET_ROW_PATH_1
:: ============================================================
:PRINT_TABLE
set "TABLE_PREFIX=%~1"
set "TABLE_COUNT=%~2"
set "TABLE_HEADERS=%~3"
set "TABLE_FIELDS=%~4"

powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; function W($s){$s=[string]$s;$n=0;foreach($c in $s.ToCharArray()){$u=[int][char]$c;if(($u -ge 0x2E80 -and $u -le 0xA4CF) -or ($u -ge 0xAC00 -and $u -le 0xD7A3) -or ($u -ge 0xF900 -and $u -le 0xFAFF) -or ($u -ge 0xFE10 -and $u -le 0xFE6F) -or ($u -ge 0xFF00 -and $u -le 0xFFE6)){$n+=2}else{$n++}};$n}; function P($s,$w){[string]$s + (' ' * [Math]::Max(0,$w-(W $s)))}; $prefix=$env:TABLE_PREFIX; $count=[int]$env:TABLE_COUNT; $headers=$env:TABLE_HEADERS -split '\|'; $fields=$env:TABLE_FIELDS -split '\|'; if($count -le 0){exit}; $rows=@(); for($i=1;$i -le $count;$i++){ $o=[ordered]@{}; for($c=0;$c -lt $fields.Count;$c++){ $v=[Environment]::GetEnvironmentVariable($prefix + '_' + $fields[$c] + '_' + $i); if($null -eq $v){$v=''}; $o[$headers[$c]]=$v }; $rows += [pscustomobject]$o }; $widths=@(); for($c=0;$c -lt $headers.Count;$c++){ $max=W $headers[$c]; foreach($r in $rows){ $v=$r.PSObject.Properties[$headers[$c]].Value; $w=W $v; if($w -gt $max){$max=$w} }; if($c -lt $headers.Count-1){$max+=2}; $widths += $max }; $line=''; for($c=0;$c -lt $headers.Count;$c++){ if($c -lt $headers.Count-1){$line += P $headers[$c] $widths[$c]}else{$line += $headers[$c]} }; Write-Host $line; $sum=0; foreach($w in $widths){$sum+=$w}; Write-Host ('-' * $sum); foreach($r in $rows){ $line=''; for($c=0;$c -lt $headers.Count;$c++){ $v=$r.PSObject.Properties[$headers[$c]].Value; if($c -lt $headers.Count-1){$line += P $v $widths[$c]}else{$line += [string]$v} }; Write-Host $line }"

exit /b 0


:: ============================================================
:: 结束
:: ============================================================
:FINISH
set "PASSWORD_B64="

if not "%RESULT_ROW_COUNT%"=="0" (
    echo.
    echo 【处理结果】
    call :PRINT_TABLE "RESULT_ROW" "%RESULT_ROW_COUNT%" "目标|动作|原文件|输出文件|结果|备注" "TARGET|ACTION|SOURCE|OUTPUT|RESULT|NOTE"
)

if "%ABORTED%"=="1" (
    set "FINAL_EXIT_CODE=2"
)

if "%FINAL_EXIT_CODE%"=="0" if not "%FAILED_COUNT%"=="0" set "FINAL_EXIT_CODE=1"

goto :END


:END
echo.
echo 请按任意键退出...
pause >nul

if defined DID_PUSHD popd >nul
endlocal & exit /b %FINAL_EXIT_CODE%