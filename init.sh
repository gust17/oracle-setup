#!/bin/bash
set -e

echo "â³ Aguardando inicializaÃ§Ã£o do Oracle..."
# Aguarda atÃ© 5 minutos pelo Oracle estar pronto
for i in {1..60}; do
    if echo 'SELECT 1 FROM DUAL;' | sqlplus -S sys/${ORACLE_PASSWORD}@localhost:1521/FREEPDB1 AS SYSDBA | grep -q "1"; then
        echo "âœ… Oracle estÃ¡ pronto!"
        break
    fi
    if [ $i -eq 60 ]; then
        echo "âŒ Timeout aguardando Oracle inicializar"
        exit 1
    fi
    echo "â³ Tentativa $i de 60..."
    sleep 5
done

echo "âœ… Oracle estÃ¡ pronto. Executando configuraÃ§Ãµes iniciais..."

# Verifica se o arquivo de dump existe
if [ ! -f "/opt/backup/arquivo.dmp" ]; then
    echo "âŒ ERRO: Arquivo /opt/backup/arquivo.dmp nÃ£o encontrado!"
    echo "Por favor, coloque o arquivo arquivo.dmp na pasta backup/"
    exit 1
fi

echo "ðŸ“¦ Criando tablespace e usuÃ¡rios..."

sqlplus -S /nolog <<EOF
CONNECT sys/${ORACLE_PASSWORD}@localhost:1521/FREEPDB1 AS SYSDBA

-- CriaÃ§Ã£o do tablespace TS_STTINF01
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

-- CriaÃ§Ã£o dos usuÃ¡rios
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

-- CriaÃ§Ã£o do diretÃ³rio lÃ³gico BACKUP_DIR
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

echo "ðŸ“¥ Iniciando importaÃ§Ã£o do dump..."
impdp system/${ORACLE_PASSWORD}@FREEPDB1 \
    directory=BACKUP_DIR \
    dumpfile=arquivo.dmp \
    logfile=importacao.log \
    remap_schema=OCIPROD1:DEVUSER \
    remap_tablespace=TS_STTINF01:TS_STTINF01 \
    full=y

if [ $? -eq 0 ]; then
    echo "âœ… ImportaÃ§Ã£o concluÃ­da com sucesso!"
else
    echo "âŒ ERRO: Falha na importaÃ§Ã£o do dump. Verifique o arquivo importacao.log"
    exit 1
fi

echo "âœ¨ ConfiguraÃ§Ã£o finalizada com sucesso!"