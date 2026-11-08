select license_plate from vehicles where status = 'active';

-- Query 1: Contar vehículos por tipo
-- Problema de negocio: Conocer la composición de la flota
SELECT 
    vehicle_type,
    COUNT(*) as cantidad
FROM vehicles
GROUP BY vehicle_type
ORDER BY cantidad DESC; 

-- Query 1: Vehículos por tipo
-- Pregunta de negocio: ¿Cuántos vehículos hay de cada tipo?
-- Resultado: 69 vans, 60 camiones grandes, 51 camiones medianos
-- y 20 motocicletas. Total: 200 vehículos.
-- Tiempo antes de optimizar: 2.675 ms
-- Plan: leyó la tabla vehicles, agrupó por tipo y ordenó por cantidad. 

EXPLAIN ANALYZE
SELECT vehicle_type, COUNT(*) AS cantidad
FROM vehicles
GROUP BY vehicle_type
ORDER BY cantidad DESC;

-- Después de crear los índices y ejecutar ANALYZE: 0.239 ms.
-- El plan siguió usando Seq Scan on vehicles, sin usar los índices nuevos.

-- Query 2: Listar conductores con licencia próxima a vencer
-- Problema de negocio: Prevenir problemas legales por licencias vencidas
SELECT 
    first_name,
    last_name,
    license_number,
    license_expiry
FROM drivers
WHERE license_expiry < CURRENT_DATE + INTERVAL '30 days'
ORDER BY license_expiry;

-- Resultado: 13 conductores con fecha de vencimiento anterior a hoy + 30 días.
-- El resultado puede incluir licencias ya vencidas.
-- Tiempo antes de optimizar: 0.245 ms
-- Plan: PostgreSQL leyó la tabla drivers, descartó 387 filas
-- y ordenó los 13 resultados por fecha de vencimiento.

EXPLAIN ANALYZE
SELECT 
    first_name,
    last_name,
    license_number,
    license_expiry
FROM drivers
WHERE license_expiry < CURRENT_DATE + INTERVAL '30 days'
ORDER BY license_expiry;

-- Después de crear los índices y ejecutar ANALYZE: 0.589 ms.
-- El plan mantuvo Seq Scan on drivers. La consulta no filtra
-- por status = 'active', así que no usó el índice de conductores activos.

-- Query 3: Total de viajes por estado
-- Problema de negocio: Monitorear operaciones en curso
SELECT 
    status,
    COUNT(*) as total_viajes
FROM trips
GROUP BY status;

-- Resultado: 100.000 viajes completados; no se registraron otros estados.
-- Tiempo antes de optimizar: 68.874 ms
-- Plan: PostgreSQL recorrió los 100.000 viajes (Seq Scan)
-- y los agrupó y contó por estado (HashAggregate).

EXPLAIN ANALYZE
SELECT 
    status,
    COUNT(*) as total_viajes
FROM trips
GROUP BY status;

-- Después de crear los índices y ejecutar ANALYZE: 142.841 ms.
-- El plan mantuvo Seq Scan on trips y HashAggregate.
-- No usó los índices nuevos. Esta ejecución tardó más que la inicial.


-- Query 4: Total de entregas por ciudad destino en los últimos 2 meses
-- Problema de negocio: Identificar demanda por ciudad para planificación de recursos
SELECT 
    r.destination_city,
    COUNT(DISTINCT t.trip_id) as total_viajes,
    COUNT(d.delivery_id) as total_entregas,
    SUM(d.package_weight_kg) as peso_total_kg
FROM routes r
INNER JOIN trips t ON r.route_id = t.route_id
INNER JOIN deliveries d ON t.trip_id = d.trip_id
WHERE t.departure_datetime >= CURRENT_DATE - INTERVAL '60 days'
GROUP BY r.destination_city
ORDER BY total_entregas DESC;

-- Resultado: Cartagena lideró con 6.955 entregas en 1.743 viajes.
-- Bogotá quedó segunda con 6.510 entregas.
-- Tiempo antes de optimizar: 104.087
-- Plan: PostgreSQL agrupó las entregas por ciudad de destino
-- (GroupAggregate) y ordenó las ciudades de mayor a menor
-- cantidad de entregas (Sort).

