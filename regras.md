# Plano de Alocação de Sub-redes Lideri.cloud

# Plano de Alocação de Sub-redes Lideri.cloud

## 1. Introdução

Este documento define o esquema de alocação de sub-redes para a infraestrutura da Lideri.cloud, iniciando com o bloco de endereçamento 10.128.0.0/16. A estrutura foi projetada para acomodar uma organização hierárquica: datacenters → clusters → servidores → VMs → containers, com amplitude para crescimento significativo.

## 2. Estrutura de Alocação

### 2.1 Visão Geral

- **Alocação por Datacenter**: Um bloco /16 completo (65.536 endereços)
- **Alocação por Cluster**: /20 (4.096 endereços por cluster)
- **Alocação por Servidor**: /24 (256 endereços por servidor)
- **Alocação por VM**: /26 (64 endereços por VM)
- **Alocação para Containers**: /28 (16 endereços por ambiente de container)

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

| Localização | Código | Bloco CIDR | Zone |
| --- | --- | --- | --- |
| Olinda | OLI | 10.128.0.0/16 | oli |
| Igarassu | IGA | 10.129.0.0/16 | iga |
| João Pessoa | JPA | 10.130.0.0/16 | jpa |
| Recife | REC | 10.131.0.0/16 | rec |
| São Paulo | SAO | 10.132.0.0/16 | spo |
| Hostinger SP | HSP | 10.133.0.0/16 | hsp |
| (Reserva para expansão) | - | 10.134.0.0/16 - 10.135.0.0/16 | - |

## 4. Convenção de Nomenclatura — LidOpsStack

### 4.1 Padrão de Nome

```
<cluster>.<node>.<vm>.<container>.<zone>.lideri.cloud

```

- **cluster**: identificador lógico do agrupamento (DC ou cluster) - formato: nome+NN (ex: bravo01)
- **node**: servidor físico ou hypervisor - formato: node+NN (ex: node02)
- **vm**: instância virtual - formato: vm+NN (ex: vm05)
- **container** (opcional): unidade de execução/container - formato: ct+NN (ex: ct03)
- **zone**: sigla da localização física - valores: oli, iga, jpa, rec, spo, hsp

### 4.2 Formatos válidos

| Campo | Formato | Exemplo |
| --- | --- | --- |
| cluster | nome+NN | bravo01 |
| node | node+NN | node02 |
| vm | vm+NN | vm05 |
| container | ct+NN | ct03 |
| zone | oli, iga, jpa, rec, spo, hsp | rec |

### 4.3 Exemplos de Hostnames

| Host completo | Descrição |
| --- | --- |
| bravo01.node02.vm05.ct03.rec.lideri.cloud | Cluster Bravo → Node02 → VM05 → CT03 → Recife |
| sierra02.node01.vm11.spo.lideri.cloud | Cluster Sierra → Node01 → VM11 → São Paulo |
| delta03.node05.vm20.ct01.jpa.lideri.cloud | Cluster Delta → Node05 → VM20 → CT01 → João Pessoa |
| bravo01.node04.vm08.oli.lideri.cloud | Cluster Bravo → Node04 → VM08 (sem container) → Olinda |

## 5. DNS Global Anycast

O DNS global Lideri será configurado como serviço Anycast nos seguintes endereços:

- **DNS Primário**: 186.208.0.1
- **DNS Secundário**: 186.208.0.2

Cada servidor DNS em cada datacenter terá estes IPs configurados em interfaces loopback com máscara /32, permitindo responder como parte do serviço Anycast global.

Em cada sub-rede:

- O endereço .2 será reservado para interface com o DNS primário Anycast
- O endereço .3 será reservado para interface com o DNS secundário Anycast

## 6. Exemplo de Subdivisão Completa (Olinda)

### 6.1 Rede de Gerenciamento e Clusters em Olinda (10.128.0.0/16)

| Rede | Bloco CIDR | Propósito |
| --- | --- | --- |
| Gerenciamento | 10.128.0.0/24 | IPMI, BMC, switches, etc. |

