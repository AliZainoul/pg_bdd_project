#!/bin/bash

#! UNIQUEMENT POUR LES MACOS

#  IN DEV, ONE MUST USE .env OR CONFIG FILES OR environment variables  ===
#  IN PROD, ONE MUST USE DOCKER  ===
# Nom du rôle, de la base de données et du tablespace
DB_USER="ecommerce_user"
DB_NAME="ecommerce_db"
TABLESPACE_NAME="ecommerce_ts"
TABLESPACE_PATH="/Users/Shared/pgsql_tablespaces/${TABLESPACE_NAME}"

# Utilisateur actuel macOS
PG_SUPERUSER=$(whoami)

# Connexion explicite à la base 'postgres' (toujours existante)
PG_CONNECTION="psql -U $PG_SUPERUSER -d postgres"

echo "🔍 Vérification de la version de PostgreSQL (15 recommandée)..."
PSQL_VERSION=$(psql --version | grep -oE '[0-9]+\.[0-9]+')
if [[ $PSQL_VERSION != 15* ]]; then
  echo "⚠️  PostgreSQL $PSQL_VERSION détecté. Utilisez bien PostgreSQL 15."
  exit 1
fi

echo "🧪 Vérification que le service PostgreSQL 15 est actif..."
brew services list | grep postgresql@15 | grep started >/dev/null
if [ $? -ne 0 ]; then
  echo "🚀 Démarrage du service PostgreSQL 15..."
  brew services start postgresql@15
else
  echo "✅ PostgreSQL 15 déjà actif."
fi

# Vérification que la connexion fonctionne
echo "🔐 Vérification des droits du superutilisateur PostgreSQL ($PG_SUPERUSER)..."
$PG_CONNECTION -c "\q"
if [ $? -ne 0 ]; then
  echo "❌ Erreur : Impossible de se connecter avec l'utilisateur '$PG_SUPERUSER' à la base 'postgres'."
  echo "💡 Conseil : Assurez-vous que le rôle '$PG_SUPERUSER' existe dans PostgreSQL ou connectez-vous avec un superutilisateur valide."
  exit 1
fi

# Création du rôle s'il n'existe pas
echo "👤 Vérification ou création du rôle PostgreSQL '${DB_USER}'..."
ROLE_EXISTS=$($PG_CONNECTION -tAc "SELECT 1 FROM pg_roles WHERE rolname='${DB_USER}'")
if [ "$ROLE_EXISTS" = "1" ]; then
  echo "ℹ️  Le rôle '${DB_USER}' existe déjà."
else
  $PG_CONNECTION -c "CREATE ROLE ${DB_USER} WITH LOGIN PASSWORD 'password';"
  $PG_CONNECTION -c "ALTER ROLE ${DB_USER} CREATEDB;"
fi

# Création de la base de données si elle n'existe pas
echo "🗂 Création de la base de données '${DB_NAME}'..."
DB_EXISTS=$($PG_CONNECTION -tAc "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'")
if [ "$DB_EXISTS" = "1" ]; then
  echo "ℹ️  La base de données '${DB_NAME}' existe déjà."
else
  $PG_CONNECTION -c "CREATE DATABASE ${DB_NAME} OWNER ${DB_USER};"
fi

# Création du répertoire de tablespace
echo "📁 Vérification du répertoire de tablespace..."
if [ ! -d "${TABLESPACE_PATH}" ]; then
  sudo mkdir -p "${TABLESPACE_PATH}"
  sudo chown "$(whoami)" "${TABLESPACE_PATH}"
  echo "✅ Répertoire '${TABLESPACE_PATH}' créé."
else
  echo "ℹ️  Le répertoire '${TABLESPACE_PATH}' existe déjà."
fi

# Création du tablespace PostgreSQL
echo "🛠 Création du tablespace PostgreSQL '${TABLESPACE_NAME}'..."
TABLESPACE_EXISTS=$($PG_CONNECTION -tAc "SELECT 1 FROM pg_tablespace WHERE spcname = '${TABLESPACE_NAME}'")
if [ "$TABLESPACE_EXISTS" = "1" ]; then
  echo "ℹ️  Le tablespace '${TABLESPACE_NAME}' existe déjà."
else
  $PG_CONNECTION -c "CREATE TABLESPACE ${TABLESPACE_NAME} LOCATION '${TABLESPACE_PATH}';"
fi

# Connexion de test à la base avec le nouvel utilisateur
echo "✅ Connexion à la base '${DB_NAME}' avec l'utilisateur '${DB_USER}'..."
psql -U "${DB_USER}" -d "${DB_NAME}" -c "\l"
if [ $? -ne 0 ]; then
  echo "❌ Échec de la connexion avec '${DB_USER}' à la base '${DB_NAME}'."
  echo "💡 Vérifiez que le mot de passe ou les droits sont corrects."
  exit 1
fi

echo "🎉 Script terminé avec succès."