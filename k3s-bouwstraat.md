# DSO-bouwstraat met k3s

## 1. Doel

Voor deze DevSecOps-opdracht wordt een lichtgewicht Kubernetes-platform gebruikt om
Gitea, Uptime Kuma, Prometheus en Grafana te hosten. De volledige bouwstraat bestaat
uit:

```text
Git push
  -> Gitea Actions
  -> build, test en security scans
  -> Docker image bouwen
  -> image naar Gitea Container Registry
  -> deployment naar k3s
  -> monitoring met Prometheus en Grafana
```

## 2. Waarom k3s?

Voor deze opdracht is gekozen voor **k3s** omdat dit een lichtgewicht,
gecertificeerde Kubernetes-distributie is. K3s is geschikt voor een kleine
virtuele machine of een single-node cluster en gebruikt minder resources dan een
volledige Kubernetes-installatie.

Voordelen:

- eenvoudige installatie;
- laag CPU- en geheugengebruik;
- geschikt voor één VM of een kleine cluster;
- ondersteuning voor standaard Kubernetes YAML-bestanden;
- ondersteuning voor Helm, Prometheus, Grafana en Argo CD;
- geschikt voor een reproduceerbare DevSecOps-omgeving;
- goed uitlegbaar tijdens het assessment.

## 3. Verschil tussen k3s en k3d

| Technologie | Gebruik |
|---|---|
| **k3s** | Kubernetes rechtstreeks op een VM of server |
| **k3d** | k3s-clusters die binnen Docker-containers draaien |
| **Minikube** | Vooral lokale ontwikkeling en testen |
| **Kind** | Kubernetes-nodes als Docker-containers, vooral voor testen |

Voor deze oplevering wordt **k3s op een Linux-VM** aanbevolen. k3d is vooral
handig wanneer de volledige omgeving lokaal op een laptop moet draaien. Voor een
productieachtige demonstratie is k3s op een VM duidelijker en professioneler.

## 4. Architectuur

```text
Linux VM
└── k3s
    ├── Traefik Ingress Controller
    ├── Gitea
    │   ├── Repository manager
    │   ├── Gitea Actions
    │   └── Container registry
    ├── Uptime Kuma
    ├── Prometheus
    ├── Grafana
    ├── kube-state-metrics
    └── Node Exporter
```

### Aanbevolen VM-specificaties

| Onderdeel | Aanbevolen |
|---|---:|
| CPU | 4 vCPU |
| RAM | 8 GB |
| Schijfruimte | 40-60 GB |
| Besturingssysteem | Ubuntu Server 22.04 of 24.04 |

Een minimale omgeving met 2 vCPU en 4 GB RAM is mogelijk, maar Gitea,
Prometheus, Grafana en Uptime Kuma kunnen dan weinig beschikbare resources
overhouden.

## 5. Installatie van k3s

Installeer k3s op de Linux-VM:

```bash
curl -sfL https://get.k3s.io | sh -
```

Controleer de installatie:

```bash
sudo systemctl status k3s
sudo kubectl get nodes
```

Verwachte uitvoer:

```text
NAME       STATUS   ROLES                  AGE   VERSION
devsecops  Ready    control-plane,master   1m    v1.x.x+k3s
```

Om `kubectl` zonder `sudo` te gebruiken:

```bash
sudo chmod 644 /etc/rancher/k3s/k3s.yaml
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
```

Stel `KUBECONFIG` permanent in:

```bash
echo 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml' >> ~/.bashrc
source ~/.bashrc
```

Controleer alle standaardcomponenten:

```bash
kubectl get pods -A
```

K3s bevat standaard onder andere:

- Kubernetes API-server;
- scheduler;
- controller manager;
- containerd;
- CoreDNS;
- lokale StorageClass;
- ServiceLB;
- Traefik Ingress Controller.

## 6. Helm installeren

Installeer Helm:

