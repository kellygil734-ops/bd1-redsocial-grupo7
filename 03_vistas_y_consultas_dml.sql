/*
==============================================================================
PROYECTO : RED SOCIAL ESTUDIANTIL PASCUALINA (NETSICAU / PARCHEU)
ARCHIVO  : 03_vistas_y_consultas_dml.sql      (SCRIPT FINAL DE LA TAREA 5)
SGBD     : PostgreSQL 16 (pgAdmin 4 -> Query Tool)
CONTIENE : PARTE A  -> 4 vistas (VIEWS), cada una con su consulta de uso
           PARTE B  -> 7 consultas DML que responden preguntas de negocio
==============================================================================

ANTES DE EJECUTAR
  1. 01_ddl_postgresql.sql   (crea las 15 tablas)
  2. 02_datos_prueba.sql     (carga datos ficticios)
  3. Este archivo. Conviene ejecutarlo por bloques (seleccionar un bloque y F5)
     para poder tomar la captura de pantalla de cada resultado.

CONVENCIÓN DE ALIAS APLICADA EN TODO EL SCRIPT
  (Nota: es la convención usada por el equipo; si el libro "DML o cómo
  conversar con las bases de datos" define otra, se ajusta aquí.)
  1. Alias de TABLA: abreviatura corta en minúscula (e = estudiante,
     p = publicacion, c = comentario, r = reaccion, g = grupo,
     mg = miembro_grupo, ei = estudiante_interes, i = interes,
     af = archivo_compartido, ev = evento, te = tipo_evento,
     ae = asistencia_evento, rc = reporte_contenido).
  2. Alias de COLUMNA CALCULADA: siempre con la palabra AS, en minúsculas y
     snake_case, sin tildes, sin espacios y sin comillas.
  3. El alias empieza con el prefijo de lo que calcula:
        total_...       -> conteos (COUNT)
        promedio_...    -> promedios (AVG)
        porcentaje_...  -> porcentajes
        nombre_...      -> textos armados (concatenación)
        lista_...       -> listas de valores (STRING_AGG)
  4. El alias describe el negocio, no la función (total_miembros, no count1).
==============================================================================
*/


/* ############################################################################
   PARTE A. VISTAS
   Una vista es una consulta guardada con nombre. No almacena datos: se
   recalcula cada vez que se consulta, así siempre muestra información al día.
   Sirve para reutilizar consultas complejas con un simple SELECT.
   ########################################################################### */

-- Limpieza para poder ejecutar el script varias veces
DROP VIEW IF EXISTS vw_asistencia_evento;
DROP VIEW IF EXISTS vw_resumen_grupo;
DROP VIEW IF EXISTS vw_actividad_publicacion;
DROP VIEW IF EXISTS vw_perfil_estudiante;


/* ----------------------------------------------------------------------------
   VISTA 1: vw_perfil_estudiante
   OBJETIVO : Consolidar en una sola fila el perfil de cada estudiante: sus
              datos académicos, la lista de sus intereses y cuánto participa
              (grupos y publicaciones).
   UTILIDAD : Facilita buscar mentores o compañeros con intereses similares
              sin repetir 3 o 4 JOIN cada vez.
   TABLAS   : estudiante, estudiante_interes, interes, miembro_grupo,
              publicacion.
   NOTA     : Se usan subconsultas por cada dato calculado para que los conteos
              no se multipliquen entre sí (problema típico al hacer varios JOIN
              a tablas hijas a la vez).
---------------------------------------------------------------------------- */
CREATE VIEW vw_perfil_estudiante AS
SELECT
    e.id_estudiante,
    e.nombre || ' ' || e.apellido AS nombre_completo,
    e.carrera,
    e.semestre,
    -- Lista de intereses del estudiante separada por comas (o aviso si no tiene)
    COALESCE(
        (SELECT STRING_AGG(i.nombre, ', ' ORDER BY i.nombre)
           FROM estudiante_interes ei
           JOIN interes i ON i.id_interes = ei.id_interes
          WHERE ei.id_estudiante = e.id_estudiante),
        'Sin intereses registrados') AS lista_intereses,
    -- Cantidad de grupos a los que pertenece
    (SELECT COUNT(*)
       FROM miembro_grupo mg
      WHERE mg.id_estudiante = e.id_estudiante) AS total_grupos,
    -- Cantidad de publicaciones que ha escrito
    (SELECT COUNT(*)
       FROM publicacion p
      WHERE p.id_estudiante = e.id_estudiante) AS total_publicaciones
