CREATE TABLE guests (
    id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name VARCHAR,
    wallet_balance DECIMAL(10,2),
    CHECK (wallet_balance >= 0.00)
);

CREATE TABLE properties (
    id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    title VARCHAR(255) NOT NULL,
    base_price NUMERIC(10,2) NOT NULL,
    latitude NUMERIC(9,6) NOT NULL,
    longitude NUMERIC(9,6) NOT NULL,
    CONSTRAINT properties_latitude_check
        CHECK (latitude >= -90 AND latitude <= 90),
    CONSTRAINT properties_longitude_check
        CHECK (longitude >= -180 AND longitude <= 180)
);

CREATE TABLE bookings (
    id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    guest_id INTEGER NOT NULL,
    property_id INTEGER NOT NULL,

    total_cost NUMERIC(10,2) NOT NULL,

    status VARCHAR(20) NOT NULL,

    created_at TIMESTAMPTZ NOT NULL,

    CONSTRAINT bookings_guest_fk
        FOREIGN KEY (guest_id)
        REFERENCES guests(id),

    CONSTRAINT bookings_property_fk
        FOREIGN KEY (property_id)
        REFERENCES properties(id),

    CONSTRAINT bookings_status_check
        CHECK (status IN ('CONFIRMED', 'CHECKED_IN', 'COMPLETED'))
);

CREATE TABLE wallet_audit_logs (
    id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    guest_id INTEGER NOT NULL,

    amount_changed NUMERIC(10,2) NOT NULL,

    action_type VARCHAR(20) NOT NULL,

    balance_after NUMERIC(10,2) NOT NULL,

    timestamp TIMESTAMPTZ NOT NULL,

    CONSTRAINT wallet_audit_guest_fk
        FOREIGN KEY (guest_id)
        REFERENCES guests(id),

    CONSTRAINT wallet_audit_balance_check
        CHECK (balance_after >= 0.00)
);