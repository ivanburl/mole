#!/usr/bin/env bash

# LOGIN: xburlu00
# FULL NAME: Ivan Burlutskyi

#configurations
EDITOR="${EDITOR:-${VISUAL:-vi}}"
MOLE_RC="${MOLE_RC}"
NSEC_IN_SEC=1000000000
DELIMITER='-'

# [DESCRIPTION]
# returns an error with code 1 and description
error() {
  echo "Error occurred. Description: $1"
  exit 1
}

help() {
  echo "
        DEPENDENCIES: wc, sed, awk, realpath, date
        NOTE: for correct work please set up MOLE_RC and EDITOR value
        mole -h  #get help
        mole [-g GROUP_NAME] [-r] FILE #open file and set the group flag
        mole [-m] [FILTER] [DIRECTORY] #open last edited or opened file in directory, which suits filters
        mole list [-r] [FILTER] [DIRECTORY] # enlist files with their group info (files without group, are signed as '-')
        [FILTER] = [-g GROUP1,GROUP2,...,GROUPN] [-a DATE] [-b DATE] [-d] [-r]
        --g - group flag
        --a - files which were opened or edited from DATE (DATE format YYYY-MM-DD)
        --b - files which were opened or edited before DATE (DATE format YYYY-MM-DD)
        --m - open file by frequency of opening or editing
        --d - filter groups without defined group
        --r - recursively filter directories"
}

# [number1] [number2]
integer_max() {
  if [ "$1" -gt "$2" ]; then
    echo "$1"
  else
    echo "$2"
  fi
}

# args:
# FILE - file to gen absolute path
get_absolute_path()
{
  _absolute_path=$1
  _unrecognised_path=""

  while ! realpath "$_absolute_path" > /dev/null 2>&1; do # send result to null + send stderr to the stdout
    _unrecognised_path="/$(basename "$_absolute_path")$_unrecognised_path"
    _absolute_path="$(dirname "$_absolute_path")"
  done

  _absolute_path="$(realpath "$_absolute_path")$_unrecognised_path"

  echo "$_absolute_path"
}

get_current_time() {
  if [ -z "${BINSLOZKA}" ]; then
      date +%s%N
  else
      # for testing
      date -d "$("${BINSLOZKA}"/testdate)" +%s%N
  fi
}

# args: FILE - file to check
get_edited_file_time() {
  if ! [ -e "$1" ]; then
    error "File $1 does not exist."
  fi

  echo "0"
  #TODO echo $(( $(integer_max "$(stat "$1" -c "%X")" "$(stat "$1" -c "%Y")") * $NSEC_IN_SEC ))
}

#[STRING] #[END_OF_DAY]
date_to_nanoseconds() {

  if [ -z "$(echo "$1" | sed -n '/^[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}$/p')" ]; then
    error "Incorrect date format. Given $1, expected yyyy-mm-dd."
  fi

  _date="$(echo "$1" | tr '-' ' ')"
  awk -v date="$_date" 'BEGIN {print mktime(sprintf("%s 00 00 00", date)) * 1000000000}'
}

#[NANOSECONDS]
nanoseconds_to_date() {
  awk -v nanoseconds="$1" 'BEGIN { seconds = nanoseconds / 1000000000; print strftime("%Y-%m-%d_%H-%M-%S", seconds) }'
}

#[DEPENDENCY]
check_dependency() {
  if [ -z "$(which "$1")" ]; then
    error "$1 was not found on the system. Please install it."
  fi
}

check_mole_dependencies() {
  check_dependency "sed"
  check_dependency "wc"
  check_dependency "realpath"
  check_dependency "date"
  check_dependency "awk"
  check_dependency "stat"
  check_dependency "which"
  check_dependency "mkdir"
  check_dependency "touch"
  check_dependency "whoami"
  check_dependency "$EDITOR"
  check_dependency "dirname"
  check_dependency "basename"
}

check_mole_rc() {
  if ! [ -e "$MOLE_RC" ]; then
    error "Set value MOLE_RC!"
  fi

  if ! [ -f "$MOLE_RC" ]; then
    error "MOLE_RC=$MOLE_RC should be file"
  fi

  if ! [ -w "$MOLE_RC" ]; then
    error "MOLE_RC=$MOLE_RC should be writable file"
  fi

  if ! [ -r "$MOLE_RC" ]; then
    error "MOLE_RC=$MOLE_RC should be readable file"
  fi
}

# [FILE]
create_path_with_file() {
  if ! [ -e "$1" ]; then
    if ! mkdir -p "$(dirname "$1")" || ! touch "$1"; then
      error "Could not create path MOLE_RC=\"$MOLE_RC\"! Try to change MOLE_RC value."
    fi
  fi
}

