#!/bin/bash

#############################################################################
# CloudStack 4.20.0.0 (LTS) Installer
# Suporta: Ubuntu 20.xx, 22.04, 24.04
# Baseado no trabalho original de Dewans Nehra (https://dewansnehra.xyz)
#############################################################################

# Verifica se está sendo executado como root
if [ "$EUID" -ne 0 ]; then
  echo "
  ############################################################################# 
  ##         Este script deve ser executado como root ou com sudo            ##   
  ##  Antes de executar o script, mude para o usuário root usando <su>       ##
  #############################################################################
  "
  sleep 3
  exit 1
fi

# Cores para melhorar a visualização
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Cria um log da instalação
LOG_FILE="/var/log/cloudstack-install-$(date +%Y%m%d%H%M%S).log"

# Função para registrar no log
log() {
    echo "$(date +"%Y-%m-%d %H:%M:%S") - $1" | tee -a "$LOG_FILE"
}

# Função para fazer backup de arquivos
backup_file() {
    local file="$1"
    local backup="${file}.bak"
    if [ -f "$file" ]; then
        cp -f "$file" "$backup"
        log "Backup de $file criado"
        rm -f "$file"
    fi
}

# Função para verificar erros
check_error() {
    if [ $? -ne 0 ]; then
        echo -e "${RED}Erro: $1${NC}"
        log "ERRO: $1"
        exit 1
    fi
}

# Função para verificar se o apt está bloqueado
wait_for_apt_lock() {
    local max_wait=300  # Tempo máximo de espera em segundos (5 minutos)
    local wait_time=0
    
    echo -e "${YELLOW}Verificando bloqueio do apt...${NC}"
    
    while fuser /var/lib/dpkg/lock /var/lib/apt/lists/lock /var/cache/apt/archives/lock /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
        if [ $wait_time -ge $max_wait ]; then
            echo -e "${RED}Tempo de espera excedido. Tentando liberar os bloqueios...${NC}"
            log "Tempo de espera pelo apt excedido. Tentando liberar os bloqueios."
            
            # Verifica processos que podem estar bloqueando
            ps aux | grep -i apt
            
            # Tenta matar processos apt que possam estar travados
            echo -e "${YELLOW}Tentando encerrar processos apt que podem estar travados...${NC}"
            for pid in $(pgrep -f apt); do
                echo "Encerrando processo apt $pid"
                kill -9 $pid 2>/dev/null || true
            done
            
            # Remove arquivos de bloqueio se necessário
            echo -e "${YELLOW}Removendo arquivos de bloqueio...${NC}"
            rm -f /var/lib/dpkg/lock /var/lib/apt/lists/lock /var/cache/apt/archives/lock /var/lib/dpkg/lock-frontend 2>/dev/null || true
            
            # Repara pacotes interrompidos
            echo -e "${YELLOW}Reparando pacotes interrompidos...${NC}"
            dpkg --configure -a
            
            return 1
        fi
        
        # Mostra informações sobre os processos que estão segurando o bloqueio
        local lock_pids=$(fuser /var/lib/dpkg/lock-frontend 2>/dev/null)
        if [ -n "$lock_pids" ]; then
            # Remover espaços extras e formatar a lista de PIDs
            lock_pids=$(echo $lock_pids | tr -s ' ' | sed 's/^ //')
            echo -e "${YELLOW}Aguardando bloqueio do apt ser liberado: processo(s) $lock_pids está(ão) usando o apt...${NC}"
            
            # Para cada PID, mostrar o nome do processo (de forma segura)
            for pid in $lock_pids; do
                if ps -p $pid >/dev/null 2>&1; then
                    local process_name=$(ps -p $pid -o comm= 2>/dev/null || echo "desconhecido")
                    echo -e "${YELLOW}  - Processo $pid: $process_name${NC}"
                fi
            done
        else
            echo -e "${YELLOW}Aguardando bloqueio do apt ser liberado...${NC}"
        fi
        
        sleep 5
        wait_time=$((wait_time + 5))
    done
    
    echo -e "${GREEN}Bloqueio do apt liberado.${NC}"
    return 0
}

# Função para verificar conectividade com a internet
check_internet_connection() {
    echo -e "${BLUE}Verificando conexão com a internet...${NC}"
    log "Verificando conexão com a internet"
    
    # Tenta pingar o Google DNS
    if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        echo -e "${GREEN}Conexão com a internet está funcionando.${NC}"
        log "Conexão com a internet está funcionando"
        return 0
    else
        echo -e "${RED}Não foi possível conectar à internet.${NC}"
        log "Não foi possível conectar à internet"
        
        echo -e "${YELLOW}Tentando métodos alternativos de verificação...${NC}"
        # Tenta conectar ao Cloudflare DNS
        if ping -c 1 1.1.1.1 >/dev/null 2>&1; then
            echo -e "${GREEN}Conexão com a internet está funcionando (via Cloudflare DNS).${NC}"
            log "Conexão com a internet está funcionando (via Cloudflare DNS)"
            return 0
        fi
        
        # Tenta conectar a outros servidores populares
        if curl --connect-timeout 5 -s https://www.google.com >/dev/null || curl --connect-timeout 5 -s https://www.cloudstack.org >/dev/null; then
            echo -e "${GREEN}Conexão com a internet está funcionando (via HTTPS).${NC}"
            log "Conexão com a internet está funcionando (via HTTPS)"
            return 0
        fi
        
        echo -e "${RED}Falha na verificação de conectividade com a internet.${NC}"
        echo -e "${YELLOW}Você deseja continuar mesmo sem conectividade com a internet? (s/n)${NC}"
        read -p "Continuar? [n]: " CONTINUE_WITHOUT_INTERNET
        CONTINUE_WITHOUT_INTERNET=${CONTINUE_WITHOUT_INTERNET:-n}
        
        if [[ "$CONTINUE_WITHOUT_INTERNET" =~ ^[Ss]$ ]]; then
            echo -e "${YELLOW}Continuando sem conectividade com a internet. Algumas funcionalidades podem não funcionar corretamente.${NC}"
            log "Usuário optou por continuar sem conectividade com a internet"
            return 0
        else
            echo -e "${RED}Instalação cancelada devido à falta de conectividade com a internet.${NC}"
            log "Instalação cancelada devido à falta de conectividade com a internet"
            exit 1
        fi
    fi
}

# Função para verificar resolução DNS
check_dns_resolution() {
    local domain="$1"
    
    # Primeiro tenta resolver usando getent hosts (que verifica /etc/hosts)
    if getent hosts "$domain" > /dev/null 2>&1; then
        echo -e "${GREEN}Domínio $domain resolvido com sucesso (via /etc/hosts).${NC}"
        log "Domínio $domain resolvido com sucesso (via /etc/hosts)"
        return 0
    fi
    
    # Tenta resolver usando host
    if host "$domain" > /dev/null 2>&1; then
        echo -e "${GREEN}Domínio $domain resolvido com sucesso (via DNS).${NC}"
        log "Domínio $domain resolvido com sucesso (via DNS)"
        return 0
    fi
    
    # Tenta resolver usando dig
    if command -v dig &> /dev/null && dig +short "$domain" > /dev/null 2>&1; then
        echo -e "${GREEN}Domínio $domain resolvido com sucesso (via dig).${NC}"
        log "Domínio $domain resolvido com sucesso (via dig)"
        return 0
    fi
    
    # Tenta resolver usando nslookup
    if command -v nslookup &> /dev/null && nslookup "$domain" > /dev/null 2>&1; then
        echo -e "${GREEN}Domínio $domain resolvido com sucesso (via nslookup).${NC}"
        log "Domínio $domain resolvido com sucesso (via nslookup)"
        return 0
    fi
    
    # Se chegou aqui, não foi possível resolver o domínio
    return 1
}

# Função para adicionar entrada no arquivo hosts
add_to_hosts() {
    local domain="$1"
    local ip="$2"
    
    echo -e "${BLUE}Adicionando $domain ($ip) ao arquivo /etc/hosts...${NC}"
    log "Adicionando $domain ($ip) ao arquivo /etc/hosts"
    
    # Verifica se a entrada já existe
    if grep -q "$domain" /etc/hosts; then
        echo -e "${YELLOW}Entrada para $domain já existe no arquivo hosts. Atualizando...${NC}"
        log "Entrada para $domain já existe no arquivo hosts. Atualizando..."
        sed -i "/$domain/d" /etc/hosts
    fi
    
    # Adiciona a nova entrada
    echo "$ip $domain" >> /etc/hosts
    echo -e "${GREEN}Entrada adicionada com sucesso.${NC}"
    log "Entrada adicionada com sucesso"
}

