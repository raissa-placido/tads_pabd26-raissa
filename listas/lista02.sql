-- Questão 01 - View de Performance da Equipe

DROP VIEW IF EXISTS v_staff_performance;
CREATE VIEW v_staff_performance AS
SELECT 
    s.staff_id,
    CONCAT(s.first_name, ' ', s.last_name) AS full_name,
    CONCAT(ci.city, ', ', co.country) AS store_location,
    COALESCE(r.total_rentals, 0) AS total_rentals,
    COALESCE(p.total_amount, 0.00) AS total_amount
FROM staff s
LEFT JOIN store st ON s.store_id = st.store_id
LEFT JOIN address a ON st.address_id = a.address_id
LEFT JOIN city ci ON a.city_id = ci.city_id
LEFT JOIN country co ON ci.country_id = co.country_id
LEFT JOIN (
    SELECT staff_id, COUNT(rental_id) AS total_rentals
    FROM rental
    GROUP BY staff_id
) r ON s.staff_id = r.staff_id
LEFT JOIN (
    SELECT staff_id, SUM(amount) AS total_amount
    FROM payment
    GROUP BY staff_id
) p ON s.staff_id = p.staff_id;

-- Consulta de Validação
SELECT * FROM v_staff_performance;

## Questão 02 - View Materializada de Receita por Categoria

CREATE MATERIALIZED VIEW mv_category_total_sales AS
SELECT 
    c.category_id,
    c.name AS category_name,
    COALESCE(SUM(p.amount), 0.00) AS total_revenue
FROM category c
JOIN film_category fc ON c.category_id = fc.category_id
JOIN inventory i ON fc.film_id = i.film_id
JOIN rental r ON i.inventory_id = r.inventory_id
JOIN payment p ON r.rental_id = p.rental_id
GROUP BY c.category_id, c.name;

-- Índice único obrigatório para permitir a atualização CONCURRENTLY
CREATE UNIQUE INDEX idx_mv_category_total_sales_id ON mv_category_total_sales (category_id);

-- Comando para recarregar sem bloquear consultas concorrentes
REFRESH MATERIALIZED VIEW CONCURRENTLY mv_category_total_sales;

-- Consulta de Validação
SELECT * FROM mv_category_total_sales ORDER BY total_revenue DESC;


## Questão 03 - Otimizando Filmes Atrasados

-- Criação do Índice Parcial apenas para locações sem data de devolução
CREATE INDEX idx_rental_open_rentals 
ON rental (rental_date) 
WHERE return_date IS NULL;

-- Consulta otimizada com verificação de plano de execução
EXPLAIN ANALYZE
SELECT rental_id, customer_id, rental_date, staff_id
FROM rental
WHERE return_date IS NULL;

## Questão 04 - Busca Inteligente de Sinopses

CREATE INDEX idx_film_description_fts 
ON film USING gin (to_tsvector('english', description));

-- Consulta buscando 'documentary' E 'drama' na sinopse
EXPLAIN ANALYZE
SELECT film_id, title, description
FROM film
WHERE to_tsvector('english', description) @@ to_tsquery('english', 'documentary & drama');

## Questão 05 - Histórico do Cliente

CREATE INDEX idx_payment_customer_date 
ON payment (customer_id, payment_date DESC);

--Por que a coluna customer_id deve vir primeiro?

-- R: A coluna customer_id é utilizada no filtro de igualdade (WHERE customer_id = X). Colocando-a em primeiro lugar, o PostgreSQL realiza a busca exata pela chave do cliente e, em seguida, percorre as folhas do índice já ordenadas pela segunda coluna (payment_date DESC). Isso elimina a necessidade de uma etapa explícita de ordenação em memória, otimizando diretamente a consulta.

## Questão 06 - Login Case-Insensitive

-- Criação do Índice Funcional
CREATE INDEX idx_customer_lower_email 
ON customer (LOWER(email));

-- Consulta utilizando a mesma função do índice
EXPLAIN ANALYZE
SELECT customer_id, first_name, last_name, email
FROM customer
WHERE LOWER(email) = LOWER('MARY.SMITH@sakilacustomer.org');

## Questão 07 - Validação de Datas

