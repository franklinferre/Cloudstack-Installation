# Plano de Alocação de Sub-redes Lideri.cloud

# Plano de Alocação de Sub-redes Lideri.cloud

## 1. Introdução

Este documento define o esquema de alocação de sub-redes para a infraestrutura da Lideri.cloud, iniciando com o bloco de endereçamento 10.128.0.0/16. A estrutura foi projetada para acomodar uma organização hierárquica: datacenters → clusters → servidores → VMs → containers, com amplitude para crescimento significativo.

## 2. Estrutura de Alocação

### 2.1 Visão Geral

- **Alocação por Datacenter**: Um bloco /16 completo (65.536 endereços)
- **Alocação por Cluster**: /20 (4.096 endereços por cluster)
- **Alocação por Servidor**: /24 (256 endereços por servidor)
- **Alocação por VM/KVM**: /26 (64 endereços por VM)
- **Alocação para Docker/Pods**: /28 (16 endereços por ambiente de container)

### 2.2 Formato de Endereçamento

```
10.(128+DC).(CLUSTER*16)+(SERVIDOR/16).HOST

```

Onde:

- **DC**: Identificador numérico do datacenter (0-7)
- **CLUSTER**: Identificador numérico do cluster (0-15 por datacenter)
- **SERVIDOR**: Identificador numérico do servidor dentro do cluster (0-255)
- **HOST**: Endereço do host dentro do servidor (0-255)

## 3. Tabela de Alocação por Datacenter

| Datacenter | Código | Bloco CIDR |
| --- | --- | --- |
| Olinda | OL | 10.128.0.0/16 |
| São Paulo | SP | 10.129.0.0/16 |
| Rio de Janeiro | RJ | 10.130.0.0/16 |
| Recife | RE | 10.131.0.0/16 |
| Belo Horizonte | BH | 10.132.0.0/16 |
| (Reserva para expansão) | - | 10.133.0.0/16 - 10.135.0.0/16 |

## 4. Exemplo de Subdivisão Completa (Olinda)

### 4.1 Rede de Gerenciamento e Clusters em Olinda (10.128.0.0/16)

| Rede | Bloco CIDR | Propósito |
| --- | --- | --- |
| Gerenciamento | 10.128.0.0/24 | iLO, iDRAC, BMC, switches, etc. |

| Cluster | Bloco CIDR |
| --- | --- |
| Cluster 001 | 10.128.16.0/20 |
| Cluster 002 | 10.128.32.0/20 |
| Cluster 003 | 10.128.48.0/20 |
| Cluster 004 | 10.128.64.0/20 |
| Cluster 005 | 10.128.80.0/20 |
| ... | ... |
| Cluster 016 | 10.128.240.0/20 |

### 4.2 Servidores no Cluster 001 de Olinda (10.128.16.0/20)

| Servidor | Bloco CIDR |
| --- | --- |
| Servidor 001 | 10.128.16.0/24 |
| Servidor 002 | 10.128.17.0/24 |
| Servidor 003 | 10.128.18.0/24 |
| ... | ... |
| Servidor 016 | 10.128.31.0/24 |

### 4.3 VMs no Servidor 001 do Cluster 001 de Olinda (10.128.16.0/24)

| VM | Bloco CIDR |
| --- | --- |
| VM 001 | 10.128.16.0/26 |
| VM 002 | 10.128.16.64/26 |
| VM 003 | 10.128.16.128/26 |
| VM 004 | 10.128.16.192/26 |

### 4.4 Containers/Pods na VM 001 (10.128.16.0/26)

| Container/Pod | Bloco CIDR |
| --- | --- |
| Pod 001 | 10.128.16.0/28 |
| Pod 002 | 10.128.16.16/28 |
| Pod 003 | 10.128.16.32/28 |
| Pod 004 | 10.128.16.48/28 |

## 5. Convenções de Uso

### 5.1 Rede de Gerenciamento

Em cada datacenter, o primeiro bloco /24 é reservado para gerenciamento:

- **Olinda**: 10.128.0.0/24
- **São Paulo**: 10.129.0.0/24
- **Rio de Janeiro**: 10.130.0.0/24
- **Recife**: 10.131.0.0/24
- **Belo Horizonte**: 10.132.0.0/24

Esta rede deve ser usada exclusivamente para:

