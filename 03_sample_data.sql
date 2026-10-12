-- =====================================================================
-- BloodNet: Blood Bank & Organ Donation Network
-- File 3 of 4: sample data
--
-- Run AFTER 02_plsql.sql. All dates are relative to today (SYSDATE),
-- so the data stays "fresh" whenever you load it.
-- The unit-insert trigger is disabled during loading because historical
-- units would otherwise violate the donor-gap rule; it is re-enabled at the end.
-- =====================================================================

SET DEFINE OFF

ALTER TRIGGER trg_blood_unit_bi DISABLE;

-- ---------------------------------------------------------------------
-- Hospitals
-- ---------------------------------------------------------------------
INSERT INTO hospital (hospital_id, name, city, license_no, hospital_type) VALUES (1, 'City General Hospital',     'Pune',      'LIC-PN-0001', 'GOVT');
INSERT INTO hospital (hospital_id, name, city, license_no, hospital_type) VALUES (2, 'Lifeline Medical Centre',   'Mumbai',    'LIC-MB-0002', 'PRIVATE');
INSERT INTO hospital (hospital_id, name, city, license_no, hospital_type) VALUES (3, 'Eastern Trust Hospital',    'Kolkata',   'LIC-KL-0003', 'TRUST');
INSERT INTO hospital (hospital_id, name, city, license_no, hospital_type) VALUES (4, 'Capital Heart Institute',   'Delhi',     'LIC-DL-0004', 'PRIVATE');
INSERT INTO hospital (hospital_id, name, city, license_no, hospital_type) VALUES (5, 'Garden City Hospital',      'Bengaluru', 'LIC-BG-0005', 'GOVT');

-- ---------------------------------------------------------------------
-- Blood banks
-- ---------------------------------------------------------------------
INSERT INTO blood_bank (bank_id, name, city, hospital_id) VALUES (1, 'Pune Central Blood Bank',      'Pune',    1);
INSERT INTO blood_bank (bank_id, name, city, hospital_id) VALUES (2, 'Mumbai Community Blood Bank',  'Mumbai',  NULL);
INSERT INTO blood_bank (bank_id, name, city, hospital_id) VALUES (3, 'Kolkata Life Blood Centre',    'Kolkata', 3);
INSERT INTO blood_bank (bank_id, name, city, hospital_id) VALUES (4, 'Delhi Capital Blood Bank',     'Delhi',   4);

