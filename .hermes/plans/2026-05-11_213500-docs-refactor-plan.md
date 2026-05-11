---
name: docs-refactor-plan
description: "Refatorar documentação: README principal enxuto + docs/ com material detalhado"
version: 1.0.0
author: Hermes Agent
license: MIT
---

# Plano (enxuto): README.md principal menor + diretório docs/

Objetivo
- Reduzir o tamanho do `README.md` principal e mover conteúdo detalhado para `docs/`.
- Manter o fluxo de leitura: Quickstart no README; aprofundamento em docs auxiliares.

Estrutura proposta (docs/)
- docs/upgrade-rollback.md
- docs/architecture.md (descrição de módulos e fluxo)
- docs/configuration.md (variáveis principais, segredos, naming)
- docs/options-parameters-reference.md (ou apontar para arquivo atual se existir)
- docs/examples/
  - sqlserver.md
  - mysql.md
  - postgres.md
  - aurora-postgres.md
  - (pode começar só com 1 engine e expandir depois)

README.md principal (conteúdo mínimo)
- Visão geral (curta)
- Quickstart (como declarar o stack e rodar terraform)
- Configuração (lista de variáveis principais e links para docs)
- Upgrade/rollback (2-4 bullets + link para docs/upgrade-rollback.md)
- Estrutura de módulos (lista curta com links)
- Contribuição + Licença

Passos
1) Diagnóstico (read-only)
- Listar seções atuais do README.md principal e identificar trechos candidatos para mover.
2) Criar diretórios/arquivos em docs/
- Adicionar arquivos com conteúdo condensado (a partir do README atual).
3) Reduzir README.md principal
- Substituir exemplos e seções longas por links para docs.
4) Atualizar links/referências
- Garantir que links apontem para os novos arquivos.
5) Validação
- Checar que `terraform-docs` (se usado) ainda não sobrescreve o README principal indevidamente.

Critérios de aceitação
- README principal < ~250-400 linhas (meta ajustável).
- docs/ contém o material detalhado antes existente no README.
- Linkagem correta (sem links quebrados).

Riscos
- Possível duplicação de conteúdo ou links quebrados.
- `terraform-docs` pode sobrescrever README se estiver configurado; alinhar para não perder manualmente.

Próximo passo
- Implementar no branch feat/docs-and-justfile-improvements (ou criar novo branch feat/docs-refactor).