- Interfaces de gerenciamento remoto (iLO, iDRAC, BMC)
- Gerenciamento de switches e roteadores
- Acesso a consoles de PDUs
- Outros dispositivos de infraestrutura

### 5.2 Endereços Reservados

Em cada sub-rede, reserve os seguintes endereços:

- Primeiro endereço (.1): Gateway de rede
- Segundo endereço (.2): DNS primário
- Terceiro endereço (.3): DNS secundário
- Quarto endereço (.4): DHCP (se aplicável)
- Quinto endereço (.5): Gerenciamento/Monitoramento
- Último endereço (.255 em /24): Broadcast

### 5.3 Exemplo de Atribuição para Servidor FZ-C1-OL001-001.lideri.cloud

- **Nome**: FZ-C1-OL001-001.lideri.cloud
- **Datacenter**: Olinda (10.128.0.0/16)
- **Cluster**: 001 (10.128.16.0/20)
- **Bloco CIDR**: 10.128.16.0/24
- **Gateway**: 10.128.16.1
- **Range Utilizável**: 10.128.16.2 - 10.128.16.254

**Endereços específicos**:

- **Interface iDRAC**: 10.128.0.10/24 (na rede de gerenciamento)
- **Sistema Operacional (Debian/OpenStack)**: 10.128.16.6/24

**Uso de endereços reservados**:

- 10.128.16.1: Gateway
- 10.128.16.2: DNS primário
- 10.128.16.3: DNS secundário
- 10.128.16.4: DHCP (se aplicável)
- 10.128.16.5: Gerenciamento/Monitoramento
- 10.128.16.6: IP principal do sistema operacional (Debian/OpenStack)
- 10.128.16.7+: IPs adicionais para interfaces específicas do OpenStack

## 6. Planejamento para Crescimento

Esta estrutura permite:

- Até 8 datacenters (facilmente expansível para 128 usando o range 10.128.0.0 - 10.255.0.0)
- Até 16 clusters por datacenter
- Até 16 servidores por cluster (expansível para mais conforme necessário)
- Até 4 VMs por servidor
- Até 4 grupos de containers por VM

## 7. Exemplos Práticos de Nomenclatura com IPs

| Recurso | Nome | Localização | IP/CIDR |
| --- | --- | --- | --- |
| Interface iDRAC (Dell R740xd) | FZ-C1-OL001-001-idrac.lideri.cloud | Datacenter: OL | 10.128.0.10/24 |
| Sistema OS (Debian/OpenStack) | FZ-C1-OL001-001.lideri.cloud | Datacenter: OL, Cluster: 001 | 10.128.16.6/24 |
| Rede do Servidor | FZ-C1-OL001-001.lideri.cloud | Datacenter: OL, Cluster: 001 | 10.128.16.0/24 |
| VM no Servidor acima | NV-A2-OL001-010.lideri.cloud | Hospedado em FZ-C1-OL001-001 | 10.128.16.64/26 |
| Container Docker | TZ-D2P-OL001-001.lideri.cloud | Hospedado em NV-A2-OL001-010 | 10.128.16.16/28 |

## 8. Mapeamento entre Nomenclatura e Endereçamento IP

Para manter o alinhamento entre o esquema de nomenclatura e o endereçamento IP:

| Componente de Nome | Componente de IP |
| --- | --- |
| Localização (OL, SP, etc.) | Segundo octeto (128, 129, etc.) |
| Número do Cluster (001-016) | Terceiro octeto (dividido por 16) |
| Número do Servidor | Resto do terceiro octeto |

## 9. São Paulo - Exemplo de Subdivisão

| Rede | Bloco CIDR | Propósito |
| --- | --- | --- |
| Gerenciamento | 10.129.0.0/24 | iLO, iDRAC, BMC, switches, etc. |

| Cluster | Bloco CIDR |
| --- | --- |
| Cluster 001 | 10.129.16.0/20 |
| Cluster 002 | 10.129.32.0/20 |

| Servidor | Bloco CIDR |
| --- | --- |
| FZ-C1-SP001-001.lideri.cloud | 10.129.16.0/24 |
| FZ-C1-SP001-002.lideri.cloud | 10.129.17.0/24 |
| FZ-C1-SP002-001.lideri.cloud | 10.129.32.0/24 |

