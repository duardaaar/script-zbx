# Zabbix 7.0 LTS — Instalação em servidores separados

Scripts em Bash que instalam o **Zabbix 7.0 LTS** em uma arquitetura de **dois servidores**: um dedicado ao banco de dados PostgreSQL e outro à aplicação (Zabbix Server + Frontend).

```
┌──────────────────────────────────┐              ┌──────────────────────────┐
│     SERVIDOR DA APLICAÇÃO        │   5432/tcp   │    SERVIDOR DE BANCO     │
│                                  │ ───────────► │                          │
│  Zabbix Server                   │              │  PostgreSQL              │
│  Frontend (Apache + PHP-FPM)     │              │  banco: zabbix           │
│  Zabbix Agent 2                  │              │                          │
└──────────────────────────────────┘              └──────────────────────────┘
   install_zabbix7_app.bash                          install_zabbix7_db.bash
```

| Componente     | Tecnologia                                   |
|----------------|----------------------------------------------|
| Sistema        | Ubuntu 26.04 LTS (nos dois servidores)       |
| Banco de dados | PostgreSQL (versão do repositório do Ubuntu) |
| Servidor web   | Apache + PHP-FPM                             |
| Zabbix         | Server, Frontend e Agent 2                   |

---

## Sumário

- [Requisitos](#requisitos)
- [Arquivos do repositório](#arquivos-do-repositório)
- [Instalação](#instalação)
- [Parâmetros (.env)](#parâmetros-env)
- [O que cada script faz](#o-que-cada-script-faz)
- [Após a instalação](#após-a-instalação)
- [Executar novamente](#executar-novamente)
- [Solução de problemas](#solução-de-problemas)
- [Segurança](#segurança)

---

## Requisitos

**Nos dois servidores**

- Ubuntu **26.04** recém-instalado
- Acesso **root** ou usuário com `sudo`
- Acesso à internet (repositórios do Ubuntu; o servidor da aplicação também acessa `repo.zabbix.com`)
- Data e hora corretas — o script tenta sincronizar via NTP automaticamente

**Entre os servidores**

- O servidor da aplicação precisa alcançar o servidor de banco na porta **5432/tcp**
- Cada servidor com **IP fixo** (o banco libera acesso apenas para o IP da aplicação)

**Recomendado para ambientes pequenos**

| Servidor  | vCPU | RAM  | Disco |
|-----------|------|------|-------|
| Banco     | 2    | 4 GB | 40 GB |
| Aplicação | 2    | 4 GB | 20 GB |

> 💡 Se estiver usando VMs, tire um **snapshot antes da instalação** nos dois servidores. É a forma mais rápida de voltar ao estado inicial para testar novamente.

---

## Arquivos do repositório

| Arquivo                    | Onde usar            | Descrição                                        |
|----------------------------|----------------------|--------------------------------------------------|
| `install_zabbix7_db.bash`  | Servidor de banco    | Instala e configura o PostgreSQL                 |
| `install_zabbix7_app.bash` | Servidor da aplicação| Instala Zabbix Server, Frontend e Agent 2        |
| `.env.db.example`          | Servidor de banco    | Modelo de parâmetros do banco                    |
| `.env.app.example`         | Servidor da aplicação| Modelo de parâmetros da aplicação                |
| `.gitignore`               | —                    | Impede que o `.env` (com a senha) vá para o repositório |

---

## Instalação

> ⚠️ **A ordem importa:** primeiro o **banco**, depois a **aplicação**. O script da aplicação conecta no banco para criar as tabelas.
>
> ⚠️ **A senha (`ZBX_DB_PASS`) deve ser a mesma nos dois servidores.**

### Passo 1 — Servidor de banco

```bash
git clone https://github.com/<seu-usuario>/<seu-repositorio>.git
cd <seu-repositorio>

cp .env.db.example .env
nano .env            # defina ZBX_APP_IP e ZBX_DB_PASS
chmod 600 .env

sudo bash install_zabbix7_db.bash
```

Ao final, o script mostra o IP do banco e o que deve ser preenchido no `.env` da aplicação.

### Passo 2 — Servidor da aplicação

```bash
git clone https://github.com/<seu-usuario>/<seu-repositorio>.git
cd <seu-repositorio>

cp .env.app.example .env
nano .env            # defina ZBX_DB_HOST e ZBX_DB_PASS (a mesma do banco)
chmod 600 .env

sudo bash install_zabbix7_app.bash
```

Antes de instalar qualquer coisa no banco, o script **testa a conexão**. Se falhar, ele para e indica o que verificar.

---

## Parâmetros (.env)

Cada script lê automaticamente o arquivo `.env` que estiver **na mesma pasta** dele. Como são servidores diferentes, cada um tem o **seu próprio** `.env`.

### Servidor de banco — `.env.db.example`

```env
ZBX_APP_IP=10.0.0.20
ZBX_DB_PASS=sua_senha_aqui
ZBX_DB_NAME=zabbix
ZBX_DB_USER=zabbix
ZBX_DB_PORT=5432
ZBX_TZ=America/Sao_Paulo
```

### Servidor da aplicação — `.env.app.example`

```env
ZBX_DB_HOST=10.0.0.10
ZBX_DB_PASS=sua_senha_aqui
ZBX_DB_NAME=zabbix
ZBX_DB_USER=zabbix
ZBX_DB_PORT=5432
ZBX_TZ=America/Sao_Paulo
ZBX_NAME=zbxserver
```

### Referência

| Variável      | Banco | Aplicação | Descrição                                          | Padrão              |
|---------------|:-----:|:---------:|----------------------------------------------------|---------------------|
| `ZBX_APP_IP`  | ✅    |           | IP da aplicação — único liberado no PostgreSQL     | *(perguntado)*      |
| `ZBX_DB_HOST` |       | ✅        | IP ou hostname do servidor de banco                | *(perguntado)*      |
| `ZBX_DB_PASS` | ✅    | ✅        | Senha do usuário do banco — **igual nos dois**     | *(perguntada)*      |
| `ZBX_DB_NAME` | ✅    | ✅        | Nome do banco                                      | `zabbix`            |
| `ZBX_DB_USER` | ✅    | ✅        | Usuário do banco                                   | `zabbix`            |
| `ZBX_DB_PORT` | ✅    | ✅        | Porta do PostgreSQL                                | `5432`              |
| `ZBX_TZ`      | ✅    | ✅        | Fuso horário do sistema (e do PHP, na aplicação)   | `America/Sao_Paulo` |
| `ZBX_NAME`    |       | ✅        | Nome exibido no frontend                           | hostname da máquina |

### Por que os dois servidores têm parâmetros do banco?

Os valores são os mesmos, mas o uso é diferente:

- **No banco**, eles servem para **criar** o banco, o usuário e a senha.
- **Na aplicação**, eles servem para **conectar**: o Zabbix Server e o Frontend gravam e leem dados no banco o tempo todo e precisam do endereço, usuário e senha.

É como uma conta de e-mail: um lado cria a conta, o outro faz login com os mesmos dados.

### Regras do `.env`

- O `.env` é **opcional**. Sem ele, o script usa os valores padrão e **pergunta** os IPs e a senha.
- Valores com ou sem aspas: `ZBX_DB_PASS=abc`, `"abc"` ou `'abc'`.
- Linhas em branco e comentários (`#`) são ignorados.
- A senha aceita caracteres especiais (`$`, `!`, `#`, `@`...), **exceto aspas simples (`'`)**.
- Arquivos editados no Windows (CRLF) funcionam normalmente.

**Arquivo em outro local:**

```bash
sudo bash install_zabbix7_app.bash --env /root/zabbix-app.env
```

**Prioridade dos valores:**

```
variável na linha de comando  >  arquivo .env  >  valor padrão
```

```bash
# exemplo: sobrescrever só o nome exibido
sudo ZBX_NAME=zabbix-teste bash install_zabbix7_app.bash
```

---

## O que cada script faz

### `install_zabbix7_db.bash` (banco)

1. Carrega o `.env` e verifica root / Ubuntu
2. Sincroniza o relógio (NTP) e aguarda o apt ficar livre
3. Instala o PostgreSQL e ajusta locale e fuso horário
4. Cria o usuário e o banco do Zabbix
5. Configura o PostgreSQL para aceitar conexões de rede (`listen_addresses`)
6. No `pg_hba.conf`, libera acesso **somente** para `ZBX_APP_IP`, apenas ao banco e usuário do Zabbix, com `scram-sha-256`
7. Se o UFW estiver ativo, libera a porta 5432 **apenas** para o IP da aplicação

Log: `/var/log/zabbix_db_install_<data>_<hora>.log`

### `install_zabbix7_app.bash` (aplicação)

1. Carrega o `.env` e verifica root / Ubuntu
2. Sincroniza o relógio (NTP) e aguarda o apt ficar livre
3. Adiciona o repositório oficial do Zabbix 7.0
4. Instala Zabbix Server, Frontend, Agent 2, Apache, PHP-FPM e o **cliente** PostgreSQL
5. **Testa a conexão** com o banco remoto
6. Importa o schema do Zabbix pela rede (somente se ainda não existir)
7. Configura o `zabbix_server.conf` e o `zabbix.conf.php` apontando para o banco remoto
8. Configura Apache (`proxy`, `proxy_fcgi`) e PHP-FPM — **o assistente web é pulado**
9. Se o UFW estiver ativo, libera as portas 80, 443, 10050 e 10051
10. Inicia os serviços e mostra o status de cada um

Log: `/var/log/zabbix_app_install_<data>_<hora>.log`

---

## Após a instalação

**Acesso ao frontend**

```
http://IP-DA-APLICAÇÃO/zabbix
```

| Usuário | Senha    |
|---------|----------|
| `Admin` | `zabbix` |

> ⚠️ **Troque a senha do Admin imediatamente**: *User settings → Profile → Change password*.

**Validar a comunicação com o banco**

No painel inicial, o widget **System information** deve mostrar **Zabbix server is running: Yes**.

**Portas utilizadas**

| Servidor  | Porta | Origem permitida    | Uso                                       |
|-----------|-------|---------------------|-------------------------------------------|
| Banco     | 5432  | IP da aplicação     | PostgreSQL                                |
| Aplicação | 80    | Usuários            | Frontend web (HTTP)                       |
| Aplicação | 443   | Usuários            | Frontend web (HTTPS, se configurado)      |
| Aplicação | 10050 | —                   | Zabbix Agent local                        |
| Aplicação | 10051 | Agentes / proxies   | Recebe dados de agentes ativos e proxies  |

**Verificar os serviços**

```bash
# servidor de banco
systemctl status postgresql

# servidor da aplicação
systemctl status zabbix-server zabbix-agent2 apache2 'php*-fpm'
```

---

## Executar novamente

Os dois scripts podem ser executados mais de uma vez:

- **Banco:** o banco não é recriado se já existir; a senha do usuário é atualizada.
- **Aplicação:** o schema não é reimportado se as tabelas já existirem; o `zabbix_server.conf` é atualizado.
- O arquivo do frontend `/etc/zabbix/web/zabbix.conf.php` **é mantido** se já existir.

> ⚠️ Se você **mudar a senha** e rodar de novo, o frontend continuará com a senha antiga e mostrará erro de conexão. Edite a senha em `/etc/zabbix/web/zabbix.conf.php` no servidor da aplicação.

---

## Solução de problemas

Quando algo falha, o script mostra na tela as **últimas linhas do log**. Para ver o log mais recente completo:

```bash
ls -t /var/log/zabbix_*_install_*.log | head -1 | xargs less
```

### `Release file ... is not valid yet`

O relógio do servidor está errado. O script tenta corrigir sozinho, mas se o NTP estiver bloqueado na rede:

```bash
timedatectl                       # veja "System clock synchronized"
sudo timedatectl set-ntp true
sudo date -s "$(curl -sI http://archive.ubuntu.com/ubuntu/ | grep -i '^date:' | cut -d' ' -f2-)"
```

Em VMs, confira também a hora do **host** (VMware, Hyper-V, Proxmox).

### `Could not get lock /var/lib/dpkg/lock-frontend`

As atualizações automáticas do Ubuntu estão rodando (comum logo após acertar o relógio). O script espera até 10 minutos. Se passar disso, aguarde terminar e rode de novo:

```bash
pgrep -af unattended-upgr
```

> Não mate o processo com `kill` — isso pode deixar pacotes corrompidos.

### Aplicação não conecta no banco

Teste a partir do servidor da aplicação:

```bash
psql -h IP-DO-BANCO -U zabbix -d zabbix -c "SELECT 1;"
```

| Mensagem                                | Causa provável                                                  |
|-----------------------------------------|-----------------------------------------------------------------|
| `Connection refused` / `timeout`        | Firewall bloqueando a 5432, ou PostgreSQL parado no banco       |
| `no pg_hba.conf entry for host`         | `ZBX_APP_IP` no banco diferente do IP real da aplicação         |
| `password authentication failed`        | Senha diferente entre os dois `.env`                            |

Para corrigir o IP liberado, rode novamente o script do banco com o `ZBX_APP_IP` certo.

### Apache não inicia

```bash
sudo a2enmod proxy proxy_fcgi setenvif
sudo apache2ctl configtest
sudo systemctl restart apache2
```

### Aviso sobre versão do PostgreSQL

O Zabbix 7.0 suporta oficialmente o PostgreSQL até a versão 17. Se o Ubuntu instalar uma versão mais nova, o script da aplicação habilita `AllowUnsupportedDBVersions=1` para o Zabbix Server iniciar. Funciona, mas **não é uma combinação oficialmente suportada**. Para produção, prefira o PostgreSQL 16 ou 17 pelo [repositório oficial do PostgreSQL (PGDG)](https://www.postgresql.org/download/linux/ubuntu/).

### O script pediu a senha mesmo com o `.env`

O `.env` não está na mesma pasta do script ou o nome está diferente. Confira com `ls -la`.

---

## Segurança

- **Nunca envie o `.env` para o repositório.** Ele está no `.gitignore`; envie apenas os `.env.*.example`.
- Mantenha o `.env` com permissão `600` (`chmod 600 .env`).
- O banco aceita conexões **somente** do IP da aplicação.
- A conexão entre os servidores **não é criptografada**. Em redes internas isso costuma ser aceitável; se o tráfego passar por redes não confiáveis, habilite SSL no PostgreSQL.
- Troque a senha padrão do usuário `Admin` após a instalação.
- Se o frontend for acessado fora da rede local, configure **HTTPS** no Apache.
