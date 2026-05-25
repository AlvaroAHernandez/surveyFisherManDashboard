import streamlit as st
import firebase_admin
from firebase_admin import credentials, firestore
import pandas as pd
import json
import plotly.express as px
from pathlib import Path
from scipy.stats import chi2_contingency

BASE_DIR = Path(__file__).parent

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

db = None

def inicializar_firebase():
    global db
    try:
        if not firebase_admin._apps:
            cred = credentials.Certificate(
                BASE_DIR / "surver-fisherman-uabcs-firebase-adminsdk-fbsvc-5c73dae273.json"
            )
            firebase_admin.initialize_app(cred)
        db = firestore.client()
        return True
    except FileNotFoundError:
        return False
    except Exception:
        return False

@st.cache_data
def cargar_definicion_preguntas(ruta_archivo):
    ruta_completa = BASE_DIR / ruta_archivo if not Path(ruta_archivo).is_absolute() else ruta_archivo
    with open(ruta_completa, 'r', encoding='utf-8') as f:
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
    if db is None:
        return pd.DataFrame()
    try:
        docs = db.collection('survey_responses').stream()
        datos = []
        for doc in docs:
            d = doc.to_dict()
            if 'responses' in d and isinstance(d['responses'], dict):
                respuestas = d.pop('responses')
                d.update(respuestas)
            datos.append(d)
        return pd.DataFrame(datos) if datos else pd.DataFrame()
    except Exception:
        return pd.DataFrame()

@st.cache_data
def cargar_localidades():
    try:
        gdf = pd.read_csv(BASE_DIR / 'geopoint.csv')
        return gdf
    except FileNotFoundError:
        return pd.DataFrame()
    except Exception as e:
        return pd.DataFrame()

def renderizar_header():
    col1, col2, col3 = st.columns([1, 3, 1])

    with col1:
        try:
            st.image(str(BASE_DIR / 'logo_uabcs.png'), width=100)
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

    fig = px.pie(
        conteo, names='Opción', values='Cantidad',
        color_discrete_sequence=px.colors.sequential.Blues[::-1],
        hole=0.3
    )
    fig.update_traces(textposition='inside', textinfo='label+percent')
    fig.update_layout(height=350, showlegend=True, margin=dict(l=20, r=20, t=20, b=20))
    st.plotly_chart(fig, use_container_width=True)

    st.markdown("**Distribución:**")
    for _, row in conteo.iterrows():
        st.write(f"• {row['Opción']}: {row['Cantidad']} ({row['Porcentaje']}%)")

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

def visualizar_pregunta_escala(df, col_id, titulo):
    """Visualiza preguntas de escala (Likert)"""
    serie = df[col_id].dropna()

    if len(serie) == 0:
        st.info("📭 Sin datos disponibles")
        return

    conteo = serie.astype(str).value_counts().reset_index()
    conteo.columns = ['Nivel', 'Cantidad']
    conteo['Porcentaje'] = (conteo['Cantidad'] / conteo['Cantidad'].sum() * 100).round(1)

    color_map = {
        'Muy en desacuerdo': UABCS_COLORS['rojo'],
        'En desacuerdo': UABCS_COLORS['rojo_suave'],
        'Neutral': UABCS_COLORS['gris'],
        'De acuerdo': '#90EE90',
        'Muy de acuerdo': UABCS_COLORS['azul'],
        '1': UABCS_COLORS['rojo'],
        '2': UABCS_COLORS['rojo_suave'],
        '3': UABCS_COLORS['gris'],
        '4': '#90EE90',
        '5': UABCS_COLORS['azul']
    }

    fig = px.bar(
        conteo, y='Nivel', x='Cantidad', text_auto=True, orientation='h',
        color='Nivel',
        color_discrete_map={nivel: color_map.get(str(nivel), UABCS_COLORS['azul']) for nivel in conteo['Nivel']}
    )
    fig.update_layout(height=300, showlegend=False, margin=dict(l=20, r=20, t=20, b=20))
    st.plotly_chart(fig, use_container_width=True)

