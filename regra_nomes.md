# Documentação Completa: Convenção de Nomes, Endereçamento IP, VLAN e DNS para Apache CloudStack

## 1. Objetivo
Este documento consolida **padrões de nomenclatura**, **plano de endereçamento IPv4**, **alocação de VLANs** e **configuração DNS/FQDN** para todos os recursos provisionados via Apache CloudStack nos seis Data Centers da Lideri. Respanda e Comente em pt-br

## 2. Data Centers (DC)
Cada DC recebe um bloco /16 distinto conforme abaixo:

| Código | Nome | Prefixo IPv4 (/16) | Comentário |
|--------|------|--------------------|------------|
| **oli** | Olinda | 10.128.0.0/16 | DC01 |
| **iga** | Igarassu | 10.129.0.0/16 | DC02 |
| **jpa** | João Pessoa | 10.130.0.0/16 | DC03 |
| **rec** | Recife | 10.131.0.0/16 | DC04 |
| **spo** | São Paulo | 10.132.0.0/16 | DC05 |
| **hsp** | Hostinger SP | 10.133.0.0/16 | DC06 |

## 3. Convenção de Nomes (FQDN)
Formato geral:
```
<rack>-<host>[-vm<seq>][-k<seq>].<dc>.lideri.cloud
```
| Tipo | Exemplo | Descrição |
|------|---------|-----------|
| Host físico | `r01-h01.oli.lideri.cloud` | Rack 01 → Host 01 em Olinda |
| VM genérica | `r01-h01-vm01.oli.lideri.cloud` | VM nº 01 no host |
| Kubernetes node | `r01-h01-vm01-k01.oli.lideri.cloud` | Node K8s nº 01 dentro da VM |
| Storage controller | `r01-st01.oli.lideri.cloud` | Storage nº 01 no rack |
| CloudStack UI/API | `cloudstack.oli.lideri.cloud` | Interface de gestão |
| Kubernetes API | `api.oli.lideri.cloud` | Endpoint de ingress |

## 4. DNS
- Domínio raiz: `lideri.cloud`
- Sub‑domínios por DC: `<dc>.lideri.cloud`
- Reverse DNS (/24 hosts): `x.x.10.in-addr.arpa`

## 5. Plano de Endereçamento IPv4 (/16 por DC)
Cada /16 é subdividido em cinco /24, com gateway em `.1`, DNS Anycast (`.2`→186.208.0.1, `.3`→186.208.0.2) **apenas na rede Hosts**, e hosts/VMs a partir de `.11`.

| DC | Rede | CIDR (/24) | Gateway | DNS Anycast | IPs Usáveis |
|----|------|------------|---------|-------------|-------------|
| **oli** | Management | 10.128.0.0/24 | .1 | Reservado | .11–.254 |
| | Hosts | 10.128.1.0/24 | .1 | .2 & .3 | .11–.254 |
| | Public | 10.128.2.0/24 | .1 | Reservado | .11–.254 |
| | VMs | 10.128.3.0/24 | .1 | Reservado | .11–.254 |
| | K8s | 10.128.4.0/24 | .1 | Reservado | .11–.254 |
| **iga** | Management | 10.129.0.0/24 | .1 | Reservado | .11–.254 |
| | Hosts | 10.129.1.0/24 | .1 | .2 & .3 | .11–.254 |
| | Public | 10.129.2.0/24 | .1 | Reservado | .11–.254 |
| | VMs | 10.129.3.0/24 | .1 | Reservado | .11–.254 |
| | K8s | 10.129.4.0/24 | .1 | Reservado | .11–.254 |
| **jpa** | Management | 10.130.0.0/24 | .1 | Reservado | .11–.254 |
| | Hosts | 10.130.1.0/24 | .1 | .2 & .3 | .11–.254 |
| | Public | 10.130.2.0/24 | .1 | Reservado | .11–.254 |
| | VMs | 10.130.3.0/24 | .1 | Reservado | .11–.254 |
| | K8s | 10.130.4.0/24 | .1 | Reservado | .11–.254 |
| **rec** | Management | 10.131.0.0/24 | .1 | Reservado | .11–.254 |
| | Hosts | 10.131.1.0/24 | .1 | .2 & .3 | .11–.254 |
| | Public | 10.131.2.0/24 | .1 | Reservado | .11–.254 |
| | VMs | 10.131.3.0/24 | .1 | Reservado | .11–.254 |
| | K8s | 10.131.4.0/24 | .1 | Reservado | .11–.254 |
| **spo** | Management | 10.132.0.0/24 | .1 | Reservado | .11–.254 |
| | Hosts | 10.132.1.0/24 | .1 | .2 & .3 | .11–.254 |
| | Public | 10.132.2.0/24 | .1 | Reservado | .11–.254 |
| | VMs | 10.132.3.0/24 | .1 | Reservado | .11–.254 |
| | K8s | 10.132.4.0/24 | .1 | Reservado | .11–.254 |
| **hsp** | Management | 10.133.0.0/24 | .1 | Reservado | .11–.254 |
| | Hosts | 10.133.1.0/24 | .1 | .2 & .3 | .11–.254 |
| | Public | 10.133.2.0/24 | .1 | Reservado | .11–.254 |
| | VMs | 10.133.3.0/24 | .1 | Reservado | .11–.254 |
| | K8s | 10.133.4.0/24 | .1 | Reservado | .11–.254 |

