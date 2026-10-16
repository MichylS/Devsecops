5. Hoe we de opdracht gaan realiseren
We werken in deze volgorde. Iedere fase heeft een controlepunt, zodat je niet verder bouwt op een installatie die nog niet goed werkt.
1. Inventarisatie en netwerk
   VM-resources, IP-adres, VPN-bereikbaarheid en firewall controleren.
2. K3s installeren
   Een single-node Kubernetes-cluster maken en controleren of de node Ready is.
3. Gitea installeren
   Een repository maken voor de demo-applicatie en de configuratiebestanden.
4. Applicatie in productie zetten
   Een eenvoudige website deployen naar K3s en bereikbaar maken via je VPN.
5. CI/CD configureren
   Gitea Actions en een runner instellen. De build moet automatisch starten na een wijziging.
6. Handmatige goedkeuring toevoegen
   Een wijziging mag pas na validatie en goedkeuring naar productie.
7. Monitoring toevoegen
   Applicatiestatus, pipeline-uitvoering en infrastructuur monitoren.
8. Bewijs en assessment voorbereiden
   Configuratiebestanden, screenshots, testresultaten en een demonstratiescript verzamelen.
6. Wat je uiteindelijk tijdens de demo laat zien
1. De website draait in productie en toont bijvoorbeeld versie 1.0.
2. Je wijzigt de code in Gitea naar versie 1.1.
3. De CI-pipeline start en bouwt de nieuwe versie.
4. Je toont de buildresultaten en de uitgevoerde tests.
5. De deployment wacht op een handmatige goedkeuring.
6. Je keurt de release goed.
7. K3s rolt de nieuwe versie uit.
8. Je ververst de website en toont versie 1.1.
9. Je toont in Grafana de monitoring en laat zien hoe je kunt vaststellen of de applicatie en infrastructuur gezond zijn.
Dat levert je een duidelijke demonstratie op van de volledige keten: commit → build → test → approve → deploy → monitor.

eerste probleem page not found bij gitea.

na tests

Perfect! We hebben nu bevestigd dat Gitea zelf werkt (HTTP/1.1 200 OK) en dat Traefik draait op 10.24.20.224. Het ontbrekende onderdeel is vrijwel zeker de route tussen Traefik en Gitea.
We gaan nu een Ingress toevoegen. Dit maakt Gitea bereikbaar via je bestaande K3s-installatie, zonder de Gitea-database of andere bestaande onderdelen te wijzigen


na ingres yamel gemaakt te hebben kopplen en k3s

sudo k3s kubectl apply -f gitea-ingress.yaml
sudo k3s kubectl get ingress -n gitea

acount maken voor gitea 

us:ms
ww: Admin!123

daarna e hebt eerder gecontroleerd dat Actions in Gitea is ingeschakeld. Dat betekent nog niet automatisch dat workflows kunnen draaien: daarvoor is ook een Actions-runner nodig

Voor jouw situatie stel ik voor om de runner als service op de VM te draaien. Daarmee kunnen we eerst de CI-workflow werkend krijgen en daarna de deployment naar K3s automatiseren

Stap 1 — download de juiste runner
We gebruiken de officiële Gitea Actions Runner. Controleer eerst welke versie momenteel beschikbaar is via de officiële releases:

nu runner key aanmaken 

qTDFvHoJ8lvUJLb02w0JWXZEA7RGSsYYstGXXHPy

Stap 1 — maak een vaste map voor de runner

sudo useradd --system --create-home \
  --home-dir /var/lib/act_runner \
  --shell /usr/sbin/nologin act_runner

sudo mkdir -p /etc/act_runner
sudo chown act_runner:act_runner /var/lib/act_runner
sudo chmod 750 /var/lib/act_runner

Stap 2 — maak de configuratie
Genereer de standaardconfiguratie:
sudo /usr/local/bin/gitea-runner generate-config \
  | sudo tee /etc/act_runner/config.yaml >/dev/null

sudo chown root:act_runner /etc/act_runner/config.yaml
sudo chmod 640 /etc/act_runner/config.yaml

read -rsp "Gitea runner registration token: " qTDFvHoJ8lvUJLb02w0JWXZEA7RGSsYYstGXXHPy
echo
export qTDFvHoJ8lvUJLb02w0JWXZEA7RGSsYYstGXXHPy

/usr/local/bin/gitea-runner register \
  --config /etc/act_runner/config.yaml \
  --instance http://gitea.10.24.20.224.sslip.io/ \
  --name k3s-vm-runner \
  --no-interactive

unset qTDFvHoJ8lvUJLb02w0JWXZEA7RGSsYYstGXXHPy
exit

Stap 2 — maak een systemd-service
Maak het servicebestand:

daarin het runner bestadn in geplakt

kreeg error dat service niet wil starten

Ja, precies! 👍 Dan maken we het zo: Docker-in-Docker in K3s, met de Gitea Runner in dezelfde Pod. Zo hoef je Docker niet rechtstreeks op je Ubuntu-VM te installeren en draait de runner binnen je bestaande Kubernetes-cluster.
Hoe het eruit komt te zien
K3s op je Ubuntu-VM
Je bestaande cluster
Runner Pod
Gitea Runner
Ontvangt jobs en voert workflows uit


Docker-in-Docker
Start containers voor de jobs





CI/CD-workflow
Code wijzigen → build → tests → goedkeuring → deployment naar productie


