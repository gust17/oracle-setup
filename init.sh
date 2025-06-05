#!/bin/bash
set -e

echo "⏳ Aguardando inicialização do Oracle..."
# Aguarda até 5 minutos pelo Oracle estar pronto
for i in {1..60}; do
    if echo 'SELECT 1 FROM DUAL;' | sqlplus -S sys/${ORACLE_PASSWORD}@localhost:1521/FREEPDB1 AS SYSDBA | grep -q "1"; then
        echo "✅ Oracle está pronto!"
        break
    fi
    if [ $i -eq 60 ]; then
        echo "❌ Timeout aguardando Oracle inicializar"
        exit 1
    fi
    echo "⏳ Tentativa $i de 60..."
    sleep 5
done

echo "✅ Oracle está pronto. Executando configurações iniciais..."

# Verifica se o arquivo de dump existe
if [ ! -f "/opt/backup/arquivo.dmp" ]; then
    echo "❌ ERRO: Arquivo /opt/backup/arquivo.dmp não encontrado!"
    echo "Por favor, coloque o arquivo arquivo.dmp na pasta backup/"
    exit 1
fi

echo "📦 Criando tablespace e usuários..."

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
EXCEPTION WHEN OTHERS THEN
  IF SQLCODE != -955 THEN RAISE; END IF;
END;
/

EXIT;
EOF

echo "📥 Iniciando importação do dump..."
impdp system/${ORACLE_PASSWORD}@FREEPDB1 \
    directory=BACKUP_DIR \
    dumpfile=arquivo.dmp \
    logfile=importacao.log \
    remap_schema=CONNECTA:devuser \
    remap_tablespace=TS_STTINF01:TS_STTINF01 \
    full=y

if [ $? -eq 0 ]; then
    echo "✅ Importação concluída com sucesso!"
else
    echo "❌ ERRO: Falha na importação do dump. Verifique o arquivo importacao.log"
    exit 1
fi

echo "✨ Configuração finalizada com sucesso!"