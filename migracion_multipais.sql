-- ============================================================
-- Migración: Soporte Multi-País (Venezuela + Panamá)
-- Ejecutar en orden. Hacer backup antes de aplicar.
-- ============================================================

-- 1. Agregar columna pais a leads (vendors VE ya tienen cids diferente a 7)
--    Los vendedores de Panamá se identifican por cids = 7 en la tabla sellers,
--    por lo que NO es necesario agregar columna pais a sellers.
ALTER TABLE leads
  ADD COLUMN pais VARCHAR(10) NOT NULL DEFAULT 'VE';

-- 2. Stored procedure para Panamá (round-robin por conteo, cids = 7)
--    Nota: en phpMyAdmin pegar solo el bloque CREATE PROCEDURE sin DELIMITER
DROP PROCEDURE IF EXISTS asignar_vendedor_rotacion_pa;

CREATE PROCEDURE asignar_vendedor_rotacion_pa()
BEGIN
    DECLARE v_seller_id INT DEFAULT 0;
    DECLARE v_name VARCHAR(255) DEFAULT '';
    DECLARE v_asignacion INT DEFAULT 0;

    START TRANSACTION;

    SELECT id, name, asignaciones
    INTO v_seller_id, v_name, v_asignacion
    FROM sellers
    WHERE activo = 1 AND cids = 7
    ORDER BY asignaciones ASC, id ASC
    LIMIT 1
    FOR UPDATE;

    IF v_seller_id > 0 THEN
        UPDATE sellers
        SET asignaciones = asignaciones + 1
        WHERE id = v_seller_id;
    END IF;

    COMMIT;

    SELECT v_seller_id AS seller_id, v_name AS name, v_asignacion AS asignacion;
END;

-- ============================================================
-- Verificación post-migración:
-- SHOW PROCEDURE STATUS WHERE Name = 'asignar_vendedor_rotacion_pa';
-- SELECT id, name, cids, activo FROM sellers WHERE cids = 7;
-- ============================================================
