# Fund Transaction Data Pipeline

A small end-to-end data engineering project modelled on how Canadian mutual fund orders
flow between dealers and fund companies. Daily order files are loaded into an
**Oracle Database 23ai Free** instance, validated by a **PL/SQL package**, and summarized
into reports. All schema changes are deployed with **Liquibase**, and the daily run is
automated with a **bash** script on Linux.

## Architecture

```
data/orders_YYYY-MM-DD.csv ─┐
data/nav_prices.csv ────────┤
                            ▼
              etl/load_orders.py  (Python: extract, clean, bulk load)
                            │
                            ▼
                   STG_ORDERS (staging table)
                            │
                            ▼
          ORDER_PKG.PROCESS_BATCH  (PL/SQL validation + unit calculation)
                            │
               ┌────────────┴────────────┐
               ▼                         ▼
     ORDERS (accepted/rejected)     ETL_RUN_LOG (audit)
               │
               ▼
   V_DAILY_SUMMARY / V_REJECTIONS  →  reports/*.csv
```

## Data model

| Table | Purpose |
|---|---|
| `DEALERS` | Dealer firms that submit orders |
| `FUNDS` | Fund products with currency and minimum purchase |
| `ACCOUNTS` | Investor accounts, each linked to a dealer |
| `NAV_PRICES` | Daily net asset value per fund (composite key: fund + date) |
| `STG_ORDERS` | Raw staging area for each day's file |
| `ORDERS` | Final validated orders with units, NAV and status |
| `REJECT_CODES` | Reference list of validation error codes |
| `ETL_RUN_LOG` | One row per batch run for auditing and troubleshooting |

## Validation rules (PL/SQL)

| Code | Rule |
|---|---|
| E01 | Account must exist and be active |
| E02 | Fund code must exist |
| E03 | A NAV price must exist for the order date |
| E04 | Amount must be positive and meet the fund minimum for purchases |
| E05 | Order reference must be unique (duplicate files are caught) |
| E06 | Order type must be BUY or SELL |
| E07 | A sell cannot exceed the units the account holds |

Accepted orders get `units = ROUND(amount / NAV, 4)`.

## Tech stack

Oracle Database 23ai Free (Docker) · SQL · PL/SQL · Python (`python-oracledb`) ·
bash · Liquibase · Git

## How to run

Tested on Windows using WSL (Ubuntu) with Docker Desktop.

**1. Start Oracle**
```bash
docker compose up -d
docker logs -f fund-oracle   # wait for "DATABASE IS READY TO USE!"
```

**2. Deploy the schema with Liquibase**
```bash
docker run --rm -v "$PWD/liquibase:/liquibase/changelog" liquibase/liquibase \
  --search-path=/liquibase/changelog \
  --changelog-file=changelog-master.xml \
  --url=jdbc:oracle:thin:@host.docker.internal:1521/FREEPDB1 \
  --username=fund_app --password=FundApp123 update
```

**3. Install Python dependencies**
```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r etl/requirements.txt
```

**4. Run two business days**
```bash
./scripts/run_daily.sh 2026-10-22
./scripts/run_daily.sh 2026-10-23
```

## Expected results

| Batch | Accepted | Rejected | Rejections |
|---|---|---|---|
| 2026-10-22 | 4 | 3 | E01 closed account, E02 unknown fund, E04 below minimum |
| 2026-10-23 | 2 | 4 | E05 duplicate, E07 oversell, E06 bad type, E04 negative amount |

Reports are written to `reports/summary_<date>.csv` and `reports/rejections_<date>.csv`.

## Design decisions

- **Staging table first.** Raw data lands in `STG_ORDERS` so bad files never touch `ORDERS` directly.
- **Business rules live in PL/SQL.** Validation runs next to the data, so every client loading orders gets the same rules.
- **Rejected orders are kept, not dropped.** Dealers need to know what failed and why.
- **Audit log.** `ETL_RUN_LOG` records counts and errors for every run, and failures roll back cleanly.
- **Re-runnable.** NAV prices load with `MERGE`, and duplicate order references are caught.
- **Version-controlled schema.** Every table, index, view and package is a Liquibase changeset.

## Possible next steps

- Schedule the run with `cron`
- Add `utPLSQL` unit tests for the package
- Partition `ORDERS` by month for large volumes
- Move the pipeline to Azure Data Factory or Microsoft Fabric