# Função para executar apt-get de forma segura
safe_apt_get() {
    local max_retries=3
    local retry_count=0
    local command="apt-get $@"
    
    while [ $retry_count -lt $max_retries ]; do
        echo -e "${BLUE}Executando: $command${NC}"
        log "Executando: $command"
        
        # Aguarda a liberação do bloqueio
        wait_for_apt_lock
        
        # Executa o comando
        if $command; then
            return 0
        else
            retry_count=$((retry_count + 1))
            echo -e "${YELLOW}Falha ao executar apt-get. Tentativa $retry_count de $max_retries.${NC}"
            log "Falha ao executar apt-get. Tentativa $retry_count de $max_retries."
            sleep 5
        fi
    done
    
    echo -e "${RED}Falha ao executar apt-get após $max_retries tentativas.${NC}"
    log "Falha ao executar apt-get após $max_retries tentativas."
    return 1
}

# Função para configurar o DNS para usar o Google DNS (8.8.8.8)
configure_dns() {
    echo -e "${BLUE}Configurando DNS para usar Google DNS (8.8.8.8)...${NC}"
    log "Configurando DNS para usar Google DNS (8.8.8.8)"
    
    # Faz backup do resolv.conf atual
    if [ -f /etc/resolv.conf ]; then
        cp /etc/resolv.conf /etc/resolv.conf.bak
        log "Backup do resolv.conf criado em /etc/resolv.conf.bak"
    fi
    
    # Configura o DNS
    echo "nameserver 8.8.8.8" > /etc/resolv.conf
    echo "nameserver 8.8.4.4" >> /etc/resolv.conf
    
    echo -e "${GREEN}DNS configurado com sucesso.${NC}"
    log "DNS configurado com sucesso"
}

# Função para permitir repositórios não autenticados
allow_unauthenticated_repos() {
    echo -e "${YELLOW}Configurando APT para permitir repositórios não autenticados...${NC}"
    log "Configurando APT para permitir repositórios não autenticados"
    
    # Cria o arquivo de configuração para permitir repositórios não autenticados
    echo 'APT::Get::AllowUnauthenticated "true";' > /etc/apt/apt.conf.d/99allow-unauth
    echo 'Acquire::AllowInsecureRepositories "true";' >> /etc/apt/apt.conf.d/99allow-unauth
    echo 'Acquire::AllowDowngradeToInsecureRepositories "true";' >> /etc/apt/apt.conf.d/99allow-unauth
    
    # Adiciona a opção --allow-unauthenticated para apt-get
    APT_OPTIONS="--allow-unauthenticated --allow-insecure-repositories"
    
    echo -e "${GREEN}APT configurado para permitir repositórios não autenticados.${NC}"
    log "APT configurado para permitir repositórios não autenticados"
}

# Função para configurar o fuso horário
configure_timezone() {
    log "Configurando fuso horário"
    
    # Define o hostname
    hostnamectl set-hostname $FULL_HOSTNAME
    
    echo -e "\n${BLUE}=== Configuração de Fuso Horário ===${NC}"
    echo -e "${YELLOW}Selecione o fuso horário:${NC}"
    echo -e "1) America/Sao_Paulo (Recomendado)"
    echo -e "2) America/Recife"
    echo -e "3) America/Fortaleza"
    echo -e "4) America/Maceio"
    echo -e "5) America/Bahia"
    echo -e "6) America/Manaus"
    echo -e "7) America/Cuiaba"
    echo -e "8) America/Campo_Grande"
    read -p "Escolha o fuso horário [1]: " TZ_CHOICE
    TZ_CHOICE=${TZ_CHOICE:-1}
    
    case $TZ_CHOICE in
        1) TIMEZONE="America/Sao_Paulo" ;;
        2) TIMEZONE="America/Recife" ;;
        3) TIMEZONE="America/Fortaleza" ;;
        4) TIMEZONE="America/Maceio" ;;
        5) TIMEZONE="America/Bahia" ;;
        6) TIMEZONE="America/Manaus" ;;
        7) TIMEZONE="America/Cuiaba" ;;
        8) TIMEZONE="America/Campo_Grande" ;;
        *) TIMEZONE="America/Sao_Paulo" ;;
    esac
    
    echo -e "Configurando fuso horário para ${GREEN}$TIMEZONE${NC}"
    timedatectl set-timezone $TIMEZONE
    
    # Verifica se o NTP está ativo
    if ! timedatectl | grep -q "NTP service: active"; then
        echo -e "${YELLOW}Serviço NTP não está ativo. Ativando...${NC}"
        timedatectl set-ntp true
    fi
    
    # Exibe a hora atual
    CURRENT_TIME=$(date)
    echo -e "Hora atual: ${GREEN}$CURRENT_TIME${NC}"
    
    # Verifica se o fuso horário foi configurado corretamente
    CONFIGURED_TZ=$(timedatectl | grep "Time zone" | awk '{print $3}')
    if [ "$CONFIGURED_TZ" != "$TIMEZONE" ]; then
        echo -e "${RED}Falha ao configurar o fuso horário. Configurado: $CONFIGURED_TZ, Esperado: $TIMEZONE${NC}"
        echo -e "${YELLOW}Tentando método alternativo...${NC}"
        
        # Método alternativo
        ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
        
        # Verifica novamente
        CONFIGURED_TZ=$(timedatectl | grep "Time zone" | awk '{print $3}')
        if [ "$CONFIGURED_TZ" != "$TIMEZONE" ]; then
            echo -e "${RED}Falha ao configurar o fuso horário pelo método alternativo.${NC}"
            echo -e "${YELLOW}Por favor, configure manualmente o fuso horário após a instalação.${NC}"
        else
            echo -e "${GREEN}Fuso horário configurado com sucesso pelo método alternativo.${NC}"
        fi
    else
        echo -e "${GREEN}Fuso horário configurado com sucesso.${NC}"
    fi
}

configure_hostname() {
    echo -e "${BLUE}=== Configurando hostname ===${NC}"
    log "Configurando hostname"
    
    # Verifica se o hostname foi configurado corretamente
    if [ -z "$FULL_HOSTNAME" ] || [ "$FULL_HOSTNAME" = "." ]; then
        echo -e "${YELLOW}Hostname não definido. Usando o hostname atual.${NC}"
        log "Hostname não definido. Usando o hostname atual"
        HOSTNAME=$(hostname -s)
        DOMAIN=$(hostname -d)
        if [ -z "$DOMAIN" ]; then
            # Tenta extrair o código do datacenter do hostname atual
            DC_CODE_FROM_HOST=$(echo "$HOSTNAME" | grep -oP '(?<=\-)([a-z]{3})(?=\.)')
            if [ -n "$DC_CODE_FROM_HOST" ]; then
                DOMAIN="${DC_CODE_FROM_HOST}.lideri.cloud"
            else
                DOMAIN="lideri.cloud"
            fi
        fi
        FULL_HOSTNAME="${HOSTNAME}.${DOMAIN}"
    fi
    
    echo -e "Configurando hostname para: ${GREEN}$FULL_HOSTNAME${NC}"
    log "Configurando hostname para: $FULL_HOSTNAME"
    
    # Configura o hostname
    hostnamectl set-hostname "$FULL_HOSTNAME"
    
    # Atualiza o arquivo hosts
    update_hosts
    
    echo -e "Hostname configurado com sucesso para: ${GREEN}$FULL_HOSTNAME${NC}"
    log "Hostname configurado com sucesso para: $FULL_HOSTNAME"
    
    return 0
}

configure_hostname

configure_timezone

# Banner
echo -e "
${BLUE} ██████╗██╗      ██████╗ ██╗   ██╗██████╗ ███████╗████████╗ █████╗  ██████╗██╗  ██╗${NC}
${BLUE}██╔════╝██║     ██╔═══██╗██║   ██║██╔══██╗██╔════╝╚══██╔══╝██╔══██╗██╔════╝██║ ██╔╝${NC}
${BLUE}██║     ██║     ██║   ██║██║   ██║██║  ██║███████╗   ██║   ███████║██║     █████╔╝ ${NC}
${BLUE}██║     ██║     ██║   ██║██║   ██║██║  ██║╚════██║   ██║   ██╔══██║██║     ██╔═██╗ ${NC}
${BLUE}╚██████╗███████╗╚██████╔╝╚██████╔╝██████╔╝███████║   ██║   ██║  ██║╚██████╗██║  ██╗${NC}
${BLUE} ╚═════╝╚══════╝ ╚═════╝  ╚═════╝ ╚═════╝ ╚══════╝   ╚═╝   ╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝${NC}
${GREEN}                                                                 v4.20.0.0 (LTS)${NC}
"