-- ---------------------------------------------------------------------
-- Donors (last_donation_date matches the most recent unit in stock)
--   Eligible now      : 10, 11, 17, 18
--   Too recent        : most others (try 4, 5, 7)
--   Under 18 (ID 15)  : ineligible by age
-- ---------------------------------------------------------------------
INSERT INTO donor (donor_id, name, dob, gender, blood_group, phone, city, last_donation_date) VALUES ( 1, 'Aarav Sharma',    DATE '1996-04-12', 'M', 'O+',  '9000000001', 'Pune',      TRUNC(SYSDATE) - 5);
INSERT INTO donor (donor_id, name, dob, gender, blood_group, phone, city, last_donation_date) VALUES ( 2, 'Priya Nair',      DATE '1999-09-03', 'F', 'A+',  '9000000002', 'Mumbai',    TRUNC(SYSDATE) - 8);
INSERT INTO donor (donor_id, name, dob, gender, blood_group, phone, city, last_donation_date) VALUES ( 3, 'Rohan Das',       DATE '1994-01-21', 'M', 'B+',  '9000000003', 'Kolkata',   TRUNC(SYSDATE) - 9);
INSERT INTO donor (donor_id, name, dob, gender, blood_group, phone, city, last_donation_date) VALUES ( 4, 'Sneha Kulkarni',  DATE '2001-06-30', 'F', 'AB+', '9000000004', 'Pune',      TRUNC(SYSDATE) - 30);
INSERT INTO donor (donor_id, name, dob, gender, blood_group, phone, city, last_donation_date) VALUES ( 5, 'Imran Sheikh',    DATE '1990-11-11', 'M', 'O-',  '9000000005', 'Mumbai',    TRUNC(SYSDATE) - 2);
INSERT INTO donor (donor_id, name, dob, gender, blood_group, phone, city, last_donation_date) VALUES ( 6, 'Ananya Roy',      DATE '1997-02-17', 'F', 'A-',  '9000000006', 'Kolkata',   TRUNC(SYSDATE) - 18);
INSERT INTO donor (donor_id, name, dob, gender, blood_group, phone, city, last_donation_date) VALUES ( 7, 'Vikram Singh',    DATE '1988-07-25', 'M', 'B-',  '9000000007', 'Mumbai',    TRUNC(SYSDATE) - 15);
INSERT INTO donor (donor_id, name, dob, gender, blood_group, phone, city, last_donation_date) VALUES ( 8, 'Meera Iyer',      DATE '1995-12-05', 'F', 'AB-', '9000000008', 'Delhi',     TRUNC(SYSDATE) - 14);
INSERT INTO donor (donor_id, name, dob, gender, blood_group, phone, city, last_donation_date) VALUES ( 9, 'Karan Mehta',     DATE '1992-03-09', 'M', 'O+',  '9000000009', 'Pune',      TRUNC(SYSDATE) - 12);
INSERT INTO donor (donor_id, name, dob, gender, blood_group, phone, city, last_donation_date) VALUES (10, 'Divya Patil',     DATE '2000-08-19', 'F', 'B+',  '9000000010', 'Pune',      TRUNC(SYSDATE) - 100);
INSERT INTO donor (donor_id, name, dob, gender, blood_group, phone, city, last_donation_date) VALUES (11, 'Arjun Reddy',     DATE '1993-05-28', 'M', 'A+',  '9000000011', 'Bengaluru', TRUNC(SYSDATE) - 130);
INSERT INTO donor (donor_id, name, dob, gender, blood_group, phone, city, last_donation_date) VALUES (12, 'Sana Khan',       DATE '1998-10-14', 'F', 'O+',  '9000000012', 'Mumbai',    TRUNC(SYSDATE) - 20);
INSERT INTO donor (donor_id, name, dob, gender, blood_group, phone, city, last_donation_date) VALUES (13, 'Rahul Ghosh',     DATE '1985-01-02', 'M', 'A+',  '9000000013', 'Kolkata',   TRUNC(SYSDATE) - 36);
INSERT INTO donor (donor_id, name, dob, gender, blood_group, phone, city, last_donation_date) VALUES (14, 'Neha Verma',      DATE '1996-09-22', 'F', 'B+',  '9000000014', 'Delhi',     TRUNC(SYSDATE) - 28);
INSERT INTO donor (donor_id, name, dob, gender, blood_group, phone, city, last_donation_date) VALUES (15, 'Tanmay Kale',     ADD_MONTHS(TRUNC(SYSDATE), -12 * 16), 'M', 'O+', '9000000015', 'Pune', NULL);
INSERT INTO donor (donor_id, name, dob, gender, blood_group, phone, city, last_donation_date) VALUES (16, 'Ishita Bose',     DATE '1994-04-04', 'F', 'O-',  '9000000016', 'Kolkata',   TRUNC(SYSDATE) - 20);
INSERT INTO donor (donor_id, name, dob, gender, blood_group, phone, city, last_donation_date) VALUES (17, 'Manoj Pillai',    DATE '1991-06-16', 'M', 'A+',  '9000000017', 'Bengaluru', TRUNC(SYSDATE) - 110);
INSERT INTO donor (donor_id, name, dob, gender, blood_group, phone, city, last_donation_date) VALUES (18, 'Farah Ali',       DATE '1999-01-27', 'F', 'B+',  '9000000018', 'Mumbai',    TRUNC(SYSDATE) - 250);
INSERT INTO donor (donor_id, name, dob, gender, blood_group, phone, city, last_donation_date) VALUES (19, 'Sandeep Rao',     DATE '1987-12-12', 'M', 'AB+', '9000000019', 'Delhi',     TRUNC(SYSDATE) - 11);
INSERT INTO donor (donor_id, name, dob, gender, blood_group, phone, city, last_donation_date) VALUES (20, 'Pooja Desai',     DATE '2002-03-23', 'F', 'A-',  '9000000020', 'Pune',      TRUNC(SYSDATE) - 45);

