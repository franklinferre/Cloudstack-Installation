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
    echo -e "${BLUE}Verificando resolução DNS para $domain...${NC}"
    log "Verificando resolução DNS para $domain"
    
    if host "$domain" >/dev/null 2>&1; then
        echo -e "${GREEN}Resolução DNS para $domain está funcionando.${NC}"
        log "Resolução DNS para $domain está funcionando"
        return 0
    else
        echo -e "${RED}Não foi possível resolver o domínio $domain.${NC}"
        log "Não foi possível resolver o domínio $domain"
        
        echo -e "${YELLOW}Tentando métodos alternativos...${NC}"
        # Tenta com nslookup
        if nslookup "$domain" >/dev/null 2>&1; then
            echo -e "${GREEN}Resolução DNS para $domain está funcionando (via nslookup).${NC}"
            log "Resolução DNS para $domain está funcionando (via nslookup)"
            return 0
        fi
        
        # Tenta com dig
        if command -v dig >/dev/null 2>&1 && dig "$domain" >/dev/null 2>&1; then
            echo -e "${GREEN}Resolução DNS para $domain está funcionando (via dig).${NC}"
            log "Resolução DNS para $domain está funcionando (via dig)"
            return 0
        fi
        
        echo -e "${YELLOW}Deseja adicionar uma entrada para $domain no arquivo /etc/hosts? (s/n)${NC}"
        read -p "Adicionar ao /etc/hosts? [s]: " ADD_TO_HOSTS
        ADD_TO_HOSTS=${ADD_TO_HOSTS:-s}
        
        if [[ "$ADD_TO_HOSTS" =~ ^[Ss]$ ]]; then
            case "$domain" in
                "download.cloudstack.org")
                    echo -e "${BLUE}Adicionando entrada para download.cloudstack.org no arquivo /etc/hosts...${NC}"
                    echo "185.199.109.153 download.cloudstack.org" >> /etc/hosts
                    log "Adicionada entrada para download.cloudstack.org no arquivo /etc/hosts"
                    ;;
                *)
                    echo -e "${RED}Não foi possível adicionar entrada para $domain no arquivo /etc/hosts.${NC}"
                    log "Não foi possível adicionar entrada para $domain no arquivo /etc/hosts"
                    ;;
            esac
            
            # Verifica se a adição funcionou
            if host "$domain" >/dev/null 2>&1; then
                echo -e "${GREEN}Resolução DNS para $domain está funcionando agora.${NC}"
                log "Resolução DNS para $domain está funcionando após adição ao /etc/hosts"
                return 0
            else
                echo -e "${RED}Ainda não foi possível resolver o domínio $domain.${NC}"
                log "Ainda não foi possível resolver o domínio $domain após adição ao /etc/hosts"
            fi
        fi
        
        echo -e "${YELLOW}Deseja continuar mesmo sem resolução DNS para $domain? (s/n)${NC}"
        read -p "Continuar? [n]: " CONTINUE_WITHOUT_DNS
        CONTINUE_WITHOUT_DNS=${CONTINUE_WITHOUT_DNS:-n}
        
        if [[ "$CONTINUE_WITHOUT_DNS" =~ ^[Ss]$ ]]; then
            echo -e "${YELLOW}Continuando sem resolução DNS para $domain. Algumas funcionalidades podem não funcionar corretamente.${NC}"
            log "Usuário optou por continuar sem resolução DNS para $domain"
            return 0
        else
            echo -e "${RED}Instalação cancelada devido à falta de resolução DNS para $domain.${NC}"
            log "Instalação cancelada devido à falta de resolução DNS para $domain"
            exit 1
        fi
    fi
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