```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

Controleer de installatie:

```bash
helm version
```

Helm wordt gebruikt om Gitea, Prometheus en Grafana reproduceerbaar te
installeren. Bewaar de gebruikte chartversies en `values.yaml`-bestanden in de
repository.

## 7. Kubernetes-namespaces

Maak aparte namespaces voor de belangrijkste onderdelen:

```bash
kubectl create namespace gitea
kubectl create namespace uptime-kuma
kubectl create namespace monitoring
```

Wanneer Argo CD wordt toegevoegd, kan ook een namespace hiervoor worden
aangemaakt:

```bash
kubectl create namespace argocd
```

## 8. Gitea op k3s

Gitea wordt geïnstalleerd als repository manager en als basis voor de CI/CD-
pipeline. De installatie bevat:

- Gitea-webinterface;
- Git-repositories;
- Gitea Actions;
- Actions runner;
- Gitea Container Registry;
- PersistentVolumeClaim voor repositories;
- PersistentVolumeClaim voor de database;
- Ingress;
- Kubernetes Secrets voor wachtwoorden en tokens.

Voeg de Gitea Helm-repository toe:

```bash
helm repo add gitea-charts https://dl.gitea.com/charts/
helm repo update
```

Leg de configuratie vast in bijvoorbeeld:

```text
helm/gitea/values.yaml
```

of:

```text
k8s/gitea-values.yaml
```

Gebruik geen wachtwoorden of tokens rechtstreeks in deze bestanden. Gebruik
Gitea Actions Secrets en Kubernetes Secrets.

## 9. Uptime Kuma deployen

Uptime Kuma wordt in een eigen namespace gedeployed met Kubernetes-manifests:

- `Deployment`;
- `Service`;
- `Ingress`;
- `PersistentVolumeClaim`;
- resource requests en limits;
- een vaste image-tag.

Gebruik bij voorkeur een immutable tag, bijvoorbeeld:

```text
uptime-kuma:<git-sha>
uptime-kuma:<release-version>
```

Gebruik niet alleen de tag `latest`, omdat daarmee niet reproduceerbaar is welke
versie draait.

## 10. Ingress met Traefik

K3s installeert standaard Traefik als Ingress Controller. Controleer dit met:

```bash
kubectl get pods -n kube-system
kubectl get svc -n kube-system
```

Voorbeeld van een Ingress voor Uptime Kuma:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: uptime-kuma
  namespace: uptime-kuma
spec:
  ingressClassName: traefik
  rules:
    - host: uptime-kuma.example.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: uptime-kuma
                port:
                  number: 3001
```

Voor een lokale demonstratie kan een tijdelijke entry in het hosts-bestand
worden gebruikt. In een echte omgeving wordt DNS gebruikt. TLS kan worden
toegevoegd met een Kubernetes TLS-secret en bijvoorbeeld cert-manager.

## 11. Storage

K3s gebruikt standaard een lokale StorageClass. Controleer deze met:

```bash
kubectl get storageclass
```

De standaard StorageClass heet meestal:

```text
local-path   rancher.io/local-path
```

Voor een single-node assessmentomgeving is deze oplossing voldoende. De opslag
is echter node-lokaal. Bij een multi-node cluster is gedeelde opslag, zoals
Longhorn, NFS of Ceph, geschikter.

Deze beperking wordt tijdens het assessment expliciet toegelicht.

## 12. Prometheus en Grafana

Installeer de `kube-prometheus-stack`:

```bash
helm repo add prometheus-community \
  https://prometheus-community.github.io/helm-charts
helm repo update

helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --values monitoring-values.yaml
```

De monitoringstack bevat onder andere:

- Prometheus;
- Grafana;
- Alertmanager;
- node-exporter;
- kube-state-metrics.

Prometheus verzamelt bijvoorbeeld:

- CPU- en geheugengebruik van nodes;
- Kubernetes pod-status;
- aantal pod-restarts;
- beschikbaarheid van Uptime Kuma;
- HTTP-statuscodes;
- latency;
- aantal actieve pods;
- schijfruimte.

Maak in Grafana minimaal dashboards voor:

1. het Kubernetes-cluster;
2. de nodes;
3. Uptime Kuma;
4. CI/CD en Gitea;
5. fouten en pod-restarts.

## 13. Alerting

Configureer minimaal de volgende alerts:

- Uptime Kuma is niet beschikbaar;
- een Kubernetes-pod blijft crashen;
- CPU- of geheugengebruik is te hoog;
- een HTTP-endpoint geeft geen `200 OK`.

