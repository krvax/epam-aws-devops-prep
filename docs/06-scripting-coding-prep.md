# 💻 Guía de Preparación: Scripting & Coding (DevOps)

Esta sección está diseñada para ayudarte a superar el miedo a la prueba de coding, enfocándote en los problemas reales que se preguntan en entrevistas de EPAM para roles de SRE/DevOps.

## 🎯 El Enfoque Correcto
En DevOps, no se busca que seas un desarrollador de algoritmos complejos (LeetCode Hard), sino que seas capaz de **automatizar tareas** y **manipular datos**.

### Lenguajes sugeridos
1. **Python** (Altamente recomendado para EPAM)
2. **Bash** (Indispensable para tareas de sistema)

---

## 📋 Temas Frecuentes en EPAM

### 1. Manipulación de Logs y Texto
*   **Problema:** Leer un archivo de log y contar cuántas peticiones hubo por cada código de estado (200, 404, 500).
*   **Habilidad:** Diccionarios en Python, manejo de strings, `split()`.

### 2. Consumo de APIs (AWS SDK / Boto3)
*   **Problema:** Listar todas las instancias EC2 que no tengan el tag "Environment" y detenerlas.
*   **Habilidad:** Uso de la librería `boto3`, bucles `for`, condicionales `if`.

### 3. Procesamiento de JSON/YAML
*   **Problema:** Dado un JSON de configuración, filtrar ciertos valores y generar un nuevo archivo.
*   **Habilidad:** Librerías `json` y `yaml` en Python.

### 4. Scripts de Sistema (Bash)
*   **Problema:** Crear un script que verifique si un proceso está corriendo, y si no, que lo inicie y mande una alerta.
*   **Habilidad:** `ps`, `grep`, `systemctl`, variables de entorno.

---

## 🛠️ Ejercicios Prácticos (Empieza aquí)

### Ejercicio 1: El Analizador de Logs (Python)
Crea un script que lea un archivo llamado `access.log` con este formato:
`192.168.1.1 - - [10/Apr/2024:10:00:00] "GET /home HTTP/1.1" 200 1234`

**Objetivo:** Imprimir el total de errores 5xx.

### Ejercicio 2: Boto3 Janitor (Python)
**Objetivo:** Identificar buckets de S3 que no tengan habilitado el versionamiento.

---

## 💡 Tips para el día de la prueba
1.  **Habla mientras programas:** Explica tu lógica. A veces les importa más tu proceso de pensamiento que si el código compila a la primera.
2.  **KISS (Keep It Simple, Stupid):** No intentes usar librerías complejas si no las dominas. Un script legible es mejor que uno "fancy".
3.  **Manejo de errores:** Usa bloques `try-except`. Demuestra que te importa la estabilidad del script.
4.  **Si te bloqueas:** Sé honesto. "Sé que necesito usar la función X de la librería Y, pero no recuerdo los parámetros exactos. ¿Puedo consultar la documentación rápida?" (Casi siempre dicen que sí).

---

## 📚 Recursos para practicar
*   **Exercism (Python Track):** Muy bueno para lógica básica.
*   **Boto3 Documentation:** Familiarízate con la estructura de respuesta de `describe_instances`.
*   **Python for DevOps (Libro):** Capítulos sobre automatización de sistema.
