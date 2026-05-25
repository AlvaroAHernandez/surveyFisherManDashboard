import streamlit as st
import firebase_admin
from firebase_admin import credentials, firestore
import pandas as pd
import json
import plotly.graph_objects as go
import plotly.express as px
import numpy as np
from pathlib import Path

UABCS_COLORS = {
    "azul": "#009FD4",
    "azul_marino": "#00497E",
    "azul_profundo": "#002147",
    "azul_suave": "#E3F4FB",
    "amarillo": "#FFD100",
    "amarillo_suave": "#FFF8CC",
    "rojo": "#CC1E1E",
    "rojo_suave": "#FDECEC",
    "gris": "#4A5568",
    "blanco": "#FFFFFF",
    "negro": "#1A1A1A",
}

if not firebase_admin._apps:
    cred = credentials.Certificate("surver-fisherman-uabcs-firebase-adminsdk-fbsvc-5c73dae273.json")
    firebase_admin.initialize_app(cred)

db = firestore.client()

@st.cache_data
def cargar_definicion_preguntas(ruta_archivo):
    with open(ruta_archivo, 'r', encoding='utf-8') as f:
        data = json.load(f)

    secciones_procesadas = []
    for seccion in data.get('cuestionario', {}).get('secciones', []):
        seccion_dict = {
            'id': seccion.get('id_seccion'),
            'titulo': seccion.get('titulo'),
            'preguntas': extraer_preguntas_recursivas(seccion.get('preguntas', []))
        }
        secciones_procesadas.append(seccion_dict)

    return {
        'titulo': data.get('cuestionario', {}).get('titulo'),
        'descripcion': data.get('cuestionario', {}).get('descripcion'),
        'secciones': secciones_procesadas
    }

def extraer_preguntas_recursivas(lista, padre_id=""):
    preguntas = []
    for item in lista:
        if 'id' in item and 'texto' in item:
            pregunta = {
                'id': item['id'],
                'texto': item['texto'],
                'tipo': item.get('tipo', 'texto_abierto'),
                'opciones': item.get('opciones', []),
                'sub_preguntas': extraer_preguntas_recursivas(item.get('sub_preguntas', []), item['id'])
            }
            preguntas.append(pregunta)

        if 'preguntas' in item and isinstance(item.get('preguntas'), list):
            preguntas.extend(extraer_preguntas_recursivas(item['preguntas'], padre_id))

    return preguntas

@st.cache_data(ttl=300)
def cargar_respuestas_encuestas():
    docs = db.collection('survey_responses').stream()
    datos = []
    for doc in docs:
        d = doc.to_dict()
        if 'responses' in d and isinstance(d['responses'], dict):
            respuestas = d.pop('responses')
            d.update(respuestas)
        datos.append(d)
    return pd.DataFrame(datos) if datos else pd.DataFrame()

@st.cache_data
def cargar_localidades():
    try:
        gdf = pd.read_csv('geopoint.csv')
        return gdf
    except:
        return pd.DataFrame()

def renderizar_header():
    col1, col2, col3 = st.columns([1, 3, 1])

    with col1:
        try:
            st.image('logo_uabcs.png', width=100)
        except:
            st.write("🏫")

    with col2:
        st.markdown(f"""
        <h1 style='text-align: center; color: {UABCS_COLORS["azul"]};'>
            📊 Dashboard de Encuestas Pesqueras
        </h1>
        <p style='text-align: center; color: {UABCS_COLORS["gris"]}; font-size: 14px;'>
            <em>Inclusión Financiera y Tecnologías en Sector Pesquero BCS</em><br>
            <strong>Universidad Autónoma de Baja California Sur</strong>
        </p>
        """, unsafe_allow_html=True)

    with col3:
        st.write("")

    st.markdown(f"<hr style='border: 2px solid {UABCS_COLORS['amarillo']};'>", unsafe_allow_html=True)

def crear_tarjeta_pregunta(titulo, icono="📊"):
    return f"<div style='padding: 15px; background-color: {UABCS_COLORS['azul_suave']}; border-left: 4px solid {UABCS_COLORS['azul']}; border-radius: 5px;'><strong>{icono} {titulo}</strong></div>"

def visualizar_pregunta_opciones(df, col_id, titulo, pregunta_info=None):
    """Visualiza preguntas de opción múltiple o si/no"""
    serie = df[col_id].dropna()

    if len(serie) == 0:
        st.info("📭 Sin datos disponibles")
        return

    conteo = serie.astype(str).value_counts().reset_index()
    conteo.columns = ['Opción', 'Cantidad']
    conteo['Porcentaje'] = (conteo['Cantidad'] / conteo['Cantidad'].sum() * 100).round(1)

    col1, col2 = st.columns([1.5, 1])

    with col1:
        fig = px.pie(
            conteo, names='Opción', values='Cantidad',
            color_discrete_sequence=px.colors.sequential.Blues[::-1],
            hole=0.3
        )
        fig.update_traces(textposition='inside', textinfo='label+percent')
        fig.update_layout(height=350, showlegend=True, margin=dict(l=20, r=20, t=20, b=20))
        st.plotly_chart(fig, use_container_width=True)

    with col2:
        st.markdown("**Estadísticas**")
        st_cols = st.columns(2)
        for i, (_, row) in enumerate(conteo.iterrows()):
            with st_cols[i % 2]:
                st.metric(str(row['Opción'])[:20], f"{row['Cantidad']} ({row['Porcentaje']}%)")

