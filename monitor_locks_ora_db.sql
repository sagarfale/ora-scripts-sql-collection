REM ***************************************************************************
REM  SCRIPT NAME
REM     monitor_Locks.sql
REM
REM  INPUT PARAMETERS
REM     NA
REM
REM  USAGE
REM     Running in SQLPLUS
REM
REM  RETURNS
REM     Lock statistics
REM
REM  DESCRIPTION
REM   Report on Locks
REM
REM
REM
REM
REM ***************************************************************************

REM WHENEVER SQLERROR EXIT sql.sqlcode;

set serveroutput ON trimspool ON linesize 200
set TERM off ECHO off
set timing ON
COLUMN P_TIMESTAMP NEW_VALUE P_TIMESTAMP FORMAT A16;
COLUMN P_INSTANCE  NEW_VALUE P_INSTANCE FORMAT A20;
SELECT TO_CHAR( SYSDATE,'YYYY.MMDD.HH24MI') P_TIMESTAMP FROM DUAL;
select INSTANCE_NAME P_INSTANCE from v$instance;

PROMPT
PROMPT Generating Report (monitor_&&P_INSTANCE&&P_TIMESTAMP..txt spool file)...
PROMPT
SPOOL Locks_&&P_INSTANCE&&P_TIMESTAMP..txt

set TERM on ECHO off

DECLARE
v_cpu_count     VARCHAR2(10);
v_database      VARCHAR2(40);
v_host          VARCHAR2(40);
v_instance      VARCHAR2(40);
v_platform      VARCHAR2(40);
v_rdbms_release VARCHAR2(17);
v_rdbms_version VARCHAR2(10);
v_sysdate       VARCHAR2(15);
v_apps_release  VARCHAR2(50);
v_decode        VARCHAR2(18);
v_locks         NUMBER;
v_locks_count   NUMBER;

-----------------------------------------------------------------------------------------
-- Functions/Procedures
-----------------------------------------------------------------------------------------
PROCEDURE usepid ( p_uxproc in VARCHAR2, p_inst_id in NUMBER ) IS
  v_sid number;
  vs_cnt number;
  s sys.gv_$session%ROWTYPE;
  p sys.gv_$process%ROWTYPE;
  cursor cur_c1 (v_uxproc VARCHAR2,v_inst_id NUMBER) is
  select sid
  from sys.gv_$process p, sys.gv_$session s
  where  p.addr  = s.paddr
  and  (p.spid =  v_uxproc or s.process = v_uxproc )
  and s.inst_id= v_inst_id and p.inst_id=s.inst_id;
