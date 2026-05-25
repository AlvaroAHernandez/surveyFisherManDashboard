import streamlit as st
import firebase_admin
from firebase_admin import credentials
# pyrefly: ignore [missing-import]
from firebase_admin import firestore
import pandas as pd
import json
# pyrefly: ignore [missing-import]
import plotly.express as px 

# 1. Autenticación con Firebase
if not firebase_admin._apps:
    cred = credentials.Certificate("surver-fisherman-uabcs-firebase-adminsdk-fbsvc-5c73dae273.json")
    firebase_admin.initialize_app(cred)

db = firestore.client()

# --- Funciones de Carga de Datos ---

# 2. Función para cargar la DEFINICIÓN de preguntas desde el JSON local
@st.cache_data
def cargar_definicion_preguntas(ruta_archivo):
    with open(ruta_archivo, 'r', encoding='utf-8') as f:
        data = json.load(f)
        
    preguntas_planas = []
    
    # Función recursiva para extraer todas las preguntas, sub-preguntas e ítems
    def extraer_preguntas(lista):
        for item in lista:
            if 'id' in item and 'texto' in item:
                preguntas_planas.append(item)
            
            if 'sub_preguntas' in item:
                extraer_preguntas(item['sub_preguntas'])
            if 'preguntas' in item and isinstance(item.get('preguntas'), list):
                extraer_preguntas(item['preguntas'])
            if 'items' in item:
                extraer_preguntas(item['items'])
            if 'columnas' in item:
                columnas_validas = [c for c in item['columnas'] if isinstance(c, dict)]
                extraer_preguntas(columnas_validas)

    secciones = data.get('cuestionario', {}).get('secciones', [])
    for seccion in secciones:
        extraer_preguntas(seccion.get('preguntas', []))
        
    return preguntas_planas

# 3. Función para obtener las RESPUESTAS de las encuestas desde Firestore
@st.cache_data(ttl=300) # Cache por 5 minutos
def cargar_respuestas_encuestas():
    # ¡IMPORTANTE! Cambia 'encuestas' por el nombre de tu colección en Firestore.
    coleccion_ref = db.collection('survey_responses')
    documentos = coleccion_ref.stream()
    
    datos = []
    for doc in documentos:
        d = doc.to_dict()
        # Si las respuestas están dentro del campo 'responses', las aplanamos hacia la raíz
        if 'responses' in d and isinstance(d['responses'], dict):
            respuestas = d.pop('responses')
            d.update(respuestas)
        datos.append(d)
        
    return pd.DataFrame(datos)

# 4. Función para homologar/limpiar datos antes de graficar
def homologar_datos(serie, tipo_pregunta, id_pregunta):
    if tipo_pregunta in ['opcion_multiple', 'si_no', 'seleccion_multiple']:
        # --- REGLAS GLOBALES ---
        # Quita espacios extra, y pone la primera letra mayúscula (ej. "  hola  " -> "Hola")
        serie = serie.str.strip().str.capitalize()
        
        # Unifica las respuestas afirmativas comunes
        reemplazos_globales = {'Si': 'Sí', 'SÍ': 'Sí', 'Si ': 'Sí', 'SI': 'Sí'}
        serie = serie.replace(reemplazos_globales)
        
        # --- REGLAS ESPECÍFICAS (NIVEL 2) ---
        # Aquí puedes agregar "diccionarios" para preguntas rebeldes.
        # Ejemplo para la pregunta 2.5 ("Es usted:")
        if id_pregunta == '2.5':
            reemplazos_2_5 = {'Coop': 'Cooperativista', 'Cooperativa': 'Cooperativista', 'Libre': 'Pescador libre'}
            serie = serie.replace(reemplazos_2_5)

        if id_pregunta == '3.10':
            reemplazos_3_10 = {'Energía cfe' : 'Energía CFE', 'Energía eléctrica (cfe)' : 'Energía CFE' }
            serie = serie.replace(reemplazos_3_10)
        
        if id_pregunta == '3.11':
            reemplazos_3_11 = {'Conectada a red municipal': 'Red Municipal' , 'Agua conectada a red municipal': 'Red Municipal', 'Autoabastecimiento': 'Autoabasto', 'Agua autoabastecimiento': 'Autoabasto'}
            serie = serie.replace(reemplazos_3_11)

        if id_pregunta == '3.12':
            reemplazos_3_12 = {'Conectado a red municipal': 'Red Municipal' ,'Drenaje fosa séptica': 'Fosa Séptica', 'Drenaje conectado a red municipal': 'Red Municipal', 'Drenaje fosa séptica': 'Fosa séptica', 'Fosa Séptica': 'Fosa séptica'}
            serie = serie.replace(reemplazos_3_12)
            
    return serie

