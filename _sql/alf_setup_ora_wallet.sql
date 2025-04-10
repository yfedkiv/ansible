select * from v$parameter where name IN ( 'wallet_root', 'tde_configuration');
select * from v$encryption_wallet;


-- Step 1 (run as DELIUS_APP_SCHEMA): Check current settings

SELECT
  SPGCONFIG.get_alfresco_url         AS alf_url,
  LENGTH(SPGCONFIG.get_alfresco_url) AS alf_url_LEN,
  SPGCONFIG.get_alfresco_user        AS alf_user,
  SPGCONFIG.get_alfresco_wallet      AS alf_wallet
FROM dual;

--https://hmpps-delius-alfresco-dev.apps.live.cloud-platform.service.justice.gov.uk/alfresco/service/noms-spg


-- Step 2 (run as DELIUS_APP_SCHEMA): Set the ALFURL SPG Parameter; set the ACEs
--    NOTE: please make sure that the L_ALF_URL variable is set to a correct value
DECLARE
    --
    l_alf_url  VARCHAR2(512) := 'https://hmpps-delius-alfresco-dev.apps.live.cloud-platform.service.justice.gov.uk/alfresco/service/noms-spg';
    l_alf_host VARCHAR2(512);
    --
    PROCEDURE do_init IS
    BEGIN
        --
        SPGConfig.set_alfresco_url(l_alf_url);
        l_alf_host := PKG_LstUtl.list_num_elem(PKG_LstUtl.list_num_elem(l_alf_url, '://', 2), '/alfresco', 1);
        --
--        SELECT PKG_LstUtl.list_num_elem(PKG_LstUtl.list_num_elem(value_string, '://', 2), '/alfresco', 1) AS alf_host
--        INTO l_alf_host
--        FROM spg_control
--        WHERE control_code = 'ALFURL';
        --
    END do_init;
    --
    PROCEDURE do_clear_old_acl IS
    BEGIN
        --
        FOR x IN (
          SELECT host, lower_port,upper_port,principal,privilege
          FROM dba_host_aces
          WHERE principal = 'DELIUS_APP_SCHEMA'
            AND ( host LIKE 'nd-systest-wl0_.bcl.local' OR
                  host IN (
                    'alfresco.dev.delius-core.probation.hmpps.dsd.io',
                    'alfresco.mis-dev.delius.probation.hmpps.dsd.io',
                    'hmpps-delius-alfresco-dev.apps.live.cloud-platform.service.justice.gov.uk',
                    'mpps-delius-alfresco-dev.apps.live.cloud-platform.service.justice.gov.uk',
                    'alfresco.dev.delius-core.probation.hmpps.dsd.io',
                    'alfresco.mis-dev.delius.probation.hmpps.dsd.io',
                    'hmpps-delius-alfresco-dev.apps.live.cloud-platform.service.justice.gov.uk',
                    'hmpps-delius-alfresco-dev.apps.live.cloud-platform.service.justice.gov.uk' ) ) )
        LOOP
            DBMS_NETWORK_ACL_ADMIN.remove_host_ace (
                host             => x.host, 
                lower_port       => x.lower_port,
                upper_port       => x.upper_port,
                ace              => xs$ace_type(
                                        privilege_list => xs$name_list(x.privilege),
                                        principal_name => x.principal,
                                        principal_type => xs_acl.ptype_db),
                remove_empty_acl => TRUE );
        END LOOP;
        --
    END do_clear_old_acl;
    --
    PROCEDURE do_set_acl IS
    BEGIN
        --
        DBMS_NETWORK_ACL_ADMIN.append_host_ace (
            host       => l_alf_host, 
            lower_port => 443,
            upper_port => 443,
            ace        => xs$ace_type(
                              privilege_list => xs$name_list('http'),
                              principal_name => 'DELIUS_APP_SCHEMA',
                              principal_type => xs_acl.ptype_db) );
        --
    END do_set_acl;
    --
BEGIN
    --
    do_init;
    --
    do_clear_old_acl;
    do_set_acl;
    --
    COMMIT;
    --
END;
/

WITH T AS (
    SELECT
      principal,
      host,
      lower_port,
      upper_port,
      acl,
      'connect' AS PRIVILEGE, 
      DECODE(DBMS_NETWORK_ACL_ADMIN.check_privilege_aclid(aclid, principal, 'connect'), 1,'GRANTED', 0,'DENIED', NULL) AS PRIVILEGE_STATUS
    FROM
      dba_network_acls
        JOIN dba_network_acl_privileges USING (acl, aclid)  
    UNION ALL
    SELECT
      principal,
      host,
      NULL AS lower_port,
      NULL AS upper_port,
      acl, 
      'resolve' AS PRIVILEGE, 
      DECODE(DBMS_NETWORK_ACL_ADMIN.check_privilege_aclid(aclid, principal, 'resolve'), 1,'GRANTED', 0,'DENIED', NULL) AS PRIVILEGE_STATUS
    FROM
      dba_network_acls
        JOIN dba_network_acl_privileges USING (acl, aclid) )
