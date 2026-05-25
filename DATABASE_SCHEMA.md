# 📊 Esquema de Base de Datos - Dashboard Pesquero UABCS

## Descripción General

El dashboard utiliza **Firebase Firestore** como base de datos principal y archivos CSV como fuentes secundarias para datos geográficos.

---

## 1. Firestore - Colección `survey_responses`

### Documento Estructura

```json
{
  "_id": "docId_uuid",
  "timestamp": "2024-05-25T14:30:00Z",
  "Localidad": "La Paz",
  "3.2": "26-35",
  "responses": {
    "1.1": "Sí",
    "1.2": "Pescador",
    "2.1": [1, 3, 5],
    "2.2": "Comentario de texto libre",
    "3.1": 25,
    "3.2": "26-35",
    "3.3": {
      "opcion_1": 3,
      "opcion_2": 4
    }
  }
}
```

### Campos Principales

| Campo | Tipo | Descripción | Valores Ejemplo |
|-------|------|-------------|-----------------|
| `_id` | ObjectId | ID único del documento | `507f1f77bcf86cd799439011` |
| `timestamp` | Timestamp | Fecha y hora de creación | `2024-05-25T14:30:00Z` |
| `Localidad` | String | Ubicación geográfica | Cabo San Lucas, La Paz, Loreto, Ciudad Constitución, Puerto Escondido, etc. |
| `3.2` | String | Rango de edad del encuestado | "18-25", "26-35", "36-45", "46-55", "56+" |
| `responses` | Object | Respuestas anidadas con IDs de preguntas | Ver sección "Respuestas" |

### Respuestas Anidadas (Object)

Las respuestas se almacenan en el objeto `responses` con estructura clave-valor donde:
- **Clave**: ID de la pregunta (ej: "1.1", "2.3")
- **Valor**: Respuesta (tipo variable según pregunta)

#### Tipos de Respuestas Soportados

```javascript
// Opción única (si/no, múltiple choice)
"1.1": "Sí",
"1.2": "Opción A",

// Opción múltiple (selección multiple)
"2.1": [1, 3, 5],
"2.2": ["Opción A", "Opción B"],

// Numérica
"3.1": 25,
"3.3": 1500.50,

// Texto libre
"4.1": "Comentario del encuestado aquí",

// Escala Likert
"5.1": 4,  // 1-5

// Grid/Matriz
"6.1": {
  "fila_1": "columna_2",
  "fila_2": "columna_1"
},

// Tabla compleja
"7.1": [
  {"col1": "valor1", "col2": "valor2"},
  {"col1": "valor3", "col2": "valor4"}
],

// Fecha
"8.1": "2024-05-25"
```

---

## 2. CSV - Archivo `geopoint.csv`

### Estructura

```csv
Localidad,Latitud,Longitud
Cabo San Lucas,22.8898,-109.9789
La Paz,24.1441,-110.3127
Loreto,25.9589,-111.3944
Ciudad Constitución,24.7136,-112.0658
Puerto Escondido,25.3667,-111.3333
Mulegé,26.0952,-111.9627
Santa Rosalía,26.9307,-111.9769
San Ignacio,27.2936,-112.8891
Guerrero Negro,27.9769,-114.0622
El Cardón,26.5,-111.4167
La Ribera,23.4,-109.6833
Los Cabos,23.6345,-109.9789
Buena Vista,23.7647,-109.7267
Las Bariles,23.6403,-109.9439
Todos Santos,23.4533,-110.2167
Cerritos,24.2333,-109.7
El Divisadero,25.4,-110.7
San José del Cabo,23.6552,-109.6784
```

### Uso en Dashboard

- **Coordenadas geográficas**: Para renderizar mapa interactivo
- **Análisis espacial**: Agrupación de encuestas por localidad
- **Cálculo de cobertura**: Comparar localidades con respuestas vs. total (18 localidades)

---

## 3. JSON - Archivo `json/survey.json`

### Estructura del Cuestionario

```json
{
  "cuestionario": {
    "titulo": "Encuesta de Inclusión Financiera y Tecnologías",
    "descripcion": "Sector Pesquero en Baja California Sur",
    "secciones": [
      {
        "id_seccion": "1",
        "titulo": "Información Personal",
        "preguntas": [
          {
            "id": "1.1",
            "texto": "¿Es pescador?",
            "tipo": "si_no",
            "opciones": ["Sí", "No"]
          },
          {
            "id": "1.2",
            "texto": "¿Cuál es su ocupación principal?",
            "tipo": "opcion_multiple",
            "opciones": ["Pescador", "Comerciante", "Otro"]
          }
        ]
      },
      {
        "id_seccion": "2",
        "titulo": "Tecnología",
        "preguntas": [
          {
            "id": "2.1",
            "texto": "¿Qué tecnologías utiliza? (Selecciona todas)",
            "tipo": "seleccion_multiple",
            "opciones": ["Celular", "Laptop", "Internet", "Software"]
          }
        ]
      },
      {
        "id_seccion": "3",
        "titulo": "Datos Demográficos",
        "preguntas": [
          {
            "id": "3.1",
            "texto": "¿Cuántos años de experiencia tiene?",
            "tipo": "numerico"
          },
          {
            "id": "3.2",
            "texto": "¿Cuál es su rango de edad?",
            "tipo": "opcion_multiple",
            "opciones": ["18-25", "26-35", "36-45", "46-55", "56+"]
          }
        ]
      }
    ]
  }
}
```

### Tipos de Preguntas