## 6. Alocação de VLANs (3001–4000)

Cada Data Center recebe um bloco contínuo de **25 VLAN IDs** para isolamento e futura expansão:

- **oli (Olinda)**: VLANs **3001–3025**
- **iga (Igarassu)**: VLANs **3026–3050**
- **jpa (João Pessoa)**: VLANs **3051–3075**
- **rec (Recife)**: VLANs **3076–3100**
- **spo (São Paulo)**: VLANs **3101–3125**
- **hsp (Hostinger SP)**: VLANs **3126–3150**

Cada bloco abrange as redes Management, Hosts, Public, VMs e K8s Nodes, deixando espaço para adicionar novas redes sem reconfiguração.

## 7. Mapeamento no CloudStack. Mapeamento no CloudStack
| Objeto | Name | Convenção |
|--------|------|-----------|
| Zone | <dc> | Código do DC (oli, iga, jpa, rec, spo, hsp) |
| Pod | R<rack> | Rack number |
| Cluster | R<rack>-CL | Cluster within Pod |
| Host | <rack>-H<host>.<dc>.lideri.cloud | Host físico |
| Primary Storage | <rack>-ST<seq>.<dc>.lideri.cloud | Storage |
| Network | <dc>-<function> | Nome da rede CloudStack |
| VM Instance | <rack>-H<host>-VM<seq>.<dc>.lideri.cloud | VM |
| Secondary Storage | <dc>-SS | Secondary Storage |

## 8. VLAN Pools & Network Isolation (Advanced Zone)
No modelo **Advanced Zone** do CloudStack, cada rede (Management, Hosts, Public, VMs, K8s) é isolada por VLAN. Os **VLAN Pools** são configurados por Pod e vinculados às ofertas de rede. A atribuição de **Public IPs** também ocorre via rede pública (VLAN específica) usando o Virtual Router.

### Configuração de VLAN Pools por DC

Cada Data Center possui um bloco contínuo de **25 VLAN IDs**. Os primeiros cinco IDs de cada bloco são usados para Management, Hosts, Public, VMs e K8s Nodes; o restante fica reservado para expansão.

| DC | VLAN Range | VLANs iniciais (Mgmt, Hosts, Public, VMs, K8s) |
|----|------------|-----------------------------------------------|
| oli | 3001–3025 | 3001, 3002, 3003, 3004, 3005 |
| iga | 3026–3050 | 3026, 3027, 3028, 3029, 3030 |
| jpa | 3051–3075 | 3051, 3052, 3053, 3054, 3055 |
| rec | 3076–3100 | 3076, 3077, 3078, 3079, 3080 |
| spo | 3101–3125 | 3101, 3102, 3103, 3104, 3105 |
| hsp | 3126–3150 | 3126, 3127, 3128, 3129, 3130 |

> **Nota:** VLAN Pools são definidos no CloudStack em **Infrastructure → Physical Network → VLAN Ranges**. A rede pública deve usar um Pool dedicado para alocação de IPs a contas (conforme Public IPs & VLANs for Accounts)

*Última atualização: Março/2025*