BEGIN
    dbms_output.put_line('=====================================================================');
        select nvl(count(sid),0) into vs_cnt from sys.gv_$process p, sys.gv_$session s  where  p.addr  = s.paddr and  (p.spid =  p_uxproc or s.process = p_uxproc) and s.inst_id=p_inst_id and p.inst_id=s.inst_id;
        dbms_output.put_line(to_char(vs_cnt)||' sessions were found with '||p_uxproc||' as their unix process id for the instance number '||p_inst_id);
         dbms_output.put_line('=====================================================================');
        open cur_c1(p_uxproc,p_inst_id);
        LOOP
      FETCH cur_c1 INTO v_sid;
            EXIT WHEN (cur_c1%NOTFOUND);
                select * into s from sys.gv_$session where sid  = v_sid and inst_id=p_inst_id;
                select * into p from sys.gv_$process where addr = s.paddr and inst_id=p_inst_id;
                dbms_output.put_line('SID/Serial  : '|| s.sid||','||s.serial#);
                dbms_output.put_line('Foreground  : '|| 'PID: '||s.process||' - '||s.program);
                dbms_output.put_line('Shadow      : '|| 'PID: '||p.spid||' - '||p.program);
                dbms_output.put_line('Terminal    : '|| s.terminal || '/ ' || p.terminal);
                dbms_output.put_line('OS User     : '|| s.osuser||' on '||s.machine);
                dbms_output.put_line('Ora User    : '|| s.username);
                dbms_output.put_line('Details     : '|| s.action||' - '||s.module);
                dbms_output.put_line('Status Flags: '|| s.status||' '||s.server||' '||s.type);
                dbms_output.put_line('Tran Active : '|| nvl(s.taddr, 'NONE'));
                dbms_output.put_line('Login Time  : '|| to_char(s.logon_time, 'Dy HH24:MI:SS'));
                dbms_output.put_line('Last Call   : '|| to_char(sysdate-(s.last_call_et/60/60/24), 'Dy HH24:MI:SS') || ' - ' || to_char(s.last_call_et/60, '9990.0') || ' min');
                dbms_output.put_line('Lock/ Latch : '|| nvl(s.lockwait, 'NONE')||'/ '||nvl(p.latchwait, 'NONE'));
                dbms_output.put_line('Latch Spin  : '|| nvl(p.latchspin, 'NONE'));
                dbms_output.put_line('Current SQL statement:');
                for c1 in ( select * from sys.gv_$sqltext  where HASH_VALUE = s.sql_hash_value and inst_id=p_inst_id order by piece)
                loop
                dbms_output.put_line(chr(9)||c1.sql_text);
                end loop;
                dbms_output.put_line('Previous SQL statement:');
                for c1 in ( select * from sys.gv_$sqltext  where HASH_VALUE = s.prev_hash_value and inst_id=p_inst_id order by piece)
                loop
                dbms_output.put_line(chr(9)||c1.sql_text);
                end loop;
                dbms_output.put_line('Session Waits:');
                for c1 in ( select * from sys.gv_$session_wait where sid = s.sid and inst_id=p_inst_id)
                loop
        dbms_output.put_line(chr(9)||c1.state||': '||c1.event);
                end loop;
--  dbms_output.put_line('Connect Info:');
--  for c1 in ( select * from sys.gv_$session_connect_info where sid = s.sid and inst_id=p_inst_id) loop
--    dbms_output.put_line(chr(9)||': '||c1.network_service_banner);
--  end loop;
                dbms_output.put_line('Locks:');
                for c1 in ( select  /*+ RULE */ decode(l.type,
          -- Long locks
                      'TM', 'DML/DATA ENQ',   'TX', 'TRANSAC ENQ',
                      'UL', 'PLS USR LOCK',
          -- Short locks
                      'BL', 'BUF HASH TBL',  'CF', 'CONTROL FILE',
                      'CI', 'CROSS INST F',  'DF', 'DATA FILE   ',
                      'CU', 'CURSOR BIND ',
                      'DL', 'DIRECT LOAD ',  'DM', 'MOUNT/STRTUP',
                      'DR', 'RECO LOCK   ',  'DX', 'DISTRIB TRAN',
                      'FS', 'FILE SET    ',  'IN', 'INSTANCE NUM',
                      'FI', 'SGA OPN FILE',
                      'IR', 'INSTCE RECVR',  'IS', 'GET STATE   ',
                      'IV', 'LIBCACHE INV',  'KK', 'LOG SW KICK ',
                      'LS', 'LOG SWITCH  ',
                      'MM', 'MOUNT DEF   ',  'MR', 'MEDIA RECVRY',
                      'PF', 'PWFILE ENQ  ',  'PR', 'PROCESS STRT',
                      'RT', 'REDO THREAD ',  'SC', 'SCN ENQ     ',
                      'RW', 'ROW WAIT    ',
                      'SM', 'SMON LOCK   ',  'SN', 'SEQNO INSTCE',
                      'SQ', 'SEQNO ENQ   ',  'ST', 'SPACE TRANSC',
                      'SV', 'SEQNO VALUE ',  'TA', 'GENERIC ENQ ',
                      'TD', 'DLL ENQ     ',  'TE', 'EXTEND SEG  ',
                      'TS', 'TEMP SEGMENT',  'TT', 'TEMP TABLE  ',
                      'UN', 'USER NAME   ',  'WL', 'WRITE REDO  ',
                      'TYPE='||l.type) type,
                                  decode(l.lmode, 0, 'NONE', 1, 'NULL', 2, 'RS', 3, 'RX',
                       4, 'S',    5, 'RSX',  6, 'X',
                       to_char(l.lmode) ) lmode,
                                   decode(l.request, 0, 'NONE', 1, 'NULL', 2, 'RS', 3, 'RX',
                         4, 'S', 5, 'RSX', 6, 'X',
                         to_char(l.request) ) lrequest,
                                        decode(l.type, 'MR', o.name,
                      'TD', o.name,
                      'TM', o.name,
                      'RW', 'FILE#='||substr(l.id1,1,3)||
                            ' BLOCK#='||substr(l.id1,4,5)||' ROW='||l.id2,
                      'TX', 'RS+SLOT#'||l.id1||' WRP#'||l.id2,
                      'WL', 'REDO LOG FILE#='||l.id1,
                      'RT', 'THREAD='||l.id1,
                      'TS', decode(l.id2, 0, 'ENQUEUE', 'NEW BLOCK ALLOCATION'),
                      'ID1='||l.id1||' ID2='||l.id2) objname
                                from  sys.gv_$lock l, sys.obj$ o
                                where sid   = s.sid
                                and inst_id=p_inst_id
                                        and l.id1 = o.obj#(+) )
                        loop
                        dbms_output.put_line(chr(9)||c1.type||' H: '||c1.lmode||' R: '||c1.lrequest||' - '||c1.objname);
                        end loop;
                        dbms_output.put_line('=====================================================================');
        END LOOP;
        dbms_output.put_line(to_char(vs_cnt)||' sessions were found with '||p_uxproc||' as their unix process id for the instance number '||p_inst_id);
        dbms_output.put_line('Please scroll up to see details of all the sessions.');
        dbms_output.put_line('=====================================================================');
        close cur_c1;
exception
    when no_data_found then
      dbms_output.put_line('Unable to find process id p_uxproc for the instance number '||p_inst_id||' !!!');
          dbms_output.put_line('=====================================================================');
     -- return;
    when others then
      dbms_output.put_line(sqlerrm);
     -- return;
END usepid;
--------------------------
-- PROCEDURE: Check Locks
--------------------------

PROCEDURE check_locks AS
v_inst_id number ;
v_sid     number;
TYPE Locks_tab IS TABLE OF gv$lock%ROWTYPE;
v_locks_tab Locks_tab;

CURSOR  c_lock IS
        SELECT *
        FROM gv$lock
        WHERE (id1, id2, type) in
        (SELECT id1, id2, type FROM gv$lock WHERE request>0)
        ORDER by id1,id2, request ;

cursor c_sessinfo (v_sid NUMBER,v_inst_id NUMBER) is
select s.inst_id,s.status,s.sid,s.serial#,p.spid,s.last_call_et,to_char(s.logon_time,'dd/mm/yy hh24:mi:ss') logon_time,s.osuser,s.username,s.module,s.program,s.action,s.machine
from gv$session s ,gv$process p
where s.paddr = p.addr
and s.inst_id = p.inst_id
and s.sid = v_sid
and s.inst_id = v_inst_id;

 CURSOR v_session  IS 
   SELECT  blocking_session,sid,serial#,wait_class,seconds_in_wait,inst_id
   FROM    gv$session
   WHERE   blocking_session IS NOT NULL
   ORDER BY   blocking_session;

no_locks EXCEPTION;
BEGIN
   FOR v_session_lock IN v_session LOOP
   IF v_session%ROWCOUNT = 1 THEN
   dbms_output.put_line(chr(10));
   dbms_output.put_line('BLOCKING_SESSION SID    SERIAL# WAIT_CLASS                SECONDS_IN_WAIT INST_ID');
   dbms_output.put_line('---------------- ------ ------- ------------------------- --------------- ----------');
   END IF;
   dbms_output.put_line(rpad(v_session_lock.blocking_session,16,' ')||' '||rpad(v_session_lock.sid,6,' ')||' '||rpad(v_session_lock.serial#,7,' ')||' '||rpad(v_session_lock.wait_class,25,' ')||' '||rpad(v_session_lock.seconds_in_wait,15,' ')||' '||v_session_lock.inst_id);
   END LOOP;
   OPEN c_lock;
   FETCH c_lock BULK COLLECT INTO v_locks_tab;
   CLOSE c_lock;
   IF v_locks_tab.COUNT < 1 THEN
   RAISE no_locks;
   END IF;
   FOR i in 1..v_locks_tab.COUNT LOOP
        IF i = 1 THEN
	dbms_output.put_line(chr(10));
        dbms_output.put_line('SESS                      ID1        ID2      LMODE    REQUEST TY    INST_ID');
        dbms_output.put_line('------------------ ---------- ---------- ---------- ---------- -- ----------');
        END IF;
           v_decode := v_locks_tab(i).request ;
        IF v_decode = '0' THEN
           v_decode := 'Holder : ';
        ELSE
           v_decode := 'Waiter : ';
        END IF;
        dbms_output.put_line(v_decode||rpad(v_locks_tab(i).sid,10,' ') || rpad(v_locks_tab(i).id1,11,' ') ||rpad(v_locks_tab(i).id2,11,' ') ||rpad(v_locks_tab(i).lmode,11,' ') ||rpad(v_locks_tab(i).request,11,' ') ||rpad(v_locks_tab(i).type,3,' ')||rpad(v_locks_tab(i).inst_id,10,' '));
   END LOOP;
   FOR i in 1..v_locks_tab.COUNT LOOP
        IF i = 1 THEN
        dbms_output.put_line(chr(10));
        dbms_output.put_line('INST_ID STATUS   SID    SERIAL# SPID       LAST_CALL_ET LOGON_TIME        OSUSER   USERNAME    MODULE           PROGRAM          ACTION                    MACHINE');
        dbms_output.put_line('------- -------- ------ ------- ---------- ------------ ----------------- -------- ----------- ---------------- ---------------- ------------------------- ---------');
        END IF;
        FOR v_sessinfo IN c_sessinfo(v_locks_tab(i).sid ,v_locks_tab(i).inst_id) LOOP
        dbms_output.put_line(rpad(v_sessinfo.inst_id,8,' ')||rpad(v_sessinfo.status,9,' ')||rpad(v_sessinfo.sid,7,' ')||rpad(v_sessinfo.serial#,8,' ')||rpad(v_sessinfo.spid,10,' ')||' '||rpad(v_sessinfo.last_call_et,12,' ')||' '||rpad(v_sessinfo.logon_time,17,' ')||' '||rpad(nvl(v_sessinfo.osuser,' '),8,' ')||' '||rpad(v_sessinfo.username,11,' ')||' '||rpad(nvl(v_sessinfo.module,' '),16,' ')||' '||rpad(nvl(v_sessinfo.program,' '),16,' ')||' '||rpad(nvl(v_sessinfo.action,' '),25,' ')||' '||rpad(v_sessinfo.machine,9,' '));
        END LOOP;
   END LOOP;
   FOR i in 1..v_locks_tab.COUNT LOOP
        IF i = 1 THEN
        dbms_output.put_line(chr(10));
        dbms_output.put_line('More details about the Holders and Waiters' ||CHR(10));
        END IF;
        IF v_locks_tab(i).request = 0 THEN
        dbms_output.put_line('Holder Details');
        dbms_output.put_line('==============');
        ELSE
        dbms_output.put_line('Waiter Details');
        dbms_output.put_line('==============');
        END IF;
        FOR v_sessinfo IN c_sessinfo(v_locks_tab(i).sid ,v_locks_tab(i).inst_id) LOOP
        usepid(v_sessinfo.spid,v_sessinfo.inst_id);
        END LOOP;
   END LOOP;


EXCEPTION WHEN NO_DATA_FOUND THEN
  dbms_output.put_line('No Locks in the DB ');
WHEN no_locks  THEN
  dbms_output.put_line('No Locks in the DB ');
END check_locks;


-----------------------------------------------------------------------------------------
-- Main
-----------------------------------------------------------------------------------------
BEGIN

    SELECT SUBSTR( UPPER( i.host_name ),1,40 ),
           SUBSTR( i.version,1,17 ),
           SUBSTR( UPPER( db.name )||'('||TO_CHAR( db.dbid )||')',1,40 ),
           SUBSTR( UPPER( i.instance_name )||'('||TO_CHAR( i.instance_number )||')',1,40 )
      INTO v_host, v_rdbms_release, v_database, v_instance
      FROM v$database db,
           v$instance i;

    v_rdbms_version := v_rdbms_release;
    IF v_rdbms_release LIKE '%8%.%1%.%7%' THEN v_rdbms_version := '8.1.7.X'; END IF;
    IF v_rdbms_release LIKE '%9%.%2%.%0%' THEN v_rdbms_version := '9.2.0.X'; END IF;
    IF v_rdbms_release LIKE '%10%.%1%.%' THEN v_rdbms_version := '10.1.X'; END IF;

    SELECT SUBSTR( REPLACE( REPLACE( pcv1.product,'TNS for '),':' )||pcv2.status,1,40 )
      INTO v_platform
      FROM product_component_version pcv1,
           product_component_version pcv2
     WHERE UPPER( pcv1.product ) LIKE '%TNS%'
       AND UPPER( pcv2.product ) LIKE '%ORACLE%'
       AND ROWNUM = 1;

    SELECT TO_CHAR(SYSDATE,'DD-MON-YY HH24:MI')
      INTO v_sysdate
      FROM dual;

    SELECT release_name
      INTO v_apps_release
      FROM APPS.fnd_product_groups;

dbms_output.enable(999999999999999);
dbms_output.put_line('*******************************************************************************************************************************');
dbms_output.put_line(
        v_sysdate || CHR(10) ||
        'Database        : ' || v_database || CHR(10) ||
        'Host            : ' || v_host   || CHR(10) ||
        'Instance        : ' || v_instance || CHR(10) ||
        'RBDMS Version   : ' || v_rdbms_version || CHR(10) ||
        'EBS Version     : ' || v_apps_release  || CHR(10) );
dbms_output.put_line('*******************************************************************************************************************************' || CHR(10));

check_locks;

END;
/
spool off;
set serveroutput ON trimspool ON linesize 200
set TERM on ECHO on
set timing OFF

exit

