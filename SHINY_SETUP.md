# 📊 Dashboard Pesquero UABCS - Shiny App

## Descripción

ShinyApp en R que replica la funcionalidad del dashboard Streamlit original. Visualiza encuestas pesqueras de Baja California Sur con datos conectados a Firebase/Firestore.

## Variables de Base de Datos Utilizadas

### Colección: `survey_responses` (Firestore)

**Campos principales:**
- `timestamp` - Fecha y hora de la encuesta
- `Localidad` - Ubicación de la encuesta (text)
  - Valores posibles: Cabo San Lucas, La Paz, Loreto, Ciudad Constitución, etc.
- `3.2` - Rango de edad del encuestado (categorical)
  - Valores: "18-25", "26-35", "36-45", "46-55", "56+"
- `responses` - Objeto anidado con todas las respuestas
- Campos de preguntas: Q1, Q2, Q3, Q4, etc. (mixed types)

### Archivo: `geopoint.csv`

**Estructura:**
| Localidad | Latitud | Longitud |
|-----------|---------|----------|
| Cabo San Lucas | 22.8898 | -109.9789 |
| La Paz | 24.1441 | -110.3127 |
| Loreto | 25.9589 | -111.3944 |

## Requisitos

### Sistema operativo
- Windows, macOS o Linux
- R 4.0+

### Librerías R necesarias

```r
install.packages(c(
  "shiny",
  "shinydashboard",
  "shinyjs",
  "tidyverse",
  "plotly",
  "jsonlite",
  "readr",
  "DT"
))
```

## Instalación

### 1. Instalar R
Descargar desde: https://www.r-project.org/

### 2. Instalar RStudio (opcional pero recomendado)
Descargar desde: https://www.rstudio.com/products/rstudio/download/

### 3. Instalar paquetes necesarios

Opción A - Automatizada (ejecutar en R):
```r
source("install_dependencies.R")
```

Opción B - Manual:
```r
install.packages(c(
  "shiny",
  "shinydashboard",
  "shinyjs",
  "tidyverse",
  "plotly",
  "jsonlite",
  "readr",
  "DT"
))
```

## Ejecución

### Opción 1: Desde RStudio
```r
library(shiny)
runApp("shiny_app.R")
```

### Opción 2: Desde línea de comandos (PowerShell)
```powershell
Rscript -e "shiny::runApp('shiny_app.R')"
```

### Opción 3: Desde línea de comandos (CMD)
```cmd
Rscript -e "shiny::runApp('shiny_app.R')"
```

## Estructura de la Aplicación

```
┌─ Header
│  └─ Dashboard de Encuestas Pesqueras UABCS
├─ Sidebar
│  ├─ Filtros (Localidad, Edad)
│  ├─ Métricas resumen
│  └─ Indicador de cobertura
└─ Body (Tabs)
   ├─ 📊 Resumen
   │  ├─ 4 Value Boxes (Encuestas, Localidades, Completitud, Campos)
   │  ├─ Gráfico de respuestas por localidad
   │  └─ Gráfico de distribución por edad
   ├─ 📋 Información Personal
   │  ├─ Gráficos de preguntas Q1, Q2
   │  └─ Histograma Q3
   ├─ 📋 Percepciones
   │  └─ Gráfico de escala Likert Q4
   ├─ 🗺️ Mapa
   │  └─ Mapa geográfico interactivo de localidades
   ├─ 📈 Análisis Cruzado
   │  └─ Tabla de contingencia y heatmap
   └─ 📊 Datos Crudos
      ├─ Tabla interactiva de datos
      └─ Botón de descarga CSV
```

## Características

✅ **Filtros dinámicos**: Localidad y rango de edad
✅ **Visualizaciones interactivas**: Gráficos Plotly
✅ **Mapa geográfico**: Distribución de encuestas en BCS
✅ **Análisis cruzado**: Tabla de contingencia
✅ **Descarga de datos**: Exportar CSV
✅ **Diseño responsivo**: Dashboard adaptable
✅ **Colores UABCS**: Paleta institucional integrada

## Tipos de Preguntas Soportados

| Tipo | Visualización |
|------|---------------|
| `opcion_multiple` / `si_no` | Gráfico de pie |
| `numerico` | Histograma |
| `escala_evaluacion` / Likert | Gráfico de barras horizontal |
| `seleccion_multiple` | Gráfico de barras |
| `grid_seleccion` | Heatmap |
| `tabla` | Tabla interactiva |
| `texto_abierto` | Texto sin procesar |

## Conexión a Firebase (Futuro)

Para conectar a Firebase Firestore en producción:

```r
# Instalar firebaseR
devtools::install_github("firebase/firebase-admin-sdk/r")

# En la función cargar_respuestas_encuestas():
library(firebaseR)

firebase_init(config = config_from_file("firebase-config.json"))
df <- firebase_read("survey_responses")
```

## Solución de problemas

### Error: "No se encuentra shiny"
```r
install.packages("shiny")
```

### Error: "No se encuentra plotly"
```r
install.packages("plotly")
```

### Puerto 3838 en uso
```r
runApp("shiny_app.R", port = 3839)
```

### Datos simulados vs. Firebase
Actualmente usa datos simulados. Descomentar línea en `cargar_respuestas_encuestas()` para conectar a Firebase.

## Comparativa: Streamlit vs. Shiny

| Aspecto | Streamlit (Python) | Shiny (R) |
|--------|-------------------|----------|
| Lenguaje | Python | R |
| Velocidad desarrollo | Muy rápida | Rápida |
| Interactividad | Buena | Excelente |
| Escalabilidad | Media | Buena |
| Comunidad | Grande (Python) | Mediana (R/Shiny) |
| Firebase | firebase-admin | firebaseR |
| Gráficos | Plotly/Altair | Plotly/ggplot2 |

## Licencia
Universidad Autónoma de Baja California Sur (UABCS)

## Contacto
Para preguntas o soporte, contactar al equipo de desarrollo UABCS.