### Demonstratie van een storing

1. Toon dat Uptime Kuma beschikbaar is.
2. Verwijder of schaal de Uptime Kuma-pod.
3. Toon de fout in Prometheus.
4. Toon de alert in Grafana of Alertmanager.
5. Toon dat Kubernetes de pod opnieuw start.
6. Toon dat de status weer herstelt.

## 14. CI/CD-pipeline

De pipeline wordt uitgevoerd met Gitea Actions.

### Pull Request-pipeline

Bij iedere Pull Request worden minimaal uitgevoerd:

```text
lint
unit tests
SAST
dependency scan
Docker build
Trivy image scan
```

De Pull Request wordt niet naar productie gedeployed.

### Productiepipeline

Na een merge naar `main` of bij het maken van een release-tag:

```text
lint
unit tests
security scans
Docker image bouwen
image pushen naar Gitea Registry
deployen naar k3s
smoke test uitvoeren
```

De pipeline mag een image niet publiceren of deployen wanneer een kritieke
security finding wordt gevonden. Eventuele uitzonderingen worden expliciet
gedocumenteerd.

## 15. Security controls

| Controle | Tool | Doel |
|---|---|---|
| SAST | Semgrep | Kwetsbaarheden in JavaScript/TypeScript |
| Dependency scan | `npm audit` of OSV-Scanner | Kwetsbare dependencies |
| Secret scanning | Gitleaks | Wachtwoorden en tokens in Git |
| Container scan | Trivy | Kwetsbaarheden in Docker-images |
| SBOM | Syft | Overzicht van softwarecomponenten |
| DAST | OWASP ZAP | Test van de draaiende webapplicatie |
| Kubernetes security | Trivy config of kube-score | Fouten in Kubernetes-configuratie |

Bandit, SpotBugs en Find Security Bugs zijn niet de primaire tools voor deze
opdracht, omdat Uptime Kuma voornamelijk een Node.js/TypeScript-applicatie is.

## 16. Git-workflow en versioning

Gebruik bijvoorbeeld deze branches:

```text
main        productie
develop     integratie
feature/*   nieuwe functionaliteit
release/*   voorbereiding release
hotfix/*    urgente productie-fix
```

Aanbevolen proces:

1. Maak een feature branch.
2. Maak betekenisvolle commits.
3. Open een Pull Request in Gitea.
4. Laat de CI-pipeline succesvol uitvoeren.
5. Merge naar `main`.
6. Maak een release-tag.

Gebruik Semantic Versioning:

```text
MAJOR.MINOR.PATCH
```

Voorbeeld:

```text
v1.2.3
```

- `MAJOR`: breaking change;
- `MINOR`: nieuwe functionaliteit;
- `PATCH`: bugfix of kleine wijziging.

## 17. Argo CD als bonus

Argo CD kan worden toegevoegd voor een GitOps-deployment:

```text
Git repository
      |
      v
Kubernetes manifests
      |
      v
Argo CD
      |
      v
k3s-cluster
```

De pipeline bouwt en scant de image en wijzigt daarna de image-tag in een
deploymentrepository. Argo CD detecteert deze wijziging en synchroniseert de
gewenste toestand naar k3s.

Het verschil is:

- **CI** bouwt en test;
- **CD** maakt de release beschikbaar;
- **Argo CD** zorgt dat de gewenste toestand in Kubernetes overeenkomt met Git.

Argo CD wordt pas toegevoegd nadat de basispipeline stabiel werkt.

## 18. Voorgestelde repositorystructuur

```text
Devsecops/
├── .gitea/
│   └── workflows/
│       ├── pull-request.yml
│       └── production.yml
├── docker/
│   └── Dockerfile
├── k8s/
│   ├── namespace.yaml
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── ingress.yaml
│   ├── pvc.yaml
│   └── kustomization.yaml
├── monitoring/
│   ├── prometheus-values.yaml
│   ├── grafana-values.yaml
│   ├── alerts.yaml
│   └── dashboards/
├── security/
│   ├── trivy.yaml
│   ├── semgrep.yml
│   └── zap-baseline.yaml
├── ansible/
│   └── install-k3s-gitea.yml
├── docs/
│   ├── architecture.md
│   ├── installation.md
│   ├── pipeline.md
│   ├── security.md
│   ├── monitoring.md
│   └── evidence.md
└── README.md
```