Waarom deze aanpak?
- Geen Docker-installatie op de VM nodig. Docker draait in een aparte container.
- Past bij je bestaande K3s-omgeving. De runner wordt beheerd als Kubernetes-workload.
- Wel een aandachtspunt: Docker-in-Docker vereist doorgaans een container met verhoogde rechten (privileged mode). Dat is een beveiligingsrisico. Voor jouw geïsoleerde schoollab is dit werkbaar als we de runner alleen vertrouwde code laten uitvoeren; gebruik deze opzet niet zomaar voor onbekende repositories.

plus runner is best competle met docker

Stap 3a — controleer K3s met sudo
Voer dit uit:
sudo kubectl get nodes
sudo kubectl get namespaces


Hiermee voeren we kubectl uit met beheerdersrechten. Je hoeft de rechten van K3s niet aan te passen.
Je zou je node k3 met status Ready moeten zien en onder de namespaces onder andere gitea.


Stap 3b — daarna maken we de runner-Pod
We gaan straks:
- de bestaande .runner-registratie behouden;
- de runner en Docker-in-Docker samen in een Pod zetten;
- Docker alleen binnen die Pod bereikbaar maken;
- de runner in Gitea laten verbinden met je bestaande Gitea-adres.
Voer eerst alleen stap 3a uit en stuur de uitvoer. Daarna geef ik je het concrete Kubernetes-configuratiebestand, afgestemd op jouw cluster

Hiermee bepalen we onder welke gebruikers-ID de runner kan draaien en controleren we dat de oude service inderdaad gestopt is.
Daarna maak ik het Kubernetes-bestand voor je. We delen een werkmap tussen de runner en Docker-in-Docker, zodat Docker de bestanden van de buildjobs daadwerkelijk kan vinden. We bewaren ook je bestaande runnerregistratie, zodat je geen nieuwe registratietoken nodig hebt.

Stap 5 — de runner in K3s aanmaken
De officiële Gitea Runner-image heeft een speciale variant met Docker-in-Docker. We gebruiken de bij jouw runner passende 2.3-dind-image. Deze bevat zowel de runner als een eigen Docker-daemon. 

Gitea Documentation



5.1 Maak het configuratiebestand
Kopieer dit volledige commando in je Ubuntu-terminal:

Wat doet dit bestand?
- Maakt een aparte namespace ci aan voor de runner.
- Start één runner met Docker-in-Docker.
- Gebruikt je bestaande .runner-registratie uit /var/lib/act_runner.
- Leest je bestaande runnerconfiguratie in, zonder het origineel te overschrijven.
- Gebruikt Recreate zodat Kubernetes niet tijdelijk twee Pods met dezelfde runnerregistratie start.

daarna runner starten sudo kubectl apply -f /tmp/gitea-runner-k3s.yaml

het runned!!

Stap 7 — test een echte workflow
In je repository dso-demo-app maak je het bestand .gitea/workflows/runner-test.yaml aan met deze inhoud: ruuunertest.yml

daarna kan kijkne of het implementeert

na action workflow te hebben gedaan werktde runner 

Wat gaan we daarna bouwen?
We bouwen het project in kleine stappen op, zodat je het goed kunt uitleggen tijdens je schoolpresentatie.
1. Demo-app maken — een eenvoudige webpagina die in K3s draait.
2. CI toevoegen — bij een codewijziging automatisch controles uitvoeren.
3. Security-check toevoegen — bijvoorbeeld een scan op bekende kwetsbaarheden.
4. Goedkeuring inbouwen — de productie-update pas starten na een bewuste handmatige actie.
5. Deployen naar productie — de nieuwe versie uitrollen en controleren of de website is bijgewerkt.

namespace voor isolatie

Wat betekent dit?
Namespace: demo

Een namespace is een logische scheiding binnen Kubernetes. Zo kunnen we de demo-website apart beheren zonder je bestaande Gitea-installatie te wijzigen.


Stap 2 — Start de webserver in K3s

sudo kubectl create deployment demo-website \
  --image=nginx:alpine \
  --namespace=demo

Wat gebeurt hier?
- demo-website is de naam van onze applicatie.
- nginx:alpine is een lichte webserver-image.
- -n demo zorgt dat alles in onze aparte namespace komt.

Stap 3 — Maak de website bereikbaar binnen Kubernetes
Voer dit commando uit

1. Wat is Traefik?
Traefik is een ingress controller: hij ontvangt webverkeer en stuurt dat door naar de juiste applicatie in Kubernetes.
Vergelijk het met de receptionist van een gebouw: bezoekers melden zich bij de ingang en Traefik bepaalt naar welke applicatie ze moeten.

. Waarom kunnen we de website nog niet openen?
Je Service heeft dit adres:
10.43.183.36:80
Dat is een intern Kubernetes-adres. Je laptop kan daar normaal gesproken niet rechtstreeks bij. Daarom voegen we een Ingress toe die Traefik vertelt waar het verkeer naartoe moet.
We gebruiken voorlopig HTTP en je bestaande interne netwerk. We maken de website niet publiek toegankelijk.

nano demo-website-ingress.yaml

plak hoer de yaml in

sudo kubectl apply -f demo-website-ingress.yaml

nu de website beetje voorbereiden 

Stap 1 — De eigen website voorbereiden
We beginnen met de HTML-pagina. Voer op je Ubuntu-server uit: 

map genaamt des-demo-app daarin een html bestand deze nu in een config map sturen

sudo kubectl create configmap demo-website-html \
  --from-file=index.html \
  -n demo