EXPLAIN ANALYZE
SELECT 
    r.destination_city,
    COUNT(DISTINCT t.trip_id) as total_viajes,
    COUNT(d.delivery_id) as total_entregas,
    SUM(d.package_weight_kg) as peso_total_kg
FROM routes r
INNER JOIN trips t ON r.route_id = t.route_id
INNER JOIN deliveries d ON t.trip_id = d.trip_id
WHERE t.departure_datetime >= CURRENT_DATE - INTERVAL '60 days'
GROUP BY r.destination_city
ORDER BY total_entregas DESC;

-- Después de crear los índices y ejecutar ANALYZE: 325.094 ms.
-- Usó el índice existente idx_trips_departure.
-- Recorrió deliveries en paralelo y routes con Seq Scan.
-- Esta ejecución tardó más que la inicial.

-- Query 5: Conductores activos con cantidad de viajes completados
-- Problema de negocio: Evaluar carga de trabajo por conductor
SELECT 
    d.driver_id,
    d.first_name || ' ' || d.last_name as nombre_completo,
    d.license_expiry,
    COUNT(t.trip_id) as viajes_totales,
    SUM(CASE WHEN t.status = 'completed' THEN 1 ELSE 0 END) as viajes_completados
FROM drivers d
LEFT JOIN trips t ON d.driver_id = t.driver_id
WHERE d.status = 'active'
GROUP BY d.driver_id, d.first_name, d.last_name, d.license_expiry
HAVING COUNT(t.trip_id) > 0
ORDER BY viajes_completados DESC;

-- Resultado: 373 conductores activos con al menos un viaje registrado.
-- Rosalba Ayala lideró con 311 viajes completados.
-- Tiempo antes de optimizar:  109.468 ms
-- Plan: PostgreSQL recorrió la tabla trips y descartó 27 conductores
-- que no estaban activos. Luego unió ambas tablas por driver_id
-- y agrupó los viajes por conductor.

EXPLAIN ANALYZE
SELECT 
    d.driver_id,
    d.first_name || ' ' || d.last_name as nombre_completo,
    d.license_expiry,
    COUNT(t.trip_id) as viajes_totales,
    SUM(CASE WHEN t.status = 'completed' THEN 1 ELSE 0 END) as viajes_completados
FROM drivers d
LEFT JOIN trips t ON d.driver_id = t.driver_id
WHERE d.status = 'active'
GROUP BY d.driver_id, d.first_name, d.last_name, d.license_expiry
HAVING COUNT(t.trip_id) > 0
ORDER BY viajes_completados DESC;

-- Después de crear los índices y ejecutar ANALYZE: 86.708 ms.
-- En esta medición tardó 22.760 ms menos que la inicial (20.8 %).
-- Plan: mantuvo Seq Scan en trips y drivers y Hash Right Join.
-- No usó los índices nuevos; la reducción de tiempo observada
-- no se puede atribuir a su uso.


-- Query 6: Promedio de entregas por conductor en los últimos 6 meses
-- Problema de negocio: Medir productividad individual de conductores
SELECT 
    dr.driver_id,
    dr.first_name || ' ' || dr.last_name as conductor,
    COUNT(DISTINCT t.trip_id) as total_viajes,
    COUNT(d.delivery_id) as total_entregas,
    ROUND(COUNT(d.delivery_id)::NUMERIC / NULLIF(COUNT(DISTINCT t.trip_id), 0), 2) as promedio_entregas_por_viaje,
    ROUND(COUNT(d.delivery_id)::NUMERIC / 180, 2) as promedio_entregas_diarias
FROM drivers dr
INNER JOIN trips t ON dr.driver_id = t.driver_id
INNER JOIN deliveries d ON t.trip_id = d.trip_id
WHERE t.departure_datetime >= CURRENT_DATE - INTERVAL '6 months'
    AND t.status = 'completed'
GROUP BY dr.driver_id, dr.first_name, dr.last_name
HAVING COUNT(DISTINCT t.trip_id) >= 10
ORDER BY promedio_entregas_por_viaje DESC;

-- Resultado: Cecilia Cerón tuvo el mayor promedio de entregas por viaje
-- en los últimos 6 meses: 4.35 (274 entregas en 63 viajes).
-- Tiempo antes de optimizar: pendiente

