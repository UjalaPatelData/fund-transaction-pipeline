--liquibase formatted sql

--changeset ujala:004-order-pkg-spec runOnChange:true splitStatements:false
CREATE OR REPLACE PACKAGE order_pkg AS
  -- Returns current accepted unit holdings for an account in a fund
  FUNCTION get_holdings (p_account_id IN VARCHAR2,
                         p_fund_code  IN VARCHAR2) RETURN NUMBER;

  -- Validates one order and returns NULL if valid, otherwise a reject code
  FUNCTION validate_order (p_order_ref  IN VARCHAR2,
                           p_account_id IN VARCHAR2,
                           p_fund_code  IN VARCHAR2,
                           p_order_type IN VARCHAR2,
                           p_amount     IN NUMBER,
                           p_order_date IN DATE) RETURN VARCHAR2;

  -- Processes all staged orders for a batch date into ORDERS, logs the run
  PROCEDURE process_batch (p_batch_date IN DATE);
END order_pkg;

--changeset ujala:004-order-pkg-body runOnChange:true splitStatements:false
CREATE OR REPLACE PACKAGE BODY order_pkg AS

  FUNCTION get_nav (p_fund_code IN VARCHAR2, p_date IN DATE) RETURN NUMBER IS
    v_nav nav_prices.nav%TYPE;
  BEGIN
    SELECT nav INTO v_nav
    FROM   nav_prices
    WHERE  fund_code = p_fund_code
    AND    price_date = TRUNC(p_date);
    RETURN v_nav;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN RETURN NULL;
  END get_nav;

  FUNCTION get_holdings (p_account_id IN VARCHAR2,
                         p_fund_code  IN VARCHAR2) RETURN NUMBER IS
    v_units NUMBER;
  BEGIN
    SELECT NVL(SUM(CASE order_type WHEN 'BUY' THEN units ELSE -units END), 0)
    INTO   v_units
    FROM   orders
    WHERE  account_id = p_account_id
    AND    fund_code  = p_fund_code
    AND    status     = 'ACCEPTED';
    RETURN v_units;
  END get_holdings;

  FUNCTION validate_order (p_order_ref  IN VARCHAR2,
                           p_account_id IN VARCHAR2,
                           p_fund_code  IN VARCHAR2,
                           p_order_type IN VARCHAR2,
                           p_amount     IN NUMBER,
                           p_order_date IN DATE) RETURN VARCHAR2 IS
    v_count   NUMBER;
    v_min     funds.min_purchase%TYPE;
    v_nav     NUMBER;
  BEGIN
    -- E05: duplicate order reference
    SELECT COUNT(*) INTO v_count FROM orders WHERE order_ref = p_order_ref;
    IF v_count > 0 THEN RETURN 'E05'; END IF;

    -- E01: account must exist and be active
    SELECT COUNT(*) INTO v_count
    FROM   accounts
    WHERE  account_id = p_account_id AND status = 'ACTIVE';
    IF v_count = 0 THEN RETURN 'E01'; END IF;

    -- E02: fund must exist
    BEGIN
      SELECT min_purchase INTO v_min FROM funds WHERE fund_code = p_fund_code;
    EXCEPTION
      WHEN NO_DATA_FOUND THEN RETURN 'E02';
    END;

    -- E06: order type
    IF p_order_type NOT IN ('BUY', 'SELL') OR p_order_type IS NULL THEN
      RETURN 'E06';
    END IF;

    -- E04: amount checks
    IF p_amount IS NULL OR p_amount <= 0 THEN RETURN 'E04'; END IF;
    IF p_order_type = 'BUY' AND p_amount < v_min THEN RETURN 'E04'; END IF;

    -- E03: NAV must exist for the order date
    v_nav := get_nav(p_fund_code, p_order_date);
    IF v_nav IS NULL THEN RETURN 'E03'; END IF;

    -- E07: cannot sell more units than held
    IF p_order_type = 'SELL'
       AND ROUND(p_amount / v_nav, 4) > get_holdings(p_account_id, p_fund_code) THEN
      RETURN 'E07';
    END IF;

    RETURN NULL;
  END validate_order;

  PROCEDURE process_batch (p_batch_date IN DATE) IS
    v_run_id    etl_run_log.run_id%TYPE;
    v_reject    VARCHAR2(3);
    v_nav       NUMBER;
    v_staged    NUMBER := 0;
    v_accepted  NUMBER := 0;
    v_rejected  NUMBER := 0;
    v_err       VARCHAR2(4000);
  BEGIN
    INSERT INTO etl_run_log (batch_date, run_status)
    VALUES (TRUNC(p_batch_date), 'RUNNING')
    RETURNING run_id INTO v_run_id;

    -- Process in order_ref order so earlier BUYs count toward later SELLs
    FOR r IN (SELECT * FROM stg_orders
              WHERE  order_date = TRUNC(p_batch_date)
              ORDER BY order_ref) LOOP
      v_staged := v_staged + 1;
      v_reject := validate_order(r.order_ref, r.account_id, r.fund_code,
                                 UPPER(TRIM(r.order_type)), r.amount, r.order_date);

      IF v_reject = 'E05' THEN
        -- Duplicate: record already exists, count it but do not insert again
        v_rejected := v_rejected + 1;
      ELSIF v_reject IS NOT NULL THEN
        INSERT INTO orders (order_ref, account_id, fund_code, order_type,
                            amount, order_date, status, reject_code)
        VALUES (r.order_ref, r.account_id, r.fund_code, UPPER(TRIM(r.order_type)),
                r.amount, r.order_date, 'REJECTED', v_reject);
        v_rejected := v_rejected + 1;
      ELSE
        v_nav := get_nav(r.fund_code, r.order_date);
        INSERT INTO orders (order_ref, account_id, fund_code, order_type,
                            amount, nav, units, order_date, status)
        VALUES (r.order_ref, r.account_id, r.fund_code, UPPER(TRIM(r.order_type)),
                r.amount, v_nav, ROUND(r.amount / v_nav, 4), r.order_date, 'ACCEPTED');
        v_accepted := v_accepted + 1;
      END IF;
    END LOOP;

    DELETE FROM stg_orders WHERE order_date = TRUNC(p_batch_date);

    UPDATE etl_run_log
    SET    rows_staged = v_staged, rows_accepted = v_accepted,
           rows_rejected = v_rejected, run_status = 'SUCCESS',
           finished_at = SYSTIMESTAMP
    WHERE  run_id = v_run_id;
    COMMIT;
  EXCEPTION
    WHEN OTHERS THEN
      v_err := SQLERRM;
      ROLLBACK;
      INSERT INTO etl_run_log (batch_date, run_status, error_message, finished_at)
      VALUES (TRUNC(p_batch_date), 'FAILED', v_err, SYSTIMESTAMP);
      COMMIT;
      RAISE;
  END process_batch;

END order_pkg;
