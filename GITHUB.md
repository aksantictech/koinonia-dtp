# Relier KOINONIA à GitHub + Vercel (déploiement automatique)

## 1. Pousser sur GitHub
Crée un dépôt vide sur github.com (sans README), puis :

    git init
    git add .
    git commit -m "KOINONIA - version initiale"
    git branch -M main
    git remote add origin https://github.com/TON-COMPTE/koinonia.git
    git push -u origin main

Ensuite, à chaque modif :

    git add .
    git commit -m "ma modification"
    git push

## 2. Relier à Vercel
- Projet Vercel existant : Settings → Git → Connect Git Repository.
- Nouveau projet : vercel.com → Add New → Project → Import le dépôt.
  Framework = Other · pas de Build Command · Output Directory = "." (racine)

Chaque push sur `main` = redéploiement automatique. (Un push sur une autre
branche crée un déploiement de "preview" pour tester avant de fusionner.)

## Sécurité
- config.js = OK à committer (clé Supabase *anon* publique + clé VAPID *publique*).
- Clé privée VAPID = JAMAIS dans le dépôt (elle reste dans `supabase secrets`).
