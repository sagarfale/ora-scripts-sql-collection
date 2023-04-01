DECLARE
  CURSOR c_sessions IS
    SELECT sid, serial#, username, module,
           program,
           status, trunc(last_call_et/60,2) AS min_inactive,
           sql_id, prev_sql_id
    FROM v$session
    WHERE type = 'USER'
      AND status = 'INACTIVE'
      AND LOWER(program) LIKE '%frmweb%' AND EVENT='SQL*Net message from client' and module like '%FNDSCSGN%'
      AND last_call_et > 1800;
  counter NUMBER := 0;
BEGIN
dbms_output.enable(999999999999999);
  FOR r_session IN c_sessions LOOP
    counter := counter + 1;
    DBMS_OUTPUT.PUT_LINE('SID: ' || r_session.sid);
    DBMS_OUTPUT.PUT_LINE('Serial#: ' || r_session.serial#);
    DBMS_OUTPUT.PUT_LINE('Username: ' || r_session.username);
    DBMS_OUTPUT.PUT_LINE('Module: ' || r_session.module);
    DBMS_OUTPUT.PUT_LINE('Program: ' || r_session.program);
    DBMS_OUTPUT.PUT_LINE('Status: ' || r_session.status);
    DBMS_OUTPUT.PUT_LINE('Minutes Inactive: ' || r_session.min_inactive);
    IF r_session.sql_id IS NOT NULL THEN
      DBMS_OUTPUT.PUT_LINE('Current SQL: ');
      FOR c_sql IN (SELECT sql_fulltext FROM v$sql WHERE sql_id = r_session.sql_id) LOOP
        DBMS_OUTPUT.PUT_LINE(c_sql.sql_fulltext);
      END LOOP;
    ELSE
      DBMS_OUTPUT.PUT_LINE('Current SQL: NULL');
    END IF;
    IF r_session.prev_sql_id IS NOT NULL THEN
      DBMS_OUTPUT.PUT_LINE('Previous SQL: ');
      FOR c_sql IN (SELECT sql_fulltext FROM v$sql WHERE sql_id = r_session.prev_sql_id) LOOP
        DBMS_OUTPUT.PUT_LINE(c_sql.sql_fulltext);
      END LOOP;
    ELSE
      DBMS_OUTPUT.PUT_LINE('Previous SQL: NULL');
    END IF;
    DBMS_OUTPUT.PUT_LINE('-----------------------');
  END LOOP;
  DBMS_OUTPUT.PUT_LINE('Total Sessions: ' || counter);
END;
/
