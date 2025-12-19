// PL/SQL FUNCTIONS (PHASE VI)
1. Calculate No-Show Risk Percentage
CREATE OR REPLACE FUNCTION calculate_risk(p_patient_id NUMBER)
RETURN NUMBER IS
    v_missed NUMBER;
    v_total NUMBER;
BEGIN
    SELECT COUNT(*) INTO v_total
    FROM appointments
    WHERE patient_id = p_patient_id;

    SELECT COUNT(*) INTO v_missed
    FROM appointments
    WHERE patient_id = p_patient_id
      AND status = 'Missed';

    IF v_total = 0 THEN
        RETURN 0;
    END IF;

    RETURN (v_missed / v_total) * 100;
END;
/

// Determine Risk Level
CREATE OR REPLACE FUNCTION risk_level_fn(p_risk NUMBER)
RETURN VARCHAR2 IS
BEGIN
    IF p_risk >= 60 THEN
        RETURN 'HIGH';
    ELSIF p_risk BETWEEN 30 AND 59 THEN
        RETURN 'MEDIUM';
    ELSE
        RETURN 'LOW';
    END IF;
END;
/

// PROCEDURES (PHASE VI)
Update Risk Score Procedure
CREATE OR REPLACE PROCEDURE update_risk_score(p_patient_id NUMBER) IS
    v_risk NUMBER;
    v_level VARCHAR2(20);
BEGIN
    v_risk := calculate_risk(p_patient_id);
    v_level := risk_level_fn(v_risk);

    MERGE INTO risk_scores r
    USING dual
    ON (r.patient_id = p_patient_id)
    WHEN MATCHED THEN
        UPDATE SET
            missed_count = (SELECT COUNT(*) FROM appointments WHERE patient_id=p_patient_id AND status='Missed'),
            total_appointments = (SELECT COUNT(*) FROM appointments WHERE patient_id=p_patient_id),
            risk_percentage = v_risk,
            risk_level = v_level,
            last_updated = SYSDATE
    WHEN NOT MATCHED THEN
        INSERT (patient_id, missed_count, total_appointments, risk_percentage, risk_level)
        VALUES (
            p_patient_id,
            (SELECT COUNT(*) FROM appointments WHERE patient_id=p_patient_id AND status='Missed'),
            (SELECT COUNT(*) FROM appointments WHERE patient_id=p_patient_id),
            v_risk,
            v_level
        );
END;
/

// CURSOR & WINDOW FUNCTIONS (ANALYTICS)
Cursor Example
DECLARE
    CURSOR c_patients IS
        SELECT patient_id FROM patients;
BEGIN
    FOR rec IN c_patients LOOP
        update_risk_score(rec.patient_id);
    END LOOP;
END;
/
// Window Function – Ranking High Risk Patients
SELECT 
    p.full_name,
    r.risk_percentage,
    RANK() OVER (ORDER BY r.risk_percentage DESC) AS risk_rank
FROM risk_scores r
JOIN patients p ON p.patient_id = r.patient_id;


// BUSINESS RULE & TRIGGER (PHASE VII)
Restriction Function
CREATE OR REPLACE FUNCTION is_restricted_day
RETURN BOOLEAN IS
    v_day VARCHAR2(10);
    v_count NUMBER;
BEGIN
    v_day := TO_CHAR(SYSDATE, 'DY');

    IF v_day NOT IN ('SAT','SUN') THEN
        RETURN TRUE;
    END IF;

    SELECT COUNT(*) INTO v_count
    FROM public_holidays
    WHERE holiday_date = TRUNC(SYSDATE);

    IF v_count > 0 THEN
        RETURN TRUE;
    END IF;

    RETURN FALSE;
END;
/

Compound Trigger with Audit
CREATE OR REPLACE TRIGGER trg_appointments_restrict
BEFORE INSERT OR UPDATE OR DELETE ON appointments
BEGIN
    IF is_restricted_day THEN
        INSERT INTO audit_log
        VALUES (NULL, USER, 'DML', 'APPOINTMENTS', SYSDATE, 'DENIED',
                'Operation blocked on weekday or holiday');

        RAISE_APPLICATION_ERROR(-20001, 'DML not allowed on weekdays or holidays');
    ELSE
        INSERT INTO audit_log
        VALUES (NULL, USER, 'DML', 'APPOINTMENTS', SYSDATE, 'ALLOWED',
                'Operation permitted');
    END IF;
END;
/

// BI & KPI QUERIES (PHASE VIII)
// Overall No-Show Rate
SELECT 
    ROUND(
        SUM(CASE WHEN status='Missed' THEN 1 ELSE 0 END) / COUNT(*) * 100, 2
    ) AS no_show_rate
FROM appointments;

// High Risk Patients
SELECT p.full_name, r.risk_percentage, r.risk_level
FROM risk_scores r
JOIN patients p ON p.patient_id = r.patient_id
WHERE r.risk_level = 'HIGH';

// Daily Appointment Turnout
SELECT 
    appointment_date,
    COUNT(*) AS total_appointments,
    SUM(CASE WHEN status='Attended' THEN 1 ELSE 0 END) AS attended
FROM appointments
GROUP BY appointment_date
ORDER BY appointment_date;

// AUDIT REPORT QUERY
SELECT *
FROM audit_log
ORDER BY action_date DESC;
