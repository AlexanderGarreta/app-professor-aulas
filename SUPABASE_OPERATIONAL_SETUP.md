# Ativação da gestão operacional do ProfEconomy

Esta configuração é necessária antes de instalar a versão 1.2.0.

1. Entre em https://supabase.com/dashboard.
2. Abra o projeto usado pelo ProfEconomy.
3. No menu esquerdo, abra **SQL Editor**.
4. Clique em **New query**.
5. Abra o arquivo
   `supabase/migrations/20260924_operational_management.sql` no GitHub.
6. Copie todo o conteúdo do arquivo, cole no SQL Editor e clique em **Run**.
7. Confirme que a execução terminou sem mensagem vermelha de erro.

A migração:

- relaciona cada aula ao ciclo correto do pacote comprado;
- grava a duração de cada aula;
- identifica sequências de aulas fixas;
- registra confirmações automáticas;
- cria a rotina que conclui aulas após o horário de término;
- tenta habilitar a execução automática dessa rotina a cada minuto.

Ela não apaga alunos, aulas, pacotes ou cobranças existentes.

Se aparecer apenas o aviso de que `pg_cron` não pôde ser habilitado, abra
**Database > Extensions**, procure por `pg_cron`, habilite a extensão e execute
novamente a mesma consulta. Mesmo sem o cron, o aplicativo atualiza aulas
passadas sempre que a Agenda ou a Gestão forem abertas.