| Cluster | Bloco CIDR |
| --- | --- |
| bravo01 | 10.128.16.0/20 |
| sierra01 | 10.128.32.0/20 |
| delta01 | 10.128.48.0/20 |
| charlie01 | 10.128.64.0/20 |
| echo01 | 10.128.80.0/20 |
| ... | ... |

### 6.2 Servidores no Cluster bravo01 de Olinda (10.128.16.0/20)

| Servidor | Bloco CIDR |
| --- | --- |
| bravo01.node01.oli.lideri.cloud | 10.128.16.0/24 |
| bravo01.node02.oli.lideri.cloud | 10.128.17.0/24 |
| bravo01.node03.oli.lideri.cloud | 10.128.18.0/24 |
| ... | ... |
| bravo01.node16.oli.lideri.cloud | 10.128.31.0/24 |

### 6.3 VMs no Servidor node01 do Cluster bravo01 de Olinda (10.128.16.0/24)

| VM | Bloco CIDR |
| --- | --- |
| bravo01.node01.vm01.oli.lideri.cloud | 10.128.16.0/26 |
| bravo01.node01.vm02.oli.lideri.cloud | 10.128.16.64/26 |
| bravo01.node01.vm03.oli.lideri.cloud | 10.128.16.128/26 |
| bravo01.node01.vm04.oli.lideri.cloud | 10.128.16.192/26 |

### 6.4 Containers na VM01 (10.128.16.0/26)

| Container | Bloco CIDR |
| --- | --- |
| bravo01.node01.vm01.ct01.oli.lideri.cloud | 10.128.16.0/28 |
| bravo01.node01.vm01.ct02.oli.lideri.cloud | 10.128.16.16/28 |
| bravo01.node01.vm01.ct03.oli.lideri.cloud | 10.128.16.32/28 |
| bravo01.node01.vm01.ct04.oli.lideri.cloud | 10.128.16.48/28 |

## 7. Convenções de Uso

### 7.1 Rede de Gerenciamento

Em cada datacenter, o primeiro bloco /24 é reservado para gerenciamento:

- **Olinda**: 10.128.0.0/24
- **Igarassu**: 10.129.0.0/24
- **João Pessoa**: 10.130.0.0/24
- **Recife**: 10.131.0.0/24
- **São Paulo**: 10.132.0.0/24
- **Hostinger SP**: 10.133.0.0/24

Esta rede deve ser usada exclusivamente para:

- Interfaces de gerenciamento remoto (IPMI, BMC)
- Gerenciamento de switches e roteadores
- Acesso a consoles de PDUs
- Outros dispositivos de infraestrutura

### 7.2 Endereços Reservados

Em cada sub-rede, reserve os seguintes endereços:

- Primeiro endereço (.1): Gateway de rede
- Segundo endereço (.2): DNS primário Anycast (186.208.0.1)
- Terceiro endereço (.3): DNS secundário Anycast (186.208.0.2)
- Quarto endereço (.4): DHCP (se aplicável)
- Quinto endereço (.5): Gerenciamento/Monitoramento
- Último endereço (.255 em /24): Broadcast

### 7.3 Exemplo de Atribuição para Servidor bravo01.node01.oli.lideri.cloud

- **Nome**: bravo01.node01.oli.lideri.cloud
- **Datacenter**: Olinda (10.128.0.0/16)
- **Cluster**: bravo01 (10.128.16.0/20)
- **Bloco CIDR**: 10.128.16.0/24
- **Gateway**: 10.128.16.1
- **Range Utilizável**: 10.128.16.2 - 10.128.16.254

**Endereços específicos**:

- **Interface IPMI/BMC**: 10.128.0.10/24 (na rede de gerenciamento)
- **Sistema Operacional (Hypervisor)**: 10.128.16.6/24

**Uso de endereços reservados**:

