# FundTogether Documentation

Deze directory bevat handleidingen voor hergebruik van FundTogether's documentatie en tooling in andere projecten.

## Beschikbare Documenten

### Voor Dit Project:
- [`../STYLEGUIDE.md`](../STYLEGUIDE.md) - Code conventions en patterns
- [`../SECURITY_AUDIT.md`](../SECURITY_AUDIT.md) - Security checklist
- [`../app/views/icons/README.md`](../app/views/icons/README.md) - Icon system

### Voor Hergebruik:
- [`REUSABLE_DOCS_SETUP.md`](REUSABLE_DOCS_SETUP.md) - Volledige guide voor hergebruik
- [`../scripts/install-docs.sh`](../scripts/install-docs.sh) - Installatie script

---

## Quick Start: Installeer in Ander Project

### Methode 1: Via Script (Aanbevolen)

```bash
# Vanuit dit project
cd /path/to/fundtogether

# Installeer in ander Rails project
./scripts/install-docs.sh ~/Projects/my-other-rails-app
```

### Methode 2: Handmatig Kopiëren

```bash
# In je nieuwe project
cd ~/Projects/my-new-rails-project

# Kopieer docs
cp ~/Projects/fundtogether/STYLEGUIDE.md .
cp ~/Projects/fundtogether/SECURITY_AUDIT.md .

# Kopieer pre-commit hook
cp ~/Projects/fundtogether/.git/hooks/pre-commit .git/hooks/
chmod +x .git/hooks/pre-commit

# (Optioneel) Kopieer icon system
cp -r ~/Projects/fundtogether/app/views/icons app/views/
cp ~/Projects/fundtogether/app/helpers/icon_helper.rb app/helpers/
```

### Methode 3: Via GitHub Template

Zie [`REUSABLE_DOCS_SETUP.md`](REUSABLE_DOCS_SETUP.md) voor complete instructies.

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

Na installatie, pas aan:

1. **Project naam** - Automatisch door install script
2. **Tech stack** - Update in STYLEGUIDE.md als afwijkend
3. **Security checklist** - Vink af wat relevant is
4. **Component patterns** - Voeg project-specifieke toe

---

## Updates Synchroniseren

### Optie A: Handmatig
```bash
# Pull laatste versie van template
./scripts/install-docs.sh ~/Projects/my-project
```

### Optie B: Git Submodule
Zie [`REUSABLE_DOCS_SETUP.md`](REUSABLE_DOCS_SETUP.md#optie-3-centrale-docs-repository-met-submodule)

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

## Changelog

### v1.0.0 (2025-12-20)
- Initial styleguide (939 lines)
- Security audit checklist
- Pre-commit hooks
- Icon system docs
- Install script
- Reusable docs guide