# Função para configurar o hostname
configure_hostname() {
    log "Configurando hostname"
    
    # Define o hostname
    hostnamectl set-hostname $FULL_HOSTNAME
    
    echo -e "${GREEN}Hostname configurado: $FULL_HOSTNAME${NC}"
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

echo -e "${BLUE}=== Instalador CloudStack 4.20.0.0 ===${NC}"
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

# Configurações de rede
echo -e "\n${BLUE}=== Detectando configurações de rede ===${NC}"
GATEWAY=$(ip r | awk '/default/ {print $3}')
IP=$(ip -o -4 addr show | awk '$2 != "lo" {print $4}' | cut -d/ -f1 | head -n1)
ADAPTER=$(ip -o -4 addr show | awk '$2 != "lo" {print $2}' | head -n1)

echo -e "IP: ${GREEN}$IP${NC}"
echo -e "Gateway: ${GREEN}$GATEWAY${NC}"
echo -e "Adaptador: ${GREEN}$ADAPTER${NC}"

# Configurações do Datacenter e Cluster (Lideri.cloud)
echo -e "\n${BLUE}=== Configurações de Datacenter e Cluster (Lideri.cloud) ===${NC}"
echo -e "${YELLOW}Selecione o datacenter:${NC}"
echo -e "1) Olinda (OLI) - 10.128.0.0/16"
echo -e "2) Igarassu (IGA) - 10.129.0.0/16"
echo -e "3) João Pessoa (JPA) - 10.130.0.0/16"
echo -e "4) Recife (REC) - 10.131.0.0/16"
echo -e "5) São Paulo (SAO) - 10.132.0.0/16"
echo -e "6) Hostinger SP (HSP) - 10.133.0.0/16"
read -p "Escolha o datacenter [1]: " DC_CHOICE
DC_CHOICE=${DC_CHOICE:-1}

case $DC_CHOICE in
    1) DC_CODE="oli"; DC_NAME="Olinda"; DC_OCTET=128 ;;
    2) DC_CODE="iga"; DC_NAME="Igarassu"; DC_OCTET=129 ;;
    3) DC_CODE="jpa"; DC_NAME="João Pessoa"; DC_OCTET=130 ;;
    4) DC_CODE="rec"; DC_NAME="Recife"; DC_OCTET=131 ;;
    5) DC_CODE="spo"; DC_NAME="São Paulo"; DC_OCTET=132 ;;
    6) DC_CODE="hsp"; DC_NAME="Hostinger SP"; DC_OCTET=133 ;;
    *) DC_CODE="oli"; DC_NAME="Olinda"; DC_OCTET=128 ;;
esac

echo -e "Datacenter selecionado: ${GREEN}$DC_NAME ($DC_CODE)${NC}"

# Seleciona o Cluster
echo -e "${YELLOW}Selecione o nome do cluster:${NC}"
echo -e "1) bravo"
echo -e "2) sierra"
echo -e "3) delta"
echo -e "4) charlie"
echo -e "5) echo"
read -p "Escolha o cluster [1]: " CLUSTER_NAME_CHOICE
CLUSTER_NAME_CHOICE=${CLUSTER_NAME_CHOICE:-1}

case $CLUSTER_NAME_CHOICE in
    1) CLUSTER_NAME="bravo" ;;
    2) CLUSTER_NAME="sierra" ;;
    3) CLUSTER_NAME="delta" ;;
    4) CLUSTER_NAME="charlie" ;;
    5) CLUSTER_NAME="echo" ;;
    *) CLUSTER_NAME="bravo" ;;
esac

