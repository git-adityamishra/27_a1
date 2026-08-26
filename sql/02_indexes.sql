CREATE UNIQUE INDEX idx_active_stay 
ON bookings (guest_id) 
WHERE status = 'CHECKED_IN';