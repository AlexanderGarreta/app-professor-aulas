# Ativação da sincronização com Google Agenda

Antes de instalar a versão 1.1.0 do ProfEconomy, aplique a migração no
Supabase:

1. Entre em https://supabase.com/dashboard.
2. Abra o projeto usado pelo ProfEconomy.
3. No menu esquerdo, abra **SQL Editor**.
4. Clique em **New query**.
5. Copie todo o conteúdo de
   `supabase/migrations/20260921_google_calendar_sync.sql`.
6. Cole no editor e clique em **Run**.
7. Confirme que aparece a mensagem **Success. No rows returned**.

A migração apenas acrescenta campos de sincronização à tabela `aulas`; ela não
apaga aulas, alunos, pacotes ou cobranças existentes.

Na primeira abertura do aplicativo atualizado, conecte a mesma conta Google já
usada no ProfEconomy e toque no botão de nuvem. Para aulas antigas, o aplicativo
procura primeiro um evento com o mesmo aluno, data e horário. Ele somente cria
um novo evento quando não encontra um correspondente.
