-- =====================================================================
-- BloodNet: Blood Bank & Organ Donation Network
-- File 2 of 4: PL/SQL (audit procedure, two packages, triggers, job)
--
-- Run AFTER 01_schema.sql. In SQL Developer use "Run Script" (F5).
-- =====================================================================

SET DEFINE OFF
SET SERVEROUTPUT ON

-- ---------------------------------------------------------------------
-- Helper: write one row to AUDIT_LOG (part of the caller's transaction)
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE log_audit (
    p_table   IN VARCHAR2,
    p_action  IN VARCHAR2,
    p_details IN VARCHAR2
) AS
BEGIN
    INSERT INTO audit_log (table_name, action, changed_by, changed_on, details)
    VALUES (p_table, p_action, USER, SYSDATE, SUBSTR(p_details, 1, 400));
END log_audit;
/
SHOW ERRORS

-- =====================================================================
-- PACKAGE 1: blood_mgmt_pkg
-- =====================================================================
CREATE OR REPLACE PACKAGE blood_mgmt_pkg AS
    -- Custom exceptions (callers can catch these by name)
    donor_ineligible   EXCEPTION;
    insufficient_stock EXCEPTION;
    PRAGMA EXCEPTION_INIT (donor_ineligible,   -20001);
    PRAGMA EXCEPTION_INIT (insufficient_stock, -20010);

    -- Returns 1 if the donor's ABO group can be given to the recipient's (Rh ignored).
    -- Used for organs.
    FUNCTION is_abo_compatible (p_donor_group IN VARCHAR2,
                                p_recipient_group IN VARCHAR2) RETURN NUMBER;

    -- Returns 1 if ABO AND Rh are compatible (red cell rules). Used for blood.
    FUNCTION is_compatible (p_donor_group IN VARCHAR2,
                            p_recipient_group IN VARCHAR2) RETURN NUMBER;

    -- Shelf life in days for a blood component
    FUNCTION shelf_life_days (p_component IN VARCHAR2) RETURN NUMBER;

    -- 1 if donor is aged 18-65 and last donated 90+ days ago, else 0
    FUNCTION is_donor_eligible (p_donor_id IN NUMBER) RETURN NUMBER;

    -- Record a donation: creates a blood unit and updates the donor's last donation date
    PROCEDURE register_donation (p_donor_id  IN NUMBER,
                                 p_bank_id   IN NUMBER,
                                 p_component IN VARCHAR2 DEFAULT 'WHOLE_BLOOD');

    -- Issue compatible units to a pending request (all-or-nothing, FIFO by expiry)
    PROCEDURE fulfill_request (p_request_id IN NUMBER);

    -- Mark all lapsed units as EXPIRED (also run nightly by a scheduler job)
    PROCEDURE expire_units;
END blood_mgmt_pkg;
/
SHOW ERRORS

CREATE OR REPLACE PACKAGE BODY blood_mgmt_pkg AS

    c_min_gap_days CONSTANT NUMBER := 90;
    c_min_age      CONSTANT NUMBER := 18;
    c_max_age      CONSTANT NUMBER := 65;

    ------------------------------------------------------------------
    FUNCTION is_abo_compatible (p_donor_group IN VARCHAR2,
                                p_recipient_group IN VARCHAR2) RETURN NUMBER IS
        v_d_abo VARCHAR2(2);
        v_r_abo VARCHAR2(2);
    BEGIN
        -- 'AB+' -> 'AB', 'O-' -> 'O'
        v_d_abo := SUBSTR(p_donor_group,     1, LENGTH(p_donor_group) - 1);
        v_r_abo := SUBSTR(p_recipient_group, 1, LENGTH(p_recipient_group) - 1);

        IF v_d_abo = 'O' OR v_r_abo = 'AB' OR v_d_abo = v_r_abo THEN
            RETURN 1;
        END IF;
        RETURN 0;
    END is_abo_compatible;

    ------------------------------------------------------------------
    FUNCTION is_compatible (p_donor_group IN VARCHAR2,
                            p_recipient_group IN VARCHAR2) RETURN NUMBER IS
    BEGIN
        IF is_abo_compatible(p_donor_group, p_recipient_group) = 1
           AND (SUBSTR(p_donor_group, -1) = '-' OR SUBSTR(p_recipient_group, -1) = '+') THEN
            RETURN 1;
        END IF;
        RETURN 0;
    END is_compatible;

    ------------------------------------------------------------------
    FUNCTION shelf_life_days (p_component IN VARCHAR2) RETURN NUMBER IS
    BEGIN
        RETURN CASE p_component
                   WHEN 'WHOLE_BLOOD' THEN 35
                   WHEN 'RBC'         THEN 42
                   WHEN 'PLASMA'      THEN 365
                   WHEN 'PLATELETS'   THEN 5
                   ELSE 35
               END;
    END shelf_life_days;

    ------------------------------------------------------------------
    FUNCTION is_donor_eligible (p_donor_id IN NUMBER) RETURN NUMBER IS
        v_dob  DATE;
        v_last DATE;
        v_age  NUMBER;
    BEGIN
        SELECT dob, last_donation_date
          INTO v_dob, v_last
          FROM donor
         WHERE donor_id = p_donor_id;

        v_age := TRUNC(MONTHS_BETWEEN(TRUNC(SYSDATE), v_dob) / 12);

        IF v_age < c_min_age OR v_age > c_max_age THEN
            RETURN 0;
        END IF;

        IF v_last IS NOT NULL AND TRUNC(SYSDATE) - v_last < c_min_gap_days THEN
            RETURN 0;
        END IF;

        RETURN 1;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RETURN 0;
    END is_donor_eligible;

    ------------------------------------------------------------------
    PROCEDURE register_donation (p_donor_id  IN NUMBER,
                                 p_bank_id   IN NUMBER,
                                 p_component IN VARCHAR2 DEFAULT 'WHOLE_BLOOD') IS
    BEGIN
        IF is_donor_eligible(p_donor_id) = 0 THEN
            RAISE_APPLICATION_ERROR(-20001,
                'Donor ' || p_donor_id || ' is not eligible (needs age 18-65 and '
                || c_min_gap_days || ' days since last donation)');
        END IF;

        -- blood_group, collected_on and expiry_on are filled by trg_blood_unit_bi
        INSERT INTO blood_unit (bank_id, donor_id, component)
        VALUES (p_bank_id, p_donor_id, p_component);

        UPDATE donor
           SET last_donation_date = TRUNC(SYSDATE)
         WHERE donor_id = p_donor_id;

        COMMIT;
        DBMS_OUTPUT.PUT_LINE('Donation registered for donor ' || p_donor_id
                             || ' at bank ' || p_bank_id);
    END register_donation;

    ------------------------------------------------------------------
    PROCEDURE fulfill_request (p_request_id IN NUMBER) IS
        v_req    blood_request%ROWTYPE;
        v_avail  NUMBER;
        v_issued NUMBER := 0;

        -- Exact blood-group matches first, then earliest expiry (FIFO).
        -- SKIP LOCKED lets two concurrent requests avoid grabbing the same unit.
        CURSOR c_units (cp_group VARCHAR2, cp_comp VARCHAR2) IS
            SELECT unit_id
              FROM blood_unit
             WHERE status    = 'AVAILABLE'
               AND expiry_on >= TRUNC(SYSDATE)
               AND component = cp_comp
               AND is_compatible(blood_group, cp_group) = 1
             ORDER BY CASE WHEN blood_group = cp_group THEN 0 ELSE 1 END, expiry_on
               FOR UPDATE SKIP LOCKED;
    BEGIN
        BEGIN
            SELECT *
              INTO v_req
              FROM blood_request
             WHERE request_id = p_request_id
               FOR UPDATE;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(-20012, 'Request ' || p_request_id || ' does not exist');
        END;

        IF v_req.status <> 'PENDING' THEN
            RAISE_APPLICATION_ERROR(-20011,
                'Request ' || p_request_id || ' is already ' || v_req.status);
        END IF;

        -- All-or-nothing: check stock before touching anything
        SELECT COUNT(*)
          INTO v_avail
          FROM blood_unit
         WHERE status    = 'AVAILABLE'
           AND expiry_on >= TRUNC(SYSDATE)
           AND component = v_req.component
           AND is_compatible(blood_group, v_req.blood_group) = 1;

        IF v_avail < v_req.units_needed THEN
            RAISE_APPLICATION_ERROR(-20010,
                'Insufficient stock for request ' || p_request_id || ': need '
                || v_req.units_needed || ', compatible units available: ' || v_avail);
        END IF;

        FOR u IN c_units(v_req.blood_group, v_req.component) LOOP
            UPDATE blood_unit SET status = 'ISSUED' WHERE unit_id = u.unit_id;

            INSERT INTO blood_issue (request_id, unit_id, issued_on)
            VALUES (p_request_id, u.unit_id, SYSDATE);

            v_issued := v_issued + 1;
            EXIT WHEN v_issued >= v_req.units_needed;
        END LOOP;

        -- Can only happen if another session locked some units meanwhile
        IF v_issued < v_req.units_needed THEN
            RAISE_APPLICATION_ERROR(-20010,
                'Insufficient stock for request ' || p_request_id
                || ' (some units are being processed by another request)');
        END IF;

        UPDATE blood_request SET status = 'FULFILLED' WHERE request_id = p_request_id;

        COMMIT;
        DBMS_OUTPUT.PUT_LINE('Request ' || p_request_id || ' fulfilled with '
                             || v_issued || ' unit(s)');
    END fulfill_request;

    ------------------------------------------------------------------
    PROCEDURE expire_units IS
        v_count NUMBER := 0;

        CURSOR c_lapsed IS
            SELECT unit_id
              FROM blood_unit
             WHERE status IN ('AVAILABLE', 'RESERVED')
               AND expiry_on < TRUNC(SYSDATE)
               FOR UPDATE;
    BEGIN
        FOR r IN c_lapsed LOOP
            UPDATE blood_unit
               SET status = 'EXPIRED'
             WHERE CURRENT OF c_lapsed;
            v_count := v_count + 1;
        END LOOP;

        COMMIT;
        DBMS_OUTPUT.PUT_LINE('expire_units: ' || v_count || ' unit(s) marked EXPIRED');
    END expire_units;

END blood_mgmt_pkg;
/
SHOW ERRORS

-- =====================================================================
-- PACKAGE 2: organ_mgmt_pkg
-- =====================================================================
CREATE OR REPLACE PACKAGE organ_mgmt_pkg AS
    no_match_found EXCEPTION;
    PRAGMA EXCEPTION_INIT (no_match_found, -20020);

    -- Ranks compatible waitlist patients for an organ and allocates it to the best one.
    -- Score = urgency * 10 + months waited + 5 bonus for an identical blood group.
    PROCEDURE find_organ_match (p_organ_donor_id IN NUMBER);

    -- Close a pending match: p_outcome is SUCCESS, FAILED or CANCELLED
    PROCEDURE complete_transplant (p_match_id     IN NUMBER,
                                   p_outcome      IN VARCHAR2,
                                   p_surgery_date IN DATE DEFAULT SYSDATE);
END organ_mgmt_pkg;
/
SHOW ERRORS

CREATE OR REPLACE PACKAGE BODY organ_mgmt_pkg AS

    ------------------------------------------------------------------
    PROCEDURE find_organ_match (p_organ_donor_id IN NUMBER) IS
        v_organ_type organ_donor.organ_type%TYPE;
        v_status     organ_donor.status%TYPE;
        v_group      donor.blood_group%TYPE;
        v_rank       NUMBER := 0;
        v_best       organ_waitlist.waitlist_id%TYPE;

        CURSOR c_cand (cp_type VARCHAR2, cp_group VARCHAR2) IS
            SELECT w.waitlist_id,
                   p.name AS patient_name,
                   p.blood_group,
                   w.medical_urgency,
                   TRUNC(SYSDATE - w.registered_on) AS days_waiting,
                   w.medical_urgency * 10
                     + TRUNC((SYSDATE - w.registered_on) / 30)
                     + CASE WHEN p.blood_group = cp_group THEN 5 ELSE 0 END AS score
              FROM organ_waitlist w
              JOIN patient p ON p.patient_id = w.patient_id
             WHERE w.status     = 'WAITING'
               AND w.organ_type = cp_type
               AND blood_mgmt_pkg.is_abo_compatible(cp_group, p.blood_group) = 1
             ORDER BY score DESC, w.registered_on ASC;
    BEGIN
        BEGIN
            SELECT od.organ_type, od.status, d.blood_group
              INTO v_organ_type, v_status, v_group
              FROM organ_donor od
              JOIN donor d ON d.donor_id = od.donor_id
             WHERE od.organ_donor_id = p_organ_donor_id;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(-20021,
                    'Organ donor ' || p_organ_donor_id || ' does not exist');
        END;

        IF v_status <> 'AVAILABLE' THEN
            RAISE_APPLICATION_ERROR(-20022,
                'Organ donor ' || p_organ_donor_id || ' is ' || v_status || ', not AVAILABLE');
        END IF;

        DBMS_OUTPUT.PUT_LINE('Candidates for ' || v_organ_type
                             || ' (donor blood group ' || v_group || '):');

        FOR c IN c_cand(v_organ_type, v_group) LOOP
            v_rank := v_rank + 1;
            IF v_rank = 1 THEN
                v_best := c.waitlist_id;
            END IF;
            IF v_rank <= 3 THEN
                DBMS_OUTPUT.PUT_LINE('  #' || v_rank || ' ' || c.patient_name
                    || ' (' || c.blood_group || ', urgency ' || c.medical_urgency
                    || ', waiting ' || c.days_waiting || ' days, score ' || c.score || ')');
            END IF;
        END LOOP;

        IF v_best IS NULL THEN
            RAISE_APPLICATION_ERROR(-20020,
                'No compatible ' || v_organ_type || ' recipient on the waitlist');
        END IF;

        -- The status check guards against two sessions allocating the same organ
        UPDATE organ_donor
           SET status = 'ALLOCATED'
         WHERE organ_donor_id = p_organ_donor_id
           AND status = 'AVAILABLE';

        IF SQL%ROWCOUNT = 0 THEN
            RAISE_APPLICATION_ERROR(-20022,
                'Organ donor ' || p_organ_donor_id || ' was allocated by another session');
        END IF;

        UPDATE organ_waitlist SET status = 'MATCHED' WHERE waitlist_id = v_best;

        INSERT INTO organ_match (organ_donor_id, waitlist_id, matched_on, outcome)
        VALUES (p_organ_donor_id, v_best, SYSDATE, 'PENDING');

        COMMIT;
        DBMS_OUTPUT.PUT_LINE('Matched organ donor ' || p_organ_donor_id
                             || ' to waitlist entry ' || v_best);
    END find_organ_match;

    ------------------------------------------------------------------
    PROCEDURE complete_transplant (p_match_id     IN NUMBER,
                                   p_outcome      IN VARCHAR2,
                                   p_surgery_date IN DATE DEFAULT SYSDATE) IS
        v_od NUMBER;
        v_wl NUMBER;
    BEGIN
        IF p_outcome NOT IN ('SUCCESS', 'FAILED', 'CANCELLED') THEN
            RAISE_APPLICATION_ERROR(-20023,
                'Outcome must be SUCCESS, FAILED or CANCELLED');
        END IF;

        BEGIN
            SELECT organ_donor_id, waitlist_id
              INTO v_od, v_wl
              FROM organ_match
             WHERE match_id = p_match_id
               AND outcome  = 'PENDING'
               FOR UPDATE;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(-20024,
                    'Match ' || p_match_id || ' not found or not PENDING');
        END;

        UPDATE organ_match
           SET outcome      = p_outcome,
               surgery_date = CASE WHEN p_outcome = 'CANCELLED' THEN NULL ELSE p_surgery_date END
         WHERE match_id = p_match_id;

        IF p_outcome = 'SUCCESS' THEN
            UPDATE organ_donor    SET status = 'TRANSPLANTED' WHERE organ_donor_id = v_od;
            UPDATE organ_waitlist SET status = 'TRANSPLANTED' WHERE waitlist_id    = v_wl;
        ELSIF p_outcome = 'FAILED' THEN
            -- organ was used, patient goes back on the list
            UPDATE organ_donor    SET status = 'TRANSPLANTED' WHERE organ_donor_id = v_od;
            UPDATE organ_waitlist SET status = 'WAITING'      WHERE waitlist_id    = v_wl;
        ELSE
            -- cancelled before surgery: organ and patient both become available again
            UPDATE organ_donor    SET status = 'AVAILABLE'    WHERE organ_donor_id = v_od;
            UPDATE organ_waitlist SET status = 'WAITING'      WHERE waitlist_id    = v_wl;
        END IF;

        COMMIT;
        DBMS_OUTPUT.PUT_LINE('Match ' || p_match_id || ' closed as ' || p_outcome);
    END complete_transplant;

END organ_mgmt_pkg;
/
SHOW ERRORS

-- =====================================================================
-- TRIGGERS
-- =====================================================================

-- Fills in blood group, collection date and expiry date, and enforces donor eligibility.
-- This is the safety net: even a direct INSERT cannot bypass the rules.
CREATE OR REPLACE TRIGGER trg_blood_unit_bi
BEFORE INSERT ON blood_unit
FOR EACH ROW
DECLARE
    v_group donor.blood_group%TYPE;
BEGIN
    SELECT blood_group INTO v_group FROM donor WHERE donor_id = :NEW.donor_id;

    IF :NEW.blood_group IS NULL THEN
        :NEW.blood_group := v_group;
    ELSIF :NEW.blood_group <> v_group THEN
        RAISE_APPLICATION_ERROR(-20003, 'Unit blood group does not match the donor''s blood group');
    END IF;

    IF blood_mgmt_pkg.is_donor_eligible(:NEW.donor_id) = 0 THEN
        RAISE_APPLICATION_ERROR(-20001,
            'Donor ' || :NEW.donor_id || ' is not eligible to donate (age 18-65, 90 days since last donation)');
    END IF;

    IF :NEW.expiry_on IS NULL THEN
        :NEW.expiry_on := :NEW.collected_on + blood_mgmt_pkg.shelf_life_days(:NEW.component);
    END IF;
END trg_blood_unit_bi;
/
SHOW ERRORS

-- Audit trail triggers: log every status change
CREATE OR REPLACE TRIGGER trg_blood_unit_audit
AFTER UPDATE OF status ON blood_unit
FOR EACH ROW
WHEN (OLD.status <> NEW.status)
BEGIN
    log_audit('BLOOD_UNIT', 'UPDATE',
              'Unit ' || :OLD.unit_id || ': ' || :OLD.status || ' -> ' || :NEW.status);
END trg_blood_unit_audit;
/
SHOW ERRORS

CREATE OR REPLACE TRIGGER trg_blood_request_audit
AFTER UPDATE OF status ON blood_request
FOR EACH ROW
WHEN (OLD.status <> NEW.status)
BEGIN
    log_audit('BLOOD_REQUEST', 'UPDATE',
              'Request ' || :OLD.request_id || ': ' || :OLD.status || ' -> ' || :NEW.status);
END trg_blood_request_audit;
/
SHOW ERRORS

CREATE OR REPLACE TRIGGER trg_waitlist_audit
AFTER UPDATE OF status ON organ_waitlist
FOR EACH ROW
WHEN (OLD.status <> NEW.status)
BEGIN
    log_audit('ORGAN_WAITLIST', 'UPDATE',
              'Waitlist ' || :OLD.waitlist_id || ': ' || :OLD.status || ' -> ' || :NEW.status);
END trg_waitlist_audit;
/
SHOW ERRORS

CREATE OR REPLACE TRIGGER trg_organ_match_audit
AFTER INSERT OR UPDATE OF outcome ON organ_match
FOR EACH ROW
BEGIN
    IF INSERTING THEN
        log_audit('ORGAN_MATCH', 'INSERT',
                  'Match ' || :NEW.match_id || ': organ donor ' || :NEW.organ_donor_id
                  || ' -> waitlist ' || :NEW.waitlist_id);
    ELSIF :OLD.outcome <> :NEW.outcome THEN
        log_audit('ORGAN_MATCH', 'UPDATE',
                  'Match ' || :OLD.match_id || ': ' || :OLD.outcome || ' -> ' || :NEW.outcome);
    END IF;
END trg_organ_match_audit;
/
SHOW ERRORS

-- =====================================================================
-- SCHEDULED JOB: mark lapsed blood units as EXPIRED every night at 00:05
-- (needs the CREATE JOB privilege: GRANT CREATE JOB TO <your_user>;)
-- =====================================================================
BEGIN
    BEGIN
        DBMS_SCHEDULER.DROP_JOB('JOB_EXPIRE_BLOOD_UNITS', TRUE);
    EXCEPTION
        WHEN OTHERS THEN NULL;   -- job did not exist yet
    END;

    DBMS_SCHEDULER.CREATE_JOB(
        job_name        => 'JOB_EXPIRE_BLOOD_UNITS',
        job_type        => 'PLSQL_BLOCK',
        job_action      => 'BEGIN blood_mgmt_pkg.expire_units; END;',
        start_date      => SYSTIMESTAMP,
        repeat_interval => 'FREQ=DAILY; BYHOUR=0; BYMINUTE=5',
        enabled         => TRUE,
        comments        => 'Nightly expiry check for blood units');
END;
/