Let op: als je de melding krijgt dat ConfigMap al bestaat, stop dan even en stuur me die melding.
Een ConfigMap is een Kubernetes-object waarin we configuratiebestanden kunnen bewaren. We gebruiken hem om onze HTML-pagina aan de webserver te leveren.

tap 3 — Laat Nginx jouw pagina gebruiken
Voer dit pas uit als stap 2 gelukt is:
sudo kubectl patch deployment demo-website -n demo --type=strategic -p '
spec:
  template:
    spec:
      volumes:
        - name: website-html
          configMap:
            name: demo-website-html
      containers:
        - name: nginx
          volumeMounts:
            - name: website-html
              mountPath: /usr/share/nginx/html


nu map kopplen aan gitea Wat we hierna gaan doen
1. Gitea koppelen: de HTML-code in dso-demo-app opslaan.
2. Automatische test: bij iedere codewijziging controleert Gitea Actions of de HTML geldig is.
3. Security-scan: een controle toevoegen op mogelijke kwetsbaarheden.
4. Goedkeuring en deployment: pas na jouw bewuste goedkeuring versie 2.0 naar de demo-website uitrollen.

Stap 3 — Koppel Git aan Gitea
Als de repository inderdaad bestaat, voer dan deze opdrachten uit: cd ~/dso-demo-app
git init
git branch -M main
git remote add origin http://gitea.10.24.20.224.sslip.io/ms/dso-demo-app.git

Stap 2 — Voeg de website toe
Voer uit:
git add index.html
git commit -m "Add demo website"


Controleer dat de commit is aangemaakt:
git log --oneline -3


Stap 3 — Push naar Gitea
Voer uit:
git push -u origin main

Stap 1 — Automatische CI-test toevoegen
De workflow moet automatisch starten als je code naar main pusht. Hij controleert dan of je HTML-bestand bestaat en of de belangrijkste onderdelen erin staan

1. Maak een nieuwe workflow aan in je lokale project
Voer op je Ubuntu-server uit:
cd ~/dso-demo-app
mkdir -p .gitea/workflows
nano .gitea/workflows/ci.yaml



Dus als je een tweede HTML-bestand toevoegt en naar main pusht, start de workflow opnieuw.
Er is wel een belangrijk verschil: je huidige controles testen alleen index.html. Ze controleren nog niet automatisch alle HTML-bestanden.

Kreeg errov voor de trivy scan dus deze in eigen docker cointainer runnen

dus trivy geddelt verandren

Stap 2 — Maak een serviceaccount voor deployment

We maken eerst een aparte serviceaccount in namespace demo. Die kan straks gebruikt worden om de website bij te werken, zonder de runner algemene beheerdersrechten te geven.

Stap 3 — Maak een beperkte Kubernetes-rol
We willen dat demo-deployer straks alleen:
- De ConfigMap demo-website-html kan aanpassen.
- De status van de website-deployment kan controleren en die deployment kan herstarten door een wijziging aan de podtemplate.
Kubernetes-RBAC k


Pas de rol toe:
sudo k3s kubectl apply -f demo-deployer-role.yaml


Koppel de rol aan de serviceaccount:
sudo k3s kubectl create rolebinding demo-deployer \
  --role=demo-deployer \
  --serviceaccount=demo:demo-deployer \
  -n demo

  aak de deployment-workflow handmatig startbaar

  We hebben al de serviceaccount demo-deployer en de beperkte rol voor de ConfigMap. De volgende stap is dat de runner die identiteit kan gebruiken. De serviceaccount bestaat nu in namespace demo, terwijl de runner in namespace ci draait.

  We moeten daarom een veilige manier kiezen om die toegang beschikbaar te maken. We gaan niet zomaar een Kubernetes-beheerdersconfiguratie in Gitea opslaan.

  Een beperkte serviceaccount voor de runner voorbereiden

  checken of het mag aanpassen
  ms@k3:~/dso-demo-app$ sudo k3s kubectl auth can-i patch configmap/demo-website-html \
  -n demo \
  --as=system:serviceaccount:ci:default
no


1. Maak een serviceaccount in namespace ci:
sudo k3s kubectl create serviceaccount deploy-runner -n ci


2. Koppel die identiteit aan de bestaande rol in namespace demo:
sudo k3s kubectl create rolebinding deploy-runner \
  --role=demo-deployer \
  --serviceaccount=ci:deploy-runner \
  -n demo


De rol demo-deployer beperkt de toegang tot de ConfigMap demo-website-html. De serviceaccount krijgt dus niet automatisch beheerdersrechten.
3. Controleer de rechten:
sudo k3s kubectl auth can-i patch configmap/demo-website-html \
  -n demo \
  --as=system:serviceaccount:ci:deploy-runner

  We kiezen voor deze aanpak:
- Je gewone CI blijft de HTML controleren en Trivy uitvoeren.
- Een aparte deployment-runner voert alleen de handmatige productie-deployment uit.
- De deployment krijgt uitsluitend toegang tot de ConfigMap demo-website-html.
- Na het publiceren controleert de workflow of de nieuwe versie via je website zichtbaar is

Maak een map voor de configuratie:
sudo mkdir -p /etc/act_runner-deploy
sudo chown root:root /etc/act_runner-deploy
sudo chmod 755 /etc/act_runner-deploy


Maak vervolgens een aparte configuratie op basis van de bestaande configuratie:
sudo cp /etc/act_runner/config.yaml \
  /etc/act_runner-deploy/config.yaml

sudo chown root:root /etc/act_runner-deploy/config.yaml
sudo chmod 600 /etc/act_runner-deploy/config.yaml