EXPLAIN ANALYZE
SELECT 
    dr.driver_id,
    dr.first_name || ' ' || dr.last_name as conductor,
    COUNT(DISTINCT t.trip_id) as total_viajes,
    COUNT(d.delivery_id) as total_entregas,
    ROUND(COUNT(d.delivery_id)::NUMERIC / NULLIF(COUNT(DISTINCT t.trip_id), 0), 2) as promedio_entregas_por_viaje,
    ROUND(COUNT(d.delivery_id)::NUMERIC / 180, 2) as promedio_entregas_diarias
FROM drivers dr
INNER JOIN trips t ON dr.driver_id = t.driver_id
INNER JOIN deliveries d ON t.trip_id = d.trip_id
WHERE t.departure_datetime >= CURRENT_DATE - INTERVAL '6 months'
    AND t.status = 'completed'
GROUP BY dr.driver_id, dr.first_name, dr.last_name
HAVING COUNT(DISTINCT t.trip_id) >= 10
ORDER BY promedio_entregas_por_viaje DESC;

-- Tiempo antes de optimizar: 187.295 ms
-- Plan: PostgreSQL usó el índice existente idx_trips_departure
-- para buscar viajes por fecha y recorrió toda la tabla deliveries.
-- También usó espacio temporal en disco para ordenar por conductor.

-- Después de crear los índices y ejecutar ANALYZE: 182.494 ms.
-- En esta medición tardó 4.801 ms menos que la inicial (2.6 %).
-- Mantuvo Seq Scan en deliveries y ordenamiento en disco.

-- Query 7: Rutas con mayor consumo de combustible por kilómetro
-- Problema de negocio: Identificar rutas ineficientes para optimización
SELECT 
    r.route_code,
    r.origin_city || ' -> ' || r.destination_city as ruta,
    r.distance_km,
    COUNT(t.trip_id) as viajes_realizados,
    AVG(t.fuel_consumed_liters) as promedio_combustible_litros,
    ROUND(AVG(t.fuel_consumed_liters / NULLIF(r.distance_km, 0)) * 100, 2) as litros_por_100km,
    SUM(t.fuel_consumed_liters) as combustible_total
FROM routes r
INNER JOIN trips t ON r.route_id = t.route_id
WHERE t.fuel_consumed_liters IS NOT NULL 
    AND r.distance_km > 0
    AND t.status = 'completed'
GROUP BY r.route_id, r.route_code, r.origin_city, r.destination_city, r.distance_km
HAVING COUNT(t.trip_id) >= 50
ORDER BY litros_por_100km DESC
LIMIT 10;

-- Resultado: R009 (Bogotá → Barranquilla) tuvo el mayor consumo
-- promedio: 11,60 L/100 km en 2.013 viajes.
-- Tiempo antes de optimizar: 92.385 ms.
-- Plan: PostgreSQL recorrió trips y routes (Seq Scan)
-- y unió ambas tablas por route_id (Hash Join).

EXPLAIN ANALYZE
SELECT 
    r.route_code,
    r.origin_city || ' -> ' || r.destination_city as ruta,
    r.distance_km,
    COUNT(t.trip_id) as viajes_realizados,
    AVG(t.fuel_consumed_liters) as promedio_combustible_litros,
    ROUND(AVG(t.fuel_consumed_liters / NULLIF(r.distance_km, 0)) * 100, 2) as litros_por_100km,
    SUM(t.fuel_consumed_liters) as combustible_total
FROM routes r
INNER JOIN trips t ON r.route_id = t.route_id
WHERE t.fuel_consumed_liters IS NOT NULL 
    AND r.distance_km > 0
    AND t.status = 'completed'
GROUP BY r.route_id, r.route_code, r.origin_city, r.destination_city, r.distance_km
HAVING COUNT(t.trip_id) >= 50
ORDER BY litros_por_100km DESC
LIMIT 10;

-- Después de crear los índices y ejecutar ANALYZE: 71.742 ms.
-- En esta medición tardó 20.643 ms menos que la inicial (22.3 %).
-- El plan usó Parallel Seq Scan en trips y Hash Join.


