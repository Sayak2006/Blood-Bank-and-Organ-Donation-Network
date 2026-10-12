# BloodNet: Blood Bank & Organ Donation Network (Oracle / PL-SQL)

DBMS course project. Four scripts, run in this order as one Oracle user
(for example `bloodnet`) using SQL Developer "Run Script" (F5) or SQL*Plus.

| Order | File | What it does |
|---|---|---|
| 1 | `01_schema.sql` | Sequences, 11 tables with constraints, indexes, 4 views. Safe to re-run (drops first). |
| 2 | `02_plsql.sql` | `log_audit`, `blood_mgmt_pkg`, `organ_mgmt_pkg`, 5 triggers, nightly scheduler job. |
| 3 | `03_sample_data.sql` | 5 hospitals, 4 banks, 20 donors, 10 patients, 16 blood units, 5 requests, 3 organ donors, 7 waitlist entries. |
| 4 | `04_tests_and_reports.sql` | 11 test scenarios and 7 report queries. Expected results are in the comments. |

## Requirements
- Oracle Database 12c or later (Oracle XE 18c / 21c is fine). Needed for `DEFAULT seq.NEXTVAL`.
- User privileges: `GRANT CONNECT, RESOURCE, CREATE VIEW, CREATE JOB TO bloodnet;`
  (and a tablespace quota, e.g. `ALTER USER bloodnet QUOTA UNLIMITED ON USERS;`)

## Where each concept lives
| Concept | Where |
|---|---|
| Procedures | `register_donation`, `fulfill_request`, `expire_units`, `find_organ_match`, `complete_transplant`, `log_audit` |
| Functions | `is_compatible`, `is_abo_compatible`, `is_donor_eligible`, `shelf_life_days` |
| Cursors | explicit cursors in `fulfill_request` (parameterised, `FOR UPDATE SKIP LOCKED`), `expire_units` (`WHERE CURRENT OF`), `find_organ_match` |
| Triggers | `trg_blood_unit_bi` (fills fields, enforces eligibility), plus four audit triggers |
| Custom exceptions | `donor_ineligible`, `insufficient_stock`, `no_match_found` |
| Packages | `blood_mgmt_pkg`, `organ_mgmt_pkg` |
| Scheduler | `JOB_EXPIRE_BLOOD_UNITS` (daily 00:05) |
| Views | `v_blood_stock`, `v_pending_critical_requests`, `v_organ_waitlist_ranking`, `v_eligible_donors` |
| Window function | `RANK()` in `v_organ_waitlist_ranking` |

## Business rules implemented
- Donor must be 18-65 and at least 90 days since the last donation.
- Shelf life: whole blood 35 days, RBC 42, plasma 365, platelets 5.
- Blood requests are all-or-nothing: exact blood group first, then earliest expiry.
- Organ matching score = urgency x 10 + months waited + 5 for an identical blood group.

## Simplifications worth stating in your report
- Blood compatibility uses red cell rules (ABO + Rh) for every component. Real plasma rules are reversed.
- Organ matching checks ABO only and ranks on urgency and waiting time. HLA is stored but not scored.
- Each donation creates one unit; multi-component donations (apheresis) are not modelled.
- Procedures `COMMIT` internally to keep the demo simple.

## Frontend connected to Oracle

The browser app now reads and writes through a local Node API. After running the schema, PL/SQL, and sample-data scripts above:

1. In PowerShell, run `Copy-Item backend/.env.example backend/.env` from the project folder.
2. Edit `backend/.env` and enter the password for the Oracle user that owns the project. The sample connection string is `localhost:1521/XEPDB1` for local Oracle XE.
3. Open a terminal in `backend` and run `npm install`, then `npm start`.
4. Open <http://localhost:3000>.

Keep the password in `backend/.env`; don’t paste it into the frontend or commit that file. More details are in [backend/README.md](backend/README.md).
