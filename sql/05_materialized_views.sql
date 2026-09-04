-- 1. Create the Materialized View
-- We use a LEFT JOIN so we still see properties even if they have 0 bookings.
-- (Note: Since our schema doesn't have a 'nights' column, we count total bookings as a proxy).
CREATE MATERIALIZED VIEW mv_property_summary AS
SELECT 
    p.id AS property_id,
    p.title,
    COUNT(b.id) AS total_bookings,
    COALESCE(SUM(b.total_cost), 0) AS total_revenue
FROM properties p
LEFT JOIN bookings b ON p.id = b.property_id
GROUP BY p.id, p.title;

-- 2. Create the Unique Index
-- This is STRICTLY REQUIRED by PostgreSQL if you want to use the CONCURRENTLY keyword later.
-- It acts just like a unique key in a std::unordered_map so the database can quickly find and update specific rows in the background.
CREATE UNIQUE INDEX idx_mv_property_summary_id ON mv_property_summary (property_id);

CREATE OR REPLACE FUNCTION refresh_property_summary()
RETURNS void AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_property_summary;
END;
$$ LANGUAGE plpgsql;