gitea-runner register --no-interactive \
  --instance http://gitea.10.24.20.224.sslip.io \
  --token qTDFvHoJ8lvUJLb02w0JWXZEA7RGSsYYstGXXHPy \
  --name deploy-runner \
  --labels deployment

  Belangrijk: de configuratiemap uit stap 18 registreert nog geen runner en geeft hem ook geen Kubernetes-toegang. We moeten de runner apart starten en daarna de toegang tot Kubernetes veilig koppelen. Ik wil voorkomen dat je nu een tweede runner installeert die wel groen wordt, maar niets kan publiceren.
De volgende technische stap is om de Kubernetes-toegang aan de deployment-job beschikbaar te maken met alleen de rechten op demo-website-html. Daarvoor gebruiken we geen admin-kubeconfig. Zodra die koppeling klaar is, vervangt de deployment-workflow de huidige teststappen door de echte publicatie en HTTP-controle.

Stap 26 — Maak de Kubernetes-configuratie voor de tweede runner

Stap 28 — Maak een aparte map voor de deployment-runner
Voer dit uit op k3:
sudo mkdir -p /var/lib/act_runner-deploy
sudo chown root:root /var/lib/act_runner-deploy
sudo chmod 750 /var/lib/act_runner-deploy


Kopieer daarna de configuratie naar een bestand dat we specifiek voor de tweede runner gaan gebruiken:
sudo cp /etc/act_runner-deploy/config.yaml \
  /etc/act_runner-deploy/config.yaml.backup


  runner uitleg
  Dit doet het volgende:

Stap A — Registreren bij Gitea
Het commando maakt via de Gitea-URL contact met Gitea, gebruikt de registratietoken en registreert daar deploy-runner met het label deployment.




Stap B — Lokale registratiegegevens opslaan
De runner schrijft zijn registratiegegevens naar een .runner-bestand. De locatie hangt af van de gebruiker en de werkdirectory/configuratie waarmee je het commando uitvoert.




Stap C — De runner daadwerkelijk starten
Een proces of Kubernetes-pod moet daarna de runner starten met die registratiegegevens. Pas dan kan de runner verbinding maken en in Gitea als Idle verschijnen.



Dus ja: het registratiecommando registreert de runner bij Gitea, maar maakt niet automatisch een Kubernetes-Deployment of Pod aan.




2. Waarom staat deploy-runner dan offline?
In jouw situatie zijn dit drie verschillende dingen:
Gitea — registratie
Je ziet deploy-runner met label deployment. Gitea kent de runner dus.



Kubernetes — Deployment
We hebben een Kubernetes-Deployment aangemaakt, maar de configuratie die daarin gemount wordt, is nog een kopie van de oude configuratie. De nieuwe registratie staat daardoor niet automatisch in die pod.



Gitea — verbinding
De runner moet als proces starten, de juiste .runner-registratie laden en contact houden met Gitea. Dan verandert de status naar Idle.



De officiële Gitea-documentatie bevestigt dat register de registratiegegevens opslaat in .runner, en dat daemon de runner daadwerkelijk laat draaien en opdrachten laat ophalen. 

Gitea Documentation
+1



3. Hoe past dat in jouw Kubernetes-configuratie?
Je bestaande runner heeft deze koppeling:
env:
  - name: CONFIG_FILE
    value: /config.yaml
volumeMounts:
  - name: runner-data
    mountPath: /data
  - name: runner-config
    mountPath: /config.yaml
    readOnly: true


Dat betekent:
- /config.yaml bevat de runnerinstellingen.
- /data is de opslag voor de runnergegevens, waaronder de registratie.
- Kubernetes start de container opnieuw als die stopt, maar maakt niet vanzelf een nieuwe registratie aan.
We hebben voor deploy-runner een aparte map gemaakt, maar die moet ook de eigen registratie bevatten. De registratie die je eerder op de VM uitvoerde, belandt niet automatisch in de map /var/lib/act_runner-deploy van de pod.
4. Wat moeten we nu doen?
We hoeven niet opnieuw te beginnen. We moeten alleen de registratie en de Kubernetes-opslag aan elkaar koppelen.
Voer eerst dit uit:
sudo k3s kubectl logs deployment/deploy-runner -n ci --tail=80


Daarna controleren we of de runner in /var/lib/act_runner-deploy al een .runner-bestand heeft:
sudo ls -la /var/lib/act_runner-deploy


Deel de uitvoer van deze twee opdrachten. De inhoud van .runner niet delen: daarin staan registratiegegevens. Dan kan ik je de concrete volgende opdrachten geven om de nieuwe runner online te krijgen, zonder de werkende k3s-vm-runner aan te passen.

De runnerconfiguratie en bijbehorende bestanden staan daarnaast op deze locaties:
Bestand/map	Waarvoor?
/etc/act_runner-deploy/config.yaml	Configuratie van de deployment-runner
/var/lib/act_runner-deploy	Gegevens van de deployment-runner
Kubernetes Secret deploy-runner-token in namespace ci	Registratietoken

problemen met runner aan de praat krijgen

De Kubernetes Secret deploy-runner-token bestaat al, maar de Deployment gebruikt die Secret nog niet. In de getoonde omgevingsvariabelen staat alleen CONFIG_FILE.
We gaan dus de bestaande Secret koppelen aan de runner, zonder