- 10.128.16.1: Gateway
- 10.128.16.2: DNS primário Anycast (186.208.0.1)
- 10.128.16.3: DNS secundário Anycast (186.208.0.2)
- 10.128.16.4: DHCP (se aplicável)
- 10.128.16.5: Gerenciamento/Monitoramento
- 10.128.16.6: IP principal do sistema operacional (Hypervisor)
- 10.128.16.7+: IPs adicionais para interfaces específicas do sistema de nuvem

## 8. Planejamento para Crescimento

Esta estrutura permite:

- Até 8 datacenters (facilmente expansível para 128 usando o range 10.128.0.0 - 10.255.0.0)
- Até 16 clusters por datacenter
- Até 16 servidores por cluster (expansível para mais conforme necessário)
- Até 4 VMs por servidor
- Até 4 grupos de containers por VM

## 9. Exemplos Práticos de Nomenclatura com IPs

| Recurso | Nome | Localização | IP/CIDR |
| --- | --- | --- | --- |
| Interface IPMI/BMC | bravo01.node01-ipmi.oli.lideri.cloud | Datacenter: oli | 10.128.0.10/24 |
| Sistema OS (Hypervisor) | bravo01.node01.oli.lideri.cloud | Datacenter: oli, Cluster: bravo01 | 10.128.16.6/24 |
| Rede do Servidor | bravo01.node01-net.oli.lideri.cloud | Datacenter: oli, Cluster: bravo01 | 10.128.16.0/24 |
| VM no Servidor acima | bravo01.node01.vm02.oli.lideri.cloud | Hospedado em bravo01.node01 | 10.128.16.64/26 |
| Container | bravo01.node01.vm02.ct01.oli.lideri.cloud | Hospedado em bravo01.node01.vm02 | 10.128.16.16/28 |

## 10. Mapeamento entre Nomenclatura e Endereçamento IP

Para manter o alinhamento entre o esquema de nomenclatura e o endereçamento IP:

| Componente de Nome | Componente de IP |
| --- | --- |
| Localização (oli, iga, etc.) | Segundo octeto (128, 129, etc.) |
| Cluster (bravo01, sierra01, etc.) | Terceiro octeto (dividido por 16) |
| Número do Node | Resto do terceiro octeto |

## 11. São Paulo - Exemplo de Subdivisão

| Rede | Bloco CIDR | Propósito |
| --- | --- | --- |
| Gerenciamento | 10.132.0.0/24 | IPMI, BMC, switches, etc. |

| Cluster | Bloco CIDR |
| --- | --- |
| sierra02 | 10.132.16.0/20 |
| delta02 | 10.132.32.0/20 |

| Servidor | Bloco CIDR |
| --- | --- |
| sierra02.node01.spo.lideri.cloud | 10.132.16.0/24 |
| sierra02.node02.spo.lideri.cloud | 10.132.17.0/24 |
| delta02.node01.spo.lideri.cloud | 10.132.32.0/24 |

## 12. Plano de Implementação

1. **Fase 1**: Configuração dos blocos de datacenter
2. **Fase 2**: Atribuição de sub-redes para clusters existentes
3. **Fase 3**: Migração gradual de servidores e VMs para o novo esquema
4. **Fase 4**: Implementação de IPAM para gerenciamento centralizado

## 13. Diretrizes para Componentes da Plataforma de Nuvem

### 13.1 Atribuição de IPs para Diferentes Serviços da Plataforma de Nuvem

Para servidores da plataforma de nuvem, recomenda-se a seguinte divisão dentro do bloco /24 do servidor:

| Faixa | Uso | Exemplo (para bravo01.node01) |
| --- | --- | --- |
| x.x.x.6 | IP principal do sistema (Hypervisor) | 10.128.16.6 |
| x.x.x.7-10 | APIs da Plataforma de Nuvem | 10.128.16.7-10 |
| x.x.x.11-20 | Redes de Gerenciamento da Plataforma | 10.128.16.11-20 |
| x.x.x.21-30 | Redes de Armazenamento | 10.128.16.21-30 |
| x.x.x.31-40 | Redes de Tenant | 10.128.16.31-40 |
| x.x.x.41-50 | Redes de Provedor | 10.128.16.41-50 |

