import streamlit as st
import firebase_admin
from firebase_admin import credentials
from firebase_admin import firestore
import pandas as pd
import json
import plotly.express as px

# 1. Autenticación con Firebase
if not firebase_admin._apps:
    cred = credentials.Certificate("/home/russellpc/workspace/surveyFisherManDashboard/surver-fisherman-uabcs-firebase-adminsdk-fbsvc-5c73dae273.json")
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

# --- Construcción del Dashboard ---

st.title("📊 Dashboard de Encuestas a Pescadores")

# Carga la definición de preguntas y las respuestas
try:
    definicion_preguntas = cargar_definicion_preguntas('/home/russellpc/workspace/surveyFisherManDashboard/json/survey.json')
except FileNotFoundError:
    st.error("Error: No se encontró el archivo JSON de la encuesta. Asegúrate de que la ruta sea correcta.")
    st.stop()

df_respuestas = cargar_respuestas_encuestas()

if not df_respuestas.empty:
    # Mostrar como texto (string) para evitar que PyArrow falle con campos de tipo lista
    st.write("### Vista General de Respuestas (Datos Crudos)", df_respuestas.astype(str))

    st.markdown("---")
    st.header("Análisis por Pregunta")

    # Crea un diccionario para mostrar el texto de la pregunta en el selectbox.
    # Usamos f"{p['id']} - {p['texto']}" para que sea más fácil identificar la pregunta
    opciones_pregunta = {f"{p['id']} - {p['texto']}": p['id'] for p in definicion_preguntas if 'texto' in p}
    
    pregunta_seleccionada_texto = st.selectbox(
        "Selecciona una pregunta para visualizar:",
        options=list(opciones_pregunta.keys())
    )
    
    # Obtiene el ID de la pregunta seleccionada para buscarlo en el DataFrame
    columna_id = opciones_pregunta[pregunta_seleccionada_texto]

    if columna_id in df_respuestas.columns:
        st.write(f"#### Resultados para: '{pregunta_seleccionada_texto}'")
        
        # Buscar la configuración de la pregunta actual en el JSON
        pregunta_info = next((p for p in definicion_preguntas if p['id'] == columna_id), None)
        tipo_pregunta = pregunta_info['tipo'] if pregunta_info else 'desconocido'
        
        # Renderizar el componente adecuado según el "tipo" definido en el JSON
        if tipo_pregunta in ['opcion_multiple', 'si_no']:
            serie_limpia = df_respuestas[columna_id].dropna().astype(str)
            if not serie_limpia.empty:
                conteo = serie_limpia.value_counts().reset_index()
                conteo.columns = ['Opción', 'Cantidad']
                fig = px.pie(conteo, names='Opción', values='Cantidad', hole=0.4, title=f"Proporción: {pregunta_seleccionada_texto}")
                st.plotly_chart(fig, use_container_width=True)
            else:
                st.info("No hay suficientes datos válidos para generar una gráfica para esta pregunta.")
            
        elif tipo_pregunta == 'seleccion_multiple':
            serie_limpia = df_respuestas[columna_id].dropna().explode().astype(str)
            if not serie_limpia.empty:
                conteo = serie_limpia.value_counts().reset_index()
                conteo.columns = ['Opción', 'Cantidad']
                fig = px.bar(conteo, x='Opción', y='Cantidad', text_auto=True, title=f"Frecuencia: {pregunta_seleccionada_texto}")
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
            st.write("📝 Respuestas textuales proporcionadas:")
            respuestas_limpias = df_respuestas[[columna_id]].dropna().astype(str)
            st.dataframe(respuestas_limpias, use_container_width=True)
            
        else:
            st.info(f"Visualización genérica para el tipo: `{tipo_pregunta}`")
            respuestas_limpias = df_respuestas[[columna_id]].dropna().astype(str)
            st.dataframe(respuestas_limpias, use_container_width=True)
            
    else:
        st.info(f"Aún no hay respuestas registradas en la base de datos para la pregunta '{pregunta_seleccionada_texto}'. (ID buscado: {columna_id})")
        with st.expander("Ver columnas detectadas en la base de datos"):
            st.write(list(df_respuestas.columns))
else:
    st.warning("No se encontraron respuestas en la colección de Firestore.")