Dat is logisch te onderzoeken: de Pod is nu Running en 1/1 Ready, maar de log toont nog:
Waiting for Docker daemon to start...
Dat betekent dat de container gestart is, maar de runner mogelijk nog wacht tot Docker klaar is. Daardoor kan hij nog offline blijven in Gitea. We gaan eerst controleren of Docker opstart en of de runner zich succesvol registreert. We hoeven niet opnieuw een token aan te maken: de Kubernetes Secret bestaat al.
Stap 1 — Controleer de logs en configuratie
Voer deze hele reeks uit op je VM:
echo "=== Recente logs ==="
sudo k3s kubectl logs deployment/deploy-runner -n ci --tail=100

echo
echo "=== Logs van de vorige container, indien beschikbaar ==="
sudo k3s kubectl logs deployment/deploy-runner -n ci --previous --tail=60

echo
echo "=== Pod-events ==="
sudo k3s kubectl describe pod \
  "$(sudo k3s kubectl get pods -n ci -l app=deploy-runner -o jsonpath='{.items[0].metadata.name}')" \
  -n ci | tail -60

echo
echo "=== Deployment-configuratie: gevoelige waarden worden niet getoond ==="
sudo k3s kubectl get deployment deploy-runner -n ci \
  -o jsonpath='{range .spec.template.spec.containers[0].env[*]}{.name}{"\n"}{end}'

echo
echo "=== Gitea-runner-status ==="
sudo k3s kubectl get pods -n ci -o wide






Stap 2 — Geef Docker even tijd en controleer opnieuw
De eerste log was meteen na het starten van de Pod; dat is mogelijk te vroeg om de uiteindelijke fout te zien. Wacht ongeveer 30 seconden en voer uit:
sleep 30

echo "=== Runner-logs ==="
sudo k3s kubectl logs deployment/deploy-runner -n ci --tail=100

echo
echo "=== Is de Docker-socket aanwezig? ==="
sudo k3s kubectl exec deployment/deploy-runner -n ci -- \
  sh -c 'ls -l /var/run/docker.sock 2>&1'

echo
echo "=== Runner-status in Kubernetes ==="
sudo k3s kubectl get pods -n ci


Let vooral op meldingen zoals Successfully registered, registration, token, Docker daemon of connection refused.
Stuur de uitvoer hierna door. Deel niet de inhoud van de Secret of het registratietoken. Dan kunnen we bepalen of het probleem bij Docker, de runnerregistratie of de verbinding met Gitea zit.
















echo "=== Recente logs ==="                                         
sudo k3s kubectl logs deployment/deploy-runner -n ci --tail=100                           
echo                                                                                      
echo "=== Logs van de vorige container, indien beschikbaar ==="                           
sudo k3s kubectl logs deployment/deploy-runner -n ci --previous --tail=60                 
echo                                                                                      
echo "=== Pod-events ==="                                                                 
sudo k3s kubectl describe pod \                                                           
  "$(sudo k3s kubectl get pods -n ci -l app=deploy-runner -o jsonpath='{.items[0].metadata
.name}')" \                                                                               
  -n ci | tail -60                                                                        
echo                                                                                      
echo "=== Deployment-configuratie: gevoelige waarden worden niet getoond ==="             
sudo k3s kubectl get deployment deploy-runner -n ci \                                     
  -o jsonpath='{range .spec.template.spec.containers[0].env[*]}{.name}{"\n"}{end}'        
