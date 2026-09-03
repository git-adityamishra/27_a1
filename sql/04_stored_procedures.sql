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
    WHERE id = p_guest_id
      AND wallet_balance >= p_total_cost;

    -- No row means either the guest does not exist
    -- or the guest does not have sufficient balance.
    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Guest does not exist or has insufficient wallet balance';
    END IF;

    -- Insert the booking.
    INSERT INTO bookings (
        guest_id,
        property_id,
        total_cost,
        status,
        created_at
    )
    VALUES (
        p_guest_id,
        p_property_id,
        p_total_cost,
        'CONFIRMED',
        CURRENT_TIMESTAMP
    );

    -- Both operations succeeded.
    COMMIT;

END;
$$;