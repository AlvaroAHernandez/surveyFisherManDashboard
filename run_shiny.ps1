# Script PowerShell para ejecutar ShinyApp en Windows
# Ejecución: .\run_shiny.ps1

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Dashboard Pesquero UABCS - ShinyApp" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Verificar si R está instalado
try {
    $rVersion = Rscript --version 2>&1
    Write-Host "✓ R encontrado: $rVersion" -ForegroundColor Green
} catch {
    Write-Host "❌ ERROR: R no está instalado o no está en PATH" -ForegroundColor Red
    Write-Host ""
    Write-Host "Por favor instala R desde: https://www.r-project.org/" -ForegroundColor Yellow
    pause
    exit 1
}

# Instalar dependencias
Write-Host ""
Write-Host "Verificando e instalando dependencias..." -ForegroundColor Yellow
Rscript install_dependencies.R

# Ejecutar app
Write-Host ""
Write-Host "Iniciando ShinyApp en puerto 3838..." -ForegroundColor Cyan
Write-Host "La app se abrirá en tu navegador automáticamente" -ForegroundColor Green
Write-Host "Presiona Ctrl+C para detener la app" -ForegroundColor Yellow
Write-Host ""

Rscript -e "shiny::runApp('shiny_app.R', host='127.0.0.1', port=3838, launch.browser=TRUE)"

pause
