# Stappenplan Argo CD (GitOps)

## Doel

```text
push ──► Gitea Actions (CI)
           ├─ HTML-check + Trivy-scan (code)
           ├─ Docker-image bouwen
           ├─ Trivy-scan (image)
           ├─ image pushen ──► Gitea Container Registry
           └─ nieuwe image-tag committen in k8s/deployment.yaml
                    │
                    ▼
        Argo CD ziet "OutOfSync"
                    │
        ► jij klikt op SYNC ◄  (handmatige validatie)
                    │
                    ▼
        k3s haalt de image uit de registry ──► nieuwe versie live
```

Alle commando's voer je uit op de VM (`ms@k3`), tenzij er iets anders staat.
Werk de fases op volgorde af. Na elke fase volgt een **✅ controle**: ga pas verder als die klopt.

---

## Fase 0: Tokens aanmaken in Gitea

Maak twee tokens aan via Gitea → profielfoto → **Settings → Applications → Generate New Token**:

| Naam | Rechten | Gebruikt door |
|---|---|---|
| `ci-token` | repository: **Read and Write**, package: **Read and Write** | CI-workflow (image pushen + tag committen) |
| `read-token` | repository: **Read**, package: **Read** | Argo CD (repo lezen) en k3s (image ophalen) |

Twee tokens zijn veiliger (least privilege): Argo CD en k3s kunnen alleen lezen.

Zet `ci-token` als secret in de repo: **dso-demo-app → Settings → Actions → Secrets → `CI_TOKEN`**.
Bewaar `read-token` voorlopig op een veilige plek; je hebt hem nodig in fase 2 en 4.

✅ **Controle:** secret `CI_TOKEN` staat in de repo-instellingen.

---

## Fase 1: Argo CD installeren

```bash
sudo helm repo add argo https://argoproj.github.io/argo-helm
sudo helm repo update

cat > ~/argocd-values.yaml <<'EOF'
configs:
  params:
    server.insecure: true        # Traefik draait op HTTP, geen TLS in Argo zelf
server:
  ingress:
    enabled: true
    ingressClassName: traefik
    hostname: argocd.10.24.20.224.sslip.io
dex:
  enabled: false                 # geen SSO nodig
EOF

sudo helm upgrade --install argocd argo/argo-cd \
  --kubeconfig /etc/rancher/k3s/k3s.yaml \
  --namespace argocd --create-namespace \
  -f ~/argocd-values.yaml

sudo k3s kubectl get pods -n argocd -w     # wachten tot alles Running is, dan Ctrl+C
```

Haal het admin-wachtwoord op:
```bash
sudo k3s kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
```

✅ **Controle:** http://argocd.10.24.20.224.sslip.io opent en je kunt inloggen als `admin`.
Wijzig daarna het wachtwoord via *User Info → Update Password*.

---

## Fase 2: Registry bereikbaar maken (HTTP)

Je Gitea draait op HTTP. Docker en k3s weigeren standaard registries zonder HTTPS. Dit moet je op twee plekken toestaan.

### 2a. Docker-in-Docker in de CI-runner

```bash
K="sudo k3s kubectl"

$K create configmap docker-daemon -n ci \
  --from-literal=daemon.json='{"insecure-registries":["gitea.10.24.20.224.sslip.io"]}'

$K patch deploy/gitea-runner -n ci --type=strategic -p '
spec:
  template:
    spec:
      containers:
        - name: runner
          volumeMounts:
            - name: docker-daemon
              mountPath: /etc/docker/daemon.json
              subPath: daemon.json
              readOnly: true
      volumes:
        - name: docker-daemon
          configMap:
            name: docker-daemon
'
$K rollout status deploy/gitea-runner -n ci
```

### 2b. k3s zelf (images ophalen)

Vervang `<READ-TOKEN>` door je `read-token`:
```bash
sudo tee /etc/rancher/k3s/registries.yaml > /dev/null <<'EOF'
mirrors:
  "gitea.10.24.20.224.sslip.io":
    endpoint:
      - "http://gitea.10.24.20.224.sslip.io"
configs:
  "gitea.10.24.20.224.sslip.io":
    auth:
      username: ms
      password: <READ-TOKEN>
EOF
sudo chmod 600 /etc/rancher/k3s/registries.yaml
sudo systemctl restart k3s
```
Het herstarten duurt ongeveer 30 seconden. Draaiende pods blijven gewoon doorlopen.

✅ **Controle:**
```bash
sudo k3s kubectl exec deploy/gitea-runner -n ci -- docker info 2>/dev/null | grep -A2 "Insecure Registries"
sudo k3s kubectl get nodes          # k3 moet Ready zijn
```
- Bij de eerste regel moet `gitea.10.24.20.224.sslip.io` verschijnen.
- Gitea moet daarna weer bereikbaar zijn.
- Check de runner in Gitea: hij moet **Idle** staan. Dankzij de liveness-probe herstelt hij zichzelf binnen een paar minuten.

