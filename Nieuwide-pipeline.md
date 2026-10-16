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