-- Query 8: Análisis de entregas retrasadas por día de la semana
-- Problema de negocio: Identificar patrones de retraso para mejorar planificación
SELECT 
    TO_CHAR(d.scheduled_datetime, 'Day') as dia_semana,
    EXTRACT(DOW FROM d.scheduled_datetime) as num_dia,
    COUNT(*) as total_entregas,
    COUNT(CASE 
        WHEN d.delivered_datetime > d.scheduled_datetime + INTERVAL '30 minutes' 
        THEN 1 
    END) as entregas_retrasadas,
    ROUND(100.0 * COUNT(CASE 
        WHEN d.delivered_datetime > d.scheduled_datetime + INTERVAL '30 minutes' 
        THEN 1 
    END) / COUNT(*), 2) as porcentaje_retrasos,
    AVG(EXTRACT(EPOCH FROM (d.delivered_datetime - d.scheduled_datetime)) / 60) as minutos_promedio_diferencia
FROM deliveries d
WHERE d.delivery_status = 'delivered'
    AND d.scheduled_datetime >= CURRENT_DATE - INTERVAL '90 days'
GROUP BY dia_semana, num_dia
ORDER BY num_dia;

-- Resultado: El miércoles tuvo el mayor porcentaje de retrasos: 9,93 %.
-- 652 de 6.563 entregas llegaron más de 30 minutos tarde.
-- Tiempo antes de optimizar: 95.224 ms.
-- Plan: PostgreSQL recorrió la tabla deliveries en paralelo,
-- filtró por estado y fecha, y agrupó las entregas por día de la semana.

EXPLAIN ANALYZE
SELECT 
    TO_CHAR(d.scheduled_datetime, 'Day') as dia_semana,
    EXTRACT(DOW FROM d.scheduled_datetime) as num_dia,
    COUNT(*) as total_entregas,
    COUNT(CASE 
        WHEN d.delivered_datetime > d.scheduled_datetime + INTERVAL '30 minutes' 
        THEN 1 
    END) as entregas_retrasadas,
    ROUND(100.0 * COUNT(CASE 
        WHEN d.delivered_datetime > d.scheduled_datetime + INTERVAL '30 minutes' 
        THEN 1 
    END) / COUNT(*), 2) as porcentaje_retrasos,
    AVG(EXTRACT(EPOCH FROM (d.delivered_datetime - d.scheduled_datetime)) / 60) as minutos_promedio_diferencia
FROM deliveries d
WHERE d.delivery_status = 'delivered'
    AND d.scheduled_datetime >= CURRENT_DATE - INTERVAL '90 days'
GROUP BY dia_semana, num_dia
ORDER BY num_dia;

-- Después de crear los índices y ejecutar ANALYZE: 107.578 ms.
-- PostgreSQL usó idx_deliveries_scheduled_datetime (Bitmap Index Scan).
-- El ordenamiento usó disco. En esta medición tardó 12.354 ms más.

-- Query 9: Costo de mantenimiento por kilómetro recorrido
-- Problema de negocio: Evaluar costo-beneficio de cada tipo de vehículo

-- CONSULTA 9 ORIGINAL DEL CURSO:
-- El JOIN duplica las sumas de kilómetros y mantenimiento.
-- Se conserva para documentar las mediciones originales.
-- La versión corregida está al final de este script.

WITH vehicle_metrics AS (
    SELECT 
        v.vehicle_id,
        v.vehicle_type,
        v.license_plate,
        COUNT(DISTINCT t.trip_id) as total_viajes,
        SUM(r.distance_km) as km_totales,
        SUM(m.cost) as costo_mantenimiento_total,
        COUNT(DISTINCT m.maintenance_id) as cantidad_mantenimientos
    FROM vehicles v
    LEFT JOIN trips t ON v.vehicle_id = t.vehicle_id
    LEFT JOIN routes r ON t.route_id = r.route_id
    LEFT JOIN maintenance m ON v.vehicle_id = m.vehicle_id
    WHERE t.status = 'completed'
    GROUP BY v.vehicle_id, v.vehicle_type, v.license_plate
)
SELECT 
    vehicle_type,
    COUNT(vehicle_id) as cantidad_vehiculos,
    SUM(total_viajes) as viajes_totales,
    SUM(km_totales) as kilometros_totales,
    SUM(costo_mantenimiento_total) as costo_total_mantenimiento,
    ROUND(SUM(costo_mantenimiento_total) / NULLIF(SUM(km_totales), 0), 2) as costo_por_km,
    ROUND(AVG(costo_mantenimiento_total / NULLIF(cantidad_mantenimientos, 0)), 2) as costo_promedio_por_mantenimiento
