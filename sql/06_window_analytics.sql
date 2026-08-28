-- -- CTE 1: Calculate raw revenue for each individual day
-- WITH DailyRevenue AS (
--     SELECT 
--         DATE(created_at) AS booking_date,
--         SUM(total_cost) AS daily_total
--     FROM bookings
--     GROUP BY DATE(created_at)
-- ),

-- -- CTE 2: Apply the Sliding Window to calculate the 7-day average
-- MovingAverages AS (
--     SELECT 
--         booking_date,
--         daily_total,
--         -- The Window Function: Average the current row and the 6 rows before it
--         AVG(daily_total) OVER (
--             ORDER BY booking_date 
--             ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
--         ) AS moving_avg_7d
--     FROM DailyRevenue
-- )

-- -- Final Output: Select the data and use DENSE_RANK() to find the best weeks
-- SELECT 
--     booking_date,
--     daily_total,
--     ROUND(moving_avg_7d, 2) AS moving_avg_7d,
--     -- Rank the days based on how high their 7-day moving average was
--     DENSE_RANK() OVER (ORDER BY moving_avg_7d DESC) AS revenue_momentum_rank
-- FROM MovingAverages
-- ORDER BY booking_date DESC;

-- CTE 1: Create a continuous calendar of all possible dates in the dataset
WITH DateRange AS (
    SELECT generate_series(
        (SELECT MIN(DATE(created_at)) FROM bookings),
        (SELECT MAX(DATE(created_at)) FROM bookings),
        '1 day'::interval
    )::date AS calendar_date
),

-- CTE 2: CROSS JOIN properties with dates so EVERY property has EVERY date
PropertyDates AS (
    SELECT p.id AS property_id, d.calendar_date
    FROM properties p
    CROSS JOIN DateRange d
),

-- CTE 3: LEFT JOIN bookings to fill in revenue, using COALESCE to force $0 on empty days
DailyRevenue AS (
    SELECT 
        pd.property_id,
        pd.calendar_date AS booking_date,
        COALESCE(SUM(b.total_cost), 0) AS daily_total
    FROM PropertyDates pd
    LEFT JOIN bookings b 
        ON pd.property_id = b.property_id 
        AND pd.calendar_date = DATE(b.created_at)
    GROUP BY pd.property_id, pd.calendar_date
),

-- CTE 4: The 7-Day Window. (Because every date exists now, ROWS is perfectly safe to use)
MovingAverages AS (
    SELECT 
        property_id,
        booking_date,
        daily_total,
        AVG(daily_total) OVER (
            PARTITION BY property_id
            ORDER BY booking_date 
            ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
        ) AS moving_avg_7d
    FROM DailyRevenue
)

-- Final Output: Rank the highest momentum weeks per property
SELECT 
    property_id,
    booking_date,
    daily_total,
    ROUND(moving_avg_7d, 2) AS moving_avg_7d,
    DENSE_RANK() OVER (PARTITION BY property_id ORDER BY moving_avg_7d DESC) AS revenue_momentum_rank
FROM MovingAverages
ORDER BY property_id, booking_date DESC;