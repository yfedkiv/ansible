DECLARE
--    l_wallet_dir VARCHAR2(512) := '/u01/app/oracle/product/19.0.0/db/dbs/alfresco_wallet';
    l_wallet_dir VARCHAR2(512) := '/u01/app/oracle/product/19.25.0/db/dbs/alfresco_wallet';
--    l_wallet_dir VARCHAR2(512) := '/u01/app/oracle/admin/ST11NDA/wallet';
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



SELECT SUBSTR(value, 1, INSTR(value, 'spfile', 1)-1) || 'alfresco_wallet' AS wallet_dir
FROM v$parameter WHERE name = 'spfile';
