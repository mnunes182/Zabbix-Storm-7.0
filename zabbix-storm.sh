#!/bin/bash

# Cores
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
WHITE='\033[1;37m'
NC='\033[0m' # Sem cor

# Função para exibir status
status() {
  if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Concluído${NC}\n"
  else
    echo -e "${RED}❌ Falhou${NC}\n"
  fi
}

# Verifica se é root
if [[ "$EUID" -ne 0 ]]; then
  echo -e "${RED}❌ Este script precisa ser executado como root!${NC}"
  exit 1
fi

clear

# ASCII ZABBIX
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
echo -e "${NC}"
echo -e ":: Iniciando instalação do MySQL + Zabbix + Grafana... Aguarde...\n"
echo

# Repositorio Zabbix
echo -e "${YELLOW}📥 Baixando e configurando repositório do Zabbix...${NC}"
wget -q https://repo.zabbix.com/zabbix/7.0/ubuntu/pool/main/z/zabbix-release/zabbix-release_latest_7.0+ubuntu24.04_all.deb &>/dev/null
dpkg -i zabbix-release_latest_7.0+ubuntu24.04_all.deb &>/dev/null
apt update -qq &>/dev/null
status

# Instala Pacotes Zabbix
echo -e "${YELLOW}📦 Instalando pacotes Zabbix...${NC}"
apt install -y zabbix-server-mysql zabbix-frontend-php zabbix-apache-conf zabbix-sql-scripts zabbix-agent &>/dev/null
status

# Instala MySQL
echo -e "${YELLOW}📦 Instalando MySQL Server...${NC}"
apt install -y mysql-server &>/dev/null
status

# Cria DB 
# Alterar a senha do DB - 123456
echo -e "${YELLOW}📦 Criando banco de dados Zabbix...${NC}"
mysql -u root <<EOF &>/dev/null
CREATE DATABASE IF NOT EXISTS zabbix CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;
CREATE USER IF NOT EXISTS 'zabbix'@'localhost' IDENTIFIED BY '123456'; 
GRANT ALL PRIVILEGES ON zabbix.* TO 'zabbix'@'localhost';
SET GLOBAL log_bin_trust_function_creators = 1;
EOF

zcat /usr/share/zabbix/sql-scripts/mysql/server.sql.gz | mysql --default-character-set=utf8mb4 -u zabbix -p 123456 zabbix &>/dev/null
mysql -u root -e "SET GLOBAL log_bin_trust_function_creators = 0;" &>/dev/null
status

# Configuração do Zabbix
echo -e "${YELLOW}📦 Configurando o servidor Zabbix...${NC}"
if [ -f /etc/zabbix/zabbix_server.conf ]; then
  sed -i 's/# DBPassword=/DBPassword=123456/' /etc/zabbix/zabbix_server.conf &>/dev/null
  status
else
  echo -e "${RED}❌ Falhou (arquivo de conf não encontrado)${NC}\n"
fi

# Altera Idioma
echo -e "${YELLOW}📦 Configurando idioma PT-BR...${NC}"
locale-gen pt_BR.UTF-8 &>/dev/null
status

# Instalar Grafana
echo -e "${YELLOW}📦 Instalando Grafana...${NC}"
apt install -y apt-transport-https software-properties-common wget &>/dev/null
mkdir -p /etc/apt/keyrings/
wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor | tee /etc/apt/keyrings/grafana.gpg &>/dev/null
echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" > /etc/apt/sources.list.d/grafana.list
apt update -qq &>/dev/null
apt install -y grafana &>/dev/null
status

# Ativa Serviços
echo -e "${YELLOW}🔁 Ativando e iniciando serviços...${NC}"
systemctl restart zabbix-server zabbix-agent apache2 grafana-server &>/dev/null
systemctl enable zabbix-server zabbix-agent apache2 grafana-server &>/dev/null
status

# Fim
echo -e "${GREEN}🎉 Instalação Finalizada com Sucesso!${NC}\n"

# Links Acesso
IP=$(hostname -I | awk '{print $1}')
echo -e "${WHITE}🔗 Zabbix: ${YELLOW}http://${BLUE}${IP}${YELLOW}/zabbix ${NC}(login: ${BLUE}Admin${NC} / ${BLUE}zabbix${NC})"
echo -e "${WHITE}🔗 Grafana:${YELLOW} http://${BLUE}${IP}${YELLOW}:3000 ${NC}(login: ${BLUE}admin${NC} / ${BLUE}admin${NC})"
echo
echo -e "\e[1;37mScript desenvolvido por: \e[1;92mBUG IT\e[0m"
echo
