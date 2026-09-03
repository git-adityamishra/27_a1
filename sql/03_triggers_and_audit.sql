-- 1. FIRST: Define the function
CREATE OR REPLACE FUNCTION log_wallet_balance_change()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.wallet_balance <> OLD.wallet_balance THEN
        INSERT INTO wallet_audit_logs (
            guest_id,
            amount_changed,
            action_type,
            balance_after,
            timestamp
        ) VALUES (
            NEW.id,
            NEW.wallet_balance - OLD.wallet_balance,
            CASE 
                WHEN NEW.wallet_balance > OLD.wallet_balance THEN 'CREDIT'
                ELSE 'DEBIT'
            END,
            NEW.wallet_balance,
            CURRENT_TIMESTAMP
        );
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 2. SECOND: Drop the old trigger (if it exists) and attach the new one
DROP TRIGGER IF EXISTS trg_wallet_balance_audit ON guests;

CREATE TRIGGER trg_wallet_balance_audit
AFTER UPDATE OF wallet_balance ON guests
FOR EACH ROW
EXECUTE FUNCTION log_wallet_balance_change();