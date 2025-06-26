#!/bin/bash
# Validation script to check for hardcoded paths and other issues

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ISSUES_FOUND=0

echo -e "${BLUE}=== Dictation Service Bundle Validator ===${NC}"
echo

# Function to report issues
report_issue() {
    echo -e "${RED}[ISSUE]${NC} $1"
    ((ISSUES_FOUND++))
}

# Function to report success
report_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

# 1. Check for hardcoded paths
echo -e "${YELLOW}Checking for hardcoded paths...${NC}"
HARDCODED_PATHS=$(grep -r "/home/stefanos" --exclude-dir=.git --exclude="*.md" --exclude="validate.sh" 2>/dev/null || true)

if [ -n "$HARDCODED_PATHS" ]; then
    report_issue "Found hardcoded paths:"
    echo "$HARDCODED_PATHS" | while IFS= read -r line; do
        echo "  $line"
    done
else
    report_success "No hardcoded paths found"
fi

# 2. Check for specific device names
echo -e "${YELLOW}Checking for hardcoded device names...${NC}"
DEVICE_NAMES=$(grep -r "SteelSeries_Arctis" --exclude-dir=.git --exclude="*.md" --exclude="validate.sh" 2>/dev/null || true)

if [ -n "$DEVICE_NAMES" ]; then
    report_issue "Found hardcoded device names:"
    echo "$DEVICE_NAMES" | while IFS= read -r line; do
        echo "  $line"
    done
else
    report_success "No hardcoded device names found"
fi

# 3. Check for absolute paths that should be relative
echo -e "${YELLOW}Checking for problematic absolute paths...${NC}"
ABSOLUTE_PATHS=$(grep -r "/.local/share\|/.config" --exclude-dir=.git --exclude="*.md" --exclude="validate.sh" | grep -v '~\|$HOME\|%h' || true)

if [ -n "$ABSOLUTE_PATHS" ]; then
    report_issue "Found absolute paths that might need HOME prefix:"
    echo "$ABSOLUTE_PATHS" | while IFS= read -r line; do
        echo "  $line"
    done
else
    report_success "Path references look good"
fi

# 4. Check for personal information
echo -e "${YELLOW}Checking for personal information...${NC}"
PERSONAL_INFO=$(grep -ri "stefanos\|anastasiou" --exclude-dir=.git --exclude="LICENSE" --exclude="*.md" --exclude="validate.sh" 2>/dev/null || true)

if [ -n "$PERSONAL_INFO" ]; then
    report_issue "Found potential personal information:"
    echo "$PERSONAL_INFO" | while IFS= read -r line; do
        echo "  $line"
    done
else
    report_success "No personal information in code"
fi

# 5. Check file permissions
echo -e "${YELLOW}Checking file permissions...${NC}"
NON_EXEC_SCRIPTS=$(find . -name "*.sh" -o -name "*.py" | while read f; do
    if [[ ! -x "$f" ]]; then
        echo "$f"
    fi
done)

if [ -n "$NON_EXEC_SCRIPTS" ]; then
    report_issue "Scripts without execute permission:"
    echo "$NON_EXEC_SCRIPTS"
else
    report_success "All scripts have proper permissions"
fi

# 6. Check for TODO/FIXME comments
echo -e "${YELLOW}Checking for TODO/FIXME comments...${NC}"
TODO_COMMENTS=$(grep -r "TODO\|FIXME\|XXX\|HACK" --exclude-dir=.git --exclude="validate.sh" 2>/dev/null || true)

if [ -n "$TODO_COMMENTS" ]; then
    echo -e "${YELLOW}[WARN]${NC} Found TODO/FIXME comments:"
    echo "$TODO_COMMENTS" | while IFS= read -r line; do
        echo "  $line"
    done
fi

# 7. Check Python syntax
echo -e "${YELLOW}Checking Python syntax...${NC}"
PYTHON_ERRORS=0
find . -name "*.py" -print0 | while IFS= read -r -d '' file; do
    if ! python3 -m py_compile "$file" 2>/dev/null; then
        report_issue "Python syntax error in: $file"
        ((PYTHON_ERRORS++))
    fi
done

if [ $PYTHON_ERRORS -eq 0 ]; then
    report_success "All Python files have valid syntax"
fi

# 8. Check shell script syntax
echo -e "${YELLOW}Checking shell script syntax...${NC}"
SHELL_ERRORS=0
find . -name "*.sh" -print0 | while IFS= read -r -d '' file; do
    if ! bash -n "$file" 2>/dev/null; then
        report_issue "Shell syntax error in: $file"
        ((SHELL_ERRORS++))
    fi
done

if [ $SHELL_ERRORS -eq 0 ]; then
    report_success "All shell scripts have valid syntax"
fi

# 9. Check for sensitive files
echo -e "${YELLOW}Checking for sensitive files...${NC}"
SENSITIVE_FILES=$(find . -name "*.log" -o -name "*.key" -o -name "*.pem" -o -name "config.json" | grep -v ".default" || true)

if [ -n "$SENSITIVE_FILES" ]; then
    report_issue "Found potentially sensitive files:"
    echo "$SENSITIVE_FILES"
else
    report_success "No sensitive files found"
fi

# 10. Verify required files exist
echo -e "${YELLOW}Checking required files...${NC}"
REQUIRED_FILES=(
    "install.sh"
    "README.md"
    "LICENSE"
    ".gitignore"
    "src/dictation-service.py"
    "src/mic-monitor.py"
    "bin/dictation"
    "bin/mic-monitor"
    "bin/arcrecord"
)

MISSING_FILES=0
for file in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$file" ]; then
        report_issue "Missing required file: $file"
        ((MISSING_FILES++))
    fi
done

if [ $MISSING_FILES -eq 0 ]; then
    report_success "All required files present"
fi

# Summary
echo
echo -e "${BLUE}=== Validation Summary ===${NC}"
if [ $ISSUES_FOUND -eq 0 ]; then
    echo -e "${GREEN}✓ No issues found! Bundle is ready for release.${NC}"
    exit 0
else
    echo -e "${RED}✗ Found $ISSUES_FOUND issues that should be fixed.${NC}"
    exit 1
fi