def visualizar_pregunta_grid(df, col_id, titulo):
    """Visualiza preguntas de grid/matriz"""
    serie = df[col_id].dropna()

    if len(serie) == 0:
        st.info("📭 Sin datos disponibles")
        return

    try:
        df_grid = pd.json_normalize(serie.apply(lambda x: x if isinstance(x, dict) else {}))
        if not df_grid.empty:
            fig = px.imshow(
                df_grid.T,
                color_continuous_scale='Blues',
                text_auto=True,
                labels=dict(color='Frecuencia')
            )
            fig.update_layout(height=400, margin=dict(l=20, r=20, t=20, b=20))
            st.plotly_chart(fig, use_container_width=True)
        else:
            st.info("Datos de grid no disponibles en el formato esperado")
    except:
        st.dataframe(serie.reset_index(drop=True), use_container_width=True)

def visualizar_pregunta_tabla(df, col_id, titulo):
    """Visualiza preguntas de tabla"""
    serie = df[col_id].dropna()

    if len(serie) == 0:
        st.info("📭 Sin datos disponibles")
        return

    try:
        df_tabla = pd.json_normalize(serie.apply(lambda x: x if isinstance(x, dict) else {}))
        if not df_tabla.empty:
            st.dataframe(df_tabla, use_container_width=True)
            st.caption(f"Total de filas: {len(df_tabla)}")
        else:
            st.dataframe(serie.reset_index(drop=True), use_container_width=True)
    except:
        st.dataframe(serie.reset_index(drop=True), use_container_width=True)

def crear_mapa_localidades(gdf, df_respuestas):
    """Crea un mapa interactivo con localidades usando Plotly"""
    if gdf.empty:
        st.warning("No hay datos geográficos disponibles")
        return

    conteo_respuestas = {}
    if 'Localidad' in df_respuestas.columns:
        conteo_respuestas = df_respuestas['Localidad'].value_counts().to_dict()

    gdf_mapa = gdf.copy()
    gdf_mapa['Respuestas'] = gdf_mapa['Localidad'].map(conteo_respuestas).fillna(0).astype(int)
    gdf_mapa['Porcentaje'] = (gdf_mapa['Respuestas'] / gdf_mapa['Respuestas'].sum() * 100).round(1)

    gdf_mapa['Hover'] = gdf_mapa.apply(
        lambda r: f"{r['Localidad']}<br>Encuestas: {r['Respuestas']}<br>% del total: {r['Porcentaje']}%",
        axis=1
    )

    fig = px.scatter_geo(
        gdf_mapa,
        lat='Latitud',
        lon='Longitud',
        size='Respuestas',
        hover_name='Localidad',
        custom_data=['Respuestas', 'Porcentaje'],
        size_max=50,
        title='Localidades de Encuesta - Baja California Sur<br>(Tamaño proporcional a número de respuestas)'
    )

    fig.update_geos(
        scope='americas',
        projection_type='mercator',
        showland=True,
        landcolor='rgb(243, 243, 243)',
        showocean=True,
        oceancolor='rgb(204, 229, 255)',
        center=dict(lon=-112, lat=25),
        projection_scale=4
    )

    fig.update_traces(
        marker=dict(
            color=UABCS_COLORS['azul'],
            opacity=0.7,
            line=dict(color=UABCS_COLORS['amarillo'], width=2),
            sizemode='diameter'
        ),
        hovertemplate='<b>%{hover_name}</b><br>Encuestas: %{customdata[0]}<br>% del total: %{customdata[1]:.1f}%<extra></extra>'
    )

    fig.update_layout(height=500, margin=dict(l=20, r=20, t=70, b=20))
    st.plotly_chart(fig, use_container_width=True)

