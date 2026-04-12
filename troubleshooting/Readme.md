## Troubleshooting & Incident Reviews

Runbooks y post-mortems basados en incidentes reales en EKS, autenticación, networking y edge delivery.  
Cada documento incluye diagnóstico paso a paso y está pensado para reforzar troubleshooting técnico y preparación de entrevistas tipo STAR.

| Documento | Tipo | Descripción |
|-----------|------|-------------|
| [01-librechat-ingress](./01-librechat-ingress.md) | Runbook | Ingress no genera ALB en EKS por configuración o annotations incompletas |
| [02-jwt-dst-incident](./02-jwt-dst-incident.md) | Post-mortem | `TokenExpiredError` causado por desfase horario y cambio de DST |
| [03-eks-target-group-unhealthy](./03-eks-target-group-unhealthy.md) | Runbook | ALB creado correctamente, pero el Target Group reporta targets `unhealthy` |
| [04-akamai-tls-handshake-5xx](./04-akamai-tls-handshake-5xx.md) | Post-mortem | Errores 5xx por fallo de TLS handshake entre Akamai y el origen tras cambios de certificado |

### Objetivo

Esta carpeta sirve para:

- practicar troubleshooting en escenarios reales,
- documentar síntomas, causa raíz, mitigación y solución,
- preparar respuestas de entrevista con enfoque STAR,
- consolidar experiencia en AWS, Kubernetes, redes y seguridad.