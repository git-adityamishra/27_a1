CREATE OR REPLACE PROCEDURE create_booking(
    p_guest_id INTEGER,
    p_property_id INTEGER,
    p_total_cost NUMERIC(10,2)
)
LANGUAGE plpgsql
AS $$
BEGIN

    -- A booking cost must be positive.
    IF p_total_cost <= 0 THEN
        RAISE EXCEPTION 'Booking cost must be greater than zero';
    END IF;

    -- Deduct the amount only if the guest has enough balance.
    UPDATE guests
    SET wallet_balance = wallet_balance - p_total_cost
    WHERE id = p_guest_id AND wallet_balance >= p_total_cost;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Insufficient balance or guest not found';
    END IF;

    INSERT INTO bookings (guest_id, property_id, total_cost, status, created_at)
    VALUES (p_guest_id, p_property_id, p_total_cost, 'CONFIRMED', CURRENT_TIMESTAMP);

    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE NOTICE 'Transaction gracefully rolled back: %', SQLERRM;
END;
$$;