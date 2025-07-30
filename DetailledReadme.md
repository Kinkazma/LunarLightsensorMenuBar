# Guide détaillé d’installation et d’utilisation

Ce document décrit étape par étape comment préparer votre environnement, créer une intégration OAuth 2.0 avec SmartThings et configurer Lunar Sensor MenuBar. L’application permet de relayer les mesures d’un capteur de luminosité SmartThings vers Lunar afin de régler automatiquement la luminosité de votre écran lorsque votre téléviseur est connecté.
## Présentation de l’application
Lunar Sensor MenuBar est une utilitaire macOS. Lorsqu’un téléviseur externe est détecté, l’application cesse d’utiliser le capteur de luminosité interne du Mac et interroge un capteur SmartThings toutes les n secondes pour récupérer la valeur de luminosité (en lux). Ces données sont ensuite exposées sur 127.0.0.1:10001/sensor/ambient_light afin que Lunar puisse ajuster la luminosité de vos écrans. Quand votre téléviseur est absent, Lunar revient automatiquement au capteur interne du Mac.

## Prérequis
•	Un Mac avec macOS et Xcode pour compiler l’application.
•	Lunar installé et configuré pour utiliser un capteur HTTP.
•	Un compte Samsung/SmartThings (gratuit). Le développement SmartThings s’appuie sur votre compte Samsung. La documentation officielle précise qu’il faut « Se connecter à son compte Samsung puis se connecter à la Developer Workspace »[1].
•	L’outil en ligne de commande SmartThings CLI (utilisable via Homebrew sur macOS).
•	Un capteur de luminosité (par exemple un capteur Zigbee SmartThings) déjà associé à votre compte SmartThings.

## 1 – Créer ou activer votre compte SmartThings développeur
1.	Rendez‑vous sur account.samsung.com et créez un compte Samsung si vous n’en possédez pas déjà un. Ce compte est utilisé par toutes les applications Samsung, y compris SmartThings.
2.	Ouvrez ensuite la SmartThings Developer Workspace et cliquez sur « Sign In With Samsung Account » pour vous connecter. La documentation rappelle qu’il est nécessaire de « se connecter à son compte Samsung et à la Developer Workspace » avant de créer une SmartApp[1].
3.	Lors de la première connexion au Workspace, suivez les instructions pour accepter les conditions d’utilisation et activer votre accès développeur.

## 2 – Installer Homebrew et la SmartThings CLI
### 2.1 Installer Homebrew (si nécessaire)
Homebrew est le gestionnaire de paquets recommandé pour macOS. La page officielle d’Homebrew indique que l’installation se fait en exécutant le script suivant dans le Terminal :

	/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
Après l’installation, suivez les instructions qui s’affichent pour ajouter Homebrew à votre PATH. La documentation officielle recommande cette commande et précise qu’il suffit de la coller dans votre terminal[2].
### 2.2 Installer la SmartThings CLI
La SmartThings CLI permet de créer et gérer des SmartApps depuis le terminal. Sur macOS elle s’installe via Homebrew :
	
	brew install smartthingscommunity/smartthings/smartthings
Les instructions d’installation sur le dépôt officiel indiquent qu’il faut utiliser Homebrew et exécuter brew install smartthingscommunity/smartthings/smartthings[3]. Une fois installé, vérifiez la version :

	smartthings --version
Lors de la première utilisation, la CLI ouvre votre navigateur et vous demande de vous authentifier sur votre compte Samsung/SmartThings. Cette authentification automatique est décrite dans la documentation : « La CLI lance une fenêtre de navigateur pour vous connecter et donner l’autorisation… »[4]. Suivez les instructions à l’écran ; la CLI stocke alors un jeton d’accès localement.
	
#### 💡 Astuce : exécutez :
	smartthings --help 
Pour consulter la liste complète des commandes disponibles.

## 3 – Créer une SmartApp OAuth2
L’application utilise le flux OAuth2 « Authorization Code » pour accéder au capteur. Vous devez donc créer une OAuth‑In SmartApp via la CLI :
Dans le terminal, lancez :

	smartthings apps:create
	
