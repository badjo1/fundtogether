# Herbruikbare Documentatie Setup

Dit document beschrijft hoe je de FundTogether styleguide en security audit herbruikbaar maakt voor andere Rails projecten.

---

## Optie 1: GitHub Template Repository (Aanbevolen ⭐)

### Stap 1: Maak een Template Repository

1. **Maak een nieuw repository:** `rails-project-template`

```bash
# Lokaal
mkdir ~/Projects/rails-project-template
cd ~/Projects/rails-project-template
git init
```

2. **Kopieer de docs:**

```bash
# Vanuit je FundTogether project
cp STYLEGUIDE.md ~/Projects/rails-project-template/
cp SECURITY_AUDIT.md ~/Projects/rails-project-template/
cp .git/hooks/pre-commit ~/Projects/rails-project-template/hooks/pre-commit
```

3. **Maak een README:**

```bash
# In template repo
cat > README.md << 'EOF'
# Rails Project Template

Template voor nieuwe Rails projecten met pre-configured docs en tooling.

## Bevat:
- STYLEGUIDE.md - Code conventions en patterns
- SECURITY_AUDIT.md - Security checklist
- Pre-commit hooks - Automated security checks

## Gebruik:

1. Klik op "Use this template" op GitHub
2. Clone je nieuwe repo
3. Run setup script:
   ```
   ./setup.sh
   ```

## Of handmatig:

```bash
# In je nieuwe Rails project
curl -O https://raw.githubusercontent.com/USERNAME/rails-project-template/main/STYLEGUIDE.md
curl -O https://raw.githubusercontent.com/USERNAME/rails-project-template/main/SECURITY_AUDIT.md

# Setup pre-commit hook
curl -o .git/hooks/pre-commit https://raw.githubusercontent.com/USERNAME/rails-project-template/main/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```
EOF
```

4. **Maak een setup script:**

```bash
cat > setup.sh << 'EOF'
#!/bin/bash
# Setup script voor nieuwe Rails projecten

echo "🚀 Setting up Rails project with docs and tooling..."

# Check if we're in a Rails project
if [ ! -f "Gemfile" ]; then
  echo "❌ Error: Not a Rails project (no Gemfile found)"
  exit 1
fi

# Copy docs
echo "📚 Copying documentation..."
cp STYLEGUIDE.md ../
cp SECURITY_AUDIT.md ../

# Setup pre-commit hook
echo "🔒 Setting up pre-commit hook..."
mkdir -p ../.git/hooks
cp hooks/pre-commit ../.git/hooks/pre-commit
chmod +x ../.git/hooks/pre-commit

# Update project-specific references in docs
echo "✏️  Updating project references..."
PROJECT_NAME=$(basename $(pwd))
sed -i '' "s/FundTogether/$PROJECT_NAME/g" ../STYLEGUIDE.md
sed -i '' "s/FundTogether/$PROJECT_NAME/g" ../SECURITY_AUDIT.md

echo "✅ Setup complete!"
echo ""
echo "Next steps:"
echo "1. Review and customize STYLEGUIDE.md"
echo "2. Review SECURITY_AUDIT.md checklist"
echo "3. Test pre-commit hook: git commit"
EOF

chmod +x setup.sh
```

5. **Push naar GitHub en maak het een template:**

```bash
git add .
git commit -m "Initial template setup"
git remote add origin https://github.com/USERNAME/rails-project-template.git
git push -u origin main
```

Ga naar GitHub → Settings → Template repository ✅

### Gebruik in Nieuwe Projecten:

**Via GitHub UI:**
1. Ga naar je template repo
2. Klik "Use this template"
3. Maak nieuwe repo

**Via CLI:**
```bash
# In je nieuwe Rails project
curl -s https://raw.githubusercontent.com/USERNAME/rails-project-template/main/setup.sh | bash
```

---

## Optie 2: Rails Application Template

Een Rails template die automatisch docs installeert bij `rails new`.

### Maak een template file:

```ruby
# ~/rails_templates/with_docs.rb

# Download docs
get "https://raw.githubusercontent.com/USERNAME/rails-project-template/main/STYLEGUIDE.md", "STYLEGUIDE.md"
get "https://raw.githubusercontent.com/USERNAME/rails-project-template/main/SECURITY_AUDIT.md", "SECURITY_AUDIT.md"

# Setup pre-commit hook
run "mkdir -p .git/hooks"
get "https://raw.githubusercontent.com/USERNAME/rails-project-template/main/hooks/pre-commit", ".git/hooks/pre-commit"
run "chmod +x .git/hooks/pre-commit"

# Update project name in docs
project_name = app_name.titleize
gsub_file "STYLEGUIDE.md", "FundTogether", project_name
gsub_file "SECURITY_AUDIT.md", "FundTogether", project_name

# Add recommended gems
gem_group :development, :test do
  gem "brakeman"
  gem "bundler-audit"
  gem "rubocop-rails"
end

