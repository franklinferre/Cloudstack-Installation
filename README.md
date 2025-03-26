# CloudStack Installer 4.20.0.0 (LTS) - Lideri.cloud

Script de instalação automatizada do Apache CloudStack 4.20.0.0 (LTS) otimizado para a infraestrutura da Lideri.cloud.

## Visão Geral

Este projeto contém scripts para instalação e configuração do Apache CloudStack 4.20.0.0 (LTS) em ambientes Ubuntu, seguindo as regras e padrões de rede da Lideri.cloud.

### Características Principais

- **Suporte a Múltiplos Datacenters**: Olinda, Igarassu, João Pessoa, Recife, São Paulo e Hostinger SP
- **Estrutura de Clusters Padronizada**: Suporte aos clusters bravo, sierra, delta, charlie e echo
- **Nomenclatura Padronizada**: Segue o formato `<cluster><cluster_num>.node<server_num>.<dc_code>.lideri.cloud`
- **Configuração de Rede Automatizada**: Configuração baseada na estrutura de rede da Lideri.cloud
- **Instalação Completa**: Inclui MySQL, NFS, e todos os componentes necessários para o CloudStack
- **Verificações de Pré-requisitos**: Verifica conectividade, resolução DNS e dependências
- **Tratamento de Erros Robusto**: Oferece alternativas quando ocorrem falhas
- **Suporte a Múltiplas Versões do Ubuntu**: Compatível com Ubuntu 20.xx, 22.04 e 24.04

## Requisitos

- Sistema Operacional: Ubuntu 20.xx, 22.04 ou 24.04
- Memória: Mínimo 8GB RAM (recomendado 16GB+)
- Armazenamento: Mínimo 100GB de espaço livre
- Rede: Conectividade com a internet para download de pacotes
- Privilégios: Acesso root ou sudo

## Uso

1. Clone este repositório ou baixe o script `cloudstack-installer.sh`
2. Torne o script executável:
   ```
   chmod +x cloudstack-installer.sh
   ```
3. Execute o script como root:
   ```
   sudo ./cloudstack-installer.sh
   ```
4. Siga as instruções interativas para configurar sua instalação

## Estrutura de Rede

O script segue o plano de alocação de sub-redes da Lideri.cloud:

- **Datacenters**: Cada datacenter possui um bloco /16 (ex: Olinda - 10.128.0.0/16)
- **Clusters**: Cada cluster recebe um bloco de 16 sub-redes /24 dentro do datacenter
- **Servidores**: Cada servidor recebe uma sub-rede /24 dentro do seu cluster

## Componentes Instalados

- Apache CloudStack 4.20.0.0 (LTS)
- MySQL Server (para banco de dados do CloudStack)
- NFS Server (para armazenamento primário e secundário)
- Dependências e utilitários necessários

## Arquivos do Projeto

- `cloudstack-installer.sh`: Script principal de instalação
- `regras.md`: Documentação das regras e padrões da Lideri.cloud
- `README.md`: Este arquivo de documentação

## Resolução de Problemas

Se encontrar problemas durante a instalação:

1. Verifique o arquivo de log (o caminho é exibido ao final da instalação)
2. Certifique-se de que seu sistema atende aos requisitos mínimos
3. Verifique se há conectividade com a internet e resolução DNS

## Contribuição

Contribuições são bem-vindas! Sinta-se à vontade para abrir issues ou enviar pull requests com melhorias.

## Licença

Este projeto é distribuído sob a licença Apache 2.0, a mesma do Apache CloudStack.

---

Desenvolvido para a infraestrutura da Lideri.cloud - 2025
