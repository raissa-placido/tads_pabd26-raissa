/*
    DESAFIO 02 - TRANSAÇÕES
*/

-- ==================================================
-- Questão 1 - Cadastro de Cliente e Perfil
-- ==================================================

begin;

-- Inserção inicial do cliente
insert into customer (store_id, first_name, last_name, address_id, active)
values (1, 'Raissa', 'Placido', 1, 1);

select customer_id, first_name, last_name
from customer
order by customer_id desc limit 5;

-- ERRO: first_name não pode ser NULL
insert into customer (store_id, first_name, last_name, address_id, active)
values (1, null, 'Teste', 1, 1);

rollback;

select customer_id, first_name, last_name
from customer
order by customer_id desc limit 5;

-- Resposta: o primeiro cliente não permanece cadastrado.
-- O ROLLBACK desfaz todas as alterações feitas pela transação antes do commit com sucesso.
-- Isso garante que o cadastro não fique incompleto ou incoerente.


-- ==================================================
-- Questão 2 - Gestão de Estoque e Suprimentos
-- ==================================================

begin;

-- Primeiro registro válido
insert into inventory (film_id, store_id)
values (1, 1);

savepoint estoque_atualizado;

-- ERRO: o film_id informado não existe
insert into inventory (film_id, store_id)
values (999999, 1);

-- Desfaz apenas a tentativa com erro
rollback to estoque_atualizado;

-- Outro registro válido
insert into inventory (film_id, store_id)
values (1, 2);

commit;

select inventory_id, film_id, store_id
from inventory
order by inventory_id desc limit 5;

-- Resposta: após o COMMIT, permanecem os dois registros válidos.
-- O SAVEPOINT permite desfazer somente a operação com erro,
-- preservando as alterações anteriores e evitando o ROLLBACK da transação inteira.