La CLI vous pose une série de questions. D’après la documentation OAuth Integrations, sur macOS il faut « exécuter smartthings apps:create et choisir l’application OAuth appropriée »[5], puis fournir :

1.	Nom d’affichage : libellé apparaissant dans l’application SmartThings. Choisissez par exemple « Lunar Sensor MenuBar ».
2.	Description : courte description pour identifier l’intégration.
3.	Icone (URL) : facultatif (laisser vide si vous n’en avez pas).
4.	Target URL : laissez vide (notre application n’héberge pas de webhook).
5.	Permissions (scopes) : sélectionnez les permissions r:devices:*, w:devices:* et x:devices:*. Ces scopes sont nécessaires pour lire les informations d’un appareil, écrire et exécuter des commandes. Un tutoriel confirme que, lors de la création, on choisit ces scopes [6].
6.	Redirect URI : ajoutez une URL HTTPS valide vers laquelle SmartThings pourra rediriger l’utilisateur après l’autorisation. Un exemple courant est https://httpbin.org/get[7], mais vous pouvez utiliser n’importe quelle URL en HTTPS (elle n’a pas besoin d’exister dans notre cas ; seuls le domaine et le protocole doivent être valides).
7.	À la fin, la CLI affiche un récapitulatif des informations saisies ainsi qu’une section OAuth Info contenant le client id et le client secret. Les informations ne seront plus affichées ensuite, notez‑les soigneusement. Le tutoriel illustre cette étape et montre que l’on obtient un OAuth Client Id et un OAuth Client Secret[8].
8.	Conservez également le Redirect URI que vous avez déclaré et les permissions choisies ; elles devront être renseignées dans l’application.

## 4 – Générer les jetons OAuth (Code d’autorisation et jetons)
L’étape suivante consiste à obtenir un code d’autorisation, puis à l’échanger contre un jeton d’accès et un jeton de rafraîchissement.
### 4.1 Construire l’URL d’autorisation
Pour obtenir le code d’autorisation, construisez une URL selon le modèle suivant :
	
	https://api.smartthings.com/oauth/authorize?client_id=<CLIENT_ID>&response_type=code&redirect_uri=<REDIRECT_URI>&scope=r:devices:*+w:devices:*+x:devices:*

Remplacez <CLIENT_ID> par votre client id et <REDIRECT_URI> par l’URI de redirection définie précédemment. Le guide « SmartThings API : Taming the OAuth 2.0 Beast » propose un exemple d’URL où les scopes sont concaténés par des symboles +[9].
Ouvrez cette URL dans votre navigateur, connectez‑vous à votre compte Samsung/SmartThings et cliquez sur Autoriser. Vous êtes redirigé vers votre redirect_uri et l’URL contient un paramètre code=<valeur>. Copiez cette valeur : c’est votre code d’autorisation.

### 4.2 Échanger le code contre des jetons

L’échange s’effectue via une requête HTTP POST vers https://api.smartthings.com/oauth/token avec les paramètres suivants :

	grant_type=authorization_code client_id=<CLIENT_ID> client_secret=<CLIENT_SECRET> redirect_uri=<REDIRECT_URI> code=<AUTH_CODE> scope=r:devices:*+w:devices:*+x:devices:*
 
Vous pouvez utiliser un outil comme curl ou Postman pour envoyer cette requête. Le même tutoriel fournit un exemple avec curl montrant l’envoi des paramètres encodés et la récupération du access_token et du refresh_token[10]. La réponse JSON contient :

•	access_token : token à courte durée de vie (24 heures maximum[11]) utilisé pour interroger l’API SmartThings ;
•	refresh_token : token valable 30 jours qui permet d’obtenir un nouvel access_token sans repasser par l’étape d’autorisation[11] ;
•	expires_in : durée de validité du jeton d’accès en secondes.

Enregistrez précieusement votre refresh_token ; l’application Lunar Sensor MenuBar utilise ce jeton pour renouveler automatiquement l’accès. L’access_token initial peut également être renseigné, mais il sera rafraîchi à l’exécution.