FROM estudiante e;

-- 1.a Consulta a la vista: contenido completo ordenado por semestre
SELECT *
FROM vw_perfil_estudiante
ORDER BY semestre DESC, nombre_completo;

-- 1.b Consulta analítica sobre la vista: estudiantes avanzados (semestre >= 7)
--     interesados en programación competitiva, posibles mentores.
SELECT nombre_completo, carrera, semestre, lista_intereses
FROM vw_perfil_estudiante
WHERE semestre >= 7
  AND lista_intereses LIKE '%Programación competitiva%'
ORDER BY semestre DESC;


/* ----------------------------------------------------------------------------
   VISTA 2: vw_actividad_publicacion
   OBJETIVO : Mostrar cada publicación con su autor y cuánta interacción ha
              recibido (comentarios y reacciones).
   UTILIDAD : Base para analítica del muro: publicaciones más populares,
              autores con mejor alcance, contenido sin respuesta.
   TABLAS   : publicacion, estudiante, comentario, reaccion.
   NOTA     : Los conteos se calculan primero por separado (tablas derivadas
              c y r) y luego se unen con LEFT JOIN; así una publicación sin
              comentarios o sin reacciones sigue apareciendo, con 0.
---------------------------------------------------------------------------- */
CREATE VIEW vw_actividad_publicacion AS
SELECT
    p.id_publicacion,
    e.nombre || ' ' || e.apellido                   AS nombre_autor,
    p.fecha_publicacion,
    LEFT(p.contenido, 60)                           AS extracto_contenido,
    COALESCE(c.total_comentarios, 0)                AS total_comentarios,
    COALESCE(r.total_reacciones, 0)                 AS total_reacciones,
    COALESCE(c.total_comentarios, 0)
      + COALESCE(r.total_reacciones, 0)             AS total_interacciones
FROM publicacion p
JOIN estudiante e ON e.id_estudiante = p.id_estudiante
LEFT JOIN (SELECT id_publicacion, COUNT(*) AS total_comentarios
             FROM comentario
            GROUP BY id_publicacion) c ON c.id_publicacion = p.id_publicacion
LEFT JOIN (SELECT id_publicacion, COUNT(*) AS total_reacciones
             FROM reaccion
            GROUP BY id_publicacion) r ON r.id_publicacion = p.id_publicacion;

-- 2.a Consulta a la vista: las 5 publicaciones con más interacción
SELECT *
FROM vw_actividad_publicacion
ORDER BY total_interacciones DESC, id_publicacion
LIMIT 5;

-- 2.b Consulta analítica: promedio de interacciones por autor
--     (solo autores con 2 o más publicaciones).
SELECT nombre_autor,
       COUNT(*)                                  AS total_publicaciones,
       ROUND(AVG(total_interacciones), 1)        AS promedio_interacciones
FROM vw_actividad_publicacion
GROUP BY nombre_autor
HAVING COUNT(*) >= 2
ORDER BY promedio_interacciones DESC, nombre_autor;


