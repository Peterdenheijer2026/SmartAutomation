# SmartAutomation
Automation

## Push + Vercel deploy

**`push.bat`** doet: `git add` → `git commit` → `git push origin main`.

Als Vercel daarna geen nieuwe deploy start, kun je een **Deploy Hook** gebruiken zodat `push.bat` na de push direct een deploy triggert:

1. Ga in Vercel naar je project → **Settings** → **Git** → scroll naar **Deploy Hooks**.
2. Maak een nieuwe hook (bijv. naam: `push.bat`), kopieer de URL.
3. In de map van dit project: maak een bestand **`vercel_deploy_hook.txt`** en plak daarin alleen die URL (één regel).
4. Sla op. Het bestand wordt niet gecommit (staat in `.gitignore`).
5. Bij de volgende keer dat je **`push.bat`** draait, wordt na de push automatisch een Vercel-deploy gestart.
