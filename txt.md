
Pasted markdown.md
Document
We hebben de oorzaak gevonden! De logs zeggen precies wat er misgaat:

.runner is missing or not a regular file
Error: missing token, token-file argument, or GITEA_RUNNER_REGISTRATION_TOKEN environment variable
De Kubernetes-pod probeert zichzelf te registreren, maar heeft geen registratietoken. Daarom blijft deploy-runner offline. Je hoeft niets opnieuw te installeren.

Stap 34 — Stop de herhaalde registratiepogingen
Voer dit uit:

sudo k3s kubectl scale deployment deploy-runner -n ci --replicas=0

Hiermee stoppen we tijdelijk de pod die zonder token blijft proberen te registreren. Je bestaande gitea-runner blijft draaien.

Stap 35 — Maak de registratietoken veilig beschikbaar
We slaan de token op als een Kubernetes Secret, in plaats van hem rechtstreeks in het Deployment-bestand te zetten.

Open Gitea en ga naar Site Administration → Actions → Runners.

Zoek de registratieoptie voor een runner en kopieer een geldige registratietoken. Gebruik geen token van je bestaande runner als Gitea een nieuwe token kan aanmaken.

Voer op k3 de volgende opdracht uit. Je wordt gevraagd om de token in te voeren; de waarde wordt niet in de opdrachtregel gezet.

read -rsp 'Gitea registratietoken: ' RUNNER_TOKEN
echo
printf '%s' "$RUNNER_TOKEN" | sudo k3s kubectl create secret generic deploy-runner-token \
  -n ci \
  --from-file=token=/dev/stdin
unset RUNNER_TOKEN

Als het Secret al bestaat, meldt Kubernetes dat. Maak het dan niet zomaar opnieuw aan; laat me weten wat de melding is.

Stap 36 — Belangrijk: eerst de configuratie aanpassen
We hebben nu de oorzaak vastgesteld, maar we zijn er nog niet: de runner moet de token gebruiken om zich te registreren en vervolgens de opgeslagen .runner-gegevens hergebruiken. Daarna moet hij verbinding maken met Gitea en online komen.

Voer stap 34 en 35 uit en stuur de uitvoer. Deel de token zelf niet. Daarna pas ik de Deployment-configuratie aan zodat de token als bestand beschikbaar is en de runner correct kan registreren.

waar heeft die dit opgeslagen ,btw het is gelukt dus kunne ook verder
Top, dan gaan we verder! 🙌

1. Waar is het opgeslagen?
Als je het over het Gitea-runnerregistratietoken hebt: we hebben dat opgeslagen als een Kubernetes Secret in namespace ci, met de naam deploy-runner-token.

Je kunt controleren of die bestaat met:

sudo k3s kubectl get secret deploy-runner-token -n ci

De token zelf staat dus in Kubernetes opgeslagen, niet als leesbaar tekstbestand op je Ubuntu-server. Kubernetes bewaart Secrets in zijn clusteropslag; ze zijn niet automatisch versleuteld op schijf.

De runnerconfiguratie en bijbehorende bestanden staan daarnaast op deze locaties:

Bestand/map

Waarvoor?

/etc/act_runner-deploy/config.yaml

Configuratie van de deployment-runner

/var/lib/act_runner-deploy

Gegevens van de deployment-runner

Kubernetes Secret deploy-runner-token in namespace ci

Registratietoken

2. Laten we controleren of alles werkt
Voer deze commando's uit op je Ubuntu-VM:

echo "=== Runner-pods ==="
sudo k3s kubectl get pods -n ci -o wide

echo
echo "=== Runner-deployments ==="
sudo k3s kubectl get deployments -n ci

echo
echo "=== Registratie-Secret ==="
sudo k3s kubectl get secret deploy-runner-token -n ci

echo
echo "=== Website ==="
curl -fsS http://demo.10.24.20.224.sslip.io/

Controleer ook in Gitea bij Site Administration → Actions → Runners of deploy-runner nu Idle of Online is.

3. Daarna bouwen we de automatische deployment
Het doel is dat onze pipeline dit automatisch doet:

Je wijzigt index.html in je Gitea-repository.

De CI-workflow controleert de HTML en voert de Trivy-scan uit.

Je start de deployment-workflow.

De deployment-runner werkt de website bij in Kubernetes.

Je controleert de nieuwe versie via http://demo.10.24.20.224.sslip.io/.

De CI-controles hebben we al werkend; nu moeten we de deployment-workflow echt laten aanpassen wat Kubernetes serveert.

Plak de uitvoer van de commando's hierboven hier. Dan kan ik je de volgende reeks commando's geven om de deployment verder af te maken, zonder onnodig veel heen-en-weer.

/dso-demo-app$ echo "=== Runner-pods ==="                                          

sudo k3s kubectl get pods -n ci -o wide                                                   

echo                                                                                      

echo "=== Runner-deployments ==="                                                         

sudo k3s kubectl get deployments -n ci                                                    

echo                                                                                      

echo "=== Registratie-Secret ==="                                                         

sudo k3s kubectl get secret deploy-runner-token -n ci                                     

echo                                                                                      

echo "=== Website ==="                                                                    

