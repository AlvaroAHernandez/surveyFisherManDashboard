@echo off
REM Script para ejecutar ShinyApp en Windows
REM Haz doble clic en este archivo para ejecutar la app

echo.
echo ========================================
echo   Dashboard Pesquero UABCS - ShinyApp
echo ========================================
echo.

REM Verificar si R está instalado
where Rscript >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: R no está instalado o no está en PATH
    echo.
    echo Por favor instala R desde: https://www.r-project.org/
    pause
    exit /b 1
)

REM Instalar dependencias si es necesario
echo Verificando dependencias...
Rscript install_dependencies.R

REM Ejecutar la app
echo.
echo Iniciando ShinyApp en puerto 3838...
echo La app se abrirá en tu navegador por defecto
echo Presiona Ctrl+C en esta ventana para detener la app
echo.

Rscript -e "shiny::runApp('shiny_app.R', host='127.0.0.1', port=3838, launch.browser=TRUE)"

pause
