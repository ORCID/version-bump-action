#!/bin/bash
#set -x

# TODO: we could not rely on a git checkout by doing at least a remote tag listing using the token and a https url

#
# defaults
#

set -o errexit -o errtrace -o nounset -o functrace -o pipefail
shopt -s inherit_errexit 2>/dev/null || true

trap 'echo "exit_code $? line $LINENO linecallfunc $BASH_COMMAND"' ERR

prefix_search_arg="v"
prefix='v'
do_tag=0
tag=${GHA_TAG:-latest}
USER=$(whoami)
bump=${GHA_BUMP:-patch}
major=0
minor=0
patch=0
git_log_from=${GHA_GIT_LOG_FROM:-second_merge}

#
# functions
#

NAME=version_bump.sh

usage(){
I_USAGE="

  Usage:  ${NAME} [OPTIONS]

  Description:
    Lookup the latest semver tag of a git checkout and optionally bump it

    Bump calculation, default is patch but the recent git logs are checked for #minor #major commits to override this.
    Also the git branch name is checked for feat/ or fix/ equivilants to get a bump that is higher than patch.

    In some cases we may want to keep the value so we use a bump of 'none' . In some cases we might want to specify a version as well
    rather than using git tags or any bumping, so setting a specific tag and not 'latest' will just return that value.

  Github actions inputs:

    To handle running this script via github actions where it can be called from a dispatch, or a commit trigger
    The version is fed in through an environment variable, GHA_TAG which can be optional (unlike an argument to the script)

  Requirements:

    This script needs to be run in a git checkout directory. For github actions this is done using the actions/checkout step before

  Options:
      -p | --prefix       ) set the version prefix ($prefix) and search based on this
      -d | --do_tag       ) perform tagging of the repo
      -t | --tag          ) provide a tag
      -b | --bump         ) bump either none patch|minor|major or ($bump) using the a #minor #major git commit message default patch
      -l | --git_log_from ) where from the git log history to look from when considering in #minor #major messages ($git_log_from)
                            options are: numeric (number of lines) , last_tag , second_merge (github actions triggers after a merge)
"
  echo "$I_USAGE"
  exit
}


#
# args
#

while :
do
  case ${1-default} in
      --*help|-h          ) usage ; exit 0 ;;
      --man               ) usage ; exit 0 ;;
      -v | --verbose      ) VERBOSE=$(($VERBOSE+1)) ; shift ;;
      --debug             ) DEBUG=1; [ "$VERBOSE" == "0" ] && VERBOSE=1 ; shift;;
      --dry-run           ) dry_run=1 ; shift ;;
      -p | --prefix       ) prefix=$2 ; prefix_search_arg="$2" ;shift 2 ;;
      -d | --do_tag       ) do_tag=1 ;shift ;;
      -t | --tag       ) tag=$2 ;shift 2 ;;
      -b | --bump       ) bump=$2 ;shift 2 ;;
      -l | --git_log_from ) git_log_from=$2 ;shift 2 ;;
      --) shift ; break ;;
      -*) echo "WARN: Unknown option (ignored): $1" >&2 ; shift ;;
      *)  break ;;
    esac
done

# handle running locally
GITHUB_OUTPUT=${GITHUB_OUTPUT:-/tmp/$NAME.$USER}

#
# main
#
#set -x

echo "git -c 'versionsort.suffix=-' ls-remote --exit-code --refs --sort='version:refname' --tags origin '*.*.*' | grep \"$prefix_search_arg\" | tail -n1 | cut -d '/' -f 3"
version=`git -c 'versionsort.suffix=-' ls-remote --exit-code --refs --sort='version:refname' --tags origin '*.*.*' | grep "$prefix_search_arg" | tail -n1 | cut -d '/' -f 3`
version_numeric="$(echo $version | tr -dc '[:digit:].')"
echo "version: $version"
echo "version_numeric: $version_numeric"

# option that just returns the provided values
if [[ "$tag" != 'latest' ]];then
  echo "tag specified: $tag"

  echo "version_last=${version}" >> "$GITHUB_OUTPUT" 2>/dev/null
  echo "version_last_numeric=${version_numeric}" >> "$GITHUB_OUTPUT" 2>/dev/null

  echo "version_tag=${tag}" >> "$GITHUB_OUTPUT" 2>/dev/null
  tag_numeric="$(echo $tag | tr -dc '[:digit:].')"
  echo "tag numeric: $tag_numeric"
  echo "version_tag_numeric=${tag_numeric}" >> "$GITHUB_OUTPUT" 2>/dev/null
  exit