## 14. Automação da Nomenclatura (Python snippet)

```python
import re

pattern = re.compile(r"^[a-z]+\d{2}\.node\d{2}\.vm\d{2}(?:\.ct\d{2})?\.(?:oli|iga|jpa|rec|spo|hsp)\.lideri\.cloud$")

def generate_name(cluster, node, vm, container=None, zone="rec"):
    parts = [f"{cluster:02}" if isinstance(cluster,int) else cluster,
             f"node{node:02}", f"vm{vm:02}"]
    if container:
        parts.append(f"ct{container:02}")
    parts.append(zone)
    name = ".".join(parts) + ".lideri.cloud"
    assert pattern.match(name), "Invalid hostname format"
    return name

def generate_ip(zone_code, cluster_num, node_num, vm_num=None, container_num=None):
    """
    Generate IP based on the hostname components

    Args:
        zone_code (str): Zone code (oli, iga, jpa, etc.)
        cluster_num (int): Cluster number (1-16)
        node_num (int): Node number (1-16)
        vm_num (int, optional): VM number (1-4)
        container_num (int, optional): Container number (1-4)

    Returns:
        str: IP address in CIDR notation
    """
    # Map zone to second octet
    zone_map = {
        'oli': 128,
        'iga': 129,
        'jpa': 130,
        'rec': 131,
        'spo': 132,
        'hsp': 133
    }

    second_octet = zone_map.get(zone_code, 128)
    third_octet = (cluster_num - 1) * 16 + (node_num - 1)

    if vm_num is None and container_num is None:
        # Server level - /24
        return f"10.{second_octet}.{third_octet}.0/24"
    elif container_num is None:
        # VM level - /26
        fourth_octet = (vm_num - 1) * 64
        return f"10.{second_octet}.{third_octet}.{fourth_octet}/26"
    else:
        # Container level - /28
        fourth_octet = (vm_num - 1) * 64 + (container_num - 1) * 16
        return f"10.{second_octet}.{third_octet}.{fourth_octet}/28"

# Example usage
hostname = generate_name('bravo01', 3, 5, 3, 'rec')
ip = generate_ip('rec', 1, 3, 5, 3)
print(f"Hostname: {hostname}")
print(f"IP: {ip}")

```

## 15. Governança

- Todos os nomes devem ser registrados no sistema IPAM (IP Address Management)
- Auditoria semestral para remover ativos obsoletos
- Qualquer exceção deve ser aprovada pelo time de Infraestrutura

## 16. Diagrama de Sub-redes

Para facilitar a visualização, abaixo está representada graficamente a subdivisão de blocos de endereços:

```
10.128.0.0/16 (Olinda)
│
├── 10.128.0.0/24 (Rede de Gerenciamento)
│
├── 10.128.16.0/20 (bravo01)
│   ├── 10.128.16.0/24 (node01)
│   │   ├── 10.128.16.0/26 (vm01)
│   │   │   ├── 10.128.16.0/28 (ct01)
│   │   │   ├── 10.128.16.16/28 (ct02)
│   │   │   └── ...
│   │   ├── 10.128.16.64/26 (vm02)
│   │   └── ...
│   ├── 10.128.17.0/24 (node02)
│   └── ...
│
├── 10.128.32.0/20 (sierra01)
└── ...

```

## 17. Recomendações para Implementação de DNS

Para uma implementação robusta do serviço DNS Anycast:

1. Configurar servidores DNS primários em cada datacenter
2. Utilizar BGP para o anúncio dos endereços Anycast 186.208.0.1/32 e 186.208.0.2/32
3. Implementar servidores BIND ou PowerDNS com suporte a zonas dinâmicas
4. Configurar replicação de zonas entre os servidores DNS
5. Implementar monitoramento e failover automatizado