-- 1. Função da Trigger
CREATE OR REPLACE FUNCTION check_rental_dates()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.return_date IS NOT NULL AND NEW.return_date < NEW.rental_date THEN
        RAISE EXCEPTION 'Erro de validação: A data de devolução (%) não pode ser anterior à data de locação (%).', 
            NEW.return_date, NEW.rental_date;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 2. Criação da Trigger
CREATE TRIGGER trg_check_rental_dates
BEFORE INSERT OR UPDATE ON rental
FOR EACH ROW
EXECUTE FUNCTION check_rental_dates();

-- 3. Consulta Teste 1: Falha esperada (return_date < rental_date)
-- Deve retornar erro: "Erro de validação..."
INSERT INTO rental (rental_date, inventory_id, customer_id, return_date, staff_id)
VALUES ('2026-10-10 10:00:00', 1, 1, '2026-10-09 10:00:00', 1);

-- 4. Consulta Teste 2: Sucesso esperado (
INSERT INTO rental (rental_date, inventory_id, customer_id, return_date, staff_id)
VALUES ('2026-10-10 10:00:00', 1, 1, '2026-10-12 10:00:00', 1);

## Questão 08 - Auditoria de Preços

-- 1. Tabela de Auditoria
CREATE TABLE film_cost_audit (
    audit_id SERIAL PRIMARY KEY,
    film_id INT NOT NULL,
    old_cost NUMERIC(5,2),
    new_cost NUMERIC(5,2),
    changed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 2. Função da Trigger
CREATE OR REPLACE FUNCTION log_film_cost_change()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO film_cost_audit (film_id, old_cost, new_cost, changed_at)
    VALUES (NEW.film_id, OLD.replacement_cost, NEW.replacement_cost, NOW());
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 3. Trigger com cláusula WHEN (dispara apenas na alteração do valor)
CREATE TRIGGER trg_audit_film_cost
AFTER UPDATE ON film
FOR EACH ROW
WHEN (OLD.replacement_cost IS DISTINCT FROM NEW.replacement_cost)
EXECUTE FUNCTION log_film_cost_change();

-- Validação:
-- Teste A: Atualizando replacement_cost (deve gerar registro na tabela de auditoria)
UPDATE film SET replacement_cost = 25.99 WHERE film_id = 1;
SELECT * FROM film_cost_audit;

-- Teste B: Atualizando título sem alterar o custo (não deve gerar novo registro)
UPDATE film SET title = 'ACADEMY DINOSAUR UPDATED' WHERE film_id = 1;
SELECT * FROM film_cost_audit;

## Questão 09 - Proteção de Catálogo

-- 1. Função da Trigger

DROP TRIGGER IF EXISTS trg_prevent_language_deletion ON language;
DROP FUNCTION IF EXISTS prevent_language_deletion();
CREATE FUNCTION prevent_language_deletion()
RETURNS TRIGGER AS $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM film 
        WHERE language_id = OLD.language_id 
    ) THEN
        RAISE EXCEPTION 'Não é possível excluir o idioma "%": existem filmes vinculados a ele.', TRIM(OLD.name);
    END IF;
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

-- 2. Trigger

CREATE TRIGGER trg_prevent_language_deletion
BEFORE DELETE ON language
FOR EACH ROW
EXECUTE FUNCTION prevent_language_deletion();

## Questão 10 - Sincronização de Estatísticas

-- 1. Tabela de Estatísticas
CREATE TABLE customer_rental_stats (
    customer_id INT PRIMARY KEY,
    total_rentals INT DEFAULT 0
);

-- 2. Carga Inicial
INSERT INTO customer_rental_stats (customer_id, total_rentals)
SELECT customer_id, COUNT(rental_id)
FROM rental
GROUP BY customer_id;

-- 3. Função da Trigger (Soma simples +1)
CREATE OR REPLACE FUNCTION sync_customer_rental_stats()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE customer_rental_stats 
    SET total_rentals = total_rentals + 1
    WHERE customer_id = NEW.customer_id;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 4. Trigger
CREATE TRIGGER trg_sync_customer_rental_stats
AFTER INSERT ON rental
FOR EACH ROW
EXECUTE FUNCTION sync_customer_rental_stats();