-- ---------------------------------------------------------------------
-- Patients
-- ---------------------------------------------------------------------
INSERT INTO patient (patient_id, name, dob, blood_group, hospital_id, urgency) VALUES ( 1, 'Rajesh Kumar',    DATE '1975-03-14', 'B+',  1, 'HIGH');
INSERT INTO patient (patient_id, name, dob, blood_group, hospital_id, urgency) VALUES ( 2, 'Lakshmi Menon',   DATE '1982-07-08', 'AB-', 2, 'CRITICAL');
INSERT INTO patient (patient_id, name, dob, blood_group, hospital_id, urgency) VALUES ( 3, 'Suresh Banerjee', DATE '1968-11-30', 'O-',  3, 'MEDIUM');
INSERT INTO patient (patient_id, name, dob, blood_group, hospital_id, urgency) VALUES ( 4, 'Anita Chawla',    DATE '1990-05-19', 'A+',  4, 'CRITICAL');
INSERT INTO patient (patient_id, name, dob, blood_group, hospital_id, urgency) VALUES ( 5, 'Mohan Gupta',     DATE '1959-09-02', 'O+',  5, 'LOW');
INSERT INTO patient (patient_id, name, dob, blood_group, hospital_id, urgency) VALUES ( 6, 'Farhan Qureshi',  DATE '1985-02-11', 'B+',  2, 'HIGH');
INSERT INTO patient (patient_id, name, dob, blood_group, hospital_id, urgency) VALUES ( 7, 'Deepa Nambiar',   DATE '1979-12-25', 'A+',  1, 'CRITICAL');
INSERT INTO patient (patient_id, name, dob, blood_group, hospital_id, urgency) VALUES ( 8, 'Gautam Sen',      DATE '1972-06-06', 'O+',  3, 'HIGH');
INSERT INTO patient (patient_id, name, dob, blood_group, hospital_id, urgency) VALUES ( 9, 'Kavita Rao',      DATE '1993-10-17', 'AB+', 4, 'MEDIUM');
INSERT INTO patient (patient_id, name, dob, blood_group, hospital_id, urgency) VALUES (10, 'Harish Patel',    DATE '1965-04-01', 'O-',  5, 'HIGH');

-- ---------------------------------------------------------------------
-- Blood units
--   u8 and u14 are AVAILABLE but already past expiry (expire_units will catch them)
--   u15 is ISSUED, u16 is EXPIRED history
-- ---------------------------------------------------------------------
INSERT INTO blood_unit (unit_id, bank_id, donor_id, blood_group, component, collected_on, expiry_on, status) VALUES ( 1, 1,  1, 'O+',  'WHOLE_BLOOD', TRUNC(SYSDATE) - 5,   TRUNC(SYSDATE) - 5   + 35,  'AVAILABLE');
INSERT INTO blood_unit (unit_id, bank_id, donor_id, blood_group, component, collected_on, expiry_on, status) VALUES ( 2, 1,  9, 'O+',  'RBC',         TRUNC(SYSDATE) - 12,  TRUNC(SYSDATE) - 12  + 42,  'AVAILABLE');
INSERT INTO blood_unit (unit_id, bank_id, donor_id, blood_group, component, collected_on, expiry_on, status) VALUES ( 3, 1,  4, 'AB+', 'WHOLE_BLOOD', TRUNC(SYSDATE) - 30,  TRUNC(SYSDATE) - 30  + 35,  'AVAILABLE');
INSERT INTO blood_unit (unit_id, bank_id, donor_id, blood_group, component, collected_on, expiry_on, status) VALUES ( 4, 1,  2, 'A+',  'WHOLE_BLOOD', TRUNC(SYSDATE) - 8,   TRUNC(SYSDATE) - 8   + 35,  'AVAILABLE');
INSERT INTO blood_unit (unit_id, bank_id, donor_id, blood_group, component, collected_on, expiry_on, status) VALUES ( 5, 2, 12, 'O+',  'WHOLE_BLOOD', TRUNC(SYSDATE) - 20,  TRUNC(SYSDATE) - 20  + 35,  'AVAILABLE');
INSERT INTO blood_unit (unit_id, bank_id, donor_id, blood_group, component, collected_on, expiry_on, status) VALUES ( 6, 2,  7, 'B-',  'WHOLE_BLOOD', TRUNC(SYSDATE) - 15,  TRUNC(SYSDATE) - 15  + 35,  'AVAILABLE');
INSERT INTO blood_unit (unit_id, bank_id, donor_id, blood_group, component, collected_on, expiry_on, status) VALUES ( 7, 2,  5, 'O-',  'PLATELETS',   TRUNC(SYSDATE) - 2,   TRUNC(SYSDATE) - 2   + 5,   'AVAILABLE');
INSERT INTO blood_unit (unit_id, bank_id, donor_id, blood_group, component, collected_on, expiry_on, status) VALUES ( 8, 3, 13, 'A+',  'WHOLE_BLOOD', TRUNC(SYSDATE) - 36,  TRUNC(SYSDATE) - 36  + 35,  'AVAILABLE');
INSERT INTO blood_unit (unit_id, bank_id, donor_id, blood_group, component, collected_on, expiry_on, status) VALUES ( 9, 3,  6, 'A-',  'WHOLE_BLOOD', TRUNC(SYSDATE) - 18,  TRUNC(SYSDATE) - 18  + 35,  'AVAILABLE');
INSERT INTO blood_unit (unit_id, bank_id, donor_id, blood_group, component, collected_on, expiry_on, status) VALUES (10, 3,  3, 'B+',  'WHOLE_BLOOD', TRUNC(SYSDATE) - 9,   TRUNC(SYSDATE) - 9   + 35,  'AVAILABLE');
INSERT INTO blood_unit (unit_id, bank_id, donor_id, blood_group, component, collected_on, expiry_on, status) VALUES (11, 4, 19, 'AB+', 'WHOLE_BLOOD', TRUNC(SYSDATE) - 11,  TRUNC(SYSDATE) - 11  + 35,  'AVAILABLE');
INSERT INTO blood_unit (unit_id, bank_id, donor_id, blood_group, component, collected_on, expiry_on, status) VALUES (12, 4, 14, 'B+',  'WHOLE_BLOOD', TRUNC(SYSDATE) - 28,  TRUNC(SYSDATE) - 28  + 35,  'AVAILABLE');
INSERT INTO blood_unit (unit_id, bank_id, donor_id, blood_group, component, collected_on, expiry_on, status) VALUES (13, 4,  8, 'AB-', 'WHOLE_BLOOD', TRUNC(SYSDATE) - 14,  TRUNC(SYSDATE) - 14  + 35,  'AVAILABLE');
INSERT INTO blood_unit (unit_id, bank_id, donor_id, blood_group, component, collected_on, expiry_on, status) VALUES (14, 1, 20, 'A-',  'RBC',         TRUNC(SYSDATE) - 45,  TRUNC(SYSDATE) - 45  + 42,  'AVAILABLE');
INSERT INTO blood_unit (unit_id, bank_id, donor_id, blood_group, component, collected_on, expiry_on, status) VALUES (15, 4, 16, 'O-',  'WHOLE_BLOOD', TRUNC(SYSDATE) - 20,  TRUNC(SYSDATE) - 20  + 35,  'ISSUED');
INSERT INTO blood_unit (unit_id, bank_id, donor_id, blood_group, component, collected_on, expiry_on, status) VALUES (16, 3,  3, 'B+',  'WHOLE_BLOOD', TRUNC(SYSDATE) - 100, TRUNC(SYSDATE) - 100 + 35,  'EXPIRED');