---

## Fase 3: Repository aanpassen

```bash
cd ~/dso-demo-app
mkdir -p k8s
```

### 3a. Dockerfile
```bash
cat > Dockerfile <<'EOF'
FROM nginx:alpine
COPY index.html /usr/share/nginx/html/index.html
EOF
```

### 3b. Kubernetes-manifests (wat Argo CD uitrolt)
De labels en namen zijn gelijk aan de huidige website, zodat Argo CD die bestaande resources overneemt.

```bash
cat > k8s/deployment.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: demo-website
  namespace: demo
  labels:
    app: demo-website
spec:
  replicas: 1
  revisionHistoryLimit: 5
  selector:
    matchLabels:
      app: demo-website
  template:
    metadata:
      labels:
        app: demo-website
    spec:
      containers:
        - name: nginx
          image: nginx:alpine       # wordt door de CI vervangen door de gebouwde image
          ports:
            - containerPort: 80
          readinessProbe:
            httpGet:
              path: /
              port: 80
          resources:
            requests: { cpu: 10m, memory: 16Mi }
            limits:   { memory: 64Mi }
EOF

cat > k8s/service.yaml <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: demo-website
  namespace: demo
spec:
  selector:
    app: demo-website
  ports:
    - port: 80
      targetPort: 80
EOF

cat > k8s/ingress.yaml <<'EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: demo-website
  namespace: demo
spec:
  ingressClassName: traefik
  rules:
    - host: demo.10.24.20.224.sslip.io
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: demo-website
                port:
                  number: 80
EOF
```

### 3c. Nieuwe CI-workflow
```bash
cat > .gitea/workflows/ci.yaml <<'EOF'
name: Demo website CI

on:
  push:
    branches: [main]
    paths-ignore:
      - 'k8s/**'          # de tag-commit van de CI zelf start geen nieuwe CI
  pull_request:

env:
  REGISTRY: gitea.10.24.20.224.sslip.io
  IMAGE: gitea.10.24.20.224.sslip.io/ms/dso-demo-app

jobs:
  html-check:
    runs-on: ubuntu-latest
    steps:
      - name: Code ophalen
        uses: actions/checkout@v4

      - name: HTML controleren
        run: |
          test -f index.html
          grep -Fqi 'Mijn DevSecOps-demo' index.html
          grep -Fqi 'Versie:' index.html
          echo "HTML-controles geslaagd"

  security-scan:
    runs-on: ubuntu-latest
    steps:
      - name: Code ophalen
        uses: actions/checkout@v4

      - name: Trivy-scan van de repository
        run: |
          docker run --rm -v "$PWD:/work" -w /work aquasec/trivy:0.69.3 \
            fs --scanners secret,vuln --format table \
            --exit-code 1 --severity HIGH,CRITICAL .

  build:
    needs: [html-check, security-scan]
    if: github.event_name == 'push'
    runs-on: ubuntu-latest
    steps:
      - name: Code ophalen
        uses: actions/checkout@v4

      - name: Image bouwen
        run: |
          TAG="${GITHUB_SHA::7}"
          echo "TAG=$TAG" >> "$GITHUB_ENV"
          docker build -t "$IMAGE:$TAG" .

      - name: Trivy-scan van de image
        run: |
          docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
            aquasec/trivy:0.69.3 image --format table \
            --exit-code 1 --severity CRITICAL "$IMAGE:$TAG"

      - name: Image pushen naar Gitea Registry
        env:
          CI_TOKEN: ${{ secrets.CI_TOKEN }}
        run: |
          echo "$CI_TOKEN" | docker login "$REGISTRY" -u ms --password-stdin
          docker push "$IMAGE:$TAG"
          docker logout "$REGISTRY"

      - name: Nieuwe versie klaarzetten voor Argo CD
        env:
          CI_TOKEN: ${{ secrets.CI_TOKEN }}
        run: |
          sed -i -E "s#^( *image: ).*#\1$IMAGE:$TAG#" k8s/deployment.yaml
          git config user.name  "Gitea CI"
          git config user.email "ci@gitea.local"
          git add k8s/deployment.yaml
          git commit -m "Deploy image $TAG"
          git push "http://ms:${CI_TOKEN}@gitea.10.24.20.224.sslip.io/ms/dso-demo-app.git" HEAD:main
EOF
```

Commit en push:
```bash
git add Dockerfile k8s .gitea/workflows/ci.yaml
git commit -m "Build container image and prepare GitOps manifests"
git push
```

✅ **Controle:**
- In Gitea Actions worden alle drie de jobs groen.
- Onder **ms → Packages** staat `dso-demo-app` met een tag van 7 tekens.
- In de repo staat een nieuwe commit *"Deploy image …"* van *Gitea CI*.
- `k8s/deployment.yaml` verwijst naar die image.

