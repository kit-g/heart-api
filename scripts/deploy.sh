ENV=$1
CONFIG=$2
TEMPLATE=$3

PROFILE="personal"


clean() {
  TEMP_DIR=".aws-sam"
  if [ -d "$TEMP_DIR" ]; then
    rm -r "$TEMP_DIR"
  fi
}

build() {
  sam build \
    --skip-pull-image \
    --parallel \
    -t "$TEMPLATE"
}

deploy() {
  sam deploy \
    --no-confirm-changeset \
    --config-env "$ENV" \
    --config-file "$CONFIG" \
    --profile "$PROFILE"
}

# clean
if build; then
  deploy
fi
