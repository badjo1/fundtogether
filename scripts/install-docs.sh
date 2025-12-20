#!/bin/bash
# Install Rails Docs Script
#
# Installeert STYLEGUIDE.md en SECURITY_AUDIT.md in een Rails project
#
# Gebruik:
#   ./install-docs.sh [target_directory]
#
# Voorbeelden:
#   ./install-docs.sh                    # Installeer in current directory
#   ./install-docs.sh ~/Projects/my-app  # Installeer in andere directory

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_DIR="${1:-.}"

echo -e "${BLUE}📚 Rails Documentation Installer${NC}"
echo ""

# Validate target is a Rails project
if [ ! -f "$TARGET_DIR/Gemfile" ]; then
  echo -e "${RED}❌ Error: Not a Rails project (no Gemfile found in $TARGET_DIR)${NC}"
  exit 1
fi

cd "$TARGET_DIR"
PROJECT_NAME=$(basename "$(pwd)")

echo -e "${BLUE}Target:${NC} $PROJECT_NAME"
echo -e "${BLUE}Path:${NC} $(pwd)"
echo ""

# Check if docs already exist
if [ -f "STYLEGUIDE.md" ] || [ -f "SECURITY_AUDIT.md" ]; then
  echo -e "${YELLOW}⚠️  Warning: Documentation files already exist${NC}"
  read -p "Overwrite? (y/N) " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
  fi
fi

# Copy docs
echo -e "${GREEN}📄 Copying STYLEGUIDE.md...${NC}"
cp "$SOURCE_DIR/STYLEGUIDE.md" .

echo -e "${GREEN}📄 Copying SECURITY_AUDIT.md...${NC}"
cp "$SOURCE_DIR/SECURITY_AUDIT.md" .

# Update project name in docs
echo -e "${BLUE}✏️  Updating project name references...${NC}"
if [[ "$OSTYPE" == "darwin"* ]]; then
  # macOS
  sed -i '' "s/FundTogether/$PROJECT_NAME/g" STYLEGUIDE.md
  sed -i '' "s/FundTogether/$PROJECT_NAME/g" SECURITY_AUDIT.md
  sed -i '' "s/fundtogether/$(echo $PROJECT_NAME | tr '[:upper:]' '[:lower:]')/g" STYLEGUIDE.md
  sed -i '' "s/fundtogether/$(echo $PROJECT_NAME | tr '[:upper:]' '[:lower:]')/g" SECURITY_AUDIT.md
else
  # Linux
  sed -i "s/FundTogether/$PROJECT_NAME/g" STYLEGUIDE.md
  sed -i "s/FundTogether/$PROJECT_NAME/g" SECURITY_AUDIT.md
  sed -i "s/fundtogether/$(echo $PROJECT_NAME | tr '[:upper:]' '[:lower:]')/g" STYLEGUIDE.md
  sed -i "s/fundtogether/$(echo $PROJECT_NAME | tr '[:upper:]' '[:lower:]')/g" SECURITY_AUDIT.md
fi

# Setup pre-commit hook
if [ -f "$SOURCE_DIR/.git/hooks/pre-commit" ]; then
  echo -e "${GREEN}🔒 Installing pre-commit hook...${NC}"
  mkdir -p .git/hooks
  cp "$SOURCE_DIR/.git/hooks/pre-commit" .git/hooks/pre-commit
  chmod +x .git/hooks/pre-commit
else
  echo -e "${YELLOW}⚠️  Pre-commit hook not found in source, skipping...${NC}"
fi

# Copy icon system if it doesn't exist
if [ -d "$SOURCE_DIR/app/views/icons" ] && [ ! -d "app/views/icons" ]; then
  read -p "Also install icon system? (y/N) " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${GREEN}🎨 Installing icon system...${NC}"
    mkdir -p app/views/icons
    cp -r "$SOURCE_DIR/app/views/icons/"* app/views/icons/

    mkdir -p app/helpers
    if [ ! -f "app/helpers/icon_helper.rb" ]; then
      cp "$SOURCE_DIR/app/helpers/icon_helper.rb" app/helpers/
    fi

    echo -e "${GREEN}✓ Icon system installed${NC}"
  fi
fi

echo ""
echo -e "${GREEN}✅ Installation complete!${NC}"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo "1. Review and customize STYLEGUIDE.md"
echo "2. Check SECURITY_AUDIT.md checklist"
echo "3. Test pre-commit hook: git add . && git commit"
echo ""
echo -e "${BLUE}Documentation:${NC}"
echo "- STYLEGUIDE.md - Code conventions and patterns"
echo "- SECURITY_AUDIT.md - Security checklist"
if [ -d "app/views/icons" ]; then
  echo "- app/views/icons/README.md - Icon system docs"
fi
echo ""
