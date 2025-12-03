#!/usr/bin/env bash
# Enterprise Vibe Code - Test Harness
# Single entry point for all TDD tests
# Usage: ./scripts/test.sh [test_name]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
HUGO_VERSION="0.152.2"
SITE_URL="https://enterprisevibecode.com/"
NEW_DOMAIN="enterprisevibecode.com"
NEW_SITE_URL="https://enterprisevibecode.com/"
OLD_SUBPATH_URL="https://mikelady.com/enterprise_vibe_code/"
MAIN_SITE_URL="https://mikelady.com/"

# GitHub Pages IP addresses for custom domain verification
GITHUB_PAGES_IPS=("185.199.108.153" "185.199.109.153" "185.199.110.153" "185.199.111.153")

# Use ./bin/hugo if exists, otherwise fall back to system hugo (for CI)
if [[ -x "${PROJECT_ROOT}/bin/hugo" ]]; then
    HUGO_BIN="${PROJECT_ROOT}/bin/hugo"
elif command -v hugo &>/dev/null; then
    HUGO_BIN="hugo"
else
    HUGO_BIN=""
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

PASSED=0
FAILED=0

log_pass() {
    echo -e "  ${GREEN}✅ PASS${NC}: $1"
    PASSED=$((PASSED + 1))
}

log_fail() {
    echo -e "  ${RED}❌ FAIL${NC}: $1"
    FAILED=$((FAILED + 1))
}

log_skip() {
    echo -e "  ${YELLOW}⏭️  SKIP${NC}: $1"
}

# =============================================================================
# TEST: Hugo Build (abn.1 RED → abn.2 GREEN)
# Expects: hugo binary exists and site builds successfully
# =============================================================================
test_hugo_build() {
    echo "TEST: Hugo build succeeds"

    # Check if hugo binary exists
    if [[ -z "$HUGO_BIN" ]]; then
        log_fail "Hugo binary not found (run ./scripts/setup.sh or install hugo)"
        return 1
    fi

    # Run hugo build
    cd "$PROJECT_ROOT"
    if "$HUGO_BIN" --minify --destination public 2>/dev/null; then
        log_pass "Hugo build completed successfully"
        return 0
    else
        log_fail "Hugo build failed"
        return 1
    fi
}

# =============================================================================
# TEST: Content Rendered (abn.3 RED → abn.4 GREEN)
# Expects: public/index.html contains site title, not 404 page
# =============================================================================
test_content_rendered() {
    echo "TEST: Content rendered correctly"

    local INDEX_FILE="$PROJECT_ROOT/public/index.html"

    # Check if index.html exists
    if [[ ! -f "$INDEX_FILE" ]]; then
        log_fail "public/index.html not found (run hugo build first)"
        return 1
    fi

    # Check for site title
    if ! grep -q 'Enterprise Vibe Code' "$INDEX_FILE"; then
        log_fail "Site title 'Enterprise Vibe Code' not found in index.html"
        return 1
    fi

    # Check it's not a 404 page
    if grep -q 'Page Not Found' "$INDEX_FILE"; then
        log_fail "Index page is showing 404 content"
        return 1
    fi

    # Check it's not Hugo's default empty page
    if grep -q 'There is nothing here' "$INDEX_FILE"; then
        log_fail "Index page is showing Hugo's empty page message"
        return 1
    fi

    log_pass "Content rendered with correct title"
    return 0
}

# =============================================================================
# TEST: Workflow Valid (abn.5 RED → abn.6 GREEN)
# Expects: .github/workflows/hugo.yml exists with required actions
# =============================================================================
test_workflow_valid() {
    echo "TEST: GitHub Actions workflow is valid"

    local WORKFLOW_FILE="$PROJECT_ROOT/.github/workflows/hugo.yml"

    # Check if workflow file exists
    if [[ ! -f "$WORKFLOW_FILE" ]]; then
        log_fail "Workflow file not found at .github/workflows/hugo.yml"
        return 1
    fi

    # Check for required actions using grep (yq would be better but may not be installed)
    local REQUIRED_PATTERNS=(
        "actions/checkout"
        "actions/configure-pages"
        "actions/upload-pages-artifact"
        "actions/deploy-pages"
        "hugo"
    )

    for pattern in "${REQUIRED_PATTERNS[@]}"; do
        if ! grep -q "$pattern" "$WORKFLOW_FILE"; then
            log_fail "Required pattern '$pattern' not found in workflow"
            return 1
        fi
    done

    # Check for proper permissions
    if ! grep -q "pages: write" "$WORKFLOW_FILE"; then
        log_fail "Missing 'pages: write' permission"
        return 1
    fi

    log_pass "Workflow contains all required actions"
    return 0
}