def renderizar_tab_resumen(df_respuestas, gdf_localidades, cuestionario):
    st.markdown(f"<h2 style='color: {UABCS_COLORS['azul_marino']};'>Resumen Ejecutivo</h2>", unsafe_allow_html=True)

    col1, col2, col3, col4 = st.columns(4)

    with col1:
        st.metric("📊 Total de Encuestas", len(df_respuestas))

    with col2:
        localidades_con_datos = df_respuestas['Localidad'].nunique() if 'Localidad' in df_respuestas.columns else 0
        st.metric("📍 Localidades", f"{localidades_con_datos}/18")

    with col3:
        completitud = (df_respuestas.notna().sum().sum() / (len(df_respuestas) * len(df_respuestas.columns)) * 100) if len(df_respuestas) > 0 else 0
        st.metric("✅ Completitud", f"{completitud:.1f}%")

    with col4:
        st.metric("❓ Total Campos", len(df_respuestas.columns))

    st.markdown("---")

    col1, col2 = st.columns(2)

    with col1:
        st.markdown("**Respuestas por Localidad**")
        if 'Localidad' in df_respuestas.columns:
            conteo_loc = df_respuestas['Localidad'].value_counts().sort_values(ascending=True).tail(10)
            fig = px.barh(conteo_loc, x=conteo_loc.values, labels={'x': 'Cantidad', 'index': 'Localidad'},
                         color_discrete_sequence=[UABCS_COLORS['azul']])
            fig.update_layout(height=300, showlegend=False, margin=dict(l=20, r=20, t=20, b=20))
            st.plotly_chart(fig, use_container_width=True)

    with col2:
        st.markdown("**Distribución por Rango de Edad**")
        if '3.2' in df_respuestas.columns:
            conteo_edad = df_respuestas['3.2'].value_counts()
            fig = px.pie(conteo_edad, names=conteo_edad.index, values=conteo_edad.values,
                        color_discrete_sequence=px.colors.sequential.Blues[::-1], hole=0.3)
            fig.update_traces(textposition='inside', textinfo='label+percent')
            fig.update_layout(height=300, showlegend=True, margin=dict(l=20, r=20, t=20, b=20))
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

    if not inicializar_firebase():
        st.error("❌ Error al conectar con Firebase. Verifica que el archivo de credenciales existe.")
        return

    try:
        cuestionario = cargar_definicion_preguntas('json/survey.json')
    except FileNotFoundError:
        st.error("❌ No se encontró el archivo de definición de preguntas (json/survey.json)")
        return

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

    col_metric = st.sidebar.columns(1)[0]
    with col_metric:
        st.metric("Total de Encuestas", len(df_respuestas))

    if 'Localidad' in df_respuestas.columns:
        localidades_con_datos = df_respuestas['Localidad'].nunique()
        cobertura = (localidades_con_datos / 18) * 100
        st.sidebar.progress(cobertura / 100, text=f"Cobertura: {cobertura:.0f}% ({localidades_con_datos}/18)")

    df_filtrado = df_respuestas.copy()

    if filtros.get('localidad') and filtros['localidad'] != 'Todas' and 'Localidad' in df_filtrado.columns:
        df_filtrado = df_filtrado[df_filtrado['Localidad'] == filtros['localidad']]

    if filtros.get('edad') and filtros['edad'] != 'Todos' and '3.2' in df_filtrado.columns:
        df_filtrado = df_filtrado[df_filtrado['3.2'] == filtros['edad']]

    st.sidebar.caption(f"Filtradas: {len(df_filtrado)} encuestas")

    tabs = st.tabs(["📊 Resumen"] + [f"📋 {s['titulo']}" for s in cuestionario['secciones']] + ["🗺️ Mapa", "📈 Análisis Cruzado", "📊 Datos Crudos"])

    num_secciones = len(cuestionario['secciones'])
    tab_resumen = tabs[0]
    tab_secciones = tabs[1:num_secciones+1]
    tab_mapa = tabs[num_secciones + 1]
    tab_cruzado = tabs[num_secciones + 2]
    tab_crudos = tabs[num_secciones + 3]

    def renderizar_seccion(seccion_data, df_data):
        st.markdown(f"<h2 style='color: {UABCS_COLORS['azul_marino']};'>{seccion_data['titulo']}</h2>",
                   unsafe_allow_html=True)

        preguntas_validas = [p for p in seccion_data['preguntas'] if p['id'] in df_data.columns]

        i = 0
        while i < len(preguntas_validas):
            pregunta = preguntas_validas[i]
            tipo = pregunta['tipo']

            usar_dos_columnas = tipo in ['opcion_multiple', 'si_no']

            if usar_dos_columnas and i + 1 < len(preguntas_validas):
                siguiente_pregunta = preguntas_validas[i + 1]
                siguiente_tipo = siguiente_pregunta['tipo']

                if siguiente_tipo in ['opcion_multiple', 'si_no']:
                    col1, col2 = st.columns(2)

                    with col1:
                        st.markdown(crear_tarjeta_pregunta(pregunta['texto']), unsafe_allow_html=True)
                        visualizar_por_tipo(df_data, pregunta['id'], pregunta['texto'], tipo)

                    with col2:
                        st.markdown(crear_tarjeta_pregunta(siguiente_pregunta['texto']), unsafe_allow_html=True)
                        visualizar_por_tipo(df_data, siguiente_pregunta['id'], siguiente_pregunta['texto'], siguiente_tipo)

                    i += 2
                    continue

            st.markdown(crear_tarjeta_pregunta(pregunta['texto']), unsafe_allow_html=True)
            visualizar_por_tipo(df_data, pregunta['id'], pregunta['texto'], tipo)
            st.markdown("")
            i += 1

    def visualizar_por_tipo(df_data, col_id, titulo, tipo):
        if tipo in ['opcion_multiple', 'si_no']:
            visualizar_pregunta_opciones(df_data, col_id, titulo, {})
        elif tipo == 'seleccion_multiple':
            visualizar_pregunta_seleccion_multiple(df_data, col_id, titulo)
        elif tipo == 'numerico':
            visualizar_pregunta_numerica(df_data, col_id, titulo)
        elif tipo == 'escala_evaluacion':
            visualizar_pregunta_escala(df_data, col_id, titulo)
        elif tipo == 'grid_seleccion':
            visualizar_pregunta_grid(df_data, col_id, titulo)
        elif tipo in ['tabla', 'tabla_compleja']:
            visualizar_pregunta_tabla(df_data, col_id, titulo)
        elif tipo in ['texto_abierto', 'texto_libre', 'fecha']:
            visualizar_pregunta_texto(df_data, col_id, titulo)
        else:
            visualizar_pregunta_texto(df_data, col_id, titulo)

    for idx, seccion in enumerate(cuestionario['secciones']):
        with tab_secciones[idx]:
            renderizar_seccion(seccion, df_filtrado)

    with tab_resumen:
        renderizar_tab_resumen(df_filtrado, gdf_localidades, cuestionario)

    with tab_mapa:
        st.markdown(f"<h2 style='color: {UABCS_COLORS['azul_marino']};'>Distribución Geográfica</h2>",
                   unsafe_allow_html=True)
        crear_mapa_localidades(gdf_localidades, df_filtrado)

    with tab_cruzado:
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

                st.markdown("**Tabla de Contingencia:**")
                st.dataframe(tabla_cruce, use_container_width=True)

                try:
                    chi2, p_value, dof, expected = chi2_contingency(tabla_cruce)
                    col1, col2, col3 = st.columns(3)
                    with col1:
                        st.metric("Chi-Cuadrado", f"{chi2:.4f}")
                    with col2:
                        st.metric("P-value", f"{p_value:.4f}")
                    with col3:
                        sig = "Significativo" if p_value < 0.05 else "No significativo"
                        st.metric("Resultado (α=0.05)", sig)
                except:
                    pass

                if len(tabla_cruce) <= 10 and len(tabla_cruce.columns) <= 10:
                    fig = px.imshow(tabla_cruce, color_continuous_scale='Blues', text_auto=True)
                    st.plotly_chart(fig, use_container_width=True)
            else:
                st.info("No hay datos para cruzar estas preguntas")

    with tab_crudos:
        st.markdown(f"<h2 style='color: {UABCS_COLORS['azul_marino']};'>Datos Crudos</h2>",
                   unsafe_allow_html=True)

        st.markdown("""
        Aquí se muestran todas las respuestas sin procesar de las encuestas.
        Útil para auditoría de datos, validación y análisis externos.
        """)

        col1, col2 = st.columns([3, 1])

        with col2:
            formato_export = st.radio("Formato", ["DataFrame", "CSV"], horizontal=True)

        if len(df_filtrado) == 0:
            st.warning("⚠️ No hay datos que mostrar con los filtros actuales")
        else:
            st.markdown(f"**📊 Total de respuestas:** {len(df_filtrado)}")

            if formato_export == "DataFrame":
                st.dataframe(df_filtrado, use_container_width=True, height=500)
            else:
                csv = df_filtrado.to_csv(index=False, encoding='utf-8')
                st.download_button(
                    label="📥 Descargar CSV",
                    data=csv,
                    file_name="encuestas_pescadores.csv",
                    mime="text/csv"
                )
                st.dataframe(df_filtrado, use_container_width=True, height=500)

            st.markdown("---")
            st.markdown("**Estadísticas de Cobertura:**")

            cobertura_col1, cobertura_col2, cobertura_col3 = st.columns(3)

            with cobertura_col1:
                porcentaje_respuestas = (df_filtrado.notna().sum().sum() / (len(df_filtrado) * len(df_filtrado.columns)) * 100)
                st.metric("Completitud de Datos", f"{porcentaje_respuestas:.1f}%")

            with cobertura_col2:
                st.metric("Total de Campos", len(df_filtrado.columns))

            with cobertura_col3:
                st.metric("Total de Registros", len(df_filtrado))

if __name__ == "__main__":
    main()