echo                                                                                      
echo "=== Gitea-runner-status ==="                                                        
sudo k3s kubectl get pods -n ci -o wide                                                   
=== Recente logs ===                                                                      
time="2026-10-16T14:05:16.045739492Z" level=info msg="Get image filesystem path \"/var/lib
/docker/containerd/daemon/io.containerd.snapshotter.v1.overlayfs\" for snapshotter \"overl
ayfs\""                                                                                   
time="2026-10-16T14:05:16.045831427Z" level=info msg="Start snapshots syncer"             
time="2026-10-16T14:05:16.046025069Z" level=info msg="loading plugin" id=io.containerd.cri
.v1.runtime type=io.containerd.cri.v1                                                     
time="2026-10-16T14:05:16.047243557Z" level=info msg="starting cri plugin" config="{\"cont
ainerd\":{\"defaultRuntimeName\":\"runc\",\"runtimes\":{\"runc\":{\"runtimeType\":\"io.con
tainerd.runc.v2\",\"runtimePath\":\"\",\"PodAnnotations\":null,\"ContainerAnnotations\":nu
ll,\"options\":{\"BinaryName\":\"\",\"CriuImagePath\":\"\",\"CriuWorkPath\":\"\",\"IoGid\"
:0,\"IoUid\":0,\"NoNewKeyring\":false,\"Root\":\"\",\"ShimCgroup\":\"\",\"SystemdCgroup\":
false},\"privileged_without_host_devices\":false,\"privileged_without_host_devices_all_dev
ices_allowed\":false,\"cgroupWritable\":false,\"baseRuntimeSpec\":\"\",\"cniConfDir\":\"\"
,\"cniMaxConfNum\":0,\"snapshotter\":\"\",\"sandboxer\":\"podsandbox\",\"io_type\":\"\"}},
\"ignoreBlockIONotEnabledErrors\":false,\"ignoreRdtNotEnabledErrors\":false},\"cni\":{\"bi
nDir\":\"\",\"binDirs\":[\\"/opt/cni/bin\\"],\"confDir\":\"/etc/cni/net.d\",\"maxConfNum\":1
,\"setupSerially\":false,\"confTemplate\":\"\",\"ipPref\":\"\",\"useInternalLoopback\":fal
se},\"enableSelinux\":false,\"selinuxCategoryRange\":1024,\"maxContainerLogLineSize\":1638
4,\"disableApparmor\":false,\"restrictOOMScoreAdj\":false,\"disableProcMount\":false,\"uns
etSeccompProfile\":\"\",\"tolerateMissingHugetlbController\":true,\"disableHugetlbControll
er\":true,\"device_ownership_from_security_context\":false,\"ignoreImageDefinedVolumes\":f
alse,\"netnsMountsUnderStateDir\":false,\"enableUnprivilegedPorts\":true,\"enableUnprivile
gedICMP\":true,\"enableCDI\":true,\"cdiSpecDirs\":[\\"/etc/cdi\\",\\"/var/run/cdi\\"],\"drainE
xecSyncIOTimeout\":\"0s\",\"ignoreDeprecationWarnings\":null,\"containerdRootDir\":\"/var/
lib/docker/containerd/daemon\",\"containerdEndpoint\":\"/var/run/docker/containerd/contain
erd.sock\",\"rootDir\":\"/var/lib/docker/containerd/daemon/io.containerd.grpc.v1.cri\",\"s
tateDir\":\"/var/run/docker/containerd/daemon/io.containerd.grpc.v1.cri\"}"               
time="2026-10-16T14:05:16.047692151Z" level=info msg="loading plugin" id=io.containerd.pod
sandbox.controller.v1.podsandbox type=io.containerd.podsandbox.controller.v1              
time="2026-10-16T14:05:16.048145840Z" level=info msg="loading plugin" id=io.containerd.san
dbox.controller.v1.shim type=io.containerd.sandbox.controller.v1                          
time="2026-10-16T14:05:16.048878605Z" level=info msg="loading plugin" id=io.containerd.grp
c.v1.sandbox-controllers type=io.containerd.grpc.v1                                       
time="2026-10-16T14:05:16.049178077Z" level=info msg="loading plugin" id=io.containerd.grp
c.v1.sandboxes type=io.containerd.grpc.v1                                                 
time="2026-10-16T14:05:16.049304376Z" level=info msg="loading plugin" id=io.containerd.grp
c.v1.snapshots type=io.containerd.grpc.v1                                                 
time="2026-10-16T14:05:16.049329262Z" level=info msg="loading plugin" id=io.containerd.str
eaming.v1.manager type=io.containerd.streaming.v1                                         
time="2026-10-16T14:05:16.049452705Z" level=info msg="loading plugin" id=io.containerd.grp
c.v1.streaming type=io.containerd.grpc.v1                                                 
time="2026-10-16T14:05:16.049515080Z" level=info msg="loading plugin" id=io.containerd.grp
c.v1.tasks type=io.containerd.grpc.v1                                                     
time="2026-10-16T14:05:16.049933395Z" level=info msg="loading plugin" id=io.containerd.grp
c.v1.transfer type=io.containerd.grpc.v1                                                  
time="2026-10-16T14:05:16.049954013Z" level=info msg="loading plugin" id=io.containerd.grp
c.v1.version type=io.containerd.grpc.v1                                                   
time="2026-10-16T14:05:16.049971599Z" level=info msg="loading plugin" id=io.containerd.mon
itor.container.v1.restart type=io.containerd.monitor.container.v1                         
time="2026-10-16T14:05:16.050103387Z" level=info msg="loading plugin" id=io.containerd.tra
cing.processor.v1.otlp type=io.containerd.tracing.processor.v1                            
time="2026-10-16T14:05:16.050135084Z" level=info msg="skip loading plugin" error="skip plu
gin: tracing endpoint not configured" id=io.containerd.tracing.processor.v1.otlp type=io.c
ontainerd.tracing.processor.v1                                                            
time="2026-10-16T14:05:16.050151145Z" level=info msg="loading plugin" id=io.containerd.int
ernal.v1.tracing type=io.containerd.internal.v1                                           
time="2026-10-16T14:05:16.050170184Z" level=info msg="skip loading plugin" error="skip plu
gin: tracing endpoint not configured" id=io.containerd.internal.v1.tracing type=io.contain
erd.internal.v1                                                                           
time="2026-10-16T14:05:16.050185127Z" level=info msg="loading plugin" id=io.containerd.ttr
pc.v1.otelttrpc type=io.containerd.ttrpc.v1                                               
time="2026-10-16T14:05:16.050203265Z" level=info msg="loading plugin" id=io.containerd.grp
c.v1.healthcheck type=io.containerd.grpc.v1                                               
time="2026-10-16T14:05:16.051553803Z" level=info msg=serving... address=/var/run/docker/co
ntainerd/containerd-debug.sock                                                            
time="2026-10-16T14:05:16.051999764Z" level=info msg=serving... address=/var/run/docker/co
ntainerd/containerd.sock.ttrpc                                                            
time="2026-10-16T14:05:16.052681098Z" level=info msg=serving... address=/var/run/docker/co
ntainerd/containerd.sock                                                                  
time="2026-10-16T14:05:16.052957416Z" level=info msg="containerd successfully booted in 0.
078135s"                                                                                  
time="2026-10-16T14:05:16.073680141Z" level=info msg="OTEL tracing is not configured, usin
g no-op tracer provider"                                                                  
time="2026-10-16T14:05:16.073889952Z" level=info msg="CDI directory does not exist, skippi
ng" dir=/etc/cdi                                                                          
time="2026-10-16T14:05:16.073906817Z" level=info msg="CDI directory does not exist, skippi
ng" dir=/var/run/cdi                                                                      
time="2026-10-16T14:05:16.097752080Z" level=info msg="Creating a containerd client" addres
s=/var/run/docker/containerd/containerd.sock timeout=1m0s                                 
time="2026-10-16T14:05:16.140900804Z" level=info msg="Loading containers: start."         
time="2026-10-16T14:05:16.140992339Z" level=info msg="NRI is disabled"                    
time="2026-10-16T14:05:16.141008104Z" level=info msg="Starting daemon with containerd snap
shotter integration enabled"                                                              
time="2026-10-16T14:05:16.174315710Z" level=info msg="Restoring containers: start."       
time="2026-10-16T14:05:16.199007324Z" level=info msg="Deleting nftables IPv4 rules" error=
"running nft: /dev/stdin:1:17-30: Error: Could not process rule: No such file or directory
\ndelete table ip docker-bridges\n                ^^^^^^^^^^^^^^\n exit status 1"         
time="2026-10-16T14:05:16.214929111Z" level=info msg="Deleting nftables IPv6 rules" error=
"running nft: /dev/stdin:1:18-31: Error: Could not process rule: No such