read -p "Número do Cluster (01-16) [01]: " CLUSTER_NUM
CLUSTER_NUM=${CLUSTER_NUM:-01}
CLUSTER_NUM=$(printf "%02d" $((10#${CLUSTER_NUM})))

# Calcula o terceiro octeto base para o cluster
CLUSTER_ID=$((10#${CLUSTER_NUM}))
if [ $CLUSTER_ID -lt 1 ] || [ $CLUSTER_ID -gt 16 ]; then
    echo -e "${RED}Número de cluster inválido. Usando o padrão (01).${NC}"
    CLUSTER_ID=1
    CLUSTER_NUM="01"
fi
# Cálculo correto: clusters começam em 16, 32, 48, etc. (incrementos de 16)
THIRD_OCTET=$(((($CLUSTER_ID-1)*16) + 16))

# Seleciona o Servidor
read -p "Número do Servidor (01-16) [01]: " SERVER_NUM
SERVER_NUM=${SERVER_NUM:-01}
SERVER_NUM=$(printf "%02d" $((10#$SERVER_NUM)))

# Calcula o IP com base nas regras da Lideri.cloud
SERVER_ID=$((10#$SERVER_NUM))
if [ $SERVER_ID -lt 1 ] || [ $SERVER_ID -gt 16 ]; then
    echo -e "${RED}Número de servidor inválido. Usando o padrão (01).${NC}"
    SERVER_ID=1
    SERVER_NUM="01"
fi

# Calcula o IP do servidor - o terceiro octeto é baseado no cluster e no número do servidor
# Para o servidor 01 do cluster 01, seria 10.128.16.0/24
# Para o servidor 02 do cluster 01, seria 10.128.17.0/24
SERVER_OCTET=$((THIRD_OCTET + SERVER_ID - 1))

# Calcula os IPs para a rede do servidor
IP_NETWORK="10.$DC_OCTET.$SERVER_OCTET.0/24"
IP_GATEWAY="10.$DC_OCTET.$SERVER_OCTET.1"
# Servidores DNS anycast da cloud completa
IP_DNS1="186.208.0.1"
IP_DNS2="186.208.0.2"
IP_DHCP="10.$DC_OCTET.$SERVER_OCTET.4"
IP_MGMT="10.$DC_OCTET.$SERVER_OCTET.5"
IP_SERVER="10.$DC_OCTET.$SERVER_OCTET.6"

# Calcula o IP de gerenciamento (iDRAC, iLO, etc.) no bloco 10.DC.0.0/24
MGMT_IP="10.$DC_OCTET.0.$SERVER_ID"

# Configurações do host
echo -e "\n${BLUE}=== Configurações do Host ===${NC}"
echo -e "${YELLOW}Seguindo padrão de nomenclatura Lideri.cloud${NC}"

# Gera o nome do host conforme padrão <cluster>.<node>.<zone>.lideri.cloud
HOSTNAME="${CLUSTER_NAME}${CLUSTER_NUM}.node${SERVER_NUM}.${DC_CODE}"
echo -e "Nome do Host: ${GREEN}$HOSTNAME${NC}"

read -p "Domínio [lideri.cloud]: " DOMAIN
DOMAIN=${DOMAIN:-lideri.cloud}

FULL_HOSTNAME="${HOSTNAME}.${DOMAIN}"
echo -e "Nome completo do host: ${GREEN}$FULL_HOSTNAME${NC}"

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
echo -e "Cluster: ${GREEN}${CLUSTER_NAME}${CLUSTER_NUM}${NC}"
echo -e "Servidor: ${GREEN}node${SERVER_NUM}${NC}"
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

# Configura o hostname
echo -e "\n${BLUE}=== Configurando hostname ===${NC}"
log "Configurando hostname: $FULL_HOSTNAME"
hostnamectl set-hostname $FULL_HOSTNAME
check_error "Falha ao configurar hostname"

# Configura o arquivo hosts
echo -e "\n${BLUE}=== Configurando arquivo /etc/hosts ===${NC}"
log "Configurando arquivo /etc/hosts"
HOSTS_CONTENT="127.0.0.1\tlocalhost\n$IP_SERVER\t$FULL_HOSTNAME\t$HOSTNAME"
echo -e "$HOSTS_CONTENT" | tee /etc/hosts
check_error "Falha ao configurar arquivo hosts"

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
    
    # Verifica se o arquivo de interfaces existe
    if [ ! -f /etc/netplan/00-installer-config.yaml ]; then
        echo -e "${YELLOW}Arquivo de configuração de rede não encontrado. Criando um novo.${NC}"
        cat > /etc/netplan/00-installer-config.yaml << EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    eth0:
      dhcp4: no
      addresses: [$IP_SERVER/24]
      gateway4: $IP_GATEWAY
      nameservers:
        addresses: [$IP_DNS1, $IP_DNS2]
EOF
    else
        # Backup do arquivo original
        cp /etc/netplan/00-installer-config.yaml /etc/netplan/00-installer-config.yaml.bak
        
        # Atualiza a configuração de rede
        cat > /etc/netplan/00-installer-config.yaml << EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    eth0:
      dhcp4: no
      addresses: [$IP_SERVER/24]
      gateway4: $IP_GATEWAY
      nameservers:
        addresses: [$IP_DNS1, $IP_DNS2]
EOF
    fi
    
    # Aplica a configuração
    netplan apply
    
    # Verifica se a configuração foi aplicada corretamente
    sleep 5
    CURRENT_IP=$(ip -4 addr show eth0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
    if [ "$CURRENT_IP" != "$IP_SERVER" ]; then
        echo -e "${RED}Falha ao aplicar configuração de rede. IP atual: $CURRENT_IP, IP esperado: $IP_SERVER${NC}"
        echo -e "${YELLOW}Tentando configuração alternativa...${NC}"
        
        # Tenta configuração alternativa
        ip addr add $IP_SERVER/24 dev eth0
        ip route add default via $IP_GATEWAY
        
        # Verifica novamente
        sleep 2
        CURRENT_IP=$(ip -4 addr show eth0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
        if [ "$CURRENT_IP" != "$IP_SERVER" ]; then
            echo -e "${RED}Falha ao aplicar configuração de rede alternativa.${NC}"
            echo -e "${YELLOW}Por favor, configure manualmente a rede após a instalação.${NC}"
        else
            echo -e "${GREEN}Configuração de rede alternativa aplicada com sucesso.${NC}"
        fi
    else
        echo -e "${GREEN}Configuração de rede aplicada com sucesso.${NC}"
    fi
    
    # Atualiza o arquivo hosts
    update_hosts_file
}

update_hosts_file() {
    log "Atualizando arquivo hosts"
    
    # Backup do arquivo original
    cp /etc/hosts /etc/hosts.bak
    
    # Cria um novo arquivo hosts
    cat > /etc/hosts << EOF
127.0.0.1       localhost
$IP_SERVER      $FULL_HOSTNAME $HOSTNAME

# Servidores DNS Anycast da Lideri.cloud
$IP_DNS1        dns1.lideri.cloud
$IP_DNS2        dns2.lideri.cloud

# The following lines are desirable for IPv6 capable hosts
::1             localhost ip6-localhost ip6-loopback
ff02::1         ip6-allnodes
ff02::2         ip6-allrouters
EOF
    
    echo -e "${GREEN}Arquivo hosts atualizado.${NC}"
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

# Gera um arquivo de informações do servidor
echo -e "\n${BLUE}=== Gerando arquivo de informações do servidor ===${NC}"
INFO_FILE="/root/server-info-$HOSTNAME.txt"
cat > $INFO_FILE << EOF
# Informações do Servidor CloudStack
# Gerado em: $(date)

## Informações Gerais
Nome do Host: $FULL_HOSTNAME
Datacenter: $DC_NAME ($DC_CODE)
Cluster: ${CLUSTER_NAME}${CLUSTER_NUM}
Servidor: node${SERVER_NUM}

## Informações de Rede
Rede: $IP_NETWORK
IP do Servidor: $IP_SERVER
Gateway: $IP_GATEWAY
DNS Primário: $IP_DNS1
DNS Secundário: $IP_DNS2
DHCP: $IP_DHCP
IP de Gerenciamento (Sistema): $IP_MGMT
IP de Gerenciamento (iDRAC/iLO): $MGMT_IP

## Acesso CloudStack
URL: http://$IP_SERVER:8080/client
Usuário: admin
Senha: password (altere após o primeiro login)

## Informações do Sistema
Sistema Operacional: $OS_TYPE $OS_VERSION ($OS_CODENAME)
CloudStack: 4.20.0.0 (LTS)

## Configuração MySQL
Usuário MySQL: $MYSQL_USER
Senha MySQL: $MYSQL_PASSWORD
Senha Root: $MYSQL_ROOT_PASSWORD

## Diretórios Importantes
NFS Primário: /export/primary
NFS Secundário: /export/secondary
Montagens: /mnt/primary, /mnt/secondary
EOF

echo -e "Arquivo de informações gerado em: ${GREEN}$INFO_FILE${NC}"
log "Arquivo de informações do servidor gerado em: $INFO_FILE"

# Configura o repositório CloudStack
echo -e "\n${BLUE}=== Configurando repositório CloudStack ===${NC}"
log "Configurando repositório CloudStack para $OS_CODENAME"

# Configura DNS para usar Google DNS
configure_dns

# Verifica conectividade com a internet antes de prosseguir
echo -e "${BLUE}Verificando conectividade com a internet...${NC}"
log "Verificando conectividade com a internet"
check_internet_connection
if [ $? -ne 0 ]; then
    echo -e "${RED}Sem conectividade com a internet. Não é possível continuar.${NC}"
    log "Sem conectividade com a internet. Não é possível continuar."
    exit 1
fi

# Verifica resolução DNS para download.cloudstack.org
echo -e "${BLUE}Verificando resolução DNS para download.cloudstack.org...${NC}"
log "Verificando resolução DNS para download.cloudstack.org"
check_dns_resolution "download.cloudstack.org"
if [ $? -ne 0 ]; then
    echo -e "${YELLOW}Falha na resolução DNS para download.cloudstack.org.${NC}"
    log "Falha na resolução DNS para download.cloudstack.org"
    
    echo -e "${BLUE}Adicionando entrada para download.cloudstack.org no arquivo /etc/hosts...${NC}"
    log "Adicionando entrada para download.cloudstack.org no arquivo /etc/hosts"
    add_to_hosts "download.cloudstack.org" "104.18.20.196"
    
    # Verifica novamente
    check_dns_resolution "download.cloudstack.org"
    if [ $? -ne 0 ]; then
        echo -e "${RED}Ainda não é possível resolver download.cloudstack.org. Não é possível continuar.${NC}"
        log "Ainda não é possível resolver download.cloudstack.org. Não é possível continuar."
        exit 1
    fi
fi

# Ubuntu
case "$OS_CODENAME" in
    focal)
        echo -e "${BLUE}Adicionando chave GPG do repositório CloudStack...${NC}"
        log "Adicionando chave GPG do repositório CloudStack"
        
        # Tenta baixar e adicionar a chave GPG com tratamento de erros
        if ! wget -q -O - http://download.cloudstack.org/release.asc | apt-key add -; then
            echo -e "${YELLOW}Falha ao baixar a chave GPG usando wget. Tentando método alternativo...${NC}"
            log "Falha ao baixar a chave GPG usando wget. Tentando método alternativo."
            
            if ! curl -fsSL http://download.cloudstack.org/release.asc | apt-key add -; then
                echo -e "${RED}Falha ao baixar a chave GPG.${NC}"
                log "Falha ao baixar a chave GPG"
                exit 1
            fi
        fi
        
        echo "deb [arch=amd64] http://download.cloudstack.org/ubuntu focal 4.20" > /etc/apt/sources.list.d/cloudstack.list
        ;;
    jammy)
        echo -e "${BLUE}Adicionando chave GPG do repositório CloudStack...${NC}"
        log "Adicionando chave GPG do repositório CloudStack"
        
        # Tenta baixar e adicionar a chave GPG com tratamento de erros
        if ! wget -q -O - http://download.cloudstack.org/release.asc | apt-key add -; then
            echo -e "${YELLOW}Falha ao baixar a chave GPG usando wget. Tentando método alternativo...${NC}"
            log "Falha ao baixar a chave GPG usando wget. Tentando método alternativo."
            
            if ! curl -fsSL http://download.cloudstack.org/release.asc | apt-key add -; then
                echo -e "${RED}Falha ao baixar a chave GPG.${NC}"
                log "Falha ao baixar a chave GPG"
                exit 1
            fi
        fi
        
        echo "deb [arch=amd64] http://download.cloudstack.org/ubuntu jammy 4.20" > /etc/apt/sources.list.d/cloudstack.list
        ;;
    noble)
        # Para Ubuntu 24.04 (noble), usamos o método moderno de adicionar a chave GPG
        echo -e "${BLUE}Adicionando chave GPG do repositório CloudStack para Ubuntu 24.04 (noble)...${NC}"
        log "Adicionando chave GPG do repositório CloudStack para Ubuntu 24.04 (noble)"
        
        # Remove configurações anteriores
        rm -f /etc/apt/sources.list.d/cloudstack.list
        rm -f /etc/apt/trusted.gpg.d/cloudstack.asc
        
        # Adiciona a chave GPG usando o método moderno com tratamento de erros aprimorado
        echo -e "${BLUE}Baixando e adicionando chave GPG...${NC}"
        log "Baixando e adicionando chave GPG"
        
        # Tenta vários métodos para baixar a chave GPG
        if wget -q -O - https://download.cloudstack.org/release.asc | tee /etc/apt/trusted.gpg.d/cloudstack.asc > /dev/null; then
            echo -e "${GREEN}Chave GPG adicionada com sucesso.${NC}"
            log "Chave GPG adicionada com sucesso"
        elif curl -fsSL https://download.cloudstack.org/release.asc | tee /etc/apt/trusted.gpg.d/cloudstack.asc > /dev/null; then
            echo -e "${GREEN}Chave GPG adicionada com sucesso usando curl.${NC}"
            log "Chave GPG adicionada com sucesso usando curl"
        else
            echo -e "${RED}Falha ao adicionar chave GPG.${NC}"
            log "Falha ao adicionar chave GPG"
            exit 1
        fi
        
        # Adiciona o repositório CloudStack usando HTTPS
        echo -e "${BLUE}Configurando repositório CloudStack...${NC}"
        log "Configurando repositório CloudStack"
        echo "deb https://download.cloudstack.org/ubuntu noble 4.20" > /etc/apt/sources.list.d/cloudstack.list
        
        echo -e "${GREEN}Repositório configurado para Ubuntu 24.04 (noble)${NC}"
        log "Repositório configurado para Ubuntu 24.04 (noble)"
        ;;
    *)
        echo -e "${RED}Versão do Ubuntu não suportada: $OS_CODENAME${NC}"
        log "Versão do Ubuntu não suportada: $OS_CODENAME"
        exit 1
        ;;
esac

# Atualiza e instala CloudStack
echo -e "\n${BLUE}=== Instalando CloudStack 4.20.0.0 ===${NC}"
log "Atualizando repositórios"

# Atualiza o sistema
echo -e "${BLUE}Atualizando o sistema...${NC}"
log "Iniciando atualização do sistema"

# Executa apt-get update
echo -e "${BLUE}Executando: apt-get update${NC}"
log "Executando: apt-get update"

# Verifica bloqueio do apt
wait_for_apt_lock

# Executa apt-get update com retry
for i in {1..3}; do
    if apt-get update; then
        echo -e "${GREEN}Sistema atualizado com sucesso.${NC}"
        log "Sistema atualizado com sucesso"
        break
    else
        echo -e "${YELLOW}Falha ao executar apt-get. Tentativa $i de 3.${NC}"
        log "Falha ao executar apt-get. Tentativa $i de 3."
        
        if [ $i -eq 3 ]; then
            echo -e "${RED}Falha ao executar apt-get após 3 tentativas.${NC}"
            log "Falha ao executar apt-get após 3 tentativas."
            echo -e "${RED}Erro: Falha ao atualizar o sistema${NC}"
            echo -e "${YELLOW}Verifique os logs para mais detalhes.${NC}"
            exit 1
        fi
        
        sleep 5
    fi
done

# Instala MySQL
echo -e "\n${BLUE}=== Instalando MySQL ===${NC}"
log "Instalando MySQL"
safe_apt_get install -y mysql-server
check_error "Falha ao instalar MySQL"
log "MySQL instalado com sucesso"

# Configura MySQL
echo -e "\n${BLUE}=== Configurando MySQL ===${NC}"
log "Configurando MySQL"
echo -e "\nserver_id = 1\nsql-mode=\"STRICT_TRANS_TABLES,NO_ENGINE_SUBSTITUTION,ERROR_FOR_DIVISION_BY_ZERO,NO_ZERO_DATE,NO_ZERO_IN_DATE,NO_ENGINE_SUBSTITUTION\"\ninnodb_rollback_on_timeout=1\ninnodb_lock_wait_timeout=600\nmax_connections=1000\nlog-bin=mysql-bin\nbinlog-format = 'ROW'" | tee -a /etc/mysql/mysql.conf.d/mysqld.cnf
echo -e "[mysqld]" | tee /etc/mysql/mysql.conf.d/cloudstack.cnf
systemctl restart mysql
check_error "Falha ao configurar MySQL"
log "MySQL configurado com sucesso"

# Instala CloudStack
echo -e "\n${BLUE}=== Instalando CloudStack ===${NC}"
log "Instalando CloudStack"
safe_apt_get install -y cloudstack-management cloudstack-usage cloudstack-ui cloudstack-common
check_error "Falha ao instalar CloudStack"
log "CloudStack instalado com sucesso"

# Configura o banco de dados CloudStack
echo -e "\n${BLUE}=== Configurando banco de dados CloudStack ===${NC}"
log "Configurando banco de dados CloudStack"
cloudstack-setup-databases "$MYSQL_USER:$MYSQL_PASSWORD@localhost" --deploy-as=root:"$MYSQL_ROOT_PASSWORD"
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
mkdir -p /export/primary
mkdir -p /export/secondary
echo "/export *(rw,async,no_root_squash,no_subtree_check)" | tee -a /etc/exports

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

# Reinicia o serviço NFS
echo -e "${BLUE}Reiniciando serviço NFS...${NC}"
log "Reiniciando serviço NFS"
if ! service nfs-kernel-server restart; then
    echo -e "${RED}Falha ao reiniciar o serviço NFS.${NC}"
    log "Falha ao reiniciar o serviço NFS"
    echo -e "${YELLOW}Tentando método alternativo...${NC}"
    log "Tentando método alternativo para reiniciar o serviço NFS"
    systemctl restart nfs-kernel-server
    if [ $? -ne 0 ]; then
        echo -e "${RED}Erro: Falha ao reiniciar NFS${NC}"
        log "Falha ao reiniciar NFS usando método alternativo"
        echo -e "${YELLOW}Verifique os logs para mais detalhes.${NC}"
        exit 1
    fi
fi

# Cria diretórios de montagem e monta os compartilhamentos NFS
mkdir -p /mnt/primary
mkdir -p /mnt/secondary
echo -e "${BLUE}Montando compartilhamentos NFS...${NC}"
log "Montando compartilhamentos NFS"
if ! mount -t nfs localhost:/export/primary /mnt/primary; then
    echo -e "${RED}Falha ao montar /export/primary em /mnt/primary.${NC}"
    log "Falha ao montar /export/primary em /mnt/primary"
    echo -e "${YELLOW}Verifique se o serviço NFS está funcionando corretamente.${NC}"
fi
if ! mount -t nfs localhost:/export/secondary /mnt/secondary; then
    echo -e "${RED}Falha ao montar /export/secondary em /mnt/secondary.${NC}"
    log "Falha ao montar /export/secondary em /mnt/secondary"
    echo -e "${YELLOW}Verifique se o serviço NFS está funcionando corretamente.${NC}"
fi
log "NFS configurado com sucesso"

# Adiciona montagens NFS ao fstab
echo -e "\n${BLUE}=== Adicionando montagens NFS ao fstab ===${NC}"
log "Adicionando montagens NFS ao fstab"
if ! grep -q "/export/primary" /etc/fstab; then
    echo "localhost:/export/primary /mnt/primary nfs rw,soft,intr 0 0" >> /etc/fstab
fi
if ! grep -q "/export/secondary" /etc/fstab; then
    echo "localhost:/export/secondary /mnt/secondary nfs rw,soft,intr 0 0" >> /etc/fstab
fi
log "Montagens NFS adicionadas ao fstab"

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

echo -e "\n${BLUE}=== Informações de Acesso ===${NC}"
echo -e "URL: ${GREEN}http://$IP_SERVER:8080/client${NC}"
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