# --- Construcción del Dashboard ---

st.title("📊 Dashboard de Encuestas a Pescadores")

# Carga la definición de preguntas y las respuestas
try:
    definicion_preguntas = cargar_definicion_preguntas('json/survey.json')
except FileNotFoundError:
    st.error("Error: No se encontró el archivo JSON de la encuesta. Asegúrate de que la ruta sea correcta.")
    st.stop()

df_respuestas = cargar_respuestas_encuestas()

if not df_respuestas.empty:
    # Mostrar como texto (string) para evitar que PyArrow falle con campos de tipo lista
    st.write("### Vista General de Respuestas (Datos Crudos)", df_respuestas.astype(str))

    st.markdown("---")
    st.header("Análisis de Todas las Preguntas")

    # Iterar sobre todas las preguntas válidas encontradas en el JSON
    for pregunta_info in definicion_preguntas:
        if 'texto' not in pregunta_info or 'id' not in pregunta_info:
            continue
            
        columna_id = pregunta_info['id']
        pregunta_texto = f"{columna_id} - {pregunta_info['texto']}"
        tipo_pregunta = pregunta_info.get('tipo', 'desconocido')

        # Renderizar la pregunta sólo si tiene respuestas en la base de datos
        if columna_id in df_respuestas.columns:
            st.markdown("---")
            st.write(f"#### {pregunta_texto}")
            
            # Renderizar el componente adecuado según el "tipo" definido en el JSON
            if tipo_pregunta in ['opcion_multiple', 'si_no']:
                serie_limpia = df_respuestas[columna_id].dropna().astype(str)
                serie_limpia = homologar_datos(serie_limpia, tipo_pregunta, columna_id)
                
                if not serie_limpia.empty:
                    conteo = serie_limpia.value_counts().reset_index()
                    conteo.columns = ['Opción', 'Cantidad']
                    fig = px.pie(conteo, names='Opción', values='Cantidad', hole=0.4, title=pregunta_texto)
                    st.plotly_chart(fig, use_container_width=True)
                else:
                    st.info("No hay suficientes datos válidos para generar una gráfica para esta pregunta.")
                
            elif tipo_pregunta == 'seleccion_multiple':
                serie_limpia = df_respuestas[columna_id].dropna().explode().astype(str)
                serie_limpia = homologar_datos(serie_limpia, tipo_pregunta, columna_id)
                
                if not serie_limpia.empty:
                    conteo = serie_limpia.value_counts().reset_index()
                    conteo.columns = ['Opción', 'Cantidad']
                    fig = px.bar(conteo, x='Opción', y='Cantidad', text_auto=True, title=pregunta_texto)
                    fig.update_layout(xaxis_title="Opciones Seleccionadas", yaxis_title="Cantidad de Respuestas")
                    st.plotly_chart(fig, use_container_width=True)
                else:
                    st.info("No hay suficientes datos válidos para generar una gráfica para esta pregunta.")
                
            elif tipo_pregunta == 'numerico':
                # Forzar a formato numérico por si Firestore lo guardó como string
                df_respuestas[columna_id] = pd.to_numeric(df_respuestas[columna_id], errors='coerce')
                
                # Mostrar métricas clave en columnas
                col1, col2, col3 = st.columns(3)
                col1.metric("Promedio", f"{df_respuestas[columna_id].mean():.2f}")
                col2.metric("Valor Máximo", f"{df_respuestas[columna_id].max()}")
                col3.metric("Valor Mínimo", f"{df_respuestas[columna_id].min()}")
                
                st.write("Distribución de los datos:")
                datos_grafica = df_respuestas.dropna(subset=[columna_id])
                if not datos_grafica.empty:
                    fig = px.histogram(datos_grafica, x=columna_id, nbins=15)
                    fig.update_layout(xaxis_title="Valor", yaxis_title="Frecuencia (Cantidad de encuestados)")
                    st.plotly_chart(fig, use_container_width=True)
                else:
                    st.info("No hay suficientes datos válidos para generar un histograma.")
                
            elif tipo_pregunta in ['texto_abierto', 'texto_libre', 'fecha']:
                respuestas_limpias = df_respuestas[[columna_id]].dropna().astype(str)
                with st.expander("📝 Ver respuestas textuales proporcionadas"):
                    st.dataframe(respuestas_limpias, use_container_width=True)
                
            else:
                respuestas_limpias = df_respuestas[[columna_id]].dropna().astype(str)
                with st.expander(f"Visualización genérica para el tipo: `{tipo_pregunta}`"):
                    st.dataframe(respuestas_limpias, use_container_width=True)
else:
    st.warning("No se encontraron respuestas en la colección de Firestore.")
