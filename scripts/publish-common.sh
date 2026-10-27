# Shared steps of scripts/publish.sh (AeroStage and AeroStage WM). Expects REPO, NAME, VERSION,
# ZIP, APP, CASK and a release_build function to be set by the caller.

TAG="v$VERSION"
TAP="${AEROSTAGE_TAP:-../homebrew-tap}"
die() { echo "Error: $*" >&2; exit 1; }

# Checks before anything is changed
command -v gh > /dev/null || die "GitHub CLI missing: brew install gh, then gh auth login"
gh auth status > /dev/null 2>&1 || die "GitHub CLI not logged in: gh auth login"
security find-identity -p codesigning | grep -q '"AeroStage Release"' || die 'certificate "AeroStage Release" missing'
[[ "$(git branch --show-current)" == "dev" ]] || die "switch to dev first"
git diff --quiet && git diff --cached --quiet || die "uncommitted changes"
git fetch -q origin
[[ "$(git rev-parse dev)" == "$(git rev-parse origin/dev)" ]] || die "push dev first"
! git rev-parse -q --verify "refs/tags/$TAG" > /dev/null || die "tag $TAG exists already"
NOTES="$(awk -v v="## $VERSION" '$0 == v {f = 1; next} /^## / {f = 0} f' CHANGELOG.md)"
[[ -n "${NOTES//[[:space:]]/}" ]] || die "CHANGELOG.md has no section \"## $VERSION\""
[[ -d "$TAP/.git" ]] || die "tap not found at $TAP"
[[ -z "$(git -C "$TAP" status --porcelain)" ]] || die "tap has uncommitted changes"

echo "Publishing $NAME $VERSION ($TAG) to $REPO"
echo "$NOTES"
read -r -p "Continue? [y/N] " answer
[[ "$answer" == [yYjJ] ]] || die "cancelled"

# 1. main and tag
git switch -q main
git merge -q --ff-only dev
git tag -a "$TAG" -m "$NAME $VERSION"
git push -q origin main "$TAG"
git switch -q dev

# 2. Signed zip; release.sh also updates the cask in the tap (on its dev branch)
git -C "$TAP" switch -q dev
release_build
codesign -dvv "$APP" 2>&1 | grep -q "Authority=AeroStage Release" || die "$APP is not signed with AeroStage Release"

# 3. GitHub release, once the mirror has brought the tag over
for _ in $(seq 1 60); do
    git ls-remote --tags "https://github.com/$REPO.git" "refs/tags/$TAG" | grep -q . && break
    sleep 2
done
git ls-remote --tags "https://github.com/$REPO.git" "refs/tags/$TAG" | grep -q . || die "tag $TAG did not reach GitHub"
gh release create "$TAG" "$ZIP" --repo "$REPO" --title "$NAME $VERSION" --notes "$NOTES" --verify-tag

# 4. Homebrew cask
git -C "$TAP" add "Casks/$CASK.rb"
git -C "$TAP" commit -q -m "$CASK $VERSION"
git -C "$TAP" switch -q main
git -C "$TAP" merge -q --ff-only dev
git -C "$TAP" push -q origin main dev
git -C "$TAP" switch -q dev

echo "Done: https://github.com/$REPO/releases/tag/$TAG"
echo "Update with: brew update && brew upgrade --cask $CASK"