FROM vehicle_metrics
WHERE km_totales > 0 AND costo_mantenimiento_total > 0
GROUP BY vehicle_type
ORDER BY costo_por_km DESC;

-- Resultado del código original: Motocicleta encabeza con 569.24 por km.
-- Observación: el JOIN entre viajes y mantenimientos repite valores
-- en las sumas. Los costos requieren corregir y validar el cálculo.

EXPLAIN ANALYZE
WITH vehicle_metrics AS (
    SELECT 
        v.vehicle_id,
        v.vehicle_type,
        v.license_plate,
        COUNT(DISTINCT t.trip_id) as total_viajes,
        SUM(r.distance_km) as km_totales,
        SUM(m.cost) as costo_mantenimiento_total,
        COUNT(DISTINCT m.maintenance_id) as cantidad_mantenimientos
    FROM vehicles v
    LEFT JOIN trips t ON v.vehicle_id = t.vehicle_id
    LEFT JOIN routes r ON t.route_id = r.route_id
    LEFT JOIN maintenance m ON v.vehicle_id = m.vehicle_id
    WHERE t.status = 'completed'
    GROUP BY v.vehicle_id, v.vehicle_type, v.license_plate
)
SELECT 
    vehicle_type,
    COUNT(vehicle_id) as cantidad_vehiculos,
    SUM(total_viajes) as viajes_totales,
    SUM(km_totales) as kilometros_totales,
    SUM(costo_mantenimiento_total) as costo_total_mantenimiento,
    ROUND(SUM(costo_mantenimiento_total) / NULLIF(SUM(km_totales), 0), 2) as costo_por_km,
    ROUND(AVG(costo_mantenimiento_total / NULLIF(cantidad_mantenimientos, 0)), 2) as costo_promedio_por_mantenimiento
FROM vehicle_metrics
WHERE km_totales > 0 AND costo_mantenimiento_total > 0
GROUP BY vehicle_type
ORDER BY costo_por_km DESC;

-- Tiempo sin los cinco índices: 1282.434 ms.
-- Tiempo con los cinco índices: 1093.520 ms.
-- Diferencia observada: 188.914 ms menos (14.7 %).
-- El cálculo original sigue pendiente de corregir porque
-- el JOIN entre viajes y mantenimientos duplica las sumas.

-- Query 10: Ranking de conductores por eficiencia usando Window Functions
-- Problema de negocio: Identificar top performers para incentivos
WITH conductor_metricas AS (
    SELECT 
        d.driver_id,
        d.first_name || ' ' || d.last_name as nombre,
        COUNT(DISTINCT t.trip_id) as viajes,
        COUNT(DISTINCT del.delivery_id) as entregas,
        AVG(t.fuel_consumed_liters / NULLIF(r.distance_km, 0)) * 100 as consumo_100km,
        COUNT(CASE WHEN del.delivered_datetime <= del.scheduled_datetime THEN 1 END)::NUMERIC / 
            NULLIF(COUNT(del.delivery_id), 0) * 100 as puntualidad_pct
    FROM drivers d
    JOIN trips t ON d.driver_id = t.driver_id
    JOIN routes r ON t.route_id = r.route_id
    LEFT JOIN deliveries del ON t.trip_id = del.trip_id
    WHERE t.departure_datetime >= CURRENT_DATE - INTERVAL '3 months'
    GROUP BY d.driver_id, d.first_name, d.last_name
    HAVING COUNT(DISTINCT t.trip_id) >= 20
)
SELECT 
    nombre,
    viajes,
    entregas,
    ROUND(consumo_100km, 2) as consumo_100km,
    ROUND(puntualidad_pct, 2) as puntualidad_pct,
    RANK() OVER (ORDER BY puntualidad_pct DESC) as rank_puntualidad,
    RANK() OVER (ORDER BY consumo_100km ASC) as rank_eficiencia,
    RANK() OVER (ORDER BY entregas DESC) as rank_productividad,
    (RANK() OVER (ORDER BY puntualidad_pct DESC) + 
     RANK() OVER (ORDER BY consumo_100km ASC) + 
     RANK() OVER (ORDER BY entregas DESC)) / 3.0 as score_promedio