echo -e "\n${BLUE}=== Instalador CloudStack 4.20.0.0 ===${NC}"
echo -e "${YELLOW}Suporta: Ubuntu 20.xx, 22.04, 24.04${NC}"
echo -e "${YELLOW}Baseado no trabalho original de Dewans Nehra (https://dewansnehra.xyz)${NC}\n"

# Detecta o sistema operacional
OS_TYPE=$(lsb_release -is)
OS_VERSION=$(lsb_release -rs)
OS_CODENAME=$(lsb_release -cs)

echo -e "${BLUE}Sistema detectado: ${NC}${GREEN}$OS_TYPE $OS_VERSION ($OS_CODENAME)${NC}"

# Verifica se é Ubuntu
if [ "$OS_TYPE" != "Ubuntu" ]; then
    echo -e "${RED}Este script é compatível apenas com Ubuntu.${NC}"
    echo -e "${RED}Sistema detectado: $OS_TYPE $OS_VERSION${NC}"
    exit 1
fi

# Verifica se os pacotes necessários estão instalados
echo -e "\n${BLUE}=== Verificando dependências iniciais ===${NC}"
if ! command -v bc &> /dev/null; then
    echo -e "${YELLOW}Instalando bc...${NC}"
    safe_apt_get install -y bc
    check_error "Falha ao instalar bc"
fi

if ! command -v lsb_release &> /dev/null; then
    echo -e "${YELLOW}Instalando lsb-release...${NC}"
    safe_apt_get install -y lsb-release
    check_error "Falha ao instalar lsb-release"
fi

# Função para detectar a interface de rede principal
detect_network_interface() {
    log "Detectando interface de rede"
    
    # Tenta encontrar a interface com a rota padrão
    IFACE=$(ip -o -4 route show to default | awk '{print $5}' | head -n 1)
    
    # Se não encontrar, tenta detectar interfaces ativas
    if [ -z "$IFACE" ]; then
        echo -e "${YELLOW}Interface de rede não encontrada. Tentando detectar...${NC}"
        log "Interface de rede não encontrada. Tentando detectar..."
        
        # Lista de possíveis nomes de interfaces
        POSSIBLE_IFACES=$(ip -o -4 addr | awk '{print $2}' | grep -v "lo" | cut -d':' -f1)
        
        # Tenta encontrar a primeira interface ativa
        for iface in $POSSIBLE_IFACES; do
            if ip link show $iface | grep -q 'state UP'; then
                IFACE=$iface
                break
            fi
        done
    fi
    
    # Se ainda não encontrar, pega a primeira interface que não seja loopback
    if [ -z "$IFACE" ]; then
        IFACE=$(ip -o -4 addr | awk '{print $2}' | grep -v "lo" | head -n 1 | cut -d':' -f1)
    fi
    
    # Verifica se encontrou uma interface
    if [ -z "$IFACE" ]; then
        echo -e "${RED}Não foi possível detectar a interface de rede. Por favor, especifique manualmente.${NC}"
        log "Não foi possível detectar a interface de rede"
        read -p "Nome da interface de rede (ex: eth0, ens3, eno1): " IFACE
        
        if [ -z "$IFACE" ]; then
            echo -e "${RED}Nenhuma interface especificada. Não é possível configurar a rede.${NC}"
            log "Nenhuma interface especificada. Não é possível configurar a rede"
            return 1
        fi
    fi
    
    echo -e "${BLUE}Interface de rede detectada: $IFACE${NC}"
    log "Interface de rede detectada: $IFACE"
    
    return 0
}

# Detecta a interface de rede no início do script
NETWORK_INTERFACE=$(detect_network_interface)
log "Interface de rede detectada: $NETWORK_INTERFACE"

# Configurações de rede
echo -e "\n${BLUE}=== Detectando configurações de rede ===${NC}"
GATEWAY=$(ip r | awk '/default/ {print $3}')
IP=$(ip -o -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v "127.0.0.1" | head -n1)
ADAPTER=$NETWORK_INTERFACE

echo -e "IP: ${GREEN}$IP${NC}"
echo -e "Gateway: ${GREEN}$GATEWAY${NC}"
echo -e "Adaptador: ${GREEN}$ADAPTER${NC}"

# Configurações do Datacenter e Rack (Lideri.cloud)
echo -e "\n${BLUE}=== Configurações de Datacenter e Rack (Lideri.cloud) ===${NC}"
echo -e "${YELLOW}Selecione o datacenter:${NC}"
echo -e "1) Olinda (OLI) - 10.128.0.0/16"
echo -e "2) Igarassu (IGA) - 10.129.0.0/16"
echo -e "3) João Pessoa (JPA) - 10.130.0.0/16"
echo -e "4) Recife (REC) - 10.131.0.0/16"
echo -e "5) São Paulo (SPO) - 10.132.0.0/16"
echo -e "6) Hostinger SP (HSP) - 10.133.0.0/16"
read -p "Escolha o datacenter [1]: " DC_CHOICE
DC_CHOICE=${DC_CHOICE:-1}

# Garante que DC_CHOICE seja um número válido
if ! [[ "$DC_CHOICE" =~ ^[1-6]$ ]]; then
    echo -e "${YELLOW}Opção inválida. Usando o padrão (Olinda).${NC}"
    DC_CHOICE=1
fi

case $DC_CHOICE in
    1) DC_NAME="Olinda"; DC_CODE="oli"; DC_OCTET=128 ;;
    2) DC_NAME="Igarassu"; DC_CODE="iga"; DC_OCTET=129 ;;
    3) DC_NAME="João Pessoa"; DC_CODE="jpa"; DC_OCTET=130 ;;
    4) DC_NAME="Recife"; DC_CODE="rec"; DC_OCTET=131 ;;
    5) DC_NAME="São Paulo"; DC_CODE="spo"; DC_OCTET=132 ;;
    6) DC_NAME="Hostinger SP"; DC_CODE="hsp"; DC_OCTET=133 ;;
    *) DC_NAME="Olinda"; DC_CODE="oli"; DC_OCTET=128 ;;
esac

echo -e "Datacenter selecionado: ${GREEN}$DC_NAME ($DC_CODE)${NC}"

# Seleciona o Rack
echo -e "${YELLOW}Selecione o rack:${NC}"
echo -e "1) Rack 01 (r01)"
echo -e "2) Rack 02 (r02)"
echo -e "3) Rack 03 (r03)"
echo -e "4) Rack 04 (r04)"
echo -e "5) Rack 05 (r05)"
read -p "Escolha o rack [1]: " RACK_CHOICE
RACK_CHOICE=${RACK_CHOICE:-1}

# Garante que RACK_CHOICE seja um número válido
if ! [[ "$RACK_CHOICE" =~ ^[1-5]$ ]]; then
    echo -e "${YELLOW}Opção inválida. Usando o padrão (r01).${NC}"
    RACK_CHOICE=1
fi

case $RACK_CHOICE in
    1) RACK_NUM="01"; RACK_NAME="r01" ;;
    2) RACK_NUM="02"; RACK_NAME="r02" ;;
    3) RACK_NUM="03"; RACK_NAME="r03" ;;
    4) RACK_NUM="04"; RACK_NAME="r04" ;;
    5) RACK_NUM="05"; RACK_NAME="r05" ;;
    *) RACK_NUM="01"; RACK_NAME="r01" ;;
esac

# Seleciona o Host
read -p "Número do Host (01-16) [01]: " HOST_NUM
HOST_NUM=${HOST_NUM:-01}

# Garante que HOST_NUM seja um número válido
if ! [[ "$HOST_NUM" =~ ^[0-9]+$ ]] || [ "$HOST_NUM" -lt 1 ] || [ "$HOST_NUM" -gt 16 ]; then
    echo -e "${YELLOW}Número de host inválido. Usando o padrão (01).${NC}"
    HOST_NUM=01
fi

