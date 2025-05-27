@echo off
REM === Variables ===
set "DB_USER=ecommerce_user"
set "DB_NAME=ecommerce_db"
set "TABLESPACE_NAME=ecommerce_ts"
set "TABLESPACE_PATH=C:\pgsql_tablespaces\%TABLESPACE_NAME%"
set "PG_SUPERUSER=postgres"
set "PGPASSWORD=password"
set PGDATA=C:\Program Files\PostgreSQL\15\data


REM === Vérification du service PostgreSQL ===
echo 🧪 Vérification que le service PostgreSQL 15 est actif...
sc query "postgresql-x64-15" | findstr "RUNNING" > nul
if errorlevel 1 (
    echo ▶️ Démarrage du service PostgreSQL...
    pg_ctl start -D "%PGDATA%"
) else (
    echo ✅ Le service PostgreSQL est déjà en cours d'exécution.
)

REM === Vérification ou création du rôle PostgreSQL ===
echo 👤 Vérification ou création du rôle PostgreSQL "%DB_USER%"...
echo 🔐 Veuillez entrer le mot de passe pour l'utilisateur PostgreSQL %PG_SUPERUSER%:

psql -U %PG_SUPERUSER% -W -tAc "SELECT 1 FROM pg_roles WHERE rolname='%DB_USER%'" | findstr "1" >nul
if errorlevel 1 (
    echo ➕ Création du rôle %DB_USER%...
    psql -U %PG_SUPERUSER% -W -c "CREATE ROLE %DB_USER% WITH LOGIN PASSWORD '%PGPASSWORD%';"
    psql -U %PG_SUPERUSER% -W -c "ALTER ROLE %DB_USER% CREATEDB;"
) else (
    echo ℹ️  Le rôle "%DB_USER%" existe déjà.
)

REM === Vérification ou création de la base ===
echo 🗂 Création de la base de données "%DB_NAME%"...
echo 🔐 Veuillez entrer le mot de passe pour l'utilisateur PostgreSQL %PG_SUPERUSER%:

psql -U %PG_SUPERUSER% -W -tAc "SELECT 1 FROM pg_database WHERE datname='%DB_NAME%'" | findstr "1" >nul
if errorlevel 1 (
    echo ➕ Création de la base %DB_NAME%...
    psql -U %PG_SUPERUSER% -W -c "CREATE DATABASE %DB_NAME% OWNER %DB_USER%;"
) else (
    echo ℹ️  La base "%DB_NAME%" existe déjà.
)

REM === Vérification du répertoire du tablespace ===
echo 📁 Vérification du répertoire de tablespace...
if not exist "%TABLESPACE_PATH%" (
    mkdir "%TABLESPACE_PATH%"
    echo ✅ Répertoire "%TABLESPACE_PATH%" créé.
) else (
    echo ℹ️  Le répertoire "%TABLESPACE_PATH%" existe déjà.
)

REM === Vérification ou création du tablespace ===
echo 🛠 Création du tablespace PostgreSQL "%TABLESPACE_NAME%"...
echo 🔐 Veuillez entrer le mot de passe pour l'utilisateur PostgreSQL %PG_SUPERUSER%:

psql -U %PG_SUPERUSER% -W -tAc "SELECT 1 FROM pg_tablespace WHERE spcname='%TABLESPACE_NAME%'" | findstr "1" >nul
if errorlevel 1 (
    echo ➕ Création du tablespace...
    psql -U %PG_SUPERUSER% -W -c "CREATE TABLESPACE %TABLESPACE_NAME% LOCATION '%TABLESPACE_PATH%';"
) else (
    echo ℹ️  Le tablespace "%TABLESPACE_NAME%" existe déjà.
)

REM === Connexion finale pour vérification ===

echo ✅ Connexion à la base "%DB_NAME%" avec l'utilisateur "%DB_USER%"...
echo 🔐 Veuillez entrer le mot de passe pour l'utilisateur PostgreSQL %DB_USER%:

psql -U %DB_USER% -d %DB_NAME% -c "\l"

echo 🎉 Script terminé avec succès.
pause