fi


# replace . with space so can split into an array
version_bits=(${version_numeric//./ })

# get number parts and increase last one by 1
vnum1=${version_bits[0]}
vnum2=${version_bits[1]}
vnum3=${version_bits[2]}

# take bumping from arguments

if [[ "$bump" = 'major' ]];then
  major=1
fi
if [[ "$bump" = 'minor' ]];then
  minor=1
fi
if [[ "$bump" = 'patch' ]];then
  patch=1
fi

re='^[0-9]+$'
if [[ "$git_log_from" =~ $re ]];then
  echo "line source selected of $git_log_from lines as source for commits_for_bump"
  commits_for_bump=$(git log --oneline -n $git_log_from)
fi

if [[ "$git_log_from" = 'last_tag' ]];then
  # NOTE: git fetch tags for 1000+ tags is very slow
  echo "fetching tags to look for bump commits"
  git fetch --tags origin
  commits_for_bump=$(git log $version..HEAD --oneline)
fi

if [[ "$git_log_from" = 'second_merge' ]];then
  echo "looking for commits since the second_merge"
  second_merge_id=$(git log --merges --oneline --grep='^Merge' -n 2 | tail -n 1 | awk '{print $1}')
  echo "git log $second_merge_id..HEAD --oneline"
  commits_for_bump=$(git log $second_merge_id..HEAD --oneline)
fi

# Allow git commit messages to override bump value
# Check for #major or #minor in commit message and increment the relevant version number

merge_commit=$(git log --merges -n 1)

echo "commits_for_bump:"
echo "$commits_for_bump"
echo " "
echo "----------------------------------------------"
echo " "
echo "merge_commit:"
echo "$merge_commit"

if grep -qE 'feat' <<< $(echo $merge_commit);then
  echo "feature git commit detected"
  minor=1
fi

if grep -qE 'fix|bug|patch|test' <<< $(echo $merge_commit);then
  echo "fix|bug|patch|test git commit detected"
  patch=1
fi

if grep -q '#major' <<< $(echo $commits_for_bump) ;then
  echo "major git commit detected"
  major=1
fi
if grep -q '#minor' <<< $(echo $commits_for_bump) ;then
  echo "minor git commit detected"
  minor=1
fi
if grep -q '#patch' <<< $(echo $commits_for_bump) ;then
  echo "patch git commit detected"
  patch=1
fi



#
# perform version bumping
#

if [[ "$bump" != 'none' ]];then
  echo "bump !=none so performing version bump"

  if [[ "$major" -eq 1 ]]; then
      echo "Update major version"
      vnum1=$((vnum1+1))
      vnum2=0
      vnum3=0
  elif [[ "$minor" -eq 1 ]]; then
      echo "Update minor version"
      vnum2=$((vnum2+1))
      vnum3=0
  elif [[ "$patch" -eq 1 ]]; then
      echo "Update patch version"
      vnum3=$((vnum3+1))
  fi
fi

# create new tag
new_tag="$prefix$vnum1.$vnum2.$vnum3"

echo "Updating $version to $new_tag"

# get current hash and see if it already has a tag
git_commit=`git rev-parse HEAD`

echo "git_commit=$git_commit"

# only tag if no tag already (would be better if the git describe command above could have a silent option)
if $(git describe --contains $git_commit); then

  echo "Already a tag on this commit"

else

  if [[ "$do_tag" -eq 1 ]];then
    echo "Tagged with $new_tag (Ignoring fatal:cannot describe - this means commit is untagged) "
    git tag $new_tag
    git push origin $new_tag
  else
    echo "Would tag with $new_tag if do_tag flag was set"
  fi

fi

new_tag_numeric="$(echo $new_tag | tr -dc '[:digit:].')"

echo "version_tag=${new_tag}" >> "$GITHUB_OUTPUT" 2>/dev/null
echo "version_tag_numeric=${new_tag_numeric}" >> "$GITHUB_OUTPUT" 2>/dev/null

