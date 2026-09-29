#!/usr/bin/env bash
# =============================================================================
#  Zabbix 7.0 LTS - SERVIDOR DE BANCO (PostgreSQL)
#  Ubuntu 26.04
#
#  Rode ESTE script PRIMEIRO, no servidor de banco.
#  Depois rode install_zabbix7_app.sh no servidor da aplicação.
#
#  Uso:
#     sudo bash install_zabbix7_db.sh                    # lê ./.env ao lado do script
#     sudo bash install_zabbix7_db.sh --env /caminho/db.env
#     sudo ZBX_APP_IP=10.0.0.20 bash install_zabbix7_db.sh
#
#  Parâmetros (no .env ou como variáveis de ambiente):
#     ZBX_APP_IP    IP do servidor Zabbix (OBRIGATÓRIO; se vazio, é perguntado)
#     ZBX_DB_PASS   senha do usuário "zabbix" (se vazia, é perguntada)
#     ZBX_DB_NAME   nome do banco               (padrão: zabbix)
#     ZBX_DB_USER   usuário do banco            (padrão: zabbix)
#     ZBX_DB_PORT   porta do PostgreSQL         (padrão: 5432)
#     ZBX_TZ        timezone do sistema         (padrão: America/Sao_Paulo)
#
#  Prioridade: variável de ambiente na linha de comando > .env > padrão.
# =============================================================================
set -Eeuo pipefail

# -----------------------------------------------------------------------------
# Arquivo .env
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --env)   ENV_FILE="${2:?Informe o caminho do arquivo após --env}"; shift 2 ;;
        --env=*) ENV_FILE="${1#*=}"; shift ;;
        -h|--help) sed -n "3,/^# ====/p" "$0"; exit 0 ;;
        *) echo "Parâmetro desconhecido: $1"; exit 1 ;;
    esac
done

