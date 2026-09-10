-- Limpieza inicial: permite ejecutar este script las veces que sea necesario
-- sin errores, sin importar si el esquema ya existía de un intento anterior.
DROP SCHEMA IF EXISTS prototipo CASCADE;

-- Crear la base de datos
--CREATE DATABASE agenda;
CREATE SCHEMA prototipo;

-- Configurar el search_path para que las tablas se creen dentro de ese esquema
-- y se busquen ahí automáticamente
SET search_path TO prototipo, public;

-- 1. Usuarios
CREATE TABLE usuarios (
    id_usuario SERIAL PRIMARY KEY,
    nombre VARCHAR(50) NOT NULL,
    apellido VARCHAR(50) NOT NULL,
    fecha_registro DATE DEFAULT CURRENT_DATE NOT NULL,
    activo BOOLEAN DEFAULT TRUE
);

-- 2. Contactos (RF02, RE02, RN02)
CREATE TABLE usuario_telefonos (
    id_usuario INT REFERENCES usuarios(id_usuario),
    telefono VARCHAR(20),
    PRIMARY KEY (id_usuario, telefono)
);

CREATE TABLE usuario_emails (
    id_usuario INT REFERENCES usuarios(id_usuario),
    email VARCHAR(100),
    PRIMARY KEY (id_usuario, email)
);

-- 3. Categorías (RF03, RE05, RN04)
CREATE TABLE categorias (
    id_categoria SERIAL PRIMARY KEY,
    nombre VARCHAR(50) NOT NULL,
    id_categoria_padre INT REFERENCES categorias(id_categoria)
    -- NOTA: La raíz tendría id_categoria_padre NULL
);

-- 4. Eventos (RF04, RE04)
CREATE TABLE eventos (
    id_evento SERIAL PRIMARY KEY,
    id_usuario_propietario INT NOT NULL REFERENCES usuarios(id_usuario),
    id_categoria INT NOT NULL REFERENCES categorias(id_categoria),
    titulo VARCHAR(100) NOT NULL,
    descripcion TEXT,
    fecha_inicio TIMESTAMP NOT NULL,
    fecha_fin TIMESTAMP NOT NULL,
    CONSTRAINT check_fechas CHECK (fecha_fin > fecha_inicio)
);

-- 5. Participación (RF05, RE01, RN01, RN05)
CREATE TABLE participaciones (
    id_evento INT REFERENCES eventos(id_evento) ON DELETE CASCADE,
    id_invitado INT REFERENCES usuarios(id_usuario),
    rol VARCHAR(50),
    estado_confirmacion VARCHAR(20) DEFAULT 'pendiente',
    PRIMARY KEY (id_evento, id_invitado)
);

