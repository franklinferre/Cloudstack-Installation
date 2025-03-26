#!/bin/bash

# Script para configurar cloudbr0 para CloudStack
# Este script configura a bridge cloudbr0 para ser usada pelo CloudStack

echo "Iniciando configuração da bridge cloudbr0 para CloudStack..."

# Verificar se está sendo executado como root
if [ "$(id -u)" -ne 0 ]; then
   echo "Este script deve ser executado como root" 
   exit 1
fi

# Obter configurações atuais da bridge br0
BR0_IP=$(ip -4 addr show dev br0 | grep inet | awk '{print $2}')
BR0_GATEWAY=$(ip route | grep default | awk '{print $3}')
BR0_INTERFACE=$(brctl show br0 | grep -v "bridge name" | awk '{print $4}')

echo "Configurações atuais:"
echo "IP da br0: $BR0_IP"
echo "Gateway: $BR0_GATEWAY"
echo "Interface conectada à br0: $BR0_INTERFACE"

# Verificar se a cloudbr0 já existe
if brctl show | grep -q cloudbr0; then
    echo "A bridge cloudbr0 já existe."
    
    # Verificar se já está configurada
    CLOUDBR0_IP=$(ip -4 addr show dev cloudbr0 2>/dev/null | grep inet | awk '{print $2}')
    if [ -n "$CLOUDBR0_IP" ]; then
        echo "A bridge cloudbr0 já está configurada com o IP: $CLOUDBR0_IP"
        echo "Não é necessário fazer alterações na configuração de rede."
        
        # Apenas reiniciar o cloudstack-agent
        echo "Reiniciando o serviço cloudstack-agent..."
        systemctl restart cloudstack-agent
        exit 0
    fi
fi

# Criar a bridge cloudbr0 se não existir
if ! brctl show | grep -q cloudbr0; then
    echo "Criando bridge cloudbr0..."
    brctl addbr cloudbr0
    ip link set dev cloudbr0 up
fi

# Verificar se a interface física está conectada à br0
if [ -z "$BR0_INTERFACE" ]; then
    echo "AVISO: Não foi encontrada interface conectada à br0!"
    echo "Verificando interfaces disponíveis..."
    
    # Listar interfaces disponíveis
    AVAILABLE_INTERFACES=$(ip -o link show | grep -v "lo\|br0\|cloudbr0" | awk -F': ' '{print $2}')
    echo "Interfaces disponíveis: $AVAILABLE_INTERFACES"
    
    # Usar a primeira interface disponível
    PHYSICAL_INTERFACE=$(echo $AVAILABLE_INTERFACES | awk '{print $1}')
    
    if [ -n "$PHYSICAL_INTERFACE" ]; then
        echo "Usando interface $PHYSICAL_INTERFACE para cloudbr0"
        brctl addif cloudbr0 $PHYSICAL_INTERFACE
    else
        echo "ERRO: Não foi possível encontrar uma interface física disponível!"
        exit 1
    fi
else
    echo "A interface $BR0_INTERFACE está conectada à br0"
    echo "IMPORTANTE: Não vamos desconectar a interface da br0 para evitar perda de conectividade."
    echo "Em vez disso, vamos configurar o cloudbr0 para uso do CloudStack sem alterar a configuração atual de rede."
fi

# Configurar o IP na cloudbr0 apenas se não tiver IP
CLOUDBR0_IP=$(ip -4 addr show dev cloudbr0 2>/dev/null | grep inet | awk '{print $2}')
if [ -z "$CLOUDBR0_IP" ]; then
    echo "Adicionando IP temporário à cloudbr0 para o CloudStack..."
    # Usar um IP na mesma sub-rede, mas diferente do br0
    if [ -n "$BR0_IP" ]; then
        # Extrair a base do IP e a máscara
        IP_BASE=$(echo $BR0_IP | cut -d'.' -f1-3)
        IP_LAST=$(echo $BR0_IP | cut -d'.' -f4 | cut -d'/' -f1)
        IP_MASK=$(echo $BR0_IP | cut -d'/' -f2)
        
        # Calcular um novo último octeto (incrementar por 10)
        NEW_LAST=$((IP_LAST + 10))
        if [ $NEW_LAST -gt 254 ]; then
            NEW_LAST=$((IP_LAST - 10))
        fi
        
        # Criar o novo IP
        NEW_IP="${IP_BASE}.${NEW_LAST}/${IP_MASK}"
        
        echo "Adicionando IP $NEW_IP à cloudbr0..."
        ip addr add $NEW_IP dev cloudbr0
    else
        echo "AVISO: Não foi possível determinar um IP para cloudbr0!"
    fi
fi

# Atualizar o arquivo de configuração do cloudstack-agent
echo "Atualizando configuração do cloudstack-agent..."
systemctl restart cloudstack-agent

echo "Configuração concluída!"
echo "A bridge cloudbr0 foi configurada para uso do CloudStack."
echo "A configuração de rede atual com br0 foi mantida para evitar perda de conectividade."
echo "Para uma configuração completa, você deve atualizar os arquivos de configuração de rede"
echo "do sistema para usar cloudbr0 como bridge principal após reiniciar o servidor."