# Lê o .env linha a linha (sem "source", para não executar código e para
# aceitar senhas com caracteres especiais). Só aceita chaves ZBX_* e não
# sobrescreve variáveis já definidas na linha de comando.
load_env() {
    local file="$1" line key val n=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        n=$((n+1))
        line="${line%$'\r'}"                                   # arquivos editados no Windows
        [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue        # comentários / linhas vazias
        line="${line#"${line%%[![:space:]]*}"}"                # remove espaços à esquerda
        line="${line#export }"
        if [[ ! "$line" =~ ^(ZBX_[A-Z0-9_]+)=(.*)$ ]]; then
            echo "[AVISO] .env linha ${n} ignorada (formato esperado ZBX_CHAVE=valor)."
            continue
        fi
        key="${BASH_REMATCH[1]}"; val="${BASH_REMATCH[2]}"
        # remove aspas envolventes: "valor" ou 'valor'
        if [[ "$val" =~ ^\"(.*)\"$ || "$val" =~ ^\'(.*)\'$ ]]; then
            val="${BASH_REMATCH[1]}"
        fi
        [[ -n "${!key+x}" ]] && continue                       # linha de comando tem prioridade
        printf -v "$key" '%s' "$val"
    done < "$file"
}

if [[ -f "$ENV_FILE" ]]; then
    echo "[INFO]  Carregando parâmetros de ${ENV_FILE}"
    perms=$(stat -c '%a' "$ENV_FILE")
    [[ "$perms" =~ [1-7]$ ]] && echo "[AVISO] ${ENV_FILE} pode ser lido por outros usuários (permissão ${perms}). Recomendado: chmod 600 ${ENV_FILE}"
    load_env "$ENV_FILE"
else
    echo "[INFO]  Arquivo ${ENV_FILE} não encontrado; usando variáveis de ambiente/padrões."
fi


ZBX_APP_IP="${ZBX_APP_IP:-}"
ZBX_DB_NAME="${ZBX_DB_NAME:-zabbix}"
ZBX_DB_USER="${ZBX_DB_USER:-zabbix}"
ZBX_DB_PASS="${ZBX_DB_PASS:-}"
ZBX_DB_PORT="${ZBX_DB_PORT:-5432}"
ZBX_TZ="${ZBX_TZ:-America/Sao_Paulo}"
LOG_FILE="/var/log/zabbix_db_install_$(date +%Y%m%d_%H%M%S).log"

# -----------------------------------------------------------------------------
# Utilitários
# -----------------------------------------------------------------------------
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*" | tee -a "$LOG_FILE"; }
warn()  { echo -e "${YELLOW}[AVISO]${NC} $*" | tee -a "$LOG_FILE"; }
fatal() { echo -e "${RED}[ERRO]${NC}  $*" | tee -a "$LOG_FILE"; exit 1; }
trap 'fatal "Falha na linha $LINENO. Veja o log: $LOG_FILE"' ERR

export DEBIAN_FRONTEND=noninteractive

# -----------------------------------------------------------------------------
# 1. Verificações iniciais
# -----------------------------------------------------------------------------
[[ $EUID -eq 0 ]] || { echo "Execute como root (sudo)."; exit 1; }
touch "$LOG_FILE"

. /etc/os-release
[[ "${ID}" == "ubuntu" ]] || fatal "Este script é para Ubuntu (detectado: ${ID})."
if [[ "${VERSION_ID}" != "26.04" ]]; then
    warn "Script feito para Ubuntu 26.04, mas o sistema é ${VERSION_ID}. Continuando mesmo assim..."
fi

if [[ -z "$ZBX_APP_IP" ]]; then
    read -rp "IP do servidor da aplicação (Zabbix server): " ZBX_APP_IP
fi
[[ "$ZBX_APP_IP" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || fatal "IP inválido: '${ZBX_APP_IP}'."

if [[ -z "$ZBX_DB_PASS" ]]; then
    while true; do
        read -rsp "Defina a senha do usuário '${ZBX_DB_USER}' no PostgreSQL: " p1; echo
        read -rsp "Confirme a senha: " p2; echo
        [[ -n "$p1" && "$p1" == "$p2" ]] && { ZBX_DB_PASS="$p1"; break; }
        echo "Senhas vazias ou diferentes, tente novamente."
    done
fi
# Aspas simples quebrariam o SQL / arquivos de configuração
[[ "$ZBX_DB_PASS" != *"'"* ]] || fatal "A senha não pode conter aspas simples (')."

# -----------------------------------------------------------------------------
# 2. Instalação do PostgreSQL
# -----------------------------------------------------------------------------
info "Atualizando sistema e instalando PostgreSQL..."
apt-get update -y >>"$LOG_FILE" 2>&1
apt-get install -y postgresql locales >>"$LOG_FILE" 2>&1

sed -i 's/^# *\(en_US.UTF-8\)/\1/; s/^# *\(pt_BR.UTF-8\)/\1/' /etc/locale.gen
locale-gen >>"$LOG_FILE" 2>&1
timedatectl set-timezone "$ZBX_TZ" 2>>"$LOG_FILE" || warn "Não foi possível definir o timezone do sistema."

systemctl enable --now postgresql >>"$LOG_FILE" 2>&1

PG_MAJOR=$(sudo -u postgres psql -tAc "SHOW server_version_num;" | cut -c1-2)
PG_CONF_DIR="/etc/postgresql/${PG_MAJOR}/main"
[[ -d "$PG_CONF_DIR" ]] || fatal "Diretório de configuração não encontrado: ${PG_CONF_DIR}"
info "PostgreSQL ${PG_MAJOR} instalado (config em ${PG_CONF_DIR})."
if [[ "$PG_MAJOR" -gt 17 ]]; then
    warn "PostgreSQL ${PG_MAJOR} pode não ser oficialmente suportado pelo Zabbix 7.0;"
    warn "o script da aplicação vai habilitar AllowUnsupportedDBVersions=1."
fi

# -----------------------------------------------------------------------------
# 3. Usuário e banco
#    O schema é importado pelo script da aplicação (ele tem o zabbix-sql-scripts).
# -----------------------------------------------------------------------------
info "Criando usuário e banco '${ZBX_DB_NAME}'..."
if sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='${ZBX_DB_USER}'" | grep -q 1; then
    warn "Usuário ${ZBX_DB_USER} já existe; atualizando a senha."
    sudo -u postgres psql -qc "ALTER USER ${ZBX_DB_USER} WITH PASSWORD '${ZBX_DB_PASS}';" >>"$LOG_FILE"
else
    sudo -u postgres psql -qc "CREATE USER ${ZBX_DB_USER} WITH PASSWORD '${ZBX_DB_PASS}';" >>"$LOG_FILE"
fi

if sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='${ZBX_DB_NAME}'" | grep -q 1; then
    warn "Banco ${ZBX_DB_NAME} já existe; mantido."
else
    sudo -u postgres createdb -O "${ZBX_DB_USER}" -E Unicode -T template0 "${ZBX_DB_NAME}"
fi

# -----------------------------------------------------------------------------
# 4. Acesso remoto (somente a partir do servidor da aplicação)
# -----------------------------------------------------------------------------
info "Liberando acesso remoto para ${ZBX_APP_IP}..."
PG_CONF="${PG_CONF_DIR}/postgresql.conf"
PG_HBA="${PG_CONF_DIR}/pg_hba.conf"
cp -n "$PG_CONF" "${PG_CONF}.orig" || true
cp -n "$PG_HBA"  "${PG_HBA}.orig"  || true

# Escuta em todas as interfaces; quem pode conectar é controlado pelo pg_hba.conf
sed -i "s|^#\?\s*listen_addresses\s*=.*|listen_addresses = '*'|" "$PG_CONF"
sed -i "s|^#\?\s*port\s*=.*|port = ${ZBX_DB_PORT}|" "$PG_CONF"
sed -i "s|^#\?\s*password_encryption\s*=.*|password_encryption = scram-sha-256|" "$PG_CONF"

HBA_LINE="host    ${ZBX_DB_NAME}    ${ZBX_DB_USER}    ${ZBX_APP_IP}/32    scram-sha-256"
if ! grep -qF "$HBA_LINE" "$PG_HBA"; then
    printf '\n# Zabbix server\n%s\n' "$HBA_LINE" >> "$PG_HBA"
fi

systemctl restart postgresql

# -----------------------------------------------------------------------------
# 5. Firewall (somente se UFW estiver ativo)
# -----------------------------------------------------------------------------
if command -v ufw >/dev/null && ufw status | grep -q "Status: active"; then
    info "Liberando porta ${ZBX_DB_PORT} no UFW apenas para ${ZBX_APP_IP}..."
    ufw allow from "$ZBX_APP_IP" to any port "$ZBX_DB_PORT" proto tcp >>"$LOG_FILE"
fi

# -----------------------------------------------------------------------------
# 6. Verificação e resumo
# -----------------------------------------------------------------------------
sleep 2
systemctl is-active --quiet postgresql && info "  postgresql: ativo" \
    || warn "  postgresql: INATIVO — verifique: journalctl -u postgresql -n 50"
ss -ltn | grep -q ":${ZBX_DB_PORT} " && info "  escutando na porta ${ZBX_DB_PORT}" \
    || warn "  PostgreSQL não está escutando na porta ${ZBX_DB_PORT}"

IP=$(hostname -I | awk '{print $1}')
cat <<EOF | tee -a "$LOG_FILE"

=====================================================================
 Servidor de banco pronto!

 PostgreSQL : ${PG_MAJOR}  (${IP}:${ZBX_DB_PORT})
 Banco      : ${ZBX_DB_NAME}   Usuário: ${ZBX_DB_USER}
 Acesso     : liberado somente para ${ZBX_APP_IP}
 Log        : ${LOG_FILE}

 Próximo passo, no servidor da aplicação (${ZBX_APP_IP}):
   no .env de lá, use  ZBX_DB_HOST=${IP}  ZBX_DB_PORT=${ZBX_DB_PORT}
   e a MESMA senha (ZBX_DB_PASS); depois rode:
   sudo bash install_zabbix7_app.sh
=====================================================================
EOF
