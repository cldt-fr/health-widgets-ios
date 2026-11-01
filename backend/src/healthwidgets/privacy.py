"""Privacy policy served at ``/privacy``, to link from the App Store listing.

It describes what this server really stores and for how long (see db.py and service.py):
keep both in sync. Who runs the server comes from the ``HW_PRIVACY_*`` settings.
"""

from __future__ import annotations

from datetime import date
from html import escape
from string import Template

from .config import Settings

UPDATED = date(2026, 11, 1)
SOURCE_URL = "https://github.com/cldt-fr/health-widgets-ios"

_MONTHS = (
    "janvier", "février", "mars", "avril", "mai", "juin",
    "juillet", "août", "septembre", "octobre", "novembre", "décembre",
)  # fmt: skip


def _french_date(day: date) -> str:
    return f"{'1er' if day.day == 1 else day.day} {_MONTHS[day.month - 1]} {day.year}"


def _mailto(address: str) -> str:
    safe = escape(address, quote=True)
    return f'<a href="mailto:{safe}">{safe}</a>'


def render_privacy_policy(settings: Settings) -> str:
    operator = (settings.privacy_operator or "").strip()
    contact = (settings.privacy_contact or "").strip()
    hosting = (settings.privacy_hosting or "").strip()

    if operator and contact:
        controller = (
            f"Ce serveur est exploité par {escape(operator)}, joignable à {_mailto(contact)}."
        )
    elif operator:
        controller = f"Ce serveur est exploité par {escape(operator)}."
    elif contact:
        controller = f"Ce serveur est exploité par la personne joignable à {_mailto(contact)}."
    else:
        controller = (
            "Ce serveur est exploité par la personne qui l'a installé : "
            "adressez-vous à elle pour toute question."
        )

    return _PAGE.substitute(
        updated=_french_date(UPDATED),
        controller=controller,
        hosting=escape(hosting) if hosting else "l'hébergeur choisi par l'exploitant du serveur",
        contact=f"écrivez à {_mailto(contact)}."
        if contact
        else ("adressez-vous à la personne qui exploite ce serveur."),
        source=SOURCE_URL,
        source_label=SOURCE_URL.removeprefix("https://"),
    )


