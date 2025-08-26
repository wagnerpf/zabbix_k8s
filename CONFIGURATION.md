# 🔧 Configuração do Ambiente Zabbix

## 📝 Antes de Começar

Este projeto contém **placeholders genéricos** que devem ser substituídos pelas suas informações específicas antes do deployment.

## 🔑 Informações Confidenciais a Configurar

### 1. **Arquivo: `ansible/inventories/production/hosts.yml`**

Substitua os seguintes valores:

```yaml
# Informações do Kubernetes Master
ansible_host: <YOUR_K8S_MASTER_IP>  # Ex: 192.168.1.100
ansible_user: <YOUR_K8S_USER>       # Ex: ubuntu, admin, etc.

# Senhas do PostgreSQL
postgres_password: "<YOUR_POSTGRES_PASSWORD>"      # Ex: "MinhaSenh@123"
postgres_root_password: "<YOUR_POSTGRES_ROOT_PASSWORD>"  # Ex: "RootSenh@456"

# Domínio (opcional)
ingress_host: "<your-zabbix-domain.local>"  # Ex: "zabbix.empresa.com"
```

### 2. **Scripts (Configuração Automática)**

Os scripts já estão configurados para extrair automaticamente o IP do arquivo de inventário, mas você pode verificar:

- `scripts/status.sh` - Extrai IP do inventário
- `scripts/deploy.sh` - Mostra placeholders genéricos
- `scripts/logs.sh` - Configurado para SSH genérico

### 3. **Verificação de Conectividade**

Após configurar o inventário, teste a conectividade:

```bash
# Teste de ping via Ansible
ansible kubernetes_masters -i ansible/inventories/production/hosts.yml -m ping

# Teste de SSH direto
ssh -i ~/.ssh/k8s-cluster-key <SEU_USUARIO>@<SEU_IP_K8S>
```

## 🚀 Processo de Deploy

1. **Configure suas informações** no arquivo `hosts.yml`
2. **Verifique a conectividade** com o comando ping acima
3. **Execute o deploy**: `./scripts/deploy.sh`
4. **Acesse via browser**: `http://<SEU_IP>:30080`

## 🔐 Segurança

- ✅ Senhas não estão hardcoded nos scripts
- ✅ IPs são extraídos dinamicamente do inventário
- ✅ Informações sensíveis são placeholders
- ✅ SSH keys referenciadas genericamente

## 📊 Observação sobre Prometheus

**Este projeto NÃO inclui deploy do Prometheus/Grafana**, apenas:
- Anotações preparatórias nos pods Zabbix
- ConfigMap com configuração prometheus.yml (não utilizada)
- Variáveis de configuração no inventário

Para implementar Prometheus, será necessário adicionar os manifests correspondentes.

## 📞 Suporte

Para dúvidas sobre a configuração específica do seu ambiente, consulte:
- Documentação do Kubernetes do seu cluster
- Políticas de segurança da sua organização
- Administradores de sistema locais

---
⚠️  **IMPORTANTE**: Nunca commite informações confidenciais (IPs, senhas, usuários) no repositório!