def visualizar_pregunta_seleccion_multiple(df, col_id, titulo):
    """Visualiza preguntas de selección múltiple"""
    serie = df[col_id].dropna()

    if len(serie) == 0:
        st.info("📭 Sin datos disponibles")
        return

    try:
        serie_exploded = serie.explode()
    except:
        serie_exploded = serie

    serie_exploded = serie_exploded.astype(str)
    conteo = serie_exploded.value_counts().reset_index()
    conteo.columns = ['Opción', 'Cantidad']
    conteo = conteo.sort_values('Cantidad', ascending=True).tail(15)

    fig = px.bar(conteo, y='Opción', x='Cantidad', text_auto=True, orientation='h',
                color='Cantidad', color_continuous_scale='Blues')
    fig.update_layout(height=400, showlegend=False, margin=dict(l=20, r=20, t=20, b=20))
    st.plotly_chart(fig, use_container_width=True)

def visualizar_pregunta_numerica(df, col_id, titulo):
    """Visualiza preguntas numéricas con métricas y distribución"""
    serie = pd.to_numeric(df[col_id], errors='coerce').dropna()

    if len(serie) == 0:
        st.info("📭 Sin datos disponibles")
        return

    col1, col2, col3, col4 = st.columns(4)

    with col1:
        st.metric("📊 Promedio", f"{serie.mean():.2f}", delta=None)
    with col2:
        st.metric("📈 Máximo", f"{serie.max():.0f}", delta=None)
    with col3:
        st.metric("📉 Mínimo", f"{serie.min():.0f}", delta=None)
    with col4:
        st.metric("👥 Respuestas", f"{len(serie)}", delta=None)

    st.markdown("**Distribución**")
    fig = px.histogram(
        x=serie, nbins=20,
        color_discrete_sequence=[UABCS_COLORS['azul']]
    )
    fig.update_layout(
        xaxis_title="Valor",
        yaxis_title="Frecuencia",
        height=350,
        showlegend=False,
        margin=dict(l=20, r=20, t=20, b=20)
    )
    st.plotly_chart(fig, use_container_width=True)

def visualizar_pregunta_texto(df, col_id, titulo):
    """Visualiza preguntas de texto abierto"""
    respuestas = df[col_id].dropna().astype(str)

    if len(respuestas) == 0:
        st.info("📭 Sin datos disponibles")
        return

    st.markdown(f"**Total de respuestas:** {len(respuestas)}")

    if len(respuestas) <= 10:
        for i, resp in enumerate(respuestas.head(10), 1):
            st.caption(f"{i}. {resp[:150]}...")
    else:
        with st.expander(f"Ver {len(respuestas)} respuestas"):
            st.dataframe(respuestas.reset_index(drop=True), use_container_width=True)

def crear_mapa_localidades(gdf, df_respuestas):
    """Crea un mapa interactivo con localidades usando Plotly"""
    if gdf.empty:
        st.warning("No hay datos geográficos disponibles")
        return

    fig = px.scatter_geo(
        gdf,
        lat='Latitud',
        lon='Longitud',
        hover_name='Localidad',
        size_max=50,
        zoom=6,
        title='Localidades de Encuesta - Baja California Sur'
    )

    fig.update_geos(
        scope='americas',
        projection_type='mercator',
        showland=True,
        landcolor='rgb(243, 243, 243)',
        showocean=True,
        oceancolor='rgb(204, 229, 255)',
    )

    fig.update_traces(
        marker=dict(
            size=12,
            color=UABCS_COLORS['azul'],
            opacity=0.8,
            line=dict(color=UABCS_COLORS['amarillo'], width=2)
        )
    )

    fig.update_layout(height=500, margin=dict(l=20, r=20, t=50, b=20))
    st.plotly_chart(fig, use_container_width=True)

def agregar_estilos():
    st.markdown(f"""
    <style>
    .stTabs [data-baseweb="tab-list"] {{
        background-color: {UABCS_COLORS['azul_suave']};
        border-bottom: 3px solid {UABCS_COLORS['azul']};
    }}

    .stTabs [data-baseweb="tab"] {{
        color: {UABCS_COLORS['azul_marino']};
        font-weight: 600;
    }}

    .stMetric {{
        background-color: {UABCS_COLORS['azul_suave']};
        padding: 10px;
        border-radius: 5px;
        border-left: 4px solid {UABCS_COLORS['amarillo']};
    }}

    h2, h3 {{
        color: {UABCS_COLORS['azul_marino']};
    }}
    </style>
    """, unsafe_allow_html=True)