HOST_NUM=$(printf "%02d" $((10#${HOST_NUM})))

# Gera o nome do host conforme padrão <rack>-<host>.<dc>.lideri.cloud
HOSTNAME="${RACK_NAME}-h${HOST_NUM}"
echo -e "Nome do Host: ${GREEN}$HOSTNAME${NC}"

# Define o domínio conforme o datacenter
DOMAIN="${DC_CODE}.lideri.cloud"

FULL_HOSTNAME="${HOSTNAME}.${DOMAIN}"
SHORT_HOSTNAME="${HOSTNAME}"

echo -e "Nome completo do host: ${GREEN}$FULL_HOSTNAME${NC}"

# Calcula o IP com base nas regras da Lideri.cloud
# Para hosts, usamos a rede .1.0/24 conforme as regras
# Hosts começam em .11 e vão até .254
HOST_IP_OCTET=$((10 + 10#${HOST_NUM}))

# Calcula os IPs para a rede do servidor conforme regra_nomes.md
IP_NETWORK="10.$DC_OCTET.1.0/24"
IP_SERVER="10.$DC_OCTET.1.$HOST_IP_OCTET"
IP_GATEWAY="10.$DC_OCTET.1.1"
IP_DNS1="10.$DC_OCTET.1.2"  # DNS Anycast primário
IP_DNS2="10.$DC_OCTET.1.3"  # DNS Anycast secundário

# IP de gerenciamento (iDRAC/iLO) na rede Management
MGMT_IP="10.$DC_OCTET.0.$HOST_IP_OCTET"

echo -e "IP do Servidor: ${GREEN}$IP_SERVER${NC}"
echo -e "IP de Gerenciamento: ${GREEN}$MGMT_IP${NC}"

# Configurações do MySQL
echo -e "\n${BLUE}=== Configurações do MySQL ===${NC}"
echo -e "${YELLOW}Deixe em branco para usar os valores padrão${NC}"

read -p "Usuário MySQL para CloudStack [cloud]: " MYSQL_USER
MYSQL_USER=${MYSQL_USER:-cloud}

read -p "Senha MySQL para CloudStack [cloud]: " MYSQL_PASSWORD
MYSQL_PASSWORD=${MYSQL_PASSWORD:-cloud}

read -p "Senha root MySQL [cloudstack]: " MYSQL_ROOT_PASSWORD
MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD:-cloudstack}

# Confirma as configurações
echo -e "\n${BLUE}=== Resumo da Instalação ===${NC}"
echo -e "Sistema: ${GREEN}$OS_TYPE $OS_VERSION${NC}"
echo -e "Datacenter: ${GREEN}$DC_NAME ($DC_CODE)${NC}"
echo -e "Rack: ${GREEN}$RACK_NAME${NC}"
echo -e "Host: ${GREEN}$FULL_HOSTNAME${NC}"
echo -e "Rede: ${GREEN}$IP_NETWORK${NC}"
echo -e "IP do Servidor: ${GREEN}$IP_SERVER${NC}"
echo -e "Gateway: ${GREEN}$IP_GATEWAY${NC}"
echo -e "DNS Primário (Anycast): ${GREEN}$IP_DNS1${NC}"
echo -e "DNS Secundário (Anycast): ${GREEN}$IP_DNS2${NC}"
echo -e "IP de Gerenciamento (iDRAC/iLO): ${GREEN}$MGMT_IP${NC}"
echo -e "Usuário MySQL: ${GREEN}$MYSQL_USER${NC}"
echo -e "CloudStack: ${GREEN}4.20.0.0 (LTS)${NC}"

read -p "Confirma estas configurações? (s/n): " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Ss]$ ]]; then
    echo -e "${RED}Instalação cancelada pelo usuário.${NC}"
    exit 0
fi

# Cria um log da instalação
LOG_FILE="/var/log/cloudstack-install-$(date +%Y%m%d%H%M%S).log"
echo -e "\n${BLUE}=== Log da instalação será salvo em: ${GREEN}$LOG_FILE${NC} ===${NC}"

# Função para registrar no log
log() {
    echo "$(date +"%Y-%m-%d %H:%M:%S") - $1" | tee -a "$LOG_FILE"
}

# Atualiza o sistema
echo -e "\n${BLUE}=== Atualizando o sistema ===${NC}"
log "Iniciando atualização do sistema"
safe_apt_get update
check_error "Falha ao atualizar o sistema"
safe_apt_get -y upgrade
check_error "Falha ao atualizar pacotes"
log "Sistema atualizado com sucesso"

# Instala pacotes básicos
echo -e "\n${BLUE}=== Instalando pacotes básicos ===${NC}"
log "Instalando pacotes básicos"
safe_apt_get install -y openntpd openssh-server sudo vim htop tar intel-microcode bridge-utils gnupg2 apt-transport-https ca-certificates curl
check_error "Falha ao instalar pacotes básicos"
log "Pacotes básicos instalados com sucesso"

# Configura a rede
echo -e "\n${BLUE}=== Configurando rede ===${NC}"
log "Configurando rede"

configure_network() {
    log "Configurando rede"
    
    # Verifica se o Netplan está instalado
    if ! command -v netplan &> /dev/null; then
        echo -e "${YELLOW}Netplan não encontrado. Instalando...${NC}"
        log "Netplan não encontrado. Instalando..."
        safe_apt_get install -y netplan.io
    fi
    
    # Determina o nome da interface de rede principal
    IFACE=$(ip -o -4 route show to default | awk '{print $5}' | head -n 1)
    if [ -z "$IFACE" ]; then
        echo -e "${YELLOW}Interface de rede não encontrada. Tentando detectar...${NC}"
        log "Interface de rede não encontrada. Tentando detectar..."
        IFACE=$(ip -o -4 addr | awk '{print $2}' | grep -v "lo" | head -n 1 | cut -d':' -f1)
        
        if [ -z "$IFACE" ]; then
            echo -e "${RED}Não foi possível detectar a interface de rede. Por favor, especifique manualmente.${NC}"
            log "Não foi possível detectar a interface de rede"
            read -p "Nome da interface de rede (ex: eth0, ens3): " IFACE
            
            if [ -z "$IFACE" ]; then
                echo -e "${RED}Nenhuma interface especificada. Não é possível configurar a rede.${NC}"
                log "Nenhuma interface especificada. Não é possível configurar a rede"
                return 1
            fi
        fi
    fi
    
    echo -e "${BLUE}Interface de rede detectada: $IFACE${NC}"
    log "Interface de rede detectada: $IFACE"
    
    # Verifica se a interface de rede está ativa
    if ! ip link show $IFACE | grep -q 'state UP'; then
        echo -e "${RED}A interface de rede $IFACE não está ativa.${NC}"
        log "A interface de rede $IFACE não está ativa"
        return 1
    fi


    # Cria o arquivo de configuração do Netplan
    local netplan_file="/etc/netplan/01-cloudstack-config.yaml"
    
    # Faz backup do arquivo existente, se houver
    if [ -f "$netplan_file" ]; then
        cp "$netplan_file" "${netplan_file}.bak.$(date +%Y%m%d%H%M%S)"
        log "Backup do arquivo de configuração do Netplan criado"
    fi
    
    # Cria o arquivo de configuração do Netplan com bridge cloudbr0
    cat > "$netplan_file" << EOF
# Configuração de rede para CloudStack
# Gerado automaticamente por cloudstack-installer.sh
network:
  version: 2
  renderer: networkd
  ethernets:
    eno1:
      dhcp4: no
      dhcp6: no
  bridges:
    cloudbr0:
      interfaces: [eno1]
      addresses: [$IP_SERVER/24]
      routes:
        - to: default
          via: $IP_GATEWAY
      nameservers:
        addresses: [186.208.0.1, 8.8.8.8]
      parameters:
        stp: false
        forward-delay: 0
      dhcp4: no
      dhcp6: no
EOF

    # Adiciona comentário sobre VLANs conforme o datacenter
    case $DC_CODE in
        oli)
            echo "      # VLANs para Olinda: 3001-3025" >> "$netplan_file"
            ;;
        iga)
            echo "      # VLANs para Igarassu: 3026-3050" >> "$netplan_file"
            ;;
        jpa)
            echo "      # VLANs para João Pessoa: 3051-3075" >> "$netplan_file"
            ;;
        rec)
            echo "      # VLANs para Recife: 3076-3100" >> "$netplan_file"
            ;;
        spo)
            echo "      # VLANs para São Paulo: 3101-3125" >> "$netplan_file"
            ;;
        hsp)
            echo "      # VLANs para Hostinger SP: 3126-3150" >> "$netplan_file"
            ;;
    esac
    
    # Define as permissões corretas para o arquivo de configuração
    chmod 600 "$netplan_file"
    
    echo -e "${BLUE}Aplicando configuração de rede...${NC}"
    log "Aplicando configuração de rede"
    
    # Aviso sobre possível perda de conectividade
    echo -e "${YELLOW}AVISO: A aplicação desta configuração pode causar perda temporária de conectividade.${NC}"
    echo -e "${YELLOW}Se você estiver conectado remotamente, certifique-se de ter acesso alternativo ao servidor.${NC}"
    read -p "Deseja aplicar a configuração agora? (s/n): " APPLY_NOW
    
    if [[ "$APPLY_NOW" =~ ^[Ss]$ ]]; then
        # Aplica a configuração
        if ! netplan apply; then
            echo -e "${RED}Falha ao aplicar configuração de rede. Verifique o arquivo $netplan_file${NC}"
            log "Falha ao aplicar configuração de rede"
            return 1
        fi
        
        echo -e "${GREEN}Configuração de rede aplicada com sucesso.${NC}"
        log "Configuração de rede aplicada com sucesso"
    else
        echo -e "${YELLOW}A configuração de rede foi salva, mas não foi aplicada.${NC}"
        echo -e "${YELLOW}Para aplicá-la manualmente, execute: sudo netplan apply${NC}"
        log "Configuração de rede salva, mas não aplicada"
    fi
    
    # Corrige as permissões de todos os arquivos do Netplan
    fix_netplan_permissions
    
    return 0
}