#### Remarque : si vous utilisez un outil graphique comme Postman, veillez à encoder les paramètres en x-www-form-urlencoded et à ajouter un en‑tête Authorization: Basic … où … est la chaîne Base64 de client_id:client_secret. Cet en‑tête est illustré dans l’exemple de la documentation[12].
 
## 5 – Obtenir l’identifiant du capteur (Device ID)
L’application a besoin de l’identifiant unique du capteur de luminosité afin de récupérer ses mesures. Voici comment l’obtenir :
1.	Ouvrez votre navigateur et connectez‑vous à l’ancienne console SmartThings à l’adresse account.smartthings.com (utilisez les mêmes identifiants que sur l’application).
2.	Une fois sur le tableau de bord, cliquez sur le capteur dont vous souhaitez récupérer la luminosité. La documentation d’un plugin Homebridge explique que lorsqu’on clique sur un appareil, « un popup s’ouvre et sur la gauche se trouve le device_id (par exemple 5d9215vx-c421-4e12-a998-c4ec48754f08) »[13]. Copiez la valeur indiquée.
3.	Ce Device ID correspond au capteur de luminosité (et non à la télévision) et devra être renseigné dans l’application.

## 6 – Déterminer le nom de votre téléviseur (TV Name)
L’application détecte la présence de votre téléviseur en analysant la sortie de la commande system_profiler SPDisplaysDataType. Le nom affiché doit donc être identique à celui retourné par macOS :
1.	Ouvrez le Terminal et exécutez :
	
		system_profiler SPDisplaysDataType
2.	La sortie contient une section Displays indiquant les écrans connectés. L’exemple donné sur Ask Different montre des entrées comme « iMac » ou « P2214H »[14]. Repérez la ligne correspondant à votre télévision et notez‑en l’intitulé exact.
3.	Ce texte (sensible à la casse et aux espaces) est le TV Name à saisir dans la configuration. Lorsqu’il est présent dans la sortie de system_profiler, l’application passe automatiquement en mode SmartThings.

