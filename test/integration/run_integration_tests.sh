#!/usr/bin/env bash
# Integration Test Runner for ReqFly
# 
# This script runs integration tests sequentially against the live Fly.io API.
# Each test creates real resources and cleans them up afterward.
#
# Usage:
#   export FLY_API_TOKEN="your_token_here"
#   ./run_integration_tests.sh

set -e  # Exit on any error

# Source .envrc if it exists
if [ -f .envrc ]; then
    set +e  # Temporarily disable exit on error
    source .envrc 2>/dev/null || true
    set -e  # Re-enable exit on error
fi

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check for API token
if [ -z "$FLY_API_TOKEN" ]; then
    echo -e "${RED}ERROR: FLY_API_TOKEN environment variable is not set${NC}"
    echo ""
    echo "Get your token from: https://fly.io/user/personal_access_tokens"
    echo "Then run: export FLY_API_TOKEN=your_token_here"
    exit 1
fi

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}ReqFly Integration Test Suite${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "${YELLOW}⚠️  WARNING: These tests create real Fly.io resources${NC}"
echo -e "${YELLOW}   They will be cleaned up, but may incur small costs${NC}"
echo ""

# Find all integration test files (sequentially numbered)
TEST_FILES=$(find test/integration -name "[0-9][0-9]_*.exs" | sort)

if [ -z "$TEST_FILES" ]; then
    echo -e "${RED}No integration test files found in test/integration/${NC}"
    exit 1
fi

echo -e "Found integration tests:"
echo "$TEST_FILES" | while read -r file; do
    echo "  • $file"
done
echo ""

# Track results
TOTAL=0
PASSED=0
FAILED=0
FAILED_TESTS=""

# Run each test file sequentially
for TEST_FILE in $TEST_FILES; do
    TOTAL=$((TOTAL + 1))
    TEST_NAME=$(basename "$TEST_FILE")
    
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}Running: ${TEST_NAME}${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    # Run the test
    if mix test "$TEST_FILE" --only integration; then
        PASSED=$((PASSED + 1))
        echo -e "${GREEN}✓ ${TEST_NAME} PASSED${NC}"
    else
        FAILED=$((FAILED + 1))
        FAILED_TESTS="${FAILED_TESTS}\n  • ${TEST_NAME}"
        echo -e "${RED}✗ ${TEST_NAME} FAILED${NC}"
    fi
    
    echo ""
    
    # Small delay between tests to avoid rate limiting
    sleep 2
done

# Summary
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Integration Test Summary${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "Total:  ${TOTAL}"
echo -e "${GREEN}Passed: ${PASSED}${NC}"

if [ $FAILED -gt 0 ]; then
    echo -e "${RED}Failed: ${FAILED}${NC}"
    echo -e "${RED}Failed tests:${FAILED_TESTS}${NC}"
    exit 1
else
    echo -e "${GREEN}All integration tests passed! ✓${NC}"
    exit 0
fi