def main():
    st.set_page_config(page_title="Dashboard Pesquero UABCS", layout="wide", initial_sidebar_state="expanded")

    agregar_estilos()
    renderizar_header()

    cuestionario = cargar_definicion_preguntas('json/survey.json')
    df_respuestas = cargar_respuestas_encuestas()
    gdf_localidades = cargar_localidades()

    if df_respuestas.empty:
        st.warning("⚠️ No hay datos disponibles en Firestore.")
        return

    st.sidebar.markdown(f"<h3 style='color: {UABCS_COLORS['azul']};'>🔍 Filtros</h3>", unsafe_allow_html=True)

    filtros = {}
    if 'Localidad' in df_respuestas.columns:
        localidades = ['Todas'] + sorted(df_respuestas['Localidad'].dropna().unique().tolist())
        filtros['localidad'] = st.sidebar.selectbox("Localidad", localidades)

    if '3.2' in df_respuestas.columns:
        rangos_edad = ['Todos'] + sorted(df_respuestas['3.2'].dropna().unique().tolist())
        filtros['edad'] = st.sidebar.selectbox("Rango de Edad", rangos_edad)

    st.sidebar.markdown(f"<hr style='border: 1px solid {UABCS_COLORS['amarillo']};'>", unsafe_allow_html=True)
    st.sidebar.markdown(f"<p style='font-size: 12px; color: {UABCS_COLORS['gris']};'>"
                       f"📊 Encuestas: {len(df_respuestas)}</p>", unsafe_allow_html=True)

    df_filtrado = df_respuestas.copy()

    if filtros.get('localidad') and filtros['localidad'] != 'Todas':
        df_filtrado = df_filtrado[df_filtrado.get('Localidad') == filtros['localidad']]

    if filtros.get('edad') and filtros['edad'] != 'Todos':
        df_filtrado = df_filtrado[df_filtrado.get('3.2') == filtros['edad']]

    tabs = st.tabs([f"📋 {s['titulo']}" for s in cuestionario['secciones']] + ["🗺️ Mapa", "📈 Análisis Cruzado", "📊 Datos Crudos"])

    for idx, seccion in enumerate(cuestionario['secciones']):
        with tabs[idx]:
            st.markdown(f"<h2 style='color: {UABCS_COLORS['azul_marino']};'>{seccion['titulo']}</h2>",
                       unsafe_allow_html=True)

            for pregunta in seccion['preguntas']:
                col_id = pregunta['id']

                if col_id not in df_filtrado.columns:
                    continue

                with st.container():
                    st.markdown(crear_tarjeta_pregunta(pregunta['texto']), unsafe_allow_html=True)

                    tipo = pregunta['tipo']

                    if tipo in ['opcion_multiple', 'si_no']:
                        visualizar_pregunta_opciones(df_filtrado, col_id, pregunta['texto'], pregunta)
                    elif tipo == 'seleccion_multiple':
                        visualizar_pregunta_seleccion_multiple(df_filtrado, col_id, pregunta['texto'])
                    elif tipo == 'numerico':
                        visualizar_pregunta_numerica(df_filtrado, col_id, pregunta['texto'])
                    elif tipo in ['texto_abierto', 'texto_libre', 'fecha']:
                        visualizar_pregunta_texto(df_filtrado, col_id, pregunta['texto'])
                    else:
                        visualizar_pregunta_texto(df_filtrado, col_id, pregunta['texto'])

                    st.markdown("")

    with tabs[-2]:
        st.markdown(f"<h2 style='color: {UABCS_COLORS['azul_marino']};'>Distribución Geográfica</h2>",
                   unsafe_allow_html=True)
        crear_mapa_localidades(gdf_localidades, df_filtrado)

    with tabs[-1]:
        st.markdown(f"<h2 style='color: {UABCS_COLORS['azul_marino']};'>Análisis de Correlaciones</h2>",
                   unsafe_allow_html=True)

        st.markdown("**Selecciona dos preguntas para cruzar información:**")
        col1, col2 = st.columns(2)

        todas_preguntas = []
        for s in cuestionario['secciones']:
            for p in s['preguntas']:
                todas_preguntas.append((p['id'], p['texto']))

        opciones_preg = {f"{p[0]} - {p[1]}": p[0] for p in todas_preguntas}

        with col1:
            preg1 = st.selectbox("Primera pregunta", list(opciones_preg.keys()), key='preg1')

        with col2:
            preg2 = st.selectbox("Segunda pregunta", list(opciones_preg.keys()), key='preg2')

        id_preg1 = opciones_preg[preg1]
        id_preg2 = opciones_preg[preg2]

        if id_preg1 in df_filtrado.columns and id_preg2 in df_filtrado.columns:
            df_cruce = df_filtrado[[id_preg1, id_preg2]].dropna()

            if len(df_cruce) > 0:
                tabla_cruce = pd.crosstab(df_cruce[id_preg1], df_cruce[id_preg2])
                st.dataframe(tabla_cruce, use_container_width=True)

                if len(tabla_cruce) <= 10 and len(tabla_cruce.columns) <= 10:
                    fig = px.imshow(tabla_cruce, color_continuous_scale='Blues', text_auto=True)
                    st.plotly_chart(fig, use_container_width=True)
            else:
                st.info("No hay datos para cruzar estas preguntas")

if __name__ == "__main__":
    main()
