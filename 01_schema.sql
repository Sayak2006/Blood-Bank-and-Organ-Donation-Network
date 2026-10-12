-- =====================================================================
-- BloodNet: Blood Bank & Organ Donation Network
-- File 1 of 4: schema (sequences, tables, indexes, views)
--
-- Requires Oracle 12c or later (uses DEFAULT seq.NEXTVAL).
-- Oracle XE 18c / 21c works fine. Run as your project user.
-- Safe to re-run: it drops the project objects first.
-- =====================================================================

SET DEFINE OFF

-- ---------------------------------------------------------------------
-- Clean slate
-- ---------------------------------------------------------------------
BEGIN
    FOR t IN (SELECT table_name FROM user_tables
               WHERE table_name IN ('AUDIT_LOG', 'ORGAN_MATCH', 'ORGAN_WAITLIST',
                                    'ORGAN_DONOR', 'BLOOD_ISSUE', 'BLOOD_REQUEST',
                                    'BLOOD_UNIT', 'PATIENT', 'DONOR',
                                    'BLOOD_BANK', 'HOSPITAL')) LOOP
        EXECUTE IMMEDIATE 'DROP TABLE ' || t.table_name || ' CASCADE CONSTRAINTS PURGE';
    END LOOP;

    FOR s IN (SELECT sequence_name FROM user_sequences
               WHERE sequence_name LIKE 'SEQ\_%' ESCAPE '\') LOOP
        EXECUTE IMMEDIATE 'DROP SEQUENCE ' || s.sequence_name;
    END LOOP;
END;
/

-- ---------------------------------------------------------------------
-- Sequences (start high so they never collide with the sample data IDs)
-- ---------------------------------------------------------------------
CREATE SEQUENCE seq_hospital    START WITH 1000;
CREATE SEQUENCE seq_bank        START WITH 1000;
CREATE SEQUENCE seq_donor       START WITH 1000;
CREATE SEQUENCE seq_patient     START WITH 1000;
CREATE SEQUENCE seq_unit        START WITH 1000;
CREATE SEQUENCE seq_request     START WITH 1000;
CREATE SEQUENCE seq_issue       START WITH 1000;
CREATE SEQUENCE seq_organ_donor START WITH 1000;
CREATE SEQUENCE seq_waitlist    START WITH 1000;
CREATE SEQUENCE seq_match       START WITH 1000;
CREATE SEQUENCE seq_audit       START WITH 1;

-- ---------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------
CREATE TABLE hospital (
    hospital_id    NUMBER        DEFAULT seq_hospital.NEXTVAL PRIMARY KEY,
    name           VARCHAR2(100) NOT NULL,
    city           VARCHAR2(50)  NOT NULL,
    license_no     VARCHAR2(30)  NOT NULL UNIQUE,
    hospital_type  VARCHAR2(10)  NOT NULL
        CONSTRAINT ck_hospital_type CHECK (hospital_type IN ('GOVT', 'PRIVATE', 'TRUST'))
);

CREATE TABLE blood_bank (
    bank_id      NUMBER        DEFAULT seq_bank.NEXTVAL PRIMARY KEY,
    name         VARCHAR2(100) NOT NULL,
    city         VARCHAR2(50)  NOT NULL,
    hospital_id  NUMBER
        CONSTRAINT fk_bank_hospital REFERENCES hospital (hospital_id)
);

CREATE TABLE donor (
    donor_id            NUMBER        DEFAULT seq_donor.NEXTVAL PRIMARY KEY,
    name                VARCHAR2(100) NOT NULL,
    dob                 DATE          NOT NULL,
    gender              CHAR(1)       NOT NULL
        CONSTRAINT ck_donor_gender CHECK (gender IN ('M', 'F', 'O')),
    blood_group         VARCHAR2(3)   NOT NULL
        CONSTRAINT ck_donor_bg CHECK (blood_group IN ('A+','A-','B+','B-','AB+','AB-','O+','O-')),
    phone               VARCHAR2(15),
    city                VARCHAR2(50)  NOT NULL,
    last_donation_date  DATE
);

CREATE TABLE patient (
    patient_id   NUMBER        DEFAULT seq_patient.NEXTVAL PRIMARY KEY,
    name         VARCHAR2(100) NOT NULL,
    dob          DATE          NOT NULL,
    blood_group  VARCHAR2(3)   NOT NULL
        CONSTRAINT ck_patient_bg CHECK (blood_group IN ('A+','A-','B+','B-','AB+','AB-','O+','O-')),
    hospital_id  NUMBER        NOT NULL
        CONSTRAINT fk_patient_hospital REFERENCES hospital (hospital_id),
    urgency      VARCHAR2(10)  DEFAULT 'MEDIUM' NOT NULL
        CONSTRAINT ck_patient_urgency CHECK (urgency IN ('LOW', 'MEDIUM', 'HIGH', 'CRITICAL'))
);

CREATE TABLE blood_unit (
    unit_id       NUMBER       DEFAULT seq_unit.NEXTVAL PRIMARY KEY,
    bank_id       NUMBER       NOT NULL
        CONSTRAINT fk_unit_bank REFERENCES blood_bank (bank_id),
    donor_id      NUMBER       NOT NULL
        CONSTRAINT fk_unit_donor REFERENCES donor (donor_id),
    blood_group   VARCHAR2(3)  NOT NULL
        CONSTRAINT ck_unit_bg CHECK (blood_group IN ('A+','A-','B+','B-','AB+','AB-','O+','O-')),
    component     VARCHAR2(12) DEFAULT 'WHOLE_BLOOD' NOT NULL
        CONSTRAINT ck_unit_component CHECK (component IN ('WHOLE_BLOOD', 'RBC', 'PLASMA', 'PLATELETS')),
    collected_on  DATE         DEFAULT TRUNC(SYSDATE) NOT NULL,
    expiry_on     DATE         NOT NULL,   -- filled by trigger if not supplied
    status        VARCHAR2(10) DEFAULT 'AVAILABLE' NOT NULL
        CONSTRAINT ck_unit_status CHECK (status IN ('AVAILABLE', 'RESERVED', 'ISSUED', 'EXPIRED')),
    CONSTRAINT ck_unit_dates CHECK (expiry_on > collected_on)
);

CREATE TABLE blood_request (
    request_id    NUMBER       DEFAULT seq_request.NEXTVAL PRIMARY KEY,
    hospital_id   NUMBER       NOT NULL
        CONSTRAINT fk_req_hospital REFERENCES hospital (hospital_id),
    patient_id    NUMBER       NOT NULL
        CONSTRAINT fk_req_patient REFERENCES patient (patient_id),
    blood_group   VARCHAR2(3)  NOT NULL
        CONSTRAINT ck_req_bg CHECK (blood_group IN ('A+','A-','B+','B-','AB+','AB-','O+','O-')),
    component     VARCHAR2(12) DEFAULT 'WHOLE_BLOOD' NOT NULL
        CONSTRAINT ck_req_component CHECK (component IN ('WHOLE_BLOOD', 'RBC', 'PLASMA', 'PLATELETS')),
    units_needed  NUMBER(3)    NOT NULL
        CONSTRAINT ck_req_units CHECK (units_needed > 0),
    status        VARCHAR2(10) DEFAULT 'PENDING' NOT NULL
        CONSTRAINT ck_req_status CHECK (status IN ('PENDING', 'FULFILLED', 'REJECTED')),
    requested_on  DATE         DEFAULT SYSDATE NOT NULL
);

CREATE TABLE blood_issue (
    issue_id    NUMBER DEFAULT seq_issue.NEXTVAL PRIMARY KEY,
    request_id  NUMBER NOT NULL
        CONSTRAINT fk_issue_request REFERENCES blood_request (request_id),
    unit_id     NUMBER NOT NULL
        CONSTRAINT uq_issue_unit UNIQUE            -- a unit can be issued only once
        CONSTRAINT fk_issue_unit REFERENCES blood_unit (unit_id),
    issued_on   DATE   DEFAULT SYSDATE NOT NULL
);

CREATE TABLE organ_donor (
    organ_donor_id  NUMBER       DEFAULT seq_organ_donor.NEXTVAL PRIMARY KEY,
    donor_id        NUMBER       NOT NULL
        CONSTRAINT fk_od_donor REFERENCES donor (donor_id),
    organ_type      VARCHAR2(10) NOT NULL
        CONSTRAINT ck_od_organ CHECK (organ_type IN ('KIDNEY', 'LIVER', 'HEART', 'LUNG', 'PANCREAS', 'CORNEA')),
    donor_kind      VARCHAR2(10) NOT NULL
        CONSTRAINT ck_od_kind CHECK (donor_kind IN ('LIVING', 'DECEASED')),
    hla_type        VARCHAR2(30),
    consent_date    DATE         NOT NULL,
    status          VARCHAR2(12) DEFAULT 'AVAILABLE' NOT NULL
        CONSTRAINT ck_od_status CHECK (status IN ('AVAILABLE', 'ALLOCATED', 'TRANSPLANTED', 'WITHDRAWN'))
);

CREATE TABLE organ_waitlist (
    waitlist_id      NUMBER       DEFAULT seq_waitlist.NEXTVAL PRIMARY KEY,
    patient_id       NUMBER       NOT NULL
        CONSTRAINT fk_wl_patient REFERENCES patient (patient_id),
    organ_type       VARCHAR2(10) NOT NULL
        CONSTRAINT ck_wl_organ CHECK (organ_type IN ('KIDNEY', 'LIVER', 'HEART', 'LUNG', 'PANCREAS', 'CORNEA')),
    medical_urgency  NUMBER(2)    NOT NULL
        CONSTRAINT ck_wl_urgency CHECK (medical_urgency BETWEEN 1 AND 10),
    hla_type         VARCHAR2(30),
    registered_on    DATE         DEFAULT SYSDATE NOT NULL,
    status           VARCHAR2(12) DEFAULT 'WAITING' NOT NULL
        CONSTRAINT ck_wl_status CHECK (status IN ('WAITING', 'MATCHED', 'TRANSPLANTED', 'REMOVED'))
);

CREATE TABLE organ_match (
    match_id        NUMBER       DEFAULT seq_match.NEXTVAL PRIMARY KEY,
    organ_donor_id  NUMBER       NOT NULL
        CONSTRAINT fk_match_od REFERENCES organ_donor (organ_donor_id),
    waitlist_id     NUMBER       NOT NULL
        CONSTRAINT fk_match_wl REFERENCES organ_waitlist (waitlist_id),
    matched_on      DATE         DEFAULT SYSDATE NOT NULL,
    surgery_date    DATE,
    outcome         VARCHAR2(10) DEFAULT 'PENDING' NOT NULL
        CONSTRAINT ck_match_outcome CHECK (outcome IN ('PENDING', 'SUCCESS', 'FAILED', 'CANCELLED'))
);

CREATE TABLE audit_log (
    log_id      NUMBER        DEFAULT seq_audit.NEXTVAL PRIMARY KEY,
    table_name  VARCHAR2(30)  NOT NULL,
    action      VARCHAR2(10)  NOT NULL,
    changed_by  VARCHAR2(30)  NOT NULL,
    changed_on  DATE          DEFAULT SYSDATE NOT NULL,
    details     VARCHAR2(400)
);

-- ---------------------------------------------------------------------
-- Indexes (on columns the procedures and reports filter by)
-- ---------------------------------------------------------------------
CREATE INDEX idx_donor_bg        ON donor (blood_group);
CREATE INDEX idx_unit_bg_status  ON blood_unit (blood_group, status);
CREATE INDEX idx_unit_expiry     ON blood_unit (expiry_on);
CREATE INDEX idx_unit_bank       ON blood_unit (bank_id);
CREATE INDEX idx_req_status      ON blood_request (status);
CREATE INDEX idx_wl_organ_status ON organ_waitlist (organ_type, status);
CREATE INDEX idx_audit_table     ON audit_log (table_name, changed_on);

-- ---------------------------------------------------------------------
-- Views
-- ---------------------------------------------------------------------

-- Current usable stock per bank, blood group and component
CREATE OR REPLACE VIEW v_blood_stock AS
SELECT b.bank_id,
       b.name        AS bank_name,
       b.city,
       u.blood_group,
       u.component,
       COUNT(*)      AS units_available
  FROM blood_unit u
  JOIN blood_bank b ON b.bank_id = u.bank_id
 WHERE u.status = 'AVAILABLE'
   AND u.expiry_on >= TRUNC(SYSDATE)
 GROUP BY b.bank_id, b.name, b.city, u.blood_group, u.component;

-- Open requests for HIGH / CRITICAL patients, most urgent first
CREATE OR REPLACE VIEW v_pending_critical_requests AS
SELECT r.request_id,
       h.name        AS hospital,
       p.name        AS patient,
       p.urgency,
       r.blood_group,
       r.component,
       r.units_needed,
       r.requested_on
  FROM blood_request r
  JOIN hospital h ON h.hospital_id = r.hospital_id
  JOIN patient  p ON p.patient_id  = r.patient_id
 WHERE r.status = 'PENDING'
   AND p.urgency IN ('HIGH', 'CRITICAL')
 ORDER BY CASE p.urgency WHEN 'CRITICAL' THEN 1 ELSE 2 END, r.requested_on;

-- Organ waitlist queue per organ type (urgency first, then who waited longest)
CREATE OR REPLACE VIEW v_organ_waitlist_ranking AS
SELECT w.waitlist_id,
       w.organ_type,
       p.name         AS patient_name,
       p.blood_group,
       w.medical_urgency,
       w.registered_on,
       RANK() OVER (PARTITION BY w.organ_type
                    ORDER BY w.medical_urgency DESC, w.registered_on ASC) AS queue_position
  FROM organ_waitlist w
  JOIN patient p ON p.patient_id = w.patient_id
 WHERE w.status = 'WAITING';

-- Donors who can donate blood right now (age 18-65, 90+ days since last donation)
CREATE OR REPLACE VIEW v_eligible_donors AS
SELECT donor_id, name, blood_group, city, last_donation_date
  FROM donor
 WHERE dob <= ADD_MONTHS(TRUNC(SYSDATE), -12 * 18)
   AND dob >  ADD_MONTHS(TRUNC(SYSDATE), -12 * 66)
   AND (last_donation_date IS NULL OR last_donation_date <= TRUNC(SYSDATE) - 90);