curl -fsS http://demo.10.24.20.224.sslip.io/                                              

=== Runner-pods ===                                                                       

NAME                           READY   STATUS    RESTARTS   AGE   IP           NODE   NOMI

NATED NODE   READINESS GATES                                                              

gitea-runner-8cd584d59-cckt6   1/1     Running   0          20h   10.42.0.30   k3     

e>                                                                                  

=== Runner-deployments ===                                                                

NAME            READY   UP-TO-DATE   AVAILABLE   AGE                                      

deploy-runner   0/0     0            0           4m34s                                    

gitea-runner    1/1     1            1           20h                                      

=== Registratie-Secret ===                                                                

NAME                  TYPE     DATA   AGE                                                 

deploy-runner-token   Opaque   1      93s                                                 

=== Website ===                                                                           

Mijn DevSecOps-demo
Hallo mensen!

Versie: 1.0

Status: applicatie draait in Kubernetes.

ms@k3:~/dso-demo-app$

…
Mooi, de website werkt nog en het registratietoken is opgeslagen. We zien ook meteen wat er nog moet gebeuren: deploy-runner staat op 0/0. Dat betekent dat Kubernetes momenteel geen Pod voor deze Deployment draait. De gewone gitea-runner draait wel.

We gaan de deployment-runner eerst starten en controleren of die in Gitea online komt.

Stap 1 — Start de deployment-runner
Voer dit uit op je Ubuntu-VM:

sudo k3s kubectl scale deployment deploy-runner -n ci --replicas=1

echo "=== Wachten op de runner ==="
sudo k3s kubectl rollout status deployment/deploy-runner -n ci --timeout=120s

echo
echo "=== Runner-pods ==="
sudo k3s kubectl get pods -n ci -o wide

echo
echo "=== Runner-logs ==="
sudo k3s kubectl logs deployment/deploy-runner -n ci --tail=60

Dit zet het gewenste aantal replica's op één, wacht maximaal twee minuten en toont vervolgens de logs.

Stap 2 — Controleer de status in Gitea
Open Gitea en ga naar Site Administration → Actions → Runners.

Controleer of deploy-runner nu Idle of Online aangeeft. Als de Pod blijft herstarten, of de logs een foutmelding tonen, kunnen we die gericht oplossen.

Stap 3 — Daarna maken we de deployment-workflow af
Zodra de runner online is, maken we .gitea/workflows/deploy.yaml zo dat hij de HTML uit je repository naar de Kubernetes-website publiceert. We testen daarna of een wijziging van versie 1.0 naar 1.1 daadwerkelijk zichtbaar wordt op:

http://demo.10.24.20.224.sslip.io/

Voer eerst stap 1 uit en stuur de uitvoer hier. Dan bouwen we verder op de werkelijke status van je cluster, zonder te gokken.

ms@k3:~/dso-demo-app$ sudo k3s kubectl scale deployment deploy-runner -n ci --replicas=1  
echo "=== Wachten op de runner ==="                                                       
sudo k3s kubectl rollout status deployment/deploy-runner -n ci --timeout=120s             
echo                                                                                      
echo "=== Runner-pods ==="                                                                
sudo k3s kubectl get pods -n ci -o wide                                                   
echo                                                                                      
echo "=== Runner-logs ==="                                                                
sudo k3s kubectl logs deployment/deploy-runner -n ci --tail=60                            
deployment.apps/deploy-runner scaled                                                      
=== Wachten op de runner ===                                                              
Waiting for deployment "deploy-runner" rollout to finish: 0 of 1 updated replicas are avai
lable...                                                                                  
deployment "deploy-runner" successfully rolled out                                        
=== Runner-pods ===                                                                       
NAME                             READY   STATUS    RESTARTS   AGE   IP           NODE   NO
MINATED NODE   READINESS GATES                                                            
deploy-runner-77b9b96d64-twl99   1/1     Running   0          1s    10.42.0.34   k3     
one>                                                                                
gitea-runner-8cd584d59-cckt6     1/1     Running   0          20h   10.42.0.30   k3     
one>                                                                                
=== Runner-logs ===                                                                       
Waiting for Docker daemon to start...                                                     
ms@k3:~/dso-demo-app$                                                                     maarr nog steeds offline

…
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

…
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

Als deploy-runner Online of Idle wordt, is de registratie gelukt.

Als je Successfully registered ziet, is dat ook een goed teken.

Krijg je een fout over de token of een dubbele registratie, stuur dan de foutmelding door. Plak nooit de tokenwaarde zelf.

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

…
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

GITEA_RUNNER_REGISTRATION_TOKEN: het token uit de Kubernetes Secret.

GITEA_INSTANCE_URL: het adres van je Gitea-server.

We hebben het eerste al gekoppeld; nu voegen we het tweede toe.

Stap 2 — Controleer of hij online komt
Als de logs Runner registered successfully of een vergelijkbare succesvolle registratie tonen, kijk dan in Gitea bij Site Administration → Actions → Runners.

Als hij nog niet online is, stuur dan de nieuwe logs door. Deel daarbij geen tokenwaarden. Zodra de runner werkt, gaan we de deployment-workflow afmaken zodat een wijziging in je Git-repository de website in Kubernetes kan bijwerken.