| Tipo | Descripción | Visualización | Almacenamiento |
|------|-------------|----------------|-----------------|
| `si_no` | Pregunta binaria | Pie chart | String: "Sí"/"No" |
| `opcion_multiple` | Una opción de varias | Pie/Bar chart | String: opción seleccionada |
| `seleccion_multiple` | Múltiples opciones | Bar chart | Array de strings |
| `numerico` | Número libre | Histogram | Number |
| `escala_evaluacion` | Likert 1-5 | Bar chart horizontal | Number (1-5) |
| `grid_seleccion` | Matriz de opciones | Heatmap | Object con filas/columnas |
| `tabla` | Tabla de datos | Table | Array de Objects |
| `tabla_compleja` | Tabla compleja | DataTable | Array de Objects |
| `texto_abierto` | Texto sin restricción | Texto sin procesar | String |
| `texto_libre` | Alias de texto_abierto | Texto sin procesar | String |
| `fecha` | Selector de fecha | Timeline/Texto | String (YYYY-MM-DD) |

---

## 4. Mapeo de Datos: Streamlit → Shiny

### En `app.py` (Streamlit)

```python
# Cargar datos desde Firestore
docs = db.collection('survey_responses').stream()
datos = []
for doc in docs:
    d = doc.to_dict()
    if 'responses' in d and isinstance(d['responses'], dict):
        respuestas = d.pop('responses')
        d.update(respuestas)  # Aplanar responses a nivel de documento
    datos.append(d)
df = pd.DataFrame(datos)
```

### En `shiny_app.R` (Shiny)

```r
cargar_respuestas_encuestas <- function() {
  # Simulación de datos (en producción, conectar a Firebase)
  df <- data.frame(
    id = 1:100,
    timestamp = Sys.Date() - sample(0:30, 100, replace = TRUE),
    Localidad = sample(c("Cabo San Lucas", "La Paz", "Loreto", ...), 100, replace = TRUE),
    `3.2` = sample(c("18-25", "26-35", ...), 100, replace = TRUE),
    # ... más campos
  )
  return(df)
}
```

---

## 5. Filtros Disponibles

### Filtro 1: Localidad
- **Fuente**: `df_respuestas['Localidad']`
- **Tipo**: Categorical select
- **Valores**: Todas las localidades únicas en respuestas + "Todas"
- **Default**: "Todas"

### Filtro 2: Rango de Edad
- **Fuente**: `df_respuestas['3.2']`
- **Tipo**: Categorical select
- **Valores**: ["18-25", "26-35", "36-45", "46-55", "56+"]
- **Default**: "Todos"

---

## 6. Métricas Calculadas

| Métrica | Fórmula | Actualización |
|---------|---------|---------------|
| Total Encuestas | `len(df_filtrado)` | Reactiva |
| Localidades | `n_distinct(df['Localidad'])` | Reactiva |
| Completitud | `sum(!is.na(df)) / (nrow(df) * ncol(df)) * 100` | Reactiva |
| Cobertura | `localidades_con_datos / 18 * 100` | Reactiva |
| Total Campos | `ncol(df)` | Estática |

---

## 7. Conexión a Firebase (Producción)

### Configuración necesaria

```r
# 1. Instalar firebaseR
devtools::install_github("firebase/firebase-admin-sdk/r")

# 2. Crear firebase-config.json con credenciales
{
  "apiKey": "...",
  "authDomain": "...",
  "projectId": "surver-fisherman-uabcs",
  "storageBucket": "...",
  "messagingSenderId": "...",
  "appId": "..."
}

# 3. En shiny_app.R
library(firebaseR)
firebase_init(config = config_from_file("firebase-config.json"))

# 4. Modificar cargar_respuestas_encuestas()
docs <- firebase_read("survey_responses")
# Procesar responses...
```

---

## 8. Notas de Implementación

### Aplanamiento de datos (Flattening)

En Streamlit:
```python
responses = d.pop('responses')  # Extraer responses
d.update(respuestas)             # Agregar campos a nivel top
```

En Shiny (simulado):
```r
# Directamente creamos columnas en el data.frame
df <- data.frame(
  Localidad = "La Paz",
  `3.2` = "26-35",
  Q1 = "Sí",
  Q2 = 4,
  # ... etc
)
```

### Validación de datos

- Campos nulos se manejan con `na.omit()` en Shiny
- Conversiones de tipo: `as.numeric()`, `as.character()`, etc.
- Coerción de errores: `errors = 'coerce'` en operaciones numéricas

---

## 9. Resumen de Variables

### Por Categoría

**Geográficas:**
- `Localidad` (String, 18 valores únicos)
- `Latitud` (Numeric, -90 a 90)
- `Longitud` (Numeric, -180 a 180)

**Demográficas:**
- `3.2` Rango de edad (Categorical, 5 valores)

**Temporales:**
- `timestamp` (DateTime)

**De Respuesta:**
- `1.x`, `2.x`, `3.x`, etc. (Mixed types según tipo de pregunta)

---

## 10. Archivos de Configuración Requeridos

```
surveyFisherManDashboard/
├── app.py                                    # Streamlit original
├── shiny_app.R                               # ShinyApp nueva
├── json/
│   └── survey.json                          # Definición de cuestionario
├── geopoint.csv                             # Datos geográficos
├── surver-fisherman-uabcs-firebase-adminsdk-fbsvc-5c73dae273.json  # Credenciales
└── (Opcional en producción)
    └── firebase-config.json                 # Config Firebase para Shiny
```