configure_network

# Verifica o status dos serviços
echo -e "\n${BLUE}=== Status dos Serviços ===${NC}"
log "Verificando status dos serviços"
systemctl status mysql --no-pager
systemctl status cloudstack-management --no-pager
systemctl status cloudstack-usage --no-pager
systemctl status nfs-kernel-server --no-pager

echo -e "\n${GREEN}=== Instalação do CloudStack 4.20.0.0 concluída! ===${NC}"
log "Processo de instalação finalizado"

# Função para limpar repositórios CloudStack antigos
clean_old_cloudstack_repos() {
    echo -e "${BLUE}Limpando repositórios CloudStack antigos...${NC}"
    log "Limpando repositórios CloudStack antigos"
    
    # Remove entradas antigas do CloudStack do sources.list
    if [ -f /etc/apt/sources.list ]; then
        echo -e "${BLUE}Verificando e removendo entradas do CloudStack em /etc/apt/sources.list...${NC}"
        log "Verificando e removendo entradas do CloudStack em /etc/apt/sources.list"
        
        # Faz backup do arquivo original
        cp /etc/apt/sources.list /etc/apt/sources.list.bak
        log "Backup do sources.list criado em /etc/apt/sources.list.bak"
        
        # Remove linhas contendo "cloudstack" ou "download.cloudstack.org"
        sed -i '/cloudstack\|download\.cloudstack\.org/d' /etc/apt/sources.list
    fi
    
    # Remove arquivos de repositório CloudStack antigos
    echo -e "${BLUE}Removendo arquivos de repositório CloudStack antigos...${NC}"
    log "Removendo arquivos de repositório CloudStack antigos"
    
    # Lista de possíveis arquivos de repositório CloudStack
    local repo_files=(
        "/etc/apt/sources.list.d/cloudstack.list"
        "/etc/apt/sources.list.d/cloudstack-repo.list"
        "/etc/apt/sources.list.d/cloudstack-stable.list"
        "/etc/apt/sources.list.d/cloudstack-testing.list"
    )
    
    # Remove cada arquivo se existir
    for file in "${repo_files[@]}"; do
        if [ -f "$file" ]; then
            echo -e "${BLUE}Removendo $file...${NC}"
            log "Removendo $file"
            rm -f "$file"
        fi
    done
    
    # Remove chaves GPG antigas
    echo -e "${BLUE}Removendo chaves GPG antigas do CloudStack...${NC}"
    log "Removendo chaves GPG antigas do CloudStack"
    
    # Remove usando apt-key (método antigo)
    apt-key del "3D62B837F100E758" 2>/dev/null || true
    
    # Lista de possíveis arquivos de chave GPG
    local gpg_files=(
        "/etc/apt/trusted.gpg.d/cloudstack.gpg"
        "/etc/apt/trusted.gpg.d/cloudstack-archive-keyring.gpg"
        "/etc/apt/keyrings/cloudstack.gpg"
        "/etc/apt/keyrings/cloudstack-archive-keyring.gpg"
    )
    
    # Remove cada arquivo se existir
    for file in "${gpg_files[@]}"; do
        if [ -f "$file" ]; then
            echo -e "${BLUE}Removendo $file...${NC}"
            log "Removendo $file"
            rm -f "$file"
        fi
    done
    
    echo -e "${GREEN}Limpeza de repositórios CloudStack antigos concluída.${NC}"
    log "Limpeza de repositórios CloudStack antigos concluída"
    
    return 0
}

# Função para adicionar o repositório CloudStack
add_cloudstack_repo() {
    local ubuntu_version=$1
    
    echo -e "${BLUE}Configurando repositório CloudStack para $ubuntu_version${NC}"
    log "Configurando repositório CloudStack para $ubuntu_version"
    
    # Limpa repositórios antigos do CloudStack
    clean_old_cloudstack_repos
    
    # Configura DNS para usar Google DNS
    echo -e "${BLUE}Configurando DNS para usar Google DNS (8.8.8.8)${NC}"
    log "Configurando DNS para usar Google DNS (8.8.8.8)"
    
    # Faz backup do resolv.conf
    cp /etc/resolv.conf /etc/resolv.conf.bak
    log "Backup do resolv.conf criado em /etc/resolv.conf.bak"
    
    # Configura DNS
    echo "nameserver 8.8.8.8" > /etc/resolv.conf
    echo "nameserver 8.8.4.4" >> /etc/resolv.conf
    
    echo -e "${GREEN}DNS configurado com sucesso.${NC}"
    log "DNS configurado com sucesso"
    
    # Verifica conectividade com a internet
    echo -e "${BLUE}Verificando conectividade com a internet...${NC}"
    log "Verificando conectividade com a internet"
    check_internet_connection
    
    # Verifica resolução DNS para download.cloudstack.org
    echo -e "${BLUE}Verificando resolução DNS para download.cloudstack.org...${NC}"
    log "Verificando resolução DNS para download.cloudstack.org"
    
    # Tenta resolver o domínio download.cloudstack.org
    if ! check_dns_resolution "download.cloudstack.org"; then
        echo -e "${YELLOW}Não foi possível resolver o domínio download.cloudstack.org.${NC}"
        log "Não foi possível resolver o domínio download.cloudstack.org"
        
        read -p "Deseja continuar mesmo sem resolução DNS para download.cloudstack.org? (s/n) " -n 1 -r
        echo
        
        if [[ ! $REPLY =~ ^[Ss]$ ]]; then
            echo -e "${RED}Instalação cancelada devido à falta de resolução DNS para download.cloudstack.org.${NC}"
            log "Instalação cancelada devido à falta de resolução DNS para download.cloudstack.org"
            exit 1
        else
            echo -e "${YELLOW}Continuando sem resolução DNS para download.cloudstack.org. Algumas funcionalidades podem não funcionar corretamente.${NC}"
            log "Usuário optou por continuar sem resolução DNS para download.cloudstack.org"
        fi
    fi
    
    # Instala dependências necessárias
    echo -e "${BLUE}Instalando dependências necessárias...${NC}"
    log "Instalando dependências necessárias"
    
    if ! safe_apt_get install -y apt-transport-https ca-certificates gnupg2; then
        echo -e "${YELLOW}Falha ao instalar dependências. Tentando continuar mesmo assim...${NC}"
        log "Falha ao instalar dependências. Tentando continuar mesmo assim"
    fi
    
    # Cria diretório para chaves GPG se não existir
    if [ ! -d /etc/apt/keyrings ]; then
        echo -e "${BLUE}Criando diretório /etc/apt/keyrings...${NC}"
        log "Criando diretório /etc/apt/keyrings"
        mkdir -p /etc/apt/keyrings
        chmod 755 /etc/apt/keyrings
    fi
    
    # Baixa e adiciona a chave GPG
    echo -e "${BLUE}Baixando e adicionando chave GPG do CloudStack...${NC}"
    log "Baixando e adicionando chave GPG do CloudStack"
    
    # Define a URL da chave GPG
    local gpg_key_url="https://download.cloudstack.org/release.asc"
    local gpg_key_file="/etc/apt/trusted.gpg.d/cloudstack.asc"
    
    # Tenta baixar a chave GPG
    echo -e "${BLUE}Tentando baixar a chave GPG oficial do Apache CloudStack...${NC}"
    log "Tentando baixar a chave GPG oficial do Apache CloudStack"
    if wget -O- "$gpg_key_url" > "$gpg_key_file" 2>/dev/null; then
        echo -e "${GREEN}Chave GPG baixada e instalada com sucesso.${NC}"
        log "Chave GPG baixada e instalada com sucesso"
        chmod 644 "$gpg_key_file"
    else
        echo -e "${YELLOW}Falha ao baixar a chave GPG usando wget. Tentando com curl...${NC}"
        log "Falha ao baixar a chave GPG usando wget. Tentando com curl"
        
        if curl -fsSL "$gpg_key_url" > "$gpg_key_file" 2>/dev/null; then
            echo -e "${GREEN}Chave GPG baixada e instalada com sucesso usando curl.${NC}"
            log "Chave GPG baixada e instalada com sucesso usando curl"
            chmod 644 "$gpg_key_file"
        else
            echo -e "${YELLOW}Falha ao baixar a chave GPG com curl. Tentando método alternativo...${NC}"
            log "Falha ao baixar a chave GPG com curl. Tentando método alternativo"
            
            # Método alternativo: usar apt-key (obsoleto, mas pode funcionar como fallback)
            if wget -O- "$gpg_key_url" | apt-key add - 2>/dev/null; then
                echo -e "${GREEN}Chave GPG adicionada com sucesso usando apt-key.${NC}"
                log "Chave GPG adicionada com sucesso usando apt-key"
            else
                echo -e "${RED}Falha ao adicionar a chave GPG. Continuando sem a chave...${NC}"
                log "Falha ao adicionar a chave GPG. Continuando sem a chave"
                USE_TRUSTED_YES=true
            fi
        fi
    fi
    
    # Adiciona o repositório CloudStack
    echo -e "${BLUE}Adicionando repositório CloudStack...${NC}"
    log "Adicionando repositório CloudStack"
    
    # Define a URL do repositório conforme a documentação oficial
    local repo_url="https://download.cloudstack.org/ubuntu"
    local repo_line="deb $repo_url $ubuntu_version 4.20"
    
    # Escreve a configuração do repositório
    echo "$repo_line" > /etc/apt/sources.list.d/cloudstack.list
    
    echo -e "${GREEN}Repositório CloudStack adicionado com sucesso.${NC}"
    log "Repositório CloudStack adicionado com sucesso"
    
    # Atualiza os repositórios
    echo -e "${BLUE}Atualizando repositórios...${NC}"
    log "Atualizando repositórios"
    
    if ! safe_apt_get update; then
        echo -e "${YELLOW}Falha ao atualizar repositórios. Tentando método alternativo...${NC}"
        log "Falha ao atualizar repositórios. Tentando método alternativo."
        
        # Tenta atualizar ignorando erros de assinatura
        if ! safe_apt_get update --allow-unauthenticated; then
            echo -e "${RED}Falha ao atualizar repositórios mesmo com --allow-unauthenticated.${NC}"
            log "Falha ao atualizar repositórios mesmo com --allow-unauthenticated"
            
            # Pergunta ao usuário se deseja continuar
            read -p "Falha ao atualizar repositórios. Deseja continuar mesmo assim? (s/n) " -n 1 -r
            echo
            
            if [[ ! $REPLY =~ ^[Ss]$ ]]; then
                echo -e "${RED}Instalação cancelada pelo usuário.${NC}"
                log "Instalação cancelada pelo usuário após falha ao atualizar repositórios"
                exit 1
            else
                echo -e "${YELLOW}Continuando mesmo com falha ao atualizar repositórios.${NC}"
                log "Usuário optou por continuar mesmo com falha ao atualizar repositórios"
            fi
        else
            echo -e "${GREEN}Repositórios atualizados com sucesso usando --allow-unauthenticated.${NC}"
            log "Repositórios atualizados com sucesso usando --allow-unauthenticated"
        fi
    else
        echo -e "${GREEN}Repositórios atualizados com sucesso.${NC}"
        log "Repositórios atualizados com sucesso"
    fi
}