/* ----------------------------------------------------------------------------
   VISTA 3: vw_resumen_grupo
   OBJETIVO : Resumir cada grupo: cuántos miembros tiene, quién lo administra,
              cuántos archivos se han compartido y cuándo fue el último.
   UTILIDAD : Permite a la plataforma recomendar grupos activos y detectar
              grupos abandonados (sin archivos o con pocos miembros).
   TABLAS   : grupo, miembro_grupo, estudiante, archivo_compartido.
---------------------------------------------------------------------------- */
CREATE VIEW vw_resumen_grupo AS
SELECT
    g.id_grupo,
    g.nombre                                         AS nombre_grupo,
    g.fecha_creacion,
    COALESCE(m.total_miembros, 0)                    AS total_miembros,
    COALESCE(a.lista_administradores, 'Sin administrador') AS lista_administradores,
    COALESCE(f.total_archivos, 0)                    AS total_archivos,
    f.fecha_ultimo_archivo
FROM grupo g
LEFT JOIN (SELECT id_grupo, COUNT(*) AS total_miembros
             FROM miembro_grupo
            GROUP BY id_grupo) m ON m.id_grupo = g.id_grupo
LEFT JOIN (SELECT mg.id_grupo,
                  STRING_AGG(e.nombre || ' ' || e.apellido, ', ') AS lista_administradores
             FROM miembro_grupo mg
             JOIN estudiante e ON e.id_estudiante = mg.id_estudiante
            WHERE mg.rol = 'Administrador'
            GROUP BY mg.id_grupo) a ON a.id_grupo = g.id_grupo
LEFT JOIN (SELECT id_grupo,
                  COUNT(*)           AS total_archivos,
                  MAX(fecha_subida)  AS fecha_ultimo_archivo
             FROM archivo_compartido
            GROUP BY id_grupo) f ON f.id_grupo = g.id_grupo;

-- 3.a Consulta a la vista: todos los grupos, del más grande al más pequeño
SELECT *
FROM vw_resumen_grupo
ORDER BY total_miembros DESC, nombre_grupo;

-- 3.b Consulta analítica: grupos con 4 o más miembros pero con poca actividad
--     de archivos (máximo 1 archivo compartido); candidatos a recibir una
--     sugerencia de la plataforma para que compartan más material.
SELECT nombre_grupo, total_miembros, total_archivos, lista_administradores
FROM vw_resumen_grupo
WHERE total_miembros >= 4
  AND total_archivos <= 1
ORDER BY total_miembros DESC;


/* ----------------------------------------------------------------------------
   VISTA 4: vw_asistencia_evento
   OBJETIVO : Resumir cada evento: su tipo, cuántas personas se registraron y
              cuántas asistieron, faltaron o cancelaron, con el porcentaje de
              asistencia efectiva.
   UTILIDAD : Medir qué eventos funcionan y planear aforo y recursos.
   TABLAS   : evento, tipo_evento, asistencia_evento.
   NOTA     : porcentaje_asistencia = asistieron / (asistieron + ausentes).
              Es NULL en eventos futuros porque aún no se sabe quién asistirá
              (NULLIF evita dividir entre cero).
---------------------------------------------------------------------------- */
CREATE VIEW vw_asistencia_evento AS
SELECT
    ev.id_evento,
    ev.nombre                                                    AS nombre_evento,
    te.nombre                                                    AS nombre_tipo_evento,
    ev.fecha,
    COUNT(ae.id_asistencia)                                      AS total_registros,
    COUNT(*) FILTER (WHERE ae.estado = 'Asistio')                AS total_asistieron,
    COUNT(*) FILTER (WHERE ae.estado = 'Ausente')                AS total_ausentes,
    COUNT(*) FILTER (WHERE ae.estado = 'Cancelado')              AS total_cancelados,
    COUNT(*) FILTER (WHERE ae.estado = 'Inscrito')               AS total_inscritos_pendientes,
    ROUND(100.0 * COUNT(*) FILTER (WHERE ae.estado = 'Asistio')
          / NULLIF(COUNT(*) FILTER (WHERE ae.estado IN ('Asistio','Ausente')), 0), 1)
                                                                 AS porcentaje_asistencia
FROM evento ev
JOIN tipo_evento te             ON te.id_tipo_evento = ev.id_tipo_evento
LEFT JOIN asistencia_evento ae  ON ae.id_evento = ev.id_evento
GROUP BY ev.id_evento, ev.nombre, te.nombre, ev.fecha;

