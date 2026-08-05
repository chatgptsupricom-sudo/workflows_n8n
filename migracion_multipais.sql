-- ============================================================
-- Migración: Soporte Multi-País (Venezuela + Panamá)
-- Ejecutar en orden. Hacer backup antes de aplicar.
-- ============================================================

-- 1. Agregar columna pais a sellers
ALTER TABLE sellers
  ADD COLUMN pais VARCHAR(10) NOT NULL DEFAULT 'VE' AFTER activo;

-- 2. Agregar columna pais a leads
ALTER TABLE leads
  ADD COLUMN pais VARCHAR(10) NOT NULL DEFAULT 'VE';

-- 3. Stored procedure para Panamá (round-robin por conteo, sin split regional)
DELIMITER //
CREATE PROCEDURE asignar_vendedor_rotacion_pa()
BEGIN
    DECLARE v_seller_id INT DEFAULT 0;
    DECLARE v_name VARCHAR(255) DEFAULT '';
    DECLARE v_asignacion INT DEFAULT 0;

    START TRANSACTION;

    SELECT id, name, asignaciones
    INTO v_seller_id, v_name, v_asignacion
    FROM sellers
    WHERE activo = 1 AND pais = 'PA'
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
END //
DELIMITER ;

-- ============================================================
-- Cuando se creen los vendedores de Panamá, usar este template:
-- INSERT INTO sellers (name, user_id, activo, pais, asignaciones, whatsapp, role)
-- VALUES ('Nombre Vendedor PA', <user_id>, 1, 'PA', 0, '+507XXXXXXXX', 7);
-- ============================================================
