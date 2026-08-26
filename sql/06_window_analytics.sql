-- CTE 1: Calculate raw revenue for each individual day
WITH DailyRevenue AS (
    SELECT 
        DATE(created_at) AS booking_date,
        SUM(total_cost) AS daily_total
    FROM bookings
    GROUP BY DATE(created_at)
),

-- CTE 2: Apply the Sliding Window to calculate the 7-day average
MovingAverages AS (
    SELECT 
        booking_date,
        daily_total,
        -- The Window Function: Average the current row and the 6 rows before it
        AVG(daily_total) OVER (
            ORDER BY booking_date 
            ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
        ) AS moving_avg_7d
    FROM DailyRevenue
)

-- Final Output: Select the data and use DENSE_RANK() to find the best weeks
SELECT 
    booking_date,
    daily_total,
    ROUND(moving_avg_7d, 2) AS moving_avg_7d,
    -- Rank the days based on how high their 7-day moving average was
    DENSE_RANK() OVER (ORDER BY moving_avg_7d DESC) AS revenue_momentum_rank
FROM MovingAverages
ORDER BY booking_date DESC;