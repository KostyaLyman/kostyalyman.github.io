#!/usr/bin/env bash
#
# Build, test and then deploy the site content to 'origin/<pages_branch>'
#
# Requirement: html-proofer, jekyll
#
# Usage: See help information

set -eu

PAGES_BRANCH="gh-pages"

SITE_DIR="_site"

_opt_dry_run=false

_config="_config.yml"

_no_pages_branch=false

# CLI Dependencies
CLI=("git" "npm")

ACTIONS_WORKFLOW=pages-deploy.yml

# temporary file suffixes that make `sed -i` compatible with BSD and Linux
TEMP_SUFFIX="to-delete"

_no_gh=false


_backup_dir="$(mktemp -d)"

_baseurl=""

help() {
  echo "Build, test and then deploy the site content to 'origin/<pages_branch>'"
  echo
  echo "Usage:"
  echo
  echo "   bash ./tools/deploy.sh [options]"
  echo
  echo "Options:"
  echo '     -c, --config   "<config_a[,config_b[...]]>"    Specify config file(s)'
  echo "     --dry-run                Build site and test, but not deploy"
  echo "     -h, --help               Print this information."
}

init() {
  if [[ -z ${GITHUB_ACTION+x} && $_opt_dry_run == 'false' ]]; then
    echo "ERROR: It is not allowed to deploy outside of the GitHub Action envrionment."
    echo "Type option '-h' to see the help information."
    exit -1
  fi

  _baseurl="$(grep '^baseurl:' _config.yml | sed "s/.*: *//;s/['\"]//g;s/#.*//")"
}


# BSD and GNU compatible sed
_sedi() {
  regex=$1
  file=$2
  sed -i.$TEMP_SUFFIX "$regex" "$file"
  rm -f "$file".$TEMP_SUFFIX
}

_check_cli() {
  for i in "${!CLI[@]}"; do
    cli="${CLI[$i]}"
    if ! command -v "$cli" &>/dev/null; then
      echo "Command '$cli' not found! Hint: you should install it."
      exit 1
    fi
  done
}

_check_status() {
  if [[ -n $(git status . -s) ]]; then
    echo "Error: Commit unstaged files first, and then run this tool again."
    exit 1
  fi
}

_check_init() {
  local _has_inited=false

  if [[ ! -d .github ]]; then # using option `--no-gh`
    _has_inited=true
  else
    if [[ -f .github/workflows/$ACTIONS_WORKFLOW ]]; then
      # on BSD, the `wc` could contains blank
      local _count
      _count=$(find .github/workflows/ -type f -name "*.yml" | wc -l)
      if [[ ${_count//[[:blank:]]/} == 1 ]]; then
        _has_inited=true
      fi
    fi
  fi

  if $_has_inited; then
    echo "Already initialized."
    exit 0
  fi
}

check_env() {
  _check_cli
  _check_status
  _check_init
}

checkout_latest_release() {
  hash=$(git log --grep="chore(release):" -1 --pretty="%H")
  git reset --hard "$hash"
}

init_files() {
  if $_no_gh; then
    rm -rf .github
  else
    ## Change the files of `.github`
    mv .github/workflows/$ACTIONS_WORKFLOW.hook .
    rm -rf .github
    mkdir -p .github/workflows
    mv ./${ACTIONS_WORKFLOW}.hook .github/workflows/${ACTIONS_WORKFLOW}

    ## Cleanup image settings in site config
    _sedi "s/^img_cdn:.*/img_cdn:/;s/^avatar:.*/avatar:/" _config.yml
  fi

  # remove the other files
  rm -rf _posts/*

  # build assets
  npm i && npm run build

  # track the js output
  _sedi "/^assets.*\/dist/d" .gitignore
}

build() {
  # clean up
  if [[ -d $SITE_DIR ]]; then
    rm -rf "$SITE_DIR"
  fi
  #  npm i && npm run build
  bundle install
  # build
  JEKYLL_ENV=production bundle exec jekyll b -d "$SITE_DIR$_baseurl" --config "$_config"
}

test() {
  bundle exec htmlproofer \
    --disable-external \
    --check-html \
    --allow_hash_href \
    "$SITE_DIR"
}

resume_site_dir() {
  if [[ -n $_baseurl ]]; then
    # Move the site file to the regular directory '_site'
    mv "$SITE_DIR$_baseurl" "${SITE_DIR}-rename"
    rm -rf "$SITE_DIR"
    mv "${SITE_DIR}-rename" "$SITE_DIR"
  fi
}

setup_gh() {
  if [[ -z $(git branch -av | grep "$PAGES_BRANCH") ]]; then
    _no_pages_branch=true
    git checkout -b "$PAGES_BRANCH"
  else
    git checkout "$PAGES_BRANCH"
  fi
}

backup() {
  mv "$SITE_DIR"/* "$_backup_dir"
  mv .git "$_backup_dir"

  # When adding custom domain from Github website,
  # the CANME only exist on `gh-pages` branch
  if [[ -f CNAME ]]; then
    mv CNAME "$_backup_dir"
  fi
}

flush() {
  rm -rf ./*
  rm -rf .[^.] .??*

  shopt -s dotglob nullglob
  mv "$_backup_dir"/* .
}

deploy() {
  git config --global user.name "GitHub Actions"
  git config --global user.email "41898282+github-actions[bot]@users.noreply.github.com"

  git update-ref -d HEAD
  git add -A
  git commit -m "[Automation] Site update No.${GITHUB_RUN_NUMBER}"

  if $_no_pages_branch; then
    git push -u origin "$PAGES_BRANCH"
  else
    git push -f
  fi
}

main() {
  init
  build
#  test
  resume_site_dir

  if $_opt_dry_run; then
    exit 0
  fi

  setup_gh
  backup
  flush
  deploy
}

while (($#)); do
  opt="$1"
  case $opt in
    -c | --config)
      _config="$2"
      shift
      shift
      ;;
    --dry-run)
      # build & test, but not deploy
      _opt_dry_run=true
      shift
      ;;
    -h | --help)
      help
      exit 0
      ;;
    *)
      # unknown option
      help
      exit 1
      ;;
  esac
done

main