> ⚠️ Faalt de image-scan op een CRITICAL-kwetsbaarheid in `nginx:alpine`? Lees dan eerst de Trivy-output. Vaak is er een nieuwere image beschikbaar. Zet de check niet zomaar uit.

---

## Fase 4: Argo CD koppelen aan de repo

Vervang `<READ-TOKEN>`. Argo CD gebruikt het interne cluster-adres van Gitea:

```bash
cat <<'EOF' | sudo k3s kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: repo-dso-demo-app
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
stringData:
  type: git
  url: http://gitea-http.gitea.svc.cluster.local:3000/ms/dso-demo-app.git
  username: ms
  password: <READ-TOKEN>
EOF

cat <<'EOF' | sudo k3s kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: demo-website
  namespace: argocd
spec:
  project: default
  source:
    repoURL: http://gitea-http.gitea.svc.cluster.local:3000/ms/dso-demo-app.git
    targetRevision: main
    path: k8s
  destination:
    server: https://kubernetes.default.svc
    namespace: demo
  # Bewust GEEN syncPolicy.automated:
  # een mens moet op "Sync" klikken = handmatige validatie naar productie
EOF
```

✅ **Controle:**
- In de Argo CD-UI staat de app `demo-website` op **OutOfSync**.
- Klik op **App Diff**. Je ziet dat de image verandert van `nginx:alpine` met ConfigMap naar je eigen image.

---

## Fase 5: Eerste Sync en de volledige keten testen

1. Klik in Argo CD op **Sync → Synchronize**.
2. Wacht tot de app **Synced** en **Healthy** is.
3. Open http://demo.10.24.20.224.sslip.io. De website moet nog steeds werken.

**Test de keten:**
1. Zet in `index.html` de versie op **2.2**, commit en push.
2. De CI bouwt `…/dso-demo-app:<nieuwe tag>` en commit de tag.
3. Argo CD → **Refresh**. De app staat op **OutOfSync**.
4. Klik op **Sync**. Daarna toont de website versie **2.2**.

**Test de rollback:**
- Argo CD → app → **History and Rollback**. Kies de vorige revisie en klik op **Rollback**.
- De website toont weer **2.1**.

✅ **Controle:** beide tests lukken. Maak hier screenshots of een opname van voor je portfolio.

---

## Fase 6: Oude deploy-oplossing opruimen

Pas uitvoeren als fase 5 werkt.

```bash
K="sudo k3s kubectl"
cd ~/dso-demo-app
git rm .gitea/workflows/deploy.yaml
git commit -m "Remove push-based deployment, replaced by Argo CD"
git push

$K delete deploy/deploy-runner -n ci
$K delete secret deploy-runner-token -n ci
$K delete secret deploy-runner-token -n demo
$K delete rolebinding deploy-runner demo-deployer -n demo
$K delete role demo-deployer -n demo
$K delete sa deploy-runner demo-deployer -n demo
$K delete sa deploy-runner -n ci
$K delete configmap demo-website-html -n demo
```

Ruim daarna ook in Gitea op:
- Verwijder de secrets `K8S_TOKEN` en `K8S_CA_CERT` uit de repo.
- Verwijder runner `deploy-runner-…` onder Site Administration → Runners.

✅ **Controle:** Argo CD staat nog steeds op **Synced/Healthy** en de website werkt.

---

## Fase 7 (optioneel): Argo CD in Grafana

Dit versterkt basisonderdeel 5 (buildmonitoring). Je ziet dan deploy- en sync-status als metriek.

```bash
cat >> ~/argocd-values.yaml <<'EOF'
controller:
  metrics:
    enabled: true
    serviceMonitor:
      enabled: true
      additionalLabels:
        release: monitoring
EOF
sudo helm upgrade argocd argo/argo-cd --kubeconfig /etc/rancher/k3s/k3s.yaml \
  -n argocd -f ~/argocd-values.yaml
```

Importeer daarna in Grafana dashboard-ID **14584** (*Argo CD*): Dashboards → New → Import.

---

## Aandachtspunten

- **Schijfruimte:** er is maar ongeveer 8 GB vrij. Images staan zowel in de DinD-runner als in k3s. Controleer af en toe met `df -h /` en ruim op met `sudo k3s kubectl exec deploy/gitea-runner -n ci -- docker system prune -af`.
- **Tokens:** `read-token` staat in `registries.yaml` (alleen leesbaar voor root) en in een Kubernetes Secret, niet in Git.
- **Lukt iets niet?** Stuur de foutmelding plus de uitvoer van:
  - `sudo k3s kubectl get pods -A | grep -v Running`
  - `sudo k3s kubectl describe pod <naam> -n <namespace>`