after_bundle do
  run "bundle exec brakeman --init"

  say "✅ Project setup complete with docs and security tooling!", :green
  say "📚 Review STYLEGUIDE.md and SECURITY_AUDIT.md", :blue
end
```

### Gebruik:

```bash
# Bij nieuw project
rails new my_app -m ~/rails_templates/with_docs.rb

# Bij bestaand project
rails app:template LOCATION=~/rails_templates/with_docs.rb
```

---

## Optie 3: Centrale Docs Repository met Submodule

Voor teams die één bron van waarheid willen.

### Setup:

```bash
# Maak centrale docs repo
mkdir ~/Projects/rails-docs
cd ~/Projects/rails-docs
git init

# Voeg docs toe
cp ~/Projects/fundtogether/STYLEGUIDE.md .
cp ~/Projects/fundtogether/SECURITY_AUDIT.md .
git add .
git commit -m "Initial docs"
git remote add origin https://github.com/USERNAME/rails-docs.git
git push -u origin main
```

### Gebruik in projecten:

```bash
# In je Rails project
git submodule add https://github.com/USERNAME/rails-docs.git docs

# Symlink naar root
ln -s docs/STYLEGUIDE.md STYLEGUIDE.md
ln -s docs/SECURITY_AUDIT.md SECURITY_AUDIT.md
```

### Updates ophalen:

```bash
# In alle projecten
git submodule update --remote docs
```

**Voordeel:** Centrale updates propageren naar alle projecten
**Nadeel:** Minder flexibiliteit per project

---

## Optie 4: NPM Package (Voor Rails + JS teams)

Als je team ook Node gebruikt, maak een npm package.

```bash
# Maak package
npm init @yourcompany/rails-docs

# In nieuwe projecten
npm install @yourcompany/rails-docs
cp node_modules/@yourcompany/rails-docs/* .
```

---

## Optie 5: Simple Script (Quick & Easy)

Maak een simpel install script:

```bash
# ~/bin/install-rails-docs.sh
#!/bin/bash

PROJECT_DIR=${1:-.}
cd "$PROJECT_DIR"

echo "📥 Downloading Rails docs..."

# Download latest docs
curl -sO https://raw.githubusercontent.com/USERNAME/rails-project-template/main/STYLEGUIDE.md
curl -sO https://raw.githubusercontent.com/USERNAME/rails-project-template/main/SECURITY_AUDIT.md

# Setup hooks
mkdir -p .git/hooks
curl -so .git/hooks/pre-commit https://raw.githubusercontent.com/USERNAME/rails-project-template/main/hooks/pre-commit
chmod +x .git/hooks/pre-commit

echo "✅ Docs installed!"
```

### Gebruik:

```bash
# In je project
~/bin/install-rails-docs.sh

# Of voor ander project
~/bin/install-rails-docs.sh ~/Projects/other-project
```

---

## Aanbeveling per Situatie

### Voor individuele developer:
→ **Optie 1 (Template Repo)** of **Optie 5 (Script)**

### Voor team met meerdere projecten:
→ **Optie 3 (Submodule)** voor centrale updates
→ **Optie 1 (Template)** voor project flexibility

### Voor nieuwe projecten:
→ **Optie 2 (Rails Template)** - Automatisch bij rails new

### Voor bestaande projecten:
→ **Optie 5 (Script)** - Snel te installeren

---

## Versioning Strategy

Ongeacht welke optie, gebruik semantic versioning:

```
v1.0.0 - Initial release
v1.1.0 - Added icon system docs
v1.2.0 - Updated security checklist
v2.0.0 - Breaking: New Rails 8 conventions
```

Tag releases in je template repo:

```bash
git tag -a v1.0.0 -m "Initial docs release"
git push origin v1.0.0
```

Download specifieke versie:

```bash
curl -O https://raw.githubusercontent.com/USERNAME/rails-project-template/v1.0.0/STYLEGUIDE.md
```

---

## Maintenance

### Updating Docs:

1. Update in template repo
2. Tag nieuwe versie
3. Update in actieve projecten:

```bash
# Script om docs te updaten
#!/bin/bash
# update-docs.sh

VERSION=${1:-main}

curl -sO https://raw.githubusercontent.com/USERNAME/rails-project-template/$VERSION/STYLEGUIDE.md
curl -sO https://raw.githubusercontent.com/USERNAME/rails-project-template/$VERSION/SECURITY_AUDIT.md

echo "✅ Updated to $VERSION"
```

### Changelog bijhouden:

```markdown
# CHANGELOG.md

## [1.1.0] - 2025-12-20
### Added
- Icon system documentation
- Component patterns section

### Changed
- Updated Tailwind color palette
- Improved security checklist

### Fixed
- Typos in testing section
```

---

## Conclusie

**Snelste Start:** Optie 5 (Script)
**Beste voor Teams:** Optie 1 (Template) + Optie 3 (Submodule)
**Meest Geautomatiseerd:** Optie 2 (Rails Template)

Kies op basis van je workflow en team size!
