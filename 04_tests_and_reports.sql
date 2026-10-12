-- =====================================================================
-- BloodNet: Blood Bank & Organ Donation Network
-- File 4 of 4: test scenarios and report queries
--
-- Run AFTER 03_sample_data.sql, top to bottom, with "Run Script" (F5).
-- Screenshot each section's output for your report.
-- To run again from scratch, re-run files 01 -> 03 first.
-- =====================================================================

SET SERVEROUTPUT ON
SET DEFINE OFF
SET LINESIZE 200
SET PAGESIZE 100

PROMPT ============================================================
PROMPT TEST 1: blood compatibility function
PROMPT Expected: 1, 0, 0, 1
PROMPT ============================================================
SELECT blood_mgmt_pkg.is_compatible('O-',  'AB+') AS o_neg_to_ab_pos,
       blood_mgmt_pkg.is_compatible('A+',  'O+')  AS a_pos_to_o_pos,
       blood_mgmt_pkg.is_compatible('AB+', 'AB-') AS ab_pos_to_ab_neg,
       blood_mgmt_pkg.is_compatible('B-',  'B+')  AS b_neg_to_b_pos
  FROM dual;

PROMPT ============================================================
PROMPT TEST 2: valid donation (donor 10 last gave blood 100 days ago)
PROMPT Expected: new unit with blood group B+, expiry = collected + 35 days
PROMPT ============================================================
BEGIN
    blood_mgmt_pkg.register_donation(10, 1);
END;
/
SELECT unit_id, donor_id, blood_group, component, collected_on, expiry_on, status
  FROM blood_unit
 WHERE donor_id = 10;

PROMPT ============================================================
PROMPT TEST 3: ineligible donors are rejected
PROMPT   3a: donor 4  (donated 30 days ago)  -> procedure check
PROMPT   3b: donor 15 (age 16)               -> procedure check
PROMPT   3c: donor 5  (donated 2 days ago)   -> direct INSERT stopped by the trigger
PROMPT ============================================================
BEGIN
    blood_mgmt_pkg.register_donation(4, 1);
EXCEPTION
    WHEN blood_mgmt_pkg.donor_ineligible THEN
        DBMS_OUTPUT.PUT_LINE('3a rejected: ' || SQLERRM);
END;
/
BEGIN
    blood_mgmt_pkg.register_donation(15, 1);
EXCEPTION
    WHEN blood_mgmt_pkg.donor_ineligible THEN
        DBMS_OUTPUT.PUT_LINE('3b rejected: ' || SQLERRM);
END;
/
BEGIN
    INSERT INTO blood_unit (bank_id, donor_id, component) VALUES (2, 5, 'WHOLE_BLOOD');
EXCEPTION
    WHEN blood_mgmt_pkg.donor_ineligible THEN
        DBMS_OUTPUT.PUT_LINE('3c trigger blocked insert: ' || SQLERRM);
END;
/

PROMPT ============================================================
PROMPT TEST 4: fulfil request 1 (B+ x2, whole blood)
PROMPT Expected: exact B+ units issued first, earliest expiry first
PROMPT ============================================================
BEGIN
    blood_mgmt_pkg.fulfill_request(1);
END;
/
SELECT i.issue_id, i.request_id, u.unit_id, u.blood_group, u.expiry_on, u.status
  FROM blood_issue i
  JOIN blood_unit u ON u.unit_id = i.unit_id
 WHERE i.request_id = 1;

SELECT request_id, status FROM blood_request WHERE request_id = 1;

PROMPT ============================================================
PROMPT TEST 5: insufficient stock (request 2 needs 5 AB- units, only 3 Rh-negative exist)
PROMPT Expected: error caught, request stays PENDING, no units issued
PROMPT ============================================================
BEGIN
    blood_mgmt_pkg.fulfill_request(2);
EXCEPTION
    WHEN blood_mgmt_pkg.insufficient_stock THEN
        DBMS_OUTPUT.PUT_LINE('5 rejected: ' || SQLERRM);
END;
/
SELECT request_id, status FROM blood_request WHERE request_id = 2;

PROMPT ============================================================
PROMPT TEST 6: fulfilling an already fulfilled request (request 4)
PROMPT Expected: ORA-20011
PROMPT ============================================================
BEGIN
    blood_mgmt_pkg.fulfill_request(4);
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('6 rejected: ' || SQLERRM);
END;
/

PROMPT ============================================================
PROMPT TEST 7: expiry job logic (units 8 and 14 are past expiry)
PROMPT Expected: 2 units marked EXPIRED
PROMPT ============================================================
BEGIN
    blood_mgmt_pkg.expire_units;
END;
/
SELECT unit_id, blood_group, component, expiry_on, status
  FROM blood_unit
 WHERE unit_id IN (8, 14);

PROMPT ============================================================
PROMPT TEST 8: organ matching, kidney from organ donor 1
PROMPT Expected: Deepa Nambiar (score 94) ranks first and is matched
PROMPT ============================================================
BEGIN
    organ_mgmt_pkg.find_organ_match(1);