-- 4.a Consulta a la vista: todos los eventos en orden cronológico
SELECT *
FROM vw_asistencia_evento
ORDER BY fecha;

-- 4.b Consulta analítica: eventos ya realizados con asistencia efectiva
--     menor al 75 % (posibles eventos a mejorar).
SELECT nombre_evento, nombre_tipo_evento, total_asistieron, total_ausentes,
       porcentaje_asistencia
FROM vw_asistencia_evento
WHERE porcentaje_asistencia < 75
ORDER BY porcentaje_asistencia;



/* ############################################################################
   PARTE B. CONSULTAS DML
   Cada consulta responde una pregunta de negocio de la red social.
   ########################################################################### */


/* ----------------------------------------------------------------------------
   CONSULTA 1
   PREGUNTA DE NEGOCIO: ¿Cuántos estudiantes tiene cada interés y qué
                        porcentaje de la comunidad representa?
   Sirve para saber qué temas mueven más a la comunidad (por ejemplo, cuántos
   estudiantes están interesados en programación competitiva).
   TABLAS : interes (i), estudiante_interes (ei)
   CLÁUSULAS: LEFT JOIN, COUNT, GROUP BY, subconsulta escalar, ROUND, ORDER BY.
   ALIAS  : total_estudiantes y porcentaje_estudiantes (calculados).
---------------------------------------------------------------------------- */
SELECT
    i.nombre                                   AS interes,
    COUNT(ei.id_estudiante)                    AS total_estudiantes,
    ROUND(100.0 * COUNT(ei.id_estudiante)
          / (SELECT COUNT(*) FROM estudiante), 1) AS porcentaje_estudiantes
FROM interes i
LEFT JOIN estudiante_interes ei ON ei.id_interes = i.id_interes
GROUP BY i.id_interes, i.nombre
ORDER BY total_estudiantes DESC, interes;


/* ----------------------------------------------------------------------------
   CONSULTA 2
   PREGUNTA DE NEGOCIO: ¿Qué estudiantes de semestres avanzados (7 o más)
                        pueden ser mentores, y a cuántos estudiantes de
                        primeros semestres (4 o menos) podrían ayudar por
                        compartir un interés?
   Responde a "conectar con compañeros de cursos avanzados que ofrezcan
   mentoría".
   TABLAS : estudiante (m = mentor, a = aprendiz), estudiante_interes
            (em, ea), interes (i)
   CLÁUSULAS: autounión de estudiante, JOIN múltiple, WHERE, GROUP BY, HAVING.
   ALIAS  : nombre_mentor, total_aprendices.
---------------------------------------------------------------------------- */
SELECT
    m.nombre || ' ' || m.apellido AS nombre_mentor,
    m.semestre                    AS semestre_mentor,
    i.nombre                      AS interes_compartido,
    COUNT(a.id_estudiante)        AS total_aprendices
FROM estudiante m
JOIN estudiante_interes em ON em.id_estudiante = m.id_estudiante
JOIN interes i             ON i.id_interes     = em.id_interes
JOIN estudiante_interes ea ON ea.id_interes    = em.id_interes
JOIN estudiante a          ON a.id_estudiante  = ea.id_estudiante
WHERE m.semestre >= 7
  AND a.semestre <= 4
GROUP BY m.id_estudiante, m.nombre, m.apellido, m.semestre, i.nombre
HAVING COUNT(a.id_estudiante) >= 2
ORDER BY total_aprendices DESC, nombre_mentor, interes_compartido;