# [FILE] [GROUP]
open_file_mole_rc() {

  _opened=$(get_current_time)
  if [ -d "$1" ]; then
    open_directory_mole_rc "$1" "$2" "" "" "" ""
  else
    $EDITOR "$1"

    _edited="0"
    if [ -e "$1" ]; then
      _edited=$(get_edited_file_time "$1")
    fi
      write_mole_rc "$(get_absolute_path "$1")" "$2" "$(integer_max "$_opened" "$_edited")"
  fi
}

#[FILE_REG_EXPR] [GROUPS] [N_START_DATE] [N_END_DATE] [EMPTY GROUP]
filter_mole_rc() {
  awk -F"$DELIMITER" \
    -v delimiter="," \
    -v dir_exp="$1" -v groups="$2" \
    -v start_date="$3" -v end_date="$4" \
    -v empty_group="$5" \
    '
    BEGIN {
      split(groups, group_arr, delimiter);
    }
    {
      good = 0;
      if (match($1, dir_exp))
      {
        find_group = 0;

        if (groups=="") { find_group = 1; } else
        {
          for (key in group_arr) {
            if (group_arr[key]!="" && group_arr[key]==$2) { find_group = 1; break; }
          }
        }
        if (empty_group==1 && $2=="") find_group = 1;

        for (i=3;i<=NF && find_group==1;i++)
        {
          if ((start_date=="" || $i+0>=start_date+0) &&
              (end_date=="" || $i+0<=end_date+0))
          {
            good = 1;
            break;
          }
        }
        if (good) print $0
      }
    }' \
    "$MOLE_RC"
}

#[DIRECTORY] [GROUPS] [N_START_DATE] [N_END_DATE] [EMPTY_GROUP] [M_FLAG]
open_directory_mole_rc() {
  _tmp="$(
    filter_mole_rc "$1" "$2" "$3" "$4" "$5" | awk -F"$DELIMITER" \
      -v m_flag="$6" \
      '
    BEGIN {
      file = ""
      group = ""
      max = 0
    }
    {
      if (m_flag==1) {
        if (max < NF) {
          max = NF;
          file=$1;
          group=$2;
        }
      }
      else {
        for (i=3;i<=NF;i++) {
            if ($i+0>max) {
              max = $i+0;
              file=$1;
              group=$2;
            }
        }
      }
    }
    END {
      if (file != "") {
        printf("%s\n%s", file, group);
      }
    }'
  )"

  if [ -z "$_tmp" ]; then
    error "Could not find the file, which suits filters in directory. Use -h for more info."
  fi

  open_file_mole_rc "$(echo "$_tmp" | sed "1q;d")" "$(echo "$_tmp" | sed "2q;d")"
}

# [DIRECTORY] [GROUPS] [START_DATE] [END_DATE] [EMPTY_GROUP]
list_info_mole_rc() {
  filter_mole_rc "$1" "$2" "$3" "$4" "$5" | awk -F"$DELIMITER" \
    '
    function basename(file) {
        sub(".*/", "", file)
        return file
    }

    BEGIN {
      indent = 0
    }
    {
      file_name = basename($1)
      group_name = $2

      if (map[file_name]=="") map[file_name]=group_name; else
      if (group_name!="") map[file_name]=map[file_name] "," group_name;

      indent = (indent+0 < length(file_name)+0 ) ? length(file_name) : indent;
    }
    END {
      for (key in map) {
        to_lower[tolower(key)] = key
      }

      n=asorti(to_lower, sorted)
      for (i=1;i<=n;i++) {
        fmt=sprintf("%%-%ds%%s\n",indent+2)
        key = to_lower[sorted[i]]
        printf(fmt, key ":", map[key]=="" ? "-" : map[key]);
      }
    }
    '
}

# [FILE_NAME_TO_CREATE][DIRECTORIES (should be absolute paths)] [START_DATE] [END_DATE] [RECURSIVE_FLAG]
create_secret_log() {
  awk -F"$DELIMITER" -v OFS=";" \
    -v delimiter="$DELIMITER" -v directories="$2" -v start_date="$3" -v end_date="$4" \
    -v recursive="$5" \
    '
  BEGIN {
    split(directories, directory_arr, delimiter);
    if (directories=="") directory_arr[1]="123";
  }
  {
    for (key in directory_arr)
    {
      if (recursive==0) {
        directory_expr= "^" directory_arr[key] "/[^/]+$"
      } else
      {
        directory_expr = "^" directory_arr[key]
      }
      if (directories == "" || match($1, directory_expr))
      {
        for(i=3;i<=NF;i++)
        {
          if ((start_date == "" || $i+0 >= start_date+0) && (end_date == "" || $i+0 <= end_date+0))
          {
            if (result[$1]=="")
              result[$1]= $i;
            else
              result[$1] = result[$1] ";" $i;
          }
        }
      }
    }
  }
  END {
    for (key in result)
    {
      printf("%s;", key);

      split(result[key], dates, ";");
      asort(dates);

      for (i=1;i<length(dates);i++)
      {
          printf("%s;", strftime("%Y-%m-%d_%H-%M-%S", dates[i]/1000000000));
      }

      printf("%s\n", strftime("%Y-%m-%d_%H-%M-%S", dates[length(dates)]/1000000000));
    }
  }' \
  "$MOLE_RC" | sort -df "-t" ";" "-k1" | bzip2 >"$1"

}