## 7 – Compiler et lancer l’application
1.	Décompressez le dossier LunarSensorMenuBar et ouvrez le projet dans Xcode (LunarSensorAppMenuBar.xcodeproj).
2.	Sélectionnez votre cible et cliquez sur Run pour compiler et lancer l’application. Un nouvel icône apparaîtra dans votre barre de menus.
3.	Depuis ce menu, ouvrez Connexion → Renseignez vos données. Saisissez les valeurs récupérées :
4.	TV Name : nom exact du téléviseur récupéré via system_profiler ;
5.	Client ID et Client Secret : obtenus lors de la création de l’app via la CLI ;
6.	Refresh Token : issu de l’échange du code d’autorisation ;
7.	Device ID : identifiant du capteur de luminosité ;
8.	Redirect URI : l’URI utilisée pendant la création (ex. https://httpbin.org/get).
9.	Validez. L’application enregistre ces paramètres, initialise les jetons via OAuthManager et commence à interroger SmartThings lorsque le téléviseur est détecté.

## 8 – Utilisation du menu et description des fonctions
Une fois configurée, Lunar Sensor MenuBar propose plusieurs actions accessibles depuis l’icône de la barre de menus :
	
 ### Élément du menu
 ### Fonction
Luminosité : X lux
Affiche la dernière mesure (brute ou recalculée). Cliquer sur ce texte copie la valeur en lux dans le presse‑papiers.
 
#### TV Name : connecté / non connecté
Indique si le téléviseur configuré est actuellement détecté. Lorsque l’état passe à « connecté », l’application interroge SmartThings toutes les n secondes ; sinon elle repasse au capteur intégré.
 
#### Délai de rafraîchissement
Sous‑menu permettant de choisir l’intervalle entre deux requêtes vers SmartThings (10 s, 20 s, 30 s, 1 min, 2 min ou 8 min). Un intervalle court offre une réactivité optimale mais augmente le trafic réseau et la sollicitation du capteur.
 
#### Seconde coulante
Active un lissage des transitions de luminosité. Lorsqu’elle est cochée, les changements de luminosité se font progressivement par petites marches plutôt que par à‑coups.
 
#### Nombre d’intervalles
Ce sous‑menu n’apparaît que si Seconde coulante est activée. Il permet de choisir entre 10 et 100 intervalles : plus le nombre est élevé, plus la transition est douce et longue.
 
#### Connexion → Renseignez vos données
Ouvre la fenêtre de configuration pour modifier le TV Name, le Client ID, le Client Secret, le Refresh Token, le Device ID et l’URI de redirection.
 
#### Connexion → Vérifier les jetons
Effectue une requête de test vers SmartThings afin de vérifier la validité des jetons stockés. Si les jetons sont valides, une alerte « Jetons valides » s’affiche ; sinon, on vous conseille de ré‑autoriser l’application.
 
#### Connexion → Reconnecter SmartThings
Génère automatiquement l’URL d’autorisation selon votre configuration et l’ouvre dans votre navigateur. Après avoir autorisé l’accès, copiez le paramètre code de l’URL et collez‑le dans la boîte de dialogue qui s’ouvre ; l’application échange le code contre de nouveaux jetons et les enregistre.
 
#### Imposer l’échelle
Force l’application à convertir les valeurs de lux en pourcentage (2 lx → 10 %, 800 lx → 100 %). Ce mode peut être utile si vous souhaitez que Lunar reçoive une valeur toujours comprise entre 0 et 800, indépendamment de la gamme de votre capteur.
 
#### Exporter les logs
Sauvegarde le fichier de journal dans votre dossier Téléchargements pour analyse ou partage.
 
#### Quitter
Ferme l’application et arrête le serveur HTTP local.
 
## 9 – Conseils et dépannage
•	TV non détectée ? Vérifiez que le nom saisi dans TV Name correspond exactement à celui affiché par system_profiler. Les minuscules/majuscules et les espaces comptent. Vous pouvez aussi activer dans le code la version alternative de isTVDected() qui détecte tout écran « non‑Apple » (voir les commentaires dans StatusBarController.swift).
•	Jetons expirés : si la vérification des jetons échoue, utilisez le menu Reconnecter SmartThings pour générer un nouveau code d’autorisation. Pensez également à mettre à jour le refresh_token dans la configuration si vous l’avez régénéré via Postman.
•	Erreur lors de la création de la SmartApp : assurez‑vous d’avoir choisi les bons scopes et d’avoir saisi une URI de redirection en HTTPS. L’outil smartthings apps:create vous guidera étape par étape[15].
•	Installation de la CLI impossible : vérifiez que Homebrew est installé correctement en exécutant brew doctor. Suivez ensuite les conseils de l’installateur Homebrew pour corriger les éventuels problèmes[2].

#### En suivant ce guide, vous devriez disposer d’une intégration complète entre votre capteur de luminosité SmartThings et Lunar. L’application se charge ensuite de la gestion des jetons et du rafraîchissement automatique pour que la synchronisation de la luminosité reste transparente.

##### [1] Developer Documentation | SmartThings
	https://developer.smartthings.com/docs/connected-services/create-a-smartapp
##### [2] Homebrew — The Missing Package Manager for macOS (or Linux)
	https://brew.sh/
##### [3] [4] GitHub - SmartThingsCommunity/smartthings-cli: Command-line Interface for the SmartThings APIs.
	https://github.com/SmartThingsCommunity/smartthings-cli
##### [5] [15] Developer Documentation | SmartThings
	https://developer.smartthings.com/docs/connected-services/oauth-integrations
##### [6] [7] [8] [9] [10] [11] [12] SmartThings API: Taming the OAuth 2.0 Beast | by Shashank Mayya | Level Up Coding
	https://levelup.gitconnected.com/smartthings-api-taming-the-oauth-2-0-beast-5d735ecc6b24
##### [13] SmartThings API | Homebridge Samsung Tizen
	https://tavicu.github.io/homebridge-samsung-tizen/configuration/smartthings-api.html
##### [14] terminal - Get Number of Screens Using system_profiler - Ask Different
	https://apple.stackexchange.com/questions/254922/get-number-of-screens-using-system-profiler
