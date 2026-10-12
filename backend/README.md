# BloodNet API

This small Node.js API serves the frontend and connects it to the Oracle schema. Database credentials stay in `backend/.env`; the browser never receives them.

## Start locally with Oracle XE

1. Run `01_schema.sql`, `02_plsql.sql`, and `03_sample_data.sql` in SQL Developer as the project user described in the root README.
2. Open a terminal in this `backend` folder and run `npm install`.
3. Copy `.env.example` to `.env`. Set `ORACLE_USER` and `ORACLE_PASSWORD` to the account used for the scripts. The example connect string is `localhost:1521/XEPDB1`, the common Oracle XE pluggable database service.
4. Run `npm start`, then open <http://localhost:3000>.

The overview shows an Oracle connection state. If your listener uses a different service name or port, update `ORACLE_CONNECT_STRING` in `.env`. Do not commit `.env` or share its password.

## What is connected

- Blood stock, request queue, donors, organ waitlist, dashboard counts, and audit activity are read from Oracle.
- Creating a request, donation, donor, or waitlist entry writes to Oracle.
- Fulfilling a blood request and finding an organ match call the PL/SQL packages in `02_plsql.sql`.
- The browser uses the same-origin `/api` routes. SQL values are sent as bind variables.

There is no sign-in or authorization layer in this course-project API. Keep it on your own machine for the demo; do not expose the server to a public network.
