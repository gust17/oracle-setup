#!/bin/bash
set -e

echo "⏳ Aguardando inicialização do Oracle..."
until echo 'SELECT 1 FROM DUAL;' | sqlplus -S sys/${ORACLE_PASSWORD}@localhost:1521/FREEPDB1 AS SYSDBA | grep "1"; do
  sleep 5
done

echo "✅ Oracle está pronto. Executando configurações iniciais..."

sqlplus -S /nolog <<EOF
CONNECT sys/${ORACLE_PASSWORD}@localhost:1521/FREEPDB1 AS SYSDBA

-- Criação do tablespace TS_STTINF01
BEGIN
  EXECUTE IMMEDIATE q'[
    CREATE TABLESPACE TS_STTINF01 DATAFILE '/opt/oracle/oradata/FREE/ts_sttinf01.dbf' SIZE 500M AUTOEXTEND ON NEXT 10M MAXSIZE UNLIMITED
    EXTENT MANAGEMENT LOCAL
    SEGMENT SPACE MANAGEMENT AUTO
  ]';
EXCEPTION
  WHEN OTHERS THEN
    IF SQLCODE != -955 THEN RAISE; END IF;
END;
/

-- Criação dos usuários
BEGIN
  EXECUTE IMMEDIATE 'CREATE USER devuser IDENTIFIED BY ${ORACLE_PASSWORD} DEFAULT TABLESPACE TS_STTINF01 QUOTA UNLIMITED ON TS_STTINF01';
  EXECUTE IMMEDIATE 'GRANT CONNECT, RESOURCE, DBA TO devuser';
EXCEPTION WHEN OTHERS THEN
  IF SQLCODE != -01920 THEN RAISE; END IF;
END;
/

BEGIN
  EXECUTE IMMEDIATE 'CREATE USER APP_MOBILE_PROD IDENTIFIED BY ${ORACLE_PASSWORD} DEFAULT TABLESPACE TS_STTINF01 QUOTA UNLIMITED ON TS_STTINF01';
  EXECUTE IMMEDIATE 'GRANT CONNECT, RESOURCE TO APP_MOBILE_PROD';
EXCEPTION WHEN OTHERS THEN
  IF SQLCODE != -01920 THEN RAISE; END IF;
END;
/

BEGIN
  EXECUTE IMMEDIATE 'CREATE USER INFOCONSIG1 IDENTIFIED BY ${ORACLE_PASSWORD} DEFAULT TABLESPACE TS_STTINF01 QUOTA UNLIMITED ON TS_STTINF01';
  EXECUTE IMMEDIATE 'GRANT CONNECT, RESOURCE TO INFOCONSIG1';
EXCEPTION WHEN OTHERS THEN
  IF SQLCODE != -01920 THEN RAISE; END IF;
END;
/

-- Criação do diretório lógico BACKUP_DIR
BEGIN
  EXECUTE IMMEDIATE q'[
    CREATE OR REPLACE DIRECTORY BACKUP_DIR AS '/opt/backup'
  ]';
END;
/

EXIT;
EOF

# Verifica se o dump existe antes de importar
if [ -f "/opt/backup/arquivo.dmp" ]; then
  echo "📥 Iniciando importação do dump..."
  impdp system/${ORACLE_PASSWORD}@FREEPDB1 \
    directory=BACKUP_DIR \
    dumpfile=arquivo.dmp \
    logfile=importacao.log \
    remap_schema=CONNECTA:devuser \
    remap_tablespace=TS_STTINF01:TS_STTINF01 \
    full=y
  echo "✅ Importação concluída."
else
  echo "⚠️ Dump /opt/backup/arquivo.dmp não encontrado. Importação ignorada."
fi