# Detecta a versão do Ubuntu
detect_ubuntu_version() {
    echo -e "${BLUE}Detectando versão do Ubuntu...${NC}"
    log "Detectando versão do Ubuntu"
    
    # Obtém a versão do Ubuntu
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_VERSION=$VERSION_ID
        OS_CODENAME=$UBUNTU_CODENAME
        
        echo -e "${GREEN}Versão do Ubuntu detectada: $OS_VERSION ($OS_CODENAME)${NC}"
        log "Versão do Ubuntu detectada: $OS_VERSION ($OS_CODENAME)"
        
        # Determina o nome da distribuição para o repositório CloudStack
        case $OS_CODENAME in
            focal)
                # Ubuntu 20.04
                CLOUDSTACK_DIST="focal"
                ;;
            jammy)
                # Ubuntu 22.04
                CLOUDSTACK_DIST="jammy"
                ;;
            noble)
                # Ubuntu 24.04
                CLOUDSTACK_DIST="noble"
                ;;
            *)
                # Fallback para focal
                echo -e "${YELLOW}Versão do Ubuntu não reconhecida. Usando 'focal' como fallback.${NC}"
                log "Versão do Ubuntu não reconhecida. Usando 'focal' como fallback"
                CLOUDSTACK_DIST="focal"
                ;;
        esac
        
        echo -e "${GREEN}Distribuição para repositório CloudStack: $CLOUDSTACK_DIST${NC}"
        log "Distribuição para repositório CloudStack: $CLOUDSTACK_DIST"
    else
        echo -e "${RED}Não foi possível detectar a versão do Ubuntu.${NC}"
        log "Não foi possível detectar a versão do Ubuntu"
        exit 1
    fi
}

# Detecta a versão do Ubuntu
detect_ubuntu_version

# Configura o repositório CloudStack
echo -e "\n${BLUE}=== Configurando repositório CloudStack ===${NC}"
log "Configurando repositório CloudStack para $OS_CODENAME"

# Adiciona o repositório CloudStack
add_cloudstack_repo "$CLOUDSTACK_DIST"

