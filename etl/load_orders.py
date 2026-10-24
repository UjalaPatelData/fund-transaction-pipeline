"""
Daily ETL for fund orders.

Extract : read a daily CSV order file
Transform: clean values (trim, upper-case, parse dates and amounts)
Load    : bulk insert into STG_ORDERS, then call ORDER_PKG.PROCESS_BATCH
          which validates each order in PL/SQL and writes ORDERS
Report  : export the daily summary and rejections to CSV
"""
import argparse
import csv
import os
import sys
from datetime import datetime
from decimal import Decimal, InvalidOperation

import oracledb

DSN = os.getenv("DB_DSN", "localhost:1521/FREEPDB1")
USER = os.getenv("DB_USER", "fund_app")
PASSWORD = os.getenv("DB_PASSWORD", "FundApp123")


def parse_date(value):
    return datetime.strptime(value.strip(), "%Y-%m-%d")


def parse_amount(value):
    try:
        return Decimal(value.strip())
    except (InvalidOperation, AttributeError):
        return None


def extract_transform(path):
    """Read the CSV and return cleaned rows ready for loading."""
    rows, skipped = [], 0
    file_name = os.path.basename(path)
    with open(path, newline="", encoding="utf-8") as f:
        for line_no, rec in enumerate(csv.DictReader(f), start=2):
            try:
                rows.append((
                    file_name,
                    rec["order_ref"].strip().upper(),
                    rec["account_id"].strip().upper(),
                    rec["fund_code"].strip().upper(),
                    rec["order_type"].strip().upper(),
                    parse_amount(rec["amount"]),
                    parse_date(rec["order_date"]),
                ))
            except (KeyError, ValueError) as err:
                skipped += 1
                print(f"  skipped line {line_no}: {err}", file=sys.stderr)
    return rows, skipped


def load_nav(cur, path):
    """Upsert NAV prices with a MERGE so the script can be re-run safely."""
    with open(path, newline="", encoding="utf-8") as f:
        data = [(r["fund_code"].strip(), parse_date(r["price_date"]), Decimal(r["nav"]))
                for r in csv.DictReader(f)]
    cur.executemany("""
        MERGE INTO nav_prices t
        USING (SELECT :1 fund_code, :2 price_date, :3 nav FROM dual) s
        ON (t.fund_code = s.fund_code AND t.price_date = s.price_date)
        WHEN MATCHED THEN UPDATE SET t.nav = s.nav
        WHEN NOT MATCHED THEN INSERT (fund_code, price_date, nav)
                              VALUES (s.fund_code, s.price_date, s.nav)""", data)
    return len(data)


def export_query(cur, sql, params, out_path):
    cur.execute(sql, params)
    cols = [d[0] for d in cur.description]
    with open(out_path, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(cols)
        w.writerows(cur.fetchall())


def main():
    p = argparse.ArgumentParser(description="Load a daily fund order file")
    p.add_argument("--orders", required=True, help="path to orders CSV")
    p.add_argument("--nav", required=True, help="path to NAV prices CSV")
    p.add_argument("--date", required=True, help="batch date YYYY-MM-DD")
    p.add_argument("--report-dir", default="reports")
    args = p.parse_args()

    batch_date = parse_date(args.date)
    rows, skipped = extract_transform(args.orders)
    print(f"Extracted {len(rows)} rows ({skipped} skipped) from {args.orders}")

    with oracledb.connect(user=USER, password=PASSWORD, dsn=DSN) as conn:
        with conn.cursor() as cur:
            print(f"Loaded {load_nav(cur, args.nav)} NAV prices")
            cur.executemany("""
                INSERT INTO stg_orders (file_name, order_ref, account_id, fund_code,
                                        order_type, amount, order_date)
                VALUES (:1, :2, :3, :4, :5, :6, :7)""", rows)
            conn.commit()

            cur.callproc("order_pkg.process_batch", [batch_date])

            cur.execute("""SELECT rows_staged, rows_accepted, rows_rejected, run_status
                           FROM etl_run_log WHERE batch_date = :1
                           ORDER BY run_id DESC FETCH FIRST 1 ROW ONLY""", [batch_date])
            staged, accepted, rejected, status = cur.fetchone()
            print(f"Run {status}: {staged} staged, {accepted} accepted, {rejected} rejected")

            os.makedirs(args.report_dir, exist_ok=True)
            export_query(cur, "SELECT * FROM v_daily_summary WHERE order_date = :1 ORDER BY fund_code",
                         [batch_date], os.path.join(args.report_dir, f"summary_{args.date}.csv"))
            export_query(cur, "SELECT * FROM v_rejections WHERE order_date = :1 ORDER BY order_ref",
                         [batch_date], os.path.join(args.report_dir, f"rejections_{args.date}.csv"))
            print(f"Reports written to {args.report_dir}/")


if __name__ == "__main__":
    main()