FROM conductor_metricas
ORDER BY score_promedio ASC
LIMIT 20;

-- Resultado: Eduardo Rodríguez aparece primero en el ranking combinado,
-- con 39 viajes y 163 entregas en los últimos 3 meses.

EXPLAIN ANALYZE
WITH conductor_metricas AS (
    SELECT 
        d.driver_id,
        d.first_name || ' ' || d.last_name as nombre,
        COUNT(DISTINCT t.trip_id) as viajes,
        COUNT(DISTINCT del.delivery_id) as entregas,
        AVG(t.fuel_consumed_liters / NULLIF(r.distance_km, 0)) * 100 as consumo_100km,
        COUNT(CASE WHEN del.delivered_datetime <= del.scheduled_datetime THEN 1 END)::NUMERIC / 
            NULLIF(COUNT(del.delivery_id), 0) * 100 as puntualidad_pct
    FROM drivers d
    JOIN trips t ON d.driver_id = t.driver_id
    JOIN routes r ON t.route_id = r.route_id
    LEFT JOIN deliveries del ON t.trip_id = del.trip_id
    WHERE t.departure_datetime >= CURRENT_DATE - INTERVAL '3 months'
    GROUP BY d.driver_id, d.first_name, d.last_name
    HAVING COUNT(DISTINCT t.trip_id) >= 20
)
SELECT 
    nombre,
    viajes,
    entregas,
    ROUND(consumo_100km, 2) as consumo_100km,
    ROUND(puntualidad_pct, 2) as puntualidad_pct,
    RANK() OVER (ORDER BY puntualidad_pct DESC) as rank_puntualidad,
    RANK() OVER (ORDER BY consumo_100km ASC) as rank_eficiencia,
    RANK() OVER (ORDER BY entregas DESC) as rank_productividad,
    (RANK() OVER (ORDER BY puntualidad_pct DESC) + 
     RANK() OVER (ORDER BY consumo_100km ASC) + 
     RANK() OVER (ORDER BY entregas DESC)) / 3.0 as score_promedio
FROM conductor_metricas
ORDER BY score_promedio ASC
LIMIT 20;

-- Tiempo sin los cinco índices: 651.443 ms.
-- Tiempo con los cinco índices: 220.600 ms.
-- Diferencia observada: 430.843 ms menos (66.1 %).
-- Plan con índices: Seq Scan en drivers y routes, y Hash Join.
-- Las mediciones se hicieron en sesiones distintas;
-- la diferencia también puede depender de caché y carga.

-- Query 11: Análisis de tendencia de viajes con LAG y LEAD
-- Problema de negocio: Proyectar necesidades futuras basadas en tendencias
WITH viajes_mensuales AS (
    SELECT 
        DATE_TRUNC('month', departure_datetime) as mes,
        COUNT(*) as total_viajes,
        SUM(total_weight_kg) as peso_total,
        AVG(fuel_consumed_liters) as combustible_promedio
    FROM trips
    WHERE status = 'completed'
    GROUP BY DATE_TRUNC('month', departure_datetime)
)
SELECT 
    TO_CHAR(mes, 'YYYY-MM') as periodo,
    total_viajes,
    LAG(total_viajes, 1) OVER (ORDER BY mes) as viajes_mes_anterior,
    LEAD(total_viajes, 1) OVER (ORDER BY mes) as viajes_mes_siguiente,
    total_viajes - LAG(total_viajes, 1) OVER (ORDER BY mes) as cambio_absoluto,
    ROUND((total_viajes - LAG(total_viajes, 1) OVER (ORDER BY mes))::NUMERIC / 
          NULLIF(LAG(total_viajes, 1) OVER (ORDER BY mes), 0) * 100, 2) as cambio_porcentual,
    ROUND(peso_total / 1000, 2) as toneladas_transportadas,
    ROUND(combustible_promedio, 2) as combustible_promedio_viaje,
    AVG(total_viajes) OVER (ORDER BY mes ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) as promedio_movil_3m
FROM viajes_mensuales
ORDER BY mes DESC
LIMIT 12;

-- Resultado: octubre de 2026 registró 3.972 viajes completados,
-- frente a 4.110 en septiembre: 138 menos (-3.36 %).

