# Proyecto 1 - Ampliación de Base de Datos: Agenda Digital "Tres Patitos"

Ampliación de una base de datos y aplicación de agenda ya existente, agregando tres módulos nuevos de gestión mediante PostgreSQL y una interfaz de escritorio en Python.

## Módulos ampliados

| Módulo | Requerimientos | Descripción |
|---|---|---|
| **Ubicaciones** | RF-08, RF-09, RF-10 | Administra salas/recintos donde ocurren los eventos, con validación automática de traslapes de horario. |
| **Disponibilidad de Usuarios** | RF-11, RF-12 | Registra bloques de horario en que cada usuario está libre. |
| **Tareas Asociadas a Eventos** | RF-15, RF-16, RF-17 | Subtareas por evento, con responsable, prioridad, estado y cálculo dinámico de tareas vencidas. |

## Tecnologías

- **Base de datos:** PostgreSQL 18
- **Aplicación:** Python 

## Estructura del repositorio

```
proyecto1-agenda/
├── script.sql   # Script completo: esquema base + los 3 módulos de ampliación
├── agenda.py    # Aplicación de escritorio (interfaz gráfica)
└── README.md
```

## Cómo restaurar la base de datos

1. Instalar PostgreSQL 18+ y crear manualmente una base de datos llamada `agenda`.
2. Ejecutar `script.sql` completo sobre esa base (incluye `DROP SCHEMA IF EXISTS` al inicio, por lo que se puede correr repetidas veces sin error).
3. Verificar que se creó el esquema `prototipo` con las siguientes tablas:
   `usuarios`, `usuario_telefonos`, `usuario_emails`, `categorias`, `eventos`, `participaciones`, `log_accesos`, `ubicaciones`, `disponibilidad`, `tareas`.

## Cómo ejecutar la aplicación

1. Instalar dependencias:
   ```
   pip install customtkinter psycopg2-binary tkcalendar
   ```
2. Ajustar los parámetros de conexión (`conn_params`) en `agenda.py` según tu instalación local de PostgreSQL (usuario, contraseña, puerto).
3. Ejecutar:
   ```
   python agenda.py
   ```

## Funcionalidad de la interfaz

La aplicación cuenta con 6 pestañas, cada una con operaciones CRUD completas (crear, consultar, actualizar, eliminar):

- **Usuarios** — gestión de usuarios de la agenda.
- **Categorías** — categorías jerárquicas de eventos (padre/hijo).
- **Eventos** — programación de eventos, con propietario, categoría y ubicación.
- **Ubicaciones** — salas y espacios, con prevención de traslapes de horario.
- **Disponibilidad** — bloques de horario libre por usuario.
- **Tareas** — subtareas por evento, con responsable, prioridad y estado.
