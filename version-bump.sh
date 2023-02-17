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
tag=${GHA_TAG:-next_tag}
USER=$(whoami)
bump=git_log
major=0
minor=0

#
# functions
#

NAME=version_bump.sh

usage(){
I_USAGE="

  Usage:  ${NAME} [OPTIONS]

  Description:
    Lookup the latest git tag in the current repo and based on the bump value increase it
    Set this as a github output to use in an action
    If a tag is provided just return that tag as an output. (This allows us to have a standard github variable name)

  Github actions inputs:

    To handle running this script via github actions where it can be called from a dispatch, or a commit trigger
    The version is fed in through an environment variable, GHA_TAG which can be optional (unlike an argument to the script)

  Options:
      -p | --prefix       ) set the version prefix ($prefix) and search based on this
      -d | --do_tag       ) perform tagging of the repo
      -t | --tag          ) provide a tag
      -b | --bump         ) bump either patch|minor|major or ($bump) using the a #minor #major git commit message default patch
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

if [[ "$tag" != 'next_tag' ]];then
  echo "tag specified: $tag"
  echo "version_tag=${tag}" >> "$GITHUB_OUTPUT"
  exit
fi

echo "git -c 'versionsort.suffix=-' ls-remote --exit-code --refs --sort='version:refname' --tags origin '*.*.*' | grep \"$prefix_search_arg\" | tail -n1 | cut -d '/' -f 3"
version=`git -c 'versionsort.suffix=-' ls-remote --exit-code --refs --sort='version:refname' --tags origin '*.*.*' | grep "$prefix_search_arg" | tail -n1 | cut -d '/' -f 3`

echo "version:$version"

# replace . with space so can split into an array
version_bits=(${version//./ })

# get number parts and increase last one by 1
vnum1=${version_bits[0]}
vnum2=${version_bits[1]}
vnum3=${version_bits[2]}
vnum1=`echo $vnum1 | sed 's/v//'`

if [[ "$bump" = 'git_log' ]];then
  # Check for #major or #minor in commit message and increment the relevant version number
  if git log --format=%B -n 1 HEAD | grep -q '#major';then
    echo "major git commit detected"
    major=1
  fi
  if git log --format=%B -n 1 HEAD | grep '#minor';then
    echo "minor git commit detected"
    minor=1
  fi
else
  if [[ "$bump" = 'major' ]];then
    major=1
  fi
  if [[ "$bump" = 'minor' ]];then
    minor=1
  fi
fi

if [[ "$major" -eq 1 ]]; then
    echo "Update major version"
    vnum1=$((vnum1+1))
    vnum2=0
    vnum3=0
elif [[ "$minor" -eq 1 ]]; then
    echo "Update minor version"
    vnum2=$((vnum2+1))
    vnum3=0
else
    echo "Update patch version"
    vnum3=$((vnum3+1))
fi

# create new tag
new_tag="$prefix$vnum1.$vnum2.$vnum3"

echo "Updating $version to $new_tag"

# get current hash and see if it already has a tag
git_commit=`git rev-parse HEAD`

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

new_tag_no_v=$(echo $new_tag | tr -d 'v')

echo "version_tag=${new_tag}" >> "$GITHUB_OUTPUT" 2>/dev/null
echo "version_tag_no_v=${new_tag_no_v}" >> "$GITHUB_OUTPUT" 2>/dev/null