-- ---------------------------------------------------------------------
-- Blood requests (1, 2, 3, 5 are PENDING; 4 is already fulfilled)
--   Request 1: B+ x2   -> fulfilled in the tests
--   Request 2: AB- x5  -> only 3 Rh-negative units exist -> insufficient stock
-- ---------------------------------------------------------------------
INSERT INTO blood_request (request_id, hospital_id, patient_id, blood_group, component, units_needed, status, requested_on) VALUES (1, 1, 1, 'B+',  'WHOLE_BLOOD', 2, 'PENDING',   SYSDATE - 1);
INSERT INTO blood_request (request_id, hospital_id, patient_id, blood_group, component, units_needed, status, requested_on) VALUES (2, 2, 2, 'AB-', 'WHOLE_BLOOD', 5, 'PENDING',   SYSDATE - 1);
INSERT INTO blood_request (request_id, hospital_id, patient_id, blood_group, component, units_needed, status, requested_on) VALUES (3, 4, 4, 'A+',  'WHOLE_BLOOD', 1, 'PENDING',   SYSDATE);
INSERT INTO blood_request (request_id, hospital_id, patient_id, blood_group, component, units_needed, status, requested_on) VALUES (4, 3, 3, 'O-',  'WHOLE_BLOOD', 1, 'FULFILLED', SYSDATE - 18);
INSERT INTO blood_request (request_id, hospital_id, patient_id, blood_group, component, units_needed, status, requested_on) VALUES (5, 5, 5, 'O+',  'RBC',         1, 'PENDING',   SYSDATE - 2);

INSERT INTO blood_issue (issue_id, request_id, unit_id, issued_on) VALUES (1, 4, 15, SYSDATE - 18);