--
SELECT *
FROM T
WHERE principal = 'DELIUS_APP_SCHEMA';


-- Step 3 (run from the SSH console as oracle): Retrieve SSL certificates from the ALF server
--    NOTE: please make sure that the ALF_HOST variable is set to a correct value

export ALF_HOST=hmpps-delius-alfresco-dev.apps.live.cloud-platform.service.justice.gov.uk; echo Q | openssl s_client -connect $ALF_HOST:443 -tls1_2 -showcerts > /tmp/alf_certs.txt
rm /tmp/alf.[0-9][0-9].crt
awk 'BEGIN{INFLAG=0}
  /-----BEGIN CERTIFICATE-----/{INFLAG=1}
  {if(INFLAG==1){print $0}}
  /-----END CERTIFICATE-----/{INFLAG=0}' /tmp/alf_certs.txt | csplit --prefix='/tmp/alf.' --suffix-format='%02d.crt' --elide-empty-files  - "/-----END CERTIFICATE-----/+1" {*}
ll /tmp/alf.[0-9][0-9].crt

-- Step 4 (run from the SSH console as oracle): Delete old (if exists) wallets; Create new Oracle Wallet
export SYSTEM_PWD=NDAmanager1; \
#export WALLET_DIR=$ORACLE_HOME/dbs/alfresco_wallet; \
export WALLET_DIR=/u01/app/oracle/wallets/alfresco_wallet; \
export WALLET_DIR0=/u01/app/oracle/product/19.0.0/db/dbs/alfresco_wallet; \
export WALLET_DIR1=/u01/app/oracle/product/19.18.0/db/dbs/alfresco_wallet; \
export WALLET_DIR2=$ORACLE_HOME/dbs/alfresco_wallet; \
echo $WALLET_DIR; mkdir -p $WALLET_DIR; chmod 700 $WALLET_DIR; \
cd $WALLET_DIR; ll $WALLET_DIR

orapki wallet remove -wallet $WALLET_DIR0 -trusted_cert_all -pwd $SYSTEM_PWD; \
orapki wallet remove -wallet $WALLET_DIR1 -trusted_cert_all -pwd $SYSTEM_PWD; \
orapki wallet remove -wallet $WALLET_DIR2 -trusted_cert_all -pwd $SYSTEM_PWD; \
orapki wallet remove -wallet $WALLET_DIR -trusted_cert_all -pwd $SYSTEM_PWD; \
rm -Rf $WALLET_DIR0 $WALLET_DIR1 $WALLET_DIR2

ll $WALLET_DIR; \
orapki wallet create -wallet $WALLET_DIR -pwd $SYSTEM_PWD -auto_login; \
ll $WALLET_DIR

-- Step 5 (run from the SSH console as oracle): Make sure that there are no existing wallets in Oracle that have matching MD5 checksums
md5sum /tmp/alf.[0-9][0-9].crt | grep -v "alf.00.crt"

--c0d3b5397d28836e46a62b3cd5f4fc23  /tmp/alf.01.crt
--old:
--5e1eb33c2d6881c8d4ed0389683a0630  /tmp/alf.01.crt
--be77e5992c00fcd753d1b9c11d3768f2  /tmp/alf.01.crt
--505444090df336fa2a75cc94cb3ce079  /tmp/alf.02.crt

orapki wallet display -wallet $WALLET_DIR | awk -F: 'BEGIN{TRUSTED=0}
                    /Trusted Certificates/{TRUSTED=1}
                    /Subject/{if(TRUSTED==1){print $2}}' | sed 's/^\s*//'


-- Step 6 (run from the SSH console as oracle): Add new ALF certificates within the Oracle Wallet
--   NOTE: make sure that the same certificate hasn't been created more than once (see previous step)

orapki wallet add -wallet $WALLET_DIR -trusted_cert -cert /tmp/alf.01.crt -pwd $SYSTEM_PWD
orapki wallet add -wallet $WALLET_DIR -trusted_cert -cert /tmp/alf.02.crt -pwd $SYSTEM_PWD
        
orapki wallet display -wallet $WALLET_DIR | awk -F: 'BEGIN{TRUSTED=0}
                    /Trusted Certificates/{TRUSTED=1}
                    /Subject/{if(TRUSTED==1){print $2}}' | sed 's/^\s*//'

-- Step 7 (run from the SSH console as oracle): Tidy up temporary files in /tmp directory
rm /tmp/alf.[0-9][0-9].crt /tmp/alf_certs.txt

-- Step 8 (run as DELIUS_APP_SCHEMA): Set the 
DECLARE
--    l_wallet_dir VARCHAR2(512) := '/u01/app/oracle/product/19.25.0/db/dbs/alfresco_wallet';
    l_wallet_dir VARCHAR2(512) := '/u01/app/oracle/wallets/alfresco_wallet';
BEGIN
    --