# =============================================================================
# TEST: Hugo baseURL (b44.o2r RED → b44.vs3 GREEN)
# Expects: hugo.toml baseURL is set to new domain
# =============================================================================
test_base_url() {
    echo "TEST: hugo.toml baseURL is set to $NEW_SITE_URL"

    local HUGO_CONFIG="$PROJECT_ROOT/hugo.toml"

    if [[ ! -f "$HUGO_CONFIG" ]]; then
        log_fail "hugo.toml not found"
        return 1
    fi

    local CURRENT_BASE_URL
    CURRENT_BASE_URL=$(grep -E '^baseURL' "$HUGO_CONFIG" | head -1 | cut -d'"' -f2)

    if [[ "$CURRENT_BASE_URL" != "$NEW_SITE_URL" ]]; then
        log_fail "baseURL is '$CURRENT_BASE_URL', expected '$NEW_SITE_URL'"
        return 1
    fi

    log_pass "hugo.toml baseURL correctly set"
    return 0
}

# =============================================================================
# TEST: CNAME File (b44.5iw RED → b44.t8r GREEN)
# Expects: static/CNAME exists with custom domain (Hugo copies to public/)
# =============================================================================
test_cname_file() {
    echo "TEST: CNAME file exists with custom domain"

    local CNAME_FILE="$PROJECT_ROOT/static/CNAME"

    # Check if CNAME file exists in static/ (Hugo's static files directory)
    if [[ ! -f "$CNAME_FILE" ]]; then
        log_fail "CNAME file not found at static/CNAME"
        return 1
    fi

    # Check if CNAME contains the correct domain
    local CNAME_CONTENT
    CNAME_CONTENT=$(cat "$CNAME_FILE" | tr -d '[:space:]')

    if [[ "$CNAME_CONTENT" != "$NEW_DOMAIN" ]]; then
        log_fail "CNAME file contains '$CNAME_CONTENT', expected '$NEW_DOMAIN'"
        return 1
    fi

    # After build, verify public/CNAME exists
    if [[ -d "$PROJECT_ROOT/public" ]] && [[ ! -f "$PROJECT_ROOT/public/CNAME" ]]; then
        log_fail "public/CNAME not found after build (Hugo didn't copy static/CNAME)"
        return 1
    fi

    log_pass "CNAME file correctly configured"
    return 0
}

# =============================================================================
# TEST: DNS Configuration (b44.8xv RED → b44.i8e GREEN)
# Expects: enterprisevibecode.com A records point to GitHub Pages IPs
# =============================================================================
test_dns_config() {
    echo "TEST: DNS A records for $NEW_DOMAIN point to GitHub Pages"

    if ! command -v dig &>/dev/null; then
        log_fail "dig command not found (install dnsutils)"
        return 1
    fi

    local DNS_IPS
    DNS_IPS=$(dig +short "$NEW_DOMAIN" A 2>/dev/null | sort)

    if [[ -z "$DNS_IPS" ]]; then
        log_fail "No A records found for $NEW_DOMAIN"
        return 1
    fi

    # Check if at least one GitHub Pages IP is present
    local FOUND_GITHUB_IP=false
    for ip in "${GITHUB_PAGES_IPS[@]}"; do
        if echo "$DNS_IPS" | grep -q "$ip"; then
            FOUND_GITHUB_IP=true
            break
        fi
    done

    if [[ "$FOUND_GITHUB_IP" == "false" ]]; then
        log_fail "DNS A records do not point to GitHub Pages IPs"
        echo "    Expected one of: ${GITHUB_PAGES_IPS[*]}"
        echo "    Got: $(echo "$DNS_IPS" | tr '\n' ' ')"
        return 1
    fi

    log_pass "DNS A records correctly point to GitHub Pages"
    return 0
}