/* ----------------------------------------------------------------------------
   CONSULTA 3
   PREGUNTA DE NEGOCIO: ¿Qué estudiantes reciben más reacciones en sus
                        publicaciones y qué tipo de reacción predomina?
   Ayuda a identificar a los creadores de contenido más valorados.
   TABLAS : estudiante (e), publicacion (p), reaccion (r)
   CLÁUSULAS: JOIN, COUNT(*) FILTER, GROUP BY, HAVING, ORDER BY.
   ALIAS  : nombre_autor, total_reacciones, total_me_gusta, total_me_encanta,
            total_me_divierte.
---------------------------------------------------------------------------- */
SELECT
    e.nombre || ' ' || e.apellido                    AS nombre_autor,
    COUNT(*)                                          AS total_reacciones,
    COUNT(*) FILTER (WHERE r.tipo = 'Me gusta')       AS total_me_gusta,
    COUNT(*) FILTER (WHERE r.tipo = 'Me encanta')     AS total_me_encanta,
    COUNT(*) FILTER (WHERE r.tipo = 'Me divierte')    AS total_me_divierte
FROM estudiante e
JOIN publicacion p ON p.id_estudiante  = e.id_estudiante
JOIN reaccion r    ON r.id_publicacion = p.id_publicacion
GROUP BY e.id_estudiante, e.nombre, e.apellido
HAVING COUNT(*) >= 3
ORDER BY total_reacciones DESC, nombre_autor;


/* ----------------------------------------------------------------------------
   CONSULTA 4
   PREGUNTA DE NEGOCIO: ¿Qué tan grande y qué tan activo es cada grupo?
                        (miembros, archivos compartidos y clasificación por
                        tamaño)
   TABLAS : grupo (g), miembro_grupo (mg), archivo_compartido (af)
   CLÁUSULAS: dos LEFT JOIN, COUNT(DISTINCT), CASE, GROUP BY, ORDER BY.
   NOTA   : al unir miembros y archivos a la vez, las filas se multiplican;
            COUNT(DISTINCT ...) evita contar doble.
   ALIAS  : total_miembros, total_archivos, tamano_grupo.
---------------------------------------------------------------------------- */
SELECT
    g.nombre                              AS nombre_grupo,
    COUNT(DISTINCT mg.id_estudiante)      AS total_miembros,
    COUNT(DISTINCT af.id_archivo)         AS total_archivos,
    CASE
        WHEN COUNT(DISTINCT mg.id_estudiante) >= 7 THEN 'Grande'
        WHEN COUNT(DISTINCT mg.id_estudiante) >= 4 THEN 'Mediano'
        ELSE 'Pequeño'
    END                                   AS tamano_grupo
FROM grupo g
LEFT JOIN miembro_grupo mg       ON mg.id_grupo = g.id_grupo
LEFT JOIN archivo_compartido af  ON af.id_grupo = g.id_grupo
GROUP BY g.id_grupo, g.nombre
ORDER BY total_miembros DESC, nombre_grupo;


/* ----------------------------------------------------------------------------
   CONSULTA 5
   PREGUNTA DE NEGOCIO: ¿Qué tipo de evento tiene mejor asistencia efectiva?
   Solo se cuentan las personas cuyo registro ya se cerró (Asistio o Ausente).
   TABLAS : tipo_evento (te), evento (ev), asistencia_evento (ae)
   CLÁUSULAS: JOIN, WHERE, COUNT(DISTINCT), COUNT FILTER, ROUND, GROUP BY.
   ALIAS  : total_eventos, total_asistieron, total_ausentes,
            porcentaje_asistencia.
---------------------------------------------------------------------------- */
SELECT
    te.nombre                                           AS tipo_evento,
    COUNT(DISTINCT ev.id_evento)                        AS total_eventos,
    COUNT(*) FILTER (WHERE ae.estado = 'Asistio')       AS total_asistieron,
    COUNT(*) FILTER (WHERE ae.estado = 'Ausente')       AS total_ausentes,
    ROUND(100.0 * COUNT(*) FILTER (WHERE ae.estado = 'Asistio') / COUNT(*), 1)
                                                        AS porcentaje_asistencia
FROM tipo_evento te
JOIN evento ev            ON ev.id_tipo_evento = te.id_tipo_evento
JOIN asistencia_evento ae ON ae.id_evento      = ev.id_evento
WHERE ae.estado IN ('Asistio', 'Ausente')
GROUP BY te.id_tipo_evento, te.nombre
ORDER BY porcentaje_asistencia DESC;


