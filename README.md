# 📊 Dashboard de Inclusión Financiera y Tecnologías en el Sector Pesquero BCS

## Descripción

Dashboard interactivo de análisis de encuestas dirigido a pescadores y productores acuícolas de Baja California Sur. Desarrollado con **Streamlit** y **Plotly**, proporciona visualizaciones avanzadas de datos sobre inclusión financiera y uso de tecnologías en el sector pesquero.

**Institución:** Universidad Autónoma de Baja California Sur (UABCS)  
**Proyecto:** PEE-2025-G-507 SECIHTY  
**Lema:** *"Sabiduría como Meta, Patria como Destino"*

---

## 🎯 Características Principales

### 📋 Organización por Secciones
- **8 secciones temáticas** de la encuesta (Identificación, Información del Encuestado, Demografía, etc.)
- Navegación mediante **tabs** intuitivos
- Cada sección agrupa preguntas relacionadas

### 📊 Visualizaciones Inteligentes
Las visualizaciones se adaptan automáticamente al tipo de pregunta:

| Tipo de Pregunta | Visualización |
|---|---|
| Opción múltiple / Sí-No | Gráfico de dona con porcentajes |
| Selección múltiple | Gráfico de barras horizontal |
| Numérico | Métricas + Histograma de distribución |
| Texto abierto | Vista expandible con respuestas |

### 🎨 Branding Institucional UABCS
- Logo oficial de la UABCS
- Paleta de colores institucionales:
  - **Azul UABCS:** #009FD4 (elementos primarios)
  - **Amarillo:** #FFD100 (acentos)
  - **Rojo:** #CC1E1E (alertas)
  - **Azul marino:** #00497E (fondos oscuros)

### 🔍 Filtros Dinámicos
- Filtro por **Localidad** (18 municipios costeros)
- Filtro por **Rango de Edad**
- Los gráficos se actualizan en tiempo real

### 🗺️ Mapa Geográfico
- Visualización interactiva de localidades de encuesta
- 18 puntos de muestreo en BCS:
  - San Carlos, La Paz, Guerrero Negro
  - Agua Verde, El Sargento, La Ventana
  - Y más...

### 📈 Análisis Cruzado
- Cruza información entre dos preguntas cualquiera
- Tabla de contingencia
- Heatmap de correlaciones
- Identifica patrones y relaciones en los datos

### 📊 Datos Crudos
- Sección dedicada para revisión de respuestas sin procesar
- Exportable para análisis externos
- Útil para auditoría de datos

---

## 🚀 Instalación

### Requisitos
- Python 3.8+
- pip o conda

### Pasos de Instalación

```bash
# 1. Clonar o descargar el repositorio
cd surveyFisherManDashboard

# 2. Crear entorno virtual (opcional pero recomendado)
python -m venv venv
source venv/bin/activate  # En Windows: venv\Scripts\activate

# 3. Instalar dependencias
pip install -r requirements.txt

# 4. Configurar Firebase
# - Descarga el archivo JSON de credenciales de Firebase
# - Colócalo en la raíz del proyecto (ya configurado como: surver-fisherman-uabcs-firebase-adminsdk-fbsvc-5c73dae273.json)
```

### Datos Requeridos

La aplicación espera los siguientes archivos en la raíz del proyecto:

```
surveyFisherManDashboard/
├── app.py
├── requirements.txt
├── logo_uabcs.png
├── UABCS_Branding.md
├── geopoint.csv                    # Coordenadas de localidades
├── json/
│   └── survey.json                 # Definición de encuesta
└── surver-fisherman-uabcs-firebase-adminsdk-fbsvc-5c73dae273.json  # Credenciales Firebase
```

---

## 📖 Uso

### Ejecutar la Aplicación

```bash
streamlit run app.py
```

La aplicación se abrirá en `http://localhost:8501`

### Navegación

1. **Encabezado:** Logo y título institucional con colores UABCS
2. **Sidebar (izquierda):** Filtros para refinar datos
3. **Tabs principales:**
   - 8 Secciones de la encuesta
   - 🗺️ **Mapa:** Localidades de muestreo
   - 📈 **Análisis Cruzado:** Correlaciones entre preguntas
   - 📊 **Datos Crudos:** Respuestas sin procesar

### Filtros

- **Localidad:** Selecciona una localidad o "Todas" para vista global
- **Rango de Edad:** Filtra por grupos etarios

Los filtros actúan en cascada: todas las visualizaciones se actualizan automáticamente.

---

## 🏗️ Estructura del Código

