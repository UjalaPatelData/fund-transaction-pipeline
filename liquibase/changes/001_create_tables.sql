--liquibase formatted sql

--changeset ujala:001-dealers
CREATE TABLE dealers (
  dealer_code   VARCHAR2(4)   PRIMARY KEY,
  dealer_name   VARCHAR2(100) NOT NULL
);

--changeset ujala:001-funds
CREATE TABLE funds (
  fund_code     VARCHAR2(8)   PRIMARY KEY,
  fund_name     VARCHAR2(100) NOT NULL,
  currency      CHAR(3)       DEFAULT 'CAD' NOT NULL,
  min_purchase  NUMBER(12,2)  DEFAULT 500 NOT NULL
);

--changeset ujala:001-accounts
CREATE TABLE accounts (
  account_id    VARCHAR2(10)  PRIMARY KEY,
  dealer_code   VARCHAR2(4)   NOT NULL REFERENCES dealers(dealer_code),
  investor_name VARCHAR2(100) NOT NULL,
  status        VARCHAR2(10)  DEFAULT 'ACTIVE' NOT NULL
                CONSTRAINT chk_acct_status CHECK (status IN ('ACTIVE','CLOSED'))
);

--changeset ujala:001-nav-prices
CREATE TABLE nav_prices (
  fund_code     VARCHAR2(8)   NOT NULL REFERENCES funds(fund_code),
  price_date    DATE          NOT NULL,
  nav           NUMBER(12,4)  NOT NULL CONSTRAINT chk_nav_pos CHECK (nav > 0),
  CONSTRAINT pk_nav_prices PRIMARY KEY (fund_code, price_date)
);

--changeset ujala:001-reject-codes
CREATE TABLE reject_codes (
  reject_code   VARCHAR2(3)   PRIMARY KEY,
  description   VARCHAR2(200) NOT NULL
);

--changeset ujala:001-stg-orders
CREATE TABLE stg_orders (
  file_name     VARCHAR2(100),
  order_ref     VARCHAR2(20),
  account_id    VARCHAR2(10),
  fund_code     VARCHAR2(8),
  order_type    VARCHAR2(10),
  amount        NUMBER(14,2),
  order_date    DATE,
  loaded_at     TIMESTAMP DEFAULT SYSTIMESTAMP
);

--changeset ujala:001-orders
CREATE TABLE orders (
  order_id      NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  order_ref     VARCHAR2(20)  NOT NULL CONSTRAINT uq_order_ref UNIQUE,
  account_id    VARCHAR2(10),
  fund_code     VARCHAR2(8),
  order_type    VARCHAR2(10),
  amount        NUMBER(14,2),
  nav           NUMBER(12,4),
  units         NUMBER(16,4),
  order_date    DATE,
  status        VARCHAR2(10)  NOT NULL
                CONSTRAINT chk_order_status CHECK (status IN ('ACCEPTED','REJECTED')),
  reject_code   VARCHAR2(3)   REFERENCES reject_codes(reject_code),
  processed_at  TIMESTAMP     DEFAULT SYSTIMESTAMP
);

--changeset ujala:001-etl-run-log
CREATE TABLE etl_run_log (
  run_id        NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  batch_date    DATE,
  rows_staged   NUMBER,
  rows_accepted NUMBER,
  rows_rejected NUMBER,
  run_status    VARCHAR2(10),
  error_message VARCHAR2(4000),
  started_at    TIMESTAMP DEFAULT SYSTIMESTAMP,
  finished_at   TIMESTAMP
);
