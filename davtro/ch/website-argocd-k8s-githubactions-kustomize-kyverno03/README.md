# Davtro Website

Repozytorium CI/CD: GHCR + Kustomize + ArgoCD (namespace: davtrokyverno03)

## Jak użyć

1. Uruchom ten skrypt: `bash setup_davtro.sh`
2. Zainicjuj git: `git init && git add . && git commit -m "Init"`
3. (opcjonalnie) Dodaj zdalne repo i zrób push
4. Zainstaluj ArgoCD i zaaplikuj: `kubectl apply -f argocd/application.yaml`
5. Obserwuj deployment w ArgoCD UI