We hebben de oorzaak nu gevonden. Docker start goed op, maar de runner blijft zichzelf registreren zonder dat hij het registratietoken meekrijgt.
De belangrijke fout is:
.runner is missing or not a regular file
Error: missing token, token-file argument, or
GITEA_RUNNER_REGISTRATION_TOKEN environment variable


De Kubernetes Secret deploy-runner-token bestaat al, maar de Deployment gebruikt die Secret nog niet. In de getoonde omgevingsvariabelen staat alleen CONFIG_FILE.
We gaan dus de bestaande Secret koppelen aan de runner, zonder het token op het scherm te tonen.




Stap 1 — Koppel de Secret aan de runner
Voer dit volledige blok uit. Het koppelt de bestaande Secret via een Kubernetes secretKeyRef, zodat het token niet letterlijk in je commando staat.
echo "=== Token-secret koppelen aan deployment-runner ==="

sudo k3s kubectl patch deployment deploy-runner -n ci \
  --type=strategic \
  -p '{"spec":{"template":{"spec":{"containers":[{"name":"runner","env":[{"name":"GITEA_RUNNER_REGISTRATION_TOKEN","valueFrom":{"secretKeyRef":{"name":"deploy-runner-token","key":"token"}}}]}]}}}}'

echo
echo "=== Wachten tot de nieuwe Pod gestart is ==="
sudo k3s kubectl rollout status deployment/deploy-runner -n ci --timeout=120s

echo
echo "=== Runner-status ==="
sudo k3s kubectl get pods -n ci

echo
echo "=== Nieuwe runner-logs ==="
sudo k3s kubectl logs deployment/deploy-runner -n ci --tail=50


Stap 2 — Controleer Gitea
Open daarna Site Administration → Actions → Runners.
- Als deploy-runner Online of Idle wordt, is de registratie gelukt.
- Als je Successfully registered ziet, is dat ook een goed teken.
- Krijg je een fout over de token of een dubbele registratie, stuur dan de foutmelding door. Plak nooit de tokenwaarde zelf.
Zodra deze runner online is, gaan we de workflow instellen die de website in Kubernetes bijwerkt.
















ms@k3:~/dso-demo-app$ echo "=== Token-secret koppelen aan deployment-runner ==="          
sudo k3s kubectl patch deployment deploy-runner -n ci \                                   
  --type=strategic \                                                                      
  -p '{"spec":{"template":{"spec":{"containers":[{"name":"runner","env":[{"name":"GITEA_RU
