#!/bin/bash
set -e

# Carrega as variáveis de ambiente
source .env

echo "🔄 Iniciando processo de reset do banco de dados..."

# Conecta como SYSDBA e executa os comandos de limpeza
sqlplus -S /nolog <<EOF
CONNECT sys/${ORACLE_PASSWORD}@localhost:1521/FREEPDB1 AS SYSDBA

-- Desconecta todas as sessões existentes
BEGIN
  FOR r IN (SELECT sid, serial# FROM v\$session WHERE username IN ('DEVUSER', 'APP_MOBILE_PROD', 'INFOCONSIG1')) LOOP
    EXECUTE IMMEDIATE 'ALTER SYSTEM KILL SESSION ''' || r.sid || ',' || r.serial# || ''' IMMEDIATE';
  END LOOP;
END;
/

-- Remove os usuários existentes
BEGIN
  EXECUTE IMMEDIATE 'DROP USER devuser CASCADE';
EXCEPTION
  WHEN OTHERS THEN
    IF SQLCODE != -01918 THEN RAISE; END IF;
END;
/

BEGIN
  EXECUTE IMMEDIATE 'DROP USER APP_MOBILE_PROD CASCADE';
EXCEPTION
  WHEN OTHERS THEN
    IF SQLCODE != -01918 THEN RAISE; END IF;
END;
/

BEGIN
  EXECUTE IMMEDIATE 'DROP USER INFOCONSIG1 CASCADE';
EXCEPTION
  WHEN OTHERS THEN
    IF SQLCODE != -01918 THEN RAISE; END IF;
END;
/

-- Remove o tablespace
BEGIN
  EXECUTE IMMEDIATE 'DROP TABLESPACE TS_STTINF01 INCLUDING CONTENTS AND DATAFILES';
EXCEPTION
  WHEN OTHERS THEN
    IF SQLCODE != -00959 THEN RAISE; END IF;
END;
/

-- Recria o tablespace
BEGIN
  EXECUTE IMMEDIATE q'[
    CREATE TABLESPACE TS_STTINF01 DATAFILE 'ts_sttinf01.dbf' SIZE 500M AUTOEXTEND ON NEXT 10M MAXSIZE UNLIMITED
    EXTENT MANAGEMENT LOCAL
    SEGMENT SPACE MANAGEMENT AUTO
  ]';
END;
/

-- Recria os usuários
BEGIN
  EXECUTE IMMEDIATE 'CREATE USER devuser IDENTIFIED BY ${ORACLE_PASSWORD} DEFAULT TABLESPACE TS_STTINF01 QUOTA UNLIMITED ON TS_STTINF01';
  EXECUTE IMMEDIATE 'GRANT CONNECT, RESOURCE, DBA TO devuser';
END;
/

BEGIN
  EXECUTE IMMEDIATE 'CREATE USER APP_MOBILE_PROD IDENTIFIED BY ${ORACLE_PASSWORD} DEFAULT TABLESPACE TS_STTINF01 QUOTA UNLIMITED ON TS_STTINF01';
  EXECUTE IMMEDIATE 'GRANT CONNECT, RESOURCE TO APP_MOBILE_PROD';
END;
/

BEGIN
  EXECUTE IMMEDIATE 'CREATE USER INFOCONSIG1 IDENTIFIED BY ${ORACLE_PASSWORD} DEFAULT TABLESPACE TS_STTINF01 QUOTA UNLIMITED ON TS_STTINF01';
  EXECUTE IMMEDIATE 'GRANT CONNECT, RESOURCE TO INFOCONSIG1';
END;
/

-- Recria o diretório de backup
BEGIN
  EXECUTE IMMEDIATE q'[
    CREATE OR REPLACE DIRECTORY BACKUP_DIR AS '/opt/backup'
  ]';
END;
/

EXIT;
EOF

# Verifica se o dump existe e importa se necessário
if [ -f "/opt/backup/arquivo.dmp" ]; then
  echo "📥 Iniciando importação do dump..."
  impdp devuser/${ORACLE_PASSWORD}@FREEPDB1 \
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

echo "✅ Reset do banco de dados concluído com sucesso!" 