/* ----------------------------------------------------------------------------
   CONSULTA 6
   PREGUNTA DE NEGOCIO: ¿Quiénes son los 10 estudiantes más activos de la
                        plataforma, sumando publicaciones, comentarios y
                        reacciones?
   TABLAS : estudiante (e) y una CTE (actividad) que une publicacion,
            comentario y reaccion con UNION ALL.
   CLÁUSULAS: WITH (CTE), UNION ALL, LEFT JOIN, COUNT FILTER, RANK() OVER
              (función de ventana), GROUP BY, LIMIT.
   ALIAS  : posicion, nombre_estudiante, total_publicaciones,
            total_comentarios, total_reacciones, total_acciones.
---------------------------------------------------------------------------- */
WITH actividad AS (
    SELECT id_estudiante, 'publicacion' AS tipo_accion FROM publicacion
    UNION ALL
    SELECT id_estudiante, 'comentario'  AS tipo_accion FROM comentario
    UNION ALL
    SELECT id_estudiante, 'reaccion'    AS tipo_accion FROM reaccion
)
SELECT
    RANK() OVER (ORDER BY COUNT(a.tipo_accion) DESC)         AS posicion,
    e.nombre || ' ' || e.apellido                             AS nombre_estudiante,
    COUNT(*) FILTER (WHERE a.tipo_accion = 'publicacion')     AS total_publicaciones,
    COUNT(*) FILTER (WHERE a.tipo_accion = 'comentario')      AS total_comentarios,
    COUNT(*) FILTER (WHERE a.tipo_accion = 'reaccion')        AS total_reacciones,
    COUNT(a.tipo_accion)                                      AS total_acciones
FROM estudiante e
LEFT JOIN actividad a ON a.id_estudiante = e.id_estudiante
GROUP BY e.id_estudiante, e.nombre, e.apellido
ORDER BY posicion, nombre_estudiante
LIMIT 10;


/* ----------------------------------------------------------------------------
   CONSULTA 7
   PREGUNTA DE NEGOCIO: ¿Qué reportes de moderación siguen abiertos
                        (Pendiente o En revision), qué contenido se reportó y
                        cuántas veces se ha reportado ese mismo contenido?
   Sirve al equipo de moderación para priorizar.
   TABLAS : reporte_contenido (rc), estudiante (e), publicacion (p),
            comentario (c)
   CLÁUSULAS: JOIN, LEFT JOIN condicionales (patrón polimórfico),
              COALESCE, COUNT(*) OVER (PARTITION BY ...), WHERE ... IN, ORDER BY.
   NOTA   : id_contenido no tiene FK porque puede apuntar a una publicación o
            a un comentario según tipo_contenido; por eso se une con una
            condición que depende de ese tipo.
   ALIAS  : nombre_reportante, contenido_reportado, veces_reportado.
---------------------------------------------------------------------------- */
SELECT
    rc.id_reporte,
    rc.tipo_contenido,
    COALESCE(p.contenido, c.contenido, '(contenido no encontrado)') AS contenido_reportado,
    e.nombre || ' ' || e.apellido                                   AS nombre_reportante,
    rc.motivo,
    rc.estado,
    rc.fecha_reporte,
    COUNT(*) OVER (PARTITION BY rc.tipo_contenido, rc.id_contenido) AS veces_reportado
FROM reporte_contenido rc
JOIN estudiante e        ON e.id_estudiante = rc.id_estudiante
LEFT JOIN publicacion p  ON rc.tipo_contenido = 'publicacion' AND p.id_publicacion = rc.id_contenido
LEFT JOIN comentario c   ON rc.tipo_contenido = 'comentario'  AND c.id_comentario  = rc.id_contenido
WHERE rc.estado IN ('Pendiente', 'En revision')
ORDER BY veces_reportado DESC, rc.fecha_reporte;
