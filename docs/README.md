# FundTogether Documentation

Deze directory bevat alle project documentatie en handleidingen voor hergebruik in andere projecten.

## Beschikbare Documenten

### Project Documentatie:
- [`STYLEGUIDE.md`](STYLEGUIDE.md) - Code conventions en patterns (939 regels)
- [`SECURITY_AUDIT.md`](SECURITY_AUDIT.md) - Security checklist (15 categorieën)
- [`../app/views/icons/README.md`](../app/views/icons/README.md) - Icon system documentatie

### Hergebruik Handleiding:
- [`REUSABLE_DOCS_SETUP.md`](REUSABLE_DOCS_SETUP.md) - Volledige guide voor hergebruik (5 strategieën)

---

## Quick Start: Gebruik in Ander Project

### Methode 1: Handmatig Kopiëren (Aanbevolen)

```bash
# Vanuit FundTogether directory
cd /Users/bloemers/Projects/fundtogether

# Kopieer docs naar je nieuwe project
cp docs/STYLEGUIDE.md ~/Projects/my-new-rails-project/
cp docs/SECURITY_AUDIT.md ~/Projects/my-new-rails-project/

# Kopieer pre-commit hook
cp .git/hooks/pre-commit ~/Projects/my-new-rails-project/.git/hooks/
chmod +x ~/Projects/my-new-rails-project/.git/hooks/pre-commit

# (Optioneel) Kopieer icon system
cp -r app/views/icons ~/Projects/my-new-rails-project/app/views/
cp app/helpers/icon_helper.rb ~/Projects/my-new-rails-project/app/helpers/
```

### Methode 2: Maak docs/ directory in nieuwe project

```bash
# In je nieuwe project
cd ~/Projects/my-new-rails-project
mkdir -p docs

# Kopieer hele docs folder
cp -r ~/Projects/fundtogether/docs/* docs/

# Kopieer pre-commit hook
mkdir -p .git/hooks
cp ~/Projects/fundtogether/.git/hooks/pre-commit .git/hooks/
chmod +x .git/hooks/pre-commit
```

### Methode 3: Via GitHub Template

Zie [`REUSABLE_DOCS_SETUP.md`](REUSABLE_DOCS_SETUP.md) voor complete instructies over het opzetten van een herbruikbare template repository.

---

## Wat Wordt Geïnstalleerd?

### 📚 Documentatie
- **STYLEGUIDE.md** (939 regels)
  - Code formatting
  - Naming conventions
  - Component patterns
  - CSS/Tailwind standards
  - Rails conventions
  - Testing guidelines

- **SECURITY_AUDIT.md**
  - Security checklist (15 categorieën)
  - Pre-commit hook docs
  - Common vulnerabilities
  - Best practices

### 🔒 Tooling
- **Pre-commit hook**
  - Bundle audit (dependencies)
  - Brakeman (security scanner)
  - RuboCop security cops
  - Custom anti-pattern checks
  - Rails test suite

### 🎨 Icon System (Optioneel)
- 25 herbruikbare SVG icons
- Icon helper method
- Complete documentation

---

## Aanpassingen per Project

Na kopiëren naar een nieuw project:

1. **Project naam** - Find & Replace "FundTogether" → "JouwProjectNaam"
   ```bash
   # macOS
   sed -i '' 's/FundTogether/JouwProjectNaam/g' docs/STYLEGUIDE.md
   sed -i '' 's/FundTogether/JouwProjectNaam/g' docs/SECURITY_AUDIT.md

   # Linux
   sed -i 's/FundTogether/JouwProjectNaam/g' docs/STYLEGUIDE.md
   sed -i 's/FundTogether/JouwProjectNaam/g' docs/SECURITY_AUDIT.md
   ```

2. **Tech stack** - Update in STYLEGUIDE.md indien afwijkend van Rails 8 + Hotwire + Tailwind
3. **Security checklist** - Vink af wat al geïmplementeerd is in SECURITY_AUDIT.md
4. **Component patterns** - Voeg project-specifieke componenten toe aan STYLEGUIDE.md
5. **Versioning** - Start met v1.0.0 voor je project

---

## Updates Synchroniseren

### Optie A: Handmatig kopiëren
```bash
# Wanneer FundTogether docs zijn geüpdatet
cd ~/Projects/fundtogether
cp docs/STYLEGUIDE.md ~/Projects/my-project/docs/
cp docs/SECURITY_AUDIT.md ~/Projects/my-project/docs/

# Update project naam weer
cd ~/Projects/my-project
sed -i '' 's/FundTogether/MyProject/g' docs/STYLEGUIDE.md
sed -i '' 's/FundTogether/MyProject/g' docs/SECURITY_AUDIT.md
```

### Optie B: Git Submodule (voor teams)
Zie [`REUSABLE_DOCS_SETUP.md`](REUSABLE_DOCS_SETUP.md#optie-3-centrale-docs-repository-met-submodule)

### Optie C: GitHub Template Repo
Zie [`REUSABLE_DOCS_SETUP.md`](REUSABLE_DOCS_SETUP.md#optie-1-github-template-repository-aanbevolen) voor setup

---

## Versioning

Gebruik semantic versioning voor doc updates:

- `v1.0.0` - Initial release
- `v1.1.0` - Added icon system
- `v1.2.0` - Updated security checklist
- `v2.0.0` - Rails 8 conventions

Tag releases in template repo voor stabiele versies.

---

## Support

Vragen of verbeteringen?
1. Open een issue in dit project
2. Zie [`REUSABLE_DOCS_SETUP.md`](REUSABLE_DOCS_SETUP.md) voor details
3. Check bestaande projecten met deze docs

---

---

## File Structuur

```
fundtogether/
├── docs/
│   ├── README.md                  # Dit bestand
│   ├── STYLEGUIDE.md              # Code conventions (939 regels)
│   ├── SECURITY_AUDIT.md          # Security checklist (15 categorieën)
│   └── REUSABLE_DOCS_SETUP.md     # Hergebruik handleiding
├── app/
│   ├── views/icons/               # Icon system (25 icons)
│   │   ├── README.md              # Icon documentatie
│   │   ├── _check.html.erb
│   │   └── ...
│   └── helpers/
│       └── icon_helper.rb         # Icon helper method
└── .git/hooks/
    └── pre-commit                 # Security pre-commit hook
```

---

## Tips voor Hergebruik

### Voor Nieuwe Rails Projecten:
1. Kopieer `docs/` directory helemaal
2. Kopieer pre-commit hook
3. Pas project naam aan (zie boven)
4. (Optioneel) Kopieer icon system

### Voor Bestaande Rails Projecten:
1. Start met alleen STYLEGUIDE.md
2. Implementeer conventions gradueel
3. Voeg SECURITY_AUDIT.md toe voor review
4. Installeer pre-commit hook als team akkoord

### Voor Teams:
1. Maak GitHub template repository (zie REUSABLE_DOCS_SETUP.md)
2. Gebruik als startpunt voor nieuwe projecten
3. Update centrale template bij verbeteringen
4. Sync updates naar projecten indien gewenst

---

## Changelog

### v1.0.0 (2025-12-20)
- Initial styleguide (939 lines)
- Security audit checklist (15 categorieën)
- Pre-commit hooks met 5 checks
- Icon system docs (25 icons)
- Reusable docs guide (5 strategieën)
- Docs verplaatst naar docs/ directory
