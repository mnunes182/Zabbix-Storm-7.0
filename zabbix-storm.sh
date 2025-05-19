#!/bin/bash

##########################################################
# Instalação automática Zabbix + MySQL + Grafana Ubuntu
# Autor: BUG IT (Aprimorado por ChatGPT)
# Compatível: Ubuntu 24.04
##########################################################

# ================================
# --- PARÂMETROS EDITÁVEIS AQUI ---
# ================================
ZABBIX_VERSION="7.0"
UBUNTU_VERSION="24.04"
ZABBIX_DB_NAME="zabbix"
ZABBIX_DB_USER="zabbix"
ZABBIX_DB_PASS="${ZABBIX_DB_PASS:-}"  # Se quiser passar por env, use: export ZABBIX_DB_PASS=suasenha
GRAFANA_PORT=3000
LOCALE="pt_BR.UTF-8"
LOGFILE="/var/log/instalador_zabbix.log"

# ================================
# --- FUNÇÕES DE CORES E STATUS ---
# ================================
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
WHITE='\033[1;37m'
NC='\033[0m' # Sem cor

status() {
  if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Concluído${NC}\n" | tee -a "$LOGFILE"
  else
    echo -e "${RED}❌ Falhou${NC}\n" | tee -a "$LOGFILE"
    exit 1
  fi
}

log() {
  echo -e "$1" | tee -a "$LOGFILE"
}

# ===============================
# --- CHECAGENS DE PRÉ-REQUISITO
# ===============================

# Root
if [[ "$EUID" -ne 0 ]]; then
  echo -e "${RED}❌ Este script precisa ser executado como root!${NC}"
  exit 1
fi

# Ubuntu correto
if ! grep -q "VERSION=\"${UBUNTU_VERSION}\"" /etc/os-release; then
  echo -e "${YELLOW}⚠️  Este script foi testado apenas no Ubuntu ${UBUNTU_VERSION}${NC}"
  echo -e "${YELLOW}    Se prosseguir, pode não funcionar!${NC}"
  read -p "Deseja continuar mesmo assim? (s/n): " resp
  [[ "$resp" =~ ^[Ss] ]] || exit 1
fi