EXPLAIN ANALYZE
WITH viajes_mensuales AS (
    SELECT 
        DATE_TRUNC('month', departure_datetime) as mes,
        COUNT(*) as total_viajes,
        SUM(total_weight_kg) as peso_total,
        AVG(fuel_consumed_liters) as combustible_promedio
    FROM trips
    WHERE status = 'completed'
    GROUP BY DATE_TRUNC('month', departure_datetime)
)
SELECT 
    TO_CHAR(mes, 'YYYY-MM') as periodo,
    total_viajes,
    LAG(total_viajes, 1) OVER (ORDER BY mes) as viajes_mes_anterior,
    LEAD(total_viajes, 1) OVER (ORDER BY mes) as viajes_mes_siguiente,
    total_viajes - LAG(total_viajes, 1) OVER (ORDER BY mes) as cambio_absoluto,
    ROUND((total_viajes - LAG(total_viajes, 1) OVER (ORDER BY mes))::NUMERIC / 
          NULLIF(LAG(total_viajes, 1) OVER (ORDER BY mes), 0) * 100, 2) as cambio_porcentual,
    ROUND(peso_total / 1000, 2) as toneladas_transportadas,
    ROUND(combustible_promedio, 2) as combustible_promedio_viaje,
    AVG(total_viajes) OVER (ORDER BY mes ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) as promedio_movil_3m
FROM viajes_mensuales
ORDER BY mes DESC
LIMIT 12;

-- Tiempo sin los cinco índices: 220.792 ms.
-- Tiempo con los cinco índices: 92.010 ms.
-- Diferencia observada: 128.782 ms menos (58.3 %).
-- Ambos planes usaron Seq Scan en trips y ordenamiento
-- en disco; no se observa uso de los cinco índices nuevos.
-- Los tiempos se midieron en sesiones distintas, por lo
-- que la diferencia no puede atribuirse solo a los índices.

-- Query 12: Pivot de entregas por hora y día de la semana
-- Problema de negocio: Optimizar horarios de operación y personal
WITH entregas_por_hora_dia AS (
    SELECT 
        EXTRACT(DOW FROM scheduled_datetime) as dia_semana,
        EXTRACT(HOUR FROM scheduled_datetime) as hora,
        COUNT(*) as cantidad_entregas
    FROM deliveries
    WHERE scheduled_datetime >= CURRENT_DATE - INTERVAL '60 days'
    GROUP BY EXTRACT(DOW FROM scheduled_datetime), EXTRACT(HOUR FROM scheduled_datetime)
)
SELECT 
    hora,
    SUM(CASE WHEN dia_semana = 0 THEN cantidad_entregas ELSE 0 END) as domingo,
    SUM(CASE WHEN dia_semana = 1 THEN cantidad_entregas ELSE 0 END) as lunes,
    SUM(CASE WHEN dia_semana = 2 THEN cantidad_entregas ELSE 0 END) as martes,
    SUM(CASE WHEN dia_semana = 3 THEN cantidad_entregas ELSE 0 END) as miercoles,
    SUM(CASE WHEN dia_semana = 4 THEN cantidad_entregas ELSE 0 END) as jueves,
    SUM(CASE WHEN dia_semana = 5 THEN cantidad_entregas ELSE 0 END) as viernes,
    SUM(CASE WHEN dia_semana = 6 THEN cantidad_entregas ELSE 0 END) as sabado,
    SUM(cantidad_entregas) as total_semana
FROM entregas_por_hora_dia
WHERE hora BETWEEN 6 AND 22
GROUP BY hora
ORDER BY hora;

-- Resultado: la franja de 16:00 a 16:59 concentró la mayor
-- cantidad de entregas programadas: 1.725 en los últimos 60 días.
-- Aunque la columna se llama total_semana, acumula todo ese período.
-- Tiempo con los cinco índices creados: 292.357 ms.
-- Plan: agrupó los datos en paralelo y usó quicksort
-- en memoria para ordenar los resultados intermedios.
-- Tiempo sin estos cinco índices: pendiente de medir.