```python
# Funciones principales

renderizar_header()                          # Header con branding UABCS
cargar_definicion_preguntas(ruta)           # Carga JSON de encuesta
cargar_respuestas_encuestas()               # Lee datos de Firebase
cargar_localidades()                        # Lee geopoint.csv

visualizar_pregunta_opciones()              # Dona para opción múltiple
visualizar_pregunta_seleccion_multiple()    # Barras para selección múltiple
visualizar_pregunta_numerica()              # Métricas + Histograma
visualizar_pregunta_texto()                 # Tabla expandible

crear_mapa_localidades()                    # Scatter geo interactivo
agregar_estilos()                           # CSS inline UABCS
main()                                      # Orquestación principal
```

---

## 🔗 Integración Firebase

La aplicación se conecta a Firebase Firestore en la colección `survey_responses`:

```python
db = firestore.client()
docs = db.collection('survey_responses').stream()
```

**Estructura esperada de documentos:**
```json
{
  "responses": {
    "1.1": "San Carlos",
    "2.1": "Juan Pérez",
    "3.1": 42,
    ...
  },
  "timestamp": "2025-05-24T10:30:00Z"
}
```

---

## 📊 Tipos de Visualización

### Gráfico de Dona (Opción Múltiple / Sí-No)
- Proporciones visuales claras
- Etiquetas con porcentajes
- Métricas adicionales en columna lateral

### Gráfico de Barras Horizontal (Selección Múltiple)
- Útil para comparar múltiples opciones
- Ordenado por frecuencia descendente
- Escala de color azul UABCS

### Histograma (Numérico)
- Distribución de valores
- 20 bins por defecto
- Estadísticas clave (promedio, máx, mín)

### Tablas (Texto Abierto)
- Vista expandible para muchas respuestas
- Numeradas y accesibles
- Formato legible

---

## 🛠️ Configuración Avanzada

### Ajustar Caché de Datos
```python
@st.cache_data(ttl=300)  # Cache por 5 minutos
def cargar_respuestas_encuestas():
    ...
```

### Agregar Más Filtros
Edita el `main()` para agregar selectores adicionales:
```python
filtros['nueva_variable'] = st.sidebar.selectbox(...)
df_filtrado = df_filtrado[df_filtrado['columna'] == filtros['nueva_variable']]
```

### Personalizar Colores
Modifica el diccionario `UABCS_COLORS` al inicio de `app.py`.

---

## 📝 Estructura de la Encuesta

La encuesta está definida en `json/survey.json` con esta estructura:

```json
{
  "cuestionario": {
    "titulo": "...",
    "descripcion": "...",
    "secciones": [
      {
        "id_seccion": 1,
        "titulo": "DATOS DE IDENTIFICACIÓN",
        "preguntas": [
          {
            "id": "1.1",
            "texto": "Lugar de la encuesta:",
            "tipo": "texto_abierto"
          },
          ...
        ]
      }
    ]
  }
}
```

### Tipos de Pregunta Soportados
- `texto_abierto`
- `fecha`
- `opcion_multiple`
- `seleccion_multiple`
- `si_no`
- `numerico`

---

## 📂 Archivo de Localidades (geopoint.csv)

```csv
Localidad,Latitud,Longitud
San Carlos,23.9500,-109.7333
Guerrero Negro,27.9667,-114.0500
La Paz,24.1394,-110.3128
...
```

Contiene 18 localidades costeras de BCS con coordenadas para mapeo.

---

## 🎨 Identidad Visual

### Paleta UABCS
Todos los componentes siguen la identidad visual institucional:

| Elemento | Color | Uso |
|---|---|---|
| Primario | #009FD4 | Encabezados, tabs, borders |
| Secundario | #00497E | Fondos oscuros, títulos |
| Acento | #FFD100 | Highlights, botones, métricas |
| Alerta | #CC1E1E | Errores, advertencias |
| Fondo claro | #E3F4FB | Viñetas de preguntas |

### Logo
El logo `logo_uabcs.png` (escudo circular azul, franja amarilla, libro y cacto) se muestra en el encabezado según especificaciones de UABCS_Branding.md.

---

## 🐛 Troubleshooting

| Problema | Solución |
|---|---|
| **"ModuleNotFoundError: No module named 'streamlit'"** | Ejecuta `pip install -r requirements.txt` |
| **"Firebase connection error"** | Verifica que el archivo JSON de credenciales existe y es válido |
| **"No data from Firestore"** | Comprueba que la colección `survey_responses` existe y tiene documentos |
| **Logo no aparece** | Asegúrate que `logo_uabcs.png` está en la raíz del proyecto |

---

## 📄 Licencia

Proyecto de investigación de la Universidad Autónoma de Baja California Sur (UABCS).  
Área de Conocimiento de Ciencias del Mar y de la Tierra.

---

## 👥 Contacto

**Institución:** UABCS  
**Email:** (contacto institucional)  
**Sitio Web:** [uabcs.mx](https://uabcs.mx)

---

**Generado con Claude Code | Febrero 2026**
