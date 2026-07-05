// ============================================================
// tenant.js — Schul-spezifische Konfiguration (KRS Schüler-Hub)
// Wird als ERSTES Script geladen. Muster: krs-projektwahl-2026.
// ============================================================
(function () {
  'use strict';
  window.TENANT = window.TENANT || {
    schule: {
      name_lang: 'Kurpfalz-Realschule Schriesheim',
      name_kurz: 'KRS',
      ort: 'Schriesheim'
    },
    branding: {
      logo_url: 'krs-logo.jpg',
      primaer: '#4A6A83',
      akzent: '#E87722',
      warm: '#F5B335'
    },
    // Externe App-Kacheln. url leer = Kachel zeigt "bald verfügbar".
    // passCode: true → ?code=<Anmeldecode> wird an die App durchgereicht.
    module: [
      { id: 'projektwoche', name: 'Projektwoche', icon: '🎨',
        beschreibung: 'Dein Projekt, deine Wahl, Tauschwünsche',
        url: 'https://kurpfalz-realschule.github.io/krs-projektwahl-2026/schueler-frontend-v3.html',
        passCode: true },
      { id: 'makerspace', name: 'Makerspace', icon: '🛠️',
        beschreibung: 'Werkstatt-Zeiten buchen', url: '', passCode: true },
      { id: 'smv', name: 'SMV', icon: '🏛️',
        beschreibung: 'Ideenbox, Aktionen, Klassensprecher', url: '', passCode: false },
      { id: 'iserv', name: 'IServ', icon: '📧',
        beschreibung: 'Schul-Mail, Dateien, Stundenplan',
        url: 'https://realschule-schriesheim.de/iserv/', passCode: false },
      { id: 'office', name: 'Office 365', icon: '📄',
        beschreibung: 'Word, Excel, PowerPoint online',
        // TODO Norbert: prüfen — Einstieg über IServ-Office oder microsoftonline?
        url: 'https://www.office.com/', passCode: false },
      { id: 'homepage', name: 'Schul-Homepage', icon: '🏫',
        beschreibung: 'realschule-schriesheim.de',
        url: 'https://realschule-schriesheim.de/', passCode: false }
    ],
    rechtliches: {
      datenschutz_url: 'https://realschule-schriesheim.de/datenschutz/',
      impressum_url: 'https://realschule-schriesheim.de/impressum/'
    },
    // Schüler dürfen in Teams schreiben? Bis das Lehrer-Panel (Moderation,
    // Phase 2) live ist, kann die Schule das hier auf false stellen —
    // Teams sind dann nur lesbar (Review-Finding 🟡8).
    teams_posting: true,
    // Fallback-Links, solange hub_links noch nicht in der DB gepflegt ist
    fallback_links: [
      { titel: 'Schul-Homepage', url: 'https://realschule-schriesheim.de/', kategorie: 'Allgemein', beschreibung: '' },
      { titel: 'IServ', url: 'https://realschule-schriesheim.de/iserv/', kategorie: 'Allgemein', beschreibung: 'Schul-Mail & Dateien' }
    ]
  };
})();