_PAGE = Template("""<!doctype html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Confidentialité · Health Widgets</title>
<style>
  :root {
    color-scheme: light dark;
    --bg: #f5f6fa; --card: #ffffff; --text: #1d1d1f; --muted: #6e6e73;
    --line: #e4e4ea; --accent: #0a6cff;
  }
  @media (prefers-color-scheme: dark) {
    :root { --bg: #000000; --card: #1c1c1e; --text: #f5f5f7; --muted: #a1a1a6;
            --line: #2c2c2e; --accent: #4c9dff; }
  }
  * { box-sizing: border-box; }
  body {
    margin: 0; background: var(--bg); color: var(--text);
    font: 16px/1.6 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
    -webkit-text-size-adjust: 100%;
  }
  main { max-width: 720px; margin: 0 auto; padding: 40px 16px 64px; }
  h1 { font-size: 30px; line-height: 1.2; margin: 0 0 6px; }
  .updated { color: var(--muted); margin: 0 0 24px; }
  section {
    background: var(--card); border: 1px solid var(--line); border-radius: 18px;
    padding: 6px 22px 12px; margin: 0 0 14px;
  }
  h2 { font-size: 19px; margin: 16px 0 6px; }
  ul { padding-left: 20px; margin: 8px 0; }
  li { margin: 7px 0; }
  a { color: var(--accent); overflow-wrap: anywhere; }
</style>
</head>
<body>
<main>
<h1>Politique de confidentialité</h1>
<p class="updated">Health Widgets · mise à jour le $updated</p>

<section>
<p>Health Widgets est une application iOS qui affiche les données de votre montre de sport
dans des widgets. Elle s'appuie sur un serveur qui récupère ces données auprès de Garmin
Connect pour votre compte. Cette page explique quelles données ce serveur et l'app
traitent, pourquoi, combien de temps, et comment exercer vos droits.</p>
</section>

<section>
<h2>Responsable du traitement</h2>
<p>$controller</p>
</section>

<section>
<h2>Données traitées</h2>
<ul>
<li><strong>Identifiants Garmin.</strong> Votre adresse e-mail et votre mot de passe Garmin
transitent une seule fois, chiffrés (HTTPS), pour obtenir des jetons d'accès auprès de
Garmin. Ils ne sont jamais enregistrés.</li>
<li><strong>Jetons d'accès Garmin.</strong> Ils permettent de lire vos données sans
redemander votre mot de passe. Ils sont chiffrés et se renouvellent automatiquement.</li>
<li><strong>Profil Garmin.</strong> Identifiant de profil, nom d'affichage, nom complet et
système d'unités, pour indiquer quel compte est connecté.</li>
<li><strong>Données de santé et d'entraînement.</strong> Pas, calories, minutes intensives,
fréquence cardiaque, stress, énergie (Body Battery), sommeil, variabilité cardiaque (VFC),
disposition et charge d'entraînement, activités, séances planifiées, prédictions de course
et VO2 max. Le serveur les lit auprès de Garmin quand l'app ou un widget les demande.</li>
<li><strong>Appareil.</strong> Un jeton aléatoire identifie votre iPhone auprès du serveur,
qui n'en garde qu'une empreinte (SHA-256), avec le type d'appareil (« iPhone ») et les
dates d'inscription et de dernière utilisation.</li>
<li><strong>Tentatives de connexion.</strong> Leur date, pour limiter les essais et protéger
votre compte Garmin.</li>
<li><strong>Journaux techniques.</strong> Adresse IP, date et requête, pour la sécurité et
le diagnostic.</li>
</ul>
</section>

<section>
<h2>Pourquoi, et sur quelle base</h2>
<ul>
<li>Afficher vos données dans l'app et ses widgets : c'est le service que vous demandez
(article 6.1.b du RGPD). Pour vos données de santé, la base est votre consentement explicite
(article 9.2.a), donné en connectant votre compte Garmin. Vous pouvez le retirer à tout
moment en déconnectant Garmin ou en supprimant votre compte.</li>
<li>Sécuriser le service (limite des tentatives de connexion, journaux) : intérêt légitime
(article 6.1.f).</li>
</ul>
<p>Aucune publicité, aucun profilage, aucune revente de données, aucun outil d'analyse ou de
pistage.</p>
</section>

<section>
<h2>Durées de conservation</h2>
<ul>
<li>Jetons et profil Garmin : jusqu'à ce que vous déconnectiez Garmin ou supprimiez votre
compte.</li>
<li>Synthèse quotidienne de vos données, chiffrée : les 14 derniers jours, pour que les
widgets restent lisibles si Garmin est momentanément indisponible. Elle est effacée quand
vous déconnectez Garmin.</li>
<li>Réponses brutes de Garmin : en mémoire vive uniquement, le temps qu'elles restent à jour
(de quelques minutes à 30 jours selon la donnée). Elles ne sont jamais écrites sur
disque.</li>
<li>Connexion en deux étapes en cours : elle expire au bout de 10 minutes et est supprimée
dans l'heure.</li>
<li>Tentatives de connexion : un jour.</li>
<li>Compte et appareil : jusqu'à la suppression de votre compte.</li>
<li>Journaux techniques : durée limitée, par rotation automatique.</li>
</ul>
</section>

<section>
<h2>Destinataires</h2>
<ul>
<li><strong>Garmin</strong> : le serveur interroge Garmin Connect avec vos jetons. Garmin reste
responsable des données de votre compte Garmin
(<a href="https://www.garmin.com/fr-FR/privacy/">centre de confidentialité de Garmin</a>).
Health Widgets n'est pas affilié à Garmin.</li>
<li><strong>Hébergement</strong> : $hosting.</li>
</ul>
<p>Vos données ne sont ni vendues ni transmises à d'autres tiers.</p>
</section>

<section>
<h2>Sur votre iPhone</h2>
<p>L'app garde son jeton d'appareil dans le trousseau iOS, et une copie de la dernière
synthèse pour les widgets. Elle ne contient ni publicité, ni outil d'analyse, ni kit de
développement tiers. Le mode démo fonctionne entièrement sur l'iPhone, sans contacter le
serveur.</p>
</section>

<section>
<h2>Sécurité</h2>
<p>Les échanges sont chiffrés (HTTPS). Sur le serveur, les jetons Garmin, les connexions en
deux étapes en cours et les synthèses sont chiffrés (AES). Votre mot de passe Garmin n'est
jamais stocké. Le code source est public : <a href="$source">$source_label</a>.</p>
</section>

<section>
<h2>Vos droits</h2>
<p>Vous pouvez accéder à vos données, les rectifier, les effacer, les récupérer, vous opposer
à leur traitement et retirer votre consentement. Dans l'app,
<strong>Réglages &rsaquo; Supprimer mon compte et mes données</strong> efface immédiatement du
serveur votre compte, vos jetons et vos synthèses. Pour toute autre demande, $contact
Vous pouvez aussi adresser une réclamation à la
<a href="https://www.cnil.fr/fr/plaintes">CNIL</a>.</p>
</section>

<section>
<h2>Modifications</h2>
<p>Cette politique peut évoluer avec l'app. La date de mise à jour figure en haut de cette
page.</p>
</section>
</main>
</body>
</html>
""")