# =============================================================================
# TEST: Live Site (abn.7 RED → abn.8 GREEN)
# Expects: Site returns 200 and contains expected content
# =============================================================================
test_live_site() {
    echo "TEST: Live site accessible with correct content"

    # Exponential backoff: 5, 10, 20, 40, 60 seconds
    local DELAYS=(5 10 20 40 60)

    for delay in "${DELAYS[@]}"; do
        local HTTP_CODE
        local BODY

        HTTP_CODE=$(curl -sL -o /dev/null -w "%{http_code}" "$SITE_URL" 2>/dev/null || echo "000")

        if [[ "$HTTP_CODE" == "200" ]]; then
            BODY=$(curl -sL "$SITE_URL" 2>/dev/null)

            if echo "$BODY" | grep -q 'Enterprise Vibe Code'; then
                log_pass "Live site returns 200 with correct content"
                return 0
            else
                echo "    HTTP 200 but content not found, waiting ${delay}s..."
            fi
        else
            echo "    HTTP $HTTP_CODE, waiting ${delay}s for deployment..."
        fi

        sleep "$delay"
    done

    log_fail "Live site test failed after retries (HTTP: $HTTP_CODE)"
    return 1
}

# =============================================================================
# TEST: GitHub Pages Custom Domain (b44.mta RED → b44.lmc GREEN)
# Expects: GitHub Pages has custom domain configured
# =============================================================================
test_gh_pages_domain() {
    echo "TEST: GitHub Pages custom domain is configured"

    if ! command -v gh &>/dev/null; then
        log_fail "gh CLI not found"
        return 1
    fi

    local PAGES_INFO
    PAGES_INFO=$(gh api repos/michaellady/enterprise_vibe_code/pages 2>/dev/null || echo "{}")

    local CNAME
    CNAME=$(echo "$PAGES_INFO" | grep -o '"cname":"[^"]*"' | sed 's/"cname":"//' | sed 's/"//' || echo "null")

    if [[ "$CNAME" != "$NEW_DOMAIN" ]]; then
        log_fail "GitHub Pages cname is '$CNAME', expected '$NEW_DOMAIN'"
        return 1
    fi

    log_pass "GitHub Pages custom domain correctly configured"
    return 0
}

# =============================================================================
# TEST: New Domain Live Site (b44.vs0 RED → b44.nnm GREEN)
# Expects: New domain returns 200 with correct content
# =============================================================================
test_new_domain_live() {
    echo "TEST: New domain $NEW_SITE_URL is live with correct content"

    local HTTP_CODE
    HTTP_CODE=$(curl -sL -o /dev/null -w "%{http_code}" "$NEW_SITE_URL" 2>/dev/null || echo "000")

    if [[ "$HTTP_CODE" != "200" ]]; then
        log_fail "New domain returns HTTP $HTTP_CODE, expected 200"
        return 1
    fi

    local BODY
    BODY=$(curl -sL "$NEW_SITE_URL" 2>/dev/null)

    if ! echo "$BODY" | grep -q 'Enterprise Vibe Code'; then
        log_fail "New domain doesn't contain expected content"
        return 1
    fi

    log_pass "New domain is live with correct content"
    return 0
}

# =============================================================================
# TEST: Main Site Preservation (b44.buz)
# Expects: mikelady.com still works with its tagline
# =============================================================================
test_main_site_preserved() {
    echo "TEST: Main site $MAIN_SITE_URL is preserved"

    local HTTP_CODE
    HTTP_CODE=$(curl -sL -o /dev/null -w "%{http_code}" "$MAIN_SITE_URL" 2>/dev/null || echo "000")

    if [[ "$HTTP_CODE" != "200" ]]; then
        log_fail "Main site returns HTTP $HTTP_CODE, expected 200"
        return 1
    fi

    local BODY
    BODY=$(curl -sL "$MAIN_SITE_URL" 2>/dev/null)

    local EXPECTED_TAGLINE="Grappling with humans and code"
    if ! echo "$BODY" | grep -q "$EXPECTED_TAGLINE"; then
        log_fail "Main site doesn't contain expected tagline"
        return 1
    fi

    log_pass "Main site preserved with correct content"
    return 0
}