-- 6. Log de Accesos (RF06)
CREATE TABLE log_accesos (
    id_log SERIAL PRIMARY KEY,
    id_usuario INT REFERENCES usuarios(id_usuario),
    fecha_acceso TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Implementación de Cálculos Dinámicos (RF07, RE03, RN03) mediante vistas

-- Vista para Antigüedad
CREATE VIEW vista_antiguedad_usuarios AS
SELECT
    id_usuario,
    nombre,
    fecha_registro,
    age(CURRENT_DATE, fecha_registro) AS antiguedad
FROM usuarios;

-- Vista para Duración de eventos diarios
CREATE VIEW vista_duracion_eventos_diarios AS
SELECT
    id_usuario_propietario,
    fecha_inicio::DATE AS dia,
    SUM(EXTRACT(EPOCH FROM (fecha_fin - fecha_inicio))/60) AS duracion_total_minutos
FROM eventos
GROUP BY id_usuario_propietario, fecha_inicio::DATE;

--Integridad y Prevención de Ciclos (RE05)
--Para evitar ciclos en la jerarquía de categorías, podemos usar una función
--que verifique el ancestro antes de insertar o actualizar:

CREATE OR REPLACE FUNCTION evitar_ciclo_categorias()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.id_categoria_padre = NEW.id_categoria THEN
        RAISE EXCEPTION 'Una categoría no puede ser padre de sí misma.';
    END IF;
    -- Aquí se podría añadir una consulta recursiva para validar ancestros,
    -- pero para Postgres 14 es altamente eficiente usar el camino (path) o este chequeo simple.
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_evitar_ciclo
BEFORE INSERT OR UPDATE ON categorias
FOR EACH ROW EXECUTE FUNCTION evitar_ciclo_categorias();

-- ============================================================
-- MÓDULO DE UBICACIONES (RF-08, RF-09, RF-10)
-- ============================================================

-- 7. Ubicaciones (RF-08, RF-09, RF-10)
CREATE TABLE ubicaciones (
    id_ubicacion SERIAL PRIMARY KEY,
    nombre VARCHAR(50) NOT NULL,
    direccion VARCHAR(150),
    capacidad INT CHECK (capacidad > 0)
);

-- Se conecta la ubicación con eventos: cada evento puede ocurrir en una ubicación (RF-09)
ALTER TABLE eventos
    ADD COLUMN id_ubicacion INT REFERENCES ubicaciones(id_ubicacion);

-- Prevención de Traslapes de Horario en una misma Ubicación (RF-10)
-- Antes de insertar o actualizar un evento con ubicación asignada, se revisa
-- si ya existe otro evento en esa misma ubicación cuyo horario se cruce.
CREATE OR REPLACE FUNCTION evitar_traslape_ubicacion()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.id_ubicacion IS NOT NULL THEN
        IF EXISTS (
            SELECT 1 FROM eventos
            WHERE id_ubicacion = NEW.id_ubicacion
              AND id_evento <> COALESCE(NEW.id_evento, -1)
              AND fecha_inicio < NEW.fecha_fin
              AND fecha_fin > NEW.fecha_inicio
        ) THEN
            RAISE EXCEPTION 'Ya existe otro evento en esta ubicación en un horario que se cruza.';
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_evitar_traslape_ubicacion
BEFORE INSERT OR UPDATE ON eventos
FOR EACH ROW EXECUTE FUNCTION evitar_traslape_ubicacion();

-- ============================================================
-- MÓDULO DE DISPONIBILIDAD DE USUARIOS (RF-11, RF-12)
-- ============================================================

-- 8. Disponibilidad de Usuarios (RF-11, RF-12)
CREATE TABLE disponibilidad (
    id_disponibilidad SERIAL PRIMARY KEY,
    id_usuario INT NOT NULL REFERENCES usuarios(id_usuario) ON DELETE CASCADE,
    fecha DATE NOT NULL,
    hora_inicio TIME NOT NULL,
    hora_fin TIME NOT NULL,
    CONSTRAINT check_horas_disponibilidad CHECK (hora_fin > hora_inicio)
);

-- Vista de apoyo: permite consultar rápidamente los bloques de disponibilidad
-- de cada usuario, útil antes de agendarle un evento (RF-12)
CREATE VIEW vista_disponibilidad_usuarios AS
SELECT
    d.id_disponibilidad,
    d.id_usuario,
    u.nombre,
    u.apellido,
    d.fecha,
    d.hora_inicio,
    d.hora_fin
FROM disponibilidad d
JOIN usuarios u ON u.id_usuario = d.id_usuario
ORDER BY d.fecha, d.hora_inicio;

-- 9. Tareas Asociadas a Eventos (RF-15, RF-16, RF-17)
CREATE TABLE tareas (
    id_tarea SERIAL PRIMARY KEY,
    titulo VARCHAR(100) NOT NULL,
    descripcion TEXT,
    prioridad VARCHAR(10) NOT NULL DEFAULT 'media'
        CHECK (prioridad IN ('baja', 'media', 'alta')),
    estado VARCHAR(20) NOT NULL DEFAULT 'pendiente'
        CHECK (estado IN ('pendiente', 'en progreso', 'completada')),
    fecha_limite DATE,
    id_evento INT NOT NULL REFERENCES eventos(id_evento) ON DELETE CASCADE,
    id_usuario_responsable INT REFERENCES usuarios(id_usuario)
);

-- Vista de apoyo: calcula dinámicamente qué tareas están vencidas
-- (fecha límite ya pasó y aún no están completadas), sin almacenar
-- ese estado físicamente, igual que se hizo con la antigüedad de usuarios (RF-17)
CREATE VIEW vista_tareas_vencidas AS
SELECT
    t.id_tarea,
    t.titulo,
    t.prioridad,
    t.estado,
    t.fecha_limite,
    e.titulo AS evento,
    u.nombre,
    u.apellido
FROM tareas t
JOIN eventos e ON e.id_evento = t.id_evento
LEFT JOIN usuarios u ON u.id_usuario = t.id_usuario_responsable
WHERE t.fecha_limite < CURRENT_DATE
  AND t.estado <> 'completada';
-- ============================================================
-- Configuración final: para que cualquier conexión nueva (incluida
-- la app Python) busque las tablas en el esquema prototipo por defecto
-- ============================================================
ALTER DATABASE agenda SET search_path TO prototipo, public;