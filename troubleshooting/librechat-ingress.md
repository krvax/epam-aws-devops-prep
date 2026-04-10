# 🐛 Issue: LibreChat Ingress no funcionaba en EKS

## Contexto

- **Fecha:** [YYYY-MM-DD]
- **Proyecto:** LibreChat en EKS
- **Herramienta:** Helm
- **Cluster:** [nombre del cluster]
- **Región:** [us-east-1, etc.]

---

## Síntoma

[Describe qué pasó - ejemplo:]
Al hacer `helm install` de LibreChat, el Ingress se creó pero:
- No se generaba el ALB
- El Target Group mostraba targets unhealthy
- Al acceder al dominio daba [502 / timeout / etc.]

---

## Diagnóstico

```bash
# ¿El ingress tiene ADDRESS?
kubectl get ingress
# Resultado:
# [pega aquí el output]

# ¿Los pods están corriendo?
kubectl get pods
# Resultado:
# [pega aquí el output]

# ¿El ALB Controller está corriendo?
kubectl get pods -n kube-system | grep load-balancer
# Resultado:
# [pega aquí el output]

# ¿Qué dicen los logs?
kubectl describe ingress librechat
# Resultado:
# [pega aquí el output]
```

---

## Causa raíz

[Explica qué estaba mal - ejemplo:]
- [ ] El ALB Controller no estaba instalado
- [ ] Faltaban annotations en el Ingress
- [ ] El healthcheck-path era incorrecto
- [ ] Permisos IAM faltantes
- [ ] Security Groups bloqueando tráfico
- [ ] Otro: _______________

---

## Solución

```bash
# Comandos exactos que resolvieron el problema
[pega aquí lo que hiciste]
```

---

## Lecciones aprendidas

1. Siempre verificar que el ALB Controller esté instalado **antes** de crear un Ingress
2. Revisar los health checks del Target Group
3. [agrega más...]

---

## Documentación relacionada

- [Conceptos: Ingress, ALB y Target Groups](../docs/01-eks-ingress-alb.md)
- [Lab: LibreChat en EKS](../labs/lab-01-librechat-eks/README.md)