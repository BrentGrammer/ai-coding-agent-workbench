#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

assert_eq() {
  local name="$1"
  local got="$2"
  local want="$3"
  [ "$got" = "$want" ] || fail "$name: got $got want $want"
}

source_fresh() {
  unset INSTALL_MATT_POCOCK_SKILLS INSTALL_SKILL_CREATOR INSTALL_NO_MISTAKES
  unset INSTALL_EXA INSTALL_GH INSTALL_GH_AXI INSTALL_NPM_AXI
  unset OPTIONAL_SKILL_OR_TOOL_FLAG_WAS_PASSED INSTALL_ANY_SKILL INSTALL_ANY_GH_TOOL
  # shellcheck source=optional_skills_and_tools.sh
  source "$SCRIPT_DIR/optional_skills_and_tools.sh"
}

source_fresh
remember_if_any_skill_or_gh_tool_is_on
assert_eq "no flags: matt pocock" "$INSTALL_MATT_POCOCK_SKILLS" true
assert_eq "no flags: skill-creator" "$INSTALL_SKILL_CREATOR" true
assert_eq "no flags: no-mistakes" "$INSTALL_NO_MISTAKES" true
assert_eq "no flags: exa" "$INSTALL_EXA" true
assert_eq "no flags: gh" "$INSTALL_GH" true
assert_eq "no flags: gh-axi" "$INSTALL_GH_AXI" true
assert_eq "no flags: npm-axi" "$INSTALL_NPM_AXI" true
assert_eq "no flags: any skill" "$INSTALL_ANY_SKILL" true
assert_eq "no flags: any gh tool" "$INSTALL_ANY_GH_TOOL" true

source_fresh
turn_on_optional_skill_or_tool --exa
remember_if_any_skill_or_gh_tool_is_on
assert_eq "--exa: exa" "$INSTALL_EXA" true
assert_eq "--exa: matt pocock" "$INSTALL_MATT_POCOCK_SKILLS" false
assert_eq "--exa: skill-creator" "$INSTALL_SKILL_CREATOR" false
assert_eq "--exa: no-mistakes" "$INSTALL_NO_MISTAKES" false
assert_eq "--exa: gh" "$INSTALL_GH" false
assert_eq "--exa: gh-axi" "$INSTALL_GH_AXI" false
assert_eq "--exa: npm-axi" "$INSTALL_NPM_AXI" false
assert_eq "--exa: any skill" "$INSTALL_ANY_SKILL" false
assert_eq "--exa: any gh tool" "$INSTALL_ANY_GH_TOOL" false

source_fresh
turn_on_optional_skill_or_tool --exa
turn_on_optional_skill_or_tool --gh
remember_if_any_skill_or_gh_tool_is_on
assert_eq "--exa --gh: exa" "$INSTALL_EXA" true
assert_eq "--exa --gh: gh" "$INSTALL_GH" true
assert_eq "--exa --gh: matt pocock" "$INSTALL_MATT_POCOCK_SKILLS" false
assert_eq "--exa --gh: gh-axi" "$INSTALL_GH_AXI" false

source_fresh
turn_on_optional_skill_or_tool --full
remember_if_any_skill_or_gh_tool_is_on
assert_eq "--full: exa" "$INSTALL_EXA" true
assert_eq "--full: npm-axi" "$INSTALL_NPM_AXI" true
assert_eq "--full: any skill" "$INSTALL_ANY_SKILL" true

echo "ok"
