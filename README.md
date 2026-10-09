# JAT

---

Script feito para automatizar e facilitar a manutenção de uma distro linux.

Funções:

- identificar erros
- limpar e monitorar armazenamento  
- instalar ferramentas de desenvolvimento

Aviso: 

Cobre distros baseadas em ARCH.
a ferramenta para instalar ferramentas de desenvolvimento Funciona via MISE e serve para outras distros.
Tudo isso usando de Git-presets com pacotes selecionados por sua distro
(VOCÊ deve CRIAR seu preset).

___


### Movendo para o `/bin`
```
cp arch-clean-tui.sh ~/.local/bin/dev-tools
chmod +x ~/.local/bin/dev-tools
```


### Exportando para o `$PATH`
```
export PATH="$HOME/.local/bin:$PATH"
```


### Comando Geral 
```
dev-tools
```


### Alterar nome da ferramenta

O nome pode ser alterado no comando:

```
cp arch-clean-tui.sh ~/.local/bin/qualquer-nome

```


### Configurar `Git-presets`
### 1. Estrutura do Repositório Central de Pacotes

Crie um repositório no GitHub ou GitLab (ex: `[https://github.com/seu-usuario/dev-environments](https://github.com/seu-usuario/dev-environments)`) contendo uma estrutura simples em arquivos de texto.

A abordagem mais limpa e manutenível é organizar por **stack** e, opcionalmente, com subpastas por família de distro (ou listas universais):

Exemplo:

```
dev-environments/
├── arch/
│   ├── web.txt
│   ├── desktop.txt
│   └── devops.txt
├── debian/
│   ├── web.txt
│   ├── desktop.txt
│   └── devops.txt
└── fedora/
    ├── web.txt
    ├── desktop.txt
    └── devops.txt
```

Dentro de cada arquivo (ex: `arch/web.txt`), liste um pacote por linha com uma descrição separada por pipe (`|`):

Exemplo de arquivo:

```
nodejs|Ambiente de execução JavaScript
npm|Gerenciador de pacotes Node
pnpm|Gerenciador rápido e com economia de disco
postgresql|SGBD relacional robusto
dbeaver|GUI universal para bancos de dados
docker|Plataforma de containers
docker-compose|Orquestração de múltiplos containers
```

