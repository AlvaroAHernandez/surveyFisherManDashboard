# 🚀 ShinyApp - Dashboard Pesquero UABCS

## ⚡ Quick Start

### Paso 1: Verificar instalación
En tu consola R, ejecuta:
```r
Rscript check_setup.R
```

### Paso 2: Instalar dependencias (si es necesario)
```r
Rscript install_dependencies.R
```

### Paso 3: Ejecutar la app
```r
shiny::runApp('shiny_app.R')
```

La app se abrirá automáticamente en tu navegador en `http://127.0.0.1:3838`

---

## 📋 Requisitos

- **R 4.0+** instalado
- Paquetes R: shiny, shinydashboard, shinyjs, tidyverse, plotly, jsonlite, readr, DT

### Instalar R:
https://www.r-project.org/

### Instalar RStudio (opcional pero recomendado):
https://www.rstudio.com/products/rstudio/download/

---

## 📁 Estructura de archivos

```
surveyFisherManDashboard/
├── shiny_app.R                    ← Aplicación principal
├── json/
│   └── survey.json               ← Definición de preguntas
├── geopoint.csv                  ← Datos geográficos
├── install_dependencies.R        ← Instala paquetes
├── check_setup.R                 ← Verifica setup
├── test_compile.R                ← Test de compilación
└── README_SHINY.md              ← Este archivo
```

---

## 🎨 Características

✅ **6 Secciones principales:**
- **Resumen** - Métricas y gráficos generales
- **Información Personal** - Preguntas demográficas
- **Acceso a Tecnología** - Preguntas sobre tech
- **Datos Demográficos** - Edad, experiencia
- **Percepción de Servicios** - Escalas Likert
- **Análisis Cruzado** - Tabla de contingencia

✅ **Filtros dinámicos:**
- Por Localidad
- Por Rango de Edad

✅ **Visualizaciones:**
- Gráficos de pie y barras
- Histogramas
- Mapas geográficos interactivos
- Tablas de contingencia
- Heatmaps

✅ **Exportación de datos:**
- Descargar CSV
- Ver datos crudos

---

## 🔗 Variables de Base de Datos

| Variable | Tipo | Descripción |
|----------|------|-------------|
| `Localidad` | String | Ubicación geográfica (18 localidades) |
| `3.2` | Categorical | Rango de edad (18-25, 26-35, etc.) |
| `timestamp` | DateTime | Fecha/hora de la encuesta |
| `Q1-Q4` | Mixed | Respuestas de preguntas |

---

## 📊 Colores UABCS

La app utiliza la paleta de colores oficial:
- Azul: `#009FD4`
- Azul Marino: `#00497E`
- Azul Profundo: `#002147`
- Amarillo: `#FFD100`
- Rojo: `#CC1E1E`

---

## 🐛 Solución de problemas

### Error: "No se encuentra shiny"
```r
install.packages("shiny")
```

### Error: "Puerto 3838 en uso"
```r
shiny::runApp('shiny_app.R', port = 3839)
```

### Error: "No se encuentra survey.json"
Verifica que exista el archivo `json/survey.json`

### Error: "No se encuentra geopoint.csv"
Verifica que exista el archivo `geopoint.csv`

---

## 🔄 Actualizar datos (Producción)

Para conectar a Firebase Firestore en lugar de datos simulados:

1. Instala firebaseR:
```r
devtools::install_github("firebase/firebase-admin-sdk/r")
```

2. En `shiny_app.R`, modifica `cargar_respuestas_encuestas()`:
```r
library(firebaseR)
firebase_init(...)
docs <- firebase_read("survey_responses")
# Procesar datos...
```

---

## 💡 Cambios personalizados

### Cambiar puerto
```r
shiny::runApp('shiny_app.R', port = 8080)
```

### Cambiar host (acceso remoto)
```r
shiny::runApp('shiny_app.R', host = '0.0.0.0', port = 3838)
```

### Desactivar auto-abrir navegador
```r
shiny::runApp('shiny_app.R', launch.browser = FALSE)
```

---

## 📞 Soporte

Para preguntas o reportar errores, contacta al equipo de desarrollo UABCS.

Versión: 1.0  
Última actualización: 2026-05-25