# Senha segura para o banco
if [ -z "$ZABBIX_DB_PASS" ]; then
  read -s -p "Digite uma senha segura para o banco do Zabbix: " ZABBIX_DB_PASS
  echo
  if [ ${#ZABBIX_DB_PASS} -lt 8 ]; then
    echo -e "${RED}Senha fraca! Use ao menos 8 caracteres.${NC}"
    exit 1
  fi
fi

# Limpa tela e arquivo de log
clear
echo "" > "$LOGFILE"

# ================================
# --- BANNER E INÍCIO ---
# ================================
echo -e "${RED}"
cat << "EOF"
 ######     ##     #####    #####     ####    ##  ##             ####    ######    ####    #####    ##   ##
     ##    ####    ##  ##   ##  ##     ##     ##  ##            ##  ##     ##     ##  ##   ##  ##   ### ###
    ##    ##  ##   ##  ##   ##  ##     ##       ###             ##         ##     ##  ##   ##  ##   #######
   ##     ######   #####    #####      ##       ##               ####      ##     ##  ##   #####    ## # ##
  ##      ##  ##   ##  ##   ##  ##     ##      ####                 ##     ##     ##  ##   ####     ##   ##
 ##       ##  ##   ##  ##   ##  ##     ##     ##  ##            ##  ##     ##     ##  ##   ## ##    ##   ##
 ######   ##  ##   #####    #####     ####    ##  ##             ####      ##      ####    ##  ##   ##   ##
EOF
echo -e "${NC}"
log "${NC}\n:: Iniciando instalação do MySQL + Zabbix + Grafana... Aguarde...\n"

# ================================
# --- REPOSITÓRIO ZABBIX ---
# ================================
log "${YELLOW}📥 Baixando e configurando repositório do Zabbix...${NC}"
wget -q "https://repo.zabbix.com/zabbix/${ZABBIX_VERSION}/ubuntu/pool/main/z/zabbix-release/zabbix-release_latest_${ZABBIX_VERSION}+ubuntu${UBUNTU_VERSION}_all.deb" \
  -O "zabbix-release_latest_${ZABBIX_VERSION}+ubuntu${UBUNTU_VERSION}_all.deb"
dpkg -i "zabbix-release_latest_${ZABBIX_VERSION}+ubuntu${UBUNTU_VERSION}_all.deb" &>>"$LOGFILE"
apt update -qq &>>"$LOGFILE"
status

# ================================
# --- INSTALA PACOTES ZABBIX ---
# ================================
log "${YELLOW}📦 Instalando pacotes Zabbix...${NC}"
apt install -y zabbix-server-mysql zabbix-frontend-php zabbix-apache-conf zabbix-sql-scripts zabbix-agent &>>"$LOGFILE"
status

# ================================
# --- INSTALA MYSQL ---
# ================================
log "${YELLOW}📦 Instalando MySQL Server...${NC}"
apt install -y mysql-server &>>"$LOGFILE"
status

# ================================
# --- CRIAÇÃO DO BANCO ZABBIX ---
# ================================
log "${YELLOW}📦 Criando banco de dados Zabbix...${NC}"
mysql -u root <<EOF &>>"$LOGFILE"
CREATE DATABASE IF NOT EXISTS ${ZABBIX_DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;
CREATE USER IF NOT EXISTS '${ZABBIX_DB_USER}'@'localhost' IDENTIFIED BY '${ZABBIX_DB_PASS}';
GRANT ALL PRIVILEGES ON ${ZABBIX_DB_NAME}.* TO '${ZABBIX_DB_USER}'@'localhost';
SET GLOBAL log_bin_trust_function_creators = 1;
EOF
status

# Importa schema Zabbix (correção do -p)
log "${YELLOW}📦 Importando schema inicial...${NC}"
zcat /usr/share/zabbix/sql-scripts/mysql/server.sql.gz | \
  mysql --default-character-set=utf8mb4 -u"${ZABBIX_DB_USER}" -p"${ZABBIX_DB_PASS}" "${ZABBIX_DB_NAME}" &>>"$LOGFILE"
mysql -u root -e "SET GLOBAL log_bin_trust_function_creators = 0;" &>>"$LOGFILE"
status

# ================================
# --- CONFIG ZABBIX SERVER ---
# ================================
log "${YELLOW}📦 Configurando o servidor Zabbix...${NC}"
if [ -f /etc/zabbix/zabbix_server.conf ]; then
  sed -i "s|^# DBPassword=.*|DBPassword=${ZABBIX_DB_PASS}|" /etc/zabbix/zabbix_server.conf
  # Se não existir, adiciona
  grep -q "^DBPassword=" /etc/zabbix/zabbix_server.conf || echo "DBPassword=${ZABBIX_DB_PASS}" >> /etc/zabbix/zabbix_server.conf
  status
else
  log "${RED}❌ Falhou (arquivo de conf não encontrado)${NC}\n"
  exit 1
fi

# ================================
# --- LOCALE PT-BR ---
# ================================
log "${YELLOW}📦 Configurando idioma PT-BR...${NC}"
locale-gen "${LOCALE}" &>>"$LOGFILE"
status

# ================================
# --- INSTALAÇÃO DO GRAFANA ---
# ================================
log "${YELLOW}📦 Instalando Grafana...${NC}"
apt install -y apt-transport-https software-properties-common wget gpg &>>"$LOGFILE"
mkdir -p /etc/apt/keyrings/
wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor > /etc/apt/keyrings/grafana.gpg
echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" > /etc/apt/sources.list.d/grafana.list
apt update -qq &>>"$LOGFILE"
apt install -y grafana &>>"$LOGFILE"
status

# ================================
# --- ATIVA E INICIA SERVIÇOS ---
# ================================
log "${YELLOW}🔁 Ativando e iniciando serviços...${NC}"
systemctl restart zabbix-server zabbix-agent apache2 grafana-server &>>"$LOGFILE"
systemctl enable zabbix-server zabbix-agent apache2 grafana-server &>>"$LOGFILE"
status

# ================================
# --- VALIDAÇÃO DE PORTAS ABERTAS
# ================================
log "${YELLOW}🔎 Verificando se as portas estão abertas...${NC}"
for port in 80 $GRAFANA_PORT; do
  if ss -tuln | grep ":$port " &>/dev/null; then
    log "${GREEN}Porta $port aberta!${NC}"
  else
    log "${RED}⚠️  Porta $port não está aberta! Verifique os serviços e firewall.${NC}"
  fi
done

# ================================
# --- FINALIZAÇÃO ---
# ================================
log "${GREEN}🎉 Instalação Finalizada com Sucesso!${NC}\n"

IP=$(hostname -I | awk '{print $1}')
log "${WHITE}🔗 Zabbix: ${YELLOW}http://${BLUE}${IP}${YELLOW}/zabbix ${NC}(login: ${BLUE}Admin${NC} / ${BLUE}zabbix${NC})"
log "${WHITE}🔗 Grafana:${YELLOW} http://${BLUE}${IP}${YELLOW}:${GRAFANA_PORT} ${NC}(login: ${BLUE}admin${NC} / ${BLUE}admin${NC})"
echo
echo -e "\e[1;37mScript desenvolvido por: \e[1;92mBUG IT\e[0m" | tee -a "$LOGFILE"

exit 0