--    SELECT SUBSTR(value, 1, INSTR(value, 'spfile', 1)-1) || 'alfresco_wallet' AS wallet_dir INTO l_wallet_dir
--    FROM v$parameter WHERE name = 'spfile';
    --
    SPGConfig.set_alfresco_wallet('file:' || l_wallet_dir);
    --
    COMMIT;
    --
END;
/

SELECT
  SPGCONFIG.get_alfresco_url         AS alf_url,
  LENGTH(SPGCONFIG.get_alfresco_url) AS alf_url_LEN,
  SPGCONFIG.get_alfresco_user        AS alf_user,
  SPGCONFIG.get_alfresco_wallet      AS alf_wallet
FROM dual;


--file:/u01/app/oracle/product/19.25.0/db/dbs/alfresco_wallet

--
-- TEST ALF
--

set serveroutput on size unlimited;
DECLARE
    CURSOR cs IS 
      SELECT *
      FROM offender O
      WHERE 1=1
        AND EXISTS (
            SELECT 1
            FROM document
            WHERE offender_id = O.offender_id
            AND TRIM(alfresco_document_id) IS NOT NULL );
    l_rec cs%ROWTYPE;
    l_cnt NUMBER;
BEGIN
    OPEN cs;
    LOOP
        FETCH cs INTO l_rec;
        EXIT WHEN cs%NOTFOUND;
        --
        SELECT COUNT(*) INTO l_cnt FROM TABLE( DocMigrationSupport.alfrescoContent(l_rec.crn) );
        EXIT WHEN l_cnt > 0;
    END LOOP;
    CLOSE cs;
    --
    IF l_cnt > 0 THEN
        DBMS_OUTPUT.put_line('crn=' || l_rec.crn || ' (cnt=' || l_cnt || ')');
    ELSE
        DBMS_OUTPUT.put_line('NOT Found. (cnt=' || l_cnt || ')');
    END IF;
END;
/

set serveroutput on size unlimited;
DECLARE
    l_wallet_dir     VARCHAR2(512) := SPGConfig.get_alfresco_wallet;
    l_url            SPG_CONTROL.value_string%TYPE := SPGConfig.get_alfresco_url;          
    l_http_request   UTL_HTTP.req;
    l_http_response  UTL_HTTP.resp;
    l_text           VARCHAR2(32767);
BEGIN
    --
    DBMS_OUTPUT.put_line('WALLET_DIR: ' || l_wallet_dir);
    DBMS_OUTPUT.put_line('ALF_URL: '    || l_url);
    --
    UTL_HTTP.set_wallet(l_wallet_dir, NULL);
    --
    -- Make a HTTP request and get the response.
    l_http_request  := UTL_HTTP.begin_request(l_url);
    l_http_response := UTL_HTTP.get_response(l_http_request);
    -- Loop through the response.
    BEGIN
        LOOP
            UTL_HTTP.read_text(l_http_response, l_text, 32766);
            DBMS_OUTPUT.put_line (l_text);
        END LOOP;
    EXCEPTION WHEN UTL_HTTP.end_of_body THEN
        UTL_HTTP.end_response(l_http_response);
    END;
EXCEPTION WHEN OTHERS THEN
    UTL_HTTP.end_response(l_http_response);
    RAISE;
END;
/






-------------------- ST6 ALF Setup (using Docker) ------------
#!/usr/bin/env bash

#endpoint=alfresco.dev.delius-core.probation.hmpps.dsd.io
#endpoint=alfresco.mis-dev.delius.probation.hmpps.dsd.io
endpoint=hmpps-delius-alfresco-dev.apps.live.cloud-platform.service.justice.gov.uk

wallet=${ORACLE_HOME}/dbs/alfresco_wallet
system_pwd=NDAmanager1

orapki wallet remove -wallet "${wallet}" -auto_login_only -trusted_cert_all -pwd ${system_pwd} || echo Creating new wallet
orapki wallet create -wallet "${wallet}" -pwd ${system_pwd} -auto_login_only

echo Q | openssl s_client -showcerts -connect "${endpoint}:443" | awk '/BEGIN CERTIFICATE/{file="/tmp/certificate_"i++".cer"} /BEGIN CERTIFICATE/,/END CERTIFICATE/{if(i>1){ print $0 > file }}'
for f in "/tmp/certificate_"*".cer"; do orapki wallet add -wallet "${wallet}" -auto_login_only -trusted_cert -cert "$f" -pwd ${system_pwd} && rm "$f"; done

chown -R 'oracle:oinstall' "${wallet}"

sqlplus sys/NDAmanager1 as sysdba <<EOF
update delius_app_schema.spg_control set value_string='https://${endpoint}/alfresco/service/admin-spg' where control_code='ALFURL';
update delius_app_schema.spg_control set value_string='file:${wallet}' where control_code='ALFWALLET';
exec dbms_network_acl_admin.append_host_ace(host => '${endpoint}', lower_port => '443', upper_port => '443', ace => xs\$ace_type(privilege_list => xs\$name_list('http'), principal_name => 'DELIUS_APP_SCHEMA', principal_type => xs_acl.ptype_db));
EOF