## 19. Bouwvolgorde

### Fase 1: basisinfrastructuur

- k3s installeren;
- Gitea installeren;
- Gitea bereikbaar maken;
- Uptime Kuma-repository aanmaken;
- Actions runner koppelen.

### Fase 2: handmatige deployment

- Uptime Kuma met Kubernetes YAML deployen;
- Service en Ingress configureren;
- persistent storage toevoegen;
- controleren dat Uptime Kuma bereikbaar is.

### Fase 3: CI-pipeline

- linting en tests toevoegen;
- Docker-image bouwen;
- image pushen naar Gitea Registry;
- logs en artifacts controleren.

### Fase 4: security

- SAST toevoegen;
- dependency scan toevoegen;
- Trivy toevoegen;
- Syft SBOM genereren;
- secrets buiten Git houden.

### Fase 5: CD

- deployment automatisch uitvoeren;
- image-tag automatisch wijzigen;
- smoke test na deployment;
- rollbackprocedure documenteren.

### Fase 6: monitoring

- Prometheus installeren;
- Grafana installeren;
- dashboards configureren;
- alerts configureren;
- storing demonstreren.

### Fase 7: bonus

- Ansible;
- Argo CD;
- automatische Semantic Versioning;
- automatische release notes;
- GitOps-deployment;
- TLS en NetworkPolicies.

## 20. Assessmentdemonstratie

Gebruik de volgende demonstratie:

1. Toon Uptime Kuma in productie.
2. Toon de actieve image-tag.
3. Maak een kleine wijziging in de repository.
4. Commit de wijziging naar een feature branch.
5. Maak een Pull Request.
6. Toon dat de CI-pipeline automatisch start.
7. Toon linting, tests en security scans.
8. Merge naar `main`.
9. Toon dat de productiepipeline start.
10. Toon de image in de Gitea Container Registry.
11. Toon de Kubernetes-deployment.
12. Toon de gewijzigde applicatie in productie.
13. Toon Prometheus en Grafana.
14. Simuleer een storing door een pod te verwijderen of te schalen.
15. Toon de alert en het herstel.
16. Toon de SBOM en Trivy-resultaten.

## 21. Bewijsstukken voor de oplevering

| Onderdeel | Implementatie | Bewijs |
|---|---|---|
| Gitea | Helm-installatie met persistent storage en registry | Screenshot, Helm values en URL |
| Git-workflow | Feature branches, Pull Requests en tags | Git-log en Pull Request |
| CI/CD | Gitea Actions met build, test en deploy | Workflow YAML en pipeline-log |
| Security | Semgrep, Trivy, Syft en Gitleaks | Scanresultaten en logs |
| Monitoring | Prometheus, Grafana en alerts | Dashboard- en alert-screenshots |
| Deployment | Kubernetes-manifests met Uptime Kuma | YAML en productie-URL |
| Reproduceerbaarheid | Helm, YAML en eventueel Ansible | Installatie-instructies |

## 22. Keuze en verantwoording

De uiteindelijke omgeving bestaat uit:

```text
Ubuntu Server VM
└── k3s
    ├── Traefik
    ├── Gitea
    ├── Gitea Actions runner
    ├── Gitea Container Registry
    ├── Uptime Kuma
    ├── Prometheus
    └── Grafana
```

Deze keuze past bij de opdracht omdat k3s weinig resources gebruikt, maar wel
standaard Kubernetes-functionaliteit biedt. Daardoor kan de volledige flow
worden gedemonstreerd:

```text
Git push
-> Gitea Actions
-> test en security scan
-> Docker-image bouwen
-> image naar Gitea Registry
-> deployment naar k3s
-> monitoring met Prometheus en Grafana
```

De belangrijkste prioriteit is een betrouwbare end-to-end-bouwstraat. Extra
onderdelen zoals Nebula, Clair en Argo CD worden pas toegevoegd wanneer de
basisopstelling stabiel werkt.