NNER_REGISTRATION_TOKEN","valueFrom":{"secretKeyRef":{"name":"deploy-runner-token","key":"
token"}}}]}]}}}}'                                                                         
echo                                                                                      
echo "=== Wachten tot de nieuwe Pod gestart is ==="                                       
sudo k3s kubectl rollout status deployment/deploy-runner -n ci --timeout=120s             
echo                                                                                      
echo "=== Runner-status ==="                                                              
sudo k3s kubectl get pods -n ci                                                           
echo                                                                                      
echo "=== Nieuwe runner-logs ==="                                                         
sudo k3s kubectl logs deployment/deploy-runner -n ci --tail=50                            
=== Token-secret koppelen aan deployment-runner ===                                       
deployment.apps/deploy-runner patched (no change)                                         
=== Wachten tot de nieuwe Pod gestart is ===                                              
deployment "deploy-runner" successfully rolled out                                        
=== Runner-status ===                                                                     
NAME                             READY   STATUS    RESTARTS   AGE                         
deploy-runner-5cd88594cc-blxbm   1/1     Running   0          51s                         
gitea-runner-8cd584d59-cckt6     1/1     Running   0          20h                         
=== Nieuwe runner-logs ===                                                                
time="2026-10-16T14:08:15.871150642Z" level=info msg="Loading containers: start."         
time="2026-10-16T14:08:15.871241039Z" level=info msg="NRI is disabled"                    
time="2026-10-16T14:08:15.871257163Z" level=info msg="Starting daemon with containerd snap
shotter integration enabled"                                                              
time="2026-10-16T14:08:15.901158790Z" level=info msg="Restoring containers: start."       
time="2026-10-16T14:08:15.931466595Z" level=info msg="Deleting nftables IPv4 rules" error=
"running nft: /dev/stdin:1:17-30: Error: Could not process rule: No such file or directory
\ndelete table ip docker-bridges\n                ^^^^^^^^^^^^^^\n exit status 1"         
time="2026-10-16T14:08:15.941190117Z" level=info msg="Deleting nftables IPv6 rules" error=
"running nft: /dev/stdin:1:18-31: Error: Could not process rule: No such file or directory
\ndelete table ip6 docker-bridges\n                 ^^^^^^^^^^^^^^\n exit status 1"       
time="2026-10-16T14:08:16.247840631Z" level=info msg="Loading containers: done."          
time="2026-10-16T14:08:16.264053253Z" level=info msg="Docker daemon" commit=3d80467 contai
nerd-snapshotter=true storage-driver=overlayfs version=29.6.2                             
time="2026-10-16T14:08:16.264254961Z" level=info msg="Initializing buildkit"              
time="2026-10-16T14:08:16.653800796Z" level=info msg="Completed buildkit initialization"  
time="2026-10-16T14:08:16.665554615Z" level=info msg="Daemon has completed initialization"
time="2026-10-16T14:08:16.665726311Z" level=info msg="API listen on /var/run/docker.sock" 
time="2026-10-16T14:08:16.666484826Z" level=info msg="API listen on [::]:2376"            
.runner is missing or not a regular file                                                  
level=info msg="Registering runner, arch=amd64, os=linux, version=v2.3.0."                
level=error msg="Invalid input, please re-run act command." error="instance address is emp
ty"                                                                                       
Error: instance address is empty                                                          
Waiting to retry ...                                                                      
level=info msg="Registering runner, arch=amd64, os=linux, version=v2.3.0."                
level=error msg="Invalid input, please re-run act command." error="instance address is emp
ty"                                                                                       
Error: instance address is empty                                                          
Waiting to retry ...                                                                      
level=info msg="Registering runner, arch=amd64, os=linux, version=v2.3.0."                
level=error msg="Invalid input, please re-run act command." error="instance address is emp
ty"                                                                                       
Error: instance address is empty                                                          
Waiting to retry ...                                                                      
level=info msg="Registering runner, arch=amd64, os=linux, version=v2.3.0."                
level=error msg="Invalid input, please re-run act command." error="instance address is emp
ty"                                                                                       
Error: instance address is empty                                                          
Waiting to retry ...                                                                      
level=info msg="Registering runner, arch=amd64, os=linux, version=v2.3.0."                
level=error msg="Invalid input, please re-run act command." error="instance address is emp
ty"                                                                                       
Error: instance address is empty                                                          
Waiting to retry ...                                                                      
level=info msg="Registering runner, arch=amd64, os=linux, version=v2.3.0."                
level=error msg="Invalid input, please re-run act command." error="instance address is emp
ty"                                                                                       
Error: instance address is empty                                                          
Waiting to retry ...                                                                      
level=info msg="Registering runner, arch=amd64, os=linux, version=v2.3.0."                
level=error msg="Invalid input, please re-run act command." error="instance address is emp
ty"                                                                                       
Error: instance address is empty                                                          
Waiting to retry ...                                                                      
level=info msg="Registering runner, arch=amd64, os=linux, version=v2.3.0."                
level=error msg="Invalid input, please re-run act command." error="instance address is emp
ty"                                                                                       
Error: instance address is empty                                                          
Waiting to retry ...                                                                      
level=info msg="Registering runner, arch=amd64, os=linux, version=v2.3.0."                
level=error msg="Invalid input, please re-run act command." error="instance address is emp
ty"                                                                                       
Error: instance address is empty                                                          
Waiting to retry ...                                                                      
ms@k3:~/dso-demo-app$















Goed, we zijn weer een stap verder. De token wordt nu herkend: de foutmelding over het ontbrekende token is verdwenen. De nieuwe fout vertelt ons precies wat er nog ontbreekt:
Error: instance address is empty


De runner heeft dus nog geen Gitea-serveradres in zijn configuratie. We voegen dat toe aan de Deployment. Je Gitea-adres is http://gitea.10.24.20.224.sslip.io.
Stap 1 — Voeg het Gitea-adres toe
Voer dit volledige blok uit:
echo "=== Gitea-adres instellen ==="

sudo k3s kubectl set env deployment/deploy-runner -n ci \
  GITEA_INSTANCE_URL=http://gitea.10.24.20.224.sslip.io

echo
echo "=== Wachten op de nieuwe runner ==="

sudo k3s kubectl rollout status deployment/deploy-runner \
  -n ci --timeout=120s

echo
echo "=== Runner-status ==="

sudo k3s kubectl get pods -n ci

echo
echo "=== Runner-logs ==="

sudo k3s kubectl logs deployment/deploy-runner -n ci --tail=60


Waarom doen we dit? De runner heeft twee dingen nodig om zichzelf te registreren:
- GITEA_RUNNER_REGISTRATION_TOKEN: het token uit de Kubernetes Secret.
- GITEA_INSTANCE_URL: het adres van je Gitea-server.
We hebben het eerste al gekoppeld; nu voegen we het tweede toe.
Stap 2 — Controleer of hij online komt
Als de logs Runner registered successfully of een vergelijkbare succesvolle registratie tonen, kijk dan in Gitea bij Site Administration → Actions → Runners.
Als hij nog niet online is, stuur dan de nieuwe logs door. Deel daarbij geen tokenwaarden. Zodra de runner werkt, gaan we de deployment-workflow afmaken zodat een wijziging in je Git-repository de website in Kubernetes kan bijwerken.

