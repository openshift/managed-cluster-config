ARTIFACT_DIR="${ARTIFACT_DIR:-/tmp/artifacts}"
[ ! -d "$ARTIFACT_DIR" ] && mkdir -p "$ARTIFACT_DIR"
TEMP_FILE=$(mktemp -p "$ARTIFACT_DIR" broken_links_XXXXXX)
IGNORE_REPOS=(
    "https://github.com/openshift/ops-sop/"
    "https://gitlab.cee.redhat.com/service"
    "https://jira.coreos.com"
    "https://grafana"
)
find . -type f -not -path '*/\.*' -print | while read -r file; do
    grep -shEo "(http|https)://[a-zA-Z0-9./?=_-]*" "$file" | sort -u | while IFS= read -r URL; do
        skip=false
        for repo in "${IGNORE_REPOS[@]}"; do
        if [[ "$URL" == *"$repo"* ]]; then
            skip=true
            break
        fi
        done
        if $skip; then
            continue
        fi
        cleanurl=${URL%.}
        if ! [[ "$cleanurl" =~ ^https?://[^/]+\. ]] ||
        [[ "$cleanurl" == *".svc"* ]] ||
        [[ "$cleanurl" =~ ^(http:\/\/|https:\/\/)?(localhost|127\.0\.0\.1|::1|10\.\d{1,3}\.\d{1,3}\.\d{1,3}|172\.(1[6-9]|2[0-9]|3[0-1])\.\d{1,3}\.\d{1,3}|192\.168\.\d{1,3}\.\d{1,3}) ]]; then
            continue
        fi
        s=$(curl "$cleanurl" --head --silent --write-out '%{response_code}' -o /dev/null)
        if [[ -n "$s" && "$s" == "404" ]]; then
            echo "Path: $file" >> "$TEMP_FILE"
            echo "URL: $URL" >> "$TEMP_FILE"
        fi
    done
done
if [ -s "$TEMP_FILE" ]; then
    echo "Broken links detected:"
    cat "$TEMP_FILE"
    exit 1
else
    echo "No broken links detected."
    exit 0
fi