END;
/
SELECT m.match_id, od.organ_type, p.name AS recipient, m.outcome
  FROM organ_match m
  JOIN organ_donor    od ON od.organ_donor_id = m.organ_donor_id
  JOIN organ_waitlist w  ON w.waitlist_id     = m.waitlist_id
  JOIN patient        p  ON p.patient_id      = w.patient_id;

PROMPT ============================================================
PROMPT TEST 9: no compatible recipient (AB+ heart donor, only an O- patient waiting)
PROMPT Expected: no_match_found error
PROMPT ============================================================
BEGIN
    organ_mgmt_pkg.find_organ_match(3);
EXCEPTION
    WHEN organ_mgmt_pkg.no_match_found THEN
        DBMS_OUTPUT.PUT_LINE('9 rejected: ' || SQLERRM);
END;
/

PROMPT ============================================================
PROMPT TEST 10: complete the transplant for the first match
PROMPT Expected: match SUCCESS, organ donor and waitlist entry TRANSPLANTED
PROMPT ============================================================
DECLARE
    v_match NUMBER;
BEGIN
    SELECT MIN(match_id) INTO v_match FROM organ_match WHERE outcome = 'PENDING';
    organ_mgmt_pkg.complete_transplant(v_match, 'SUCCESS');
END;
/
SELECT od.organ_donor_id, od.status AS organ_status, w.waitlist_id, w.status AS waitlist_status
  FROM organ_match m
  JOIN organ_donor    od ON od.organ_donor_id = m.organ_donor_id
  JOIN organ_waitlist w  ON w.waitlist_id     = m.waitlist_id;

PROMPT ============================================================
PROMPT TEST 11: audit trail written by the triggers
PROMPT ============================================================
SELECT log_id, table_name, action, changed_by, TO_CHAR(changed_on, 'DD-MON HH24:MI') AS changed_on, details
  FROM audit_log
 ORDER BY log_id;

PROMPT ============================================================
PROMPT REPORT 1: current blood stock (view)
PROMPT ============================================================
SELECT bank_name, blood_group, component, units_available
  FROM v_blood_stock
 ORDER BY bank_name, blood_group, component;

PROMPT ============================================================
PROMPT REPORT 2: shortage alert - bank / blood group combinations with zero usable stock
PROMPT ============================================================
WITH bg_list AS (
    SELECT column_value AS bg
      FROM TABLE(sys.odcivarchar2list('A+','A-','B+','B-','AB+','AB-','O+','O-'))
)
SELECT b.name AS bank, g.bg AS blood_group, COUNT(u.unit_id) AS units
  FROM blood_bank b
 CROSS JOIN bg_list g
  LEFT JOIN blood_unit u
         ON u.bank_id     = b.bank_id
        AND u.blood_group = g.bg
        AND u.status      = 'AVAILABLE'
        AND u.expiry_on  >= TRUNC(SYSDATE)
 GROUP BY b.name, g.bg
HAVING COUNT(u.unit_id) = 0
 ORDER BY b.name, g.bg;

PROMPT ============================================================
PROMPT REPORT 3: pending HIGH / CRITICAL blood requests (view)
PROMPT ============================================================
SELECT * FROM v_pending_critical_requests;

PROMPT ============================================================
PROMPT REPORT 4: donors eligible to donate again (view)
PROMPT ============================================================
SELECT * FROM v_eligible_donors ORDER BY blood_group, name;

PROMPT ============================================================
PROMPT REPORT 5: hospital-wise blood request fulfilment rate
PROMPT ============================================================
SELECT h.name AS hospital,
       COUNT(*) AS total_requests,
       SUM(CASE WHEN r.status = 'FULFILLED' THEN 1 ELSE 0 END) AS fulfilled,
       ROUND(100 * SUM(CASE WHEN r.status = 'FULFILLED' THEN 1 ELSE 0 END) / COUNT(*), 1) AS fulfilment_pct
  FROM hospital h
  JOIN blood_request r ON r.hospital_id = h.hospital_id
 GROUP BY h.hospital_id, h.name
 ORDER BY fulfilment_pct DESC, h.name;

PROMPT ============================================================
PROMPT REPORT 6: organ waitlist queue per organ type (RANK window function, view)
PROMPT ============================================================
SELECT organ_type, queue_position, patient_name, blood_group, medical_urgency,
       TRUNC(SYSDATE - registered_on) AS days_waiting
  FROM v_organ_waitlist_ranking
 ORDER BY organ_type, queue_position;

PROMPT ============================================================
PROMPT REPORT 7: average waiting time per organ type (still waiting)
PROMPT ============================================================
SELECT organ_type,
       COUNT(*) AS patients_waiting,
       ROUND(AVG(SYSDATE - registered_on)) AS avg_days_waiting
  FROM organ_waitlist
 WHERE status = 'WAITING'
 GROUP BY organ_type
 ORDER BY avg_days_waiting DESC;
