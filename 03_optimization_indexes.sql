CREATE INDEX idx_trips_composite_joins ON trips(vehicle_id, driver_id, route_id, departure_datetime)
WHERE status = 'completed';

CREATE INDEX idx_deliveries_scheduled_datetime
ON deliveries (scheduled_datetime, delivery_status)
WHERE delivery_status = 'delivered';

CREATE INDEX idx_maintenance_vehicle_cost
ON maintenance (vehicle_id, cost);

CREATE INDEX idx_drivers_status_license
ON drivers (status, license_expiry)
WHERE status = 'active';

CREATE INDEX idx_routes_metrics
ON routes (route_id, distance_km, destination_city);

ANALYZE vehicles;
ANALYZE drivers;
ANALYZE routes;
ANALYZE trips;
ANALYZE deliveries;
ANALYZE maintenance;

SELECT tablename, indexname, indexdef
FROM pg_indexes
WHERE schemaname = 'public'
  AND indexname IN (
    'idx_trips_composite_joins',
    'idx_deliveries_scheduled_datetime',
    'idx_maintenance_vehicle_cost',
    'idx_drivers_status_license',
    'idx_routes_metrics'
  )
ORDER BY indexname;
