--liquibase formatted sql

--changeset ujala:002-idx-orders
CREATE INDEX idx_orders_acct_fund ON orders (account_id, fund_code, status);
CREATE INDEX idx_orders_date ON orders (order_date);

--changeset ujala:002-v-daily-summary runOnChange:true
CREATE OR REPLACE VIEW v_daily_summary AS
SELECT o.order_date,
       o.fund_code,
       f.fund_name,
       SUM(CASE WHEN o.status = 'ACCEPTED' AND o.order_type = 'BUY'  THEN o.amount ELSE 0 END) AS total_buys,
       SUM(CASE WHEN o.status = 'ACCEPTED' AND o.order_type = 'SELL' THEN o.amount ELSE 0 END) AS total_sells,
       SUM(CASE WHEN o.status = 'ACCEPTED' AND o.order_type = 'BUY'  THEN o.amount
                WHEN o.status = 'ACCEPTED' AND o.order_type = 'SELL' THEN -o.amount ELSE 0 END) AS net_flow,
       COUNT(CASE WHEN o.status = 'ACCEPTED' THEN 1 END) AS accepted_orders,
       COUNT(CASE WHEN o.status = 'REJECTED' THEN 1 END) AS rejected_orders
FROM   orders o
LEFT JOIN funds f ON f.fund_code = o.fund_code
GROUP BY o.order_date, o.fund_code, f.fund_name;

--changeset ujala:002-v-rejections runOnChange:true
CREATE OR REPLACE VIEW v_rejections AS
SELECT o.order_date, o.order_ref, o.account_id, o.fund_code,
       o.order_type, o.amount, o.reject_code, r.description
FROM   orders o
JOIN   reject_codes r ON r.reject_code = o.reject_code
WHERE  o.status = 'REJECTED';
