@echo off
chcp 65001 >nul

set "APP_DIR=%~dp0"
set "PROJECT_ROOT=%APP_DIR%"
set "TARGET_DIR=%APP_DIR%..\openclaude\gateway\data\app"

for %%i in ("%TARGET_DIR%") do set "TARGET_DIR=%%~fi"

echo Source: %PROJECT_ROOT%
echo Target: %TARGET_DIR%
echo.

if not exist "%TARGET_DIR%" (
    mkdir "%TARGET_DIR%"
    echo Created: %TARGET_DIR%
    echo.
)

:: Copy directories
if exist "%PROJECT_ROOT%\bin" (
    echo [1/8] Copying bin ...
    xcopy "%PROJECT_ROOT%\bin" "%TARGET_DIR%\bin\" /E /I /Y >nul
    echo   OK bin
)

if exist "%PROJECT_ROOT%\dist" (
    echo [2/8] Copying dist ...
    xcopy "%PROJECT_ROOT%\dist" "%TARGET_DIR%\dist\" /E /I /Y >nul
    echo   OK dist
)

if exist "%PROJECT_ROOT%\docs" (
    echo [3/8] Copying docs ...
    xcopy "%PROJECT_ROOT%\docs" "%TARGET_DIR%\docs\" /E /I /Y >nul
    echo   OK docs
)

if exist "%PROJECT_ROOT%\packages" (
    echo [4/8] Copying packages ...
    xcopy "%PROJECT_ROOT%\packages" "%TARGET_DIR%\packages\" /E /I /Y >nul
    echo   OK packages
)

if exist "%PROJECT_ROOT%\scripts" (
    echo [5/8] Copying scripts ...
    xcopy "%PROJECT_ROOT%\scripts" "%TARGET_DIR%\scripts\" /E /I /Y >nul
    echo   OK scripts
)

if exist "%PROJECT_ROOT%\tests" (
    echo [6/8] Copying tests ...
    xcopy "%PROJECT_ROOT%\tests" "%TARGET_DIR%\tests\" /E /I /Y >nul
    echo   OK tests
)

if exist "%PROJECT_ROOT%\node_modules" (
    echo [7/8] Copying node_modules ...
    xcopy "%PROJECT_ROOT%\node_modules" "%TARGET_DIR%\node_modules\" /E /I /Y >nul
    echo   OK node_modules
)

:: Copy root files
echo [8/8] Copying root files...
if exist "%PROJECT_ROOT%\AGENTS.md" (
    copy "%PROJECT_ROOT%\AGENTS.md" "%TARGET_DIR%\AGENTS.md" /Y >nul
    echo   OK AGENTS.md
)

if exist "%PROJECT_ROOT%\ARCHITECTURE.md" (
    copy "%PROJECT_ROOT%\ARCHITECTURE.md" "%TARGET_DIR%\ARCHITECTURE.md" /Y >nul
    echo   OK ARCHITECTURE.md
)

if exist "%PROJECT_ROOT%\DEVELOPMENT.md" (
    copy "%PROJECT_ROOT%\DEVELOPMENT.md" "%TARGET_DIR%\DEVELOPMENT.md" /Y >nul
    echo   OK DEVELOPMENT.md
)

if exist "%PROJECT_ROOT%\Dockerfile" (
    copy "%PROJECT_ROOT%\Dockerfile" "%TARGET_DIR%\Dockerfile" /Y >nul
    echo   OK Dockerfile
)

if exist "%PROJECT_ROOT%\LICENSE" (
    copy "%PROJECT_ROOT%\LICENSE" "%TARGET_DIR%\LICENSE" /Y >nul
    echo   OK LICENSE
)

if exist "%PROJECT_ROOT%\README.md" (
    copy "%PROJECT_ROOT%\README.md" "%TARGET_DIR%\README.md" /Y >nul
    echo   OK README.md
)

if exist "%PROJECT_ROOT%\README_zh.md" (
    copy "%PROJECT_ROOT%\README_zh.md" "%TARGET_DIR%\README_zh.md" /Y >nul
    echo   OK README_zh.md
)

if exist "%PROJECT_ROOT%\docker-compose.yml" (
    copy "%PROJECT_ROOT%\docker-compose.yml" "%TARGET_DIR%\docker-compose.yml" /Y >nul
    echo   OK docker-compose.yml
)

if exist "%PROJECT_ROOT%\nodemon.json" (
    copy "%PROJECT_ROOT%\nodemon.json" "%TARGET_DIR%\nodemon.json" /Y >nul
    echo   OK nodemon.json
)

if exist "%PROJECT_ROOT%\package-lock.json" (
    copy "%PROJECT_ROOT%\package-lock.json" "%TARGET_DIR%\package-lock.json" /Y >nul
    echo   OK package-lock.json
)

if exist "%PROJECT_ROOT%\package.json" (
    copy "%PROJECT_ROOT%\package.json" "%TARGET_DIR%\package.json" /Y >nul
    echo   OK package.json
)

if exist "%PROJECT_ROOT%\playwright.config.ts" (
    copy "%PROJECT_ROOT%\playwright.config.ts" "%TARGET_DIR%\playwright.config.ts" /Y >nul
    echo   OK playwright.config.ts
)

if exist "%PROJECT_ROOT%\tsconfig.app.json" (
    copy "%PROJECT_ROOT%\tsconfig.app.json" "%TARGET_DIR%\tsconfig.app.json" /Y >nul
    echo   OK tsconfig.app.json
)

if exist "%PROJECT_ROOT%\tsconfig.json" (
    copy "%PROJECT_ROOT%\tsconfig.json" "%TARGET_DIR%\tsconfig.json" /Y >nul
    echo   OK tsconfig.json
)

if exist "%PROJECT_ROOT%\tsconfig.node.json" (
    copy "%PROJECT_ROOT%\tsconfig.node.json" "%TARGET_DIR%\tsconfig.node.json" /Y >nul
    echo   OK tsconfig.node.json
)

if exist "%PROJECT_ROOT%\tsconfig.website.json" (
    copy "%PROJECT_ROOT%\tsconfig.website.json" "%TARGET_DIR%\tsconfig.website.json" /Y >nul
    echo   OK tsconfig.website.json
)

if exist "%PROJECT_ROOT%\vite.config.ts" (
    copy "%PROJECT_ROOT%\vite.config.ts" "%TARGET_DIR%\vite.config.ts" /Y >nul
    echo   OK vite.config.ts
)

if exist "%PROJECT_ROOT%\vite.config.website.ts" (
    copy "%PROJECT_ROOT%\vite.config.website.ts" "%TARGET_DIR%\vite.config.website.ts" /Y >nul
    echo   OK vite.config.website.ts
)

if exist "%PROJECT_ROOT%\vitest.config.ts" (
    copy "%PROJECT_ROOT%\vitest.config.ts" "%TARGET_DIR%\vitest.config.ts" /Y >nul
    echo   OK vitest.config.ts
)

echo.
echo ========================================
echo Deploy completed!
echo Target: %TARGET_DIR%
echo ========================================
pause