-- ---------------------------------------------------------------------
-- Organ donors
--   1: deceased O- kidney donor  -> compatible with every ABO group
--   2: living O+ liver donor     -> only O recipients
--   3: deceased AB+ heart donor  -> no compatible heart recipient (tests the no-match error)
-- ---------------------------------------------------------------------
INSERT INTO organ_donor (organ_donor_id, donor_id, organ_type, donor_kind, hla_type, consent_date, status) VALUES (1,  5, 'KIDNEY', 'DECEASED', 'A2-B7-DR4',  TRUNC(SYSDATE) - 3, 'AVAILABLE');
INSERT INTO organ_donor (organ_donor_id, donor_id, organ_type, donor_kind, hla_type, consent_date, status) VALUES (2, 12, 'LIVER',  'LIVING',   'A1-B8-DR3',  TRUNC(SYSDATE) - 10, 'AVAILABLE');
INSERT INTO organ_donor (organ_donor_id, donor_id, organ_type, donor_kind, hla_type, consent_date, status) VALUES (3, 19, 'HEART',  'DECEASED', 'A3-B35-DR1', TRUNC(SYSDATE) - 1, 'AVAILABLE');

-- ---------------------------------------------------------------------
-- Organ waitlist
--   Expected ranking for organ donor 1 (kidney):
--     score = urgency*10 + months waited (+5 if same blood group, O- here -> none)
--     w2 (Deepa)  9*10 + 4  = 94   <- best
--     w1 (Farhan) 7*10 + 13 = 83
--     w7 (Anita)  8*10 + 1  = 81
-- ---------------------------------------------------------------------
INSERT INTO organ_waitlist (waitlist_id, patient_id, organ_type, medical_urgency, hla_type, registered_on, status) VALUES (1,  6, 'KIDNEY', 7, 'A2-B44-DR4',  TRUNC(SYSDATE) - 400, 'WAITING');
INSERT INTO organ_waitlist (waitlist_id, patient_id, organ_type, medical_urgency, hla_type, registered_on, status) VALUES (2,  7, 'KIDNEY', 9, 'A2-B7-DR15',  TRUNC(SYSDATE) - 120, 'WAITING');
INSERT INTO organ_waitlist (waitlist_id, patient_id, organ_type, medical_urgency, hla_type, registered_on, status) VALUES (3,  9, 'KIDNEY', 5, 'A24-B27-DR7', TRUNC(SYSDATE) - 700, 'WAITING');
INSERT INTO organ_waitlist (waitlist_id, patient_id, organ_type, medical_urgency, hla_type, registered_on, status) VALUES (4,  8, 'LIVER',  8, 'A1-B8-DR3',   TRUNC(SYSDATE) - 90,  'WAITING');
INSERT INTO organ_waitlist (waitlist_id, patient_id, organ_type, medical_urgency, hla_type, registered_on, status) VALUES (5, 10, 'HEART',  9, 'A11-B51-DR2', TRUNC(SYSDATE) - 60,  'WAITING');
INSERT INTO organ_waitlist (waitlist_id, patient_id, organ_type, medical_urgency, hla_type, registered_on, status) VALUES (6,  1, 'KIDNEY', 6, 'A29-B44-DR4', TRUNC(SYSDATE) - 200, 'WAITING');
INSERT INTO organ_waitlist (waitlist_id, patient_id, organ_type, medical_urgency, hla_type, registered_on, status) VALUES (7,  4, 'KIDNEY', 8, 'A3-B35-DR1',  TRUNC(SYSDATE) - 30,  'WAITING');

COMMIT;

ALTER TRIGGER trg_blood_unit_bi ENABLE;

-- Sanity check: row counts
SELECT 'HOSPITAL' AS tbl, COUNT(*) AS n FROM hospital       UNION ALL
SELECT 'BLOOD_BANK',      COUNT(*)      FROM blood_bank     UNION ALL
SELECT 'DONOR',           COUNT(*)      FROM donor          UNION ALL
SELECT 'PATIENT',         COUNT(*)      FROM patient        UNION ALL
SELECT 'BLOOD_UNIT',      COUNT(*)      FROM blood_unit     UNION ALL
SELECT 'BLOOD_REQUEST',   COUNT(*)      FROM blood_request  UNION ALL
SELECT 'BLOOD_ISSUE',     COUNT(*)      FROM blood_issue    UNION ALL
SELECT 'ORGAN_DONOR',     COUNT(*)      FROM organ_donor    UNION ALL
SELECT 'ORGAN_WAITLIST',  COUNT(*)      FROM organ_waitlist;