# =============================================================================
# TEST: Old URL Redirect (b44.sgr)
# Expects: Old subpath URL redirects to new domain
# =============================================================================
test_old_url_redirect() {
    echo "TEST: Old URL $OLD_SUBPATH_URL redirects to new domain"

    # Get redirect location without following redirects
    local REDIRECT_INFO
    REDIRECT_INFO=$(curl -sI "$OLD_SUBPATH_URL" 2>/dev/null | head -20)

    local HTTP_CODE
    HTTP_CODE=$(echo "$REDIRECT_INFO" | grep -i "^HTTP" | tail -1 | awk '{print $2}')

    # Should be 301 redirect
    if [[ "$HTTP_CODE" != "301" ]]; then
        log_fail "Old URL returns HTTP $HTTP_CODE, expected 301 redirect"
        return 1
    fi

    local LOCATION
    LOCATION=$(echo "$REDIRECT_INFO" | grep -i "^location:" | sed 's/[Ll]ocation:\s*//' | tr -d '\r\n')

    if [[ "$LOCATION" != *"$NEW_DOMAIN"* ]]; then
        log_fail "Old URL redirects to '$LOCATION', expected redirect to $NEW_DOMAIN"
        return 1
    fi

    log_pass "Old URL correctly redirects to new domain"
    return 0
}

# =============================================================================
# MAIN: Run all tests or specific test
# =============================================================================
run_all_tests() {
    echo "========================================"
    echo "Enterprise Vibe Code - Test Suite"
    echo "========================================"
    echo ""

    # Run tests in order, continue even if some fail
    test_hugo_build || true
    echo ""
    test_content_rendered || true
    echo ""
    test_workflow_valid || true
    echo ""

    # Live site test is optional (only run if --live flag passed)
    if [[ "${1:-}" == "--live" ]]; then
        test_live_site || true
        echo ""
    else
        log_skip "Live site test (pass --live to run)"
        echo ""
    fi

    echo "========================================"
    echo "Results: ${GREEN}${PASSED} passed${NC}, ${RED}${FAILED} failed${NC}"
    echo "========================================"

    # Exit with failure if any tests failed
    [[ $FAILED -eq 0 ]]
}

# Run specific test or all tests
case "${1:-all}" in
    build)
        test_hugo_build
        ;;
    content)
        test_content_rendered
        ;;
    workflow)
        test_workflow_valid
        ;;
    live)
        test_live_site
        ;;
    dns)
        test_dns_config
        ;;
    cname)
        test_cname_file
        ;;
    baseurl)
        test_base_url
        ;;
    ghpages)
        test_gh_pages_domain
        ;;
    newdomain)
        test_new_domain_live
        ;;
    mainsite)
        test_main_site_preserved
        ;;
    redirect)
        test_old_url_redirect
        ;;
    migration)
        # Run all migration-related tests
        echo "========================================"
        echo "Custom Domain Migration Tests"
        echo "========================================"
        echo ""
        test_dns_config || true
        echo ""
        test_cname_file || true
        echo ""
        test_base_url || true
        echo ""
        test_gh_pages_domain || true
        echo ""
        test_new_domain_live || true
        echo ""
        test_main_site_preserved || true
        echo ""
        test_old_url_redirect || true
        echo ""
        echo "========================================"
        echo "Migration Results: ${GREEN}${PASSED} passed${NC}, ${RED}${FAILED} failed${NC}"
        echo "========================================"
        [[ $FAILED -eq 0 ]]
        ;;
    all|--live)
        run_all_tests "$@"
        ;;
    *)
        echo "Usage: $0 [build|content|workflow|dns|live|all] [--live] [--migration]"
        exit 1
        ;;
esac