# args:
# FILE - path to the file
# GROUP - group of the file
# DATE - date in nanoseconds
write_mole_rc() {
  _result="$(awk -F"$DELIMITER" -v OFS="$DELIMITER" \
    -v name="$1" -v group="$2" -v date="$3" \
    '
      BEGIN { found = 0; }
      {
        if ($1==name && $2==group) {
          found=1;
          print $0, date
        } else {
          print $0
        }
      }
      END { if (found == 0) print name,group,date }
      ' \
    "$MOLE_RC")"
  echo "$_result" >"$MOLE_RC"
}

################################# READ_OF_ARGS #######################################

#check mole dependencies
check_mole_dependencies

a_flag="" # date type
b_flag="" # date type
h_flag=0  # help flag
g_flag="" # string type (collection fo strings in string)
m_flag=0  # flag to open file which is opened mostly
d_flag=0  # default group flag
r_flag=0  # recursive search flag

list_flag=0       #to list group info
secret_log_flag=0 #to generate secret info

case $1 in
list) list_flag=1 ;;
secret-log) secret_log_flag=1 ;;
esac

if [ "$list_flag" -eq 1 ] || [ "$secret_log_flag" -eq 1 ]; then
  shift
fi

while getopts a:b:g:hmdr flag; do
  case "${flag}" in
  d) d_flag=1 ;;
  r) r_flag=1 ;;
  a) a_flag=$(("$(date_to_nanoseconds "$OPTARG")" + 24*60*60*"$NSEC_IN_SEC"));;
  b) b_flag="$(date_to_nanoseconds "$OPTARG")";;
  h) h_flag=1 ;;
  g) g_flag=$OPTARG ;;
  m) m_flag=1 ;;
  *) error "Unknown option: $OPTARG." ;;
  esac
done

if [ $d_flag -eq 1 ] && [ -z "$g_flag" ]; then
  error "Arguments -g and -d cant be together."
fi

shift "$((OPTIND - 1))"

if [ $h_flag -eq 1 ]; then
  help
  exit 0
fi

#get full path of mole_rc
MOLE_RC=$(get_absolute_path "$MOLE_RC")
#create moler_rc
create_path_with_file "$MOLE_RC"
#check existance fo mole_rc
check_mole_rc


#secret-log processing
if [ $secret_log_flag -eq 1 ]; then

  if [ "$#" -eq 0 ]; then
    directories=""
  else
    directories="$(get_absolute_path "$1")"
    shift
  fi

  while [ "$#" -ne 0 ]; do
    directories="$directories$DELIMITER$(get_absolute_path "$1")"
    shift
  done

  SECRET_LOG="/home/$USER/.mole"
  mkdir -p "$SECRET_LOG"

  create_secret_log "$SECRET_LOG/log_$(whoami)_$(nanoseconds_to_date "$(get_current_time)").bz2" \
    "$directories" "$a_flag" "$b_flag" "$r_flag"

  exit 0
fi

directory="$(get_absolute_path "$PWD")"

if [ "$#" -eq 1 ]; then

  if [ -e "$1" ]; then
    directory="$(get_absolute_path "$1")"
  else
    directory="$1"
  fi

  shift
fi

if [ "$#" -ne 0 ]; then
  error "Incorrect command format. Use -h to get more info."
fi

#list processing
if [ "$list_flag" -eq 1 ]; then
  if [ $r_flag -eq 0 ]; then
    list_info_mole_rc "^$(get_absolute_path "$directory")/[^/]+$" "$g_flag" "$a_flag" "$b_flag" "$d_flag"
  else
    list_info_mole_rc "^$(get_absolute_path "$directory")/" "$g_flag" "$a_flag" "$b_flag" "$d_flag"
  fi
  exit 0
fi
################

if [ -d "$directory" ]; then
  #[DIRECTORY] [GROUPS] [N_START_DATE] [N_END_DATE] [M_FLAG]
  if [ $r_flag -eq 0 ]; then
    open_directory_mole_rc "^$(get_absolute_path "$directory")/[^/]+$" "$g_flag" "$a_flag" "$b_flag" "$d_flag" "$m_flag";
  else
    open_directory_mole_rc "^$(get_absolute_path "$directory")/" "$g_flag" "$a_flag" "$b_flag" "$d_flag" "$m_flag";
  fi
  exit 0
fi

open_file_mole_rc "$directory" "$g_flag"