# Função para instalar pacotes do CloudStack
install_cloudstack_packages() {
    echo -e "${BLUE}Instalando pacotes do CloudStack...${NC}"
    log "Instalando pacotes do CloudStack"
    
    # Verifica se o repositório foi adicionado corretamente
    if [ ! -f /etc/apt/sources.list.d/cloudstack.list ]; then
        echo -e "${RED}Repositório CloudStack não encontrado. Verifique a configuração.${NC}"
        log "Repositório CloudStack não encontrado"
        return 1
    fi
    
    # Atualiza os repositórios novamente para garantir
    echo -e "${BLUE}Atualizando repositórios...${NC}"
    log "Atualizando repositórios"
    
    if ! safe_apt_get update; then
        echo -e "${YELLOW}Falha ao atualizar repositórios. Tentando método alternativo...${NC}"
        log "Falha ao atualizar repositórios. Tentando método alternativo"
        
        # Tenta atualizar ignorando erros de assinatura
        if ! safe_apt_get update --allow-unauthenticated; then
            echo -e "${RED}Falha ao atualizar repositórios mesmo com --allow-unauthenticated.${NC}"
            log "Falha ao atualizar repositórios mesmo com --allow-unauthenticated"
            
            # Pergunta ao usuário se deseja continuar
            read -p "Falha ao atualizar repositórios. Deseja continuar com a instalação? (s/n) " -n 1 -r
            echo
            
            if [[ ! $REPLY =~ ^[Ss]$ ]]; then
                echo -e "${RED}Instalação cancelada pelo usuário.${NC}"
                log "Instalação cancelada pelo usuário após falha ao atualizar repositórios"
                return 1
            fi
        fi
    fi
    
    # Lista de pacotes CloudStack a serem instalados
    local packages=(
        "cloudstack-management"
        "cloudstack-usage"
        "cloudstack-common"
        "cloudstack-agent"
        "cloudstack-ui"
    )
    
    # Tenta instalar todos os pacotes de uma vez
    echo -e "${BLUE}Instalando pacotes CloudStack...${NC}"
    log "Instalando pacotes CloudStack"
    
    if ! safe_apt_get install -y "${packages[@]}"; then
        echo -e "${YELLOW}Falha ao instalar pacotes CloudStack em grupo. Tentando instalar individualmente...${NC}"
        log "Falha ao instalar pacotes CloudStack em grupo. Tentando instalar individualmente"
        
        # Instala pacotes individualmente
        local failed_packages=()
        for package in "${packages[@]}"; do
            echo -e "${BLUE}Instalando $package...${NC}"
            log "Instalando $package"
            
            if ! safe_apt_get install -y "$package"; then
                echo -e "${YELLOW}Falha ao instalar $package. Tentando com --allow-unauthenticated...${NC}"
                log "Falha ao instalar $package. Tentando com --allow-unauthenticated"
                
                if ! safe_apt_get install -y --allow-unauthenticated "$package"; then
                    echo -e "${RED}Falha ao instalar $package mesmo com --allow-unauthenticated.${NC}"
                    log "Falha ao instalar $package mesmo com --allow-unauthenticated"
                    failed_packages+=("$package")
                else
                    echo -e "${GREEN}$package instalado com sucesso usando --allow-unauthenticated.${NC}"
                    log "$package instalado com sucesso usando --allow-unauthenticated"
                fi
            else
                echo -e "${GREEN}$package instalado com sucesso.${NC}"
                log "$package instalado com sucesso"
            fi
        done
        
        # Verifica se algum pacote falhou
        if [ ${#failed_packages[@]} -gt 0 ]; then
            echo -e "${RED}Os seguintes pacotes não puderam ser instalados:${NC}"
            for package in "${failed_packages[@]}"; do
                echo -e "${RED}- $package${NC}"
            done
            
            # Pergunta ao usuário se deseja continuar
            read -p "Alguns pacotes não puderam ser instalados. Deseja continuar com a instalação? (s/n) " -n 1 -r
            echo
            
            if [[ ! $REPLY =~ ^[Ss]$ ]]; then
                echo -e "${RED}Instalação cancelada pelo usuário.${NC}"
                log "Instalação cancelada pelo usuário após falha ao instalar alguns pacotes"
                return 1
            fi
        fi
    else
        echo -e "${GREEN}Todos os pacotes CloudStack instalados com sucesso.${NC}"
        log "Todos os pacotes CloudStack instalados com sucesso"
    fi
    
    echo -e "${GREEN}Instalação dos pacotes CloudStack concluída.${NC}"
    log "Instalação dos pacotes CloudStack concluída"
    return 0
}

# Instala os pacotes CloudStack
install_cloudstack_packages

# Instala MySQL
echo -e "\n${BLUE}=== Instalando MySQL ===${NC}"
log "Instalando MySQL"
safe_apt_get install -y mysql-server
check_error "Falha ao instalar MySQL"
log "MySQL instalado com sucesso"

# Verificar se o MySQL está em execução
if ! systemctl is-active --quiet mysql; then
  echo 'Iniciando o serviço MySQL...'
  systemctl start mysql
fi

# Verificar credenciais do MySQL
if ! sudo mysql -e 'SELECT 1' > /dev/null 2>&1; then
  echo -e "${RED}ERRO: Não foi possível acessar o MySQL como root. Verificando método alternativo...${NC}"
  log "Erro ao acessar MySQL como root. Tentando método alternativo."
  
  # Tenta usar o método auth_socket (padrão no Ubuntu moderno)
  if ! sudo mysql -e "CREATE USER IF NOT EXISTS '$MYSQL_USER'@'localhost' IDENTIFIED BY '$MYSQL_PASSWORD'; GRANT ALL PRIVILEGES ON *.* TO '$MYSQL_USER'@'localhost' WITH GRANT OPTION; FLUSH PRIVILEGES;" > /dev/null 2>&1; then
    echo -e "${RED}ERRO: Não foi possível configurar o usuário MySQL. A instalação não pode continuar.${NC}"
    log "Falha ao configurar usuário MySQL"
    exit 1
  else
    echo -e "${GREEN}Usuário MySQL configurado com sucesso usando método alternativo.${NC}"
    log "Usuário MySQL configurado com método alternativo"
    # Define uma variável para indicar que já configuramos o usuário
    MYSQL_USER_CONFIGURED=true
  fi
else
  echo -e "${GREEN}Acesso ao MySQL verificado com sucesso.${NC}"
  log "Acesso ao MySQL verificado com sucesso"
fi

# Configura o banco de dados CloudStack
echo -e "\n${BLUE}=== Configurando banco de dados CloudStack ===${NC}"
log "Configurando banco de dados CloudStack"

# Usa o usuário MySQL criado para configurar o banco de dados CloudStack
echo -e "${BLUE}Executando cloudstack-setup-databases...${NC}"
cloudstack-setup-databases $MYSQL_USER:$MYSQL_PASSWORD@localhost --deploy-as=root
check_error "Falha ao configurar banco de dados CloudStack"
log "Banco de dados CloudStack configurado com sucesso"

# Configura o gerenciamento CloudStack
echo -e "\n${BLUE}=== Configurando gerenciamento CloudStack ===${NC}"
log "Configurando gerenciamento CloudStack"
cloudstack-setup-management
check_error "Falha ao configurar gerenciamento CloudStack"
log "Gerenciamento CloudStack configurado com sucesso"

# Configura o firewall
echo -e "\n${BLUE}=== Configurando firewall ===${NC}"
log "Configurando firewall"
ufw allow 22/tcp
ufw allow 8080/tcp
ufw allow 8443/tcp
ufw allow 8250/tcp
ufw allow 9090/tcp
ufw allow 111/tcp
ufw allow 111/udp
ufw allow 2049/tcp
ufw allow 2049/udp
ufw allow 32803/tcp
ufw allow 32769/udp
log "Firewall configurado com sucesso"

# Configura o NFS
echo -e "\n${BLUE}=== Configurando NFS ===${NC}"
log "Configurando NFS"

# Função para configurar corretamente as permissões dos diretórios NFS
configure_nfs_permissions() {
    echo -e "${BLUE}Configurando permissões dos diretórios NFS...${NC}"
    log "Configurando permissões dos diretórios NFS"
    
    # Cria os diretórios de exportação se não existirem
    mkdir -p /export/primary
    mkdir -p /export/secondary
    
    # Define as permissões corretas
    chmod 777 /export/primary
    chmod 777 /export/secondary
    
    # Define o proprietário para o usuário nobody e grupo nogroup (padrão para NFS)
    chown nobody:nogroup /export/primary
    chown nobody:nogroup /export/secondary
    
    # Adiciona a configuração ao arquivo exports
    if ! grep -q "/export" /etc/exports; then
        echo "/export *(rw,async,no_root_squash,no_subtree_check)" | tee -a /etc/exports
        echo -e "${GREEN}Configuração adicionada ao arquivo /etc/exports${NC}"
        log "Configuração adicionada ao arquivo /etc/exports"
    fi
    
    # Recarrega a configuração do NFS
    exportfs -ra
    
    # Reinicia o serviço NFS
    echo -e "${BLUE}Reiniciando serviço NFS...${NC}"
    log "Reiniciando serviço NFS"
    
    if ! systemctl restart nfs-server; then
        echo -e "${RED}Falha ao reiniciar o serviço NFS.${NC}"
        log "Falha ao reiniciar o serviço NFS"
        return 1
    fi
    
    echo -e "${GREEN}Permissões dos diretórios NFS configuradas com sucesso.${NC}"
    log "Permissões dos diretórios NFS configuradas com sucesso"
    return 0
}

# Configura as permissões dos diretórios NFS
configure_nfs_permissions

# Instala o servidor NFS com tratamento de erros aprimorado
echo -e "${BLUE}Instalando servidor NFS...${NC}"
log "Instalando servidor NFS"
if ! safe_apt_get install -y nfs-kernel-server; then
    echo -e "${RED}Falha ao instalar o servidor NFS.${NC}"
    log "Falha ao instalar o servidor NFS"
    echo -e "${YELLOW}Tentando método alternativo...${NC}"
    log "Tentando método alternativo para instalar o servidor NFS"
    apt-get install -y nfs-kernel-server
    if [ $? -ne 0 ]; then
        echo -e "${RED}Erro: Falha ao instalar NFS${NC}"
        log "Falha ao instalar NFS usando método alternativo"
        echo -e "${YELLOW}Verifique os logs para mais detalhes.${NC}"
        exit 1
    fi
fi

# Cria diretórios de montagem e monta os compartilhamentos NFS
mkdir -p /mnt/primary
mkdir -p /mnt/secondary
echo -e "${BLUE}Montando compartilhamentos NFS...${NC}"
log "Montando compartilhamentos NFS"

# Tenta montar com várias tentativas
MAX_RETRIES=3
RETRY_COUNT=0
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if mount -t nfs localhost:/export/primary /mnt/primary; then
        echo -e "${GREEN}/export/primary montado com sucesso em /mnt/primary.${NC}"
        log "/export/primary montado com sucesso em /mnt/primary"
        break
    else
        RETRY_COUNT=$((RETRY_COUNT + 1))
        if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
            echo -e "${YELLOW}Tentativa $RETRY_COUNT falhou. Reconfigurando NFS e tentando novamente...${NC}"
            log "Tentativa $RETRY_COUNT falhou. Reconfigurando NFS e tentando novamente"
            configure_nfs_permissions
            sleep 5
        else
            echo -e "${RED}Falha ao montar /export/primary em /mnt/primary após $MAX_RETRIES tentativas.${NC}"
            log "Falha ao montar /export/primary em /mnt/primary após $MAX_RETRIES tentativas"
            echo -e "${YELLOW}Verifique se o serviço NFS está funcionando corretamente.${NC}"
        fi
    fi
done

# Reinicia o contador para o segundo compartilhamento
RETRY_COUNT=0
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if mount -t nfs localhost:/export/secondary /mnt/secondary; then
        echo -e "${GREEN}/export/secondary montado com sucesso em /mnt/secondary.${NC}"
        log "/export/secondary montado com sucesso em /mnt/secondary"
        break
    else
        RETRY_COUNT=$((RETRY_COUNT + 1))
        if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
            echo -e "${YELLOW}Tentativa $RETRY_COUNT falhou. Reconfigurando NFS e tentando novamente...${NC}"
            log "Tentativa $RETRY_COUNT falhou. Reconfigurando NFS e tentando novamente"
            sleep 5
        else
            echo -e "${RED}Falha ao montar /export/secondary em /mnt/secondary após $MAX_RETRIES tentativas.${NC}"
            log "Falha ao montar /export/secondary em /mnt/secondary após $MAX_RETRIES tentativas"
            echo -e "${YELLOW}Verifique se o serviço NFS está funcionando corretamente.${NC}"
        fi
    fi
done

log "NFS configurado com sucesso"

# Adiciona montagens NFS ao fstab
echo -e "\n${BLUE}=== Adicionando montagens NFS ao fstab ===${NC}"
log "Adicionando montagens NFS ao fstab"
if ! grep -q "/export/primary" /etc/fstab; then
    echo "localhost:/export/primary /mnt/primary nfs rw,async,intr 0 0" >> /etc/fstab
fi
if ! grep -q "/export/secondary" /etc/fstab; then
    echo "localhost:/export/secondary /mnt/secondary nfs rw,async,intr 0 0" >> /etc/fstab
fi
log "Montagens NFS adicionadas ao fstab"

# Função para adicionar o domínio download.cloudstack.org ao arquivo /etc/hosts com o IP 79.127.208.169 para garantir a resolução DNS.
add_cloudstack_repo_to_hosts() {
    echo -e "${BLUE}Adicionando download.cloudstack.org ao arquivo hosts...${NC}"
    log "Adicionando download.cloudstack.org ao arquivo hosts"
    
    # Verifica se já existe uma entrada para download.cloudstack.org
    if grep -q "download.cloudstack.org" /etc/hosts; then
        echo -e "${GREEN}Entrada para download.cloudstack.org já existe no arquivo hosts.${NC}"
        log "Entrada para download.cloudstack.org já existe no arquivo hosts"
        return 0
    fi
    
    # Adiciona a entrada para download.cloudstack.org
    echo "79.127.208.169 download.cloudstack.org" >> /etc/hosts
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Entrada para download.cloudstack.org adicionada com sucesso ao arquivo hosts.${NC}"
        log "Entrada para download.cloudstack.org adicionada com sucesso ao arquivo hosts"
    else
        echo -e "${RED}Falha ao adicionar entrada para download.cloudstack.org ao arquivo hosts.${NC}"
        log "Falha ao adicionar entrada para download.cloudstack.org ao arquivo hosts"
        return 1
    fi
}

# Adiciona o domínio download.cloudstack.org ao arquivo /etc/hosts
add_cloudstack_repo_to_hosts

# Verificar credenciais do MySQL
if ! sudo mysql -e 'SELECT 1' > /dev/null 2>&1; then
  echo -e "${RED}ERRO: Não foi possível acessar o MySQL como root. Verificando método alternativo...${NC}"
  log "Erro ao acessar MySQL como root. Tentando método alternativo."
  
  # Tenta usar o método auth_socket (padrão no Ubuntu moderno)
  if ! sudo mysql -e "CREATE USER IF NOT EXISTS '$MYSQL_USER'@'localhost' IDENTIFIED BY '$MYSQL_PASSWORD'; GRANT ALL PRIVILEGES ON *.* TO '$MYSQL_USER'@'localhost' WITH GRANT OPTION; FLUSH PRIVILEGES;" > /dev/null 2>&1; then
    echo -e "${RED}ERRO: Não foi possível configurar o usuário MySQL. A instalação não pode continuar.${NC}"
    log "Falha ao configurar usuário MySQL"
    exit 1
  else
    echo -e "${GREEN}Usuário MySQL configurado com sucesso usando método alternativo.${NC}"
    log "Usuário MySQL configurado com método alternativo"
    # Define uma variável para indicar que já configuramos o usuário
    MYSQL_USER_CONFIGURED=true
  fi
else
  echo -e "${GREEN}Acesso ao MySQL verificado com sucesso.${NC}"
  log "Acesso ao MySQL verificado com sucesso"
fi

echo -e "\n${BLUE}=== Configurando usuário MySQL para CloudStack ===${NC}"
log "Configurando usuário MySQL para CloudStack"

# Cria o usuário MySQL usando sudo (funciona com auth_socket no Ubuntu moderno)
echo -e "${BLUE}Criando usuário MySQL 'cloud'...${NC}"
if sudo mysql -e "CREATE USER IF NOT EXISTS '$MYSQL_USER'@'localhost' IDENTIFIED BY '$MYSQL_PASSWORD'; GRANT ALL PRIVILEGES ON *.* TO '$MYSQL_USER'@'localhost' WITH GRANT OPTION; FLUSH PRIVILEGES;" > /dev/null 2>&1; then
  echo -e "${GREEN}Usuário MySQL '$MYSQL_USER' criado com sucesso.${NC}"
  log "Usuário MySQL '$MYSQL_USER' criado com sucesso"
  MYSQL_USER_CONFIGURED=true
else
  echo -e "${RED}ERRO: Não foi possível criar o usuário MySQL '$MYSQL_USER'.${NC}"
  log "ERRO: Não foi possível criar o usuário MySQL '$MYSQL_USER'"
  
  # Tenta método alternativo com senha root
  echo -e "${YELLOW}Tentando método alternativo usando senha root...${NC}"
  if mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "CREATE USER IF NOT EXISTS '$MYSQL_USER'@'localhost' IDENTIFIED BY '$MYSQL_PASSWORD'; GRANT ALL PRIVILEGES ON *.* TO '$MYSQL_USER'@'localhost' WITH GRANT OPTION; FLUSH PRIVILEGES;" > /dev/null 2>&1; then
    echo -e "${GREEN}Usuário MySQL '$MYSQL_USER' criado com sucesso usando senha root.${NC}"
    log "Usuário MySQL '$MYSQL_USER' criado com sucesso usando senha root"
    MYSQL_USER_CONFIGURED=true
  else
    echo -e "${RED}ERRO: Falha ao criar usuário MySQL. A instalação não pode continuar.${NC}"
    log "ERRO: Falha ao criar usuário MySQL"
    exit 1
  fi
fi

# Testa a conexão com o usuário criado
echo -e "${BLUE}Testando conexão com o usuário MySQL '$MYSQL_USER'...${NC}"
if mysql -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" -e "SELECT 'Conexao bem-sucedida' as Status;" > /dev/null 2>&1; then
  echo -e "${GREEN}Conexão com o MySQL bem-sucedida usando o usuário '$MYSQL_USER'.${NC}"
  log "Conexão com o MySQL bem-sucedida usando o usuário '$MYSQL_USER'"
else
  echo -e "${RED}ERRO: Não foi possível conectar ao MySQL com o usuário '$MYSQL_USER'.${NC}"
  log "ERRO: Não foi possível conectar ao MySQL com o usuário '$MYSQL_USER'"
  exit 1
fi

# Finaliza a instalação
echo -e "\n${GREEN}=== Instalação concluída com sucesso! ===${NC}"
log "Instalação concluída com sucesso"
echo -e "${YELLOW}Aguarde enquanto os serviços iniciam...${NC}"

# Barra de progresso
width=$(tput cols)
progress_width=$((width - 20))
sleep_duration=$(echo "30 / $progress_width" | bc -l)
echo -n "Progresso: ["
for i in $(seq 1 $progress_width)
do
    sleep $sleep_duration
    echo -n "#"
done
echo "]"

# Obtém o IP do servidor para exibir a URL de acesso
IP_ACCESS=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v "127.0.0.1" | head -n 1)

echo -e "\n${BLUE}=== Informações de Acesso ===${NC}"
echo -e "URL: ${GREEN}http://$IP_ACCESS:8080/client${NC}"
echo -e "Usuário: ${GREEN}admin${NC}"
echo -e "Senha: ${GREEN}password${NC}"
echo -e "\n${YELLOW}Nota: Por motivos de segurança, altere a senha padrão após o primeiro login.${NC}"
echo -e "${YELLOW}Pode levar alguns minutos para que o CloudStack esteja totalmente operacional.${NC}"
echo -e "${YELLOW}Log da instalação salvo em: ${GREEN}$LOG_FILE${NC}"

# Verifica o status dos serviços
echo -e "\n${BLUE}=== Status dos Serviços ===${NC}"
log "Verificando status dos serviços"
systemctl status mysql --no-pager
systemctl status cloudstack-management --no-pager
systemctl status cloudstack-usage --no-pager
systemctl status nfs-kernel-server --no-pager

echo -e "\n${GREEN}=== Instalação do CloudStack 4.20.0.0 concluída! ===${NC}"
log "Processo de instalação finalizado"