EXPLAIN ANALYZE
WITH entregas_por_hora_dia AS (
    SELECT 
        EXTRACT(DOW FROM scheduled_datetime) as dia_semana,
        EXTRACT(HOUR FROM scheduled_datetime) as hora,
        COUNT(*) as cantidad_entregas
    FROM deliveries
    WHERE scheduled_datetime >= CURRENT_DATE - INTERVAL '60 days'
    GROUP BY EXTRACT(DOW FROM scheduled_datetime), EXTRACT(HOUR FROM scheduled_datetime)
)
SELECT 
    hora,
    SUM(CASE WHEN dia_semana = 0 THEN cantidad_entregas ELSE 0 END) as domingo,
    SUM(CASE WHEN dia_semana = 1 THEN cantidad_entregas ELSE 0 END) as lunes,
    SUM(CASE WHEN dia_semana = 2 THEN cantidad_entregas ELSE 0 END) as martes,
    SUM(CASE WHEN dia_semana = 3 THEN cantidad_entregas ELSE 0 END) as miercoles,
    SUM(CASE WHEN dia_semana = 4 THEN cantidad_entregas ELSE 0 END) as jueves,
    SUM(CASE WHEN dia_semana = 5 THEN cantidad_entregas ELSE 0 END) as viernes,
    SUM(CASE WHEN dia_semana = 6 THEN cantidad_entregas ELSE 0 END) as sabado,
    SUM(cantidad_entregas) as total_semana
FROM entregas_por_hora_dia
WHERE hora BETWEEN 6 AND 22
GROUP BY hora
ORDER BY hora;

-- Consulta 9: comprobación de viajes por vehículo
SELECT
    t.vehicle_id,
    COUNT(*) AS total_viajes,
    SUM(r.distance_km) AS km_totales
FROM trips t
LEFT JOIN routes r ON t.route_id = r.route_id
WHERE t.status = 'completed'
GROUP BY t.vehicle_id;

-- Consulta 9: comprobación de mantenimiento por vehículo
SELECT
    vehicle_id,
    SUM(cost) AS costo_mantenimiento_total,
    COUNT(*) AS cantidad_mantenimientos
FROM maintenance
GROUP BY vehicle_id;

-- Consulta 9 corregida: sumar antes de unir
EXPLAIN ANALYZE
WITH viajes_por_vehiculo AS (
    SELECT
        t.vehicle_id,
        COUNT(*) AS total_viajes,
        SUM(r.distance_km) AS km_totales
    FROM trips t
    LEFT JOIN routes r ON t.route_id = r.route_id
    WHERE t.status = 'completed'
    GROUP BY t.vehicle_id
),
mantenimiento_por_vehiculo AS (
    SELECT
        vehicle_id,
        SUM(cost) AS costo_total,
        COUNT(*) AS cantidad_mantenimientos
    FROM maintenance
    GROUP BY vehicle_id
)
SELECT
    v.vehicle_type,
    COUNT(*) AS cantidad_vehiculos,
    SUM(t.total_viajes) AS viajes_totales,
    SUM(t.km_totales) AS kilometros_totales,
    SUM(m.costo_total) AS costo_total_mantenimiento,
    ROUND(
        SUM(m.costo_total) / NULLIF(SUM(t.km_totales), 0),
        2
    ) AS costo_por_km,
    ROUND(
        AVG(m.costo_total / NULLIF(m.cantidad_mantenimientos, 0)),
        2
    ) AS costo_promedio_por_mantenimiento
FROM vehicles v
JOIN viajes_por_vehiculo t ON v.vehicle_id = t.vehicle_id
JOIN mantenimiento_por_vehiculo m ON v.vehicle_id = m.vehicle_id
WHERE t.km_totales > 0
  AND m.costo_total > 0
GROUP BY v.vehicle_type
ORDER BY costo_por_km DESC;

-- Resultado corregido: Motocicleta presentó el mayor costo
-- de mantenimiento por km: 28.94; Van, el menor: 28.65.
-- Se sumaron viajes y mantenimientos por separado antes
-- de unirlos por vehículo, evitando duplicar las sumas.
-- Los tiempos documentados en la consulta 9 original
-- corresponden a esa versión, no a esta corrección.

-- Versión corregida con los cinco índices: 128.569 ms.
-- El plan muestra Seq Scan en trips y routes,
-- y un Hash Left Join para unir viajes con rutas.

-- Versión corregida sin los cinco índices: 89.377 ms.
-- Con los cinco índices: 128.569 ms.
-- En estas mediciones, con índices tardó 39.192 ms más.
-- La variación de tiempo no demuestra por sí sola
-- que los índices sean la causa.